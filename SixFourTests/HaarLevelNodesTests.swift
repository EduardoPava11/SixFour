import Testing
import simd
@testable import SixFour

/// Gate for the on-device Haar level-node kernel (`s4_haar_level_nodes`, via
/// `SixFourNative.haarLevelNodes`) — the abstraction cascade that the capture
/// shutter (level 4 = 16 colours) surfaces. The cross-language byte-exactness vs
/// the Haskell `levelNodesFixed` is pinned by `haar_golden.json` + the Zig fixture
/// test; here we pin the Swift surface's internal consistency against the sibling
/// Zig kernels (all three homes — Haskell ≡ Zig ≡ Swift — agree because they share
/// the exact integer lifting).
struct HaarLevelNodesTests {

    /// A deterministic Q16 OKLab palette (LCG), in gamut.
    private func leaves(_ count: Int) -> [SIMD3<Int32>] {
        var s: UInt64 = 0xCAFE_C0DE_1234_5678
        func next(_ lo: Int32, _ hi: Int32) -> Int32 {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return lo + Int32(truncatingIfNeeded: (s >> 40)) % (hi - lo)
        }
        return (0..<count).map { _ in SIMD3<Int32>(next(0, 65536), next(-26214, 26214), next(-26214, 26214)) }
    }

    /// Deepest level == the full reconstruction (the leaves), and each level has 2^l nodes.
    @Test func levelNodesCascadeMatchesReconstruct() {
        let n = 64                       // depth 6
        guard let hp = SixFourNative.haarAnalyze(leaves: leaves(n)) else {
            Issue.record("haarAnalyze returned nil"); return
        }
        guard let full = SixFourNative.haarReconstruct(root: hp.root, offsets: hp.offsets) else {
            Issue.record("haarReconstruct returned nil"); return
        }
        let depth = 6
        for l in 0...depth {
            guard let nodes = SixFourNative.haarLevelNodes(level: l, root: hp.root, offsets: hp.offsets) else {
                Issue.record("haarLevelNodes(\(l)) returned nil"); return
            }
            #expect(nodes.count == (1 << l), "level \(l) must have 2^\(l) nodes")
        }
        // level 0 == [root]
        #expect(SixFourNative.haarLevelNodes(level: 0, root: hp.root, offsets: hp.offsets) == [hp.root])
        // deepest level == reconstruct (the leaves)
        #expect(SixFourNative.haarLevelNodes(level: depth, root: hp.root, offsets: hp.offsets) == full)
    }

    /// The capture shutter: a 256-leaf palette yields exactly 16 level-4 colours.
    @Test func shutterIsSixteenLevelFourColours() {
        guard let hp = SixFourNative.haarAnalyze(leaves: leaves(256)) else {
            Issue.record("haarAnalyze returned nil"); return
        }
        let shutter = SixFourNative.haarLevelNodes(level: 4, root: hp.root, offsets: hp.offsets)
        #expect(shutter?.count == 16, "shutter must be 16 colours (Haar level 4)")
    }

    /// Out-of-range level is rejected (guard, not a crash).
    @Test func levelBeyondDepthReturnsNil() {
        guard let hp = SixFourNative.haarAnalyze(leaves: leaves(16)) else {  // depth 4
            Issue.record("haarAnalyze returned nil"); return
        }
        #expect(SixFourNative.haarLevelNodes(level: 5, root: hp.root, offsets: hp.offsets) == nil)
    }
}
