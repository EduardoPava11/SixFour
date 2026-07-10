//  CaptureRecordTests.swift
//  Golden-parity gate for the hand-written CBOR capture record.
//
//  The authority is the Haskell spec: `Spec.CaptureRecord.goldenRecordBytes`
//  (a pinned LITERAL, `lawGoldenRecordPinned`) and, for the version-2
//  independent-rung fields, `goldenRecordV2Bytes` (`lawGoldenRecordV2Pinned`).
//  The Swift encoder must reproduce both byte for byte — any drift between
//  what the app writes at the shutter and what the study/training tooling
//  reads is a failed test here, never a debugging session later.

import XCTest
@testable import SixFour

final class CaptureRecordTests: XCTestCase {

    /// `Spec.CaptureRecord.goldenRecordBytes` — copied literal, never derived.
    private static let specGolden: [UInt8] = [
        0xA7,                                            // map(7)
        0x61, 0x76, 0x01,                                // "v": 1
        0x62, 0x64, 0x30, 0x05,                          // "d0": 5
        0x63, 0x67, 0x63, 0x74, 0x43, 0x00, 0x01, 0x02,  // "gct": h'000102'
        0x63, 0x73, 0x31, 0x36, 0x83, 0x01, 0x02, 0x03,  // "s16": [1,2,3]
        0x63, 0x77, 0x69, 0x6E, 0x19, 0x01, 0x40,        // "win": 320
        0x64, 0x64, 0x74, 0x75, 0x73,                    // "dtus":
        0x83, 0x19, 0xC3, 0x50, 0x19, 0xC3, 0x50, 0x19, 0xC3, 0x50, // [50000 ×3]
        0x65, 0x77, 0x65, 0x61, 0x76, 0x65,              // "weave":
        0x84, 0x02, 0x01, 0x00, 0x00,                    // [2,1,0,0] = 16,32,64,64
    ]

    /// The exact twin of `Spec.CaptureRecord.goldenRecord`.
    func testGoldenRecordMatchesSpec() {
        let r = S4CaptureRecord(
            weave: [2, 1, 0, 0],
            frameIntervalsUs: [50_000, 50_000, 50_000],
            sums16: [1, 2, 3],
            gct: [0, 1, 2]
        )
        XCTAssertEqual(r.cborBytes, Self.specGolden)
    }

    /// `Spec.CaptureRecord.lawHeadsAreMinimal` — minimal heads at every boundary.
    func testHeadsAreMinimal() {
        let boundaries: [UInt64] = [0, 23, 24, 255, 256, 65_535, 65_536,
                                    4_294_967_295, 4_294_967_296]
        XCTAssertEqual(boundaries.map { S4Cbor.head(major: 0, $0).count },
                       [1, 1, 2, 2, 3, 3, 5, 5, 9])
    }

    /// `Spec.CaptureRecord.lawMapKeysSortedBytewise` — listing order in source
    /// never reaches the bytes: a shuffled map encodes identically.
    func testMapKeyOrderIsCanonical() {
        let a = S4Cbor.map([(.text("win"), .uint(320)), (.text("v"), .uint(1))])
        let b = S4Cbor.map([(.text("v"), .uint(1)), (.text("win"), .uint(320))])
        XCTAssertEqual(a.encoded, b.encoded)
    }

    /// Duplicate keys drop (first wins), matching the spec's `canonical`.
    func testDuplicateKeysDrop() {
        let m = S4Cbor.map([(.text("v"), .uint(1)), (.text("v"), .uint(2))])
        XCTAssertEqual(m.encoded, S4Cbor.map([(.text("v"), .uint(1))]).encoded)
    }

    /// An empty record still encodes every field (absent-as-empty, never omitted).
    func testEmptyRecordShape() {
        let bytes = S4CaptureRecord().cborBytes
        XCTAssertEqual(bytes.first, 0xA7)  // still map(7)
    }

    // MARK: - Version 2 (the independent rungs)

