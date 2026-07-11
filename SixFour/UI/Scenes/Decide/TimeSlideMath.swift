//  TimeSlideMath.swift
//  THE TIME SLIDE — the hand-written Swift twin of `Spec.TimeSlide`
//  (source of truth: spec/src/SixFour/Spec/TimeSlide.hs, proven by `cabal test`).
//
//  One vertical finger slide dilates the Decide hero's playback between the
//  THREE LAWFUL RUNGS, and every quantity it displays is an exact integer of
//  the ladder:
//
//  • The slide QUANTIZES to a detent k ∈ {0,1,2} (`detentOf` — `cellsPerDetent`
//    hero-lattice cells of travel per rung step, down = coarser). FLOOR
//    division, never truncation: Haskell `div` floors, Swift `/` truncates
//    toward zero, and the two diverge on the negative (upward) branch
//    (`lawDivRoundHalfUpNegatives` pins the same discipline).
//  • A detent's playback period is EXACTLY the rung's weave units
//    (`periodOf` = `Spec.WeaveOrder.unitsOf` = 2^k — 1/2/4 ticks =
//    20/10/5 Hz). The seductive 3-tick delay is REFUSED: 64 mod 3 ≠ 0 cannot
//    tile the window (`lawDetentsAreRungs`).
//  • The playhead is a pure function of the ONE 20 Hz tick (`pos`, anchored at
//    the latch); the group it shows steps exactly on the realize ticks
//    (`lawGroupChangesExactlyOnRealize`), and the group window IS the poured
//    window ENDING at the realize tick (`lawGroupWindowIsPouredWindow` — the
//    off-by-one killer vs `goldenSchedule16`).
//  • A coarse detent's frame is a TRUE temporal integral: Int64 sums over the
//    ALIGNED group window, ONE `divRoundHalfUp` by the frame count 2^k —
//    never the spatial ride-along 8^k (`lawIntegralIsSumsDividedOnce`), total
//    over the NEGATIVE Q16 OKLab a/b channels.
//  • Wall time is INVARIANT: the loop is 64 ticks = 320 cs at EVERY detent
//    (`lawLoopWallTimeInvariant`) — "slower" is chunkier holds, never a
//    longer loop.
//  • The slide is DISPLAY ONLY: no detent or playhead transition ever emits a
//    game op (`lawSlideNeverWritesTheWord`, pinned at the model boundary by
//    `MergeBoardTests` — the decision word is THE MERGE's alone).
//
//  Cross-language goldens (`goldenPlayhead16`, `goldenVolumeQ16`,
//  `goldenIntegralQ16`) are mirrored VERBATIM from the Haskell module and
//  gated by `TimeSlideMathTests`. Pure integer value math, display side only.

/// Pure integer twin of `Spec.TimeSlide`. Never touches `S4MergeBoard` state,
/// the decision word, `.s4cr` bytes, or GIF bytes — display math only.
enum TimeSlideMath {

    // MARK: The slide → detent quantizer

    /// THE ONE NAMED TUNING INTEGER (`Spec.TimeSlide.cellsPerDetent`):
    /// hero-lattice cells of vertical finger travel per rung step
    /// (16 = one region side). Retuning the slide's feel on device is a
    /// one-line, spec-visible change here — never a scattered float.
    static let cellsPerDetent = 16

    /// The finest/coarsest detents: the three lawful rungs are k ∈ {0,1,2}.
    static let minDetent = 0
    static let maxDetent = 2

    /// The 64-frame loop (`Spec.WeaveOrder.windowUnits` — ticks = frames =
    /// units). DELEGATED to the one Swift owner
    /// (`ColorTimeDisplayMath.burstFrames`), never a free 64.
    static let windowUnits = ColorTimeDisplayMath.burstFrames

