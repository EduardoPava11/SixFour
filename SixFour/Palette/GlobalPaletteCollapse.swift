import Foundation
import simd

/// Per-frame → global palette collapse — the `PaletteCollapse` slot the look-NN will
/// eventually fill (see `docs/global-palette-skeleton-design.md`).
///
/// This is the **provisional deterministic conformer**: the coverage/diversity MAXIMIN
/// floor (farthest-point set over the pooled per-frame palettes) — NOT the Wasserstein
/// barycenter (that's the *trained* NN's target). It is a real, meaningful global palette
/// (the gamut-coverage floor), not a stub.
///
/// ⚠️ PROVISIONAL: this float pool/argmax is for interactive play. The shipped path is the
/// Q16 integer reference gated against `collapse_golden.json` (`Spec.Collapse`, not yet
/// wired). Index ties here keep the lowest index (matching the spec's `V.maxIndex` rule).
enum GlobalPaletteCollapse {
    /// Pool all 64×256 per-frame colours and greedily pick `k` maximally-spread ones.
    /// Returns the global palette as OKLab (the editable form) — `srgb` via `okLabToSRGB8`.
    static func maximin(perFramePalettes: [[SIMD3<UInt8>]], k: Int = 256) -> [OKLab] {
        var pool: [OKLab] = []
        pool.reserveCapacity(perFramePalettes.reduce(0) { $0 + $1.count })
        for frame in perFramePalettes {
            for c in frame { pool.append(ColorScience.srgb8ToOKLab(c.x, c.y, c.z)) }
        }
        let n = pool.count
        guard n > 0 else { return [] }

        @inline(__always) func d2(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
            let d = a - b; return d.x * d.x + d.y * d.y + d.z * d.z
        }

        // First seed = farthest from the pooled mean (ties: lowest index).
        var mean = SIMD3<Float>(repeating: 0)
        for p in pool { mean += p.simd }
        mean /= Float(n)

        var chosen: [Int] = []
        chosen.reserveCapacity(min(k, n))
        var best = 0
        var bestD: Float = -1
        for i in 0 ..< n { let dd = d2(pool[i].simd, mean); if dd > bestD { bestD = dd; best = i } }
        chosen.append(best)

        var minD = [Float](repeating: .greatestFiniteMagnitude, count: n)
        let firstC = pool[best].simd
        for i in 0 ..< n { minD[i] = d2(pool[i].simd, firstC) }

        while chosen.count < min(k, n) {
            var pick = 0
            var pickD: Float = -1
            for i in 0 ..< n where minD[i] > pickD { pickD = minD[i]; pick = i }
            chosen.append(pick)
            let pc = pool[pick].simd
            for i in 0 ..< n { let dd = d2(pool[i].simd, pc); if dd < minD[i] { minD[i] = dd } }
        }

        var out = chosen.map { pool[$0] }
        while out.count < k, let last = out.last { out.append(last) }  // pad if pool < k
        return out
    }
}
