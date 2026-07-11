//  MergeWidgets.swift
//  THE MERGE's instrument column (decisionScene `signal` + `pour` regions) —
//  the game's resource verb and its energy account, beside the board.
//
//  The board itself IS the hero (`DecideHeroWidget` — the per-region
//  granularity pooling is the depth display; tap = S, hold = K). These two
//  widgets carry the economy: `MergeSignalBar` (16×2, display-only) reads the
//  `S4MergeBoard` ledger as a fill bar — phase 1 fills with banked
//  32-evidence toward `threshold32`, phase 2 with regions at the ceiling —
//  and `MergePourWidget` (16×12, D1 FRAME face) banks the next 4-frame slice
//  (`Spec.MergeBoard`: pours are the ONLY signal source; 16 pours = the whole
//  burst). Verdict haptics: accepted = the discrete-event generator
//  (`Haptics.selection()`); refused = dropReject (`Haptics.play(4)`).

import SwiftUI

/// The energy account as a 16×2 cell rail (the tally idiom, one row per
/// quantity): row 0 = the PHASE progress (banked 32-evidence vs the window,
/// then regions at 64), row 1 = spendable signal (one cell per frame-unit,
/// capped at the rail width). Display-only.
struct MergeSignalBar: View {
    @ObservedObject var model: DecideModel

    var body: some View {
        let ink = SIMD3<UInt8>(UInt8(SixFourCellMechanics.faceControlInk.r),
                               UInt8(SixFourCellMechanics.faceControlInk.g),
                               UInt8(SixFourCellMechanics.faceControlInk.b))
        let ghost = SFTheme.ledGhost
        let dim = SIMD3<UInt8>(ghost.x / 4, ghost.y / 4, ghost.z / 4)
        let b = model.merge
        let phaseFill = b.phase2Unlocked
            ? b.count(atLeast: S4MergeBoard.maxDepth)
            : min(16, b.bank32 * 16 / S4MergeBoard.threshold32)
        let signalFill = min(16, b.signal)
        return CellSprite(cols: 16, rows: 2, cellPt: GlobalLattice.gif(1)) { c, r in
            let fill = r == 0 ? phaseFill : signalFill
            return c < fill ? ink : dim
        }
        // THE PROVENANCE CAPTION (`Spec.MergeEvidence`): one word of the SAME
        // honesty vocabulary as the hero chip — MEASURED when pours credit a
        // non-constant schedule priced from the capture's own sealed
        // telemetry, DERIVED for the constant. An instrument label on an
        // instrument (never over image pixels), naming a real provenance bit
        // (`evidenceScaled`) — the charter's rule, not decoration. Data-gated
        // by nature: every shipped burst prices to the constant and reads
        // DERIVED.
        .overlay(alignment: .trailing) {
            CellText(model.evidenceScaled ? "MEASURED" : "DERIVED",
                     rows: 2, cell: GlobalLattice.pt(1),
                     ink: Color(srgb8: SFTheme.ledGhost))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .allowsHitTesting(false)
        .accessibilityLabel(b.phase2Unlocked
            ? "Phase two: \(b.count(atLeast: 2)) of sixteen regions at sixty-four"
            : "Banked evidence \(b.bank32) of \(S4MergeBoard.threshold32)"
              + (model.evidenceScaled ? ", measured evidence" : ", derived evidence"))
    }
}

/// THE MERGE's one resource verb: POUR banks the next 4-frame slice
/// (+4 signal; credits banked 32-evidence where the board already measures
/// at 32). A 16×12 FRAME face (1-cell control-ink ring, the D1 idle BEAT on
/// the 16-rung realize) with the verb and the remaining-slice count as cell
/// text. Exhausted pours = quarter-ink ring, disabled (the burst has no more
/// slices — the honest end of the resource).
struct MergePourWidget: View {
    @ObservedObject var model: DecideModel
    let clock: SurfaceClock
    @State private var baked: (key: Int, image: UIImage?) = (.min, nil)

    var body: some View {
        let remaining = S4MergeBoard.pourCap - model.merge.pours
        let exhausted = remaining <= 0
        // The NEXT pour's ACTUAL deposit under the capture's own schedule —
        // never a hardcoded "+4": an evidence-scaled burst may deposit less
        // (a zero-deposit pour is an accepted honest dud, and the instrument
        // must say so before the tap, not after).
        let nextDeposit = S4MergeBoard.effectiveDeposit(model.pourSchedule,
                                                        model.merge.pours)
        let treatment = SixFourCellMechanics.faceTreatment(
            state: 0, tick: (clock.reduceMotion || exhausted) ? 1 : clock.tick)
        let key = (exhausted ? 16 : 0) + treatment
        Button {
            switch model.mergeStep(.pour) {
            case .accept: Haptics.selection()
            case .rejected: Haptics.play(4)   // dropReject
            }
        } label: {
            ZStack {
                Group {
                    if let img = baked.image {
                        Image(uiImage: img)
                            .interpolation(.none)
                            .resizable()
                    } else {
                        Color.clear
                    }
                }
                VStack(spacing: GlobalLattice.gif(1)) {
                    CellText("POUR", rows: 5, cell: GlobalLattice.pt(1),
                             ink: exhausted ? Color(srgb8: SFTheme.ledGhost) : .white)
                    // remaining slices + the next slice's REAL worth ("+4"
                    // derived, less on a scaled short burst, "+0" for a dud).
                    CellText(exhausted ? "\(remaining)/16"
                                       : "\(remaining)/16 +\(nextDeposit)",
                             rows: 3, cell: GlobalLattice.pt(1),
                             ink: Color(srgb8: SFTheme.ledGhost))
                }
            }
            .frame(width: GlobalLattice.gif(16), height: GlobalLattice.gif(12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(exhausted)
        .onChange(of: key, initial: true) { _, k in
            guard k != baked.key else { return }
            baked = (k, Self.bake(exhausted: exhausted, treatment: treatment))
        }
        .accessibilityLabel("Pour: bank the next four-frame slice, worth \(nextDeposit) signal")
        .accessibilityHint("\(remaining) of sixteen slices remain")
    }

    private static func bake(exhausted: Bool, treatment: Int) -> UIImage? {
        let lit = SIMD3<UInt8>(UInt8(SixFourCellMechanics.faceControlInk.r),
                               UInt8(SixFourCellMechanics.faceControlInk.g),
                               UInt8(SixFourCellMechanics.faceControlInk.b))
        let ghost = SFTheme.ledGhost
        let quarter = SIMD3<UInt8>(ghost.x / 4, ghost.y / 4, ghost.z / 4)
        // The FRAME ring: quarter-ink when the resource is spent; else the
        // ghost ring, lit for 1 tick on every 16-rung realize (the D1 BEAT).
        let ring = exhausted ? quarter : (treatment == 1 ? lit : ghost)
        return CellBitmap.image(cols: 16, rows: 12) { c, r in
            (c == 0 || c == 15 || r == 0 || r == 11) ? ring : nil
        }
    }
}
