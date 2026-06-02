import Testing
import Foundation
import simd
@testable import SixFour

/// Gate for the 4⁴ drill navigation (`Quad4Nav`) — the pure core behind
/// `Quad4DrillView`. Navigating the genome tree to a full-depth path must land on
/// exactly the `Quad4.reconstruct` leaf for that path's 4-ary index, so the visual
/// drill and the projected palette can never disagree.
struct Quad4NavTests {

    private func leaves() -> [SIMD3<Double>] {
        var s: UInt64 = 0x4ADD
        func d() -> Double { s = s &* 6364136223846793005 &+ 1; return Double(s >> 40) / Double(1 << 24) }
        return (0..<256).map { _ in SIMD3<Double>(d(), d() - 0.5, d() - 0.5) }
    }

    @Test func nodeIndexIsBase4Positional() {
        #expect(Quad4Nav.nodeIndex([][...]) == 0)
        #expect(Quad4Nav.nodeIndex([3][...]) == 3)
        #expect(Quad4Nav.nodeIndex([1, 2][...]) == 6)        // 1*4 + 2
        #expect(Quad4Nav.leafIndex([1, 2, 3, 0]) == 1*64 + 2*16 + 3*4 + 0)
    }

    @Test func fullPathLandsOnTheReconstructLeaf() {
        let tree = Quad4.analyze(leaves())
        let recon = Quad4.reconstruct(tree)
        // A spread of full-depth paths.
        for path in [[0,0,0,0], [3,3,3,3], [1,2,3,0], [2,0,1,3], [0,3,1,2]] {
            let (leaf, children) = Quad4Nav.nodeAndChildren(tree, path: path)
            #expect(children == [leaf], "full-depth node must be a leaf")
            let want = recon[Quad4Nav.leafIndex(path)]
            #expect(abs(leaf.x - want.x) <= 1e-9 && abs(leaf.y - want.y) <= 1e-9 && abs(leaf.z - want.z) <= 1e-9,
                    "drill path \(path) diverged from reconstruct leaf")
        }
    }

    @Test func childrenAreTheFourOpponentQuadrants() {
        let tree = Quad4.analyze(leaves())
        // At the root, the four children are exactly reconstruct's first 4 leaves
        // grouped by the top-level quad (one per 64-leaf block's top parent path).
        let (_, kids) = Quad4Nav.nodeAndChildren(tree, path: [])
        #expect(kids.count == 4)
        // Each child equals navigating one level down.
        for q in 0..<4 {
            let (childParent, _) = Quad4Nav.nodeAndChildren(tree, path: [q])
            #expect(childParent == kids[q])
        }
    }
}