    /// `Spec.CaptureRecord.goldenRecordV2Bytes` — copied literal, never derived.
    /// Bytewise key order interleaves old and new keys:
    /// v < d0 < ev < c16 < c32 < c64 < gct < s16 < tel < win < dtus < weave.
    private static let specGoldenV2: [UInt8] = [
        0xAC,                                            // map(12)
        0x61, 0x76, 0x02,                                // "v": 2
        0x62, 0x64, 0x30, 0x05,                          // "d0": 5
        0x62, 0x65, 0x76,                                // "ev":
        0x83,                                            //   3 rung triples
        0x83, 0x19, 0x30, 0xD4, 0x19, 0x03, 0xE8, 0x18, 0x31,
        //   [12500, 1000, zigzag(-25) = 49]
        0x83, 0x19, 0x61, 0xA8, 0x19, 0x07, 0xD0, 0x18, 0xC8,
        //   [25000, 2000, zigzag(100) = 200]
        0x83, 0x19, 0xC3, 0x50, 0x19, 0x0F, 0xA0, 0x19, 0x01, 0x90,
        //   [50000, 4000, zigzag(200) = 400]
        0x63, 0x63, 0x31, 0x36, 0x83, 0x07, 0x08, 0x09,  // "c16": [7,8,9]
        0x63, 0x63, 0x33, 0x32, 0x81, 0x06,              // "c32": [6]
        0x63, 0x63, 0x36, 0x34, 0x82, 0x04, 0x05,        // "c64": [4,5]
        0x63, 0x67, 0x63, 0x74, 0x43, 0x00, 0x01, 0x02,  // "gct": h'000102'
        0x63, 0x73, 0x31, 0x36, 0x83, 0x01, 0x02, 0x03,  // "s16": [1,2,3]
        0x63, 0x74, 0x65, 0x6C,                          // "tel":
        0x83,                                            //   [arrivals, N, comovement]
        0x83, 0x18, 0x40, 0x18, 0x20, 0x10,              //   [64,32,16]
        0x83, 0x01, 0x08, 0x18, 0x40,                    //   [1,8,64]
        0x18, 0xFA,                                      //   250 permille
        0x63, 0x77, 0x69, 0x6E, 0x19, 0x01, 0x40,        // "win": 320
        0x64, 0x64, 0x74, 0x75, 0x73,                    // "dtus":
        0x83, 0x19, 0xC3, 0x50, 0x19, 0xC3, 0x50, 0x19, 0xC3, 0x50, // [50000 ×3]
        0x65, 0x77, 0x65, 0x61, 0x76, 0x65,              // "weave":
        0x84, 0x02, 0x01, 0x00, 0x00,                    // [2,1,0,0] = 16,32,64,64
    ]

    /// The exact twin of `Spec.CaptureRecord.goldenRecordV2` — the v1 sample
    /// plus every independent-rung field populated small-but-real, including
    /// a NEGATIVE fine EV offset that pins the zigzag odd branch on the wire.
    func testGoldenRecordV2MatchesSpec() {
        var r = S4CaptureRecord(
            weave: [2, 1, 0, 0],
            frameIntervalsUs: [50_000, 50_000, 50_000],
            sums16: [1, 2, 3],
            gct: [0, 1, 2]
        )
        r.version = 2
        r.cube64 = [4, 5]
        r.cube32 = [6]
        r.cube16 = [7, 8, 9]
        r.exposures = [
            S4RungExposure(durationUs: 12_500, isoMilli: 1_000, evCentistops: -25),
            S4RungExposure(durationUs: 25_000, isoMilli: 2_000, evCentistops: 100),
            S4RungExposure(durationUs: 50_000, isoMilli: 4_000, evCentistops: 200),
        ]
        r.telemetry = S4TelemetrySnapshot(arrivals: [64, 32, 16],
                                          sampleVolumes: [1, 8, 64],
                                          comovementPermille: 250)
        XCTAssertEqual(r.cborBytes, Self.specGoldenV2)
    }

    /// The version gate: a version-1 record's bytes NEVER change — populated
    /// v2 fields are silently dropped from the wire below version 2 (the
    /// spec's `recordToCbor` gate, which is what keeps `goldenRecordBytes`
    /// pinned forever).
    func testV1BytesUnchangedByV2Fields() {
        var r = S4CaptureRecord(
            weave: [2, 1, 0, 0],
            frameIntervalsUs: [50_000, 50_000, 50_000],
            sums16: [1, 2, 3],
            gct: [0, 1, 2]
        )
        r.cube64 = [4, 5]
        r.cube32 = [6]
        r.cube16 = [7, 8, 9]
        r.exposures = [S4RungExposure(durationUs: 1, isoMilli: 2, evCentistops: -3)]
        r.telemetry = S4TelemetrySnapshot(arrivals: [1], sampleVolumes: [2],
                                          comovementPermille: 3)
        XCTAssertEqual(r.cborBytes, Self.specGolden)
    }

