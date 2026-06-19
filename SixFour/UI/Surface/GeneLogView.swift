import SwiftUI
import simd

/// A cells-only readout of the A/B-game decision log (the "log of A vs B"): one row per round —
/// which side won + the chosen gene's Q16 shift (the `IsoMove` translation that IS the look).
/// Reads the persisted `AtlasDecisionLog` directly, so it survives relaunch. The fuller
/// GeneInspector (the σ-pair / θ gene lenses + per-round GIF thumbnails) is the follow-on.
struct GeneLogView: View {
    /// The A/B rounds, newest first (Compare records carrying the live-game gene fields).
    private var rounds: [AtlasDecisionRecord] {
        AtlasDecisionLogStore.load().entries
            .filter { $0.tag == 3 && $0.abRound != nil }
            .sorted { ($0.abRound ?? 0) > ($1.abRound ?? 0) }
    }

    var body: some View {
        VStack(spacing: GlobalLattice.pt(2)) {
            CellText("A / B LOG", rows: 8, ink: .white)
            let rs = rounds
            if rs.isEmpty {
                CellText("no picks yet", rows: 6, ink: Color(srgb8: SIMD3(140, 140, 140)))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: GlobalLattice.pt(1)) {
                        ForEach(Array(rs.enumerated()), id: \.offset) { _, r in
                            CellText(row(r), rows: 5, ink: Color(srgb8: SIMD3(200, 200, 200)))
                        }
                    }
                }
                .frame(maxHeight: GlobalLattice.gif(72))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("A versus B pick log")
    }

    /// "R{n}  {A|B}  t({l},{a},{b})" — the round, the winning side, the chosen gene's Q16 shift.
    private func row(_ r: AtlasDecisionRecord) -> String {
        let n = r.abRound ?? 0
        let side = (r.abPickedA ?? false) ? "A" : "B"
        let s = r.abCenterShift ?? [0, 0, 0]
        let shift = s.count == 3 ? "t(\(s[0]) \(s[1]) \(s[2]))" : ""
        return "R\(n) \(side) \(shift)"
    }
}
