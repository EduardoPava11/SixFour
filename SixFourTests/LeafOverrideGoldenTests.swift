import Testing
import simd
@testable import SixFour

/// Gate for the owned σ-pair leaf-override kernel (`s4_leaf_override` via
/// `SixFourNative.leafOverride`) — the Swift end of the port of
/// `SixFour.Spec.LeafOverride`, the n=0 taste tint of the canonical path. Spec≡Zig
/// is pinned by the `kernels.zig` unit test; this pins the Swift FFI surface + the
/// four LeafOverride laws (identity-no-op, adds-to-generators, σ-of-nudged,
/// scoped). σ(l,a,b) = (l,−a,−b), exact (no tolerance).
struct LeafOverrideGoldenTests {

    private let generators: [SIMD3<Int32>] = [
        SIMD3<Int32>(10000, 20000, -5000),
        SIMD3<Int32>(40000, -10000, 30000),
    ]

    /// δ0 = 0 (no-op), δ1 nudges all three channels — pins the σ-pair leaves.
    @Test func tintMatchesSpecLaws() {
        let deltas: [SIMD3<Int32>] = [SIMD3<Int32>(0, 0, 0), SIMD3<Int32>(1000, -2000, 3000)]
        guard let leaves = SixFourNative.leafOverride(generators: generators, deltas: deltas) else {
            Issue.record("s4_leaf_override returned nil"); return
        }
        #expect(leaves.count == 4)
        // even leaves = generator + δ (lawSigmaOverrideAddsToGenerators)
        #expect(leaves[0] == SIMD3<Int32>(10000, 20000, -5000)) // δ0 = 0 ⇒ identity
        #expect(leaves[2] == SIMD3<Int32>(41000, -12000, 33000))
        // odd leaves = σ of the NUDGED generator (lawSigmaOverrideOddLeafCarriesSigmaOfNudged)
        #expect(leaves[1] == SIMD3<Int32>(10000, -20000, 5000))
        #expect(leaves[3] == SIMD3<Int32>(41000, 12000, -33000))
    }

    /// The no-op (nil) override = the pure σ-pair of the generators
    /// (lawSigmaOverrideIdentityNoOp), and every odd leaf is σ of its even predecessor.
    @Test func nilOverrideIsPureSigmaPair() {
        guard let leaves = SixFourNative.leafOverride(generators: generators) else {
            Issue.record("nil"); return
        }
        #expect(leaves.count == 4)
        for k in 0 ..< 2 {
            let g = leaves[2 * k]
            #expect(leaves[2 * k + 1] == SIMD3<Int32>(g.x, -g.y, -g.z))
        }
        #expect(leaves[0] == SIMD3<Int32>(10000, 20000, -5000))
        #expect(leaves[2] == SIMD3<Int32>(40000, -10000, 30000))
    }

    /// A single-generator override touches ONLY that pair — the other pair is
    /// byte-identical to the no-op (lawSigmaOverrideScopedToGenerator).
    @Test func overrideIsScopedToOneGenerator() {
        let base = SixFourNative.leafOverride(generators: generators)
        let only1 = SixFourNative.leafOverride(
            generators: generators,
            deltas: [SIMD3<Int32>(0, 0, 0), SIMD3<Int32>(7, 8, 9)])
        guard let base, let only1 else { Issue.record("nil"); return }
        #expect(base[0] == only1[0]) // generator 0's pair untouched
        #expect(base[1] == only1[1])
        #expect(base[2] != only1[2]) // generator 1's pair changed
    }
}
