import Testing
import simd
@testable import SixFour

/// Gate for the owned integer Haar kernels (`s4_haar_analyze` / `s4_haar_reconstruct`
/// via `SixFourNative`). The defining property is EXACT reversibility — pure integer
/// lifting, so `reconstruct∘analyze = id` byte-for-byte (no tolerance). Spec≡Zig is
/// pinned by the Zig fixture test; this pins the Swift FFI surface + exactness.
struct ZigHaarTests {

    private func lcgLeaves(_ n: Int, seed: UInt64) -> [SIMD3<Int32>] {
        var s = seed
        func next(_ lo: Int32, _ hi: Int32) -> Int32 {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            let r = Int32(truncatingIfNeeded: s >> 40) & 0x7FFF
            return lo + (r % (hi - lo + 1))
        }
        return (0..<n).map { _ in SIMD3<Int32>(next(0, 65536), next(-26214, 26214), next(-26214, 26214)) }
    }

    /// reconstruct ∘ analyze = id EXACTLY at every power-of-two depth up to 256.
    @Test func haarRoundTripIsExact() {
        for d in 0...8 {
            let n = 1 << d
            let leaves = lcgLeaves(n, seed: UInt64(0xA11CE &+ d))
            guard let (root, offs) = SixFourNative.haarAnalyze(leaves: leaves) else {
                Issue.record("haarAnalyze nil for n=\(n)"); continue
            }
            #expect(offs.count == n - 1, "n=\(n): expected \(n-1) offsets, got \(offs.count)")
            guard let back = SixFourNative.haarReconstruct(root: root, offsets: offs) else {
                Issue.record("haarReconstruct nil for n=\(n)"); continue
            }
            #expect(back == leaves, "integer Haar round-trip drifted at n=\(n)")
        }
    }

    /// A coefficient move (+δ then −δ) is exactly reversible (the structured LAB step).
    @Test func haarMoveIsExactlyReversible() {
        let leaves = lcgLeaves(64, seed: 0xBEEF)
        guard let (root, offs) = SixFourNative.haarAnalyze(leaves: leaves) else {
            Issue.record("haarAnalyze nil"); return
        }
        var moved = offs
        let delta = SIMD3<Int32>(1234, -567, 890)
        moved[10] &+= delta          // a move on one coefficient
        moved[10] &-= delta          // its inverse
        #expect(moved == offs)
        // And reconstruct of the (round-tripped) tree returns the original leaves.
        #expect(SixFourNative.haarReconstruct(root: root, offsets: moved) == leaves)
    }
}
