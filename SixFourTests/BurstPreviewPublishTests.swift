import Testing
import Foundation
import simd
@testable import SixFour

/// THE FREEZE FIX's publish-path pin (THE DESIGN E7, 2026-07-08). During `.capturing`
/// the `CoalescingFrameRenderer` closure now ALWAYS runs `makeQuantizedPreviewImage`,
/// because σ carries NO UIImage — the pyramid's only food is the index tile + palette
/// (`previewIndexTile`/`previewPalette` → `surface.previewTile`), and the old
/// non-quantized branch published `indices = []`, starving the surface for the whole
/// 3.2 s burst. These tests pin the pure part: a valid burst tile through the quantized
/// path yields a FULL index tile + palette (the burst is the show), and the guard's
/// empty-indices starvation is exactly what the raw path used to produce.
struct BurstPreviewPublishTests {

    /// A deterministic synthetic 64² OKLab tile with enough colour spread for the
    /// maximin-256 quantizer (a smooth L/a/b gradient — in-gamut, k-coverable).
    private static func syntheticTile() -> OKLabTile {
        let side = 64
        var px = [SIMD3<Float>]()
        px.reserveCapacity(side * side)
        for y in 0 ..< side {
            for x in 0 ..< side {
                let l = 0.15 + 0.7 * Float(y) / Float(side - 1)
                let a = -0.12 + 0.24 * Float(x) / Float(side - 1)
                let b = -0.10 + 0.20 * Float((x + y) % side) / Float(side - 1)
                px.append(SIMD3(l, a, b))
            }
        }
        return OKLabTile(side: side, pixels: px, captureNanos: 0, palette: [], finalShift: 0)
    }

    /// The quantized publish path feeds the pyramid: 4096 indices + a 256-colour palette
    /// + a drawable image, for both error-diffusion modes and serpentine on/off.
    @Test func quantizedPathPublishesFullIndexTile() {
        let tile = Self.syntheticTile()
        for (mode, serpentine) in [(0, false), (0, true), (1, false)] {
            let frame = CaptureViewModel.makeQuantizedPreviewImage(
                from: tile, mode: mode, serpentine: serpentine)
            #expect(frame.indices.count == 64 * 64,
                    "burst publish must carry a full index tile (mode \(mode))")
            #expect(frame.palette.count == 256,
                    "burst publish must carry the paired 256-colour palette")
            #expect(frame.image != nil)
        }
    }

    /// A malformed tile (wrong pixel count) degrades to the EMPTY publish — the exact
    /// shape the `onFrame` guard drops. This is the starvation signature the freeze fix
    /// removed from the happy path; it must remain confined to genuinely broken frames.
    @Test func malformedTileDegradesToEmptyIndices() {
        let bad = OKLabTile(side: 64, pixels: [SIMD3<Float>(0.5, 0, 0)],
                            captureNanos: 0, palette: [], finalShift: 0)
        let frame = CaptureViewModel.makeQuantizedPreviewImage(from: bad, mode: 0, serpentine: false)
        #expect(frame.indices.isEmpty)
        #expect(frame.image == nil)
    }

    /// The σ-side of the same path: `InvertedPyramidField.sums64` (what the pyramid pools
    /// from the published indices) resolves every published index through the paired
    /// palette — so a full publish is exactly a full 64×64×3 sums carrier.
    @MainActor
    @Test func publishedIndicesPoolIntoSums() {
        let tile = Self.syntheticTile()
        let frame = CaptureViewModel.makeQuantizedPreviewImage(from: tile, mode: 0, serpentine: false)
        let sums = InvertedPyramidField.sums64(from: frame.indices, palette: frame.palette)
        #expect(sums.count == 64 * 64 * 3)
        // The gradient tile cannot quantize to all-black: the pooled carrier has energy.
        #expect(sums.reduce(0, +) > 0)
    }
}
