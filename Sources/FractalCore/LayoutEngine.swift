import CoreGraphics

/// A draggable gap between two siblings of a split.
public struct Seam: Equatable, Sendable {
    public let split: NodeID
    /// The seam sits between child `index` and `index + 1`.
    public let index: Int
    public let axis: Axis
    public let rect: CGRect
    /// The split's length along its axis, minus gaps. Divide a drag distance by this to get the
    /// `delta` for `LayoutTree.resizeSeam`.
    public let length: CGFloat
}

public struct Layout: Equatable, Sendable {
    /// A frame for every window. Windows in the same stack share their stack's frame.
    public var frames: [WindowID: CGRect] = [:]
    /// The active window of each stack: the windows that should be on screen.
    public var visible: Set<WindowID> = []
    public var seams: [Seam] = []
}

/// Turns a layout tree and a display area into window frames. Pure; no AppKit.
///
/// Coordinates are AppKit's: origin bottom-left, y grows upward. Frames are rounded to whole points,
/// and neighbors share exact edges, so there are no 1-point gaps or overlaps from rounding.
public enum LayoutEngine {
    public static func layout(_ tree: LayoutTree, in bounds: CGRect, gap: CGFloat = 8) -> Layout {
        var result = Layout()
        guard let root = tree.root else { return result }
        place(root, in: bounds.insetBy(dx: gap, dy: gap), gap: gap, into: &result)
        return result
    }

    private static func place(_ node: Node, in rect: CGRect, gap: CGFloat, into result: inout Layout) {
        switch node {
        case .stack(let stack):
            for window in stack.windows { result.frames[window] = rect }
            if let active = stack.activeWindow { result.visible.insert(active) }

        case .split(let split):
            let count = split.children.count
            let horizontal = split.axis == .horizontal
            let length = horizontal ? rect.width : rect.height
            let available = max(0, length - gap * CGFloat(count - 1))

            // Leading and trailing offset of each child along the axis, from the leading edge.
            var spans: [(start: CGFloat, end: CGFloat)] = []
            var cumulative = 0.0
            for (i, fraction) in split.fractions.enumerated() {
                let start = CGFloat(cumulative) * available + CGFloat(i) * gap
                cumulative += fraction
                let end = CGFloat(cumulative) * available + CGFloat(i) * gap
                spans.append((start, end))
            }

            func childRect(_ span: (start: CGFloat, end: CGFloat)) -> CGRect {
                if horizontal {
                    let minX = (rect.minX + span.start).rounded()
                    let maxX = (rect.minX + span.end).rounded()
                    return CGRect(x: minX, y: rect.minY, width: maxX - minX, height: rect.height)
                } else {
                    // First child on top: offsets run downward from maxY.
                    let maxY = (rect.maxY - span.start).rounded()
                    let minY = (rect.maxY - span.end).rounded()
                    return CGRect(x: rect.minX, y: minY, width: rect.width, height: maxY - minY)
                }
            }

            let rects = spans.map(childRect)
            for (child, childRect) in zip(split.children, rects) {
                place(child, in: childRect, gap: gap, into: &result)
            }

            for i in 0..<(count - 1) {
                let a = rects[i], b = rects[i + 1]
                let seamRect = horizontal
                    ? CGRect(x: a.maxX, y: rect.minY, width: b.minX - a.maxX, height: rect.height)
                    : CGRect(x: rect.minX, y: b.maxY, width: rect.width, height: a.minY - b.maxY)
                result.seams.append(
                    Seam(split: split.id, index: i, axis: split.axis, rect: seamRect, length: available)
                )
            }
        }
    }
}
