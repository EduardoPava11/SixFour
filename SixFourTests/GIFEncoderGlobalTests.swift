import Testing
import Foundation
import simd
import ImageIO
@testable import SixFour

/// Gate for `GIFEncoder.encodeGlobal` — the Global Color Table mode that produces the
/// `64³-B` / 16³ working-copy GIFs (SIXFOUR-WIDGETS Family 1). The defining property:
/// frames may use a SUBSET of the one global table (the per-frame mode forbids that),
/// and the result is a valid, ImageIO-decodable GIF.
struct GIFEncoderGlobalTests {

    private func palette256() -> [SIMD3<UInt8>] {
        var p = [SIMD3<UInt8>](repeating: SIMD3<UInt8>(0, 0, 0), count: 256)
        p[0] = SIMD3<UInt8>(255, 0, 0)
        p[1] = SIMD3<UInt8>(0, 255, 0)
        p[2] = SIMD3<UInt8>(0, 0, 255)
        return p
    }

    @Test func encodeGlobalWritesValidSubsetGIF() throws {
        let enc = GIFEncoder(width: 2, height: 2, fps: 20, upscale: 1)
        // Two 2×2 frames using ONLY indices 0/1/2 — a subset of the 256-entry table.
        let frames: [[UInt8]] = [[0, 1, 2, 0], [2, 0, 1, 1]]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sixfour-global-subset.gif")
        try? FileManager.default.removeItem(at: url)
        try enc.encodeGlobal(frames: frames, globalPalette: palette256(), to: url)

        let bytes = try Data(contentsOf: url)
        // Header + a Global Color Table present (LSD packed 0xF7) + trailer.
        #expect(Array(bytes.prefix(6)) == [0x47, 0x49, 0x46, 0x38, 0x39, 0x61])  // "GIF89a"
        #expect(bytes[10] == 0xF7)            // LSD packed: GCT flag + 256 entries
        #expect(bytes.last == 0x3B)           // trailer
        // GCT (768 bytes) begins immediately after the 13-byte header+LSD.
        #expect(bytes[13] == 255 && bytes[14] == 0 && bytes[15] == 0)   // entry 0 = red

        // Round-trips through ImageIO: a real, decodable 2-frame 2×2 GIF.
        let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetCount(src) == 2)
        let img = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
        #expect(img.width == 2 && img.height == 2)

        try? FileManager.default.removeItem(at: url)
    }

    @Test func encodeGlobalUpscalesViaReplication() throws {
        let enc = GIFEncoder(width: 2, height: 2, fps: 20, upscale: 4)   // emits 8×8
        let frames: [[UInt8]] = [[0, 1, 2, 0]]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sixfour-global-upscale.gif")
        try? FileManager.default.removeItem(at: url)
        try enc.encodeGlobal(frames: frames, globalPalette: palette256(), to: url)

        let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let img = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
        #expect(img.width == 8 && img.height == 8)   // 2 × upscale 4
        try? FileManager.default.removeItem(at: url)
    }

    /// End-to-end producer (SIXFOUR-WIDGETS Family 1): per-frame cube → reindex against a
    /// collapsed global palette → valid global-table GIF. Proves the whole 64³-B / 16³
    /// chain (reindex + sRGB convert + global encode) yields a decodable GIF.
    @Test func encodeGlobalGIFEndToEnd() throws {
        let side = 2
        // 4 frames, each a 4-entry per-frame Q16 OKLab palette; pixels index 0…3.
        let perFrame: [[OKLabQ16]] = (0 ..< 4).map { f in
            (0 ..< 4).map { i in OKLabQ16(Int32((i + f) * 1000), Int32(i * 500), 0) }
        }
        let frameIdx: [[UInt8]] = (0 ..< 4).map { _ in [0, 1, 2, 3] }
        // A 2-entry global palette — every per-frame colour reindexes onto {0,1}.
        let global: [OKLabQ16] = [OKLabQ16(0, 0, 0), OKLabQ16(3000, 1500, 0)]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sixfour-global-e2e.gif")
        try? FileManager.default.removeItem(at: url)

        try LadderGIF.encodeGlobalGIF(perFramePalettes: perFrame, frameIndices: frameIdx,
                                      global: global, side: side, to: url)

        let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetCount(src) == 4)
        let img = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
        #expect(img.width == 2 && img.height == 2)
        // The padded GCT is a full 256 entries (LSD packed 0xF7).
        let bytes = try Data(contentsOf: url)
        #expect(bytes[10] == 0xF7)
        try? FileManager.default.removeItem(at: url)
    }

    @Test func encodeGlobalRejectsWrongPaletteSize() {
        let enc = GIFEncoder(width: 2, height: 2)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sixfour-bad.gif")
        #expect(throws: GIFEncoderError.self) {
            try enc.encodeGlobal(frames: [[0, 0, 0, 0]],
                                 globalPalette: [SIMD3<UInt8>(0, 0, 0)], to: url)
        }
    }
}
