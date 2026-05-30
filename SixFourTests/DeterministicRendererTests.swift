import Testing
import Foundation
import simd
@testable import SixFour

/// Tier-D determinism test for the on-device path: the deterministic renderer
/// (the per-stage Zig core) must produce a brand-valid GIF whose bytes are a
/// pure function of the input — the same burst twice yields the identical
/// SHA-256. This is the guarantee surfaced in the Review screen.
struct DeterministicRendererTests {

    /// 64 synthetic OKLab frames, deterministic, spread across the gamut so the
    /// maximin quantizer produces diverse centroids.
    private func makeTiles() -> [OKLabTile] {
        let side = SixFourShape.W
        let p = side * side
        return (0..<SixFourShape.T).map { f in
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

    @Test("Deterministic render is byte-reproducible (same input → same SHA-256)")
    func reproducible() throws {
        let tiles = makeTiles()
        let renderer = DeterministicRenderer(dither: .default)  // FS error-diffusion, no STBN

        // Sendable collector (the stage callback is @Sendable).
        final class StageLog: @unchecked Sendable {
            private let lock = NSLock()
            private(set) var stages: [DeterministicRenderer.Stage] = []
            func add(_ s: DeterministicRenderer.Stage) { lock.lock(); stages.append(s); lock.unlock() }
        }
        let log = StageLog()
        let a = try renderer.render(tiles: tiles, comment: "test") { log.add($0) }
        let b = try renderer.render(tiles: tiles, comment: "test") { _ in }

        // Headline: identical bytes ⇒ identical fingerprint.
        #expect(a.sha256Hex == b.sha256Hex)
        #expect(a.gifData == b.gifData)
        #expect(a.sha256Hex.count == 64)

        // All five stages ran, in order.
        #expect(log.stages == DeterministicRenderer.Stage.allCases)

        // Output is a real GIF89a.
        #expect(a.gifData.count > 1000)
        #expect(Array(a.gifData.prefix(6)) == Array("GIF89a".utf8))
        #expect(a.gifData.last == 0x3B)  // trailer
    }

    @Test("Deterministic output satisfies the Complete + Significant voxel brands")
    func brandsHold() throws {
        let tiles = makeTiles()
        let renderer = DeterministicRenderer(dither: .default)
        let r = try renderer.render(tiles: tiles, comment: nil) { _ in }

        #expect(r.frameIndices.count == SixFourShape.T)
        #expect(r.cells.count == SixFourShape.T)
        #expect(r.srgbPalettes.allSatisfy { $0.count == SixFourShape.K })

        // CompleteVoxelVolume: every frame surjective onto all 256 colours.
        let volume = CompleteVoxelVolume(checkingFrames: r.frameIndices)
        #expect(volume != nil)

        // SignificantVoxelVolume: every slot backed by ≥ minPopulation pixels,
        // mass conserved — the guarantee the encoder gates on.
        if let volume {
            #expect(SignificantVoxelVolume(complete: volume, cells: r.cells) != nil)
        }

        // Every frame's significance count is the full 256 (the headline).
        for cells in r.cells {
            let significant = cells.filter { $0.count >= SixFourSignificance.minPopulation }.count
            #expect(significant == SixFourShape.K)
        }
    }
}
