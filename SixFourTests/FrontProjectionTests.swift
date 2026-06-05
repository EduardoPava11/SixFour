import Testing
import Foundation
import CoreGraphics
import ImageIO
import simd
@testable import SixFour

/// Parity gate for the Review hero's FRONT-PROJECTION (#5): the 2D hero reconstructs
/// each frame as `pixel(x,y,t) = palette[t][indices[t][y·64 + x]]` instead of decoding
/// the `.gif`. This proves that law equals what the verified Zig encoder
/// (`s4_gif_assemble`) actually wrote — i.e. the front-projected hero is byte-identical
/// to the on-disk GIF, so the unified surface (hero ≡ cube ≡ palette) cannot silently
/// drift from the shared file. Per SIXFOUR-SPEC-METHODOLOGY: a Layer 0-2 round-trip.
struct FrontProjectionTests {

    /// Read a decoded CGImage into a top-left-origin RGBA8 buffer. `CGContext` is
    /// bottom-left origin, so we flip rows back to top-left to match the GIF's
    /// `y·64 + x` convention.
    private func topLeftRGBA(_ cg: CGImage) -> [UInt8]? {
        let w = cg.width, h = cg.height
        var flipped = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: &flipped, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: cs, bitmapInfo: info) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        // flipped is bottom-left origin; restore top-left.
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            let src = (h - 1 - y) * w * 4
            let dst = y * w * 4
            for b in 0..<(w * 4) { out[dst + b] = flipped[src + b] }
        }
        return out
    }

    @Test func frontProjectionEqualsEncodedAndDecodedBytes() throws {
        let side = SixFourShape.W            // 64
        let k = SixFourShape.K               // 256
        let frameCount = 2
        let perFrame = side * side

        // A distinct 256-colour palette (per frame; the assembler takes per-frame
        // tables) and a deterministic index map exercising every slot. Explicit loops
        // + pre-typed locals — `SIMD3` inits inside `.map` blow up the type-checker.
        var palette: [SIMD3<UInt8>] = []
        palette.reserveCapacity(k)
        for j in 0..<k {
            let r = UInt8(j & 0xFF), g = UInt8((j * 2) & 0xFF), b = UInt8((j * 3) & 0xFF)
            palette.append(SIMD3<UInt8>(r, g, b))
        }
        var frameIndices: [[UInt8]] = []
        frameIndices.reserveCapacity(frameCount)
        for f in 0..<frameCount {
            var row = [UInt8](repeating: 0, count: perFrame)
            for i in 0..<perFrame { row[i] = UInt8(((i + f * 7) % k) & 0xFF) }
            frameIndices.append(row)
        }

        // Flatten for the Zig encoder (per-frame palettes repeated). Explicit loops —
        // nested `flatMap` array literals blow up the Swift type-checker.
        var flatIndices: [UInt8] = []
        flatIndices.reserveCapacity(frameCount * perFrame)
        for f in 0..<frameCount { flatIndices.append(contentsOf: frameIndices[f]) }

        var paletteFlat: [UInt8] = []
        paletteFlat.reserveCapacity(k * 3)
        for c in palette { paletteFlat.append(c.x); paletteFlat.append(c.y); paletteFlat.append(c.z) }
        var palettesRGBFlat: [UInt8] = []
        palettesRGBFlat.reserveCapacity(frameCount * k * 3)
        for _ in 0..<frameCount { palettesRGBFlat.append(contentsOf: paletteFlat) }
        guard let gif = SixFourNative.gifAssemble(
            indices: flatIndices, palettesRGB: palettesRGBFlat,
            frameCount: frameCount, side: side, k: k, delayCs: 5, comment: nil
        ) else {
            Issue.record("s4_gif_assemble returned nil")
            return
        }

        // Decode the assembled GIF back to frames via ImageIO (the OLD hero path).
        guard let src = CGImageSourceCreateWithData(gif as CFData, nil) else {
            Issue.record("CGImageSourceCreateWithData failed")
            return
        }
        #expect(CGImageSourceGetCount(src) == frameCount)

        for t in 0..<frameCount {
            guard let cg = CGImageSourceCreateImageAtIndex(src, t, nil),
                  let decoded = topLeftRGBA(cg) else {
                Issue.record("decode of frame \(t) failed")
                return
            }
            #expect(cg.width == side && cg.height == side)
            // The front-projection law the hero uses must equal the decoded bytes.
            var mismatches = 0
            for i in 0..<perFrame {
                let expected = palette[Int(frameIndices[t][i])]
                let b = i * 4
                if decoded[b] != expected.x || decoded[b + 1] != expected.y || decoded[b + 2] != expected.z {
                    mismatches += 1
                }
            }
            #expect(mismatches == 0, "frame \(t): \(mismatches)/\(perFrame) px differ between front-projection and decoded GIF")
        }
    }
}
