//  CaptureRecord.swift
//  THE SHUTTER'S LEDGER — the hand-written Swift twin of `Spec.CaptureRecord`.
//
//  One deterministic CBOR record per capture, written when the burst completes,
//  carrying exactly what the pooled sums CANNOT: the weave word (the temporal
//  ORDER of rung frames — `Spec.WeaveOrder` proves the order is invisible to
//  every conserved marginal, so if the shutter does not persist it, it is gone),
//  the measured per-frame intervals (integer microseconds), the 16×16×3 u64 bin
//  sums (the transitive pyramid carrier — the 32² and 16² views derive exactly,
//  never stored twice), and the realized 768-byte GCT.
//
//  ENCODING CONTRACT (RFC 8949 core deterministic subset, pinned by the spec):
//  majors 0 (uint) / 2 (bytes) / 3 (ASCII text) / 4 (array) / 5 (map) only;
//  minimal-length integer heads; definite lengths; map keys sorted BYTEWISE on
//  their encodings; NO floats (float milliseconds round to integer µs once,
//  here, at the boundary). Same content ⇒ byte-identical file, so records can
//  be content-addressed, deduplicated, and diffed. Parity with the Haskell
//  encoder is gated by the golden bytes in `CaptureRecordTests`
//  (`Spec.CaptureRecord.lawGoldenRecordPinned`).
//
//  Zero third-party dependencies (Foundation only, for Data/URL at the write).

import Foundation

/// The deterministic CBOR value subset — the Swift twin of `Spec.CaptureRecord.Cbor`.
enum S4Cbor {
    case uint(UInt64)
    case bytes([UInt8])
    case text(String)
    case array([S4Cbor])
    case map([(S4Cbor, S4Cbor)])

    /// A CBOR head with the minimal-length argument encoding (RFC 8949 §4.2.1).
    static func head(major: UInt8, _ n: UInt64) -> [UInt8] {
        let m = major << 5
        switch n {
        case 0..<24:
            return [m | UInt8(n)]
        case 24...0xFF:
            return [m | 24, UInt8(n)]
        case 0x100...0xFFFF:
            return [m | 25, UInt8(n >> 8), UInt8(n & 0xFF)]
        case 0x1_0000...0xFFFF_FFFF:
            return [m | 26] + (0..<4).map { UInt8((n >> (8 * (3 - $0))) & 0xFF) }
        default:
            return [m | 27] + (0..<8).map { UInt8((n >> (8 * (7 - $0))) & 0xFF) }
        }
    }

    /// Deterministic encode: maps sorted bytewise on encoded keys (duplicates
    /// dropped, first wins), text ASCII-clamped ('?' above 127) so text length
    /// equals byte length — exactly the spec's `canonical ∘ encode`.
    var encoded: [UInt8] {
        switch self {
        case .uint(let n):
            return Self.head(major: 0, n)
        case .bytes(let bs):
            return Self.head(major: 2, UInt64(bs.count)) + bs
        case .text(let s):
            let bs = s.unicodeScalars.map { $0.value < 128 ? UInt8($0.value) : UInt8(63) }
            return Self.head(major: 3, UInt64(bs.count)) + bs
        case .array(let xs):
            return xs.reduce(Self.head(major: 4, UInt64(xs.count))) { $0 + $1.encoded }
        case .map(let kvs):
            var seen = [[UInt8]]()
            var pairs = [(key: [UInt8], value: [UInt8])]()
            for (k, v) in kvs {
                let ek = k.encoded
                guard !seen.contains(ek) else { continue }
                seen.append(ek)
                pairs.append((ek, v.encoded))
            }
            pairs.sort { $0.key.lexicographicallyPrecedes($1.key) }
            return pairs.reduce(Self.head(major: 5, UInt64(pairs.count))) { $0 + $1.key + $1.value }
        }
    }
}

/// The per-capture record — the Swift twin of `Spec.CaptureRecord.CaptureRecord`.
/// Empty arrays are legal: a field the burst did not produce is absent-as-empty,
/// never invented.
struct S4CaptureRecord: Sendable {
    /// Record format version.
    var version: UInt64 = 1
    /// The burst window, centiseconds (320 = `S4_WINDOW_CS`).
    var windowCs: UInt64 = 320
    /// The timeline quantum, centiseconds (5 = one 64-rung frame at 20 fps).
    var baseDelayCs: UInt64 = 5
    /// THE ORDER — rung indices in capture order (0 = 64², 1 = 32², 2 = 16²).
    /// The shipped uniform burst is 64 zeros; a woven schedule is any word of
    /// `Spec.WeaveOrder` (one 16² frame = 4 units = index 2, etc.).
    var weave: [UInt64] = []
    /// Measured per-frame intervals, integer microseconds (the one place the
    /// float milliseconds round).
    var frameIntervalsUs: [UInt64] = []
    /// 16×16×3 u64 bin sums, row-major (`ColorHead.latest16` — the exact
    /// transitive carrier at burst end), or empty.
    var sums16: [UInt64] = []
    /// The realized 768-byte GCT (`ColorHead.latestGCT`), or empty.
    var gct: [UInt8] = []

    /// The record as canonical CBOR. Key set and semantics are pinned by the
    /// spec; the encoder sorts, so listing order here is documentation only.
    var cborBytes: [UInt8] {
        S4Cbor.map([
            (.text("v"),     .uint(version)),
            (.text("win"),   .uint(windowCs)),
            (.text("d0"),    .uint(baseDelayCs)),
            (.text("weave"), .array(weave.map { .uint($0) })),
            (.text("dtus"),  .array(frameIntervalsUs.map { .uint($0) })),
            (.text("s16"),   .array(sums16.map { .uint($0) })),
            (.text("gct"),   .bytes(gct)),
        ]).encoded
    }

    /// Atomic write next to the capture's other artifacts (`.s4cr`).
    func write(to url: URL) throws {
        try Data(cborBytes).write(to: url, options: .atomic)
    }
}
