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

    // MARK: contestedness sidecar (mode margin)

    /// The margin is `peak count - runner-up count` per bin and channel. A spike (one level holds every
    /// observation) has the full margin; a two-way tie has margin 0 (the collapse is arbitrary there).
    @Test func contestedMarginIsPeakMinusRunnerUp() {
        let n = 4
        var counts = [Int32](repeating: 0, count: 2 * 2 * 3 * n)
        // Cell 0, channel R: a spike at level 1 (5 observations) -> margin 5.
        counts[(0 * 3 + 0) * n + 1] = 5
        // Cell 1, channel R: a perfect tie, levels 0 and 2 both 3 -> margin 0.
        counts[(1 * 3 + 0) * n + 0] = 3
        counts[(1 * 3 + 0) * n + 2] = 3
        // Cell 2, channel R: peak 4 at level 0, runner-up 1 at level 3 -> margin 3.
        counts[(2 * 3 + 0) * n + 0] = 4
        counts[(2 * 3 + 0) * n + 3] = 1
        let f = V21FieldData(side: 2, nLevels: n, counts: counts)
        let m = V21Contested.margins(f)
        #expect(m.count == 2 * 2 * 3)
        #expect(m[0 * 3 + 0] == 5)   // spike
        #expect(m[1 * 3 + 0] == 0)   // tie: the GIF byte here is a coin-flip
        #expect(m[2 * 3 + 0] == 3)   // confident-ish
    }

    /// The sidecar `.npy` is valid NumPy v1.0 with the level axis collapsed: shape `(side, side, 3)`.
    @Test func contestedNpyIsValidAndCollapsesLevelAxis() {
        let f = V21FieldData(side: 2, nLevels: 4,
                             counts: Array(0 ..< (2 * 2 * 3 * 4)).map { Int32($0) })
        let data = [UInt8](V21Contested.npyData(f))
        #expect(Array(data[0 ..< 6]) == [0x93] + Array("NUMPY".utf8))
        let hlen = Int(data[8]) | (Int(data[9]) << 8)
        let header = String(bytes: data[10 ..< 10 + hlen], encoding: .ascii) ?? ""
        #expect(header.contains("'descr': '<i4'"))
        #expect(header.contains("'shape': (2, 2, 3)"))           // level axis gone
        #expect(data.count - (10 + hlen) == 2 * 2 * 3 * 4)        // side·side·3 int32s
    }

    // MARK: manifest + bundle

    /// The manifest is valid JSON that records the field source and the artifact filenames, so the
    /// receiver knows which probability function it got without guessing.
    @Test func manifestRecordsSourceAndArtifacts() throws {
        let f = V21FieldData(side: 64, nLevels: 256, counts: [Int32](repeating: 0, count: 64 * 64 * 3 * 256))
        let data = V21Manifest.json(field: f, source: .cameraBox, stem: "sixfour_abcd1234",
                                    artifacts: ["gif": "sixfour_abcd1234.gif",
                                                "field": "sixfour_abcd1234_field_64x64x3x256.npy",
                                                "contested": "sixfour_abcd1234_contested_64x64x3.npy"])
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["field_source"] as? String == "camera_box")
        #expect(obj?["schema"] as? String == "sixfour.v21.capture/1")
        let arts = obj?["artifacts"] as? [String: String]
        #expect(arts?["field"] == "sixfour_abcd1234_field_64x64x3x256.npy")
        #expect(arts?["contested"] == "sixfour_abcd1234_contested_64x64x3.npy")
    }

    /// The temporal-proxy source is recorded faithfully (the fallback path must not masquerade as the
    /// camera-box field).
    @Test func manifestRecordsTemporalProxy() throws {
        let f = V21FieldData(side: 2, nLevels: 4, counts: [Int32](repeating: 0, count: 2 * 2 * 3 * 4))
        let data = V21Manifest.json(field: f, source: .temporalProxy, stem: "s", artifacts: [:])
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["field_source"] as? String == "temporal_proxy")
    }

    /// The share bundle includes the field tensor, the contestedness sidecar, and the manifest.
    @Test func shareItemsIncludeTensorContestedAndManifest() {
        let field = V21FieldData(side: 2, nLevels: 4, counts: [Int32](repeating: 1, count: 2 * 2 * 3 * 4))
        let items = V21Export.shareItems(field: field, source: .cameraBox, gifURL: nil)
        let names = items.compactMap { ($0 as? URL)?.lastPathComponent }
        #expect(names.contains { $0.contains("_field_") && $0.hasSuffix(".npy") })
        #expect(names.contains { $0.contains("_contested_") && $0.hasSuffix(".npy") })
        #expect(names.contains { $0.hasSuffix("_manifest.json") })
        // The field, contested, and manifest all share the one stem (the bundle groups in the receiver).
        let stems = Set(names.map { String($0.prefix("sixfour_xxxxxxxx".count)) })
        #expect(stems.count == 1)
    }
}
