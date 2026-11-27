import CoreGraphics
import Foundation
import Testing
@testable import FractalCore

private func w(_ n: Int) -> WindowID { WindowID(n) }

/// Builds a tree by inserting windows 1...n in order.
private func tree(_ n: Int, bounds: CGRect = CGRect(x: 0, y: 0, width: 1600, height: 1000)) -> LayoutTree {
    var tree = LayoutTree()
    for i in 1...n { tree.insert(w(i), bounds: bounds) }
    return tree
}

private func stackID(_ tree: LayoutTree, _ n: Int) -> NodeID {
    tree.stack(containing: w(n))!.id
}

private func fractions(_ tree: LayoutTree) -> [Double] {
    guard case .split(let split)? = tree.root else { return [] }
    return split.fractions
}

private func close(_ a: [Double], _ b: [Double]) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 1e-9 }
}

@Suite struct InsertTests {
    @Test func firstWindowBecomesRootStack() {
        #expect(tree(1).summary == "1")
    }

    @Test func secondWindowSplitsSideBySide() {
        let t = tree(2)
        #expect(t.summary == "H(1 | 2)")
        #expect(close(fractions(t), [0.5, 0.5]))
    }

    @Test func splitsLargestStackAlongLongerSide() {
        // 3: windows 1 and 2 tie at 800x1000, so 1 (first) splits, vertically (taller than wide).
        #expect(tree(3).summary == "H(V(1 / 3) | 2)")
        #expect(tree(4).summary == "H(V(1 / 3) | V(2 / 4))")
        #expect(tree(5).summary == "H(V(H(1 | 5) / 3) | V(2 / 4))")
        #expect(tree(6).summary == "H(V(H(1 | 5) / H(3 | 6)) | V(2 / 4))")
    }

    @Test func insertingExistingWindowIsIgnored() {
        var t = tree(2)
        t.insert(w(1))
        #expect(t.summary == "H(1 | 2)")
    }

    @Test func sixWindowsTileTheAreaWithoutOverlap() {
        let bounds = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let layout = LayoutEngine.layout(tree(6, bounds: bounds), in: bounds, gap: 0)
        let rects = Array(layout.frames.values)
        let totalArea = rects.reduce(0) { $0 + $1.width * $1.height }
        #expect(totalArea == bounds.width * bounds.height)
        for (i, a) in rects.enumerated() {
            for b in rects[(i + 1)...] {
                #expect(a.intersection(b).isEmpty || a.intersection(b).width * a.intersection(b).height == 0)
            }
        }
    }
}

@Suite struct DockTests {
    @Test func dockAlongParentAxisAddsSiblingWithAnEqualShare() {
        var t = tree(2) // H(1 | 2)
        t.dock(w(3), at: .right, of: stackID(t, 2))
        #expect(t.summary == "H(1 | 2 | 3)")
        #expect(close(fractions(t), [1.0 / 3, 1.0 / 3, 1.0 / 3]))
    }

    @Test func equalShareKeepsExistingProportions() {
        var t = tree(2)
        t.resizeSeam(in: t.root!.id, after: 0, by: 0.25) // [0.75, 0.25]
        t.dock(w(3), at: .right, of: stackID(t, 2))
        #expect(close(fractions(t), [0.5, 1.0 / 6, 1.0 / 3]))
    }

    @Test func dockOnRootEdgeAlongItsAxisJoinsTheSplit() {
        var t = tree(2) // H(1 | 2)
        t.dock(w(3), at: .left, of: t.root!.id)
        #expect(t.summary == "H(3 | 1 | 2)")
        #expect(close(fractions(t), [1.0 / 3, 1.0 / 3, 1.0 / 3]))
    }

    @Test func dockLeftInsertsBeforeTarget() {
        var t = tree(2)
        t.dock(w(3), at: .left, of: stackID(t, 2))
        #expect(t.summary == "H(1 | 3 | 2)")
    }

