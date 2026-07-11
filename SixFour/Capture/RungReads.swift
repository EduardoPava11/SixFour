//  RungReads.swift
//  THE READS ON SCREEN — the hand-written Swift twin of `Spec.RungReadDisplay`
//  plus the off-main realizer that turns a burst's raw `CaptureSession.RungCubes`
//  (u64 linear16 BT.2020 sums, t-major owned slices) into display-ready sRGB8
//  rung volumes the Decide hero can composite per MERGE region.
//
//  Three problems, three exact answers (the spec's own framing):
//
//  • TIME — a rung's owned slices are SPARSE in burst time (the weave scatters
//    them), so the display holds CAUSALLY: `sliceForTick` shows the LAST owned
//    slice at or before the playhead tick, slice 0 before the first arrival
//    (`lawOwnedTickShowsOwnSlice` / `lawHoldIsCausal`). Naive `frame/2`
//    indexing is exactly the bug this kills.
//  • RADIOMETRY — realizing a u64 sum slice divides by the TRUE pixel base
//    `sliceRealizeCount` = fine-bin area × spatial pool × ticks-per-slice,
//    where ticks-per-slice is 1 for a ladder slice and 4 for the derived c16
//    (`lawSliceCountMatchesProvenance`). Reusing `ColorHead.emit16`'s
//    `lastCropArea*4` on a ladder slice over-counts ×4 = a 2-stop shift, or
//    trips the realize kernel's refusal — a refused rung is marked EMPTY, and
//    an empty rung drops the WHOLE hero back to the derived fallback.
//  • PROVENANCE — reads are claimed iff ALL THREE rungs realized
//    (`independent`; the c16-only shape is the derived signature and NEVER
//    claims reads, `lawDerivedNeverClaimsReads`). Pooled display stays the
//    honest fallback forever.
//
//  The per-frame sampler `frameSample` is `s4_render_select`'s index math
//  restricted to ONE voxel; `RungReadDisplayTests` gates it against the
//  whole-volume kernel authority (`lawSamplerMatchesRenderSelectWhenDense`).
//  Raw u64 cubes are DROPPED after realize — a full 24/12/4 ladder burst
//  retains ~330 KB of sRGB8 here instead of ~2.6 MB of sums.

import Foundation

/// One burst's realized independent rung reads (or the honest derived subset).
/// Built OFF-MAIN by `CaptureViewModel` after the `.s4cr` record write; folded
/// into σ (`Surface.rungReads`) and attached late to `DecideModel` — the
/// attachGene/attachSubstrate arrival pattern.
struct RungReads: Sendable, Equatable {

    /// One realized rung volume: `frames` t-major slices of `side²·3` sRGB8.
    struct Rung: Sendable, Equatable {
        /// Spatial side (64 / 32 / 16).
        let side: Int
        /// Owned slices realized (== `ownedTicks.count`).
        let frames: Int
        /// The burst tick (0…63) each slice landed on, strictly ascending —
        /// the causal hold's index (`sliceForTick`).
        let ownedTicks: [Int]
        /// `frames × side² × 3` sRGB8 bytes, t-major, bin = `(y·side+x)`.
        let rgb: [UInt8]
    }

    /// The fine 64-rung read (ladder mode only; nil = EMPTY).
    let r64: Rung?
    /// The mid 32-rung read (ladder mode only; nil = EMPTY).
    let r32: Rung?
    /// The coarse 16-rung read (ladder OR the derived c16; nil = EMPTY).
    let r16: Rung?

    /// The data gate for rendering a region from its own read — the twin of
    /// `Spec.RungReadDisplay.independentReads`: all three rungs realized. The
    /// c16-only derived shape answers false (`lawDerivedNeverClaimsReads`).
    var independent: Bool { r64 != nil && r32 != nil && r16 != nil }

    /// The rung a MERGE depth selects: 0 → 16², 1 → 32², 2 → 64² (the
    /// `MultiScaleLadder.Scale.rawValue` / RenderSelect depth code).
    func rung(atDepth d: Int) -> Rung? {
        switch min(2, max(0, d)) {
        case 0: return r16
        case 1: return r32
        default: return r64
        }
    }

