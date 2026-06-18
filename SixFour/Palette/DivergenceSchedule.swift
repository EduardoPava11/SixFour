import Foundation

/// Swift port of `SixFour.Spec.DivergenceSchedule` — the A/B policy:value gap `Δ = |r_A − r_B|`
/// that starts WIDE (very different A/B) and NARROWS as the user picks, floored above 0 so A and B
/// never collapse. The "start-diverse-then-converge" knob of the game loop + the MAP-Elites
/// descriptor axis. Double-valued search guidance; gated by the spec laws in
/// `DivergenceScheduleTests` (6 laws, mirroring `Properties.DivergenceSchedule`).
struct DivergenceSchedule {
    var ratioCenter: Double   // r0, the explore/exploit center the pair straddles
    var deltaMax: Double      // widest gap (cold start, n = 0)
    var deltaMin: Double      // floor gap (> 0): A and B never collapse to identical
    var halfLife: Double      // Compares to halve the EXCESS gap (deltaMax − deltaMin)

    /// The shipped schedule: center 0.5, gap 0.8 → 0.05, half-life 8 Compares. Ratios stay in
    /// [0.1, 0.9] ⊂ [0,1] for all n (no clamping).
    static let `default` = DivergenceSchedule(ratioCenter: 0.5, deltaMax: 0.8, deltaMin: 0.05, halfLife: 8)

    /// The decay factor in (0, 1]: halfLife / (n + halfLife). 1 at n = 0, → 0 as n → ∞.
    func deltaDecay(_ n: Int) -> Double { halfLife / (Double(max(0, n)) + halfLife) }

    /// The A/B gap Δ(n) = deltaMin + (deltaMax − deltaMin)·decay(n). Δ(0) = deltaMax; Δ(∞) → deltaMin.
    func divergence(_ n: Int) -> Double { deltaMin + (deltaMax - deltaMin) * deltaDecay(n) }

    /// Candidate A's policy:value ratio — the EXPLORE pole (policy-heavy): center + Δ/2.
    func ratioA(_ n: Int) -> Double { ratioCenter + divergence(n) / 2 }

    /// Candidate B's policy:value ratio — the EXPLOIT pole (value-heavy): center − Δ/2.
    func ratioB(_ n: Int) -> Double { ratioCenter - divergence(n) / 2 }
}
