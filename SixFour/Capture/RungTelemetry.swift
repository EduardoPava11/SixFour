import Foundation

/// The Swift twin of `Spec.RungTelemetry` — WHAT THE GRID SHOWS PER RUNG, for
/// BOTH capture modes, in exact integer arithmetic (no floats on any carrier).
///
/// Once the three rungs (64²@20 Hz / 32²@10 Hz / 16²@5 Hz) become independent
/// data signals (`Feature.multiScaleLadder`, `BurstWeaveDriver`), the surface
/// must report per rung, AS IT ARRIVES: its exposure state, its arrival pulse,
/// its statistical significance, and whether it is genuinely independent or has
/// silently fallen back to derived pooling. `RungTelemetryMath` mirrors the
/// spec's exports function-for-function (`RungTelemetryTests` pins the spec's
/// own witness numbers); `RungTelemetry` / `SystemTelemetry` are the Sendable
/// value snapshots the delegate queue publishes to the UI — coalesced at rung
/// cadence, never per-frame (the PERF-MAP publish→fold discipline).
enum RungTelemetryMath {

    // MARK: - Exposure state (one vocabulary for both modes)

    /// The photon-equivalent exposure product `duration × gain` — the one scalar
    /// both shutter time and ISO spend into. Negative inputs clamp to 0 (no
    /// anti-photons). Spec: `exposureProduct`.
    static func exposureProduct(durationUs: Int64, iso: Int64) -> Int64 {
        max(0, durationUs) * max(0, iso)
    }

    /// INDEPENDENT-MODE exposure state: the rung's light ratio versus the fine
    /// reference as an EXACT rational `(num, den)` — `(0, 1)` for a degenerate
    /// (non-positive) reference. `+1 stop == num = 2·den`. Spec: `opticalLightRatio`.
    static func opticalLightRatio(durationUs: Int64, iso: Int64,
                                  refDurationUs: Int64, refIso: Int64)
        -> (num: Int64, den: Int64) {
        let ref = exposureProduct(durationUs: refDurationUs, iso: refIso)
        guard ref > 0 else { return (0, 1) }
        return (exposureProduct(durationUs: durationUs, iso: iso), ref)
    }

    /// DERIVED-MODE exposure state: pooling `2^k` frames is worth exactly `+k`
    /// stops — ColorTime's one-integer axis. Spec: `poolingEquivalentStops`.
    static func poolingEquivalentStops(rung k: Int) -> Int { max(0, k) }

    /// The derived-mode light RATIO `2^k`, comparable one-for-one with
    /// `opticalLightRatio` (`lawExposureVocabulariesAgreeOnLadder`).
    static func poolingEquivalentRatio(rung k: Int) -> Int64 {
        1 << UInt64(poolingEquivalentStops(rung: k))
    }

    // MARK: - Arrival (the native cadences on the 320 cs window)

    /// The 3.2 s burst window in centiseconds (`Spec.WeaveOrder.windowCs`).
    static let windowCs = 320

    /// A rung's native GIF-exact interval in centiseconds: 5 / 10 / 20 cs for
    /// sides 64 / 32 / 16 (`s4_ladder_delay_cs`, the time law).
    static func nativeIntervalCs(side: Int) -> Int { 320 / side }

    /// Pulses a rung delivers on the 320 cs window: 64 / 32 / 16 for sides
    /// 64 / 32 / 16 (`lawExpectedArrivalsPinned`). Spec: `expectedArrivals`.
    static func expectedArrivals(side: Int) -> Int { side }

    /// LATE pulses in an observed interval list: intervals strictly longer than
    /// the rung's native interval. Zero on the clean cadence. Spec: `lateArrivals`.
    static func lateArrivals(side: Int, intervalsCs: [Int]) -> Int {
        let native = nativeIntervalCs(side: side)
        return intervalsCs.lazy.filter { $0 > native }.count
    }

    /// MISSING pulses: how far the observed count falls short of
    /// `expectedArrivals` (never negative). Spec: `missingArrivals`.
    static func missingArrivals(side: Int, intervalsCs: [Int]) -> Int {
        max(0, expectedArrivals(side: side) - intervalsCs.count)
    }

    // MARK: - Significance (sample volume; the meter shows √N, read on squares)

    /// DERIVED-MODE sample volume of a rung-k voxel: `N(k) = 2^k · 4^k · N₀ =
    /// 8^k · N₀` — temporal pool depth × spatial cell area, the SAME integer k
    /// on both factors (`lawDerivedSignificanceLattice`, the 1:8:64 lattice).
    /// Negative `n0` clamps to 0. Spec: `derivedSampleVolume`.
    static func derivedSampleVolume(rung k: Int, n0: Int64) -> Int64 {
        let kk = max(0, k)
        return (1 << UInt64(3 * kk)) * max(0, n0)
    }

