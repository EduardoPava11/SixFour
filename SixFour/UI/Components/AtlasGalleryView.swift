import SwiftUI
import simd

/// COLOR ATLAS — the Compare candidate strip (docs/COLOR-ATLAS.md §8 Phase C).
///
/// Two candidate global palettes side by side, each a 16×16 swatch of its 256
/// leaves at the GIF-pixel atom: A = the `FarthestPointCollapse` maximin
/// baseline (the fidelity floor), B = the deterministic perturbed alternative.
/// Tapping one PLAYS a `Compare` move (the Bradley-Terry pairwise signal) and
/// publishes the winner — with pinned anchors substituted verbatim — as the
/// curated global palette at the `PaletteCollapse` seam. The MCTS gallery
/// (`extractGallery`, DPP-diverse) drops into this exact pair seam later; the
/// UI contract (pick one of the surfaced options) does not change.
struct AtlasGalleryView: View {
    @Bindable var atlas: AtlasState

    var body: some View {
        VStack(spacing: GlobalLattice.pt(2)) {
            HStack(spacing: GlobalLattice.gif(GlobalLattice.gutterCells)) {
                candidate(.a, label: "A·MAXIMIN", swatch: atlas.candidateASRGB,
                          leaves: atlas.candidateA)
                candidate(.b, label: "B·PERTURB", swatch: atlas.candidateBSRGB,
                          leaves: atlas.candidateB)
            }
            // The n=0 taste readout — picks fold θ; the winner palette recolours
            // toward the learned taste. Made legible so the loop is testable.
            CellText(tasteLine, rows: 6,
                     ink: Color(srgb8: atlas.compareCount > 0
                        ? SIMD3<UInt8>(120, 190, 230)
                        : SIMD3<UInt8>(110, 110, 116)))
        }
    }

    /// e.g. "TASTE · 3 PICKS · ‖θ‖ 0.12 · ACTIVE" (or "LEARNING" before any pick).
    private var tasteLine: String {
        let n = atlas.compareCount
        let norm = String(format: "%.2f", atlas.tasteNorm)
        return "TASTE · \(n) PICK\(n == 1 ? "" : "S") · ‖θ‖ \(norm) · \(n > 0 ? "ACTIVE" : "LEARNING")"
    }

    private func candidate(
        _ which: AtlasState.Candidate, label: String,
        swatch: [SIMD3<UInt8>], leaves: [SIMD3<Int32>]
    ) -> some View {
        let picked = !leaves.isEmpty && atlas.pickedHash == AtlasState.fnv1a32(leaves)
        return VStack(spacing: GlobalLattice.pt(2)) {
            CellText(picked ? "\(label) ✓" : label, rows: 8,
                     ink: Color(srgb8: picked
                        ? SIMD3<UInt8>(80, 210, 100)
                        : SIMD3<UInt8>(170, 170, 170)))
            Button { atlas.choose(which) } label: {
                CellSprite(cols: 16, rows: 16, cellPt: GlobalLattice.gifPx) { c, r in
                    let i = r * 16 + c
                    return i < swatch.count ? swatch[i] : SIMD3<UInt8>(20, 20, 24)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose candidate \(label)")
        }
    }
}