    // MARK: - The exact display algebra (Spec.RungReadDisplay twins)

    /// Ticks summed into one LADDER cube slice: 1 (each owned frame is a
    /// single-tick slice — `Spec.RungReadDisplay.ladderTicksPerSlice`).
    static let ladderTicksPerSlice = 1

    /// Ticks summed into one DERIVED c16 slice:
    /// `Spec.MultiScaleCapture.fastPerSlow` = 4 (`ColorHead.cube16` appends
    /// 4-tick temporal sums — `derivedTicksPerSlice`).
    static let derivedTicksPerSlice = Int(S4_MS_FAST_PER_SLOW)

    /// The cube slice to SHOW at playhead tick `t` — the causal hold
    /// (`Spec.RungReadDisplay.sliceForTick`): the index of the LAST owned tick
    /// ≤ `t` (never evidence from the future), slice 0 before the first
    /// arrival. Slices sit in the cube in owned order, so this index IS the
    /// t-major slice index. `owned` must be ascending (the builder enforces it).
    static func sliceForTick(_ owned: [Int], _ t: Int) -> Int {
        var n = 0
        for o in owned where o <= t { n += 1 }
        return max(0, n - 1)
    }

    /// The EXACT per-bin sample count a sum slice divides by at realize — the
    /// twin of `Spec.RungReadDisplay.sliceRealizeCount`:
    /// `fineBinArea · (64/side)² · ticksPerSlice`. This is the `count`
    /// argument of `s4_sums_bt2020_to_srgb8`; a wrong count is a constant
    /// stop-shift or a kernel refusal. Non-positive or non-dividing sides
    /// answer 0 (totality; the ladder's sides are 16/32/64).
    static func sliceRealizeCount(side: Int, fineBinArea: Int64, ticksPerSlice: Int) -> Int64 {
        guard side > 0, 64 % side == 0 else { return 0 }
        let q = Int64(64 / side)
        return fineBinArea * q * q * Int64(ticksPerSlice)
    }

    /// The spacetime block a depth-d region replicates — `Spec.RenderSelect.
    /// blockSideAt`: 4 / 2 / 1, which ARE the capture cadence ratios
    /// (`fastPerSlow` / `midPerSlow` — render replication and capture nesting
    /// are one clock, `lawTemporalQuantizeOnSharedClock`).
    static func blockSideAt(_ d: Int) -> Int {
        4 >> min(2, max(0, d))
    }

    /// Quantize a display frame to its depth's window start on the shared
    /// 4:2:1 clock — `Spec.RungReadDisplay.temporalQuantize`: `(t/b)·b`, the
    /// frame a depth-d region's content is constant from
    /// (`lawTemporalReplicateOnSharedClock`, one frame at a time).
    static func temporalQuantize(depth d: Int, t: Int) -> Int {
        let b = blockSideAt(d)
        return (t / b) * b
    }

    /// The per-display-voxel sampler — `s4_render_select`'s index math
    /// restricted to ONE voxel (`Spec.RungReadDisplay.frameSample`), gated
    /// against the whole-volume kernel by `RungReadDisplayTests`
    /// (`lawSamplerMatchesRenderSelectWhenDense`): region on the `(side/4)`
    /// grid, clamp the depth, quantize on the shared clock, read the chosen
    /// scale's OWN volume at `(x/b, y/b, tq/b)` — SELECT, never a pool.
    /// Volumes are t-major flat arrays at sides `outSide/4` / `outSide/2` /
    /// `outSide`. nil on any out-of-range shape (totality, never a trap).
    static func frameSample(outSide: Int, depth: [Int32],
                            v16: [Int32], v32: [Int32], v64: [Int32],
                            x: Int, y: Int, t: Int) -> Int32? {
        guard outSide >= 4, outSide % 4 == 0,
              x >= 0, x < outSide, y >= 0, y < outSide, t >= 0, t < outSide
        else { return nil }
        let rgs = outSide / 4
        let region = ((t / 4) * rgs + (y / 4)) * rgs + (x / 4)
        guard region >= 0, region < depth.count else { return nil }
        let d = Int(min(2, max(0, depth[region])))
        let b = blockSideAt(d)
        let srcSide = outSide / b
        let si = ((t / b) * srcSide + (y / b)) * srcSide + (x / b)
        let src = [v16, v32, v64][d]
        guard si >= 0, si < src.count else { return nil }
        return src[si]
    }