    /// INDEPENDENT-MODE sample volume: the sum of the ACTUAL owned sample counts
    /// (frames owned × pixels each, whatever the weave delivered) — evidence
    /// counted, not assumed. Negative counts clamp to 0. Spec: `independentSampleVolume`.
    static func independentSampleVolume(_ counts: [Int64]) -> Int64 {
        counts.reduce(0) { $0 + max(0, $1) }
    }

    // MARK: - Independence health (the exact decorrelation statistic)

    /// Pool a stream to a coarser lattice by exact block sums of `b` bins
    /// (incomplete trailing blocks are DROPPED, so pooling composes —
    /// `lawPoolCompose`; the Haskell twin drops them identically). `b <= 0`
    /// yields the empty stream. Spec: `poolTo`.
    static func poolTo(_ b: Int, _ xs: [Int64]) -> [Int64] {
        guard b > 0 else { return [] }
        let blocks = xs.count / b
        var out = [Int64](); out.reserveCapacity(blocks)
        for i in 0..<blocks {
            var s: Int64 = 0
            for j in 0..<b { s += xs[i * b + j] }
            out.append(s)
        }
        return out
    }

    /// Per-bin deltas of a stream: `x[i+1] − x[i]` — the MOVEMENT the
    /// co-movement statistic reads. Spec: `binDeltas`.
    static func binDeltas(_ xs: [Int64]) -> [Int64] {
        guard xs.count >= 2 else { return [] }
        return (1..<xs.count).map { xs[$0] - xs[$0 - 1] }
    }

    /// THE STATISTIC: `(agreements, comparisons)` over the aligned delta pairs
    /// of the two streams — how many move with the SAME sign (0 counts as a
    /// sign). Spec: `comovement`.
    static func comovement(_ a: [Int64], _ b: [Int64]) -> (agree: Int, total: Int) {
        let da = binDeltas(a), db = binDeltas(b)
        let n = min(da.count, db.count)
        var agree = 0
        for i in 0..<n where da[i].signum() == db[i].signum() { agree += 1 }
        return (agree, n)
    }

    /// The normalized statistic in PERMILLE (integer-exact: `⌊1000·agree/total⌋`).
    /// 1000 = fully determined — the BAD pole (derived pooling); zero comparisons
    /// also reads 1000 (no evidence of independence is not evidence of
    /// independence). Spec: `comovementRatio` (permille instead of Rational so
    /// the value rides the capture record's unsigned-integer CBOR subset).
    static func comovementPermille(_ a: [Int64], _ b: [Int64]) -> Int {
        let (agree, total) = comovement(a, b)
        guard total > 0 else { return 1000 }
        return agree * 1000 / total
    }

    /// The warning-light predicate: the two streams co-move everywhere — the
    /// observable signature that the coarse rung is (or is indistinguishable
    /// from) a derived pool of the fine one. Spec: `fullyDetermined`.
    /// NOTE: permille floors, so this checks the EXACT ratio, not the floor.
    static func fullyDetermined(_ a: [Int64], _ b: [Int64]) -> Bool {
        let (agree, total) = comovement(a, b)
        return agree == total
    }

    /// The SHARP byte-exact fallback signature: the coarse stream IS the exact
    /// block-sum pool of the fine one — the provenance bit the capture record
    /// stamps. Spec: `isDerivedPool`.
    static func isDerivedPool(block b: Int, fine: [Int64], coarse: [Int64]) -> Bool {
        !coarse.isEmpty && coarse == poolTo(b, fine)
    }
}

/// One burst's per-rung instrument snapshot (`Feature.rungTelemetry`) — the
/// value the delegate queue publishes (coalesced, ≤ 5 Hz) and `finishBurst`
/// snapshots for the capture record. Rungs run FINE → COARSE (64, 32, 16),
/// matching `Spec.CaptureRecord`'s exposure-triple order.
struct RungTelemetry: Sendable, Equatable {