    /// The loop's wall time: `Spec.WeaveOrder.windowCs` = 320 cs at EVERY
    /// detent (`lawLoopWallTimeInvariant`) — the window × the fine GCE delay,
    /// both delegated integers, never a free 320.
    static let windowCs = windowUnits * delayCsOf(0)

    /// Haskell `div` — FLOOR division (Swift `/` truncates toward zero; the
    /// two differ exactly on negative operands, the upward slide branch).
    /// DELEGATED to the kernel core's one implementation (`s4DivFloor64`,
    /// the same floor every golden-gated kernel rounds with) — a third
    /// hand-copy of the negative-branch discipline is exactly how a future
    /// fix misses one.
    @inline(__always)
    static func floorDiv(_ a: Int, _ b: Int) -> Int {
        Int(s4DivFloor64(Int64(a), Int64(b)))
    }

    /// Quantize a slide to a detent (`Spec.TimeSlide.detentOf`):
    /// `min 2 (max 0 (kAtLatch + dyCells div cellsPerDetent))` — the detent
    /// latched when the finger went down, moved one rung per `cellsPerDetent`
    /// cells of travel, clamped to the three lawful rungs. Downward travel
    /// (positive dy) is COARSER. FLOOR semantics pinned: the negative
    /// (upward) branch crosses its first detent one cell in
    /// (`lawDetentTotal` / `lawDetentMonotone` / `lawDetentEndpoints`).
    static func detentOf(kAtLatch: Int, dyCells: Int) -> Int {
        min(maxDetent, max(minDetent, kAtLatch + floorDiv(dyCells, cellsPerDetent)))
    }

    // MARK: Detents are rungs

    /// A detent's playback period in ticks (`Spec.TimeSlide.periodOf` =
    /// `Spec.WeaveOrder.unitsOf` = 2^k): 1/2/4 ticks = 20/10/5 Hz. TRUE
    /// DELEGATION — reads `ColorTimeDisplayMath.displayPeriodTicks` (the one
    /// Swift owner of the pool-depth ladder), so a ladder change moves the
    /// slide's cadence by compile-time link, not by remembering a parity test.
    @inline(__always)
    static func periodOf(_ k: Int) -> Int {
        ColorTimeDisplayMath.displayPeriodTicks[min(maxDetent, max(minDetent, k))]
    }

    /// The spatial side a detent names: 64/32/16 (`Spec.ColorTime.coarseSide`).
    @inline(__always)
    static func coarseSide(_ k: Int) -> Int {
        64 >> min(maxDetent, max(minDetent, k))
    }

    /// The detent's GIF89a GCE delay in centiseconds: 5/10/20 cs — TRUE
    /// DELEGATION to THE TIME LAW kernel itself (`s4_ladder_delay_cs`,
    /// `Spec.WeaveOrder.delayCsOf` / `lawDelayMatchesFloorLaw`): the readout
    /// chip displays the same integer the encoder writes, by construction.
    @inline(__always)
    static func delayCsOf(_ k: Int) -> Int {
        Int(s4_ladder_delay_cs(Int32(coarseSide(k))))
    }

    /// The two-sided detent readout the slide's transient CellText shows:
    /// the rung's side paired with its exact GCE delay —
    /// "64 - 5cs" / "32 - 10cs" / "16 - 20cs". Both integers are theorems of
    /// the ladder, never display copy.
    static func readoutLabel(_ k: Int) -> String {
        "\(coarseSide(k)) - \(delayCsOf(k))cs"
    }

    // MARK: The playhead on the one clock

    /// The playhead frame at `tick`, anchored at the latch
    /// (`Spec.TimeSlide.pos`): `(anchorFrame + (tick − anchorTick)) mod 64` —
    /// one frame per tick around the 64-frame loop, TOTAL over ticks before
    /// the anchor (the mod keeps it in 0…63). The playhead is a pure function
    /// of the ONE 20 Hz `SurfaceClock.tick`; no second timer exists.
    static func pos(anchorTick: Int, anchorFrame: Int, tick: Int) -> Int {
        let raw = (anchorFrame + (tick - anchorTick)) % windowUnits
        return raw < 0 ? raw + windowUnits : raw
    }

