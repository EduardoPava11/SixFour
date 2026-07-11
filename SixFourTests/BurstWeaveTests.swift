import Testing
@testable import SixFour

/// The burst-time independent ladder's PURE floor: the deterministic weave plan
/// (owner word + settle accounting), the exposure-switch boundaries, and the
/// `BurstWeaveDriver` accumulation + telemetry on synthetic sums — including
/// the derived-vs-independent separation the independence meter must show.
struct BurstWeaveTests {

    // MARK: - The weave plan (pure schedule)

    @Test func planCovers64TicksDeterministically() {
        let plan = MultiScaleLadder.weavePlan()
        #expect(plan.count == 64)
        #expect(plan == MultiScaleLadder.weavePlan())   // deterministic
        // The super-cycle: fine ×8, mid ×5, coarse ×3, repeated 4×.
        let word = MultiScaleLadder.weaveWord(plan)
        #expect(word.count == 64)
        let cycle: [UInt64] = [UInt64](repeating: 2, count: 8)
            + [UInt64](repeating: 1, count: 5) + [UInt64](repeating: 0, count: 3)
        #expect(word == cycle + cycle + cycle + cycle)
        // Depth codes only (0 = 16³, 1 = 32³, 2 = 64³).
        #expect(word.allSatisfy { $0 <= 2 })
    }

    @Test func planSettleAccounting() {
        let plan = MultiScaleLadder.weavePlan(settleFrames: 2)
        // Each dwell's first 2 ticks are unsettled, the rest owned.
        #expect(!plan[0].owned && !plan[1].owned && plan[2].owned)     // fine dwell
        #expect(!plan[8].owned && !plan[9].owned && plan[10].owned)    // mid dwell
        #expect(!plan[13].owned && !plan[14].owned && plan[15].owned)  // coarse dwell
        // Owned counts: fine 6×4 = 24, mid 3×4 = 12, coarse 1×4 = 4.
        #expect(MultiScaleLadder.plannedOwnedCount(plan, scale: .fine64) == 24)
        #expect(MultiScaleLadder.plannedOwnedCount(plan, scale: .mid32) == 12)
        #expect(MultiScaleLadder.plannedOwnedCount(plan, scale: .coarse16) == 4)
        // A settle window longer than the coarse dwell owns nothing there —
        // legal, and the telemetry reports it honestly.
        let slow = MultiScaleLadder.weavePlan(settleFrames: 3)
        #expect(MultiScaleLadder.plannedOwnedCount(slow, scale: .coarse16) == 0)
    }

    // MARK: - The exposure-switch boundaries

    private func makeStops() -> [MultiScaleLadder.Stop] {
        MultiScaleLadder.schedule(
            evSpreadStops: 4,
            sensor: .init(minISO: 32, maxISO: 3200,
                          minDurationSeconds: 1.0 / 8000, maxDurationSeconds: 1.0 / 20),
            referenceDuration: 1.0 / 240, referenceISO: 100)
    }

    @Test func exposureSwitchesAtDwellBoundariesOnly() {
        let driver = BurstWeaveDriver(plan: MultiScaleLadder.weavePlan(),
                                      stops: makeStops(), cropSide: 512)
        #expect(driver.firstStop?.scale == .fine64)
        // Mid-dwell: no switch.
        #expect(driver.exposureSwitchAfter(tick: 3) == nil)
        // Tick 7 is the last fine tick of the first dwell → program mid.
        #expect(driver.exposureSwitchAfter(tick: 7)?.scale == .mid32)
        // Tick 12 is the last mid tick → program coarse.
        #expect(driver.exposureSwitchAfter(tick: 12)?.scale == .coarse16)
        // Tick 15 is the last coarse tick → back to fine (cycle 2).
        #expect(driver.exposureSwitchAfter(tick: 15)?.scale == .fine64)
        // Last tick of the burst: nothing to program.
        #expect(driver.exposureSwitchAfter(tick: 63) == nil)
    }

    // MARK: - Accumulation (synthetic sums through the pure seam)

    /// A synthetic 64-rung sums frame: `value(i) = base + i·step` over the
    /// flattened (y·64+x)·3+c order — strictly monotone, so every pooled
    /// lattice delta has the sign of `step`.
    private func gradientSums(base: UInt64, step: Int64) -> [UInt64] {
        (0..<(64 * 64 * 3)).map { UInt64(Int64(base) + Int64($0) * step) }
    }

    @Test func accumulateRoutesToOwnerResolutionAndCounts() {
        let driver = BurstWeaveDriver(plan: MultiScaleLadder.weavePlan(),
                                      stops: makeStops(), cropSide: 512)
        let frame = gradientSums(base: 100, step: 1)
        // Explicit plan ticks (fine owns 2,3…; mid 10…; coarse 15 — the
        // settle-2 weave): `tickIndex` is required, the seam never invents.
        driver.accumulate(scale: .fine64, sums64: frame, fineBinArea: 64, tickIndex: 2)
        driver.accumulate(scale: .fine64, sums64: frame, fineBinArea: 64, tickIndex: 3)
        driver.accumulate(scale: .mid32, sums64: frame, fineBinArea: 64, tickIndex: 10)
        driver.accumulate(scale: .coarse16, sums64: frame, fineBinArea: 64, tickIndex: 15)
        let cubes = driver.cubesSnapshot()
        #expect(cubes.frames64 == 2 && cubes.cube64.count == 2 * 64 * 64 * 3)
        #expect(cubes.frames32 == 1 && cubes.cube32.count == 1 * 32 * 32 * 3)
        #expect(cubes.frames16 == 1 && cubes.cube16.count == 1 * 16 * 16 * 3)
        // The owner slice is the EXACT block-sum pool of the frame at the
        // owner's own side (never derived from another rung's stream).
        let pooled32 = ColorHead.poolSpatial2(frame, side: 64)
        #expect(cubes.cube32 == pooled32)
        #expect(cubes.cube16 == ColorHead.poolSpatial2(pooled32, side: 32))
        // Fine slices stack t-major.
        #expect(Array(cubes.cube64.prefix(64 * 64 * 3)) == frame)
    }

