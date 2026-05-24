import Foundation
import simd

/// Wu 1992 variance-based color quantization, adapted to OKLab.
///
/// "Color quantization by dynamic programming and principal analysis"
/// (Xiaolin Wu, ACM Transactions on Graphics vol. 11(4), 1992,
/// pp. 348-372). The recursive-bipartition family representative
/// for `PaletteExtractor`.
///
/// ## Algorithm
///
/// 1. Quantize the 4096 OKLab pixels into a 32-bin-per-axis 3D
///    histogram (32³ ≈ 33K cells). Each cell accumulates 10
///    moments: count, three linear sums (L, a, b), three squared
///    sums (LL, aa, bb), three cross-products (La, Lb, ab).
/// 2. Build 3D cumulative tables (prefix sums) for each moment.
///    Given any axis-aligned box, the box's total of any moment is
///    then a single 8-corner inclusion-exclusion lookup in O(1).
/// 3. Start with one box covering the whole 32³ volume.
/// 4. Pop the box with highest "weighted variance" (= within-box
///    sum of squared error, a.k.a. WCSS contribution). Find the
///    axis along which splitting reduces WCSS the most; find the
///    split position that maximizes the reduction. Push the two
///    child boxes.
/// 5. Repeat step 4 until K boxes exist.
/// 6. Each final box becomes a cluster. Mean and covariance come
///    straight from the box's prefix-sum moments. Each pixel is
///    assigned to the box that contains its quantized cell.
///
/// ## Why this is the recursive-bipartition representative
///
/// Wu strictly dominates median-cut (the obvious alternative in
/// this family) on quality at the same K, because:
/// - Median-cut splits at the median, which minimizes count
///   imbalance but ignores variance. Wu splits at the variance-
///   minimizing position, which directly minimizes the global WCSS.
/// - Median-cut picks the split axis as the longest axis of the
///   box's bounding region. Wu picks the axis that produces the
///   largest WCSS reduction — usually the axis with highest
///   within-box variance, but the optimization is direct.
///
/// ## Per-cluster statistics
///
/// Because each cluster IS a box (axis-aligned, populated by the
/// pixels that fall into that volume), the (μ, Σ, count) come for
/// free from the moment prefix sums. No second pass needed for
/// covariance — Σ = E[xxᵀ] − μμᵀ where E[xxᵀ] is the box's
/// outer-product moment / box count. This is the key reason Wu is
/// the chosen representative: rich statistics fall out of the
/// algorithm rather than being bolted on.
struct WuExtractor: PaletteExtractor {
    /// Bins per OKLab axis. 32 gives 32³ ≈ 33K cells — fine
    /// granularity for the recursive splits, total prefix-sum
    /// memory ~1.3 MB per tile (10 tables × 32³ × 4 bytes).
    /// Allocations are per-extract; transient memory.
    static let binsPerAxis: Int = 32

    var family: ClusterStatistics.Family { .recursiveBipartitionWu }