    @Test func dockAcrossParentAxisWrapsTarget() {
        var t = tree(2)
        t.dock(w(3), at: .top, of: stackID(t, 2))
        #expect(t.summary == "H(1 | V(3 / 2))")
    }

    @Test func dockOnRootEdgeSpansTheWholeSide() {
        var t = tree(2)
        t.dock(w(3), at: .bottom, of: t.root!.id)
        #expect(t.summary == "V(H(1 | 2) / 3)")
    }

    @Test func dockingAnExistingWindowMovesIt() {
        var t = tree(2)
        t.dock(w(3), at: .right, of: stackID(t, 2)) // H(1 | 2 | 3)
        t.dock(w(1), at: .bottom, of: stackID(t, 3))
        #expect(t.summary == "H(2 | V(3 / 1))")
        #expect(t.windows.sorted { $0.raw < $1.raw } == [w(1), w(2), w(3)])
    }

    @Test func dockingALoneWindowNextToItselfChangesNothing() {
        var t = tree(2)
        let before = t
        t.dock(w(2), at: .left, of: stackID(t, 2))
        #expect(t == before)
    }

    @Test func dockOnMissingTargetChangesNothing() {
        var t = tree(2)
        let before = t
        t.dock(w(3), at: .left, of: NodeID())
        #expect(t == before)
    }
}

@Suite struct RemoveTests {
    @Test func removingCollapsesSingleChildSplit() {
        var t = tree(3) // H(V(1 / 3) | 2)
        t.remove(w(3))
        #expect(t.summary == "H(1 | 2)")
    }

    @Test func removingLastWindowEmptiesTree() {
        var t = tree(1)
        t.remove(w(1))
        #expect(t.root == nil)
        #expect(t.summary == "∅")
    }

    @Test func removedSpaceGoesToTheNextSibling() {
        var t = tree(2)
        t.dock(w(3), at: .right, of: stackID(t, 2)) // H(1 | 2 | 3), thirds
        t.remove(w(2))
        #expect(t.summary == "H(1 | 3)")
        #expect(close(fractions(t), [1.0 / 3, 2.0 / 3]))
    }

    @Test func removedLastChildsSpaceGoesToThePreviousSibling() {
        var t = tree(2)
        t.dock(w(3), at: .right, of: stackID(t, 2))
        t.remove(w(3))
        #expect(close(fractions(t), [1.0 / 3, 2.0 / 3]))
    }

    @Test func emptiedSubtreeGivesItsSpaceToItsNeighbor() {
        // H(V(1 / 3) | 2 | 4): removing 1 and 3 empties the first group; 2 takes its share.
        var t = tree(3) // H(V(1 / 3) | 2)
        t.dock(w(4), at: .right, of: stackID(t, 2)) // thirds
        t.remove(w(1))
        t.remove(w(3))
        #expect(t.summary == "H(2 | 4)")
        #expect(close(fractions(t), [2.0 / 3, 1.0 / 3]))
    }

    @Test func removingUnknownWindowChangesNothing() {
        var t = tree(2)
        let before = t
        t.remove(w(99))
        #expect(t == before)
    }
}

@Suite struct TabTests {
    @Test func addTabMovesWindowIntoStackAndActivatesIt() {
        var t = tree(2)
        t.addTab(w(2), to: stackID(t, 1))
        #expect(t.summary == "1,2*")
    }

    @Test func tabsShareAFrameAndOnlyTheActiveOneIsVisible() {
        var t = tree(3) // H(V(1 / 3) | 2)
        t.addTab(w(3), to: stackID(t, 2)) // H(1 | 2,3*)
        #expect(t.summary == "H(1 | 2,3*)")
        let layout = LayoutEngine.layout(t, in: CGRect(x: 0, y: 0, width: 1000, height: 500), gap: 0)
        #expect(layout.frames[w(2)] == layout.frames[w(3)])
        #expect(layout.visible == [w(1), w(3)])
    }

