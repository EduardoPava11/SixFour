import Foundation
import simd

/// **Significance-preserving split-fill** — the producer that makes every
/// per-frame palette slot *statistically significant*.
///
/// Significance is **population** (see `SixFour.Spec.Significance` /
/// `SixFourSignificance`): a palette slot is significant iff it is backed by
/// at least `SixFourSignificance.minPopulation` pixels. The slot then owns the
/// OKLab range `mean ± z_α·σ` of *its own* member population — a real "range
/// for each bin", never a lone outlier.
///
/// This replaced the earlier worst-fit *donation* rescue, which filled an
/// empty slot with the single highest-error pixel — a slot of population 1
/// sitting on an outlier. `rescue` here instead, for each under-populated slot
/// `k`, pulls the pixels **nearest to `palette[k]`** out of surplus slots until
/// `k` reaches `minPopulation`. The donated pixels genuinely belong near slot
/// `k`, so the slot's range is tight and real, and `Set(indices).count == K`
/// still holds (surjectivity).
///
/// Termination / "cannot fail": with `P = H·W = 4096` pixels and `K = 256`
/// slots, `P = 16·K ≥ minPopulation·K` (4096 ≥ 512), so total surplus always
/// covers total deficit (`surplus − deficit = P − minPopulation·K ≥ 0`).
/// Donors are only ever taken from slots still above `minPopulation`, so a pull
/// never creates a new deficit. The loop therefore always completes with every
/// slot significant — see the Haskell oracle `splitFillFrame` and law
/// `lawSigAllSignificant`.
enum SignificantSplitFill {

    /// Force every palette slot to hold `≥ minPopulation` pixels (which
    /// implies surjectivity), pulling in-range donor pixels — never the global
    /// worst-fit. Returns the (unchanged) palette and the repaired indices.
    /// Already-significant frames are returned untouched (fast path).
    static func rescue(
        palette: [SIMD3<Float>],
        indices: [UInt8],
        pixels: [SIMD3<Float>],
        K: Int = SixFourShape.K
    ) -> (palette: [SIMD3<Float>], indices: [UInt8]) {
        let nMin = SixFourSignificance.minPopulation
        precondition(palette.count == K, "split-fill: palette must have K entries")
        precondition(indices.count == pixels.count, "split-fill: indices/pixels length mismatch")
        precondition(pixels.count >= K * nMin, "split-fill: need ≥ K·minPopulation pixels")

        var counts = [Int](repeating: 0, count: K)
        for ix in indices { counts[Int(ix)] += 1 }
        if counts.allSatisfy({ $0 >= nMin }) { return (palette, indices) }  // already significant

        var idx = indices
        for k in 0..<K where counts[k] < nMin {
            let target = palette[k]
            while counts[k] < nMin {
                // Nearest-to-palette[k] pixel from a slot that can spare one
                // (count > nMin). In-range by construction → not an outlier.
                var bestI = -1
                var bestD = Float.greatestFiniteMagnitude
                for i in 0..<idx.count {
                    let s = Int(idx[i])
                    if s == k || counts[s] <= nMin { continue }
                    let d = simd_length_squared(pixels[i] - target)
                    if d < bestD { bestD = d; bestI = i }
                }
                if bestI < 0 { break }  // infeasible shape — unreachable when P ≥ K·nMin
                counts[Int(idx[bestI])] -= 1
                idx[bestI] = UInt8(k)
                counts[k] += 1
            }
        }
        return (palette, idx)
    }

    /// The per-frame palette cells for the `SignificantVoxelVolume` brand: one
    /// `SixFourSignificantCell` per slot, carrying the member population's mean,
    /// per-axis std-dev (√ of the OKLab covariance diagonal → the range
    /// `mean ± z·σ`), count, and provenance. Counts come from the final index
    /// assignment, so `Σ count = pixels.count` (mass conservation) and — after
    /// `rescue` — every count is `≥ minPopulation` (all `.extracted`).
    static func cells(
        palette: [SIMD3<Float>],
        indices: [UInt8],
        pixels: [SIMD3<Float>],
        K: Int = SixFourShape.K
    ) -> [SixFourSignificantCell] {
        var sumX  = [SIMD3<Float>](repeating: .zero, count: K)
        var sumX2 = [SIMD3<Float>](repeating: .zero, count: K)
        var counts = [Int](repeating: 0, count: K)
        for i in 0..<indices.count {
            let k = Int(indices[i])
            let p = pixels[i]
            sumX[k]  += p
            sumX2[k] += p * p
            counts[k] += 1
        }
        let nMin = SixFourSignificance.minPopulation
        let zero3 = SIMD3<Float>(repeating: 0)
        return (0..<K).map { k in
            let n = counts[k]
            if n == 0 {
                // Unreachable post-rescue; honest fallback for a raw assignment.
                return SixFourSignificantCell(mean: palette[k], stdDev: zero3,
                                              count: 0, provenance: .degenerate)
            }
            let nf = Float(n)
            let mean = sumX[k] / nf
            // Population variance per axis: E[x²] − μ², clamped ≥ 0.
            let variance = simd_max(zero3, sumX2[k] / nf - mean * mean)
            let std = SIMD3<Float>(variance.x.squareRoot(),
                                   variance.y.squareRoot(),
                                   variance.z.squareRoot())
            let prov: SixFourProvenance = n >= nMin ? .extracted : .degenerate
            return SixFourSignificantCell(mean: mean, stdDev: std, count: n, provenance: prov)
        }
    }
}