    func extract(tile: OKLabTile, K: Int) throws -> ClusterStatistics {
        let started = ContinuousClock().now
        let N = Self.binsPerAxis
        let pixelCount = tile.side * tile.side

        // 1. Build 10 histogram tables. Each indexed by Morton-flat
        //    [iL * N*N + ia * N + ib]. Using Double for accumulation
        //    to avoid precision loss across 4096 additions of small
        //    OKLab values; downcast to Float for the final covariance.
        var hist     = [Double](repeating: 0, count: N * N * N)
        var sumL     = [Double](repeating: 0, count: N * N * N)
        var sumA     = [Double](repeating: 0, count: N * N * N)
        var sumB     = [Double](repeating: 0, count: N * N * N)
        var sumLL    = [Double](repeating: 0, count: N * N * N)
        var sumAA    = [Double](repeating: 0, count: N * N * N)
        var sumBB    = [Double](repeating: 0, count: N * N * N)
        var sumLA    = [Double](repeating: 0, count: N * N * N)
        var sumLB    = [Double](repeating: 0, count: N * N * N)
        var sumAB    = [Double](repeating: 0, count: N * N * N)
        // Per-pixel quantized cell index, used both during bipartition
        // (to know which box owns which pixel) and during final
        // assignment readout.
        var cellOfPixel = [Int](repeating: 0, count: pixelCount)

        for p in 0..<pixelCount {
            let lab = tile.pixels[p]
            let iL = Self.quantizeL(lab.x)
            let ia = Self.quantizeAB(lab.y)
            let ib = Self.quantizeAB(lab.z)
            let cell = iL * N * N + ia * N + ib
            cellOfPixel[p] = cell
            let L = Double(lab.x), A = Double(lab.y), B = Double(lab.z)
            hist[cell]  += 1
            sumL[cell]  += L
            sumA[cell]  += A
            sumB[cell]  += B
            sumLL[cell] += L * L
            sumAA[cell] += A * A
            sumBB[cell] += B * B
            sumLA[cell] += L * A
            sumLB[cell] += L * B
            sumAB[cell] += A * B
        }

        // 2. 3D cumulative sums (in-place, three sweeps).
        Self.cumulate3D(&hist,  N: N)
        Self.cumulate3D(&sumL,  N: N)
        Self.cumulate3D(&sumA,  N: N)
        Self.cumulate3D(&sumB,  N: N)
        Self.cumulate3D(&sumLL, N: N)
        Self.cumulate3D(&sumAA, N: N)
        Self.cumulate3D(&sumBB, N: N)
        Self.cumulate3D(&sumLA, N: N)
        Self.cumulate3D(&sumLB, N: N)
        Self.cumulate3D(&sumAB, N: N)

        // 3-5. Recursive bipartition. Box ranges are HALF-OPEN
        // [lo, hi) along each axis (0 ≤ lo < hi ≤ N). Variance
        // (within-box sum of squared error) drives the split queue.
        var boxes: [Box] = [Box(loL: 0, hiL: N, loA: 0, hiA: N, loB: 0, hiB: N)]
        boxes[0].wcss = Self.wcss(box: boxes[0],
                                  hist: hist, sumL: sumL, sumA: sumA, sumB: sumB,
                                  sumLL: sumLL, sumAA: sumAA, sumBB: sumBB)

        while boxes.count < K {
            // Linear scan for highest WCSS — K is at most 256, so
            // O(K²) total = 65K compares. Negligible vs prefix-sum
            // construction.
            var bestI = 0
            var bestWCSS = boxes[0].wcss
            for i in 1..<boxes.count {
                if boxes[i].wcss > bestWCSS {
                    bestWCSS = boxes[i].wcss
                    bestI = i
                }
            }
            // Cannot split a single-cell box; bail with the current
            // K (the consumer pads empty clusters).
            let parent = boxes[bestI]
            guard parent.canSplit else { break }
            // Find the best split (axis + position + child WCSSs).
            guard let split = Self.bestSplit(
                box: parent,
                hist: hist, sumL: sumL, sumA: sumA, sumB: sumB,
                sumLL: sumLL, sumAA: sumAA, sumBB: sumBB
            ) else { break }
            boxes.remove(at: bestI)
            boxes.append(split.left)
            boxes.append(split.right)
        }

        // 6. Build ClusterStatistics. Pad to K with empty clusters
        // if bipartition terminated early (single-color images).
        var clusters: [ClusterStatistics.Cluster] = []
        clusters.reserveCapacity(K)
        for box in boxes {
            let m = Self.moments(box: box,
                                 hist: hist, sumL: sumL, sumA: sumA, sumB: sumB,
                                 sumLL: sumLL, sumAA: sumAA, sumBB: sumBB,
                                 sumLA: sumLA, sumLB: sumLB, sumAB: sumAB)
            if m.count == 0 {
                clusters.append(ClusterStatistics.Cluster(
                    mean: .zero,
                    covariance: ClusterStatistics.Cluster.emptyCovariance,
                    count: 0
                ))
            } else {
                let inv = 1.0 / m.count
                let mL = m.sumL * inv
                let mA = m.sumA * inv
                let mB = m.sumB * inv
                // Σ = E[xxᵀ] − μμᵀ; clamp tiny negatives to 0 to
                // keep Σ PSD against numerical drift.
                let LL = max(0, m.sumLL * inv - mL * mL)
                let aa = max(0, m.sumAA * inv - mA * mA)
                let bb = max(0, m.sumBB * inv - mB * mB)
                let La = m.sumLA * inv - mL * mA
                let Lb = m.sumLB * inv - mL * mB
                let ab = m.sumAB * inv - mA * mB
                let sigma = simd_float3x3(
                    columns: (
                        SIMD3<Float>(Float(LL), Float(La), Float(Lb)),
                        SIMD3<Float>(Float(La), Float(aa), Float(ab)),
                        SIMD3<Float>(Float(Lb), Float(ab), Float(bb))
                    )
                )
                clusters.append(ClusterStatistics.Cluster(
                    mean: SIMD3<Float>(Float(mL), Float(mA), Float(mB)),
                    covariance: sigma,
                    count: UInt32(m.count)
                ))
            }
        }
        while clusters.count < K {
            clusters.append(ClusterStatistics.Cluster(
                mean: .zero,
                covariance: ClusterStatistics.Cluster.emptyCovariance,
                count: 0
            ))
        }

        // Build cell → cluster lookup for assignments. Each box owns
        // an axis-aligned range of cells; the boxes partition the
        // 32³ volume so every cell belongs to exactly one cluster
        // (after termination — early-terminated extractions may
        // leave unowned cells, which we route to cluster 0 as a
        // numerical safety net).
        var cellCluster = [UInt16](repeating: 0, count: N * N * N)
        for (k, box) in boxes.enumerated() {
            for iL in box.loL..<box.hiL {
                for ia in box.loA..<box.hiA {
                    for ib in box.loB..<box.hiB {
                        cellCluster[iL * N * N + ia * N + ib] = UInt16(k)
                    }
                }
            }
        }
        var assignments = [UInt16](repeating: 0, count: pixelCount)
        var sse: Double = 0
        for p in 0..<pixelCount {
            let k = Int(cellCluster[cellOfPixel[p]])
            assignments[p] = UInt16(k)
            let c = clusters[k].mean
            let d = tile.pixels[p] - c
            sse += Double(simd_dot(d, d))
        }
        let mse = Float(sse / Double(pixelCount))

        let extractMs = Self.millis(ContinuousClock().now - started)
        return ClusterStatistics(
            clusters: clusters,
            assignments: assignments,
            provenance: ClusterStatistics.Provenance(
                family: .recursiveBipartitionWu,
                parameters: .wu(histogramBinsPerAxis: N),
                extractMillis: extractMs,
                mse: mse
            )
        )
    }

