import CoreGraphics

/// Temporary tiling for milestone 1: lays `count` windows out in a near-square grid.
/// Replaced by the layout tree and layout engine in milestone 2.
public enum SimpleGrid {
    public static func frames(count: Int, in area: CGRect, gap: CGFloat = 8) -> [CGRect] {
        guard count > 0 else { return [] }
        let columns = Int(Double(count).squareRoot().rounded(.up))
        let rows = Int((Double(count) / Double(columns)).rounded(.up))

        let cellWidth = (area.width - gap * CGFloat(columns + 1)) / CGFloat(columns)
        let cellHeight = (area.height - gap * CGFloat(rows + 1)) / CGFloat(rows)

        return (0..<count).map { index in
            let column = index % columns
            let row = index / columns
            // Row 0 is the top row; AppKit's y grows upward, so count down from maxY.
            let x = area.minX + gap + CGFloat(column) * (cellWidth + gap)
            let y = area.maxY - gap - CGFloat(row + 1) * cellHeight - CGFloat(row) * gap
            return CGRect(x: x, y: y, width: cellWidth, height: cellHeight)
        }
    }
}
