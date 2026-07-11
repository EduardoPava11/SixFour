import simd

/// EXACT 64-frame loop closure + the low-frequency temporal residual — the
/// hand-written Swift twin of `SixFour.Spec.TemporalLoop`, promoted by the
/// 2026-07-11 link ledger (wave 2; it was the audit's ONE kernel-only link:
/// the temporal-Haar half ships via `VoxelReduce`, but the loop-closure
/// algebra had no app-side realization).
///
/// Two integer facts make a SixFour loop exact and its motion smooth:
///
///  1. CLOSURE IS AN INDEX IDENTITY. The period is exactly 64 = 2⁶, so the
///     wrap `loopIndex(t) = t & 63` is a bitmask, not an approximation, and
///     `temporalCos(t + 64) == temporalCos(t)` for ALL t — frame 63 hands off
///     to exactly frame 0's value (unlike the CubeGIF lineage's approximate
///     period-19 seam). The closure depends only on the index algebra, never
///     on the cosine values, so it is float-independent.
///  2. MOTION IS LOW-FREQUENCY. One level of the OWNED reversible integer
///     Haar along the TIME axis splits a frame series into a smoothed low
///     band and a detail high band — LOSSLESSLY (`haarJoinTime` inverts
///     exactly), so `temporalResidual` (keep low, drop high) is an honest,
///     recoverable projection of the loop's motion. The pair lift uses the
///     same FLOORED halving as the `s4_haar_*` kernels (arithmetic shift,
///     never truncating division — they differ on negative details).
///
/// Pure values, no floats on any path (the LUT literals are golden-pinned
/// constants; the spec generates them once from the reference cosine).
enum TemporalLoop {

    /// The GIF length and cosine period — exactly 64 = 2⁶ (load-bearing:
    /// power-of-two is what makes the wrap a bitmask identity).
    static let period = 64

    /// The Q16 fixed-point scale of the cosine table.
    static let cosScaleQ16 = 65536

    /// The golden-pinned Q16 cosine table: `round(cos(2π·t/64)·2¹⁶)` with
    /// round-half-to-even, byte-identical to the spec's `cosLutQ16`.
    static let cosLutQ16: [Int32] = [
        65536, 65220, 64277, 62714, 60547, 57798, 54491, 50660,
        46341, 41576, 36410, 30893, 25080, 19024, 12785, 6424,
        0, -6424, -12785, -19024, -25080, -30893, -36410, -41576,
        -46341, -50660, -54491, -57798, -60547, -62714, -64277, -65220,
        -65536, -65220, -64277, -62714, -60547, -57798, -54491, -50660,
        -46341, -41576, -36410, -30893, -25080, -19024, -12785, -6424,
        0, 6424, 12785, 19024, 25080, 30893, 36410, 41576,
        46341, 50660, 54491, 57798, 60547, 62714, 64277, 65220,
    ]

    /// Wrap any frame index into [0, 63] — the bitmask identity (two's
    /// complement makes this agree with the spec's `mod` for negatives too).
    static func loopIndex(_ t: Int) -> Int { t & (period - 1) }

    /// The Q16 cosine modulation at frame `t`, exactly periodic — the basis
    /// of seamless looping.
    static func temporalCos(_ t: Int) -> Int32 { cosLutQ16[loopIndex(t)] }

    /// One forward pair lift `(x, y) → (parent, detail)` per channel, with
    /// the owned Haar's FLOORED halving (`&>> 1` = floor division by 2 —
    /// matches Haskell `div`; Swift `/` would truncate and drift on negative
    /// details, which `TemporalLoopTests` pins).
    static func liftPair(_ x: SIMD3<Int32>, _ y: SIMD3<Int32>) -> (parent: SIMD3<Int32>, detail: SIMD3<Int32>) {
        let d = x &- y
        return (y &+ (d &>> 1), d)
    }

    /// Exact inverse of `liftPair`.
    static func unliftPair(_ parent: SIMD3<Int32>, _ detail: SIMD3<Int32>) -> (x: SIMD3<Int32>, y: SIMD3<Int32>) {
        let y = parent &- (detail &>> 1)
        return (y &+ detail, y)
    }

    /// One Haar level over a frame series → (lowBand, highBand). Adjacent
    /// frames pair into a lifted parent (low) + detail (high); an odd
    /// trailing frame carries into the low band with no detail.
    static func haarSplitTime(_ series: [SIMD3<Int32>]) -> (low: [SIMD3<Int32>], high: [SIMD3<Int32>]) {
        var low = [SIMD3<Int32>]()
        var high = [SIMD3<Int32>]()
        low.reserveCapacity((series.count + 1) / 2)
        high.reserveCapacity(series.count / 2)
        var i = 0
        while i + 1 < series.count {
            let (p, d) = liftPair(series[i], series[i + 1])
            low.append(p)
            high.append(d)
            i += 2
        }
        if i < series.count { low.append(series[i]) }
        return (low, high)
    }

    /// Exact inverse of `haarSplitTime` — the losslessness that makes the
    /// residual an honest projection.
    static func haarJoinTime(low: [SIMD3<Int32>], high: [SIMD3<Int32>]) -> [SIMD3<Int32>] {
        var out = [SIMD3<Int32>]()
        out.reserveCapacity(low.count + high.count)
        for (i, p) in low.enumerated() {
            if i < high.count {
                let (x, y) = unliftPair(p, high[i])
                out.append(x)
                out.append(y)
            } else {
                out.append(p)   // the carried odd tail
            }
        }
        return out
    }

    /// The low-frequency temporal residual: the Haar low band, high band
    /// dropped — the displacement that carries the loop's motion.
    static func temporalResidual(_ series: [SIMD3<Int32>]) -> [SIMD3<Int32>] {
        haarSplitTime(series).low
    }

    /// LIVE READOUT: one temporal-Haar level over a burst's per-frame palette
    /// BARYCENTERS (the mean leaf per frame, floored) — how much of the
    /// loop's palette motion is high-frequency detail vs the smooth low band.
    /// Returns (lowFrames, highFrames, maxDetail = the largest |high-band|
    /// channel magnitude, Q16). Log-only consumer at the commit seam.
    static func burstTemporalSummary(paletteQ16Frames: [[SIMD3<Int32>]])
        -> (low: Int, high: Int, maxDetailQ16: Int32)? {
        guard !paletteQ16Frames.isEmpty else { return nil }
        let barycenters: [SIMD3<Int32>] = paletteQ16Frames.map { frame in
            guard !frame.isEmpty else { return SIMD3<Int32>(0, 0, 0) }
            var sum = SIMD3<Int64>(0, 0, 0)
            for leaf in frame {
                sum &+= SIMD3<Int64>(Int64(leaf.x), Int64(leaf.y), Int64(leaf.z))
            }
            let n = Int64(frame.count)
            // Floored division per channel (matches the owned Haar's flooring;
            // Swift `/` truncates, which differs on negative a/b sums).
            func fdiv(_ a: Int64) -> Int32 {
                let q = a / n
                return Int32(a % n != 0 && a < 0 ? q - 1 : q)
            }
            return SIMD3<Int32>(fdiv(sum.x), fdiv(sum.y), fdiv(sum.z))
        }
        let (low, high) = haarSplitTime(barycenters)
        var maxDetail: Int32 = 0
        for d in high {
            maxDetail = max(maxDetail, max(abs(d.x), max(abs(d.y), abs(d.z))))
        }
        return (low.count, high.count, maxDetail)
    }
}
