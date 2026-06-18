import SwiftUI

/// The per-frame orthogonal A/B candidate picker: two competing 16×16 candidate looks; tapping one
/// IS the pick. Surfaces `ABCandidates.fromPalette` (the `GenomePair.sampleOrthogonalPair` pair).
/// Renders through the sanctioned `CellSprite` primitive and routes every dimension through
/// `GlobalLattice` (the GRID design law). Gated by `Feature.abCandidatePicker`. See
/// `docs/SIXFOUR-PER-FRAME-GENOME-AB-MIGRATION-WORKFLOW.md` Pillar B.
struct CandidatePickView: View {
    let candidateA: [SIMD3<UInt8>]
    let candidateB: [SIMD3<UInt8>]
    /// Picks so far — drives the converging A/B gap shown to the user (`DivergenceSchedule`).
    let round: Int
    /// Called with `true` for A, `false` for B — the Compare outcome (winner = the tapped tile).
    /// The game continues: each pick re-proposes a taste-shifted pair.
    let onPick: (_ pickedA: Bool) -> Void
    /// Called when the user is satisfied and wants the full cube-ladder export {16³, 64³, 256³}.
    let onExport: () -> Void

    var body: some View {
        VStack(spacing: GlobalLattice.pt(2)) {
            Text(headerText).font(.caption2.monospaced())
            HStack(spacing: GlobalLattice.pt(9)) {          // 9 × 4 = 36 pt gutter (symmetric A|B)
                tile(candidateA, label: "A") { onPick(true) }
                tile(candidateB, label: "B") { onPick(false) }
            }
            Button(action: onExport) {
                Text("EXPORT ▸").font(.caption.monospaced().weight(.bold))
            }
            .buttonStyle(.plain)
            .padding(.top, GlobalLattice.pt(2))
            .accessibilityLabel("Export the full cube ladder")
        }
    }

    /// "PICK A LOOK · ROUND n · Δ closing" — the game progress + the converging gap.
    private var headerText: String {
        let gap = DivergenceSchedule.default.divergence(round)
        return "PICK A LOOK · ROUND \(round + 1) · Δ \(String(format: "%.2f", gap))"
    }

    private func tile(_ palette: [SIMD3<UInt8>], label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: GlobalLattice.pt(1)) {
                CellSprite(cols: 16, rows: 16, cellPt: GlobalLattice.gif(1)) { c, r in
                    let i = r * 16 + c
                    return i < palette.count ? palette[i] : nil
                }
                Text(label).font(.caption.monospaced().weight(.bold))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Candidate \(label)")
    }
}
