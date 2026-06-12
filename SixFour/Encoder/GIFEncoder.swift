import Foundation
import simd

enum GIFEncoderError: Error {
    case wrongFrameSize(expected: Int, got: Int)
    case paletteWrongSize(expected: Int, got: Int)
    case mismatchedFrameAndPaletteCount
    /// The per-frame index volume failed the `CompleteVoxelVolume` check:
    /// wrong frame count, a short frame, or a frame missing a palette index.
    case incompleteVoxelVolume
    /// A per-frame palette slot was not statistically significant (backed by
    /// fewer than `SixFourSignificance.minPopulation` pixels), or the cells
    /// failed mass conservation — the `SignificantVoxelVolume` brand rejected
    /// it. Unreachable on the SixFour shape (4096 ≥ 2·256); fail loud rather
    /// than ship an outlier-backed palette.
    case insignificantVoxelVolume
    case writeFailed(underlying: Error)
}

/// GIF89a encoder for SixFour: fixed 64×64, 64 frames.
///
/// One mode — **per-frame** (`encode(volume:perFramePalettes:to:)`): each frame
/// writes its own 256-entry Local Color Table (~49 KB of palette data per GIF),
/// gated on a `CompleteVoxelVolume` so the frames are provably complete (every
/// frame uses all 256 colours — the full 64×64×64 voxel volume). The former
/// shared Global-Color-Table path was removed with the cross-frame Sinkhorn
/// merge; collapsing 64 frames onto one palette is the opposite of "full of
/// colours".
///
/// Disposal method 1 (do not dispose) — every frame fully overwrites the
/// canvas, so no transparency tricks are needed.
struct GIFEncoder {
    /// SOURCE frame dimensions (the working cube face, 64). Frames are validated +
    /// brand-gated at this size; the emitted GIF is `width·upscale` (see `upscale`).
    let width: Int
    let height: Int
    /// Export index-replication factor (`SixFourExport.upscaleFactor` = 4 → a 256²
    /// GIF). 1 = no upscale. Replication is nearest-neighbour in the INDEX domain at
    /// emit time, so the per-frame palette / colour tables are byte-identical and no
    /// transparency is introduced (`Spec.Export.lawReplicatePreservesUsedSet`).
    let upscale: Int
    let frameDelayCentiseconds: UInt16

    init(width: Int = 64, height: Int = 64, fps: Int = 20, upscale: Int = 1) {
        self.width = width
        self.height = height
        self.upscale = max(1, upscale)
        let cs = max(1, 100 / fps)
        self.frameDelayCentiseconds = UInt16(cs)
    }

    /// Per-frame Local Color Table mode, gated on completeness.
    ///
    /// `volume`: a `CompleteVoxelVolume` — the type itself proves there are
    /// exactly `T` frames, each `pixelsPerFrame` indices long, and each frame
    /// surjective onto all `K` colours. An incomplete volume cannot be
    /// constructed, so it cannot reach this encoder.
    /// `perFramePalettes[i]`: 256 sRGB triplets, the local color table for frame i.
    /// `comment`: optional text embedded as a GIF89a **Comment Extension**
    /// (`0x21 0xFE`). It travels inside the file (so it survives AirDrop) and is
    /// readable by `exiftool file.gif` (the `Comment` tag) or `strings`. SixFour
    /// uses it to stamp each GIF with its render + benchmark metadata so the
    /// numbers don't have to be copied out of Console.
    func encode(
        volume: CompleteVoxelVolume,
        perFramePalettes: [[SIMD3<UInt8>]],
        to url: URL,
        comment: String? = nil
    ) throws {
        let frames = volume.frames
        guard frames.count == perFramePalettes.count else {
            throw GIFEncoderError.mismatchedFrameAndPaletteCount
        }
        let pixelCount = width * height
        for f in frames where f.count != pixelCount {
            throw GIFEncoderError.wrongFrameSize(expected: pixelCount, got: f.count)
        }
        // Emitted dimensions: the source frame replicated `upscale`× per axis. Frames
        // stay SOURCE-sized (so the completeness/significance brand holds on the 64²
        // source); replication happens per frame just before LZW (below).
        let outW = width * upscale
        let outH = height * upscale
        for p in perFramePalettes where p.count != 256 {
            throw GIFEncoderError.paletteWrongSize(expected: 256, got: p.count)
        }

        var data = Data()
        data.append(contentsOf: [0x47, 0x49, 0x46, 0x38, 0x39, 0x61])  // "GIF89a"

        // Logical screen descriptor: NO global color table.
        // Packed: bit 7 = GCT flag (0), bits 4-6 = color resolution (7 → 8 bits/primary),
        // bit 3 = sort (0), bits 0-2 = GCT size (ignored when flag is 0).
        data.append(contentsOf: u16(outW))
        data.append(contentsOf: u16(outH))
        data.append(0x70)
        data.append(0x00)  // background color index (irrelevant w/o GCT)
        data.append(0x00)  // pixel aspect ratio

        data.append(contentsOf: netscapeLoop(count: 0))

        // Optional Comment Extension — render/bench metadata that travels with
        // the file (AirDrop-safe, exiftool/strings-readable). Placed before the
        // first frame, after the loop block, per GIF89a convention.
        if let comment, !comment.isEmpty {
            data.append(contentsOf: commentExtension(comment))
        }

        for (i, frame) in frames.enumerated() {
            let palette = perFramePalettes[i]
            // 1→upscale² index replication (nearest, palette untouched). At upscale=1
            // this is the identity. `SixFourExport.replicate` is golden-pinned.
            let emitted = upscale > 1
                ? SixFourExport.replicate(frame, side: width, factor: upscale)
                : frame
            data.append(contentsOf: graphicsControl(delay: frameDelayCentiseconds))
            data.append(contentsOf: imageDescriptorWithLCT(width: outW, height: outH))
            data.append(contentsOf: localColorTable(palette))
            data.append(lzwEncode(emitted, minCodeSize: 8))
        }

        data.append(0x3B)

        do { try data.write(to: url) }
        catch { throw GIFEncoderError.writeFailed(underlying: error) }
    }

