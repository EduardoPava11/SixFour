import simd

/// Weights on the search value head's two aesthetic terms. The look-NN's value head
/// learns to match this weighted objective; the weights are a tuning choice.
struct RewardWeights: Sendable, Equatable {
    let beauty: Double
    let diversity: Double
    static let `default` = RewardWeights(beauty: 0.5, diversity: 0.5)
}

/// The search's **value head**: a deterministic aesthetic objective over a candidate
/// palette — the ground truth the look-NN is trained to approximate (so it is real,
/// and golden-testable today). Hand-written port of `SixFour.Spec.PaletteOracle.paletteReward`
/// (= `Loss.beautyLossLeaves` + `Diversity.gaussianColorEntropy`), gated within
/// tolerance against `PaletteValueGolden` (`PaletteValueGoldenTests`).
///
/// UNWIRED: consumed ONLY by `PaletteValueGoldenTests` today — no runtime caller until
/// the deferred `PaletteSearch` feature lands. It is verified-but-dormant groundwork
/// (`RewardWeights` likewise), kept because it is the spec-pinned objective search will use.
enum PaletteValue {

    // MARK: Diversity — OKLab Gaussian colour entropy

    /// Differential entropy of the Gaussian fit to the weighted palette,
    /// `½·ln((2πe)³·|Σ|)`. Mirrors `Spec.Diversity.gaussianColorEntropy` exactly,
    /// including the uniform-weight fallback (`Σw ≤ 0`) and the `|Σ| ← max(|Σ|, 1e-12)`
    /// floor. `weights` are normalised to sum to 1 (no re-division in the covariance).
    static func gaussianColorEntropy(_ palette: [SIMD3<Double>], weights: [Double]) -> Double {
        let n = palette.count
        let s = weights.reduce(0, +)
        let ps: [Double] = s <= 0
            ? [Double](repeating: 1 / Double(max(1, n)), count: n)
            : weights.map { $0 / s }

        // Covariance for already-normalised probabilities (Σp = 1).
        var ml = 0.0, ma = 0.0, mb = 0.0
        for (c, p) in zip(palette, ps) { ml += p * c.x; ma += p * c.y; mb += p * c.z }
        var sLL = 0.0, sLa = 0.0, sLb = 0.0, saa = 0.0, sab = 0.0, sbb = 0.0
        for (c, p) in zip(palette, ps) {
            let dl = c.x - ml, da = c.y - ma, db = c.z - mb
            sLL += p * dl * dl; sLa += p * dl * da; sLb += p * dl * db
            saa += p * da * da; sab += p * da * db; sbb += p * db * db
        }
        // Determinant of the symmetric 3×3 covariance (same expansion as the oracle).
        let det = sLL * (saa * sbb - sab * sab)
                - sLa * (sLa * sbb - sab * sLb)
                + sLb * (sLa * sab - saa * sLb)
        let twoPiE = 2 * Double.pi * exp(1.0)
        return 0.5 * log(pow(twoPiE, 3) * max(det, 1e-12))
    }

    // MARK: Beauty — Ou-Luo pair harmony

    /// Combined per-pair beauty: chromatic similarity `exp(−‖Δa,Δb‖)` + lightness
    /// asymmetry `|ΔL|` + combined lightness `(L₁+L₂)/2`. Mirrors `Spec.Loss.pairBeauty`.
    static func pairBeauty(_ c1: SIMD3<Double>, _ c2: SIMD3<Double>) -> Double {
        let da = c1.y - c2.y, db = c1.z - c2.z
        let chrom = exp(-(da * da + db * db).squareRoot())
        let lightAsym = abs(c1.x - c2.x)
        let lightSum = (c1.x + c2.x) / 2
        return chrom + lightAsym + lightSum
    }

    /// Beauty LOSS over ADJACENT leaf pairs `(leaves[2i], leaves[2i+1])`, negated
    /// (a loss is minimised). Mirrors `Spec.Loss.beautyLossLeaves` (drops a trailing
    /// odd leaf — the σ-pair palette is always even).
    static func beautyLossLeaves(_ leaves: [SIMD3<Double>]) -> Double {
        var s = 0.0
        var i = 0
        while i + 1 < leaves.count { s += pairBeauty(leaves[i], leaves[i + 1]); i += 2 }
        return -s
    }

    // MARK: The value head

    /// The value head's target reward over a candidate palette: `wb·(−beautyLoss) +
    /// wd·entropy` on the reconstructed leaves (uniform weights). Mirrors
    /// `Spec.PaletteOracle.paletteReward`.
    static func paletteReward(_ w: RewardWeights, _ hp: HaarPalette) -> Double {
        let leaves = PaletteHaarTree.reconstruct(hp)
        let n = leaves.count
        let ws = [Double](repeating: n == 0 ? 0 : 1 / Double(n), count: n)
        return w.beauty * -beautyLossLeaves(leaves) + w.diversity * gaussianColorEntropy(leaves, weights: ws)
    }
}