    /// `Spec.CaptureRecord.zigzag` — 0,-1,1,-2,2 → 0,1,2,3,4, the golden's
    /// odd branch (-25 → 49), and totality at the Int64 extremes.
    func testZigzagMatchesSpec() {
        XCTAssertEqual(S4Cbor.zigzag(0), 0)
        XCTAssertEqual(S4Cbor.zigzag(-1), 1)
        XCTAssertEqual(S4Cbor.zigzag(1), 2)
        XCTAssertEqual(S4Cbor.zigzag(-2), 3)
        XCTAssertEqual(S4Cbor.zigzag(2), 4)
        XCTAssertEqual(S4Cbor.zigzag(-25), 49)
        XCTAssertEqual(S4Cbor.zigzag(Int64.max), UInt64.max - 1)
        XCTAssertEqual(S4Cbor.zigzag(Int64.min), UInt64.max)
    }

    /// A v2 record with nothing to report still encodes: absent telemetry is
    /// the empty array, absent cubes are empty arrays — absent-as-empty,
    /// never invented (`lawV1DecodesUnderV2Reader`'s writer-side mirror).
    func testEmptyV2RecordShape() {
        var r = S4CaptureRecord()
        r.version = 2
        let bytes = r.cborBytes
        XCTAssertEqual(bytes.first, 0xAC)  // map(12)
        // "tel" (absent) encodes as the empty array right after its key.
        let telKey: [UInt8] = [0x63, 0x74, 0x65, 0x6C]
        let range = bytes.indices.dropLast(telKey.count).first { i in
            Array(bytes[i..<(i + telKey.count)]) == telKey
        }
        XCTAssertNotNil(range)
        if let i = range { XCTAssertEqual(bytes[i + telKey.count], 0x80) } // array(0)
    }

    // MARK: - Version 3 (the decision word)

    /// `Spec.CaptureRecord.goldenRecordV3Bytes` — copied literal, never
    /// derived. The `dw` key encodes between `d0` and `ev` (bytewise
    /// d0 < dw < ev); the op-codes are [0, 1, 46, 2, 48] = pour, S@r0,
    /// S@r15, K@r0, I@r15 (`gameOpCode`: 0 = pour, 1 + 3·region + verb).
    private static let specGoldenV3: [UInt8] = [
        0xAD,                                            // map(13)
        0x61, 0x76, 0x03,                                // "v": 3
        0x62, 0x64, 0x30, 0x05,                          // "d0": 5
        0x62, 0x64, 0x77,                                // "dw":
        0x85, 0x00, 0x01, 0x18, 0x2E, 0x02, 0x18, 0x30,  // [0,1,46,2,48]
        0x62, 0x65, 0x76,                                // "ev":
        0x83,                                            //   3 rung triples
        0x83, 0x19, 0x30, 0xD4, 0x19, 0x03, 0xE8, 0x18, 0x31,
        //   [12500, 1000, zigzag(-25) = 49]
        0x83, 0x19, 0x61, 0xA8, 0x19, 0x07, 0xD0, 0x18, 0xC8,
        //   [25000, 2000, zigzag(100) = 200]
        0x83, 0x19, 0xC3, 0x50, 0x19, 0x0F, 0xA0, 0x19, 0x01, 0x90,
        //   [50000, 4000, zigzag(200) = 400]
        0x63, 0x63, 0x31, 0x36, 0x83, 0x07, 0x08, 0x09,  // "c16": [7,8,9]
        0x63, 0x63, 0x33, 0x32, 0x81, 0x06,              // "c32": [6]
        0x63, 0x63, 0x36, 0x34, 0x82, 0x04, 0x05,        // "c64": [4,5]
        0x63, 0x67, 0x63, 0x74, 0x43, 0x00, 0x01, 0x02,  // "gct": h'000102'
        0x63, 0x73, 0x31, 0x36, 0x83, 0x01, 0x02, 0x03,  // "s16": [1,2,3]
        0x63, 0x74, 0x65, 0x6C,                          // "tel":
        0x83,                                            //   [arrivals, N, comovement]
        0x83, 0x18, 0x40, 0x18, 0x20, 0x10,              //   [64,32,16]
        0x83, 0x01, 0x08, 0x18, 0x40,                    //   [1,8,64]
        0x18, 0xFA,                                      //   250 permille
        0x63, 0x77, 0x69, 0x6E, 0x19, 0x01, 0x40,        // "win": 320
        0x64, 0x64, 0x74, 0x75, 0x73,                    // "dtus":
        0x83, 0x19, 0xC3, 0x50, 0x19, 0xC3, 0x50, 0x19, 0xC3, 0x50, // [50000 ×3]
        0x65, 0x77, 0x65, 0x61, 0x76, 0x65,              // "weave":
        0x84, 0x02, 0x01, 0x00, 0x00,                    // [2,1,0,0] = 16,32,64,64
    ]

