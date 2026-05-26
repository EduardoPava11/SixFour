import Testing
import Foundation
import simd
@testable import SixFour

/// Byte-level acceptance of `GIFEncoder`. We don't import a third-party GIF
/// parser; we walk the bytes ourselves. The tests pin every header field that
/// matters for the spec (per-frame Local Color Tables, no Global Color Table)
/// so refactors can't silently change what's on the wire. There is one
/// encoder mode now — per-frame LCT, gated on a `CompleteVoxelVolume`.
struct GIFEncoderTests {

    // MARK: - Per-frame (LCT) mode

    @Test func perFrameModeWritesNoGCTAnd64LocalTables() throws {
        let encoder = GIFEncoder(width: 64, height: 64, fps: 20)
        let palettes: [[SIMD3<UInt8>]] = Array(
            repeating: synthPalette256(seed: 1), count: SixFourShape.T
        )
        // The per-frame encoder accepts only a CompleteVoxelVolume — a small
        // 8×8×4 fixture can no longer reach it, which is the gate working.
        let volume = try #require(CompleteVoxelVolume(checkingFrames: surjectiveFrames()))
        let url = scratchURL("perframe.gif")
        try encoder.encode(volume: volume, perFramePalettes: palettes, to: url)

        let bytes = try Data(contentsOf: url)
        try expectMagic(bytes)
        // Logical screen descriptor packed byte at offset 10 = 0x70 → GCT flag OFF.
        #expect(bytes[10] == 0x70, "per-frame mode must NOT write a Global Color Table")
        // Trailer.
        #expect(bytes.last == 0x3B)

        // Walk and count image descriptors (0x2C) — each must carry an LCT
        // packed byte at offset+9 with bit 7 set.
        let lctCount = countImageDescriptors(bytes, expectLCT: true)
        #expect(lctCount == SixFourShape.T, "expected \(SixFourShape.T) image descriptors with LCT; saw \(lctCount)")
    }

    // MARK: - Comment Extension (embedded metadata)

    @Test func commentExtensionIsEmbeddedAndReadable() throws {
        let encoder = GIFEncoder(width: 64, height: 64, fps: 20)
        let palettes = Array(repeating: synthPalette256(seed: 5), count: SixFourShape.T)
        let volume = try #require(CompleteVoxelVolume(checkingFrames: surjectiveFrames()))
        // Multi-line + a >255-byte payload to exercise sub-block chunking.
        let comment = "SixFour 64×64×64 GIF\nextractor=Wu+KM dither=blueNoise/GPU 4ms\n"
            + String(repeating: "x", count: 300)
        let url = scratchURL("comment.gif")
        try encoder.encode(volume: volume, perFramePalettes: palettes, to: url, comment: comment)

        let bytes = try Data(contentsOf: url)
        try expectMagic(bytes)
        #expect(extractGIFComment(bytes) == comment, "embedded comment did not round-trip")
        // No comment → no comment extension.
        let url2 = scratchURL("nocomment.gif")
        try encoder.encode(volume: volume, perFramePalettes: palettes, to: url2)
        #expect(extractGIFComment(try Data(contentsOf: url2)) == nil)
    }

    /// Walk the blocks after the header and return the first Comment Extension's
    /// text (0x21 0xFE … 0x00), mirroring how exiftool reads the Comment tag.
    private func extractGIFComment(_ bytes: Data) -> String? {
        var i = 13  // header (6) + logical screen descriptor (7); no GCT here
        var data = [UInt8]()
        var found = false
        while i < bytes.count {
            let b = bytes[i]
            if b == 0x3B || b == 0x2C { break }   // trailer or first image → done
            guard b == 0x21 else { i += 1; continue }
            let label = bytes[i + 1]; i += 2
            if label == 0xFE { found = true }
            while i < bytes.count {                // sub-blocks until 0x00
                let n = Int(bytes[i]); i += 1
                if n == 0 { break }
                if label == 0xFE { data.append(contentsOf: bytes[i..<(i + n)]) }
                i += n
            }
            if found { break }
        }
        return found ? String(decoding: data, as: UTF8.self) : nil
    }

    // MARK: - LZW round-trip

    /// Encode a complete per-frame volume, run our LZW decoder over the first
    /// frame's LZW image data, and confirm the pixel stream comes back
    /// identical. Guards against future minCodeSize / clear-code regressions.
    /// (Exercised through the only public encode path — per-frame LCT.)
    @Test func lzwRoundTripOnFirstFrame() throws {
        let encoder = GIFEncoder(width: 64, height: 64, fps: 20)
        let frames = surjectiveFrames()
        let palettes = Array(repeating: synthPalette256(seed: 99), count: SixFourShape.T)
        let volume = try #require(CompleteVoxelVolume(checkingFrames: frames))
        let url = scratchURL("lzw.gif")
        try encoder.encode(volume: volume, perFramePalettes: palettes, to: url)

        let bytes = try Data(contentsOf: url)
        let imageDataStart = locateFirstImageDataBlock(bytes)
        let decoded = decodeLZWBlocks(bytes, startingAt: imageDataStart)
        #expect(decoded == frames[0], "LZW round-trip lost pixels on frame 0")
    }

