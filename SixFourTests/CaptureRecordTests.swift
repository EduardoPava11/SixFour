//  CaptureRecordTests.swift
//  Golden-parity gate for the hand-written CBOR capture record.
//
//  The authority is the Haskell spec: `Spec.CaptureRecord.goldenRecordBytes`
//  (a pinned LITERAL, `lawGoldenRecordPinned`). The Swift encoder must
//  reproduce it byte for byte — any drift between what the app writes at the
//  shutter and what the study/training tooling reads is a failed test here,
//  never a debugging session later.

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
}
