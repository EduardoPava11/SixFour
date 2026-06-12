import Foundation
import simd

/// Pure index-domain transforms that turn the captured 64³ cube into any rung of the
/// shareable GIF **LADDER** (SIXFOUR-WIDGETS Family 1: `16³ · 64³-A · 64³-B · 256³-A ·
/// 256³-B`). The GIF is the product, so every rung is one cheap projection of the same
/// cube: 16³ "working copies" are nearly free (subsample, any time), and the global
/// (GIFB) rungs reindex the per-frame cube against ONE collapsed palette.
///
/// These functions are **pure** (index + nearest-colour math) and byte-exact, so any
/// rung is reproducible across devices. The GIF byte-encode (`GIFEncoder`) and the
/// universal "save any-size GIF" export gesture wrap them; they own no I/O themselves.
enum LadderGIF {

    // MARK: Global reindex — the 64³-B / GIFB core

    /// The 256-entry remap LUT taking each per-frame palette slot to its NEAREST global
    /// leaf (squared Q16 OKLab distance, strict `<` ⇒ lowest index on ties — the GIF
    /// index-map rule, mirroring `FarthestPointCollapse.nearestQ16`). `global.count ≤ 256`
    /// so every result fits a `UInt8`. Feed `global =
    /// collapse(...,branching:).branchedLeaves` to get the GIFB table for the chosen radix.
    static func globalRemap(perFramePalette: [OKLabQ16], global: [OKLabQ16]) -> [UInt8] {
        perFramePalette.map { UInt8(FarthestPointCollapse.nearestQ16($0, global)) }
    }

    /// Reindex one frame's per-frame-palette indices through a `globalRemap` LUT, so the
    /// whole burst shares ONE global colour table (GIFB). Pure table lookup — the palette
    /// shrinks to the global leaves, the pixels keep their nearest-colour assignment.
    static func reindexFrame(_ frame: [UInt8], remap: [UInt8]) -> [UInt8] {
        frame.map { remap[Int($0)] }
    }

    /// Reindex the whole 64-frame cube against one global palette (per-frame palettes →
    /// global). Returns the GIFB index volume; the colour table is `global` (→ sRGB8 at
    /// encode time). `perFramePalettes` and `frameIndices` are both length T.
    static func reindexCubeToGlobal(perFramePalettes: [[OKLabQ16]],
                                    frameIndices: [[UInt8]],
                                    global: [OKLabQ16]) -> [[UInt8]] {
        zip(perFramePalettes, frameIndices).map { palette, frame in
            reindexFrame(frame, remap: globalRemap(perFramePalette: palette, global: global))
        }
    }

    // MARK: 16³ working copy — cheap, any-time snapshot

    /// Spatially downsample one square frame from `srcSide` to `dstSide` by block-corner
    /// sampling (nearest: top-left index of each src block) — index-domain, no colour
    /// mixing, so the palette is untouched and the result stays a valid index frame.
    /// Requires `srcSide % dstSide == 0` (64→16 = stride 4); returns the frame unchanged
    /// if not evenly divisible (caller's contract is to pass clean ladder sizes).
    static func spatialDownsample(_ frame: [UInt8], srcSide: Int, dstSide: Int) -> [UInt8] {
        guard dstSide > 0, srcSide % dstSide == 0, frame.count == srcSide * srcSide else {
            return frame
        }
        let stride = srcSide / dstSide
        var out = [UInt8]()
        out.reserveCapacity(dstSide * dstSide)
        for y in 0 ..< dstSide {
            let row = (y * stride) * srcSide
            for x in 0 ..< dstSide { out.append(frame[row + x * stride]) }
        }
        return out
    }

    /// Evenly subsample a sequence of `srcCount` frames down to `dstCount` (64→16 = every
    /// 4th), the temporal half of a 16³ working copy. Deterministic floor-stride indices
    /// `⌊i·n/dstCount⌋`, so the first and a spread across the burst are always kept.
    static func temporalSubsample<T>(_ frames: [T], dstCount: Int) -> [T] {
        let n = frames.count
        guard dstCount > 0, n > 0 else { return [] }
        return (0 ..< dstCount).map { frames[($0 * n) / dstCount] }
    }

    /// A 16³ working copy of the cube: temporally subsample to `frames` frames, then
    /// spatially downsample each to `side`×`side`. Pure index math — pair with the
    /// per-frame palettes (subsampled the same way) to encode a cheap snapshot GIF.
    static func workingCopy(frameIndices: [[UInt8]], srcSide: Int = 64,
                            side: Int = 16, frames: Int = 16) -> [[UInt8]] {
        temporalSubsample(frameIndices, dstCount: frames)
            .map { spatialDownsample($0, srcSide: srcSide, dstSide: side) }
    }

    // MARK: Encode (the producer that ties reindex + collapse + GIFEncoder together)

    /// The collapsed global leaves (Q16 OKLab) → a 256-entry sRGB Global Color Table,
    /// padded with black if fewer than 256 (the GCT is always 256 entries).
    static func paletteToSRGB8(_ leaves: [OKLabQ16]) -> [SIMD3<UInt8>] {
        var out: [SIMD3<UInt8>] = leaves.map { leaf in
            let f = SIMD3<Float>(Float(leaf.x), Float(leaf.y), Float(leaf.z)) / 65536
            return ColorScience.okLabToSRGB8(OKLab(f))
        }
        if out.count < 256 {
            out.append(contentsOf: Array(repeating: SIMD3<UInt8>(0, 0, 0), count: 256 - out.count))
        }
        return Array(out.prefix(256))
    }

    /// Produce a GLOBAL-palette GIF (GIFB / 16³ working copy) end-to-end: reindex the
    /// cube against the collapsed `global` leaves, convert them to the sRGB Global Color
    /// Table, and encode with `GIFEncoder.encodeGlobal`. Feed `global =
    /// collapse(...,branching:).branchedLeaves` for the chosen radix. The whole burst
    /// shares one table, so frames may use any subset — exactly what GIFB is.
    static func encodeGlobalGIF(perFramePalettes: [[OKLabQ16]], frameIndices: [[UInt8]],
                                global: [OKLabQ16], side: Int, fps: Int = 20,
                                upscale: Int = 1, to url: URL, comment: String? = nil) throws {
        let frames = reindexCubeToGlobal(perFramePalettes: perFramePalettes,
                                         frameIndices: frameIndices, global: global)
        let encoder = GIFEncoder(width: side, height: side, fps: fps, upscale: upscale)
        try encoder.encodeGlobal(frames: frames, globalPalette: paletteToSRGB8(global),
                                 to: url, comment: comment)
    }
}
