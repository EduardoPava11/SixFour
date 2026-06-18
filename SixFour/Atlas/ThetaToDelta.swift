import Foundation
import simd

/// The taste vector θ → generator-space nudge δ — the canonical path's n=0
/// personalization map (`SixFour.Spec.ThetaToDelta`; `docs/SIXFOUR-CANONICAL-PATH.md`
/// §2, step 2).
///
/// Turns the on-device 770-D Bradley–Terry taste vector θ
/// (`PreferenceUpdate.btUpdate`, laid out as `256 leaves × 3 ++ [coverage, beauty]`)
/// into the 384-DOF generator-space override δ that `SixFourNative.leafOverride`
/// (the owned Zig `s4_leaf_override`) consumes. δ is the **leaf-linear taste-ascent
/// gradient** in generator space; because the σ-pair palette is `[g, σ(g), …]` with
/// `σ(l,a,b) = (l,−a,−b)`, the chain rule gives the closed form (L weights add, chroma
/// weights subtract — σ's signature, structural):
///
///     ∂u/∂Lᵢ = θ[6i]   + θ[6i+3]
///     ∂u/∂aᵢ = θ[6i+1] − θ[6i+4]
///     ∂u/∂bᵢ = θ[6i+2] − θ[6i+5]
///
/// θ is a per-device FLOAT, so this map lives in the float tier (no cross-device
/// bit-exactness is required — each device derives δ from its own θ). It is, however,
/// golden-gated against the Haskell spec (`ThetaToDeltaGoldenTests`): the rounding is
/// **round-half-to-even** (`.toNearestOrEven`, matching Haskell `round`), and δ is
/// clamped to `±deltaMaxQ16` so the tint can recolour but never escape the floor.
enum ThetaToDelta {

    /// Per-component clamp on δ (Q16): ±8192 = ±0.125 OKLab. Mirrors `Spec.deltaMaxQ16`.
    static let deltaMaxQ16: Int32 = 8192
    /// Default gain mapping the float taste-gradient to Q16 units (tunable; the laws
    /// hold for any gain ≥ 0). Mirrors `Spec.defaultGain`.
    static let defaultGain = 4096.0

    /// Generators implied by a θ of length `6g + 2` (= 128 for the 770-D θ).
    static func generators(of theta: [Double]) -> Int { max(0, (theta.count - 2) / 6) }

    /// The raw (unscaled, unclamped) per-generator taste gradient. Linear in θ.
    static func raw(_ theta: [Double]) -> [(Double, Double, Double)] {
        let n = theta.count
        func at(_ k: Int) -> Double { k < n ? theta[k] : 0 }
        return (0 ..< generators(of: theta)).map { i in
            (at(6 * i) + at(6 * i + 3),
             at(6 * i + 1) - at(6 * i + 4),
             at(6 * i + 2) - at(6 * i + 5))
        }
    }

    /// The shipped map: scale by `gain`, round half-to-even, clamp to ±`deltaMaxQ16`.
    /// The result feeds `SixFourNative.leafOverride(generators:deltas:)`.
    static func delta(gain: Double = defaultGain, theta: [Double]) -> [SIMD3<Int32>] {
        let lo = Double(-deltaMaxQ16), hi = Double(deltaMaxQ16)
        func q(_ x: Double) -> Int32 {
            // round-half-to-even matches Haskell `round`; clamp AFTER rounding.
            Int32(min(hi, max(lo, (gain * x).rounded(.toNearestOrEven))))
        }
        return raw(theta).map { SIMD3<Int32>(q($0.0), q($0.1), q($0.2)) }
    }
}
