import Foundation
import Testing
import simd
@testable import SixFour

/// UNIT 2's PARITY GATE: the deterministic renderer now derives its shipped
/// bytes from the typed `Loop`, and σ derives its palette/index views from the
/// same value. These tests pin that the typed path is byte-identical to the
/// raw-array path it replaced — the file, the display palettes, and the index
/// cube all come from ONE value and agree exactly. (The pre-existing golden
/// SHA tests independently pin that the bytes did not drift across the swap.)
struct LoopPipelineParityTests {

    /// Deterministic synthetic burst (same recipe as DeterministicRendererTests).
    private func makeTiles(frames: Int = 8) -> [OKLabTile] {
        let side = SixFourShape.W
        let p = side * side
        return (0..<frames).map { f in
            var px = [SIMD3<Float>]()
            px.reserveCapacity(p)
            for i in 0..<p {
                let l = Float((i * 7 + f * 13) % 1000) / 1000.0
                let a = (Float((i * 11 + f * 5) % 800) / 800.0 - 0.5) * 0.8
                let b = (Float((i * 17 + f * 3) % 800) / 800.0 - 0.5) * 0.8
                px.append(SIMD3(l, a, b))
            }
            return OKLabTile(side: side, pixels: px, captureNanos: UInt64(f), palette: [], finalShift: 0)
        }
    }

    @Test func shippedBytesAreTheLoopsBytes() throws {
        let renderer = DeterministicRenderer(dither: .default)
        let result = try renderer.render(tiles: makeTiles(), comment: "parity") { _ in }
        // The file IS the value: re-deriving the bytes from the canonical Loop
        // through the export-replication view reproduces gifData exactly.
        let rederived = result.loop
            .replicated(by: SixFourExport.upscaleFactor)?
            .gifBytes(comment: "parity")
        #expect(rederived == result.gifData)
        // And the canonical loop is 64-side on the w64 rung (delay theorem: 5 cs).
        #expect(result.loop.cels.allSatisfy { $0.plane.side == SixFourShape.W && $0.rung == .w64 })
        #expect(result.loop.cels.first?.delayCs == 5)
    }

    @Test func loopViewsMatchTheLegacyArrays() throws {
        let renderer = DeterministicRenderer(dither: .default)
        let result = try renderer.render(tiles: makeTiles(), comment: nil) { _ in }
        // σ's palette view (Loop.srgb8Palettes) == the legacy srgbPalettes.
        #expect(result.loop.srgb8Palettes() == result.srgbPalettes)
        // σ's index-cube view == the legacy frameIndices, frame for frame.
        #expect(result.loop.cels.map(\.plane.indices) == result.frameIndices)
        // The wire round-trips: decoding the shipped bytes and decimating the
        // planes recovers the canonical indices exactly (replicate ∘ decimate
        // inverse, on the real render — not just the synthetic law test).
        guard let decoded = Loop(gifBytes: result.gifData, rung: .w64) else {
            Issue.record("decode of shipped bytes failed"); return
        }
        let decimated = decoded.cels.map {
            SixFourCaptureFormat.decimate($0.plane.indices,
                                          bigSide: $0.plane.side,
                                          factor: SixFourExport.upscaleFactor)
        }
        #expect(decimated == result.frameIndices)
    }
}
