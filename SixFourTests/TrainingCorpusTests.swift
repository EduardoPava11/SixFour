import XCTest
@testable import SixFour

/// THE CORPUS EXPORT gates (`TrainingCorpus`, `Feature.trainingCorpus`):
/// the volume `.npy` byte format (the Mac reads it with a bare `numpy.load`),
/// the sidecar Codable round-trip, and the stage-folder + manifest packaging
/// that the AirDrop archive zips. Mac-side twin: `trainer/corpus_ingest.py`
/// (its self-check manufactures the same shapes).
final class TrainingCorpusTests: XCTestCase {

    /// A tiny octant-partitionable burst: 2 frames of 2×2 OKLab tiles with
    /// distinct, exactly-representable channel values.
    private func tinyTiles() -> [OKLabTile] {
        (0..<2).map { f in
            let pixels = (0..<4).map { p in
                SIMD3<Float>(Float(f) * 0.5, Float(p) * 0.25, -0.125)
            }
            return OKLabTile(side: 2, pixels: pixels, captureNanos: UInt64(f),
                             palette: [], finalShift: 0)
        }
    }

    // MARK: - Volume .npy

    func testVolumeNpyHeaderAndPayload() throws {
        let tiles = tinyTiles()
        let npy = try XCTUnwrap(TrainingCorpus.volumeNpy(tiles: tiles))

        // NumPy v1.0 magic + version.
        XCTAssertEqual(npy[0], 0x93)
        XCTAssertEqual(String(data: npy[1..<6], encoding: .ascii), "NUMPY")
        XCTAssertEqual(Array(npy[6..<8]), [0x01, 0x00])

        // Header: little-endian uint16 length, dict with dtype + our shape.
        let hlen = Int(npy[8]) | (Int(npy[9]) << 8)
        let header = try XCTUnwrap(String(data: npy[10..<(10 + hlen)], encoding: .ascii))
        XCTAssertTrue(header.contains("'<i4'"))
        XCTAssertTrue(header.contains("(2, 2, 2, 3)"))
        XCTAssertTrue(header.hasSuffix("\n"))
        XCTAssertEqual((10 + hlen) % 64, 0, "header block is 64-aligned")

        // Payload: exactly the sanctioned Q16 volume, int32 little-endian.
        let volume = try XCTUnwrap(CaptureGene.volume(from: tiles))
        let payload = npy[(10 + hlen)...]
        XCTAssertEqual(payload.count, volume.count * 4)
        let decoded: [Int32] = payload.withUnsafeBytes { raw in
            (0..<volume.count).map { Int32(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 4, as: Int32.self)) }
        }
        XCTAssertEqual(decoded, volume)
        // Spot-check the sanctioned crossing: 0.25 → 16384 in Q16 (channel a
        // of pixel 1, frame 0 → flat index (0·4 + 1)·3 + 1).
        XCTAssertEqual(decoded[(0 * 4 + 1) * 3 + 1], 16384)
    }

    // MARK: - Sidecar Codable

    func testSidecarRoundTrip() throws {
        var sidecar = TrainingCorpus.Sidecar(
            stem: "sixfour_test", capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
            colorSpace: "rec709", frames: 64, side: 64)
        sidecar.volumeFile = "sixfour_test.volume.npy"
        sidecar.bandHead = TrainingCorpus.BandHeadOutcome(
            initialMSE: 0.5, finalMSE: 0.125, weights: [0.1, -0.2, 0.3, 0, 1])
        sidecar.haltOrders = [Int32](repeating: 2, count: 256)
        sidecar.tband = TrainingCorpus.TBandPairs(
            width: 5, features: [1, 0.5, 0.25, 0.125, 0], targets: [0.75])

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("corpus-sidecar-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try TrainingCorpus.writeSidecar(sidecar, to: url)

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode(TrainingCorpus.Sidecar.self,
                                  from: Data(contentsOf: url))
        XCTAssertEqual(back.schema, TrainingCorpus.sidecarSchema)
        XCTAssertEqual(back.stem, sidecar.stem)
        XCTAssertEqual(back.capturedAt, sidecar.capturedAt)
        XCTAssertEqual(back.volumeFile, sidecar.volumeFile)
        XCTAssertEqual(back.bandHead, sidecar.bandHead)
        XCTAssertEqual(back.haltOrders, sidecar.haltOrders)
        XCTAssertEqual(back.tband, sidecar.tband)
        XCTAssertNil(back.thetaUp, "absent-as-nil survives the trip")
    }

    // MARK: - Staging + manifest + zip

    func testStageFolderManifestAndZip() throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("corpus-test-\(UUID().uuidString)", isDirectory: true)
        let documents = scratch.appendingPathComponent("Documents", isDirectory: true)
        try fm.createDirectory(at: documents, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }

        // Two corpus captures (volume present) + one plain capture (GIF only —
        // must NOT join the corpus).
        for stem in ["sixfour_a", "sixfour_b"] {
            for suffix in [".gif", ".s4cr", ".volume.npy", ".train.json"] {
                try Data(stem.utf8).write(to: documents.appendingPathComponent(stem + suffix))
            }
        }
        try Data("nocorpus".utf8).write(to: documents.appendingPathComponent("sixfour_c.gif"))

        XCTAssertEqual(TrainingCorpus.corpusStems(in: documents), ["sixfour_a", "sixfour_b"])

        let folder = try TrainingCorpus.stageFolder(documents: documents, into: scratch)
        let staged = try fm.contentsOfDirectory(atPath: folder.path).sorted()
        XCTAssertTrue(staged.contains("corpus_manifest.json"))
        XCTAssertTrue(staged.contains("sixfour_a.volume.npy"))
        XCTAssertTrue(staged.contains("sixfour_b.train.json"))
        XCTAssertFalse(staged.contains("sixfour_c.gif"), "volume-less captures stay out")

        // Manifest is honest about what it staged.
        struct Manifest: Decodable {
            let schema: String
            let captureCount: Int
            let captures: [String: [String]]
        }
        let manifest = try JSONDecoder().decode(
            Manifest.self,
            from: Data(contentsOf: folder.appendingPathComponent("corpus_manifest.json")))
        XCTAssertEqual(manifest.schema, TrainingCorpus.manifestSchema)
        XCTAssertEqual(manifest.captureCount, 2)
        XCTAssertEqual(manifest.captures["sixfour_a"]?.sorted(),
                       ["sixfour_a.gif", "sixfour_a.s4cr",
                        "sixfour_a.train.json", "sixfour_a.volume.npy"])

        // The zip lands and is non-trivial (system facility; content gated by
        // the Mac-side ingest self-check, not re-parsed here).
        let zip = try TrainingCorpus.zipArchive(of: folder, into: scratch)
        let size = try XCTUnwrap(try fm.attributesOfItem(atPath: zip.path)[.size] as? Int)
        XCTAssertGreaterThan(size, 0)
    }
}
