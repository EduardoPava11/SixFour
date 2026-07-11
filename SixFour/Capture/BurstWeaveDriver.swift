import CoreVideo
import Foundation

/// The BURST-TIME independent ladder (`Feature.multiScaleLadder`): executes one
/// `MultiScaleLadder.weavePlan` over the 64-tick burst, routing each SETTLED
/// frame to its owner scale's independent u64 sum volume — three separate
/// exposure reads (16³/32³/64³), never pools of one source
/// (`Spec.MultiScaleCapture.lawScalesAreNotDerivable` made physical).
///
/// Division of labour:
///   * This type is AVFoundation-FREE and delegate-queue-confined (the
///     `ColorHead` convention: constructed AND mutated only on
///     `CaptureSession.delegateQueue`; never `Sendable`). Everything except the
///     pixel-buffer pool is pure and unit-tested off-device
///     (`BurstWeaveTests` feeds `accumulate` synthetic sums directly).
///   * `CaptureSession` owns the DEVICE half: it applies
///     `MultiScaleLadder.applyExposure` for the stop this driver's pure
///     `exposureSwitchAfter(tick:)` hands back (device-only; no-op in the
///     Simulator, exactly like `ExposureBracketDriver`).
///
/// PERF (the 50 ms tick discipline): the three volumes and the 16²-lattice
/// running totals are preallocated at init from the plan's owned counts — the
/// per-tick work is one pool (owned ticks only; settle ticks cost a counter
/// bump) plus fixed-size integer adds. No per-tick logging; `CaptureSession`
/// aggregates the tick CPU and logs once per burst.
final class BurstWeaveDriver {

    /// The executed plan (owner word + settle accounting), fixed at init.
    let plan: [MultiScaleLadder.WeaveTick]
    /// The EV-tiled stops, indexed by `Scale.rawValue` (0 = coarse16 … 2 = fine64).
    let stops: [MultiScaleLadder.Stop]

    /// Pooling-only `ColorHead` (its `ingest` is never called — the derived
    /// ladder must NOT run on EV-cycled frames; this instance is just the
    /// byte-exact x420 → 64-rung-sums kernel plus its crop bookkeeping).
    private let poolHead: ColorHead

    // Per-scale accumulators, indexed by Scale.rawValue. Volumes are t-major
    // slices of side²·3 u64 sums, preallocated to the plan's owned counts.
    private var volumes: [[UInt64]]

    /// Owned frames landed per scale (by rawValue).
    private(set) var owned: [Int] = [0, 0, 0]
    /// The burst TICK each landed slice arrived on, per scale (by rawValue),
    /// in owned order — what `cubesSnapshot` hands the display's causal hold
    /// (`Spec.RungReadDisplay.sliceForTick`). `ingest` records the REAL tick;
    /// direct `accumulate` callers (the test seam) pass their own explicit
    /// ticks — no fallback exists, so a fabricated-looking tick log can never
    /// compile its way into production.
    private(set) var ownedTicks: [[Int]] = [[], [], []]
    /// Ticks charged to each scale that produced NO evidence: settle frames,
    /// pool failures, kernel-dropped frames (by rawValue).
    private(set) var skipped: [Int] = [0, 0, 0]
    /// Running per-scale totals on the SHARED 16² lattice (768 sums each) —
    /// the streams the independence statistic compares. Comparing every pair on
    /// the coarsest shared lattice is licensed by the spec's scale-equivariance
    /// (`lawDerivedStaysMaximalUnderSharedPool`: further shared pooling cannot
    /// un-saturate a derived pair).
    private var lattice16: [[UInt64]]
    /// Pixels per fine (64-rung) bin of the last pooled frame — the telemetry's
    /// per-frame sample base. Settable by tests via `accumulate`.
    private(set) var fineBinArea: Int64 = 0

    /// - Parameters:
    ///   - plan: the tick weave (usually `MultiScaleLadder.weavePlan()`).
    ///   - stops: the EV-tiled bracket from `MultiScaleLadder.schedule` (any
    ///     order; indexed here by scale).
    ///   - cropSide: center-crop for the pooling head (512 matches the burst
    ///     `ColorHead` budget: ≈256k px/tick, well inside 50 ms).
    init(plan: [MultiScaleLadder.WeaveTick], stops: [MultiScaleLadder.Stop], cropSide: Int = 512) {
        self.plan = plan
        var byScale = [MultiScaleLadder.Stop?](repeating: nil, count: 3)
        for s in stops { byScale[s.scale.rawValue] = s }
        // A missing stop degrades to a zero placeholder (telemetry reports 0s;
        // capture still runs) — schedule() always emits all three, so this is
        // belt-and-braces, not a real path.
        self.stops = MultiScaleLadder.Scale.allCases.map { sc in
            byScale[sc.rawValue] ?? MultiScaleLadder.Stop(
                scale: sc, durationSeconds: 0, iso: 0, evOffsetStops: 0)
        }
        self.poolHead = ColorHead(cropSide: cropSide)
        self.volumes = MultiScaleLadder.Scale.allCases.map { sc in
            let n = MultiScaleLadder.plannedOwnedCount(plan, scale: sc)
            return [UInt64](repeating: 0, count: n * sc.side * sc.side * 3)
        }
        self.lattice16 = [[UInt64]](repeating: [UInt64](repeating: 0, count: 16 * 16 * 3),
                                    count: 3)
    }