    // MARK: - CompleteVoxelVolume brand (completeness gate)

    @Test func brandAcceptsACompletePerFrameSurjectiveVolume() {
        #expect(CompleteVoxelVolume(checkingFrames: surjectiveFrames()) != nil)
    }

    @Test func brandRejectsWrongFrameCount() {
        var frames = surjectiveFrames()
        frames.removeLast()                                   // 63 frames
        #expect(CompleteVoxelVolume(checkingFrames: frames) == nil)
    }

    @Test func brandRejectsAShortFrame() {
        var frames = surjectiveFrames()
        frames[10].removeLast()                               // 4095 pixels
        #expect(CompleteVoxelVolume(checkingFrames: frames) == nil)
    }

    @Test func brandRejectsANonSurjectiveFrame() {
        var frames = surjectiveFrames()
        frames[0] = frames[0].map { $0 == 255 ? 0 : $0 }      // frame 0 never uses 255
        #expect(CompleteVoxelVolume(checkingFrames: frames) == nil)
    }

    // MARK: - Per-frame surjectivity rescue (producer side)

    @Test func rescueFillsAllSlotsWhenDitherCollapsedToOne() {
        // Pathological dither output: every pixel landed on slot 0.
        let indices = [UInt8](repeating: 0, count: SixFourShape.pixelsPerFrame)
        let (_, fixed) = SignificantSplitFill.rescue(
            palette: distinctPalette(), indices: indices, pixels: gradientPixels()
        )
        #expect(Set(fixed).count == SixFourShape.K, "rescue must use all K slots")
        #expect(CompleteVoxelVolume(checkingFrames:
            Array(repeating: fixed, count: SixFourShape.T)) != nil)
    }

    @Test func rescueIsNoOpOnAnAlreadySurjectiveFrame() {
        let indices = surjectiveFrames()[0]
        let (_, fixed) = SignificantSplitFill.rescue(
            palette: distinctPalette(), indices: indices, pixels: gradientPixels()
        )
        #expect(fixed == indices, "already-surjective frame must be returned unchanged")
    }

    @Test func rescueSucceedsOnAFlatScene() {
        // Adversarial case: every pixel identical. Strict per-frame
        // surjectivity must still produce 256 distinct indices.
        let flat = [SIMD3<Float>](repeating: SIMD3<Float>(0.5, 0, 0),
                                  count: SixFourShape.pixelsPerFrame)
        let indices = [UInt8](repeating: 0, count: SixFourShape.pixelsPerFrame)
        let (_, fixed) = SignificantSplitFill.rescue(
            palette: distinctPalette(), indices: indices, pixels: flat
        )
        #expect(Set(fixed).count == SixFourShape.K)
    }

    // MARK: - Helpers (fixtures + tiny parser)

    /// 4096 OKLab pixels spanning the L axis, for rescue donor-ordering.
    private func gradientPixels() -> [SIMD3<Float>] {
        (0..<SixFourShape.pixelsPerFrame).map { i in
            SIMD3<Float>(Float(i % 256) / 255.0, Float((i * 7) % 256) / 255.0 - 0.5, 0)
        }
    }

    /// 256 distinct OKLab palette colours.
    private func distinctPalette() -> [SIMD3<Float>] {
        (0..<SixFourShape.K).map { SIMD3<Float>(Float($0) / 255.0, 0, 0) }
    }

    private func scratchURL(_ name: String) -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "sixfour-tests", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: name)
    }

    /// The minimal `CompleteVoxelVolume` fixture: `T` frames, each
    /// `pixelsPerFrame` indices, each frame surjective onto `0..<K` (every
    /// palette slot used exactly `pixelsPerFrame / K` = 16 times).
    private func surjectiveFrames() -> [[UInt8]] {
        let frame = (0..<SixFourShape.pixelsPerFrame).map { UInt8($0 % SixFourShape.K) }
        return Array(repeating: frame, count: SixFourShape.T)
    }

    /// Deterministic 256-entry palette derived from a seed — values cover the
    /// gamut so we can spot palette truncation or transposition bugs.
    private func synthPalette256(seed: UInt8) -> [SIMD3<UInt8>] {
        (0..<256).map { i in
            let v = UInt8((i ^ Int(seed)) & 0xFF)
            return SIMD3<UInt8>(v, UInt8(255 - i), UInt8((i + Int(seed)) & 0xFF))
        }
    }

    private func expectMagic(_ bytes: Data) throws {
        #expect(bytes.count > 13)
        #expect(bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) // "GIF"
        #expect(bytes[3] == 0x38 && bytes[4] == 0x39 && bytes[5] == 0x61) // "89a"
    }

    /// Walk the file and count `0x2C` image-descriptor blocks. For each, also
    /// assert the LCT-flag bit matches `expectLCT`.
    private func countImageDescriptors(_ bytes: Data, expectLCT: Bool) -> Int {
        var i = 13  // past header + LSD
        // Skip optional GCT if present.
        if (bytes[10] & 0x80) != 0 {
            i += 768
        }
        var count = 0
        while i < bytes.count {
            let b = bytes[i]
            if b == 0x3B { break }
            if b == 0x21 {
                // Extension introducer: 0x21 label size data... 0x00 terminator.
                i += 2  // intro + label
                while i < bytes.count {
                    let n = Int(bytes[i]); i += 1
                    if n == 0 { break }
                    i += n
                }
            } else if b == 0x2C {
                // Image descriptor: 10 bytes.
                let packed = bytes[i + 9]
                let hasLCT = (packed & 0x80) != 0
                #expect(hasLCT == expectLCT,
                        "image descriptor LCT flag mismatch: expected \(expectLCT), got \(hasLCT)")
                i += 10
                if hasLCT { i += 768 }
                // LZW min code size + sub-blocks.
                i += 1
                while i < bytes.count {
                    let n = Int(bytes[i]); i += 1
                    if n == 0 { break }
                    i += n
                }
                count += 1
            } else {
                i += 1
            }
        }
        return count
    }

    /// Returns the file offset of the LZW min-code-size byte for the first
    /// image descriptor in `bytes`.
    private func locateFirstImageDataBlock(_ bytes: Data) -> Int {
        var i = 13
        if (bytes[10] & 0x80) != 0 { i += 768 }
        while i < bytes.count {
            if bytes[i] == 0x21 {
                i += 2
                while i < bytes.count {
                    let n = Int(bytes[i]); i += 1
                    if n == 0 { break }
                    i += n
                }
            } else if bytes[i] == 0x2C {
                let packed = bytes[i + 9]
                i += 10
                if (packed & 0x80) != 0 { i += 768 }
                return i
            } else {
                i += 1
            }
        }
        return -1
    }

    /// Decode GIF LZW from `start` (min-code-size byte) and return the pixel
    /// stream. Walks until end-of-information code.
    private func decodeLZWBlocks(_ bytes: Data, startingAt start: Int) -> [UInt8] {
        let minCodeSize = Int(bytes[start])
        var i = start + 1
        // Concatenate sub-blocks.
        var lzw = Data()
        while i < bytes.count {
            let n = Int(bytes[i]); i += 1
            if n == 0 { break }
            lzw.append(bytes.subdata(in: i..<(i + n)))
            i += n
        }

        let clearCode = 1 << minCodeSize
        let endCode = clearCode + 1
        var codeSize = minCodeSize + 1
        var nextCode = endCode + 1
        var dict: [Int: [UInt8]] = [:]
        for k in 0..<clearCode { dict[k] = [UInt8(k)] }

        var output: [UInt8] = []
        var bitBuffer: UInt32 = 0
        var bitsInBuffer = 0
        var byteIndex = 0
        var prev: [UInt8] = []

        func readCode() -> Int? {
            while bitsInBuffer < codeSize {
                if byteIndex >= lzw.count { return nil }
                bitBuffer |= UInt32(lzw[byteIndex]) << bitsInBuffer
                byteIndex += 1
                bitsInBuffer += 8
            }
            let mask: UInt32 = (1 << UInt32(codeSize)) - 1
            let code = Int(bitBuffer & mask)
            bitBuffer >>= UInt32(codeSize)
            bitsInBuffer -= codeSize
            return code
        }

        while let code = readCode() {
            if code == clearCode {
                dict.removeAll(keepingCapacity: true)
                for k in 0..<clearCode { dict[k] = [UInt8(k)] }
                codeSize = minCodeSize + 1
                nextCode = endCode + 1
                prev = []
                continue
            }
            if code == endCode { break }
            let entry: [UInt8]
            if let e = dict[code] {
                entry = e
            } else if code == nextCode, let p = prev.first {
                entry = prev + [p]
            } else {
                return output  // corrupt; bail
            }
            output.append(contentsOf: entry)
            if !prev.isEmpty {
                dict[nextCode] = prev + [entry[0]]
                nextCode += 1
                if nextCode == (1 << codeSize) && codeSize < 12 {
                    codeSize += 1
                }
            }
            prev = entry
        }
        return output
    }
}