    /// The exact twin of `Spec.CaptureRecord.goldenRecordV3` — the v2 sample
    /// plus a five-op decision word pinning both head widths and all three
    /// verbs (`lawGoldenRecordV3Pinned`).
    func testGoldenRecordV3MatchesSpec() {
        var r = S4CaptureRecord(
            weave: [2, 1, 0, 0],
            frameIntervalsUs: [50_000, 50_000, 50_000],
            sums16: [1, 2, 3],
            gct: [0, 1, 2]
        )
        r.version = 3
        r.cube64 = [4, 5]
        r.cube32 = [6]
        r.cube16 = [7, 8, 9]
        r.exposures = [
            S4RungExposure(durationUs: 12_500, isoMilli: 1_000, evCentistops: -25),
            S4RungExposure(durationUs: 25_000, isoMilli: 2_000, evCentistops: 100),
            S4RungExposure(durationUs: 50_000, isoMilli: 4_000, evCentistops: 200),
        ]
        r.telemetry = S4TelemetrySnapshot(arrivals: [64, 32, 16],
                                          sampleVolumes: [1, 8, 64],
                                          comovementPermille: 250)
        r.decisionWord = [0, 1, 46, 2, 48]
        XCTAssertEqual(r.cborBytes, Self.specGoldenV3)
    }

    /// The version gate holds downward: a populated decision word is silently
    /// dropped from the wire below version 3, so v1 AND v2 bytes never change
    /// (`lawV2DecodesUnderV3Reader`'s writer-side mirror).
    func testV2BytesUnchangedByV3Field() {
        var r = S4CaptureRecord(
            weave: [2, 1, 0, 0],
            frameIntervalsUs: [50_000, 50_000, 50_000],
            sums16: [1, 2, 3],
            gct: [0, 1, 2]
        )
        r.version = 2
        r.cube64 = [4, 5]
        r.cube32 = [6]
        r.cube16 = [7, 8, 9]
        r.exposures = [
            S4RungExposure(durationUs: 12_500, isoMilli: 1_000, evCentistops: -25),
            S4RungExposure(durationUs: 25_000, isoMilli: 2_000, evCentistops: 100),
            S4RungExposure(durationUs: 50_000, isoMilli: 4_000, evCentistops: 200),
        ]
        r.telemetry = S4TelemetrySnapshot(arrivals: [64, 32, 16],
                                          sampleVolumes: [1, 8, 64],
                                          comovementPermille: 250)
        r.decisionWord = [0, 1, 46, 2, 48]
        XCTAssertEqual(r.cborBytes, Self.specGoldenV2)
    }

    /// A v3 record with no game played still encodes: the empty decision word
    /// is the empty array — absent-as-empty, never invented.
    func testEmptyV3RecordShape() {
        var r = S4CaptureRecord()
        r.version = 3
        let bytes = r.cborBytes
        XCTAssertEqual(bytes.first, 0xAD)  // map(13)
        // "dw" (absent) encodes as the empty array right after its key.
        let dwKey: [UInt8] = [0x62, 0x64, 0x77]
        let idx = bytes.indices.dropLast(dwKey.count).first { i in
            Array(bytes[i..<(i + dwKey.count)]) == dwKey
        }
        XCTAssertNotNil(idx)
        if let i = idx { XCTAssertEqual(bytes[i + dwKey.count], 0x80) } // array(0)
    }
}