    // MARK: - The device seam (pure decisions; CaptureSession applies them)

    /// The stop the burst must open with (the exposure live for tick 0).
    var firstStop: MultiScaleLadder.Stop? {
        plan.first.map { stops[$0.scale.rawValue] }
    }

    /// The stop to program AFTER tick `i` lands, or nil when the next tick
    /// keeps the same exposure. Applying at the dwell boundary gives the ISP
    /// the dwell's settle ticks to clear — the `ExposureBracketDriver` timing.
    func exposureSwitchAfter(tick i: Int) -> MultiScaleLadder.Stop? {
        guard i >= 0, i + 1 < plan.count, plan[i + 1].scale != plan[i].scale else { return nil }
        return stops[plan[i + 1].scale.rawValue]
    }

    // MARK: - Per-tick ingest (delegate queue)

    /// Feed the frame that landed at tick `i`. Settle ticks (and pool failures)
    /// bump the owning scale's `skipped` and cost nothing else; owned ticks
    /// pool the x420 buffer once and accumulate into the owner's volume.
    /// Returns the owner scale when the frame was routed, nil otherwise.
    @discardableResult
    func ingest(tickIndex i: Int, pixelBuffer: CVPixelBuffer) -> MultiScaleLadder.Scale? {
        guard i >= 0, i < plan.count else { return nil }
        let t = plan[i]
        guard t.owned else {
            skipped[t.scale.rawValue] += 1
            return nil
        }
        guard let sums = poolHead.poolSums64(fromX420: pixelBuffer) else {
            skipped[t.scale.rawValue] += 1
            return nil
        }
        accumulate(scale: t.scale, sums64: sums, fineBinArea: poolHead.pixelsPerFineBin,
                   tickIndex: i)
        return t.scale
    }

    /// A kernel-side dropped frame during the burst, charged to the scale whose
    /// exposure was live (`captureOutput(_:didDrop:)`).
    func noteDropped(tickIndex i: Int) {
        guard !plan.isEmpty else { return }
        let t = plan[min(max(0, i), plan.count - 1)]
        skipped[t.scale.rawValue] += 1
    }

    /// The pure accumulation core (the test seam): route one owned frame's
    /// 64-rung sums (64·64·3 u64) into `scale`'s independent volume at the
    /// scale's OWN resolution — exact `poolSpatial2` block sums down to the
    /// owner side, never derived from another rung's stream — and fold the
    /// frame into the scale's 16²-lattice running total. `tickIndex` is
    /// REQUIRED: it is the burst tick this frame actually landed on (`ingest`
    /// passes the real one; tests pass the plan ticks they assert against).
    /// A defaulted fallback here once let a caller compile with a
    /// fabricated-but-lawful-looking tick log — the causal-hold display
    /// (`RungReads.sliceForTick`, `lawHoldIsCausal`) trusts this log, so the
    /// seam refuses to invent ticks.
    func accumulate(scale: MultiScaleLadder.Scale, sums64: [UInt64], fineBinArea area: Int64,
                    tickIndex: Int) {
        precondition(sums64.count == 64 * 64 * 3)
        fineBinArea = area
        // Record the slice's arrival tick (owned order == slice order).
        let slot = owned[scale.rawValue]
        let tick = tickIndex
        // Pool to the owner's resolution (exact block sums; fine64 = identity).
        var rung = sums64
        var side = 64
        while side > scale.side {
            rung = ColorHead.poolSpatial2(rung, side: side)
            side /= 2
        }
        // Write the slice into the preallocated volume. If the plan's owned
        // budget is somehow exceeded (cannot happen with plan-driven ticks),
        // skip the WHOLE slice bookkeeping — tick log, slice bytes, and the
        // owned counter move together or not at all, so `cubesSnapshot` can
        // never report one more frame than the cube holds (one phantom frame
        // would fail `RungReads.realizeRung`'s shape guard and silently drop
        // the entire reads display).
        let sliceLen = scale.side * scale.side * 3
        if (slot + 1) * sliceLen <= volumes[scale.rawValue].count {
            volumes[scale.rawValue].withUnsafeMutableBufferPointer { buf in
                rung.withUnsafeBufferPointer { src in
                    _ = memcpy(buf.baseAddress! + slot * sliceLen, src.baseAddress!,
                               sliceLen * MemoryLayout<UInt64>.stride)
                }
            }
            ownedTicks[scale.rawValue].append(tick)
            owned[scale.rawValue] += 1
        }
        // Fold into the shared 16² lattice total (pool the rest of the way down).
        while side > 16 {
            rung = ColorHead.poolSpatial2(rung, side: side)
            side /= 2
        }
        for j in 0..<(16 * 16 * 3) { lattice16[scale.rawValue][j] &+= rung[j] }
    }

