import Foundation
import Testing
import simd
@testable import SixFour

/// `Spec.SuperResPalette`'s ≤K brand, app-side (2026-07-11 link-ledger wave 1):
/// invented detail is free only as INDEX detail inside each frame's ≤K table —
/// never a (K+1)th colour. The brand predicate guards the model-output adapter,
/// and the wire (`Loop.gifBytes`) refuses k > 256 outright.
struct SuperResPaletteBrandTests {

    @Test func brandHoldsOnLawfulOutputAndCatchesViolations() {
        let pal: [OKLabQ16] = [OKLabQ16(0, 0, 0), OKLabQ16(65536, 0, 0)]
        let out = ModelFloor.output(perFramePalettes: [pal], indexPlanes: [[0, 1, 1, 0]])
        #expect(ModelFloor.paletteBrandHolds(out))
        // An index outside its frame's table breaks the brand.
        let bad = SixFourModelOutput(palettes: out.palettes, indexPlanes: [[0, 2]])
        #expect(!ModelFloor.paletteBrandHolds(bad))
        // More than K distinct colours breaks the brand (tiny k for the test).
        let wide = SixFourModelOutput(
            palettes: [[SIMD3<Int>(0, 0, 0), SIMD3<Int>(1, 0, 0), SIMD3<Int>(2, 0, 0)]],
            indexPlanes: [[0]])
        #expect(!ModelFloor.paletteBrandHolds(wide, k: 2))
    }

    @Test func wireRefusesMoreThan256Colours() {
        // A 257-colour palette can exist as a value, but the GIF89a wire must
        // refuse it — never clamp, never truncate.
        let leaves = (0..<257).map { SIMD3<Int32>(Int32($0), 0, 0) }
        let palette = Palette(leavesQ16: leaves)
        guard let plane = IndexPlane(side: 16, indices: [UInt8](repeating: 0, count: 256)),
              let cel = Cel(plane: plane, rung: .w16),
              let loop = Loop(cels: [cel], palettes: [palette]) else {
            Issue.record("construction failed"); return
        }
        #expect(loop.gifBytes() == nil)
    }
}