    /// **Global Color Table mode** (GIFB / 16³ working copies): ONE 256-entry palette
    /// shared by every frame, written once as the GCT. Unlike `encode(volume:…)`, frames
    /// may use any SUBSET of the table — there is **no completeness brand**, because a
    /// global-collapse GIF (every frame re-indexed onto one palette, `LadderGIF
    /// .reindexCubeToGlobal`) is precisely the case the per-frame mode rejects. This is
    /// the encoder half of SIXFOUR-WIDGETS Family 1's global ladder rungs.
    ///
    /// `frames[i]`: `width·height` palette indices (each < 256), NOT gated for
    /// completeness. `globalPalette`: 256 sRGB triplets, the Global Color Table.
    func encodeGlobal(
        frames: [[UInt8]],
        globalPalette: [SIMD3<UInt8>],
        to url: URL,
        comment: String? = nil
    ) throws {
        guard globalPalette.count == 256 else {
            throw GIFEncoderError.paletteWrongSize(expected: 256, got: globalPalette.count)
        }
        let pixelCount = width * height
        for f in frames where f.count != pixelCount {
            throw GIFEncoderError.wrongFrameSize(expected: pixelCount, got: f.count)
        }
        let outW = width * upscale
        let outH = height * upscale

        var data = Data()
        data.append(contentsOf: [0x47, 0x49, 0x46, 0x38, 0x39, 0x61])  // "GIF89a"

        // Logical screen descriptor WITH a Global Color Table.
        // Packed 0xF7: bit7 GCT=1, bits4-6 colorRes=7 (8 bits/primary), bit3 sort=0,
        // bits0-2 GCT size=7 → 2^(7+1)=256 entries.
        data.append(contentsOf: u16(outW))
        data.append(contentsOf: u16(outH))
        data.append(0xF7)
        data.append(0x00)  // background color index (into the GCT)
        data.append(0x00)  // pixel aspect ratio
        data.append(contentsOf: colorTable(globalPalette))   // the 768-byte GCT

        data.append(contentsOf: netscapeLoop(count: 0))
        if let comment, !comment.isEmpty {
            data.append(contentsOf: commentExtension(comment))
        }

        for frame in frames {
            // 1→upscale² index replication (nearest, palette untouched); identity at upscale=1.
            let emitted = upscale > 1
                ? SixFourExport.replicate(frame, side: width, factor: upscale)
                : frame
            data.append(contentsOf: graphicsControl(delay: frameDelayCentiseconds))
            // Image descriptor with NO Local Color Table (packed 0x00) — use the GCT.
            data.append(contentsOf: imageDescriptor(width: outW, height: outH, packed: 0x00))
            data.append(lzwEncode(emitted, minCodeSize: 8))
        }

        data.append(0x3B)

        do { try data.write(to: url) }
        catch { throw GIFEncoderError.writeFailed(underlying: error) }
    }

    // MARK: - Block builders

