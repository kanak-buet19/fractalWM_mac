import CoreGraphics
import Foundation

/// Stable identifier for a node in the layout tree.
public struct NodeID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let raw: UUID
    public init() { raw = UUID() }
    public var description: String { "n" + raw.uuidString.prefix(4) }
}

public enum Axis: String, Codable, Sendable {
    /// Children side by side, first child on the left.
    case horizontal
    /// Children stacked, first child on top.
    case vertical
}

public enum Edge: String, Codable, Sendable, CaseIterable {
    case left, right, top, bottom

    var axis: Axis { self == .left || self == .right ? .horizontal : .vertical }
    /// True when a node docked on this edge goes before the target in child order.
    var isLeading: Bool { self == .left || self == .top }
}

/// A tab group: several windows sharing one frame, one of them active (visible).
/// A plain docked window is a one-window stack.
public struct Stack: Equatable, Codable, Sendable {
    public var id: NodeID
    public var windows: [WindowID]
    public var active: Int

    public init(windows: [WindowID], active: Int = 0, id: NodeID = NodeID()) {
        self.id = id
        self.windows = windows
        self.active = active
    }

    public var activeWindow: WindowID? { windows.indices.contains(active) ? windows[active] : nil }

    mutating func remove(_ window: WindowID) {
        guard let index = windows.firstIndex(of: window) else { return }
        windows.remove(at: index)
        if index < active || active >= windows.count { active = max(0, active - 1) }
    }
}

/// Children laid out along one axis. `weights` are relative sizes (any positive scale).
public struct Split: Equatable, Codable, Sendable {
    public var id: NodeID
    public var axis: Axis
    public var children: [Node]
    public var weights: [Double]

    public init(axis: Axis, children: [Node], weights: [Double]? = nil, id: NodeID = NodeID()) {
        self.id = id
        self.axis = axis
        self.children = children
        self.weights = weights ?? Array(repeating: 1, count: children.count)
    }

    /// Weights scaled to sum to 1.
    public var fractions: [Double] {
        let total = weights.reduce(0, +)
        guard total > 0 else { return weights.map { _ in 1 / Double(max(weights.count, 1)) } }
        return weights.map { $0 / total }
    }
}

public enum Node: Equatable, Codable, Sendable {
    case split(Split)
    case stack(Stack)

    public var id: NodeID {
        switch self {
        case .split(let split): split.id
        case .stack(let stack): stack.id
        }
    }

    /// Every window under this node, in tree order.
    public var windows: [WindowID] { stacks.flatMap(\.windows) }

    /// Every stack under this node, in tree order.
    public var stacks: [Stack] {
        switch self {
        case .stack(let stack): [stack]
        case .split(let split): split.children.flatMap(\.stacks)
        }
    }

    /// Compact text form for tests and debugging, e.g. `H(1 | V(2 / 3,4*))`.
    /// `H(a | b)` is a horizontal split, `V(a / b)` a vertical one, and `3,4*` a stack whose active tab is 4.
    public var summary: String {
        switch self {
        case .stack(let stack):
            let names = stack.windows.map { String($0.raw) }
            if names.count <= 1 { return names.first ?? "∅" }
            return names.enumerated().map { $0.offset == stack.active ? $0.element + "*" : $0.element }
                .joined(separator: ",")
        case .split(let split):
            let separator = split.axis == .horizontal ? " | " : " / "
            let prefix = split.axis == .horizontal ? "H(" : "V("
            return prefix + split.children.map(\.summary).joined(separator: separator) + ")"
        }
    }
}

/// The whole arrangement of one display. A pure value: every edit returns a normalized tree.
public struct LayoutTree: Equatable, Codable, Sendable {
    public private(set) var root: Node?

    /// No child of a split can be resized below this share of the split.
    public static let minimumFraction = 0.05

    public init(root: Node? = nil) {
        self.root = root.flatMap(Self.normalized)
    }

    // MARK: Queries

    public var windows: [WindowID] { root?.windows ?? [] }
    public var summary: String { root?.summary ?? "∅" }

    public func contains(_ window: WindowID) -> Bool { windows.contains(window) }

    public func stack(containing window: WindowID) -> Stack? {
        root?.stacks.first { $0.windows.contains(window) }
    }

    public func node(_ id: NodeID) -> Node? {
        guard let root else { return nil }
        return Self.find(id, in: root)
    }

    // MARK: Edits

    /// Adds a window by splitting the largest stack along its longer side (ties go to the first in
    /// tree order). `bounds` is the display area, so "longer side" matches what the user sees.
    public mutating func insert(
        _ window: WindowID, bounds: CGRect = CGRect(x: 0, y: 0, width: 1600, height: 1000)
    ) {
        guard !contains(window) else { return }
        let new = Node.stack(Stack(windows: [window]))
        guard let root else {
            self.root = new
            return
        }

        let layout = LayoutEngine.layout(self, in: bounds, gap: 0)
        var best: (id: NodeID, rect: CGRect)?
        for stack in root.stacks {
            guard let first = stack.windows.first, let rect = layout.frames[first] else { continue }
            let area = rect.width * rect.height
            if best == nil || area > best!.rect.width * best!.rect.height + 0.5 {
                best = (stack.id, rect)
            }
        }
        guard let best else { return }
        let edge: Edge = best.rect.width >= best.rect.height ? .right : .bottom
        self.root = Self.normalized(Self.placing(new, at: edge, of: best.id, in: root))
    }