    // MARK: - Snapshots (burst seam)

    /// The three independent volumes, trimmed to the frames that actually
    /// landed (t-major, side²·3 u64 per slice) — what `finishBurst` snapshots
    /// for the capture record, exactly like `recordSums16`.
    func cubesSnapshot() -> CaptureSession.RungCubes {
        func trimmed(_ sc: MultiScaleLadder.Scale) -> [UInt64] {
            let len = owned[sc.rawValue] * sc.side * sc.side * 3
            return Array(volumes[sc.rawValue].prefix(len))
        }
        return CaptureSession.RungCubes(
            cube64: trimmed(.fine64), frames64: owned[MultiScaleLadder.Scale.fine64.rawValue],
            cube32: trimmed(.mid32), frames32: owned[MultiScaleLadder.Scale.mid32.rawValue],
            cube16: trimmed(.coarse16), frames16: owned[MultiScaleLadder.Scale.coarse16.rawValue],
            ownedTicks64: ownedTicks[MultiScaleLadder.Scale.fine64.rawValue],
            ownedTicks32: ownedTicks[MultiScaleLadder.Scale.mid32.rawValue],
            ownedTicks16: ownedTicks[MultiScaleLadder.Scale.coarse16.rawValue],
            fineBinArea: fineBinArea,
            // Ladder slices are SINGLE-tick (one owned frame each) — the
            // realize count must NOT carry the derived ×4
            // (`Spec.RungReadDisplay.lawSliceCountMatchesProvenance`).
            ticksPerSlice16: 1)
    }

    /// The independence statistic between `scale` and the next-coarser rung on
    /// the shared 16² lattice, permille. -1 when either side has no evidence
    /// yet or there is no coarser rung.
    private func comovementVsCoarser(of scale: MultiScaleLadder.Scale) -> Int {
        guard scale != .coarse16 else { return -1 }
        let coarser = MultiScaleLadder.Scale(rawValue: scale.rawValue - 1)!
        guard owned[scale.rawValue] > 0, owned[coarser.rawValue] > 0 else { return -1 }
        let a = lattice16[scale.rawValue].map { Int64(bitPattern: $0) }
        let b = lattice16[coarser.rawValue].map { Int64(bitPattern: $0) }
        return RungTelemetryMath.comovementPermille(a, b)
    }

    /// The INDEPENDENT-MODE telemetry snapshot (fine → coarse): optical EV/ISO/
    /// duration from the schedule, arrivals = owned frames vs the plan's
    /// expectation, N = actual owned frames × pixels per bin at the rung's own
    /// side (`independentSampleVolume` — evidence counted, not assumed), and
    /// the measured co-movement statistic vs the next-coarser rung.
    func telemetrySnapshot(generation: Int) -> RungTelemetry {
        let fineToCoarse: [MultiScaleLadder.Scale] = [.fine64, .mid32, .coarse16]
        let rungs = fineToCoarse.map { sc -> RungTelemetry.RungState in
            let stop = stops[sc.rawValue]
            // Pixels per bin at this rung's side: (crop/side)² = fineBinArea·(64/side)².
            let ratio = Int64(64 / sc.side)
            let pixelsPerBin = fineBinArea * ratio * ratio
            return RungTelemetry.RungState(
                side: sc.side,
                independent: true,
                evCentistops: stop.evCentistops,
                exposureDurationUs: stop.durationUs,
                isoMilli: stop.isoMilli,
                expectedArrivals: MultiScaleLadder.plannedOwnedCount(plan, scale: sc),
                arrivals: owned[sc.rawValue],
                skipped: skipped[sc.rawValue],
                sampleVolume: RungTelemetryMath.independentSampleVolume(
                    [Int64(owned[sc.rawValue]) * pixelsPerBin]),
                comovementPermilleVsCoarser: comovementVsCoarser(of: sc)
            )
        }
        return RungTelemetry(rungs: rungs, generation: generation)
    }
}
