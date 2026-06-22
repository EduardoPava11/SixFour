import Testing
import Foundation
@testable import SixFour

/// DEVICE PROOF: the iPhone can MAKE and ENCODE the GIF, camera-free and byte-exact.
///
/// The simulator has no camera, so we never capture; instead we feed the deterministic
/// Haskell golden input (`GifGoldenFixture`) and the deterministic synthetic-burst
/// generator (`s4_synth_burst`) — the synthetic-data-harness the no-camera rule permits.
/// Run on the real iPhone 17 Pro with:
///   xcodebuild test -scheme SixFour -destination 'platform=iOS,id=<UDID>' \
///     -allowProvisioningUpdates -only-testing:SixFourTests/DeviceGifParityTests
/// The same Zig arm64 core runs on Mac and device, so a green run here is the proof the
/// phone reproduces the Mac/Haskell reference bit-for-bit.
struct DeviceGifParityTests {

    /// L1 — MAKE + ENCODE, byte-exact. Encode the committed golden linear-sRGB input
    /// through the FULL device pipeline (widen -> OKLab -> quantize -> FloydSteinberg
    /// dither -> palette -> GIF89a) and assert the bytes equal the Haskell `golden.gif`.
    /// CRITICAL: ditherMode MUST be 0 (FloydSteinberg); the default is 2 (blue-noise),
    /// which needs an STBN mask and would never match the FS golden.
    @Test func encodeBurstMatchesHaskellGoldenGif() {
        var params = SixFourNative.GifEncodeParams()
        params.frameCount = GifGoldenFixture.frameCount
        params.side = GifGoldenFixture.side
        params.k = GifGoldenFixture.k
        params.inputSpace = 0                 // linear-sRGB Float16
        params.lloydIters = GifGoldenFixture.lloydIters
        params.ditherMode = 0                 // FloydSteinberg (no STBN mask)
        params.serpentine = 0
        params.frameDelayCentiseconds = GifGoldenFixture.frameDelayCentiseconds

        guard let gif = SixFourNative.encodeBurst(
            linearHalfs: GifGoldenFixture.goldenInputHalfs,
            stbnMask: nil, comment: nil, params: params
        ) else {
            Issue.record("encodeBurst returned nil (kernel unavailable?)"); return
        }
        #expect(gif == GifGoldenFixture.goldenGif,
                "device GIF bytes (\(gif.count)) != Haskell golden (\(GifGoldenFixture.goldenGif.count))")
    }

    /// L1b — FULL-SHAPE LIVENESS. Synthesize a real 64x64x64 burst from nothing (no
    /// camera), quantize each frame, build local palettes, and assemble a GIF89a.
    /// Proves the device handles the SHIPPING shape end to end. (Lloyd=1: liveness, not
    /// quality.)
    @Test func synthBurstMakesFullShapeGif() {
        let fc: Int32 = 64, sd: Int32 = 64, k = 256
        guard let burst = SixFourNative.synthBurst(seed: 0xA11CE, mode: 0,
                                                   frameCount: fc, side: sd) else {
            Issue.record("synthBurst nil"); return
        }
        let p = Int(sd) * Int(sd)
        #expect(burst.count == Int(fc) * p * 3, "burst shape \(burst.count) != \(Int(fc) * p * 3)")

        var allIndices = [UInt8](); allIndices.reserveCapacity(Int(fc) * p)
        var allPalettes = [UInt8](); allPalettes.reserveCapacity(Int(fc) * k * 3)
        for f in 0..<Int(fc) {
            let frame = Array(burst[(f * p * 3)..<((f + 1) * p * 3)])
            guard let q = SixFourNative.quantizeFrame(oklabQ16: frame, k: k, lloydIters: 1),
                  let pal = SixFourNative.paletteToSRGB8(centroidsQ16: q.centroids, k: k) else {
                Issue.record("quantize/palette nil at frame \(f)"); return
            }
            allIndices.append(contentsOf: q.indices)
            allPalettes.append(contentsOf: pal)
        }
        guard let gif = SixFourNative.gifAssemble(indices: allIndices, palettesRGB: allPalettes,
                                                  frameCount: Int(fc), side: Int(sd), k: k,
                                                  delayCs: 5, comment: nil) else {
            Issue.record("gifAssemble nil"); return
        }
        #expect(gif.count > 6)
        #expect(Array(gif.prefix(6)) == Array("GIF89a".utf8), "not a GIF89a stream")
    }

    /// The synthetic generator is DETERMINISTIC (same seed -> identical bytes), which is
    /// what lets device and Mac agree per seed.
    @Test func synthBurstIsDeterministic() {
        let a = SixFourNative.synthBurst(seed: 0xA11CE, mode: 0, frameCount: 4, side: 32)
        let b = SixFourNative.synthBurst(seed: 0xA11CE, mode: 0, frameCount: 4, side: 32)
        #expect(a != nil && a == b, "synthBurst not deterministic for a fixed seed")
    }
}
