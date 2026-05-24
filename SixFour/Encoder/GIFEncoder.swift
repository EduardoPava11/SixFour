import Foundation
import simd

enum GIFEncoderError: Error {
    case emptyFrames
    case wrongFrameSize(expected: Int, got: Int)
    case paletteWrongSize(expected: Int, got: Int)
    case mismatchedFrameAndPaletteCount
    case writeFailed(underlying: Error)
}

/// GIF89a encoder for SixFour: fixed 64×64, 64 frames.
///
/// Two modes:
///   - **Per-frame** (`encode(frames:perFramePalettes:to:)`): each frame writes
///     its own 256-entry Local Color Table. ~49 KB of palette data per GIF.
///   - **Global** (`encode(frames:globalPalette:to:)`): one 256-entry Global
///     Color Table in the file header; frames carry no palette. ~768 B of
///     palette data per GIF (≈48 KB smaller).
///
/// Disposal method 1 (do not dispose) in both modes — every frame fully
/// overwrites the canvas, so no transparency tricks are needed.
struct GIFEncoder {
    let width: Int
    let height: Int
    let frameDelayCentiseconds: UInt16

    init(width: Int = 64, height: Int = 64, fps: Int = 20) {
        self.width = width
        self.height = height
        let cs = max(1, 100 / fps)
        self.frameDelayCentiseconds = UInt16(cs)
    }

    /// `frames[i]`: row-major UInt8 indices in 0...255 for that frame.
    /// `perFramePalettes[i]`: 256 sRGB triplets, the local color table for frame i.
    func encode(
        frames: [[UInt8]],
        perFramePalettes: [[SIMD3<UInt8>]],
        to url: URL
    ) throws {
        guard !frames.isEmpty else { throw GIFEncoderError.emptyFrames }
        guard frames.count == perFramePalettes.count else {
            throw GIFEncoderError.mismatchedFrameAndPaletteCount
        }
        let pixelCount = width * height
        for f in frames where f.count != pixelCount {
            throw GIFEncoderError.wrongFrameSize(expected: pixelCount, got: f.count)
        }
        for p in perFramePalettes where p.count != 256 {
            throw GIFEncoderError.paletteWrongSize(expected: 256, got: p.count)
        }

        var data = Data()
        data.append(contentsOf: [0x47, 0x49, 0x46, 0x38, 0x39, 0x61])  // "GIF89a"

        // Logical screen descriptor: NO global color table.
        // Packed: bit 7 = GCT flag (0), bits 4-6 = color resolution (7 → 8 bits/primary),
        // bit 3 = sort (0), bits 0-2 = GCT size (ignored when flag is 0).
        data.append(contentsOf: u16(width))
        data.append(contentsOf: u16(height))
        data.append(0x70)
        data.append(0x00)  // background color index (irrelevant w/o GCT)
        data.append(0x00)  // pixel aspect ratio

        data.append(contentsOf: netscapeLoop(count: 0))

        for (i, frame) in frames.enumerated() {
            let palette = perFramePalettes[i]
            data.append(contentsOf: graphicsControl(delay: frameDelayCentiseconds))
            data.append(contentsOf: imageDescriptorWithLCT(width: width, height: height))
            data.append(contentsOf: localColorTable(palette))
            data.append(lzwEncode(frame, minCodeSize: 8))
        }

        data.append(0x3B)

        do { try data.write(to: url) }
        catch { throw GIFEncoderError.writeFailed(underlying: error) }
    }

    /// GCT (global color table) mode. Writes one 256-entry palette in the file
    /// header; every frame's image descriptor carries no LCT, so frame indices
    /// resolve through the GCT.
    ///
    /// Requires the caller to have *already remapped* every frame's indices
    /// against the shared palette — typically by passing the merged centroids
    /// + remapped indices from `StageBSinkhorn`.
    func encode(
        frames: [[UInt8]],
        globalPalette: [SIMD3<UInt8>],
        to url: URL
    ) throws {
        guard !frames.isEmpty else { throw GIFEncoderError.emptyFrames }
        guard globalPalette.count == 256 else {
            throw GIFEncoderError.paletteWrongSize(expected: 256, got: globalPalette.count)
        }
        let pixelCount = width * height
        for f in frames where f.count != pixelCount {
            throw GIFEncoderError.wrongFrameSize(expected: pixelCount, got: f.count)
        }

        var data = Data()
        data.append(contentsOf: [0x47, 0x49, 0x46, 0x38, 0x39, 0x61])  // "GIF89a"

        // Logical screen descriptor WITH global color table.
        // Packed: bit 7 = GCT flag (1), bits 4-6 = color resolution (7),
        // bit 3 = sort (0), bits 0-2 = GCT size (7 → 256 entries). 0xF7 total.
        data.append(contentsOf: u16(width))
        data.append(contentsOf: u16(height))
        data.append(0xF7)
        data.append(0x00)  // background color index
        data.append(0x00)  // pixel aspect ratio

        data.append(contentsOf: colorTable(globalPalette))

        data.append(contentsOf: netscapeLoop(count: 0))

        for frame in frames {
            data.append(contentsOf: graphicsControl(delay: frameDelayCentiseconds))
            data.append(contentsOf: imageDescriptorNoLCT(width: width, height: height))
            data.append(lzwEncode(frame, minCodeSize: 8))
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

    /// Image descriptor with NO local color table — frames resolve indices
    /// through the file's global color table. Packed byte 0x00.
    private func imageDescriptorNoLCT(width: Int, height: Int) -> [UInt8] {
        imageDescriptor(width: width, height: height, packed: 0x00)
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
