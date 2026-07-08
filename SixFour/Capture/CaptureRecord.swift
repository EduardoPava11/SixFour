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
//  here, at the boundary); no major 1 — SIGNED quantities (the ladder's EV
//  offsets) ride major 0 under the zigzag convention (`S4Cbor.zigzag`). Same
//  content ⇒ byte-identical file, so records can be content-addressed,
//  deduplicated, and diffed. Parity with the Haskell encoder is gated by the
//  golden bytes in `CaptureRecordTests` (`Spec.CaptureRecord.
//  lawGoldenRecordPinned` + `lawGoldenRecordV2Pinned`).
//
//  VERSION 2 (the independent rungs): when the multi-scale ladder captures the
//  three rungs as SEPARATE exposures, `s16`'s derived-pyramid premise breaks
//  by design — version 2 adds `c64`/`c32`/`c16` (per-rung u64 sum volumes),
//  `ev` (per-rung exposure triples, fine→coarse) and `tel` (the RungTelemetry
//  snapshot). The five keys are VERSION-GATED (`version >= 2`), so a
//  version-1 record's bytes are exactly what they were before v2 existed.
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

    /// The zigzag convention for signed values inside major 0 (the subset has
    /// no major 1): `n ↦ 2n` for `n ≥ 0`, `-n ↦ 2n-1` for `n > 0` — so
    /// 0,-1,1,-2,2 → 0,1,2,3,4. Total over all of `Int64` (the twin of
    /// `Spec.CaptureRecord.zigzag`, `lawZigzagRoundTrips`).
    static func zigzag(_ n: Int64) -> UInt64 {
        n >= 0 ? UInt64(n) &* 2 : UInt64(-(n &+ 1)) &* 2 &+ 1
    }

    /// Deterministic encode: maps sorted bytewise on encoded keys (duplicates
    /// dropped, first wins), text ASCII-clamped ('?' above 127) so text length
    /// equals byte length — exactly the spec's `canonical ∘ encode`.
    var encoded: [UInt8] {
        var out = [UInt8]()
        appendEncoded(to: &out)
        return out
    }

    /// The linear-time encoder body: one shared output buffer, appended in
    /// place (the v2 cubes are hundreds of thousands of uints — the old
    /// `reduce(+)` array concatenation was quadratic in element count and is
    /// byte-identical to this). Same bytes, gated by the golden tests.
    private func appendEncoded(to out: inout [UInt8]) {
        switch self {
        case .uint(let n):
            out += Self.head(major: 0, n)
        case .bytes(let bs):
            out += Self.head(major: 2, UInt64(bs.count))
            out += bs
        case .text(let s):
            let bs = s.unicodeScalars.map { $0.value < 128 ? UInt8($0.value) : UInt8(63) }
            out += Self.head(major: 3, UInt64(bs.count))
            out += bs
        case .array(let xs):
            out += Self.head(major: 4, UInt64(xs.count))
            for x in xs { x.appendEncoded(to: &out) }
        case .map(let kvs):
            var seen = [[UInt8]]()
            var pairs = [(key: [UInt8], value: S4Cbor)]()
            for (k, v) in kvs {
                let ek = k.encoded
                guard !seen.contains(ek) else { continue }
                seen.append(ek)
                pairs.append((ek, v))
            }
            pairs.sort { $0.key.lexicographicallyPrecedes($1.key) }
            out += Self.head(major: 5, UInt64(pairs.count))
            for (key, value) in pairs {
                out += key
                value.appendEncoded(to: &out)
            }
        }
    }
}

/// One rung's realized exposure — the Swift twin of
/// `Spec.CaptureRecord.RungExposure`. Integer micro-fields only (the
/// no-floats rule); the EV offset is SIGNED and rides `S4Cbor.zigzag` on the
/// wire as the triple `[duration_us, iso_milli, zigzag(ev_centistops)]`.
struct S4RungExposure: Sendable, Equatable {
    /// Exposure duration, µs (unsigned).
    var durationUs: UInt64
    /// ISO in milli-units (ISO 100 = 100_000; unsigned).
    var isoMilli: UInt64
    /// EV offset vs the fine reference, CENTISTOPS — signed.
    var evCentistops: Int64
}

/// The burst's telemetry snapshot — the Swift twin of
/// `Spec.CaptureRecord.TelemetrySnapshot`, all unsigned, encoded as the triple
/// `[arrivals[], sampleVolumes[], comovement_permille]`. Rung lists run
/// fine → coarse (64, 32, 16).
struct S4TelemetrySnapshot: Sendable, Equatable {
    /// Per-rung arrival pulse counts.
    var arrivals: [UInt64]
    /// Per-rung significance N (sample volumes).
    var sampleVolumes: [UInt64]
    /// Independence co-movement statistic, permille (1000 = fully determined =
    /// the fell-back-to-derived warning).
    var comovementPermille: UInt64
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
    /// v2: 64-rung independent volume u64 sums, t-major (or empty).
    var cube64: [UInt64] = []
    /// v2: 32-rung independent volume u64 sums, t-major (or empty).
    var cube32: [UInt64] = []
    /// v2: 16-rung volume u64 sums, t-major — DERIVED mode writes only this
    /// cube (the c16-only signature is the provenance story, together with
    /// `telemetry`'s comovement); independent mode writes all three (or empty).
    var cube16: [UInt64] = []
    /// v2: per-rung exposure, fine → coarse (or empty). Optical when the
    /// ladder ran; pooling-equivalent EV (duration/ISO zero) when derived.
    var exposures: [S4RungExposure] = []
    /// v2: the telemetry snapshot (`nil` encodes as the empty array —
    /// absent-as-empty, like everything else here).
    var telemetry: S4TelemetrySnapshot? = nil

    /// The record as canonical CBOR. Key set and semantics are pinned by the
    /// spec; the encoder sorts, so listing order here is documentation only.
    /// The five v2 keys appear only when `version >= 2` — a version-1
    /// record's bytes are exactly what they were before version 2 existed
    /// (`Spec.CaptureRecord.recordToCbor`, same gate).
    var cborBytes: [UInt8] {
        var fields: [(S4Cbor, S4Cbor)] = [
            (.text("v"),     .uint(version)),
            (.text("win"),   .uint(windowCs)),
            (.text("d0"),    .uint(baseDelayCs)),
            (.text("weave"), .array(weave.map { .uint($0) })),
            (.text("dtus"),  .array(frameIntervalsUs.map { .uint($0) })),
            (.text("s16"),   .array(sums16.map { .uint($0) })),
            (.text("gct"),   .bytes(gct)),
        ]
        if version >= 2 {
            fields += [
                (.text("c64"), .array(cube64.map { .uint($0) })),
                (.text("c32"), .array(cube32.map { .uint($0) })),
                (.text("c16"), .array(cube16.map { .uint($0) })),
                (.text("ev"),  .array(exposures.map { e in
                    .array([.uint(e.durationUs),
                            .uint(e.isoMilli),
                            .uint(S4Cbor.zigzag(e.evCentistops))])
                })),
                (.text("tel"), telemetry.map { t in
                    .array([.array(t.arrivals.map { .uint($0) }),
                            .array(t.sampleVolumes.map { .uint($0) }),
                            .uint(t.comovementPermille)])
                } ?? .array([])),
            ]
        }
        return S4Cbor.map(fields).encoded
    }

    /// Atomic write next to the capture's other artifacts (`.s4cr`).
    func write(to url: URL) throws {
        try Data(cborBytes).write(to: url, options: .atomic)
    }
}