    @Test func activateSwitchesTab() {
        var t = tree(2)
        t.addTab(w(2), to: stackID(t, 1)) // 1,2*
        t.activate(w(1))
        #expect(t.summary == "1*,2")
    }

    @Test func removingActiveTabActivatesANeighbor() {
        var t = tree(1)
        t.dock(w(2), at: .right, of: stackID(t, 1))
        t.dock(w(3), at: .right, of: stackID(t, 2))
        t.addTab(w(2), to: stackID(t, 1))
        t.addTab(w(3), to: stackID(t, 1)) // 1,2,3*
        t.remove(w(3))
        #expect(t.summary == "1,2*")
        t.activate(w(1)) // 1*,2
        t.remove(w(1))
        #expect(t.summary == "2")
    }
}

@Suite struct ResizeTests {
    @Test func resizeMovesTheSeam() throws {
        var t = tree(2)
        let split = t.root!.id
        t.resizeSeam(in: split, after: 0, by: 0.2)
        #expect(close(fractions(t), [0.7, 0.3]))
        t.resizeSeam(in: split, after: 0, by: -0.4)
        #expect(close(fractions(t), [0.3, 0.7]))
    }

    @Test func resizeClampsToMinimumShare() {
        var t = tree(2)
        t.resizeSeam(in: t.root!.id, after: 0, by: 0.9)
        #expect(close(fractions(t), [0.95, 0.05]))
    }

    @Test func resizeOnlyTouchesTheTwoNeighbors() {
        var t = tree(2)
        t.dock(w(3), at: .right, of: stackID(t, 2)) // thirds
        t.resizeSeam(in: t.root!.id, after: 1, by: 0.1)
        #expect(close(fractions(t), [1.0 / 3, 1.0 / 3 + 0.1, 1.0 / 3 - 0.1]))
    }

    @Test func resizeWithBadIndexChangesNothing() {
        var t = tree(2)
        let before = t
        t.resizeSeam(in: t.root!.id, after: 5, by: 0.1)
        #expect(t == before)
    }
}

@Suite struct NormalizeTests {
    private func stack(_ n: Int) -> Node { .stack(Stack(windows: [w(n)])) }

    @Test func sameAxisChildSplitIsFlattenedKeepingGeometry() {
        let inner = Split(axis: .horizontal, children: [stack(2), stack(3)])
        let t = LayoutTree(root: .split(Split(axis: .horizontal, children: [stack(1), .split(inner)])))
        #expect(t.summary == "H(1 | 2 | 3)")
        #expect(close(fractions(t), [0.5, 0.25, 0.25]))
    }

    @Test func crossAxisChildSplitIsKept() {
        let inner = Split(axis: .vertical, children: [stack(2), stack(3)])
        let t = LayoutTree(root: .split(Split(axis: .horizontal, children: [stack(1), .split(inner)])))
        #expect(t.summary == "H(1 | V(2 / 3))")
    }

    @Test func collapseThenFlatten() {
        // H(1 | V(H(2 | 3))) — the V has one child, collapses to H(2 | 3), which then flattens.
        let h23 = Split(axis: .horizontal, children: [stack(2), stack(3)])
        let v = Split(axis: .vertical, children: [.split(h23)])
        let t = LayoutTree(root: .split(Split(axis: .horizontal, children: [stack(1), .split(v)])))
        #expect(t.summary == "H(1 | 2 | 3)")
    }

    @Test func badWeightsAreRepaired() {
        let t = LayoutTree(root: .split(
            Split(axis: .horizontal, children: [stack(1), stack(2)], weights: [.nan, -1])
        ))
        #expect(close(fractions(t), [0.5, 0.5]))
    }
}

@Suite struct CodableTests {
    @Test func treeRoundTripsThroughJSON() throws {
        var t = tree(6)
        t.addTab(w(4), to: stackID(t, 2))
        let data = try JSONEncoder().encode(t)
        let decoded = try JSONDecoder().decode(LayoutTree.self, from: data)
        #expect(decoded == t)
    }
}
