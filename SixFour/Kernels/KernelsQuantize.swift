//  KernelsQuantize.swift
//  Swift port of the GIF/quantize section of Native/src/kernels.zig (2026-07-06);
//  byte-exact twin; the encoder is additionally gated by DeterministicRenderer
//  SHA-256 reproducibility.
//
//  This file carries the quantize/dither/collapse half of the slice:
//    s4_quantize_frame, s4_global_collapse, s4_leaf_override, s4_dither_frame,
//    s4_significance_fill
//  (the GIF89a codec half — encode/assemble/decode + size helpers — lives in
//  KernelsGif.swift). Shared surface (s4log, S4_* constants, s4DivFloor) comes
//  from KernelsCore.swift. Translation dictionary: see KernelsCore.swift header.
//
//  OKLab is carried in Q16 (scale 2^16); distances accumulate in Int64;
//  nearest-centroid argmin ties resolve to the LOWEST index (strict <, loops in
//  index order — do NOT reorder).

// ── return codes (private copies of kernels.zig RC_*, per the port convention) ─
private let rcOK: Int32 = 0
private let rcNullPtr: Int32 = 1
private let rcBadShape: Int32 = 2
private let rcScratchTooSmall: Int32 = 3
private let rcOutputTooSmall: Int32 = 4
private let rcInfeasibleSignificance: Int32 = 5
private let rcBadDitherMode: Int32 = 6
private let rcOutOfRange: Int32 = 7
private let rcNotImplemented: Int32 = 100

// ── reversible-substrate domain bound (private twin of kernels.zig) ──────────
// NOTE (ported private helper): kernels.zig `SUBSTRATE_BOUND` (pub const) —
// B = 2^29 − 1, the largest symmetric input bound that keeps the entire lift
// composition representable in i32. Only `s4_leaf_override` needs it in this
// file (the producer-side totality guard for the whole lift).
private let s4SubstrateBound: Int64 = (1 << 29) - 1

// NOTE (ported private helper): kernels.zig `inBound`.
@inline(__always)
private func inBound(_ v: Int64, _ bound: Int64) -> Bool {
    v >= -bound && v <= bound
}

// ── error-diffusion taps (private twins of kernels.zig FS_TAPS/ATKINSON_TAPS) ─
// (dx, dy, num, den). FS = 7/3/5/1 ÷ 16; Atkinson = 6 × 1/8. Carried as Int64
// so the tap arithmetic below is verbatim i64, exactly as the Zig `[4]i32`
// entries coerce to i64 at every use site.
private let fsTaps: [(dx: Int64, dy: Int64, num: Int64, den: Int64)] = [
    (1, 0, 7, 16), (-1, 1, 3, 16), (0, 1, 5, 16), (1, 1, 1, 16),
]
private let atkinsonTaps: [(dx: Int64, dy: Int64, num: Int64, den: Int64)] = [
    (1, 0, 1, 8), (2, 0, 1, 8), (-1, 1, 1, 8), (0, 1, 1, 8), (1, 1, 1, 8), (0, 2, 1, 8),
]

// NOTE (ported private helper): kernels.zig `distSqCentroid`.
// Squared Q16 distance, point→centroid j. SCALAR Int64 (deliberately not SIMD —
// see the Zig NEON note: the real SIMD win is SoA across centroids, deferred).
@inline(__always)
private func distSqCentroid(_ c: UnsafePointer<Int32>, _ j: Int, _ l: Int64, _ a: Int64, _ b: Int64) -> Int64 {
    let dl = l - Int64(c[j * 3 + 0])
    let da = a - Int64(c[j * 3 + 1])
    let db = b - Int64(c[j * 3 + 2])
    return dl * dl + da * da + db * db
}

// NOTE (ported private helper): kernels.zig `nearestCentroidQ16`.
// Nearest centroid index; strict < ⇒ lowest index on ties.
private func nearestCentroidQ16(_ c: UnsafePointer<Int32>, _ k: Int, _ l: Int64, _ a: Int64, _ b: Int64) -> Int {
    var best = 0
    var bd = distSqCentroid(c, 0, l, a, b)
    var j = 1
    while j < k {
        let d = distSqCentroid(c, j, l, a, b)
        if d < bd {
            bd = d
            best = j
        }
        j += 1
    }
    return best
}