    @Test func telemetryCountsExposureAndSampleVolume() {
        let plan = MultiScaleLadder.weavePlan()
        let stops = makeStops()
        let driver = BurstWeaveDriver(plan: plan, stops: stops, cropSide: 512)
        let frame = gradientSums(base: 100, step: 1)
        driver.accumulate(scale: .fine64, sums64: frame, fineBinArea: 64, tickIndex: 2)
        driver.accumulate(scale: .fine64, sums64: frame, fineBinArea: 64, tickIndex: 3)
        driver.accumulate(scale: .mid32, sums64: frame, fineBinArea: 64, tickIndex: 10)
        let t = driver.telemetrySnapshot(generation: 3)
        #expect(t.generation == 3)
        #expect(t.rungs.map(\.side) == [64, 32, 16])
        #expect(t.rungs.allSatisfy { $0.independent })
        #expect(t.rungs.map(\.arrivals) == [2, 1, 0])
        #expect(t.rungs.map(\.expectedArrivals) == [24, 12, 4])
        // N = owned frames × pixels per bin at the rung's own side:
        // fine 2×64, mid 1×(64·4), coarse 0.
        #expect(t.rungs.map(\.sampleVolume) == [128, 256, 0])
        // Exposure state comes from the schedule (fine = reference = 0 EV;
        // coarse carries the spread).
        #expect(t.rungs[0].evCentistops == 0)
        #expect(t.rungs[2].evCentistops == 400)
        #expect(t.rungs[0].exposureDurationUs == stops[2].durationUs)
        #expect(t.rungs[2].isoMilli == stops[0].isoMilli)
        // No coarser data yet for the 16² rung; coarse owns nothing → -1.
        #expect(t.rungs[2].comovementPermilleVsCoarser == -1)
        #expect(t.rungs[1].comovementPermilleVsCoarser == -1)
    }

    /// DERIVED-LIKE input (every rung sees the same scene curve) saturates the
    /// meter at 1000‰; INDEPENDENT input (the coarse read counter-moves — the
    /// dead-time-photon story) sits strictly below. The separation the GRID's
    /// warning light rests on, end-to-end through the driver.
    @Test func independenceMeterSeparatesDerivedFromIndependent() {
        let stops = makeStops()
        let plan = MultiScaleLadder.weavePlan()

        // Derived-like: identical spatial curve into fine AND mid → the two
        // 16²-lattice totals are proportional → fully determined (1000‰).
        let derived = BurstWeaveDriver(plan: plan, stops: stops, cropSide: 512)
        let rising = gradientSums(base: 1000, step: 2)
        derived.accumulate(scale: .fine64, sums64: rising, fineBinArea: 64, tickIndex: 2)
        derived.accumulate(scale: .fine64, sums64: rising, fineBinArea: 64, tickIndex: 3)
        derived.accumulate(scale: .mid32, sums64: rising, fineBinArea: 64, tickIndex: 10)
        #expect(derived.telemetrySnapshot(generation: 0).rungs[0]
                    .comovementPermilleVsCoarser == 1000)

        // Independent-like: the mid exposure integrated light the fine read
        // never saw, and its spatial curve counter-moves → strictly < 1000.
        let independent = BurstWeaveDriver(plan: plan, stops: stops, cropSide: 512)
        let falling = gradientSums(base: 100_000, step: -2)
        independent.accumulate(scale: .fine64, sums64: rising, fineBinArea: 64, tickIndex: 2)
        independent.accumulate(scale: .mid32, sums64: falling, fineBinArea: 64, tickIndex: 10)
        let stat = independent.telemetrySnapshot(generation: 0).rungs[0]
            .comovementPermilleVsCoarser
        #expect(stat >= 0 && stat < 1000)
    }

    @Test func skippedTicksAreCountedPerRung() {
        let driver = BurstWeaveDriver(plan: MultiScaleLadder.weavePlan(),
                                      stops: makeStops(), cropSide: 512)
        // Kernel-side drops charge the rung whose exposure was live.
        driver.noteDropped(tickIndex: 0)    // fine dwell
        driver.noteDropped(tickIndex: 9)    // mid dwell
        driver.noteDropped(tickIndex: 13)   // coarse dwell
        driver.noteDropped(tickIndex: 999)  // clamps to the last tick (coarse)
        let t = driver.telemetrySnapshot(generation: 0)
        #expect(t.rungs.map(\.skipped) == [1, 1, 2])
    }
}
