import Foundation
import simd

/// SIMD nearest-centroid search over an OKLab palette.
///
/// This is the always-on CPU hot loop: error-diffusion dither and the
/// optional learned-metric refine both ask "which of the K centroids is
/// closest to this pixel?" ~67M times per 64-frame capture. The naive form
/// (`for j in 0..<K { simd_dot(d,d) }`) uses 3 of 4 SIMD lanes per centroid
/// and runs a scalar, branch-dependent loop over all K — i.e. it is *not*
/// SIMD across centroids.
///
/// `CentroidSet` stores the palette **structure-of-arrays** (`L`, `a`, `b`
/// in three parallel `[Float]`, padded to a multiple of 8). The hot loop runs
/// through a `Probe` (`withProbe`) that captures the three base pointers
/// **once per frame** — the SIMD8 search must not re-enter `withUnsafeBytes`
/// per pixel. Each step tests **8 centroids** with `SIMD8<Float>` FMAs and a
/// vectorised running argmin: K = 256 becomes 32 vector iterations with no
/// per-element branch.
///
/// Euclidean-only by design: the dither always uses the Euclidean OKLab
/// metric, which is the always-on path worth vectorising. The learned PSD
/// (Mahalanobis) metric keeps the generic scalar path. `Probe.nearestScalar`
/// is the parity oracle — bit-faithful to the old inner loop.
struct CentroidSet {
    /// Logical palette size (K).
    let count: Int
    /// `count` rounded up to a multiple of 8 (the SIMD8 width).
    let paddedCount: Int
    private(set) var L: [Float]
    private(set) var a: [Float]
    private(set) var b: [Float]

    /// Distance sentinel for padding lanes: huge but finite (1e18² = 1e36 <
    /// Float.greatestFiniteMagnitude), so it stays finite and never beats a
    /// real centroid in the argmin.
    private static let padSentinel: Float = 1e18

    init(_ centroids: [SIMD3<Float>]) {
        let k = centroids.count
        count = k
        paddedCount = (k + 7) & ~7
        L = [Float](repeating: Self.padSentinel, count: paddedCount)
        a = [Float](repeating: 0, count: paddedCount)
        b = [Float](repeating: 0, count: paddedCount)
        for i in 0..<k {
            L[i] = centroids[i].x
            a[i] = centroids[i].y
            b[i] = centroids[i].z
        }
    }

    /// A lightweight view holding the three SoA base pointers. The caller
    /// acquires it once (e.g. per frame) and reuses it across all pixels, so
    /// the `withUnsafeBytes` setup is paid once, not per query.
    struct Probe {
        let l: UnsafeRawPointer
        let a: UnsafeRawPointer
        let b: UnsafeRawPointer
        let count: Int
        let paddedCount: Int

        /// Vectorised nearest centroid (Euclidean OKLab). Returns an index in
        /// `0..<count`. Ties resolve to the lowest index among equidistant
        /// lanes (matching the scalar oracle's strict-`<`, lowest-wins rule).
        @inline(__always)
        func nearest(_ p: SIMD3<Float>) -> Int {
            let px = SIMD8<Float>(repeating: p.x)
            let py = SIMD8<Float>(repeating: p.y)
            let pz = SIMD8<Float>(repeating: p.z)
            var bestDist = SIMD8<Float>(repeating: .greatestFiniteMagnitude)
            var bestIdx = SIMD8<Int32>(repeating: 0)
            let laneSeed = SIMD8<Int32>(0, 1, 2, 3, 4, 5, 6, 7)

            var g = 0
            while g < paddedCount {
                let byte = g * MemoryLayout<Float>.stride
                let cl = l.loadUnaligned(fromByteOffset: byte, as: SIMD8<Float>.self)
                let ca = a.loadUnaligned(fromByteOffset: byte, as: SIMD8<Float>.self)
                let cb = b.loadUnaligned(fromByteOffset: byte, as: SIMD8<Float>.self)
                let dl = cl - px
                let da = ca - py
                let db = cb - pz
                let dist = dl * dl + da * da + db * db
                let mask = dist .< bestDist
                bestIdx.replace(with: laneSeed &+ Int32(g), where: mask)
                bestDist.replace(with: dist, where: mask)
                g += 8
            }

            let m = bestDist.min()
            var winner = Int32.max
            for lane in 0..<8 where bestDist[lane] == m {
                winner = Swift.min(winner, bestIdx[lane])
            }
            return Int(winner)
        }