// NOTE (ported private helper): kernels.zig `nearest2CentroidQ16`.
// Two nearest centroid indices {near0 closest, near1 second}; near1 == near0
// only when k == 1. Single fused k-scan; byte-identical tie-breaking: near0
// keeps the strict-< global min (lowest index on ties); when a new global min
// appears the old best demotes to near1, so near1 is the strict-< min over
// j≠near0 (lowest index on ties).
private func nearest2CentroidQ16(_ c: UnsafePointer<Int32>, _ k: Int, _ l: Int64, _ a: Int64, _ b: Int64) -> (Int, Int) {
    var near0 = 0
    var bd0 = distSqCentroid(c, 0, l, a, b)
    var near1 = 0
    var bd1 = Int64.max
    var j = 1
    while j < k {
        let d = distSqCentroid(c, j, l, a, b)
        if d < bd0 {
            bd1 = bd0
            near1 = near0
            bd0 = d
            near0 = j
        } else if d < bd1 {
            bd1 = d
            near1 = j
        }
        j += 1
    }
    if k == 1 { near1 = near0 }
    return (near0, near1)
}

// NOTE (ported private helper): kernels.zig `isqrt64`.
// Exact integer floor square root (binary search) — mirrors
// SixFour.Spec.SignificanceFixed.isqrtInt. hi = 2^20 keeps mid² ≤ 2^40 in Int64.
private func isqrt64(_ n: Int64) -> Int64 {
    if n <= 0 { return 0 }
    var lo: Int64 = 0
    var hi: Int64 = 1 << 20
    while lo < hi {
        let mid = (lo + hi + 1) / 2
        if mid * mid <= n {
            lo = mid
        } else {
            hi = mid - 1
        }
    }
    return lo
}

