import SwiftUI

/// Π·deciding — the V3.0 16³ decide loop (`docs/V3-BUILD-WORKFLOW.md` C1).
///
/// A thin σ adapter around `DecideSurface` (the widgets live there, on the
/// proven `GridLayoutContract.decisionScene`): the committed burst's tiles and
/// its somatic θ_up gene flow IN from σ (folded at `commit`), and the verdict
/// flows OUT as FSM events — accept stashes the chosen `SixFourModelInput` +
/// gene ride on σ (the 256³ build's future input) and fires `.decideAccept`
/// (→ `.picked`: a decide-accept IS a committed pick, so export stays
/// pick-gated); again fires `.decideAgain` (→ `.live` for another burst).
/// κ (the ONE 20 Hz clock) rides along for the D1 control beats + the fold reveal.
struct DecidingPhaseField: View {
    let surface: Surface
    let clock: SurfaceClock
    /// THE MERGE's exit seam: ACCEPT's played decision word (as `.s4cr` v3
    /// op-codes) flows OUT to the capture record's owner — wired by
    /// `SurfaceView` to `CaptureViewModel.sealDecisionWord`.
    var onSealWord: ([UInt64]) -> Void = { _ in }

    var body: some View {
        DecideSurface(tiles: surface.burstTiles, thetaUp: surface.thetaUp,
                      substrate: surface.coarseSubstrate,
                      clock: clock,
                      onSealWord: onSealWord) { verdict, input, useGene in
            switch verdict {
            case .accept:
                surface.acceptedInput = input
                surface.acceptedUseGene = useGene
                surface.step(.decideAccept)
            case .again:
                surface.step(.decideAgain)
            }
        }
    }
}
