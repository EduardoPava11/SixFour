import Testing
import simd
@testable import SixFour

/// Gate for the θ → δ taste map (`ThetaToDelta`, the Swift port of
/// `SixFour.Spec.ThetaToDelta`). θ is per-device float, so this is a single-impl
/// determinism + spec-conformance gate (the GLRM pattern), not a cross-device
/// claim. Goldens captured from the Haskell spec via `cabal repl`. The gain=1 case
/// deliberately exercises a `.5` tie to pin **round-half-to-even** (Haskell `round`
/// vs Swift's default away-from-zero).
struct ThetaToDeltaGoldenTests {

    // 2 generators (14 dims = 6·2 + [coverage, beauty]).
    private let tg: [Double] = [1.0, 2.0, 3.0, 0.5, -1.0, 4.0,
                                -2.0, 1.5, 0.0, 3.0, 0.5, -0.5,
                                7.0, 8.0]

    /// The raw gradient matches the chain-rule closed form (L adds, chroma subtracts).
    @Test func rawMatchesGolden() {
        let raw = ThetaToDelta.raw(tg)
        #expect(raw.count == 2)
        #expect(raw[0] == (1.5, 3.0, -1.0)) // (1+0.5, 2−(−1), 3−4)
        #expect(raw[1] == (1.0, 1.0, 0.5)) // (−2+3, 1.5−0.5, 0−(−0.5))
    }

    /// gain=1 — exercises round-half-to-even: raw[1].b = 0.5 → 0 (NOT 1).
    @Test func gain1MatchesGoldenWithBankersRounding() {
        let d = ThetaToDelta.delta(gain: 1.0, theta: tg)
        #expect(d == [SIMD3<Int32>(2, 3, -1), SIMD3<Int32>(1, 1, 0)])
    }

    /// gain=4096 (default) — exact integers + the clamp to ±8192 (3.0·4096=12288 → 8192).
    @Test func gain4096MatchesGoldenWithClamp() {
        let d = ThetaToDelta.delta(gain: 4096.0, theta: tg)
        #expect(d == [SIMD3<Int32>(6144, 8192, -4096), SIMD3<Int32>(4096, 4096, 2048)])
    }

    /// Zero θ ⇒ zero δ (lawZeroThetaZeroDelta), and the [coverage, beauty] tail is ignored.
    @Test func zeroAndTailIgnored() {
        #expect(ThetaToDelta.delta(theta: [Double](repeating: 0, count: 770)).allSatisfy { $0 == .zero })
        var bumped = [Double](repeating: 0, count: 770)
        bumped[768] = 999; bumped[769] = -999 // coverage/beauty only
        #expect(ThetaToDelta.delta(theta: bumped).allSatisfy { $0 == .zero })
    }

    /// δ is bounded to ±deltaMaxQ16 under a large gain (lawDeltaBoundedQ16).
    @Test func deltaIsBounded() {
        let d = ThetaToDelta.delta(gain: 1e9, theta: tg)
        for v in d {
            #expect(v.x >= -8192 && v.x <= 8192)
            #expect(v.y >= -8192 && v.y <= 8192)
            #expect(v.z >= -8192 && v.z <= 8192)
        }
    }

    /// End-to-end: θ → δ → `s4_leaf_override` produces a valid σ-pair palette
    /// (odd leaf = σ of the nudged even leaf), proving the n=0 channel composes.
    @Test func composesWithLeafOverride() {
        let generators = [SIMD3<Int32>(10000, 20000, -5000), SIMD3<Int32>(40000, -10000, 30000)]
        let deltas = ThetaToDelta.delta(theta: tg)
        guard let leaves = SixFourNative.leafOverride(generators: generators, deltas: deltas) else {
            Issue.record("leafOverride nil"); return
        }
        #expect(leaves.count == 4)
        for k in 0 ..< 2 {
            let g = leaves[2 * k]
            #expect(leaves[2 * k + 1] == SIMD3<Int32>(g.x, -g.y, -g.z)) // σ preserved
        }
    }
}