    /// The display group the playhead sits in at detent `k`
    /// (`Spec.TimeSlide.displayGroup`): `pos` divided by the period 2^k — the
    /// index of the temporal-integral frame the hero SHOWS. The latch
    /// convention (the runtime invariant `DecideModel` honors via
    /// `snapToGroupStart`) snaps `anchorFrame` to a group boundary, so the
    /// group steps exactly on the realize ticks
    /// (`lawGroupChangesExactlyOnRealize` — the bake gate IS the realize gate).
    static func displayGroup(k: Int, anchorTick: Int, anchorFrame: Int, tick: Int) -> Int {
        pos(anchorTick: anchorTick, anchorFrame: anchorFrame, tick: tick) / periodOf(k)
    }

    /// The latch convention as a function: snap a frame DOWN to its group
    /// boundary at detent `k` — the anchor frame every (re-)anchor must use so
    /// `lawGroupChangesExactlyOnRealize` holds on device.
    static func snapToGroupStart(_ frame: Int, k: Int) -> Int {
        let p = periodOf(k)
        let f = min(windowUnits - 1, max(0, frame))
        return (f / p) * p
    }

    /// The LAST frame of group `j` at detent `k`
    /// (`Spec.TimeSlide.groupEndFrame`): `j·2^k + 2^k − 1` — the
    /// `Spec.ColorTimeDisplay.pouredWindow` END frame (the window ENDS at the
    /// realize tick, `lawGroupWindowIsPouredWindow`), i.e. the playhead value
    /// right after that group's realize.
    static func groupEndFrame(group j: Int, k: Int) -> Int {
        j * periodOf(k) + periodOf(k) - 1
    }

    // MARK: The temporal integral (divide once, round half up)

    /// Round-half-up integer mean (`Spec.TimeSlide.divRoundHalfUp`):
    /// `floor((2s + n) / (2n))` — DELEGATED to the kernel core's floor
    /// division (`s4DivFloor64`, the identical `q−1` correction every
    /// golden-gated realize rounds with — e.g. the palette kernels'
    /// `s4DivFloor64(dot + 16384, 32768)`). Halves round UP (toward +∞):
    /// −1.5 → −1; `lawDivRoundHalfUpNegatives` pins `(−5)/4 → −1` where a
    /// truncating port answers 0. Non-positive divisors answer 0 (totality;
    /// the ladder's divisors are 2^k ≥ 1).
    static func divRoundHalfUp(_ s: Int64, _ n: Int64) -> Int64 {
        guard n > 0 else { return 0 }
        return s4DivFloor64(2 * s + n, 2 * n)
    }

    /// THE INTEGRAL FRAME of group `j` at detent `k` over a generic
    /// frames × voxels volume (`Spec.TimeSlide.integralQ16` — the exact
    /// Haskell mirror the goldens ride): per voxel, the Int64 SUM over the
    /// aligned window `[j·2^k … j·2^k+2^k−1]`, then ONE `divRoundHalfUp` by
    /// the FRAME count 2^k (`lawIntegralIsSumsDividedOnce` — sums are the
    /// transitive carrier, the divide happens once at the display boundary,
    /// and the divisor is NEVER the spatial ride-along 8^k). Frames or voxels
    /// outside the volume read 0 (totality); the voxel width is frame 0's.
    static func integralQ16(k kRaw: Int, group j: Int, volume: [[Int64]]) -> [Int64] {
        let k = min(maxDetent, max(minDetent, kRaw))
        let p = periodOf(k)
        let nVox = volume.first?.count ?? 0
        return (0 ..< nVox).map { v in
            var s: Int64 = 0
            for f in (j * p) ..< (j * p + p) where f >= 0 && f < volume.count {
                let fr = volume[f]
                if v < fr.count { s += fr[v] }
            }
            return divRoundHalfUp(s, Int64(p))
        }
    }

