import SwiftUI

/// Π·curating — the LAUNCH 256³ curation loop (a Picked self-excursion;
/// `docs/LAUNCH-BUILD-WORKFLOW.md` L1.3).
///
/// A thin σ adapter around `CurateSurface` (the widgets live there, on the
/// proven `GridLayoutContract.curateScene`): the accepted decide result flows
/// IN from σ (`acceptedInput` + `acceptedUseGene` — stashed by the decide
/// accept, consumed HERE at last) together with the burst's substrate and
/// somatic gene, and the verdict flows OUT as an FSM event — accept records
/// the curated source on σ (`curatedUseGene`, the export step's input) and
/// fires `.curateDone` (→ `.picked`: curation never bypasses the export gate,
/// `lawCurateResolves`).
struct Curating256PhaseField: View {
    let surface: Surface

    var body: some View {
        CurateSurface(
            substrate: surface.coarseSubstrate,
            thetaUp: surface.thetaUp,
            useGene: surface.acceptedUseGene,
            paintedCells: paintedCells,
            paintMask: paintMask
        ) { verdict, useGene in
            switch verdict {
            case .accept:
                surface.curatedUseGene = useGene
                surface.step(.curateDone)
            }
        }
    }

    /// The recorded paint (rows of `acceptedInput.nudge` with any nonzero
    /// budget) — surfaced honestly on the gated repaint cell.
    private var paintedCells: Int {
        guard let input = surface.acceptedInput else { return 0 }
        return input.nudge.reduce(0) { $0 + ($1.contains { $0 != 0 } ? 1 : 0) }
    }

    /// W1: the accepted paint CONSUMED — the decide-time `acceptedInput.nudge`
    /// as a device-order mask, gating WHERE the curate build's gene arm invents
    /// (nil = nothing painted = the whole-volume shortcut). This closes the
    /// "recorded but consumed by nothing" gap the 2026-07-03 audit named.
    private var paintMask: [Bool]? {
        surface.acceptedInput.flatMap { NudgePaintModel.deviceMask(budget: $0.nudge) }
    }
}