    /// One rung's state. All integer-exact; the UI renders, never recomputes.
    struct RungState: Sendable, Equatable {
        /// Spatial side (64 / 32 / 16).
        let side: Int
        /// True = this rung is its OWN exposure read (independent ladder);
        /// false = derived by exact pooling from the fine stream.
        let independent: Bool
        /// SIGNED EV offset vs the fine reference, in centistops: optical
        /// (schedule `Stop.evOffsetStops`) when independent, pooling-equivalent
        /// (+100k per rung k) when derived — ONE vocabulary
        /// (`lawExposureVocabulariesAgreeOnLadder`).
        let evCentistops: Int
        /// Optical exposure duration in µs (0 in derived mode — no per-rung shutter).
        let exposureDurationUs: Int64
        /// Optical gain in ISO milli-units (ISO 100 = 100_000; 0 in derived mode).
        let isoMilli: Int64
        /// Pulses this rung should deliver: the plan's owned count (independent)
        /// or the 64/32/16 cadence pin (derived, `lawExpectedArrivalsPinned`).
        let expectedArrivals: Int
        /// Pulses actually landed (owned settled frames / derived rung frames).
        let arrivals: Int
        /// Ticks charged to this rung that produced NO evidence: ISP settle
        /// frames, pool failures, kernel-dropped frames. 0 in derived mode.
        let skipped: Int
        /// Per-voxel sample volume N: `8^k·N₀` derived, actual owned
        /// frames × pixels independent. The meter shows √N; the √N order IS the
        /// N order (`lawSignificanceSqrtMonotone`), so N ships and nothing
        /// irrational is ever computed.
        let sampleVolume: Int64
        /// Co-movement statistic vs the NEXT-COARSER rung, in permille.
        /// 1000 = fully determined = "this pair is (indistinguishable from)
        /// derived pooling" — the warning light. -1 = no coarser rung / no data.
        let comovementPermilleVsCoarser: Int
    }

    /// Fine → coarse: [64², 32², 16²].
    let rungs: [RungState]
    /// The burst generation this snapshot belongs to (the `flowCallback`
    /// stale-delivery discipline).
    let generation: Int

    /// The DERIVED-MODE snapshot, built from the shipped `ColorHead` ladder's
    /// exact bookkeeping: arrivals are the actual rung frame counts
    /// (`ticks >> k`), EV is the pooling-equivalent +k stops, N is the 1:8:64
    /// lattice on the fine bin's pixel count, and independence health reports
    /// the maximal pole HONESTLY (the coarse rungs ARE exact pools — comovement
    /// 1000‰ by construction, no computation needed). Pure; unit-tested against
    /// the spec numbers in `RungTelemetryTests`.
    static func derived(ticks: Int, fineBinArea: Int64, generation: Int) -> RungTelemetry {
        let rungs = (0..<3).map { k in
            RungState(
                side: 64 >> k,
                independent: false,
                evCentistops: RungTelemetryMath.poolingEquivalentStops(rung: k) * 100,
                exposureDurationUs: 0,
                isoMilli: 0,
                expectedArrivals: RungTelemetryMath.expectedArrivals(side: 64 >> k),
                arrivals: max(0, ticks) >> k,
                skipped: 0,
                sampleVolume: RungTelemetryMath.derivedSampleVolume(rung: k, n0: fineBinArea),
                comovementPermilleVsCoarser: k < 2 ? 1000 : -1
            )
        }
        return RungTelemetry(rungs: rungs, generation: generation)
    }
}

/// The ONE system region's data (`Feature.rungTelemetry`): tick CPU vs the
/// 50 ms budget, the v21 histogram buffer's lifecycle (the ~384 MiB the memory
/// audit watches), and the camera's thermal/system pressure. Published from the
/// delegate queue ON CHANGE and at burst boundaries only — never per tick.
struct SystemTelemetry: Sendable, Equatable {

    /// Lifecycle of the per-burst v21 histogram buffer.
    enum V21BufferState: Int, Sendable {
        /// No buffer this burst (flag off, ladder mode, or allocation failed).
        case none = 0
        /// Allocated at burst start; the GPU is accumulating into it.
        case allocated = 1
        /// Handed to the detached flow-encode job (still resident).
        case held = 2
        /// The flow job finished; the buffer was released.
        case freed = 3
    }

    /// Mean delegate-queue CPU per ladder tick this burst, µs.
    let tickCpuMeanUs: Int
    /// Worst single tick, µs.
    let tickCpuMaxUs: Int
    /// Ticks aggregated (0 = no ladder ran).
    let tickCount: Int
    /// The hardware tick budget: 50 ms at the pinned 20 fps cadence.
    let tickBudgetUs: Int
    /// Where the v21 hist buffer is in its life.
    let v21Buffer: V21BufferState
    /// `AVCaptureDevice.SystemPressureState.Level` mapped to 0…4
    /// (nominal/fair/serious/critical/shutdown); -1 = unknown/never observed.
    let pressureLevel: Int
}