    // MARK: - Box + moments

    /// Half-open box [loL, hiL) × [loA, hiA) × [loB, hiB) in
    /// 32³-quantized OKLab space. `wcss` is cached so the
    /// highest-variance-box selection is a single scan.
    private struct Box {
        var loL, hiL, loA, hiA, loB, hiB: Int
        var wcss: Double = 0
        var canSplit: Bool { (hiL - loL) > 1 || (hiA - loA) > 1 || (hiB - loB) > 1 }
    }

    private struct Moments {
        let count: Double
        let sumL, sumA, sumB: Double
        let sumLL, sumAA, sumBB: Double
        let sumLA, sumLB, sumAB: Double
    }

    /// 8-corner inclusion-exclusion lookup. Returns the sum of any
    /// of the 10 moments over the axis-aligned half-open box
    /// [loL, hiL) × [loA, hiA) × [loB, hiB) — O(1) regardless of
    /// box volume.
    @inline(__always)
    private static func volume(
        _ table: [Double],
        loL: Int, hiL: Int, loA: Int, hiA: Int, loB: Int, hiB: Int, N: Int
    ) -> Double {
        // Cumulative tables use 1-indexed semantics implicitly:
        // table[i*N*N+j*N+k] = sum over [0..i] × [0..j] × [0..k]
        // (CLOSED ranges, INCLUSIVE upper bound). For a half-open
        // box [lo, hi), we use indices (lo-1) and (hi-1); a -1
        // index means "before any cell," so the contribution is 0.
        @inline(__always) func at(_ iL: Int, _ ia: Int, _ ib: Int) -> Double {
            if iL < 0 || ia < 0 || ib < 0 { return 0 }
            return table[iL * N * N + ia * N + ib]
        }
        let aL = loL - 1, bL = hiL - 1
        let aA = loA - 1, bA = hiA - 1
        let aB = loB - 1, bB = hiB - 1
        return at(bL, bA, bB)
             - at(aL, bA, bB) - at(bL, aA, bB) - at(bL, bA, aB)
             + at(aL, aA, bB) + at(aL, bA, aB) + at(bL, aA, aB)
             - at(aL, aA, aB)
    }

