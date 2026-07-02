import Testing
@testable import SixFour

/// I/O gates for the capture-seam somatic gene (`CaptureGene`, workflow B2.3
/// live wiring): burst tiles → interleaved Q16 volume → one fused GPU dispatch.
struct CaptureGeneTests {

    /// Build burst-shaped tiles from a synth volume. Q16 → Float division by
    /// 2¹⁶ is exact (power-of-two scale, values fit the 24-bit mantissa), so
    /// the volume assembly must round-trip the ints EXACTLY.
    private func tiles(from volume: [Int32], frames: Int, side: Int) -> [OKLabTile] {
        (0 ..< frames).map { f in
            let base = f * side * side * 3
            let pixels = (0 ..< side * side).map { p in
                SIMD3<Float>(Float(volume[base + p * 3]) / 65536,
                             Float(volume[base + p * 3 + 1]) / 65536,
                             Float(volume[base + p * 3 + 2]) / 65536)
            }
            return OKLabTile(side: side, pixels: pixels, captureNanos: UInt64(f),
                             palette: [], finalShift: 0)
        }
    }

    @Test func volumeAssemblyRoundTripsTheQ16Ints() throws {
        let volume = try #require(SixFourNative.synthBurst(
            seed: 0x4232_3400, mode: 0, frameCount: 16, side: 16))
        let assembled = try #require(CaptureGene.volume(
            from: tiles(from: volume, frames: 16, side: 16)))
        #expect(assembled == volume)
    }

    @Test func volumeAssemblyRejectsUntrainableBursts() {
        let ok = tiles(from: [Int32](repeating: 0, count: 4 * 4 * 4 * 3), frames: 4, side: 4)
        #expect(CaptureGene.volume(from: ok) != nil)
        #expect(CaptureGene.volume(from: []) == nil)                    // empty
        #expect(CaptureGene.volume(from: Array(ok.prefix(3))) == nil)   // odd frame count
    }

    /// The tiles path is bitwise the volume path: training from burst tiles
    /// gives the SAME gene as training on the raw synth volume directly.
    @Test func geneFromTilesIsBitwiseTheVolumePathGene() throws {
        let rung = try #require(RungDispatch())
        let volume = try #require(SixFourNative.synthBurst(
            seed: 0x4232_3401, mode: 0, frameCount: 16, side: 16))
        let gene = try #require(CaptureGene.train(
            tiles: tiles(from: volume, frames: 16, side: 16), rung: rung))
        let direct = try #require(rung.trainOnVolume(
            volume: volume, frames: 16, side: 16, channel: 0))
        #expect(gene.theta.map(\.bitPattern) == direct.theta.map(\.bitPattern))
        #expect(gene.committed == direct.committed)
        #expect(gene.loss.bitPattern == direct.loss.bitPattern)
        #expect(gene.channel == 0 && gene.frames == 16 && gene.side == 16)
    }

    /// The gene is Codable (it persists with the capture bundle) — round-trip
    /// through JSON preserves θ bit patterns.
    @Test func geneRoundTripsThroughJSON() throws {
        let gene = CaptureGene.ThetaUp(
            theta: [0.25, -1e-7, 3.5e4], committed: [1, -2, 3, 0, 0, 0, 7],
            loss: 0.125, floorLoss: 0.5, trainMillis: 12.5,
            channel: 0, frames: 64, side: 64)
        let data = try JSONEncoder().encode(gene)
        let back = try JSONDecoder().decode(CaptureGene.ThetaUp.self, from: data)
        #expect(back.theta.map(\.bitPattern) == gene.theta.map(\.bitPattern))
        #expect(back.committed == gene.committed)
        #expect(back.loss == gene.loss)
    }
}
