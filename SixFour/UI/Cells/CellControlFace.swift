import SwiftUI
import UIKit
import simd

/// THE CONTROL LANGUAGE's image-content face — **BRACKETS** (THE DESIGN D1/E3).
///
/// A control whose content IS an image (the 16² shutter vertex, the Decide hero) must
/// never obscure a content pixel, so its face is four corner brackets drawn in the
/// GUTTER OUTSIDE the tile: arms `armCells` long × 1 cell thick, on a footprint of
/// `side + 2·(gutter + 1)` cells per edge. The bracket rect IS the hit rect (the
/// caller puts `.contentShape(Rectangle())` on the assembled ZStack).
///
/// States are the closed `SixFourCellMechanics` ControlFace algebra — OPAQUE ink
/// transforms, never alpha (`lawFaceNoAlpha`):
///   idle   → ghost brackets, going LIT for exactly 1 tick on every 16-rung realize
///            (the BEAT, `lawBeatIsPoolCadence` — the affordance and the cadence
///            teacher are one element; under reduce-motion the caller passes
///            `reduceMotion: true` and the beat is pinned OFF here — the brackets
///            hold steady ghost, D1's "suppressed under reduce-motion");
///   pressed→ full control-ink inversion (the caller inverts the tile too);
///   busy   → the CellButton red;
///   disabled→ the 2×2 checker over the bracket cells only.
///
/// PERF: the bitmap is baked ONCE per treatment change — `faceTreatment(state:tick:)`
/// only moves when the state changes or the beat edge passes (1 rebake per 4 ticks at
/// worst, and only while idle), never per publish.
struct ControlBrackets: View {
    /// The content tile's side in cells (16 for the shutter vertex).
    let side: Int
    /// Control state ordinal into `SixFourCellMechanics.controlStates`
    /// (0 idle · 1 pressed · 2 busy · 3 disabled).
    let state: Int
    /// The ONE 20 Hz clock — drives the idle BEAT only.
    let tick: Int
    /// Reduce-motion (pass `SurfaceClock.reduceMotion`): pins the idle BEAT off —
    /// the 5 Hz lit-bracket strobe is this face's only motion, so it must not run
    /// for reduce-motion users (D1). All other states are tick-invariant anyway.
    var reduceMotion: Bool = false
    /// Gutter cells between the tile edge and the bracket (1 for the shutter).
    var gutterCells: Int = 1
    /// Bracket arm length in cells (the D1 spec: 3).
    var armCells: Int = 3

    /// The baked face, keyed by the treatment ordinal so identical states never rebake.
    @State private var baked: (treatment: Int, image: UIImage?) = (-1, nil)

    /// Total footprint per edge: tile + gutter + 1-cell bracket on both flanks.
    private var footprint: Int { side + 2 * (gutterCells + 1) }

    var body: some View {
        // Reduce-motion pins the BEAT off by evaluating the treatment at tick 1 —
        // provably beat-free (`SixFourCellMechanics.goldenBeat[1] == false`); only
        // IDLE reads the tick, so pressed/busy/disabled render identically.
        let treatment = SixFourCellMechanics.faceTreatment(state: state,
                                                           tick: reduceMotion ? 1 : tick)
        Group {
            if let img = baked.image {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
            }
        }
        // The footprint is reserved even while the bake is pending, so the pyramid /
        // hero stack never reflows around a transiently empty face.
        .frame(width: GlobalLattice.gif(footprint),
               height: GlobalLattice.gif(footprint))
        .onChange(of: treatment, initial: true) { _, t in
            guard t != baked.treatment else { return }
            baked = (t, Self.bake(footprint: footprint, armCells: armCells, treatment: t))
        }
        .accessibilityHidden(true)
    }

    /// Bake one treatment's bracket bitmap. Only bracket cells are inked; everything
    /// else stays transparent (the tile shows through the ZStack underneath).
    private static func bake(footprint n: Int, armCells: Int, treatment: Int) -> UIImage? {
        let lit = SIMD3<UInt8>(UInt8(SixFourCellMechanics.faceControlInk.r),
                               UInt8(SixFourCellMechanics.faceControlInk.g),
                               UInt8(SixFourCellMechanics.faceControlInk.b))
        let busy = SIMD3<UInt8>(UInt8(SixFourCellMechanics.rejectInk.r),
                                UInt8(SixFourCellMechanics.rejectInk.g),
                                UInt8(SixFourCellMechanics.rejectInk.b))
        let ghost = SFTheme.ledGhost
        return CellBitmap.image(cols: n, rows: n) { c, r in
            guard onBracket(c, r, n: n, arm: armCells) else { return nil }
            switch treatment {
            case 0: return ghost                       // ghost (idle between beats)
            case 1: return lit                         // lit (the BEAT tick)
            case 2: return lit                         // inverted (pressed — full ink; tile inverts too)
            case 3: return busy                        // busy (the CellButton red)
            default:                                   // checker (disabled)
                return ((c / 2) + (r / 2)) % 2 == 0 ? lit : ghost
            }
        }
    }

    /// True iff cell (c,r) lies on one of the four corner brackets: the outermost
    /// ring (row/col 0 or n−1), within `arm` cells of a corner along either axis.
    private static func onBracket(_ c: Int, _ r: Int, n: Int, arm: Int) -> Bool {
        let onEdgeCol = c == 0 || c == n - 1
        let onEdgeRow = r == 0 || r == n - 1
        guard onEdgeCol || onEdgeRow else { return false }
        let nearCornerC = c < arm || c >= n - arm
        let nearCornerR = r < arm || r >= n - arm
        // Horizontal arms live on the edge ROWS near a corner; vertical arms on the
        // edge COLS near a corner. The corner cell itself satisfies both.
        return (onEdgeRow && nearCornerC) || (onEdgeCol && nearCornerR)
    }
}