    private static func moments(
        box: Box,
        hist: [Double], sumL: [Double], sumA: [Double], sumB: [Double],
        sumLL: [Double], sumAA: [Double], sumBB: [Double],
        sumLA: [Double], sumLB: [Double], sumAB: [Double]
    ) -> Moments {
        let N = binsPerAxis
        return Moments(
            count: volume(hist,  loL: box.loL, hiL: box.hiL, loA: box.loA, hiA: box.hiA, loB: box.loB, hiB: box.hiB, N: N),
            sumL:  volume(sumL,  loL: box.loL, hiL: box.hiL, loA: box.loA, hiA: box.hiA, loB: box.loB, hiB: box.hiB, N: N),
            sumA:  volume(sumA,  loL: box.loL, hiL: box.hiL, loA: box.loA, hiA: box.hiA, loB: box.loB, hiB: box.hiB, N: N),
            sumB:  volume(sumB,  loL: box.loL, hiL: box.hiL, loA: box.loA, hiA: box.hiA, loB: box.loB, hiB: box.hiB, N: N),
            sumLL: volume(sumLL, loL: box.loL, hiL: box.hiL, loA: box.loA, hiA: box.hiA, loB: box.loB, hiB: box.hiB, N: N),
            sumAA: volume(sumAA, loL: box.loL, hiL: box.hiL, loA: box.loA, hiA: box.hiA, loB: box.loB, hiB: box.hiB, N: N),
            sumBB: volume(sumBB, loL: box.loL, hiL: box.hiL, loA: box.loA, hiA: box.hiA, loB: box.loB, hiB: box.hiB, N: N),
            sumLA: volume(sumLA, loL: box.loL, hiL: box.hiL, loA: box.loA, hiA: box.hiA, loB: box.loB, hiB: box.hiB, N: N),
            sumLB: volume(sumLB, loL: box.loL, hiL: box.hiL, loA: box.loA, hiA: box.hiA, loB: box.loB, hiB: box.hiB, N: N),
            sumAB: volume(sumAB, loL: box.loL, hiL: box.hiL, loA: box.loA, hiA: box.hiA, loB: box.loB, hiB: box.hiB, N: N)
        )
    }

    /// Within-cluster sum of squared error (WCSS) — the quantity
    /// Wu's bipartition reduces. For a box with mean μ and N pixels:
    ///   WCSS = Σ_p ‖p − μ‖² = ΣsumXX − ΣsumX² / N  (per channel, summed)
    /// Empty boxes return 0 (no error contribution; nothing to split).
    private static func wcss(
        box: Box,
        hist: [Double], sumL: [Double], sumA: [Double], sumB: [Double],
        sumLL: [Double], sumAA: [Double], sumBB: [Double]
    ) -> Double {
        let N = binsPerAxis
        let n  = volume(hist,  loL: box.loL, hiL: box.hiL, loA: box.loA, hiA: box.hiA, loB: box.loB, hiB: box.hiB, N: N)
        if n == 0 { return 0 }
        let sL = volume(sumL,  loL: box.loL, hiL: box.hiL, loA: box.loA, hiA: box.hiA, loB: box.loB, hiB: box.hiB, N: N)
        let sA = volume(sumA,  loL: box.loL, hiL: box.hiL, loA: box.loA, hiA: box.hiA, loB: box.loB, hiB: box.hiB, N: N)
        let sB = volume(sumB,  loL: box.loL, hiL: box.hiL, loA: box.loA, hiA: box.hiA, loB: box.loB, hiB: box.hiB, N: N)
        let sLL = volume(sumLL, loL: box.loL, hiL: box.hiL, loA: box.loA, hiA: box.hiA, loB: box.loB, hiB: box.hiB, N: N)
        let sAA = volume(sumAA, loL: box.loL, hiL: box.hiL, loA: box.loA, hiA: box.hiA, loB: box.loB, hiB: box.hiB, N: N)
        let sBB = volume(sumBB, loL: box.loL, hiL: box.hiL, loA: box.loA, hiA: box.hiA, loB: box.loB, hiB: box.hiB, N: N)
        return (sLL + sAA + sBB) - (sL * sL + sA * sA + sB * sB) / n
    }

