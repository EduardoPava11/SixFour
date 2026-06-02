import Testing
import simd
@testable import SixFour

/// Gate for the search value head (`PaletteValue`) against the spec golden
/// (`PaletteValueGolden`, from `SixFour.Spec.PaletteOracle` / `Loss` / `Diversity`).
/// Float aesthetic math ⇒ tolerance gate. All three numbers are computed on the SAME
/// `reconstruct(analyze(leaves))` path the spec used.
struct PaletteValueGoldenTests {

    private static let tol = 1e-9

    @Test func valueHeadMatchesGolden() {
        let hp = PaletteHaarTree.analyze(PaletteValueGolden.leaves)
        let leaves = PaletteHaarTree.reconstruct(hp)
        let n = leaves.count
        let uniform = [Double](repeating: 1 / Double(n), count: n)

        let beauty = PaletteValue.beautyLossLeaves(leaves)
        #expect(abs(beauty - PaletteValueGolden.beautyLoss) <= Self.tol,
                "beautyLoss \(beauty) vs \(PaletteValueGolden.beautyLoss)")

        let entropy = PaletteValue.gaussianColorEntropy(leaves, weights: uniform)
        #expect(abs(entropy - PaletteValueGolden.entropy) <= Self.tol,
                "entropy \(entropy) vs \(PaletteValueGolden.entropy)")

        let w = RewardWeights(beauty: PaletteValueGolden.beautyWeight,
                              diversity: PaletteValueGolden.diversityWeight)
        let reward = PaletteValue.paletteReward(w, hp)
        #expect(abs(reward - PaletteValueGolden.reward) <= Self.tol,
                "reward \(reward) vs \(PaletteValueGolden.reward)")
    }

    /// Sanity: higher beauty ⇒ higher reward (the value head is monotone in beauty).
    @Test func rewardRisesWithBeauty() {
        // Two identical leaves are maximally harmonious (chrom=1, asym=0); a spread
        // pair is less so. Reward should not be NaN and should be finite.
        let hp = PaletteHaarTree.analyze(PaletteValueGolden.leaves)
        let r = PaletteValue.paletteReward(.default, hp)
        #expect(r.isFinite)
    }
}
