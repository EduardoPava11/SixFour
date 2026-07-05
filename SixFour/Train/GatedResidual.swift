import Foundation

/// The determinism-SAFE learned-residual gate — the Swift twin of
/// `Spec.GatedResidual` (verified byte-for-byte against it in
/// `GatedResidualTests`). A float learner (`DeviceTrainStepCPU.rawBands`, the
/// `Spec.DetailPredictor` head) is introduced over the byte-exact floor by
/// scaling its residual with a gate `s = tanh α` BEFORE the single Q16 crossing:
///
///   • `α = 0 ⇒ s = 0 ⇒` every committed band is `0` = the lossless floor, by
///     arithmetic (no sentinel) — the gene can be dialled fully to the floor
///     without touching its weights.
///   • `|tanh α| < 1 ⇒ |s·rawⱼ| ≤ |rawⱼ|` — the gate only pulls TOWARD the floor,
///     never past the ungated invention, so riding a float learner on the
///     lossless path can never make a capture worse than the full gene.
///
/// The gate `α` starts at `0` (contribute nothing) and is raised only as the
/// gene earns it — the "introduce with α ≈ 0" rule from the per-capture-learning
/// research (`docs/PER-CAPTURE-LEARNING-RESEARCH.md` §3, `docs/YINYANG-ZIG-METAL.md`).
enum GatedResidual {

    /// The gate `s = tanh α ∈ (-1, 1)`. `α = 0` is the floor; `α → ±∞` is the
    /// ungated head. `Spec.GatedResidual.gate`.
    static func gate(_ alpha: Double) -> Double { tanh(alpha) }

    /// The gated raw bands: each ungated readout `θⱼ·φ(v)` scaled by `tanh α`,
    /// still a Latent (float) — the gate never touches a byte.
    static func gatedRawBands(theta: [Double], coarse: Int, alpha: Double) -> [Double] {
        let s = gate(alpha)
        return DeviceTrainStepCPU.rawBands(theta: theta, coarse: coarse).map { s * $0 }
    }

    /// The committed gated detail: the gated readout re-entered to Q16 through the
    /// one sanctioned crossing (`DeviceTrainStepCPU.quantizeQ16`, round-half-to-even).
    /// `α = 0` commits the all-zero floor. `Spec.GatedResidual.gatedCommitted`.
    static func gatedCommitted(theta: [Double], coarse: Int, alpha: Double) -> [Int] {
        gatedRawBands(theta: theta, coarse: coarse, alpha: alpha).map(DeviceTrainStepCPU.quantizeQ16)
    }
}
