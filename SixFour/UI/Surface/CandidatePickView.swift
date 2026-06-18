import SwiftUI

/// The per-frame orthogonal A/B candidate picker: two competing 16×16 candidate looks; tapping one
/// IS the pick. Surfaces `ABCandidates.fromPalette` (the `GenomePair.sampleOrthogonalPair` pair).
/// Renders through the sanctioned `CellSprite` primitive and routes every dimension through
/// `GlobalLattice` (the GRID design law). Gated by `Feature.abCandidatePicker`. See
/// `docs/SIXFOUR-PER-FRAME-GENOME-AB-MIGRATION-WORKFLOW.md` Pillar B.
struct CandidatePickView: View {
    let candidateA: [SIMD3<UInt8>]
    let candidateB: [SIMD3<UInt8>]
    /// Called with `true` for A, `false` for B — the Compare outcome (winner = the tapped tile).
    let onPick: (_ pickedA: Bool) -> Void

    var body: some View {
        VStack(spacing: GlobalLattice.pt(2)) {
            Text("PICK A LOOK").font(.caption2.monospaced())
            HStack(spacing: GlobalLattice.pt(9)) {          // 9 × 4 = 36 pt gutter (symmetric A|B)
                tile(candidateA, label: "A") { onPick(true) }
                tile(candidateB, label: "B") { onPick(false) }
            }
        }
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