/// Per-frame quantise → k centroids + assignment. Maximin (farthest-first)
/// seeding (the diversity-optimal Gonzalez-1985 rule, the per-frame COVERAGE
/// objective), then `lloyd_iters` optional Lloyd refinements (truncating means,
/// empty cluster keeps its old centroid), then nearest-centroid assignment
/// (strict-<, lowest index). Mirrors SixFour.Spec.QuantFixed byte-for-byte.
/// k ≤ 256 (u8 indices). `scratch` ≥ p·8 + 3·k·8 + k·4 bytes.
/// lloyd_iters: caller chooses; 0 = pure maximin (the diversity/coverage objective).
/// The shipped deterministic capture path and s4_global_collapse pass 0; the
/// GPU/full-pipeline Swift path and gif fixtures use 15. Standardizing the device
/// count (15 GPU-parity vs 3 spec variance-cut) is an OPEN question (NOTES.md §4,
/// §6 Q4). Byte-exactness requires the same count across Zig/Swift/Metal for a
/// given path.
@_cdecl("s4_quantize_frame")
public func s4_quantize_frame(
    _ oklab_q16: UnsafePointer<Int32>?,
    _ p: Int32,
    _ k: Int32,
    _ lloyd_iters: Int32,
    _ out_centroids_q16: UnsafeMutablePointer<Int32>?,
    _ out_indices: UnsafeMutablePointer<UInt8>?,
    _ scratch: UnsafeMutableRawPointer?,
    _ scratch_cap: Int
) -> Int32 {
    guard let px = oklab_q16, let cen = out_centroids_q16, let idx = out_indices else { return rcNullPtr }
    // k > p would make maximin return duplicate seeds (a silent degenerate
    // palette); fail loud instead. Shipped shape (p=4096, k=256) is unaffected.
    if p <= 0 || k <= 0 || k > 256 || k > p { return rcBadShape }
    let pp = Int(p)
    let kk = Int(k)

    let need = pp * MemoryLayout<Int64>.stride + 3 * kk * MemoryLayout<Int64>.stride + kk * MemoryLayout<Int32>.stride
    guard let scr = scratch, scratch_cap >= need else { return rcScratchTooSmall }
    let mind = scr.bindMemory(to: Int64.self, capacity: pp)
    let sums = (scr + pp * 8).bindMemory(to: Int64.self, capacity: 3 * kk)
    let counts = (scr + pp * 8 + 3 * kk * 8).bindMemory(to: Int32.self, capacity: kk)

    // ── maximin (farthest-first) seeding ──────────────────────────────────────
    var sl: Int64 = 0
    var sa: Int64 = 0
    var sb: Int64 = 0
    var i = 0
    while i < pp {
        sl += Int64(px[i * 3 + 0])
        sa += Int64(px[i * 3 + 1])
        sb += Int64(px[i * 3 + 2])
        i += 1
    }
    let ml = sl / Int64(p)
    let ma = sa / Int64(p)
    let mb = sb / Int64(p)

    // first seed = pixel farthest from the integer mean (strict >, lowest index)
    var first = 0
    var bd: Int64 = -1
    i = 0
    while i < pp {
        let d = distSqCentroid(px, i, ml, ma, mb)
        if d > bd {
            bd = d
            first = i
        }
        i += 1
    }
    cen[0] = px[first * 3 + 0]
    cen[1] = px[first * 3 + 1]
    cen[2] = px[first * 3 + 2]
    do {
        let fl = Int64(px[first * 3 + 0])
        let fa = Int64(px[first * 3 + 1])
        let fb = Int64(px[first * 3 + 2])
        i = 0
        while i < pp {
            mind[i] = distSqCentroid(px, i, fl, fa, fb)
            i += 1
        }
    }

    var chosen = 1
    while chosen < kk {
        var nextI = 0
        var bm: Int64 = -1
        i = 0
        while i < pp {
            if mind[i] > bm {
                bm = mind[i]
                nextI = i
            }
            i += 1
        }
        cen[chosen * 3 + 0] = px[nextI * 3 + 0]
        cen[chosen * 3 + 1] = px[nextI * 3 + 1]
        cen[chosen * 3 + 2] = px[nextI * 3 + 2]
        let nl = Int64(px[nextI * 3 + 0])
        let na = Int64(px[nextI * 3 + 1])
        let nb = Int64(px[nextI * 3 + 2])
        i = 0
        while i < pp {
            let d = distSqCentroid(px, i, nl, na, nb)
            if d < mind[i] { mind[i] = d }
            i += 1
        }
        chosen += 1
    }

    // ── Lloyd refinement (optional; 0 = pure maximin) ─────────────────────────
    var iter: Int32 = 0
    while iter < lloyd_iters {
        sums.update(repeating: 0, count: 3 * kk)
        counts.update(repeating: 0, count: kk)
        i = 0
        while i < pp {
            let j = nearestCentroidQ16(cen, kk, Int64(px[i * 3 + 0]), Int64(px[i * 3 + 1]), Int64(px[i * 3 + 2]))
            sums[j * 3 + 0] += Int64(px[i * 3 + 0])
            sums[j * 3 + 1] += Int64(px[i * 3 + 1])
            sums[j * 3 + 2] += Int64(px[i * 3 + 2])
            counts[j] += 1
            i += 1
        }
        var j = 0
        while j < kk {
            if counts[j] > 0 {
                let n = Int64(counts[j])
                cen[j * 3 + 0] = Int32(sums[j * 3 + 0] / n)
                cen[j * 3 + 1] = Int32(sums[j * 3 + 1] / n)
                cen[j * 3 + 2] = Int32(sums[j * 3 + 2] / n)
            } // else keep old centroid
            j += 1
        }
        iter += 1
    }

    // ── final nearest-centroid assignment ─────────────────────────────────────
    i = 0
    while i < pp {
        idx[i] = UInt8(nearestCentroidQ16(cen, kk, Int64(px[i * 3 + 0]), Int64(px[i * 3 + 1]), Int64(px[i * 3 + 2])))
        i += 1
    }
    s4log("quantize  p=\(p) k=\(k) lloyd=\(lloyd_iters) (maximin seed)")
    return rcOK
}