    /// The DEVICE-VOLUME integral frame: the same law
    /// (`lawIntegralIsSumsDividedOnce` / `lawIntegralFineIsIdentity`) over the
    /// hero's interleaved reconstruction volume
    /// (`((t·64+row)·64+col)·3+ch` Int32 Q16 OKLab, `OctantCube.expandProposal`
    /// layout). Int64 accumulators, ONE divide by 2^k. k=0 returns the group's
    /// single frame untouched (the identity — the 64-rung playback shows the
    /// frames byte-for-byte). Missing frames read 0 (totality — short volumes
    /// never trap).
    static func integralFrame64(volume: [Int32], group j: Int, k kRaw: Int) -> [Int32] {
        let k = min(maxDetent, max(minDetent, kRaw))
        let p = periodOf(k)
        let frameLen = 64 * 64 * 3
        let frames = volume.count / frameLen
        var sums = [Int64](repeating: 0, count: frameLen)
        for f in (j * p) ..< (j * p + p) where f >= 0 && f < frames {
            let base = f * frameLen
            for v in 0 ..< frameLen {
                sums[v] += Int64(volume[base + v])
            }
        }
        let n = Int64(p)
        return sums.map { Int32(clamping: divRoundHalfUp($0, n)) }
    }

    // MARK: The cross-language goldens

    /// The 16-tick playhead golden (`Spec.TimeSlide.goldenPlayhead16`,
    /// mirrored VERBATIM): per detent k ∈ {0,1,2} and tick t ∈ 0…15 (anchor
    /// tick 0, anchor frame 0) — (k, t, playhead frame, display group,
    /// realizes?). The realize gating is `goldenSchedule16`'s, keyed by
    /// detent. `TimeSlideMathTests` re-derives every row.
    static let goldenPlayhead16: [(k: Int, t: Int, frame: Int, group: Int, realizes: Bool)] =
        (0 ... 2).flatMap { k in
            (0 ... 15).map { t in
                (k: k, t: t,
                 frame: pos(anchorTick: 0, anchorFrame: 0, tick: t),
                 group: displayGroup(k: k, anchorTick: 0, anchorFrame: 0, tick: t),
                 realizes: ColorTimeDisplayMath.realizesAt(period: periodOf(k), tick: t))
            }
        }

    /// The golden integral volume (`Spec.TimeSlide.goldenVolumeQ16`, mirrored
    /// VERBATIM): 4 frames × 12 voxels (2×2 spatial × 3 channels,
    /// channel-interleaved) with NEGATIVE a/b entries throughout — the
    /// rounding vectors a truncating port trips on.
    static let goldenVolumeQ16: [[Int64]] = [
        [4, -3, 2, -5, 0, 7, 1, -1, 6, -6, 3, -2],
        [6, -4, 1, -5, 1, 8, 2, -2, 5, -7, 4, -3],
        [5, -6, 3, -4, 2, 9, 3, -3, 4, -8, 5, -4],
        [7, -5, 4, -6, 3, 10, 4, -4, 3, -9, 6, -5],
    ]

    /// The golden integral frames of `goldenVolumeQ16` per detent
    /// (`Spec.TimeSlide.goldenIntegralQ16`): (k, groups) for k ∈ {0,1,2} —
    /// 4 identity frames at k=0, 2 pair-integrals at k=1, 1 whole-window
    /// integral at k=2. The literal expected values (hand-derived in the
    /// Haskell battery) are pinned in `TimeSlideMathTests` byte-for-byte.
    static let goldenIntegralQ16: [(k: Int, groups: [[Int64]])] =
        (0 ... 2).map { k in
            (k: k, groups: (0 ..< goldenVolumeQ16.count / periodOf(k)).map { j in
                integralQ16(k: k, group: j, volume: goldenVolumeQ16)
            })
        }
}
