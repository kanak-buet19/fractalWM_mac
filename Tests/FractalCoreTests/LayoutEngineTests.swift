import CoreGraphics
import Testing
@testable import FractalCore

private func w(_ n: Int) -> WindowID { WindowID(n) }
private func stack(_ n: Int...) -> Node { .stack(Stack(windows: n.map(w))) }

@Suite struct LayoutEngineTests {
    @Test func emptyTreeHasNoFrames() {
        let layout = LayoutEngine.layout(LayoutTree(), in: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(layout.frames.isEmpty)
        #expect(layout.seams.isEmpty)
    }

    @Test func singleStackFillsBoundsInsetByGap() {
        let tree = LayoutTree(root: stack(1))
        let layout = LayoutEngine.layout(tree, in: CGRect(x: 0, y: 0, width: 1000, height: 500), gap: 10)
        #expect(layout.frames[w(1)] == CGRect(x: 10, y: 10, width: 980, height: 480))
        #expect(layout.visible == [w(1)])
    }

    @Test func horizontalSplitWithGap() {
        let tree = LayoutTree(root: .split(Split(axis: .horizontal, children: [stack(1), stack(2)])))
        let layout = LayoutEngine.layout(tree, in: CGRect(x: 0, y: 0, width: 1000, height: 500), gap: 10)
        #expect(layout.frames[w(1)] == CGRect(x: 10, y: 10, width: 485, height: 480))
        #expect(layout.frames[w(2)] == CGRect(x: 505, y: 10, width: 485, height: 480))

        #expect(layout.seams.count == 1)
        #expect(layout.seams[0].rect == CGRect(x: 495, y: 10, width: 10, height: 480))
        #expect(layout.seams[0].length == 970)
    }

    @Test func verticalSplitPutsFirstChildOnTop() {
        let tree = LayoutTree(root: .split(Split(axis: .vertical, children: [stack(1), stack(2)])))
        let layout = LayoutEngine.layout(tree, in: CGRect(x: 0, y: 0, width: 500, height: 1000), gap: 0)
        #expect(layout.frames[w(1)] == CGRect(x: 0, y: 500, width: 500, height: 500))
        #expect(layout.frames[w(2)] == CGRect(x: 0, y: 0, width: 500, height: 500))
    }

    @Test func weightsSetShares() {
        let tree = LayoutTree(root: .split(
            Split(axis: .horizontal, children: [stack(1), stack(2)], weights: [3, 1])
        ))
        let layout = LayoutEngine.layout(tree, in: CGRect(x: 0, y: 0, width: 1000, height: 100), gap: 0)
        #expect(layout.frames[w(1)]?.width == 750)
        #expect(layout.frames[w(2)]?.width == 250)
    }

    @Test func roundingKeepsNeighborsFlush() {
        let tree = LayoutTree(root: .split(
            Split(axis: .horizontal, children: [stack(1), stack(2), stack(3)])
        ))
        let layout = LayoutEngine.layout(tree, in: CGRect(x: 0, y: 0, width: 1000, height: 100), gap: 0)
        let a = layout.frames[w(1)]!, b = layout.frames[w(2)]!, c = layout.frames[w(3)]!
        #expect(a.minX == 0)
        #expect(a.maxX == b.minX)
        #expect(b.maxX == c.minX)
        #expect(c.maxX == 1000)
        #expect([a, b, c].allSatisfy { $0.width == $0.width.rounded() })
    }

    @Test func respectsBoundsOrigin() {
        // e.g. a display area that starts after a left-side Dock.
        let tree = LayoutTree(root: stack(1))
        let layout = LayoutEngine.layout(tree, in: CGRect(x: 64, y: 0, width: 1856, height: 1170), gap: 8)
        #expect(layout.frames[w(1)] == CGRect(x: 72, y: 8, width: 1840, height: 1154))
    }

    @Test func nestedSplitSeamsReportTheirOwnSplit() {
        let inner = Split(axis: .vertical, children: [stack(2), stack(3)])
        let tree = LayoutTree(root: .split(Split(axis: .horizontal, children: [stack(1), .split(inner)])))
        let layout = LayoutEngine.layout(tree, in: CGRect(x: 0, y: 0, width: 1000, height: 1000), gap: 0)
        #expect(layout.seams.count == 2)
        #expect(Set(layout.seams.map(\.split)) == [tree.root!.id, inner.id])
    }
}