/// GIFA → GIFB: collapse the `t` per-frame Q16 OKLab palettes into ONE global
/// palette. The pooled candidate cloud is the contiguous `t·k_in` input
/// (per-frame palettes laid out back-to-back); maximin (farthest-first, the
/// `lloyd_iters = 0` path) selects `k_out` global leaves, then every pooled
/// colour is assigned to its nearest leaf — the per-frame GIF index map,
/// flattened to `t·k_in`. This is exactly the per-frame quantiser's maximin at
/// burst scale, so it SHARES `s4_quantize_frame`'s byte-exact path (no duplicated
/// argmin/tie-break). Mirrors `SixFour.Spec.Collapse.globalCollapseQ16` +
/// `reindexFrameQ16`. `k_out` ≤ 256 (u8 indices) and ≤ `t·k_in`.
/// `scratch` ≥ (t·k_in)·8 + 3·k_out·8 + k_out·4 bytes.
///
/// ⚠️ V2-DEFERRED-GLOBAL-PALETTE — global (GIFB) collapse, deferred to V2 behind the Swift gate
/// Feature.globalPaletteV2 (false in MVP1). Kept, compiled, and golden-gated for V2; not a live
/// MVP1 path (global-palette is V2-deferred). Do not add new callers.
@_cdecl("s4_global_collapse")
public func s4_global_collapse(
    _ palettes_q16: UnsafePointer<Int32>?,
    _ t: Int32,
    _ k_in: Int32,
    _ k_out: Int32,
    _ out_leaves_q16: UnsafeMutablePointer<Int32>?,
    _ out_indices: UnsafeMutablePointer<UInt8>?,
    _ scratch: UnsafeMutableRawPointer?,
    _ scratch_cap: Int
) -> Int32 {
    if palettes_q16 == nil || out_leaves_q16 == nil || out_indices == nil { return rcNullPtr }
    if t <= 0 || k_in <= 0 { return rcBadShape }
    // Pooled candidate count = t·k_in. Guard the i32 product (the Zig trap twin).
    let p64 = Int64(t) * Int64(k_in)
    if p64 > 2147483647 { return rcBadShape }
    let p = Int32(p64)
    // The pooled cloud is already contiguous, so the maximin seed phase of the
    // per-frame quantiser (lloyd_iters = 0) IS the collapse; its final assignment
    // is the per-frame re-index (flattened). One byte-exact code path, two scales.
    let rc = s4_quantize_frame(palettes_q16, p, k_out, 0, out_leaves_q16, out_indices, scratch, scratch_cap)
    if rc == rcOK { s4log("collapse  t=\(t) k_in=\(k_in) k_out=\(k_out) (pooled maximin)") }
    return rc
}

/// `n` generators (interleaved L,a,b Q16) + `n` deltas → `2n` σ-pair leaves
/// `[g₀, σ(g₀), g₁, σ(g₁), …]` where `gᵢ = generatorᵢ + δᵢ` and σ(l,a,b) =
/// (l, −a, −b). `out_leaves_q16` holds `2n` triples (`6n` ints). Pass
/// `deltas_q16 == nil` for the no-op (zero) override. Byte-exact vs
/// `Spec.LeafOverride`.
/// TOTAL: this is the USER / Core-AI taste channel, so it is the producer-side
/// guard for the whole lift. Each `gᵢ = generatorᵢ + δᵢ` (and its σ-negate) is
/// formed in Int64 and must satisfy |gᵢ| ≤ B; an out-of-domain δ returns
/// `rcOutOfRange` rather than manufacturing a leaf that overflows the lift.
@_cdecl("s4_leaf_override")
public func s4_leaf_override(
    _ generators_q16: UnsafePointer<Int32>?,
    _ deltas_q16: UnsafePointer<Int32>?,
    _ n: Int32,
    _ out_leaves_q16: UnsafeMutablePointer<Int32>?
) -> Int32 {
    guard let out = out_leaves_q16 else { return rcNullPtr }
    if n < 0 { return rcBadShape }
    if n > 0 && generators_q16 == nil { return rcNullPtr }
    var i = 0
    let cnt = Int(n)
    while i < cnt {
        let gens = generators_q16!
        let gi = i * 3
        let dl: Int32 = deltas_q16 == nil ? 0 : deltas_q16![gi + 0]
        let da: Int32 = deltas_q16 == nil ? 0 : deltas_q16![gi + 1]
        let db: Int32 = deltas_q16 == nil ? 0 : deltas_q16![gi + 2]
        // TOTALITY: this is the CHEAPEST place to refuse — the producer of the leaf
        // space the downstream Haar consumes. Each nudged generator sum gᵢ = generatorᵢ
        // + δᵢ (computed in Int64 so the add cannot wrap) must satisfy |gᵢ| ≤ B; then
        // the σ-negate −gᵢ is also representable and the downstream analyze detail
        // gᵢ−(−gᵢ) = 2gᵢ stays ≤ 2B. Out of domain ⇒ rcOutOfRange.
        let gl64 = Int64(gens[gi + 0]) + Int64(dl)
        let ga64 = Int64(gens[gi + 1]) + Int64(da)
        let gb64 = Int64(gens[gi + 2]) + Int64(db)
        if !inBound(gl64, s4SubstrateBound) || !inBound(ga64, s4SubstrateBound) ||
            !inBound(gb64, s4SubstrateBound) { return rcOutOfRange }
        let gl = Int32(gl64)
        let ga = Int32(ga64)
        let gb = Int32(gb64)
        let o = i * 6
        out[o + 0] = gl // even leaf = g
        out[o + 1] = ga
        out[o + 2] = gb
        out[o + 3] = gl // odd leaf = σ(g) = (l, −a, −b)
        out[o + 4] = -ga
        out[o + 5] = -gb
        i += 1
    }
    return rcOK
}

