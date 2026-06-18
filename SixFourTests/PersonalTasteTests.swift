import Testing
import simd
@testable import SixFour

/// Gate for the on-device taste vector θ (`PersonalTaste`, the n=0 personalization
/// core). `btUpdate` is golden-gated vs `Spec.PreferenceUpdate` (goldens captured
/// from `cabal repl`); the embedding + leaf-tint are pinned for shape/bounds.
struct PersonalTasteTests {

    /// btUpdate matches Haskell: from θ=0, winner=[1,0…], loser=0 (d=[1,0…]),
    /// g = 1−σ(0) = 0.5 ⇒ θ[0] = η·g = 0.025; a second step ⇒ 0.0496862…
    @Test func btUpdateMatchesHaskellGolden() {
        let w = [1.0] + [Double](repeating: 0, count: 769)
        let l = [Double](repeating: 0, count: 770)

        let t1 = PersonalTaste.btUpdate(theta: PersonalTaste.zeroTheta(), winner: w, loser: l)
        #expect(abs(t1[0] - 0.025) < 1e-12)
        #expect(t1[1] == 0)

        let t2 = PersonalTaste.btUpdate(theta: t1, winner: w, loser: l)
        #expect(abs(t2[0] - 0.04968626627502448) < 1e-12)
    }

    /// The embedding is 770-D: 768 leaf components + [coverage, beauty]; coverage ∈ [0,1].
    @Test func embeddingShape() {
        let leaves: [SIMD3<Int32>] = (0 ..< 256).map { i in
            let x = Int32(i * 200)
            let y = Int32(i * 100 - 12800)
            return SIMD3<Int32>(x, y, 0)
        }
        let e = PersonalTaste.embedding(leaves: leaves)
        #expect(e.count == 770)
        #expect(e[0] == Double(leaves[0].x) / 65536)
        let coverage = e[768]
        #expect(coverage >= 0 && coverage <= 1)
    }

    /// θ = 0 ⇒ the tint is the identity (no taste ⇒ no recolour).
    @Test func zeroThetaIsIdentityTint() {
        let leaves = (0 ..< 256).map { SIMD3<Int32>(Int32($0 * 100), 0, 0) }
        let tinted = PersonalTaste.leafTint(leaves, theta: PersonalTaste.zeroTheta())
        #expect(tinted == leaves)
    }

    /// The tint is bounded: every channel moves by at most ±tintMaxQ16, even under a
    /// huge θ (the tint can recolour but never escape the floor far).
    @Test func tintIsBounded() {
        let leaves = (0 ..< 256).map { _ in SIMD3<Int32>(30000, 0, 0) }
        let bigTheta = [Double](repeating: 100, count: 770)
        let tinted = PersonalTaste.leafTint(leaves, theta: bigTheta, gain: 1e6)
        for (t, c) in zip(tinted, leaves) {
            #expect(abs(Int(t.x - c.x)) <= 8192)
            #expect(abs(Int(t.y - c.y)) <= 8192)
            #expect(abs(Int(t.z - c.z)) <= 8192)
        }
    }

    /// End-to-end: a pick that prefers winner over loser moves θ in the direction
    /// of (winnerEmb − loserEmb), growing ‖θ‖ from zero.
    @Test func pickGrowsTasteNorm() {
        let winner: [SIMD3<Int32>] = (0 ..< 256).map { i in
            SIMD3<Int32>(Int32(i * 200), 5000, 0)
        }
        let loser: [SIMD3<Int32>] = (0 ..< 256).map { i in
            SIMD3<Int32>(Int32(i * 200), -5000, 0)
        }
        let we = PersonalTaste.embedding(leaves: winner)
        let le = PersonalTaste.embedding(leaves: loser)
        let theta = PersonalTaste.btUpdate(theta: PersonalTaste.zeroTheta(), winner: we, loser: le)
        let norm = (theta.reduce(0) { $0 + $1 * $1 }).squareRoot()
        #expect(norm > 0)
    }
}