    private struct Split {
        let axis: Int
        let position: Int
        let left: Box
        let right: Box
    }

    /// For each axis, scan all valid split positions; return the
    /// split that maximizes (parent_wcss − left_wcss − right_wcss).
    /// Returns nil only if no axis is splittable (single-cell box).
    private static func bestSplit(
        box: Box,
        hist: [Double], sumL: [Double], sumA: [Double], sumB: [Double],
        sumLL: [Double], sumAA: [Double], sumBB: [Double]
    ) -> Split? {
        var best: (gain: Double, split: Split)? = nil
        // Axis 0 = L, axis 1 = a, axis 2 = b.
        for axis in 0..<3 {
            let lo: Int, hi: Int
            switch axis {
            case 0: lo = box.loL; hi = box.hiL
            case 1: lo = box.loA; hi = box.hiA
            default: lo = box.loB; hi = box.hiB
            }
            if hi - lo < 2 { continue }
            for pos in (lo + 1)..<hi {
                var left = box, right = box
                switch axis {
                case 0: left.hiL = pos; right.loL = pos
                case 1: left.hiA = pos; right.loA = pos
                default: left.hiB = pos; right.loB = pos
                }
                let lW = wcss(box: left,  hist: hist, sumL: sumL, sumA: sumA, sumB: sumB,
                              sumLL: sumLL, sumAA: sumAA, sumBB: sumBB)
                let rW = wcss(box: right, hist: hist, sumL: sumL, sumA: sumA, sumB: sumB,
                              sumLL: sumLL, sumAA: sumAA, sumBB: sumBB)
                let gain = box.wcss - lW - rW
                if best == nil || gain > best!.gain {
                    var ls = left, rs = right
                    ls.wcss = lW
                    rs.wcss = rW
                    best = (gain, Split(axis: axis, position: pos, left: ls, right: rs))
                }
            }
        }
        return best?.split
    }

    // MARK: - Quantization + 3D cumulative sums

    /// Quantize L ∈ [0, 1] to bin index ∈ [0, N).
    @inline(__always)
    private static func quantizeL(_ v: Float) -> Int {
        let N = binsPerAxis
        return min(max(0, Int(v * Float(N))), N - 1)
    }

    /// Quantize a/b ∈ [-0.5, 0.5] (with some slack) to bin index
    /// ∈ [0, N). Values outside the nominal range are clamped.
    @inline(__always)
    private static func quantizeAB(_ v: Float) -> Int {
        let N = binsPerAxis
        return min(max(0, Int((v + 0.5) * Float(N))), N - 1)
    }

    /// In-place 3D cumulative sum (three orthogonal sweeps). After
    /// this call, `table[iL*N*N + ia*N + ib]` holds the sum over
    /// [0..iL] × [0..ia] × [0..ib] (closed, inclusive).
    private static func cumulate3D(_ table: inout [Double], N: Int) {
        // Sweep along L for fixed (a, b).
        for ia in 0..<N {
            for ib in 0..<N {
                var acc: Double = 0
                for iL in 0..<N {
                    acc += table[iL * N * N + ia * N + ib]
                    table[iL * N * N + ia * N + ib] = acc
                }
            }
        }
        // Sweep along a for fixed (L, b).
        for iL in 0..<N {
            for ib in 0..<N {
                var acc: Double = 0
                for ia in 0..<N {
                    acc += table[iL * N * N + ia * N + ib]
                    table[iL * N * N + ia * N + ib] = acc
                }
            }
        }
        // Sweep along b for fixed (L, a).
        for iL in 0..<N {
            for ia in 0..<N {
                var acc: Double = 0
                for ib in 0..<N {
                    acc += table[iL * N * N + ia * N + ib]
                    table[iL * N * N + ia * N + ib] = acc
                }
            }
        }
    }

    private static func millis(_ d: Duration) -> Int {
        let (s, attos) = d.components
        return Int(s) * 1_000 + Int(attos / 1_000_000_000_000_000)
    }
}