/// Per-frame dither against a fixed palette → indices. Mirrors Dither.swift /
/// SixFour.Spec.SpatialDither byte-for-byte.
/// dither_mode: 0=FloydSteinberg, 1=Atkinson, 2=blueNoise spatiotemporal, 3=frozen.
/// (modes 2 and 3 are identical at the kernel level — the caller chooses which
/// STBN3D slice to pass.) Error-diffusion modes need `scratch` ≥ 3·p·4 bytes.
/// stbn_slice MUST be one frame (p bytes) of the canonical STBN3D mask: the 8³
/// void-and-cluster scalar mask (stbn3d-8.bin, 512 bytes, toroidal Euclidean
/// distance) tiled 8×8→64³ by the Swift caller (STBN3DMaskLoader.loadTiled).
/// Pre-computed off-device, pinned by Spec/STBN3D.hs + Generated/STBN3DContract.swift;
/// canonical bytes emitted by spec/app/Spec.hs (writeBinary stbn3d-8.bin). Never
/// regenerate — Euclidean ≠ toroidal mask would break cross-device determinism
/// (NOTES.md §STBN3D).
@_cdecl("s4_dither_frame")
public func s4_dither_frame(
    _ oklab_q16: UnsafePointer<Int32>?,
    _ centroids_q16: UnsafePointer<Int32>?,
    _ p: Int32,
    _ k: Int32,
    _ dither_mode: Int32,
    _ serpentine: Int32,
    _ stbn_slice: UnsafePointer<UInt8>?,
    _ out_indices: UnsafeMutablePointer<UInt8>?,
    _ scratch: UnsafeMutableRawPointer?,
    _ scratch_cap: Int
) -> Int32 {
    guard let px = oklab_q16, let cen = centroids_q16, let idx = out_indices else { return rcNullPtr }
    if p <= 0 || k <= 0 || k > 256 { return rcBadShape }
    let pp = Int(p)
    let kk = Int(k)

    // ── ordered blue-noise (modes 2, 3): independent per pixel ────────────────
    if dither_mode >= 2 {
        guard let stbn = stbn_slice else { return rcBadDitherMode }
        var i = 0
        while i < pp {
            let pl = Int64(px[i * 3 + 0])
            let pa = Int64(px[i * 3 + 1])
            let pb = Int64(px[i * 3 + 2])
            let (n0, n1) = nearest2CentroidQ16(cen, kk, pl, pa, pb)
            if n0 == n1 {
                idx[i] = UInt8(n0)
                i += 1
                continue
            }
            let c0l = Int64(cen[n0 * 3 + 0])
            let c0a = Int64(cen[n0 * 3 + 1])
            let c0b = Int64(cen[n0 * 3 + 2])
            let axl = Int64(cen[n1 * 3 + 0]) - c0l
            let axa = Int64(cen[n1 * 3 + 1]) - c0a
            let axb = Int64(cen[n1 * 3 + 2]) - c0b
            let denom = axl * axl + axa * axa + axb * axb
            let num = (pl - c0l) * axl + (pa - c0a) * axa + (pb - c0b) * axb
            var sQ16: Int64 = 0
            if denom > 0 {
                sQ16 = num * 65536 / denom
                if sQ16 < 0 { sQ16 = 0 }
                if sQ16 > 65536 { sQ16 = 65536 }
            }
            let tQ16 = (2 * Int64(stbn[i]) + 1) * 128
            idx[i] = sQ16 > tQ16 ? UInt8(n1) : UInt8(n0)
            i += 1
        }
        s4log("dither    p=\(p) k=\(k) mode=\(dither_mode) (blue-noise)")
        return rcOK
    }

    // ── error diffusion (modes 0, 1): sequential, mutate a working copy ───────
    if dither_mode != 0 && dither_mode != 1 { return rcBadDitherMode }
    let sideI = isqrt64(Int64(p))
    if sideI * sideI != Int64(p) { return rcBadShape }
    let side = Int(sideI)

    let need = pp * 3 * MemoryLayout<Int32>.stride
    guard let scr = scratch, scratch_cap >= need else { return rcScratchTooSmall }
    let buf = scr.bindMemory(to: Int32.self, capacity: pp * 3)
    var ci = 0
    while ci < pp * 3 {
        buf[ci] = px[ci]
        ci += 1
    }

    let taps = dither_mode == 0 ? fsTaps : atkinsonTaps
    let serp = serpentine != 0
    let sideI64 = Int64(side)

    var y = 0
    while y < side {
        let l2r = !serp || (y % 2 == 0)
        var xi = 0
        while xi < side {
            let x = l2r ? xi : side - 1 - xi
            let pos = y * side + x
            let hl = Int64(buf[pos * 3 + 0])
            let ha = Int64(buf[pos * 3 + 1])
            let hb = Int64(buf[pos * 3 + 2])
            let bestK = nearestCentroidQ16(cen, kk, hl, ha, hb)
            idx[pos] = UInt8(bestK)
            let el = hl - Int64(cen[bestK * 3 + 0])
            let ea = ha - Int64(cen[bestK * 3 + 1])
            let eb = hb - Int64(cen[bestK * 3 + 2])
            for tap in taps {
                let dx: Int64 = l2r ? tap.dx : -tap.dx
                let nx = Int64(x) + dx
                let ny = Int64(y) + tap.dy
                if nx < 0 || nx >= sideI64 || ny < 0 || ny >= sideI64 { continue }
                let nidx = Int(ny * sideI64 + nx)
                let num = tap.num
                let den = tap.den
                buf[nidx * 3 + 0] += Int32(el * num / den)
                buf[nidx * 3 + 1] += Int32(ea * num / den)
                buf[nidx * 3 + 2] += Int32(eb * num / den)
            }
            xi += 1
        }
        y += 1
    }
    s4log("dither    p=\(p) k=\(k) mode=\(dither_mode) serp=\(serpentine) (error-diffusion)")
    return rcOK
}