        /// The two nearest centroids (Euclidean OKLab): `(i0, i1)` where `i0`
        /// is nearest and `i1` is second-nearest. Used by the parallel
        /// blue-noise dither, which picks between them per pixel. If `count < 2`,
        /// `i1 == i0`. Per-lane top-2 is tracked vectorised; the final 16-way
        /// horizontal reduction (8 bests + 8 seconds) is a cheap scalar scan.
        @inline(__always)
        func nearest2(_ p: SIMD3<Float>) -> (i0: Int, i1: Int) {
            let px = SIMD8<Float>(repeating: p.x)
            let py = SIMD8<Float>(repeating: p.y)
            let pz = SIMD8<Float>(repeating: p.z)
            let huge = SIMD8<Float>(repeating: .greatestFiniteMagnitude)
            var best = huge
            var bestI = SIMD8<Int32>(repeating: 0)
            var second = huge
            var secondI = SIMD8<Int32>(repeating: 0)
            let laneSeed = SIMD8<Int32>(0, 1, 2, 3, 4, 5, 6, 7)

            var g = 0
            while g < paddedCount {
                let byte = g * MemoryLayout<Float>.stride
                let cl = l.loadUnaligned(fromByteOffset: byte, as: SIMD8<Float>.self)
                let ca = a.loadUnaligned(fromByteOffset: byte, as: SIMD8<Float>.self)
                let cb = b.loadUnaligned(fromByteOffset: byte, as: SIMD8<Float>.self)
                let dl = cl - px, da = ca - py, db = cb - pz
                let dist = dl * dl + da * da + db * db
                let idx = laneSeed &+ Int32(g)
                // dist < best → demote best to second, then install new best.
                let m1 = dist .< best
                second.replace(with: best, where: m1)
                secondI.replace(with: bestI, where: m1)
                best.replace(with: dist, where: m1)
                bestI.replace(with: idx, where: m1)
                // best ≤ dist < second → install new second.
                let m2 = (dist .< second) .& (.!m1)
                second.replace(with: dist, where: m2)
                secondI.replace(with: idx, where: m2)
                g += 8
            }

            // 16 per-lane candidates → global nearest + second-nearest.
            var d0: Float = .greatestFiniteMagnitude, i0: Int32 = 0
            var d1: Float = .greatestFiniteMagnitude, i1: Int32 = 0
            @inline(__always) func offer(_ d: Float, _ i: Int32) {
                if d < d0 { d1 = d0; i1 = i0; d0 = d; i0 = i }
                else if d < d1 && i != i0 { d1 = d; i1 = i }
            }
            for lane in 0..<8 { offer(best[lane], bestI[lane]) }
            for lane in 0..<8 { offer(second[lane], secondI[lane]) }
            if count < 2 { i1 = i0 }
            return (Int(i0), Int(i1))
        }

        /// The OKLab colour of centroid `i` (reassembled from the SoA arrays).
        @inline(__always)
        func color(_ i: Int) -> SIMD3<Float> {
            let byte = i * MemoryLayout<Float>.stride
            return SIMD3<Float>(
                l.loadUnaligned(fromByteOffset: byte, as: Float.self),
                a.loadUnaligned(fromByteOffset: byte, as: Float.self),
                b.loadUnaligned(fromByteOffset: byte, as: Float.self)
            )
        }

        /// Scalar parity oracle — bit-faithful to the historical inner loop
        /// (`for j { simd_dot }`, strict `<`, lowest index wins ties).
        @inline(__always)
        func nearestScalar(_ p: SIMD3<Float>) -> Int {
            var bestK = 0
            var bestD: Float = .infinity
            for j in 0..<count {
                let d = color(j) - p
                let dd = simd_dot(d, d)
                if dd < bestD { bestD = dd; bestK = j }
            }
            return bestK
        }
    }

    /// Acquire a `Probe` over the SoA storage for the duration of `body`.
    @inline(__always)
    func withProbe<R>(_ body: (Probe) -> R) -> R {
        L.withUnsafeBytes { lRaw in
            a.withUnsafeBytes { aRaw in
                b.withUnsafeBytes { bRaw in
                    body(Probe(
                        l: lRaw.baseAddress!,
                        a: aRaw.baseAddress!,
                        b: bRaw.baseAddress!,
                        count: count,
                        paddedCount: paddedCount
                    ))
                }
            }
        }
    }

    /// Convenience single-shot query (used by tests). Production callers
    /// should hoist a `Probe` via `withProbe` and reuse it across pixels.
    @inline(__always)
    func nearest(_ p: SIMD3<Float>) -> Int { withProbe { $0.nearest(p) } }

    @inline(__always)
    func nearestScalar(_ p: SIMD3<Float>) -> Int { withProbe { $0.nearestScalar(p) } }

    @inline(__always)
    func color(_ i: Int) -> SIMD3<Float> { withProbe { $0.color(i) } }
}
