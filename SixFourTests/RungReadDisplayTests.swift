import Testing
@testable import SixFour

/// Golden gate for `RungReads` — the Swift twin of `Spec.RungReadDisplay`
/// (THE READS ON SCREEN). The Haskell battery's pinned vectors are mirrored
/// VERBATIM: the settle-2 hold table, the realize pixel bases (including the
/// named ×4 double-count bug), the shared-clock quantizer, and the 9 sampler
/// probes on the coded volumes. The per-frame sampler is additionally gated
/// against the whole-volume kernel authority (`s4_render_select` via
/// `SixFourNative.renderSelect` — `lawSamplerMatchesRenderSelectWhenDense`),
/// and the builder is exercised end-to-end through `BurstWeaveDriver.
/// accumulate` (the existing synthetic test seam — the Simulator has no
/// camera, so this IS the exercisable ladder path).
struct RungReadDisplayTests {

    // MARK: - Causal slice lookup (Spec golden: the settle-2 fixture weave)

    /// `goldenSliceForTick16`: owned ticks [2,3,6,7,12,13] hold to exactly
    /// the pinned table — and the naive `frame/2` indexing FOIL disagrees
    /// (non-vacuity: the causal hold is not a renamed division).
    @Test func causalHoldGolden() {
        let owned = [2, 3, 6, 7, 12, 13]
        let held = (0...15).map { RungReads.sliceForTick(owned, $0) }
        #expect(held == [0, 0, 0, 1, 1, 1, 2, 3, 3, 3, 3, 3, 4, 5, 5, 5])
        #expect(held != (0...15).map { $0 / 2 })   // the frame/2 foil
        // lawOwnedTickShowsOwnSlice: the i-th owned tick answers exactly i.
        for (i, t) in owned.enumerated() {
            #expect(RungReads.sliceForTick(owned, t) == i)
        }
        // lawHoldIsCausal edges: slice 0 before the first arrival; monotone.
        #expect(RungReads.sliceForTick(owned, 0) == 0)
        #expect(RungReads.sliceForTick([], 7) == 0)
        for t in 0..<63 {
            #expect(RungReads.sliceForTick(owned, t) <= RungReads.sliceForTick(owned, t + 1))
        }
    }

    // MARK: - The realize pixel base (lawSliceCountMatchesProvenance)