    // MARK: - The builder (off-main; sums in, sRGB8 out, cubes dropped)

    /// Realize a burst's rung cubes into display volumes. Ladder cubes carry
    /// single-tick slices (`ladderTicksPerSlice`); the c16 cube's temporal
    /// base rides `cubes.ticksPerSlice16` (1 ladder / 4 derived — NEVER
    /// `ColorHead.emit16`'s `lastCropArea*4` blanket, the pinned ×4
    /// double-count). Any kernel refusal (`S4_RC_BAD_ARGS`, e.g. a mean over
    /// 65535 from a wrong count), shape mismatch, or non-ascending tick log
    /// marks that rung EMPTY — the honest whole-hero fallback trigger. Both
    /// burst modes pool through the x420 measurement path, so the sums are
    /// linear16 BT.2020 and realize via `s4_sums_bt2020_to_srgb8`
    /// (`Spec.RadiometricRealize`), exactly like `ColorHead.emit16`.
    static func build(from cubes: CaptureSession.RungCubes) -> RungReads {
        RungReads(
            r64: realizeRung(cube: cubes.cube64, frames: cubes.frames64, side: 64,
                             ownedTicks: cubes.ownedTicks64,
                             fineBinArea: cubes.fineBinArea,
                             ticksPerSlice: ladderTicksPerSlice),
            r32: realizeRung(cube: cubes.cube32, frames: cubes.frames32, side: 32,
                             ownedTicks: cubes.ownedTicks32,
                             fineBinArea: cubes.fineBinArea,
                             ticksPerSlice: ladderTicksPerSlice),
            r16: realizeRung(cube: cubes.cube16, frames: cubes.frames16, side: 16,
                             ownedTicks: cubes.ownedTicks16,
                             fineBinArea: cubes.fineBinArea,
                             ticksPerSlice: cubes.ticksPerSlice16))
    }

    /// One rung's realize: every t-major slice through the inverse-EOTF
    /// kernel at the exact pixel base. nil (EMPTY) on any refusal — never a
    /// wrong image.
    private static func realizeRung(cube: [UInt64], frames: Int, side: Int,
                                    ownedTicks: [Int], fineBinArea: Int64,
                                    ticksPerSlice: Int) -> Rung? {
        let sliceLen = side * side * 3
        guard frames > 0, cube.count == frames * sliceLen,
              ownedTicks.count == frames,
              zip(ownedTicks, ownedTicks.dropFirst()).allSatisfy({ $0 < $1 })
        else { return nil }
        let count = sliceRealizeCount(side: side, fineBinArea: fineBinArea,
                                      ticksPerSlice: ticksPerSlice)
        guard count > 0 else { return nil }
        var rgb = [UInt8](repeating: 0, count: frames * sliceLen)
        let ok = cube.withUnsafeBufferPointer { src -> Bool in
            rgb.withUnsafeMutableBufferPointer { dst -> Bool in
                for f in 0..<frames {
                    let rc = s4_sums_bt2020_to_srgb8(
                        src.baseAddress! + f * sliceLen, Int32(side), count,
                        dst.baseAddress! + f * sliceLen)
                    if rc != 0 { return false }   // refusal ⇒ the rung is EMPTY
                }
                return true
            }
        }
        guard ok else { return nil }
        return Rung(side: side, frames: frames, ownedTicks: ownedTicks, rgb: rgb)
    }

    // MARK: - The per-region compositor (the Decide hero's READS frame)