/// Significance split-fill: rebalance indices so every slot has ≥ min_population
/// pixels; optionally emit per-slot cell stats (mean3, std3, count) into
/// out_cell_stats (k × 7 Int32) — pass nil to skip. Mirrors the app's
/// SignificantSplitFill.rescue (+ cells) and SixFour.Spec.SignificanceFixed
/// byte-for-byte: nearest-to-centroid donor, strict-< (lowest index) tie-break,
/// donor must have count > min_population. k ≤ 256 (stack-resident accumulators).
@_cdecl("s4_significance_fill")
public func s4_significance_fill(
    _ oklab_q16: UnsafePointer<Int32>?,
    _ centroids_q16: UnsafePointer<Int32>?,
    _ p: Int32,
    _ k: Int32,
    _ min_population: Int32,
    _ io_indices: UnsafeMutablePointer<UInt8>?,
    _ out_cell_stats: UnsafeMutablePointer<Int32>?,
    _ scratch: UnsafeMutableRawPointer?,
    _ scratch_cap: Int
) -> Int32 {
    _ = scratch
    _ = scratch_cap
    guard let px = oklab_q16, let cen = centroids_q16, let idx = io_indices else { return rcNullPtr }
    if p <= 0 || k <= 0 || k > 256 || min_population < 0 { return rcBadShape }
    let pp = Int(p)
    let kk = Int(k)
    let nmin = min_population
    if Int64(p) < Int64(nmin) * Int64(k) { return rcInfeasibleSignificance }

    // Zig keeps [256] arrays on the stack; withUnsafeTemporaryAllocation is the
    // Swift stack-allocation twin (no heap on the hot path).
    return withUnsafeTemporaryAllocation(of: Int32.self, capacity: kk) { countsBuf -> Int32 in
        let counts = countsBuf.baseAddress!
        counts.update(repeating: 0, count: kk)
        var i = 0
        while i < pp {
            counts[Int(idx[i])] += 1
            i += 1
        }

        var allOK = true
        do {
            var t = 0
            while t < kk {
                if counts[t] < nmin {
                    allOK = false
                    break
                }
                t += 1
            }
        }

        var moves: Int32 = 0
        if !allOK {
            var slot = 0
            while slot < kk {
                if counts[slot] >= nmin {
                    slot += 1
                    continue
                }
                let tl = Int64(cen[slot * 3 + 0])
                let ta = Int64(cen[slot * 3 + 1])
                let tb = Int64(cen[slot * 3 + 2])
                while counts[slot] < nmin {
                    var bestI: Int64 = -1
                    var bestD = Int64.max
                    var j = 0
                    while j < pp {
                        let s = Int(idx[j])
                        if s == slot || counts[s] <= nmin {
                            j += 1
                            continue
                        }
                        let d = distSqCentroid(px, j, tl, ta, tb)
                        if d < bestD {
                            bestD = d
                            bestI = Int64(j)
                        }
                        j += 1
                    }
                    if bestI < 0 { break } // infeasible (unreachable when p ≥ nmin·k)
                    let bi = Int(bestI)
                    counts[Int(idx[bi])] -= 1
                    idx[bi] = UInt8(slot)
                    counts[slot] += 1
                    moves += 1
                }
                slot += 1
            }
        }
        s4log("signif    p=\(p) k=\(k) minPop=\(min_population) rebalanced=\(moves) px")

        if let stats = out_cell_stats {
            withUnsafeTemporaryAllocation(of: Int64.self, capacity: 9 * kk) { accBuf in
                let acc = accBuf.baseAddress!
                let sumL = acc
                let sumA = acc + kk
                let sumB = acc + 2 * kk
                let meanL = acc + 3 * kk
                let meanA = acc + 4 * kk
                let meanB = acc + 5 * kk
                let varL = acc + 6 * kk
                let varA = acc + 7 * kk
                let varB = acc + 8 * kk
                sumL.update(repeating: 0, count: 3 * kk) // zeroes sumL, sumA, sumB
                var ci = 0
                while ci < pp {
                    let t = Int(idx[ci])
                    sumL[t] += Int64(px[ci * 3 + 0])
                    sumA[t] += Int64(px[ci * 3 + 1])
                    sumB[t] += Int64(px[ci * 3 + 2])
                    ci += 1
                }
                var t = 0
                while t < kk {
                    if counts[t] > 0 {
                        let n = Int64(counts[t])
                        meanL[t] = sumL[t] / n
                        meanA[t] = sumA[t] / n
                        meanB[t] = sumB[t] / n
                    } else {
                        meanL[t] = Int64(cen[t * 3 + 0])
                        meanA[t] = Int64(cen[t * 3 + 1])
                        meanB[t] = Int64(cen[t * 3 + 2])
                    }
                    t += 1
                }
                varL.update(repeating: 0, count: 3 * kk) // zeroes varL, varA, varB
                var vi = 0
                while vi < pp {
                    let t2 = Int(idx[vi])
                    let dl = Int64(px[vi * 3 + 0]) - meanL[t2]
                    let da = Int64(px[vi * 3 + 1]) - meanA[t2]
                    let db = Int64(px[vi * 3 + 2]) - meanB[t2]
                    varL[t2] += dl * dl
                    varA[t2] += da * da
                    varB[t2] += db * db
                    vi += 1
                }
                var ti = 0
                while ti < kk {
                    stats[ti * 7 + 0] = Int32(meanL[ti])
                    stats[ti * 7 + 1] = Int32(meanA[ti])
                    stats[ti * 7 + 2] = Int32(meanB[ti])
                    if counts[ti] > 0 {
                        let n = Int64(counts[ti])
                        stats[ti * 7 + 3] = Int32(isqrt64(varL[ti] / n))
                        stats[ti * 7 + 4] = Int32(isqrt64(varA[ti] / n))
                        stats[ti * 7 + 5] = Int32(isqrt64(varB[ti] / n))
                    } else {
                        stats[ti * 7 + 3] = 0
                        stats[ti * 7 + 4] = 0
                        stats[ti * 7 + 5] = 0
                    }
                    stats[ti * 7 + 6] = counts[ti]
                    ti += 1
                }
            }
        }

        return rcOK
    }
}
