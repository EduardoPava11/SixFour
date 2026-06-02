import Testing
@testable import SixFour

/// Gate for the cross-view brush CONTRACT (`BrushSet`) — the Step-5 unification. The
/// per-radix highlight set is canonical, and the cube's GPU kernel predicate
/// (mirrored in `BrushSet.kernelHit`) must agree with it for every index, so the
/// cube and the CPU views (grid/cloud/tree/picker) light the same colours.
struct BrushSetTests {

    @Test func perRadixHighlightSet() {
        // 16² — single colour.
        #expect(BrushSet.indices(42, branching: .b16) == [42])
        // 2⁸ — the σ-pair {k, k^1}, from either member.
        #expect(Set(BrushSet.indices(42, branching: .b2)) == [42, 43])
        #expect(Set(BrushSet.indices(43, branching: .b2)) == [42, 43])
        // 4⁴ — the four opponent-quadrant siblings sharing k & ~3.
        #expect(Set(BrushSet.indices(42, branching: .b4)) == [40, 41, 42, 43])
        // The primary index is always a member.
        for b in [PaletteBranching.b16, .b4, .b2] {
            #expect(BrushSet.indices(137, branching: b).contains(137))
        }
        // Cube modes.
        #expect(BrushSet.mode(.b16) == 0)
        #expect(BrushSet.mode(.b4) == 1)
        #expect(BrushSet.mode(.b2) == 2)
    }

    /// The cube kernel predicate equals BrushSet membership for EVERY palette index —
    /// the GPU highlight and the CPU views are provably consistent.
    @Test func kernelHitMatchesContract() {
        for b in [PaletteBranching.b16, .b4, .b2] {
            let mode = BrushSet.mode(b)
            for brushed in [0, 1, 2, 42, 43, 200, 255] {
                let set = Set(BrushSet.indices(brushed, branching: b))
                for k in 0..<256 {
                    #expect(BrushSet.kernelHit(k, brushedIndex: brushed, mode: mode) == set.contains(k),
                            "radix \(b) brushed \(brushed): kernel vs contract disagree at \(k)")
                }
            }
        }
        // No brush (-1) ⇒ nothing highlights.
        #expect(!BrushSet.kernelHit(0, brushedIndex: -1, mode: 2))
    }
}
