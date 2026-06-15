import simd

/// Act II — the 4-frame quartet motion outline. Hand-written Swift port of
/// `SixFour.Spec.QuartetDelta`. The user picks 4 frames; each palette slot becomes a
/// 4-sample OKLab trajectory. The readouts split the quartet into a static *core*
/// (low-displacement slots = structural colour) and the *motion outline* (per-slot
/// displacement = how far each colour travels). This is the residual the global
/// collapse (`FarthestPointCollapse`) discards — collapse owns the static pose,
/// `QuartetDelta` owns the motion.
///
/// Carried as `SIMD3<Double>` (OKLab) to match the spec's precision. Gated against
/// `QuartetDeltaGolden` (`QuartetDeltaGoldenTests`) — float OKLab Euclidean math
/// can't be bit-exact across languages, so the gate is within tolerance.
enum QuartetDelta {
    /// The number of frames in a quartet — fixed at 4 (the `T` axis of `4⁴`).
    static let quartetFrames = 4

    /// Zip 4 aligned palettes (each `K` colours, slot-aligned) into `K` trajectories
    /// (a transpose). Requires exactly 4 equal-length palettes; malformed input → `[]`
    /// (mirrors the spec's `toSlots` total contract).
    static func toSlots(_ palettes: [[SIMD3<Double>]]) -> [[SIMD3<Double>]] {
        guard palettes.count == quartetFrames,
              let n = palettes.first?.count,
              palettes.allSatisfy({ $0.count == n })
        else { return [] }
        return (0..<n).map { i in palettes.map { $0[i] } }
    }

    /// The 3 transition distances `[|f1→f2|, |f2→f3|, |f3→f4|]` (OKLab Euclidean).
    static func slotDeltas(_ slot: [SIMD3<Double>]) -> [Double] {
        guard slot.count == quartetFrames else { return [] }
        return (0..<(quartetFrames - 1)).map { simd_distance(slot[$0], slot[$0 + 1]) }
    }

    /// Total path length over the quartet = the slot's motion magnitude. 0 ⇔ never moves.
    static func slotDisplacement(_ slot: [SIMD3<Double>]) -> Double {
        slotDeltas(slot).reduce(0, +)
    }

    /// The slot's central colour: the mean of its 4 samples (its piece of the barycenter).
    static func slotMean(_ slot: [SIMD3<Double>]) -> SIMD3<Double> {
        guard slot.count == quartetFrames else { return .zero }
        return 0.25 * (slot[0] + slot[1] + slot[2] + slot[3])
    }

    /// The quartet's overall barycenter — "the core of the whole": the mean of all slot means.
    static func quartetCore(_ slots: [[SIMD3<Double>]]) -> SIMD3<Double> {
        guard !slots.isEmpty else { return .zero }
        let sum = slots.reduce(SIMD3<Double>.zero) { $0 + slotMean($1) }
        return sum / Double(slots.count)
    }

    /// Slots ranked by displacement, ascending — `(slotIndex, displacement)`. Lowest first =
    /// most "core". Ties resolve to the lower slot index (a total, device-stable order).
    static func corenessRanked(_ slots: [[SIMD3<Double>]]) -> [(Int, Double)] {
        slots.enumerated()
            .map { ($0.offset, slotDisplacement($0.element)) }
            .sorted { ($0.1, $0.0) < ($1.1, $1.0) }
    }

    /// Median per-slot displacement — the relative core/motion cut (mirrors
    /// `Spec.QuartetDelta.medianDisplacementThreshold`, golden-pinned). Recomputed per quartet;
    /// `0` for an empty quartet. On a spread of displacements it splits the slots non-trivially.
    static func medianDisplacementThreshold(_ slots: [[SIMD3<Double>]]) -> Double {
        let ds = slots.map { slotDisplacement($0) }.sorted()
        return ds.isEmpty ? 0 : ds[ds.count / 2]
    }

    /// The core-colour set: slot indices whose displacement is `<=` the threshold — the
    /// colours the UI outlines as structural, and the protect-set passed to Act III.
    static func coreColors(_ threshold: Double, _ slots: [[SIMD3<Double>]]) -> [Int] {
        slots.enumerated()
            .filter { slotDisplacement($0.element) <= threshold }
            .map { $0.offset }
    }
}
