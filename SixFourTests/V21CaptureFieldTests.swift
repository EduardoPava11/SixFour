import Testing
import Foundation
import simd
@testable import SixFour

/// Gates the V2.1 capture-to-tensor export: the probability field built from a committed burst, and the
/// NumPy `.npy` writer (which must be byte-valid or `numpy.load` fails on the training side).
struct V21CaptureFieldTests {

    // MARK: fromCapture (burst -> probability field)

    /// Every spatial bin sees exactly `frames` observations per channel: the field totals to
    /// `pixels · 3 · frames`, and a bin that is the same colour every frame is a spike at that value.
    @Test func fromCaptureCountsEveryFrameOnce() {
        let side = 2, frames = 2
        // Two palettes (frame 0, frame 1), each [black, white].
        let pal: [SIMD3<UInt8>] = [SIMD3(0, 0, 0), SIMD3(255, 255, 255)]
        let palettes = [pal, pal]
        // cube layout t·side² + y·side + x. Cell 0 is black in both frames (a spike).
        let cube: [UInt8] = [
            0, 1, 0, 1,   // frame 0
            0, 0, 1, 1,   // frame 1
        ]
        let f = V21FieldData.fromCapture(indexCube: cube, palettesPerFrame: palettes, side: side)
        #expect(f != nil)
        guard let f else { return }
        #expect(f.side == side && f.nLevels == 256)
        #expect(f.counts.reduce(0) { $0 + Int($1) } == side * side * 3 * frames)
        // Cell 0, channel R (level 0 = black): both frames -> count 2 (a spike).
        let r0 = Array(f.curve(cell: 0, channel: 0))
        #expect(r0[0] == 2)
        #expect(r0[1 ..< 256].allSatisfy { $0 == 0 })
        // Cell 1: black (frame0 idx0) then black (frame1 idx0)? frame1 cell1 idx=0 -> black; frame0 cell1 idx=1 -> white.
        let r1 = Array(f.curve(cell: 1, channel: 0))
        #expect(r1[0] == 1 && r1[255] == 1)   // one black, one white observation
    }

    /// A malformed cube (too short) is rejected.
    @Test func fromCaptureRejectsShortCube() {
        let pal: [SIMD3<UInt8>] = [SIMD3(0, 0, 0)]
        #expect(V21FieldData.fromCapture(indexCube: [0, 0], palettesPerFrame: [pal, pal], side: 2) == nil)
    }

    // MARK: .npy writer

    /// The `.npy` is a valid NumPy v1.0 file: magic, version, 64-aligned header, `<i4` dtype, correct
    /// shape, and exactly `count · 4` data bytes. (Parsed back the way numpy parses it.)
    @Test func npyIsValidNumpyV1() {
        let field = V21FieldData(side: 2, nLevels: 4,
                                 counts: Array(0 ..< (2 * 2 * 3 * 4)).map { Int32($0) })
        let data = [UInt8](V21Tensor.npyData(field))

        // Magic (0x93 then ASCII "NUMPY") + version 1.0. (0x93 is a single byte, not UTF-8 U+0093.)
        #expect(Array(data[0 ..< 6]) == [0x93] + Array("NUMPY".utf8))
        #expect(data[6] == 1 && data[7] == 0)

        // Header length (little-endian uint16), and total header block is 64-aligned.
        let hlen = Int(data[8]) | (Int(data[9]) << 8)
        #expect((10 + hlen) % 64 == 0)

        // Header dict: little-endian int32, C order, the declared shape.
        let header = String(bytes: data[10 ..< 10 + hlen], encoding: .ascii) ?? ""
        #expect(header.contains("'descr': '<i4'"))
        #expect(header.contains("'fortran_order': False"))
        #expect(header.contains("'shape': (2, 2, 3, 4)"))
        #expect(header.hasSuffix("\n"))

        // Data payload is exactly count int32s.
        let payload = data.count - (10 + hlen)
        #expect(payload == field.counts.count * 4)
        // First element round-trips little-endian (counts[0] == 0).
        #expect(data[10 + hlen] == 0 && data[10 + hlen + 1] == 0)
    }

    /// The share bundle includes the tensor URL (and the GIF when present).
    @Test func shareItemsIncludeTensor() {
        let field = V21FieldData(side: 2, nLevels: 4, counts: [Int32](repeating: 1, count: 2 * 2 * 3 * 4))
        let items = V21Export.shareItems(field: field, gifURL: nil)
        let urls = items.compactMap { $0 as? URL }
        #expect(urls.contains { $0.pathExtension == "npy" })
    }
}
