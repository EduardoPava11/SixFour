import Foundation
import Testing
import simd
@testable import SixFour

/// UNIT 3's OWNERSHIP SEAM: σ's palette/index arrays are `private(set)` views
/// that only `adopt(_:)` / `adoptLegacy(…)` may populate — so a committed
/// surface can never desync from its typed Loop. These tests pin the seam's
/// semantics; the compiler pins the exclusivity.
struct SurfaceAdoptTests {

    /// A tiny canonical 64-side loop (2 frames, k=4) with sRGB8-canonical palettes.
    private func makeLoop() -> Loop? {
        var seed: UInt64 = 0xC0FF_EE00_0C7A_5005
        func byte() -> UInt8 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return UInt8(truncatingIfNeeded: seed >> 33)
        }
        var cels = [Cel]()
        var palettes = [Palette]()
        for _ in 0..<2 {
            let indices = (0..<(64 * 64)).map { _ in byte() % 4 }
            guard let plane = IndexPlane(side: 64, indices: indices),
                  let cel = Cel(plane: plane, rung: .w64),
                  let palette = Palette(srgb8: (0..<12).map { _ in byte() })
            else { return nil }
            cels.append(cel)
            palettes.append(palette)
        }
        return Loop(cels: cels, palettes: palettes)
    }

    @Test @MainActor func adoptPopulatesEveryViewFromTheValue() {
        guard let loop = makeLoop() else { Issue.record("loop construction failed"); return }
        let surface = Surface()
        #expect(surface.adopt(loop))
        #expect(surface.loop == loop)
        #expect(surface.palettesPerFrame == loop.srgb8Palettes())
        #expect(surface.palette == loop.srgb8Palettes()?.first)
        #expect(surface.indexCube == loop.cels.flatMap { $0.plane.indices })
        // The hot-path reader goes through the view and lands on palette[index]:
        // gifCell(x,y,t) == the loop's own render, projected to sRGB8.
        let (x, y, t) = (5, 7, 1)
        let idx = Int(loop.cels[t].plane.indices[y * 64 + x])
        #expect(surface.gifCell(x, y, t) == surface.palettesPerFrame[t][idx])
    }

    @Test @MainActor func adoptLegacyMarksTheTypedValueAbsent() {
        guard let loop = makeLoop() else { Issue.record("loop construction failed"); return }
        let surface = Surface()
        #expect(surface.adopt(loop))
        // A float-fallback commit replaces the views and clears the value.
        let pals: [[SIMD3<UInt8>]] = [[SIMD3(1, 2, 3), SIMD3(4, 5, 6)]]
        let frames: [[UInt8]] = [[UInt8](repeating: 1, count: 64 * 64)]
        surface.adoptLegacy(palettesPerFrame: pals, frameIndices: frames)
        #expect(surface.loop == nil)
        #expect(surface.palettesPerFrame == pals)
        #expect(surface.palette == pals[0])
        #expect(surface.indexCube.count == 64 * 64)
        // nil frameIndices leaves the previous cube untouched (legacy contract).
        surface.adoptLegacy(palettesPerFrame: pals, frameIndices: nil)
        #expect(surface.indexCube.count == 64 * 64)
    }
}
