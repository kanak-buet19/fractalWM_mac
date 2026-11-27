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
        self.root = Self.normalized(Self.placing(new, at: edge, of: best.id, in: root, share: .halveTarget))
    }

    /// Docks `window` on `edge` of the node `target`. A window already in the tree is moved.
    /// Along the parent's axis the newcomer gets an equal share (1/(n+1)); across it, the target is
    /// wrapped 50/50. Docking on the root's edge makes the window span that whole side of the display.
    public mutating func dock(_ window: WindowID, at edge: Edge, of target: NodeID) {
        guard var root, Self.find(target, in: root) != nil else { return }
        if let stack = stack(containing: window), stack.id == target, stack.windows.count == 1 {
            return // docking a lone window next to itself changes nothing
        }
        root = Self.removing(window, from: root)
        let new = Node.stack(Stack(windows: [window]))
        self.root = Self.normalized(Self.placing(new, at: edge, of: target, in: root, share: .equal))
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

    /// How a newcomer takes space from siblings along the same axis.
    enum Share {
        /// The newcomer gets 1/(n+1) of the split; the others scale by n/(n+1). Used by `dock` (user drops).
        case equal
        /// The newcomer takes half of the target's share. Used by `insert` (automatic placement).
        case halveTarget
    }

    /// Inserts `new` beside `target`. If the target's parent already runs along the edge's axis, the
    /// new node becomes a sibling; otherwise the target is wrapped in a new 50/50 split.
    static func placing(_ new: Node, at edge: Edge, of target: NodeID, in node: Node, share: Share) -> Node {
        if node.id == target {
            // Docking on the edge of a split that already runs this way: join it rather than wrap it.
            if share == .equal, case .split(var split) = node, split.axis == edge.axis {
                insertEqually(new, into: &split, at: edge.isLeading ? 0 : split.children.count)
                return .split(split)
            }
            let children = edge.isLeading ? [new, node] : [node, new]
            return .split(Split(axis: edge.axis, children: children))
        }
        guard case .split(var split) = node else { return node }
        if split.axis == edge.axis, let i = split.children.firstIndex(where: { $0.id == target }) {
            let at = edge.isLeading ? i : i + 1
            switch share {
            case .equal:
                insertEqually(new, into: &split, at: at)
            case .halveTarget:
                let half = split.weights[i] / 2
                split.weights[i] = half
                split.children.insert(new, at: at)
                split.weights.insert(half, at: at)
            }
            return .split(split)
        }
        split.children = split.children.map { placing(new, at: edge, of: target, in: $0, share: share) }
        return .split(split)
    }

    static func insertEqually(_ new: Node, into split: inout Split, at index: Int) {
        let n = Double(split.children.count)
        var fractions = split.fractions.map { $0 * n / (n + 1) }
        fractions.insert(1 / (n + 1), at: index)
        split.children.insert(new, at: index)
        split.weights = fractions
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

    /// Canonical form:
    /// - empty stacks and splits are dropped, and a vanished child's whole share goes to its next surviving
    ///   sibling (or the previous one if it was last), so one neighbor grows instead of everyone shifting;
    /// - a child split running along its parent's axis is flattened into the parent, keeping geometry;
    /// - a single-child split is replaced by its child.
    static func normalized(_ node: Node) -> Node? {
        switch node {
        case .stack(let stack):
            return stack.windows.isEmpty ? nil : node
        case .split(var split):
            let results = split.children.map(normalized)
            var weights = split.weights.map { $0.isFinite && $0 > 0 ? $0 : 0.001 }

            for (i, result) in results.enumerated() where result == nil {
                let next = (i + 1..<results.count).first { results[$0] != nil }
                let previous = (0..<i).last { results[$0] != nil }
                if let heir = next ?? previous { weights[heir] += weights[i] }
            }

            var children: [Node] = []
            var kept: [Double] = []
            for (i, result) in results.enumerated() {
                guard let child = result else { continue }
                if case .split(let inner) = child, inner.axis == split.axis {
                    for (grandchild, fraction) in zip(inner.children, inner.fractions) {
                        children.append(grandchild)
                        kept.append(weights[i] * fraction)
                    }
                } else {
                    children.append(child)
                    kept.append(weights[i])
                }
            }
            if children.isEmpty { return nil }
            if children.count == 1 { return children[0] }
            split.children = children
            split.weights = kept
            return .split(split)
        }
    }
}