    /// One 64² RGBA display frame where every MERGE region shows ITS OWN
    /// read: per board region at depth d, select the rung (16/32/64), quantize
    /// the frame on the shared 4:2:1 clock, hold causally to the last owned
    /// slice (`sliceForTick`), block-replicate the bin's sRGB8 over
    /// `(64/side)` px — the same visible chunk geometry as the derived
    /// `pooled()` display, different SOURCE. BINARY WHOLE-HERO: nil unless
    /// ALL THREE rungs are present (`independent`) — camera sRGB8 and
    /// Q16-OKLab reconstruction never mix inside one frame.
    func composited(frame: Int, depths: [Int]) -> [UInt8]? {
        guard independent, depths.count == S4MergeBoard.regionCount else { return nil }
        let t = min(63, max(0, frame))
        // Resolve each region's (rung, slice) once — 16 lookups, not 4096.
        struct Src { let rung: Rung; let sliceBase: Int }
        var srcs = [Src]()
        srcs.reserveCapacity(S4MergeBoard.regionCount)
        for region in 0 ..< S4MergeBoard.regionCount {
            let d = min(S4MergeBoard.maxDepth, max(S4MergeBoard.minDepth, depths[region]))
            guard let rung = rung(atDepth: d) else { return nil }
            // The causal hold runs on the RAW playhead tick. Quantizing first
            // (the dense sampler's move) makes any slice landing late in a
            // window unreachable — the weave's c16 ticks are [15,31,47,63],
            // all ≡ 3 mod 4, so a depth-0 quantize (multiples of 4) would
            // never reach the last slice and lag every other by one window.
            // Owned slices are SPARSE: the hold IS their temporal indexing
            // (`lawHoldIsCausal`); `temporalQuantize` belongs only to the
            // dense `frameSample`.
            let slice = min(rung.frames - 1, Self.sliceForTick(rung.ownedTicks, t))
            srcs.append(Src(rung: rung, sliceBase: slice * rung.side * rung.side * 3))
        }
        var rgba = [UInt8](repeating: 255, count: 64 * 64 * 4)
        for y in 0 ..< 64 {
            for x in 0 ..< 64 {
                let src = srcs[S4MergeBoard.regionOfPixel(x: x, y: y)]
                let s = src.rung.side
                let bin = ((y * s) / 64) * s + ((x * s) / 64)
                let i = src.sliceBase + bin * 3
                let o = (y * 64 + x) * 4
                rgba[o] = src.rung.rgb[i]
                rgba[o + 1] = src.rung.rgb[i + 1]
                rgba[o + 2] = src.rung.rgb[i + 2]
            }
        }
        return rgba
    }

    // MARK: - The record fixture (DEBUG bring-up tooling only)

    #if DEBUG
    /// FIXTURE-ONLY: rebuild reads from a record's raw cube arrays (the
    /// `.s4cr` v2 `c64`/`c32`/`c16` values). The wire does not persist owned
    /// ticks yet, so they are RECONSTRUCTED via the settle-2 dwell rule
    /// (`MultiScaleLadder.weavePlan(settleFrames: 2)` — brittle if
    /// `settleFrames` ever changes; persisting the ticks is a future record
    /// version). A c16-only shape is treated as the derived signature (5 Hz
    /// realize ticks, ×4 temporal base) and honestly never claims reads.
    static func fixture(cube64: [UInt64], cube32: [UInt64], cube16: [UInt64],
                        fineBinArea: Int64) -> RungReads {
        let f64 = cube64.count / (64 * 64 * 3)
        let f32 = cube32.count / (32 * 32 * 3)
        let f16 = cube16.count / (16 * 16 * 3)
        let derived = f64 == 0 && f32 == 0
        let plan = MultiScaleLadder.weavePlan(settleFrames: 2)
        func planTicks(_ sc: MultiScaleLadder.Scale, _ n: Int) -> [Int] {
            Array(plan.indices.filter { plan[$0].scale == sc && plan[$0].owned }.prefix(n))
        }
        let cubes = CaptureSession.RungCubes(
            cube64: cube64, frames64: f64,
            cube32: cube32, frames32: f32,
            cube16: cube16, frames16: f16,
            ownedTicks64: planTicks(.fine64, f64),
            ownedTicks32: planTicks(.mid32, f32),
            ownedTicks16: derived ? (0..<f16).map { $0 * 4 + 3 }
                                  : planTicks(.coarse16, f16),
            fineBinArea: fineBinArea,
            ticksPerSlice16: derived ? derivedTicksPerSlice : ladderTicksPerSlice)
        return build(from: cubes)
    }
    #endif
}
