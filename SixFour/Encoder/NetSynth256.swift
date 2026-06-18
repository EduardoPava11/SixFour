import Foundation

/// The learned 256³ super-resolution — genome-driven detail ABOVE the deterministic
/// nearest-neighbour floor (migration Phase 6 / workflow G6).
///
/// SCAFFOLD (honest): the learned detail is produced by an on-device trainer (the `NetSynth256`
/// weights), which is **not yet built** — a learned net needs training, not a port. Until weights
/// ship, synthesis returns the floor EXACTLY. This is the gated-enhancement contract from
/// `Spec.ExportFamily`: *bit-exact-equal to the floor at zero genome*. The enhancement drops in
/// later (load weights → add genome-driven detail above the floor) without changing the export path.
enum NetSynth256 {

    /// Whether trained weights are loaded. `false` until the trainer ships them.
    static var hasLearnedWeights: Bool { false }

    /// The 256³ synthesis. With no weights (or a zero genome), returns `floor` byte-for-byte — the
    /// `SixFourExport.replicate4x` nearest-neighbour result. When weights land, this adds the
    /// learned high-frequency detail conditioned on `genome` above the floor.
    static func synthesize(floor: [UInt8], genome: [Int]) -> [UInt8] {
        // No weights yet ⇒ the gated enhancement is the identity on the floor.
        guard hasLearnedWeights, genome.contains(where: { $0 != 0 }) else { return floor }
        return floor   // future: floor ⊕ learned detail(genome)
    }
}