    private func u16(_ v: Int) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]
    }

    private func localColorTable(_ palette: [SIMD3<UInt8>]) -> [UInt8] {
        colorTable(palette)
    }

    /// 768-byte palette block (256 × RGB). Shared by both LCT and GCT writers.
    private func colorTable(_ palette: [SIMD3<UInt8>]) -> [UInt8] {
        var table = [UInt8](repeating: 0, count: 256 * 3)
        for i in 0..<256 {
            let c = palette[i]
            let base = i * 3
            table[base + 0] = c.x
            table[base + 1] = c.y
            table[base + 2] = c.z
        }
        return table
    }

    /// GIF89a Comment Extension: `0x21 0xFE`, then UTF-8 text in ≤255-byte
    /// sub-blocks, then a `0x00` terminator. Read by `exiftool` / `strings`.
    private func commentExtension(_ text: String) -> [UInt8] {
        var out: [UInt8] = [0x21, 0xFE]
        let bytes = Array(text.utf8)
        var i = 0
        while i < bytes.count {
            let chunk = min(255, bytes.count - i)
            out.append(UInt8(chunk))
            out.append(contentsOf: bytes[i..<(i + chunk)])
            i += chunk
        }
        out.append(0x00)
        return out
    }

    private func netscapeLoop(count: UInt16) -> [UInt8] {
        [
            0x21, 0xFF, 0x0B,
            0x4E, 0x45, 0x54, 0x53, 0x43, 0x41, 0x50, 0x45,
            0x32, 0x2E, 0x30,
            0x03, 0x01,
            UInt8(count & 0xFF), UInt8((count >> 8) & 0xFF),
            0x00
        ]
    }

    private func graphicsControl(delay: UInt16) -> [UInt8] {
        // Disposal method 1 (do not dispose) — every frame fully overwrites the canvas.
        // Packed: bits 4-2 = disposal = 001, bit 1 = user input = 0, bit 0 = transparent = 0
        let packed: UInt8 = 0x04
        return [
            0x21, 0xF9, 0x04,
            packed,
            UInt8(delay & 0xFF), UInt8((delay >> 8) & 0xFF),
            0x00,
            0x00
        ]
    }

    private func imageDescriptorWithLCT(width: Int, height: Int) -> [UInt8] {
        // Packed: bit 7 = LCT (1), bit 6 = interlace (0), bit 5 = sort (0),
        // bits 0-2 = size (7 → 256 entries). 0x87 total.
        imageDescriptor(width: width, height: height, packed: 0x87)
    }

    private func imageDescriptor(width: Int, height: Int, packed: UInt8) -> [UInt8] {
        [
            0x2C,
            0x00, 0x00, 0x00, 0x00,
            UInt8(width & 0xFF), UInt8((width >> 8) & 0xFF),
            UInt8(height & 0xFF), UInt8((height >> 8) & 0xFF),
            packed
        ]
    }

    // MARK: - LZW (standard GIF variable-code-size)

    private func lzwEncode(_ pixels: [UInt8], minCodeSize: UInt8) -> Data {
        var result = Data()
        result.append(minCodeSize)

        let clearCode = 1 << Int(minCodeSize)
        let endCode = clearCode + 1
        let maxCode = 4095

        var dictionary = [Data: Int]()
        var codeSize = Int(minCodeSize) + 1
        var nextCode = endCode + 1

        var bitBuffer: UInt32 = 0
        var bitsInBuffer = 0
        var subBlock = Data()

        func flushSubBlock() {
            if !subBlock.isEmpty {
                result.append(UInt8(subBlock.count))
                result.append(subBlock)
                subBlock.removeAll(keepingCapacity: true)
            }
        }

        func outputCode(_ code: Int) {
            bitBuffer |= UInt32(code) << bitsInBuffer
            bitsInBuffer += codeSize
            while bitsInBuffer >= 8 {
                subBlock.append(UInt8(bitBuffer & 0xFF))
                bitBuffer >>= 8
                bitsInBuffer -= 8
                if subBlock.count == 255 { flushSubBlock() }
            }
        }

        func initDict() {
            dictionary.removeAll(keepingCapacity: true)
            for i in 0..<clearCode {
                dictionary[Data([UInt8(i)])] = i
            }
            nextCode = endCode + 1
            codeSize = Int(minCodeSize) + 1
        }

        initDict()
        outputCode(clearCode)

        // LZW invariant: every `current` value that reaches an emission point was
        // either the single-pixel string we just initialised (always in the dict
        // after `initDict`) or a previously-stored `next`. So the dictionary
        // lookups below are guaranteed to succeed; the `?? clearCode` arms are
        // unreachable but cheaper than `!` for both readers and the linter.
        var current = Data()
        for pixel in pixels {
            var next = current
            next.append(pixel)
            if dictionary[next] != nil {
                current = next
            } else {
                outputCode(dictionary[current] ?? clearCode)
                if nextCode <= maxCode {
                    dictionary[next] = nextCode
                    nextCode += 1
                    if nextCode > (1 << codeSize) && codeSize < 12 {
                        codeSize += 1
                    }
                } else {
                    outputCode(clearCode)
                    initDict()
                }
                current = Data([pixel])
            }
        }
        if !current.isEmpty {
            outputCode(dictionary[current] ?? clearCode)
        }
        outputCode(endCode)
        if bitsInBuffer > 0 {
            subBlock.append(UInt8(bitBuffer & 0xFF))
        }
        flushSubBlock()
        result.append(0x00)
        return result
    }
}
