import Foundation
import simd

/// Shared Wu quantization core — everything *after* the 10-moment histogram is
/// built. Both `WuReference` (CPU histogram) and `WuPalettePipeline` (GPU
/// histogram) feed identical `Histogram` tables + `cellOfPixel` into
/// `quantize`, so the cumulative-sum + greedy-bipartition + covariance steps
/// are byte-identical on both paths. Parity therefore reduces to "does the GPU
/// histogram match the CPU histogram" (it does, to fixed-point tolerance —
/// `cellOfPixel` is integer-exact since both quantize the same Float32 pixels).
///
/// Lifted verbatim from the former `WuExtractor` (Wu 1992, adapted to OKLab).
enum WuQuantizer {
    /// Bins per OKLab axis. 32³ ≈ 33K cells; 10 moment tables × 32³ × 8 bytes
    /// ≈ 2.6 MB transient per tile (CPU, Double).
    static let binsPerAxis: Int = 32

    /// Quantize L ∈ [0, 1] to bin index ∈ [0, N). MUST match `wuQuantizeL` in
    /// WuShaders.metal exactly so `cellOfPixel` is identical on CPU and GPU.
    @inline(__always)
    static func quantizeL(_ v: Float) -> Int {
        let N = binsPerAxis
        return min(max(0, Int(v * Float(N))), N - 1)
    }

    /// Quantize a/b ∈ [-0.5, 0.5] (with slack) to bin index ∈ [0, N).
    @inline(__always)
    static func quantizeAB(_ v: Float) -> Int {
        let N = binsPerAxis
        return min(max(0, Int((v + 0.5) * Float(N))), N - 1)
    }

    /// The 10 raw (non-cumulated) per-cell moment tables plus the per-pixel
    /// cell index. Tables are flat `[iL*N*N + ia*N + ib]`.
    struct Histogram {
        var hist:  [Double]
        var sumL:  [Double]
        var sumA:  [Double]
        var sumB:  [Double]
        var sumLL: [Double]
        var sumAA: [Double]
        var sumBB: [Double]
        var sumLA: [Double]
        var sumLB: [Double]
        var sumAB: [Double]
        var cellOfPixel: [Int]
    }

    /// One quantization result. The caller wraps this in `ClusterStatistics`
    /// with its own provenance (the GPU vs CPU paths differ only in timing).
    struct Result {
        let clusters: [ClusterStatistics.Cluster]
        let assignments: [UInt16]
        let mse: Float
    }

    /// Build the raw histogram on CPU. Used by `WuReference` and as the parity
    /// oracle for the GPU `wuHistogramKernel`.
    static func buildHistogramCPU(pixels: [SIMD3<Float>]) -> Histogram {
        let N = binsPerAxis
        let cells = N * N * N
        var h = Histogram(
            hist: .init(repeating: 0, count: cells),
            sumL: .init(repeating: 0, count: cells),
            sumA: .init(repeating: 0, count: cells),
            sumB: .init(repeating: 0, count: cells),
            sumLL: .init(repeating: 0, count: cells),
            sumAA: .init(repeating: 0, count: cells),
            sumBB: .init(repeating: 0, count: cells),
            sumLA: .init(repeating: 0, count: cells),
            sumLB: .init(repeating: 0, count: cells),
            sumAB: .init(repeating: 0, count: cells),
            cellOfPixel: .init(repeating: 0, count: pixels.count)
        )
        for p in 0..<pixels.count {
            let lab = pixels[p]
            let iL = quantizeL(lab.x)
            let ia = quantizeAB(lab.y)
            let ib = quantizeAB(lab.z)
            let cell = iL * N * N + ia * N + ib
            h.cellOfPixel[p] = cell
            let L = Double(lab.x), A = Double(lab.y), B = Double(lab.z)
            h.hist[cell]  += 1
            h.sumL[cell]  += L
            h.sumA[cell]  += A
            h.sumB[cell]  += B
            h.sumLL[cell] += L * L
            h.sumAA[cell] += A * A
            h.sumBB[cell] += B * B
            h.sumLA[cell] += L * A
            h.sumLB[cell] += L * B
            h.sumAB[cell] += A * B
        }
        return h
    }