    /// Ladder slices are 1-tick, the derived c16 is 4-tick; at the device's
    /// fine-bin area 64 the ladder 32-slice base is 256 and the derived c16
    /// base is 4096. THE ×4 DOUBLE-COUNT REGRESSION PIN: reusing the derived
    /// multiplier on a ladder 32-slice over-counts by exactly 4 (a 2-stop
    /// shift) — `ColorHead.emit16`'s `lastCropArea*4` must never leak here.
    @Test func realizeCountMatchesProvenance() {
        #expect(RungReads.ladderTicksPerSlice == 1)
        #expect(RungReads.derivedTicksPerSlice == 4)   // == fastPerSlow
        for a in [Int64(1), 7, 64, 1024] {
            #expect(RungReads.sliceRealizeCount(side: 64, fineBinArea: a, ticksPerSlice: 1) == a)
            #expect(RungReads.sliceRealizeCount(side: 32, fineBinArea: a, ticksPerSlice: 1) == 4 * a)
            #expect(RungReads.sliceRealizeCount(side: 16, fineBinArea: a, ticksPerSlice: 1) == 16 * a)
            #expect(RungReads.sliceRealizeCount(side: 16, fineBinArea: a, ticksPerSlice: 4) == 64 * a)
        }
        #expect(RungReads.sliceRealizeCount(side: 32, fineBinArea: 64, ticksPerSlice: 1) == 256)
        #expect(RungReads.sliceRealizeCount(side: 16, fineBinArea: 64, ticksPerSlice: 4) == 4096)
        // The named bug, pinned: derived multiplier on a ladder 32-slice = ×4.
        #expect(RungReads.sliceRealizeCount(side: 32, fineBinArea: 64,
                                            ticksPerSlice: RungReads.derivedTicksPerSlice)
                == 4 * RungReads.sliceRealizeCount(side: 32, fineBinArea: 64,
                                                   ticksPerSlice: RungReads.ladderTicksPerSlice))
        // Totality: non-dividing / non-positive sides answer 0.
        #expect(RungReads.sliceRealizeCount(side: 60, fineBinArea: 64, ticksPerSlice: 1) == 0)
        #expect(RungReads.sliceRealizeCount(side: 0, fineBinArea: 64, ticksPerSlice: 1) == 0)
    }

    // MARK: - The shared 4:2:1 clock (lawTemporalQuantizeOnSharedClock)

    @Test func temporalQuantizeOnSharedClock() {
        for d in 0...2 {
            let b = RungReads.blockSideAt(d)
            for t in 0..<64 {
                let tq = RungReads.temporalQuantize(depth: d, t: t)
                #expect(tq % b == 0)
                #expect(tq <= t && t < tq + b)
                #expect(tq / b == t / b)
            }
        }
        // Render replication and capture nesting are ONE clock: the block
        // sides ARE the cadence ratios.
        #expect(RungReads.blockSideAt(0) == Int(S4_MS_FAST_PER_SLOW))
        #expect(RungReads.blockSideAt(1) == Int(S4_MS_MID_PER_SLOW))
        #expect(RungReads.blockSideAt(2) == 1)
    }

    // MARK: - The per-frame sampler (the Haskell probes + the kernel gate)

    /// Coded volume at `side`: value = base + flat (t,y,x)-major index, so
    /// every probe names its own coordinates (the Haskell battery's shape).
    private func codedVolume(side: Int, base: Int32) -> [Int32] {
        (0 ..< side * side * side).map { base + Int32($0) }
    }

    /// The 9 hand-checked Haskell probes on the coded volumes (outSide 8,
    /// field r % 3) — pinned byte-for-byte from `Properties.RungReadDisplay`.
    @Test func samplerGoldenProbes() {
        let v16 = codedVolume(side: 2, base: 100)
        let v32 = codedVolume(side: 4, base: 200)
        let v64 = codedVolume(side: 8, base: 1000)
        let depth: [Int32] = (0..<8).map { Int32($0 % 3) }
        let probes: [(t: Int, x: Int, y: Int)] = [
            (0, 0, 0), (0, 5, 0), (2, 1, 5), (1, 6, 6), (6, 3, 2),
            (7, 7, 3), (5, 2, 7), (4, 5, 4), (3, 0, 0),
        ]
        let got = probes.map {
            RungReads.frameSample(outSide: 8, depth: depth,
                                  v16: v16, v32: v32, v64: v64,
                                  x: $0.x, y: $0.y, t: $0.t)
        }
        #expect(got == [100, 202, 1169, 103, 253, 1479, 106, 242, 100])
    }

    /// THE KERNEL-AUTHORITY GATE (`lawSamplerMatchesRenderSelectWhenDense`):
    /// on dense volumes the per-voxel sampler agrees with the golden
    /// whole-volume kernel (`s4_render_select`) at EVERY voxel, for a field
    /// that hits all depths INCLUDING out-of-range values (clamped by both).
    @Test func samplerMatchesRenderSelect() {
        var seed: UInt64 = 0x5DEE_CE66_D123_4567
        func next() -> Int32 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int32(truncatingIfNeeded: seed >> 33)
        }
        let v16 = (0..<8).map { _ in next() }
        let v32 = (0..<64).map { _ in next() }
        let v64 = (0..<512).map { _ in next() }
        let depth: [Int32] = (0..<8).map { _ in Int32(abs(Int(next())) % 5 - 1) } // -1…3, clamped
        let fused = SixFourNative.renderSelect(v16: v16, v32: v32, v64: v64,
                                               depth: depth, side: 8)
        #expect(fused != nil)
        guard let fused else { return }
        for t in 0..<8 {
            for y in 0..<8 {
                for x in 0..<8 {
                    #expect(RungReads.frameSample(outSide: 8, depth: depth,
                                                  v16: v16, v32: v32, v64: v64,
                                                  x: x, y: y, t: t)
                            == fused[(t * 8 + y) * 8 + x])
                }
            }
        }
    }

    // MARK: - The builder through the driver's synthetic seam

    private func makeStops() -> [MultiScaleLadder.Stop] {
        MultiScaleLadder.schedule(
            evSpreadStops: 4,
            sensor: .init(minISO: 32, maxISO: 3200,
                          minDurationSeconds: 1.0 / 8000, maxDurationSeconds: 1.0 / 20),
            referenceDuration: 1.0 / 240, referenceISO: 100)
    }

    /// A constant 64-rung sums frame: every fine bin sums `area × mean`
    /// (so realization at the exact count answers the linear mean everywhere).
    private func constantSums(mean: UInt64, area: UInt64) -> [UInt64] {
        [UInt64](repeating: area * mean, count: 64 * 64 * 3)
    }

    /// Synthetic ladder burst through `BurstWeaveDriver.accumulate` →
    /// `cubesSnapshot` → `RungReads.build`: all three rungs realize, the
    /// reads claim independence, the owned ticks are the plan's, and the
    /// builder's bytes equal a DIRECT kernel realize at the exact count —
    /// while the ×4-wrong count produces DIFFERENT bytes (the 2-stop foil).
    @Test func buildRealizesLadderCubesAtTheExactCount() {
        let driver = BurstWeaveDriver(plan: MultiScaleLadder.weavePlan(),
                                      stops: makeStops(), cropSide: 512)
        let frame = constantSums(mean: 40000, area: 64)
        driver.accumulate(scale: .fine64, sums64: frame, fineBinArea: 64, tickIndex: 2)
        driver.accumulate(scale: .mid32, sums64: frame, fineBinArea: 64, tickIndex: 10)
        driver.accumulate(scale: .coarse16, sums64: frame, fineBinArea: 64, tickIndex: 15)
        let cubes = driver.cubesSnapshot()
        // The driver hands the display everything the realize needs.
        #expect(cubes.fineBinArea == 64)
        #expect(cubes.ticksPerSlice16 == 1)
        #expect(cubes.ownedTicks64 == [2])    // the plan's first owned ticks
        #expect(cubes.ownedTicks32 == [10])   // (settle-2 dwell rule)
        #expect(cubes.ownedTicks16 == [15])

        let reads = RungReads.build(from: cubes)
        #expect(reads.independent)
        #expect(reads.r64?.frames == 1 && reads.r32?.frames == 1 && reads.r16?.frames == 1)

        // Builder == the kernel realized directly at count 256 (fineBinArea·4·1).
        var direct = [UInt8](repeating: 0, count: 32 * 32 * 3)
        let rcDirect = cubes.cube32.withUnsafeBufferPointer { s in
            direct.withUnsafeMutableBufferPointer { o in
                s4_sums_bt2020_to_srgb8(s.baseAddress, 32, 256, o.baseAddress)
            }
        }
        #expect(rcDirect == 0)
        #expect(reads.r32?.rgb == direct)

        // The ×4 double-count FOIL: count 1024 realizes a DIFFERENT image
        // (a constant 2-stop shift) — the bug lawSliceCountMatchesProvenance kills.
        var wrong = [UInt8](repeating: 0, count: 32 * 32 * 3)
        let rcWrong = cubes.cube32.withUnsafeBufferPointer { s in
            wrong.withUnsafeMutableBufferPointer { o in
                s4_sums_bt2020_to_srgb8(s.baseAddress, 32, 1024, o.baseAddress)
            }
        }
        #expect(rcWrong == 0)
        #expect(wrong != direct)
    }

    /// A kernel refusal (mean > 65535 from wrong/hot sums) marks THAT rung
    /// EMPTY — and one empty rung drops the whole `independent` claim (the
    /// binary whole-hero fallback trigger). A rung must be nil, never wrong.
    @Test func kernelRefusalMarksRungEmpty() {
        let hot = [UInt64](repeating: 64 * 70000, count: 64 * 64 * 3)   // mean 70000 > 65535
        let fine = [UInt64](repeating: 64 * 30000, count: 64 * 64 * 3)
        let cubes = CaptureSession.RungCubes(
            cube64: hot, frames64: 1,
            cube32: Array(ColorHead.poolSpatial2(fine, side: 64)), frames32: 1,
            cube16: ColorHead.poolSpatial2(ColorHead.poolSpatial2(fine, side: 64), side: 32),
            frames16: 1,
            ownedTicks64: [2], ownedTicks32: [10], ownedTicks16: [15],
            fineBinArea: 64, ticksPerSlice16: 1)
        let reads = RungReads.build(from: cubes)
        #expect(reads.r64 == nil)          // refused ⇒ EMPTY, never a wrong image
        #expect(reads.r32 != nil && reads.r16 != nil)
        #expect(!reads.independent)        // ⇒ whole-hero derived fallback
    }

    /// The derived c16-only shape (`ColorHead`'s signature) realizes its one
    /// honest rung with the ×4 temporal base and NEVER claims the reads
    /// (`lawDerivedNeverClaimsReads`); the all-empty shape is neither.
    @Test func derivedSignatureNeverClaimsReads() {
        let c16 = [UInt64](repeating: 4096 * 1000, count: 16 * 16 * 3)  // mean 1000 at count 4096
        let cubes = CaptureSession.RungCubes(
            cube64: [], frames64: 0, cube32: [], frames32: 0,
            cube16: c16, frames16: 1,
            ownedTicks16: [3], fineBinArea: 64, ticksPerSlice16: 4)
        let reads = RungReads.build(from: cubes)
        #expect(reads.r16 != nil && reads.r64 == nil && reads.r32 == nil)
        #expect(!reads.independent)
        // All-empty (the v1 shape): neither derived rung nor reads.
        let empty = RungReads.build(from: CaptureSession.RungCubes(
            cube64: [], frames64: 0, cube32: [], frames32: 0,
            cube16: [], frames16: 0))
        #expect(empty.r16 == nil && !empty.independent)
    }

    // MARK: - The compositor (per-region source, causal hold, block geometry)

    /// Three constant rungs with DISTINCT greys: a depth-d region shows ITS
    /// OWN rung's bytes (select, never a pool of another), block-replicated
    /// over the same chunk geometry the derived `pooled()` display uses.
    @Test func compositedSelectsPerRegionSource() {
        func cube(side: Int, mean: UInt64, count: UInt64) -> [UInt64] {
            [UInt64](repeating: count * mean, count: side * side * 3)
        }
        // fineBinArea 64 ⇒ counts 64 / 256 / 1024 for sides 64 / 32 / 16.
        let cubes = CaptureSession.RungCubes(
            cube64: cube(side: 64, mean: 10000, count: 64), frames64: 1,
            cube32: cube(side: 32, mean: 20000, count: 256), frames32: 1,
            cube16: cube(side: 16, mean: 30000, count: 1024), frames16: 1,
            ownedTicks64: [2], ownedTicks32: [10], ownedTicks16: [15],
            fineBinArea: 64, ticksPerSlice16: 1)
        let reads = RungReads.build(from: cubes)
        #expect(reads.independent)
        guard let r64 = reads.r64, let r32 = reads.r32, let r16 = reads.r16 else { return }
        let a = r16.rgb[0], b = r32.rgb[0], c = r64.rgb[0]
        #expect(a != b && b != c && a != c)   // the greys separate (non-vacuity)

        var depths = [Int](repeating: 0, count: 16)
        depths[1] = 1
        depths[2] = 2
        guard let rgba = reads.composited(frame: 0, depths: depths) else {
            Issue.record("composited refused on independent reads")
            return
        }
        func px(_ x: Int, _ y: Int) -> UInt8 { rgba[(y * 64 + x) * 4] }
        #expect(px(0, 0) == a)     // region 0 depth 0 → the 16-rung's own read
        #expect(px(16, 0) == b)    // region 1 depth 1 → the 32-rung's own read
        #expect(px(32, 0) == c)    // region 2 depth 2 → the 64-rung's own read
        #expect(px(48, 0) == a)    // region 3 depth 0 → back to the coarse read
        #expect(px(63, 63) == a)   // region 15 depth 0
    }

    /// REGRESSION (review 2026-07-10): the causal hold runs on the RAW
    /// playhead tick, never on a window-quantized one. The REAL weave plan's
    /// c16 owned ticks are [15, 31, 47, 63] — all ≡ 3 mod 4 — so a depth-0
    /// quantize-then-hold (multiples of 4, max 60) could NEVER reach the 4th
    /// slice and lagged every other by one window. Every slice must be
    /// reachable at its own landing tick, at coarse depth.
    @Test func compositedReachesLateInWindowSlices() {
        func slice16(mean: UInt64) -> [UInt64] {
            [UInt64](repeating: 1024 * mean, count: 16 * 16 * 3)   // count 64·16
        }
        let c16 = slice16(mean: 5000) + slice16(mean: 15000)
                + slice16(mean: 30000) + slice16(mean: 45000)
        let cubes = CaptureSession.RungCubes(
            cube64: [UInt64](repeating: 64 * 10000, count: 64 * 64 * 3), frames64: 1,
            cube32: [UInt64](repeating: 256 * 20000, count: 32 * 32 * 3), frames32: 1,
            cube16: c16, frames16: 4,
            ownedTicks64: [2], ownedTicks32: [10],
            ownedTicks16: [15, 31, 47, 63],   // the shipped weave plan's coarse ticks
            fineBinArea: 64, ticksPerSlice16: 1)
        let reads = RungReads.build(from: cubes)
        #expect(reads.independent)
        guard let r16 = reads.r16 else { return }
        let sliceByte = (0 ..< 4).map { r16.rgb[$0 * 16 * 16 * 3] }
        #expect(Set(sliceByte).count == 4)   // four distinct greys (non-vacuity)
        let depths = [Int](repeating: 0, count: 16)   // ALL regions at the coarse read
        func heroByte(_ f: Int) -> UInt8? { reads.composited(frame: f, depths: depths)?[0] }
        #expect(heroByte(0)  == sliceByte[0])   // pre-arrival hold
        #expect(heroByte(30) == sliceByte[0])   // held until the next landing
        #expect(heroByte(31) == sliceByte[1])   // flips AT the landing tick
        #expect(heroByte(47) == sliceByte[2])
        #expect(heroByte(62) == sliceByte[2])
        #expect(heroByte(63) == sliceByte[3])   // THE regression: the 4th slice shows
    }

    /// The compositor HOLDS causally through sparse owned ticks: two c64
    /// slices at ticks [2, 5] — frames 2…4 show slice 0, frame 5 flips to
    /// slice 1 the instant it lands (`lawOwnedTickShowsOwnSlice`).
    @Test func compositedHoldsCausally() {
        func slice64(mean: UInt64) -> [UInt64] {
            [UInt64](repeating: 64 * mean, count: 64 * 64 * 3)
        }
        let f0 = slice64(mean: 10000), f1 = slice64(mean: 25000)
        let mid = ColorHead.poolSpatial2(f0, side: 64)          // 64 → 32
        let coarse = ColorHead.poolSpatial2(mid, side: 32)      // 32 → 16
        let cubes = CaptureSession.RungCubes(
            cube64: f0 + f1, frames64: 2,
            cube32: mid, frames32: 1,
            cube16: coarse, frames16: 1,
            ownedTicks64: [2, 5], ownedTicks32: [10], ownedTicks16: [15],
            fineBinArea: 64, ticksPerSlice16: 1)
        let reads = RungReads.build(from: cubes)
        #expect(reads.independent)
        guard let r64 = reads.r64 else { return }
        let byte0 = r64.rgb[0]
        let byte1 = r64.rgb[64 * 64 * 3]
        #expect(byte0 != byte1)
        let depths = [Int](repeating: 2, count: 16)   // every region reads c64
        for f in 2...4 {
            #expect(reads.composited(frame: f, depths: depths)?[0] == byte0)
        }
        #expect(reads.composited(frame: 5, depths: depths)?[0] == byte1)
        #expect(reads.composited(frame: 0, depths: depths)?[0] == byte0)  // hold before first
    }

    // MARK: - The record fixture (the settle-2 dwell reconstruction)

    /// DEBUG fixture loader: rebuilding reads from the raw cube arrays alone
    /// (the `.s4cr` v2 shape — no owned ticks on the wire yet) reconstructs
    /// the owned ticks via the settle-2 dwell rule and lands byte-identical
    /// to the live driver build.
    @Test func fixtureLoaderRebuildsFromRecordCubes() {
        let driver = BurstWeaveDriver(plan: MultiScaleLadder.weavePlan(),
                                      stops: makeStops(), cropSide: 512)
        let frame = constantSums(mean: 12000, area: 64)
        driver.accumulate(scale: .fine64, sums64: frame, fineBinArea: 64, tickIndex: 2)
        driver.accumulate(scale: .fine64, sums64: frame, fineBinArea: 64, tickIndex: 3)
        driver.accumulate(scale: .mid32, sums64: frame, fineBinArea: 64, tickIndex: 10)
        driver.accumulate(scale: .coarse16, sums64: frame, fineBinArea: 64, tickIndex: 15)
        let cubes = driver.cubesSnapshot()
        let live = RungReads.build(from: cubes)
        let fixture = RungReads.fixture(cube64: cubes.cube64, cube32: cubes.cube32,
                                        cube16: cubes.cube16, fineBinArea: 64)
        #expect(fixture == live)
        #expect(fixture.independent)
        // The derived c16-only record shape reconstructs the derived signature.
        let derived = RungReads.fixture(cube64: [], cube32: [],
                                        cube16: [UInt64](repeating: 4096 * 900,
                                                         count: 2 * 16 * 16 * 3),
                                        fineBinArea: 64)
        #expect(!derived.independent)
        #expect(derived.r16?.ownedTicks == [3, 7])   // the 5 Hz realize ticks
    }

    // MARK: - The model boundary (a derived burst keeps the pooled path)

    /// A derived burst renders BYTE-IDENTICAL to the existing pooled path:
    /// the reads branch is data-gated on `independent`, so a c16-only (or
    /// absent) `RungReads` leaves `heroSource == .derived` and `readsSlice`
    /// nil — the hero never enters the reads bake.
    @MainActor
    @Test func derivedBurstKeepsThePooledPath() {
        let model = DecideModel(tiles: [], gene: nil)
        #expect(model.heroSource == .derived)
        #expect(model.readsSlice(frame: 0) == nil)
        // Attach a derived-signature reads value: STILL the pooled path.
        let c16 = [UInt64](repeating: 4096 * 800, count: 16 * 16 * 3)
        let derived = RungReads.build(from: CaptureSession.RungCubes(
            cube64: [], frames64: 0, cube32: [], frames32: 0,
            cube16: c16, frames16: 1,
            ownedTicks16: [3], fineBinArea: 64, ticksPerSlice16: 4))
        model.attachRungReads(derived)
        #expect(model.heroSource == .derived)
        #expect(model.readsSlice(frame: 0) == nil)
    }

    /// A ladder burst's reads attach late and flip the hero source; the
    /// arrival flips the cache keys' `hasReads` marker exactly once (repeat
    /// deliveries are no-ops — first delivery wins).
    @MainActor
    @Test func ladderReadsAttachAndFlipTheSource() {
        let cubes = CaptureSession.RungCubes(
            cube64: [UInt64](repeating: 64 * 5000, count: 64 * 64 * 3), frames64: 1,
            cube32: [UInt64](repeating: 256 * 5000, count: 32 * 32 * 3), frames32: 1,
            cube16: [UInt64](repeating: 1024 * 5000, count: 16 * 16 * 3), frames16: 1,
            ownedTicks64: [2], ownedTicks32: [10], ownedTicks16: [15],
            fineBinArea: 64, ticksPerSlice16: 1)
        let reads = RungReads.build(from: cubes)
        #expect(reads.independent)
        let model = DecideModel(tiles: [], gene: nil)
        #expect(model.heroCacheKey(rungK: 0, group: 0, useGene: false).hasReads == false)
        model.attachRungReads(reads)
        #expect(model.heroCacheKey(rungK: 0, group: 0, useGene: false).hasReads == true)
        #expect(model.heroSource == .rungReads)
        #expect(model.readsSlice(frame: 0) != nil)
        model.attachRungReads(reads)              // repeat delivery: no-op
        #expect(model.rungReads == reads)
        // The slide never touches the reads gate either way (display-only).
        model.startPlayback(rungK: 2, atTick: 0, fromFrame: 0)
        #expect(model.heroSource == .rungReads)
    }
}
