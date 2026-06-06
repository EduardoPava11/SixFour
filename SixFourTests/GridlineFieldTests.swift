import Testing
import Foundation
import simd
@testable import SixFour

/// Guards for the uniform 4 pt capture grid + the 20 fps refresh checker (Layer 1, no
/// codegen — UI off the deterministic GIF path). The whole capture scene is ONE cell size.
struct GridlineFieldTests {

    /// Every capture element is a whole number of the ONE capture cell — uniform size.
    @Test func everyElementIsWholeCaptureCells() {
        #expect(CaptureGrid.cell == 4)
        #expect(CaptureGrid.previewCells == 64)   // 256 pt
        #expect(CaptureGrid.paletteCells == 16)   // 64 pt
        #expect(CaptureGrid.gearCells == 12)      // 48 pt (HIG tap floor)
        // The preview is exactly 4× the palette — cell-count locked, the core geometry.
        #expect(CaptureGrid.previewCells == 4 * CaptureGrid.paletteCells)
        #expect(CaptureGrid.pt(CaptureGrid.previewCells) == 256)
        #expect(CaptureGrid.pt(CaptureGrid.paletteCells) == 64)
        #expect(CaptureGrid.pt(CaptureGrid.gearCells) == 48)
    }

    /// True `(c + r)` parity checker that inverts on phase, opaque B/W only.
    @Test func checkerAlternatesAndInvertsOnPhase() {
        #expect(GridChecker.color(0, 0, phase: 0) != GridChecker.color(1, 0, phase: 0))
        #expect(GridChecker.color(0, 0, phase: 0) != GridChecker.color(0, 1, phase: 0))
        #expect(GridChecker.color(5, 7, phase: 0) != GridChecker.color(5, 7, phase: 1))
        #expect(GridChecker.color(5, 7, phase: 0) == GridChecker.color(6, 7, phase: 1))
        let v = GridChecker.color(3, 4, phase: 0)
        #expect(v == GridChecker.white || v == GridChecker.dark)
    }

    /// Elements are CELL-ALIGNED — centred on whole-cell offsets, so the preview, palette
    /// and checker share one grid phase (no sub-cell drift between surfaces).
    @Test func elementsAreCellAligned() {
        let previewOff = (CaptureGrid.cols - CaptureGrid.previewCells) / 2
        #expect(CaptureGrid.previewCenter.x
                == CaptureGrid.pt(previewOff) + CaptureGrid.pt(CaptureGrid.previewCells) / 2)
        let paletteOff = (CaptureGrid.cols - CaptureGrid.paletteCells) / 2
        #expect(CaptureGrid.paletteCenter.x
                == CaptureGrid.pt(paletteOff) + CaptureGrid.pt(CaptureGrid.paletteCells) / 2)
        // Preview and palette are both horizontally centred ⇒ share the same column axis.
        #expect(CaptureGrid.previewCenter.x == CaptureGrid.paletteCenter.x)
    }

    /// The checker bitmap covers the whole screen (ceil to whole cells, ≥ screen size).
    @Test func checkerCoversScreen() {
        #expect(CaptureGrid.pt(CaptureGrid.cols) >= CaptureGrid.screenW)
        #expect(CaptureGrid.pt(CaptureGrid.rows) >= CaptureGrid.screenH)
        #expect(GridChecker.image(phase: 0) != nil)
    }
}