    /// Cumulate → greedy bipartition → clusters → assignments → MSE. The tables
    /// in `h` are RAW (per-cell); this copies and cumulates them internally.
    static func quantize(_ h: Histogram, pixels: [SIMD3<Float>], K: Int) -> Result {
        let N = binsPerAxis
        var hist = h.hist, sumL = h.sumL, sumA = h.sumA, sumB = h.sumB
        var sumLL = h.sumLL, sumAA = h.sumAA, sumBB = h.sumBB
        var sumLA = h.sumLA, sumLB = h.sumLB, sumAB = h.sumAB

        cumulate3D(&hist,  N: N); cumulate3D(&sumL,  N: N); cumulate3D(&sumA,  N: N)
        cumulate3D(&sumB,  N: N); cumulate3D(&sumLL, N: N); cumulate3D(&sumAA, N: N)
        cumulate3D(&sumBB, N: N); cumulate3D(&sumLA, N: N); cumulate3D(&sumLB, N: N)
        cumulate3D(&sumAB, N: N)

        var boxes: [Box] = [Box(loL: 0, hiL: N, loA: 0, hiA: N, loB: 0, hiB: N)]
        boxes[0].wcss = wcss(box: boxes[0], hist: hist, sumL: sumL, sumA: sumA, sumB: sumB,
                             sumLL: sumLL, sumAA: sumAA, sumBB: sumBB)

        while boxes.count < K {
            var bestI = 0
            var bestWCSS = boxes[0].wcss
            for i in 1..<boxes.count where boxes[i].wcss > bestWCSS {
                bestWCSS = boxes[i].wcss
                bestI = i
            }
            let parent = boxes[bestI]
            guard parent.canSplit else { break }
            guard let split = bestSplit(box: parent, hist: hist, sumL: sumL, sumA: sumA, sumB: sumB,
                                        sumLL: sumLL, sumAA: sumAA, sumBB: sumBB) else { break }
            boxes.remove(at: bestI)
            boxes.append(split.left)
            boxes.append(split.right)
        }

        var clusters: [ClusterStatistics.Cluster] = []
        clusters.reserveCapacity(K)
        for box in boxes {
            let m = moments(box: box, hist: hist, sumL: sumL, sumA: sumA, sumB: sumB,
                            sumLL: sumLL, sumAA: sumAA, sumBB: sumBB,
                            sumLA: sumLA, sumLB: sumLB, sumAB: sumAB)
            if m.count == 0 {
                clusters.append(ClusterStatistics.Cluster(
                    mean: .zero, covariance: ClusterStatistics.Cluster.emptyCovariance, count: 0))
            } else {
                let inv = 1.0 / m.count
                let mL = m.sumL * inv, mA = m.sumA * inv, mB = m.sumB * inv
                let LL = max(0, m.sumLL * inv - mL * mL)
                let aa = max(0, m.sumAA * inv - mA * mA)
                let bb = max(0, m.sumBB * inv - mB * mB)
                let La = m.sumLA * inv - mL * mA
                let Lb = m.sumLB * inv - mL * mB
                let ab = m.sumAB * inv - mA * mB
                let sigma = simd_float3x3(columns: (
                    SIMD3<Float>(Float(LL), Float(La), Float(Lb)),
                    SIMD3<Float>(Float(La), Float(aa), Float(ab)),
                    SIMD3<Float>(Float(Lb), Float(ab), Float(bb))
                ))
                clusters.append(ClusterStatistics.Cluster(
                    mean: SIMD3<Float>(Float(mL), Float(mA), Float(mB)),
                    covariance: sigma, count: UInt32(m.count)))
            }
        }
        while clusters.count < K {
            clusters.append(ClusterStatistics.Cluster(
                mean: .zero, covariance: ClusterStatistics.Cluster.emptyCovariance, count: 0))
        }

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
        var assignments = [UInt16](repeating: 0, count: pixels.count)
        var sse: Double = 0
        for p in 0..<pixels.count {
            let k = Int(cellCluster[h.cellOfPixel[p]])
            assignments[p] = UInt16(k)
            let d = pixels[p] - clusters[k].mean
            sse += Double(simd_dot(d, d))
        }
        let mse = Float(sse / Double(pixels.count))
        return Result(clusters: clusters, assignments: assignments, mse: mse)
    }

    // MARK: - Box + moments (private; unchanged from the original WuExtractor)

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

    @inline(__always)
    private static func volume(
        _ table: [Double],
        loL: Int, hiL: Int, loA: Int, hiA: Int, loB: Int, hiB: Int, N: Int
    ) -> Double {
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
        func v(_ t: [Double]) -> Double {
            volume(t, loL: box.loL, hiL: box.hiL, loA: box.loA, hiA: box.hiA, loB: box.loB, hiB: box.hiB, N: N)
        }
        return Moments(count: v(hist), sumL: v(sumL), sumA: v(sumA), sumB: v(sumB),
                       sumLL: v(sumLL), sumAA: v(sumAA), sumBB: v(sumBB),
                       sumLA: v(sumLA), sumLB: v(sumLB), sumAB: v(sumAB))
    }

    private static func wcss(
        box: Box,
        hist: [Double], sumL: [Double], sumA: [Double], sumB: [Double],
        sumLL: [Double], sumAA: [Double], sumBB: [Double]
    ) -> Double {
        let N = binsPerAxis
        func v(_ t: [Double]) -> Double {
            volume(t, loL: box.loL, hiL: box.hiL, loA: box.loA, hiA: box.hiA, loB: box.loB, hiB: box.hiB, N: N)
        }
        let n = v(hist)
        if n == 0 { return 0 }
        let sL = v(sumL), sA = v(sumA), sB = v(sumB)
        let sLL = v(sumLL), sAA = v(sumAA), sBB = v(sumBB)
        return (sLL + sAA + sBB) - (sL * sL + sA * sA + sB * sB) / n
    }

    private struct Split {
        let axis: Int
        let position: Int
        let left: Box
        let right: Box
    }

    private static func bestSplit(
        box: Box,
        hist: [Double], sumL: [Double], sumA: [Double], sumB: [Double],
        sumLL: [Double], sumAA: [Double], sumBB: [Double]
    ) -> Split? {
        var best: (gain: Double, split: Split)? = nil
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
                let lW = wcss(box: left, hist: hist, sumL: sumL, sumA: sumA, sumB: sumB,
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

    private static func cumulate3D(_ table: inout [Double], N: Int) {
        for ia in 0..<N {
            for ib in 0..<N {
                var acc: Double = 0
                for iL in 0..<N {
                    acc += table[iL * N * N + ia * N + ib]
                    table[iL * N * N + ia * N + ib] = acc
                }
            }
        }
        for iL in 0..<N {
            for ib in 0..<N {
                var acc: Double = 0
                for ia in 0..<N {
                    acc += table[iL * N * N + ia * N + ib]
                    table[iL * N * N + ia * N + ib] = acc
                }
            }
        }
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
}