    /// Docks `window` on `edge` of the node `target`. A window already in the tree is moved.
    /// Docking on the root's edge makes the window span that whole side of the display.
    public mutating func dock(_ window: WindowID, at edge: Edge, of target: NodeID) {
        guard var root, Self.find(target, in: root) != nil else { return }
        if let stack = stack(containing: window), stack.id == target, stack.windows.count == 1 {
            return // docking a lone window next to itself changes nothing
        }
        root = Self.removing(window, from: root)
        let new = Node.stack(Stack(windows: [window]))
        self.root = Self.normalized(Self.placing(new, at: edge, of: target, in: root))
    }

    /// Moves `window` into the stack `target` as a new tab and makes it active.
    public mutating func addTab(_ window: WindowID, to target: NodeID) {
        guard var root, case .stack? = Self.find(target, in: root) else { return }
        root = Self.removing(window, from: root)
        self.root = Self.normalized(Self.updatingStack(target, in: root) { stack in
            stack.windows.append(window)
            stack.active = stack.windows.count - 1
        })
    }

    /// Makes `window` the active tab of its stack.
    public mutating func activate(_ window: WindowID) {
        guard let root, let stack = stack(containing: window),
              let index = stack.windows.firstIndex(of: window) else { return }
        self.root = Self.updatingStack(stack.id, in: root) { $0.active = index }
    }

    /// Removes `window`. Empty stacks disappear and single-child splits collapse.
    public mutating func remove(_ window: WindowID) {
        guard let root else { return }
        self.root = Self.normalized(Self.removing(window, from: root))
    }

    /// Moves the seam between child `index` and `index + 1` of split `splitID`. `delta` is a share of
    /// the split's length; positive grows the leading child (left or top). Both children keep at
    /// least `minimumFraction`.
    public mutating func resizeSeam(in splitID: NodeID, after index: Int, by delta: Double) {
        guard let root else { return }
        self.root = Self.updatingSplit(splitID, in: root) { split in
            guard index >= 0, index + 1 < split.children.count else { return }
            var fractions = split.fractions
            let pair = fractions[index] + fractions[index + 1]
            let minimum = Self.minimumFraction
            guard pair >= 2 * minimum else { return }
            let leading = min(max(fractions[index] + delta, minimum), pair - minimum)
            fractions[index] = leading
            fractions[index + 1] = pair - leading
            split.weights = fractions
        }
    }

    // MARK: Tree helpers

    static func find(_ id: NodeID, in node: Node) -> Node? {
        if node.id == id { return node }
        guard case .split(let split) = node else { return nil }
        for child in split.children {
            if let found = find(id, in: child) { return found }
        }
        return nil
    }

    /// Inserts `new` beside `target`. If the target's parent already runs along the edge's axis, the
    /// new node becomes a sibling that takes half the target's share; otherwise the target is wrapped
    /// in a new split.
    static func placing(_ new: Node, at edge: Edge, of target: NodeID, in node: Node) -> Node {
        if node.id == target {
            let children = edge.isLeading ? [new, node] : [node, new]
            return .split(Split(axis: edge.axis, children: children))
        }
        guard case .split(var split) = node else { return node }
        if split.axis == edge.axis, let i = split.children.firstIndex(where: { $0.id == target }) {
            let half = split.weights[i] / 2
            split.weights[i] = half
            let at = edge.isLeading ? i : i + 1
            split.children.insert(new, at: at)
            split.weights.insert(half, at: at)
            return .split(split)
        }
        split.children = split.children.map { placing(new, at: edge, of: target, in: $0) }
        return .split(split)
    }

    /// Takes `window` out of its stack without normalizing (so node IDs stay put).
    static func removing(_ window: WindowID, from node: Node) -> Node {
        switch node {
        case .stack(var stack):
            stack.remove(window)
            return .stack(stack)
        case .split(var split):
            split.children = split.children.map { removing(window, from: $0) }
            return .split(split)
        }
    }

    static func updatingStack(_ id: NodeID, in node: Node, _ change: (inout Stack) -> Void) -> Node {
        switch node {
        case .stack(var stack):
            if stack.id == id { change(&stack) }
            return .stack(stack)
        case .split(var split):
            split.children = split.children.map { updatingStack(id, in: $0, change) }
            return .split(split)
        }
    }

    static func updatingSplit(_ id: NodeID, in node: Node, _ change: (inout Split) -> Void) -> Node {
        guard case .split(var split) = node else { return node }
        if split.id == id { change(&split) }
        split.children = split.children.map { updatingSplit(id, in: $0, change) }
        return .split(split)
    }

    /// Drops empty stacks and splits, and replaces single-child splits with their child.
    static func normalized(_ node: Node) -> Node? {
        switch node {
        case .stack(let stack):
            return stack.windows.isEmpty ? nil : node
        case .split(var split):
            var children: [Node] = []
            var weights: [Double] = []
            for (child, weight) in zip(split.children, split.weights) {
                if let kept = normalized(child) {
                    children.append(kept)
                    weights.append(weight)
                }
            }
            if children.isEmpty { return nil }
            if children.count == 1 { return children[0] }
            split.children = children
            split.weights = weights
            return .split(split)
        }
    }
}
