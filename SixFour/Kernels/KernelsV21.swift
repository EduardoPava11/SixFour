//  KernelsV21.swift
//  Swift port of the V2.1 field section of Native/src/kernels.zig (2026-07-06);
//  byte-exact twin, golden-gated.
//
//  Thirteen exported kernels (the V2.1 pre-collapse field, ports of
//  SixFour.Spec.V21Field / SixFour.Spec.V21Transport): a "curve" carries one
//  channel's per-level energy or count; collapse of a curve is the sRGB byte the
//  V2 boundary consumes. These are ADDITIVE: no MVP1 path calls them. Memory
//  rule unchanged: caller owns all memory. All return S4_RC_* (RC_OUT_OF_RANGE
//  on a domain/envelope refusal).
//
//  Cross-slice call: `s4_octant_lift` (kernels.zig, another port slice) is
//  invoked by name from `s4_v21_octant_lift_curve`.
//
//  Translation semantics follow the dictionary in KernelsCore.swift (trapping
//  `+`/`-`/`*`, `@intCast` → trapping numeric init, `@mod` on a positive
//  modulus → the private `s4Mod64` below).

// ── Return codes (private copies of kernels.zig RC_*) ────────────────────────

private let rcOK: Int32 = 0
private let rcNullPtr: Int32 = 1
private let rcBadShape: Int32 = 2
private let rcScratchTooSmall: Int32 = 3
private let rcOutputTooSmall: Int32 = 4
private let rcInfeasibleSignificance: Int32 = 5
private let rcBadDitherMode: Int32 = 6
private let rcOutOfRange: Int32 = 7
private let rcNotImplemented: Int32 = 100

// ── Private helpers ──────────────────────────────────────────────────────────

/// The i32 envelope bounds the V2.1 kernels refuse to leave (kernels.zig
/// declares these as local `const i32max`/`const i32min` inside each kernel).
private let s4I32Max: Int64 = 2_147_483_647
private let s4I32Min: Int64 = -2_147_483_648

/// Euclidean/floored modulus on Int64 for a POSITIVE modulus — the Zig `@mod`
/// twin (Swift `%` truncates toward zero, which differs on a negative
/// dividend). NOTE: private helper; kernels.zig used the `@mod` builtin, so
/// this has no named Zig source counterpart.
@inline(__always)
private func s4Mod64(_ a: Int64, _ n: Int64) -> Int64 {
    let r = a % n
    return r < 0 ? r + n : r
}

// ── Exported kernels ─────────────────────────────────────────────────────────

/// V2.1 COLLAPSE (SixFour.Spec.V21Field.collapseQ16): per channel-curve, the energy-MINIMISING
/// level (argmin), with the LOWEST index winning ties (strict `<`, the same discipline as
/// nearestCentroidQ16). `curves` is [p*3*n_levels] Q16 energies in pixel-major order (pixel,
/// then channel R,G,B, then level); writes the p*3 collapsed levels as sRGB bytes into `out_rgb`.
/// This is the SEAM from the V2.1 pre-collapse field to the existing byte path: collapse of a
/// curve is the sRGB byte the V2 boundary consumes. Energy is order-only, so the result is exact
/// under any monotone code. n_levels must be <= 256 (the level is the byte).
@_cdecl("s4_v21_collapse")
public func s4_v21_collapse(
    _ curves: UnsafePointer<Int32>?,
    _ p: Int32,
    _ n_levels: Int32,
    _ out_rgb: UnsafeMutablePointer<UInt8>?
) -> Int32 {
    guard let curves, let out_rgb else { return rcNullPtr }
    if p <= 0 || n_levels <= 0 { return rcBadShape }
    if n_levels > 256 { return rcOutOfRange } // the level is written as a byte
    let nl = Int(n_levels)
    let total = Int(p) * 3
    var ch = 0
    while ch < total {
        let base = ch * nl
        var bestI = 0
        var bestV: Int32 = curves[base]
        var l = 1
        while l < nl {
            let v = curves[base + l]
            if v < bestV { // strict: first (lowest-index) minimum wins ties
                bestV = v
                bestI = l
            }
            l += 1
        }
        out_rgb[ch] = UInt8(bestI)
        ch += 1
    }
    return rcOK
}

/// V2.1 TRANSPORT (SixFour.Spec.V21Transport.transportDisp): the monotone 1-D optimal-transport map
/// T = F⁻¹∘F between two EQUAL-MASS count histograms, as a per-RANK integer displacement
/// d[k] = q_dst[k] - q_src[k] on the sorted-quantile (mass) line. `src`/`dst` are [p*3*n_levels] count
/// histograms (pixel-major: pixel, then channel R,G,B, then level), each per-(cell,channel) curve
/// summing to `mass`; writes [p*3*mass] displacements (same cell/channel major order, rank-contiguous).
/// This is the byte-exact seam that RESTORES the time axis the pooled field marginalises away: an
/// anchor curve plus this map reconstructs a frame's curve (s4_v21_pushforward). Computed allocation-
/// free by a two-pointer walk over the two CDFs; the rank matching is optimal for any convex ground
/// cost in 1-D. TOTAL: refuses (RC_OUT_OF_RANGE) n_levels>256, mass<=0, a negative count, or any
/// per-(cell,channel) curve whose counts do not sum to `mass` (the equal-mass precondition, guaranteed
/// on the soft-splat field where every cell totals box*w).
@_cdecl("s4_v21_transport")
public func s4_v21_transport(
    _ src: UnsafePointer<Int32>?,
    _ dst: UnsafePointer<Int32>?,
    _ p: Int32,
    _ n_levels: Int32,
    _ mass: Int32,
    _ out_disp: UnsafeMutablePointer<Int32>?
) -> Int32 {
    guard let src, let dst, let out_disp else { return rcNullPtr }
    if p <= 0 || n_levels <= 0 { return rcBadShape }
    if n_levels > 256 || mass <= 0 { return rcOutOfRange }
    let nl = Int(n_levels)
    let m = Int(mass)
    let total = Int(p) * 3
    var ch = 0
    while ch < total {
        let cbase = ch * nl
        let obase = ch * m
        // Equal-mass precondition: both curves must sum to exactly `mass`, no negative counts.
        var ssum: Int32 = 0
        var dsum: Int32 = 0
        var q = 0
        while q < nl {
            if src[cbase + q] < 0 || dst[cbase + q] < 0 { return rcOutOfRange }
            ssum += src[cbase + q]
            dsum += dst[cbase + q]
            q += 1
        }
        if ssum != mass || dsum != mass { return rcOutOfRange }
        // Two-pointer walk over the source/dest levels along the mass line: each unit of mass at src
        // level i is carried to dst level j, emitting the displacement j - i for that rank.
        var i = 0
        var j = 0
        var remI: Int32 = src[cbase + 0]
        var remJ: Int32 = dst[cbase + 0]
        var k = 0
        while k < m {
            while remI == 0 {
                i += 1
                remI = src[cbase + i]
            }
            while remJ == 0 {
                j += 1
                remJ = dst[cbase + j]
            }
            let take: Int32 = remI < remJ ? remI : remJ
            let d: Int32 = Int32(j) - Int32(i)
            var t: Int32 = 0
            while t < take {
                out_disp[obase + k] = d
                k += 1
                t += 1
            }
            remI -= take
            remJ -= take
        }
        ch += 1
    }
    return rcOK
}

/// V2.1 PUSHFORWARD (SixFour.Spec.V21Transport.pushforward): apply a per-rank displacement to a source
/// curve and re-bin, reproducing the transported curve. `src` is [p*3*n_levels] counts (each
/// per-(cell,channel) curve summing to `mass`); `disp` is [p*3*mass] rank displacements; writes `out`
/// [p*3*n_levels] counts. With `disp` = s4_v21_transport(src, dst) this yields `dst` byte-exact; with
/// the negated displacement it inverts back to the source (reversible, no data lost). TOTAL: refuses
/// (RC_OUT_OF_RANGE) n_levels>256, mass<=0, a curve not summing to `mass`, or a landing level
/// src_level+disp outside [0, n_levels).
@_cdecl("s4_v21_pushforward")
public func s4_v21_pushforward(
    _ src: UnsafePointer<Int32>?,
    _ disp: UnsafePointer<Int32>?,
    _ p: Int32,
    _ n_levels: Int32,
    _ mass: Int32,
    _ out: UnsafeMutablePointer<Int32>?
) -> Int32 {
    guard let src, let disp, let out else { return rcNullPtr }
    if p <= 0 || n_levels <= 0 { return rcBadShape }
    if n_levels > 256 || mass <= 0 { return rcOutOfRange }
    let nl = Int(n_levels)
    let m = Int(mass)
    let total = Int(p) * 3
    let outLen = total * nl
    var z = 0
    while z < outLen {
        out[z] = 0
        z += 1
    }
    var ch = 0
    while ch < total {
        let cbase = ch * nl
        let obase = ch * m
        // Equal-mass precondition on the source curve.
        var ssum: Int32 = 0
        var q = 0
        while q < nl {
            if src[cbase + q] < 0 { return rcOutOfRange }
            ssum += src[cbase + q]
            q += 1
        }
        if ssum != mass { return rcOutOfRange }
        // Walk the source quantiles in rank order (level i repeated src[i] times); land each at i+disp.
        var i = 0
        var k = 0
        while i < nl {
            var c: Int32 = src[cbase + i]
            while c > 0 {
                let land: Int32 = Int32(i) + disp[obase + k]
                if land < 0 || land >= n_levels { return rcOutOfRange }
                out[cbase + Int(land)] += 1
                k += 1
                c -= 1
            }
            i += 1
        }
        ch += 1
    }
    return rcOK
}

/// V2.1 per-level OCTANT LIFT DRIVER (SixFour.Spec.V21Field.liftOctList): drives the gated,
/// byte-exact s4_octant_lift over each of the n_levels curve levels. `octant_curves` is
/// [8*n_levels], cell-major (the 8 octant cells' one-channel curves, level-contiguous); writes the
/// coarse curve [n_levels] and the 7 residual curves [7*n_levels] (residual-major). NO new spine
/// math: the reversible edge is s4_octant_lift; this is only the per-level loop, in Zig. Refuses
/// (propagates RC_OUT_OF_RANGE) when a level's octant is out of the substrate domain.
@_cdecl("s4_v21_octant_lift_curve")
public func s4_v21_octant_lift_curve(
    _ octant_curves: UnsafePointer<Int32>?,
    _ n_levels: Int32,
    _ out_coarse: UnsafeMutablePointer<Int32>?,
    _ out_residuals: UnsafeMutablePointer<Int32>?
) -> Int32 {
    guard let octant_curves, let out_coarse, let out_residuals else { return rcNullPtr }
    if n_levels <= 0 { return rcBadShape }
    let nl = Int(n_levels)
    // Stack twins of the Zig `var in8/out8: [8]i32 = undefined` scratch.
    return withUnsafeTemporaryAllocation(of: Int32.self, capacity: 8) { in8 in
        withUnsafeTemporaryAllocation(of: Int32.self, capacity: 8) { out8 in
            var l = 0
            while l < nl {
                var w = 0
                while w < 8 {
                    in8[w] = octant_curves[w * nl + l]
                    w += 1
                }
                let rc = s4_octant_lift(in8.baseAddress, out8.baseAddress)
                if rc != rcOK { return rc }
                out_coarse[l] = out8[0]
                var r = 0
                while r < 7 {
                    out_residuals[r * nl + l] = out8[1 + r]
                    r += 1
                }
                l += 1
            }
            return rcOK
        }
    }
}

/// V2.1 OPPONENT DELTA (SixFour.Spec.V21Field.labDeltaAt): per level, the integer opponent
/// transform of the per-channel NEIGHBOUR DELTA. `bin1`/`bin2` are [3*n_levels] (R,G,B curves,
/// level-contiguous) Q16; writes [3*n_levels] (L,a,b) delta curves. By linearity, opponent of the
/// delta == delta of the opponent (lawOpponentCommutesWithDelta), so this is the encode target.
/// Computed in i64; refuses (RC_OUT_OF_RANGE) if any L,a,b leaves the i32 envelope rather than wrapping.
@_cdecl("s4_v21_opponent_delta")
public func s4_v21_opponent_delta(
    _ bin1: UnsafePointer<Int32>?,
    _ bin2: UnsafePointer<Int32>?,
    _ n_levels: Int32,
    _ out_lab: UnsafeMutablePointer<Int32>?
) -> Int32 {
    guard let bin1, let bin2, let out_lab else { return rcNullPtr }
    if n_levels <= 0 { return rcBadShape }
    let nl = Int(n_levels)
    var l = 0
    while l < nl {
        let dr: Int64 = Int64(bin1[l]) - Int64(bin2[l])
        let dg: Int64 = Int64(bin1[nl + l]) - Int64(bin2[nl + l])
        let db: Int64 = Int64(bin1[2 * nl + l]) - Int64(bin2[2 * nl + l])
        let ll: Int64 = dr + dg + db // L = R + G + B
        let aa: Int64 = dr - dg // a = R - G
        let bb: Int64 = dr + dg - 2 * db // b = R + G - 2B
        if ll > s4I32Max || ll < s4I32Min || aa > s4I32Max || aa < s4I32Min || bb > s4I32Max || bb < s4I32Min {
            return rcOutOfRange
        }
        out_lab[l] = Int32(ll)
        out_lab[nl + l] = Int32(aa)
        out_lab[2 * nl + l] = Int32(bb)
        l += 1
    }
    return rcOK
}

/// V2.1 CAPTURED-BIN ENERGY CURVE (make_bins core; SixFour.Spec.V21Field.countsToEnergy): the
/// empirical-histogram energy E(level) = total - count(level), total = the sum of that curve's
/// counts. argmin E = argmax count = the MODE (the most-observed value), so s4_v21_collapse of this
/// energy is the captured byte. The PROBABILITY face is the existing s4_board_counts_to_mass_q16
/// (boardMassFromCount); this is its order-dual ENERGY face, the same empirical-histogram algorithm
/// generalised to the per-channel value alphabet. `counts` is [p*3*n_levels] (pixel-major, R,G,B,
/// then level), non-negative; writes [p*3*n_levels] energies. Per-curve total in i64; refuses
/// (RC_OUT_OF_RANGE) if a total or an energy leaves the i32 envelope rather than wrapping.
@_cdecl("s4_v21_counts_to_energy")
public func s4_v21_counts_to_energy(
    _ counts: UnsafePointer<Int32>?,
    _ p: Int32,
    _ n_levels: Int32,
    _ out_energy: UnsafeMutablePointer<Int32>?
) -> Int32 {
    guard let counts, let out_energy else { return rcNullPtr }
    if p <= 0 || n_levels <= 0 { return rcBadShape }
    let nl = Int(n_levels)
    let ncurves = Int(p) * 3
    var c = 0
    while c < ncurves {
        let base = c * nl
        var total: Int64 = 0
        var l = 0
        while l < nl {
            total += Int64(counts[base + l])
            l += 1
        }
        if total > s4I32Max || total < s4I32Min { return rcOutOfRange }
        l = 0
        while l < nl {
            let e: Int64 = total - Int64(counts[base + l]) // E = total - count
            if e > s4I32Max || e < s4I32Min { return rcOutOfRange }
            out_energy[base + l] = Int32(e)
            l += 1
        }
        c += 1
    }
    return rcOK
}

/// V2.1 HISTOGRAM ACCUMULATION (the other half of make_bins; SixFour.Spec.V21Field.accumulateHist):
/// box-decimate a FINE grid into coarse output voxels and, per voxel per channel, count the fine
/// samples at each value level. A fine sample's coarse voxel is its integer floor-division by the
/// decimation factor (the SAME box grouping the cube-ladder reduction uses; V2.1 keeps the per-cell
/// value DISTRIBUTION instead of the reversible Haar detail). `fine` is [ft*fy*fx*3] u8, layout
/// (((ft*fy + y)*fx + x)*3 + ch); `out_counts` (zeroed here) is [ct*cy*cx*3*n_levels], layout
/// ((coarseVoxel*3 + ch)*n_levels + value). Dimensions must be divisible by the decimation factors.
/// Feeds s4_v21_counts_to_energy. TOTAL: refuses (RC_OUT_OF_RANGE) a value >= n_levels.
@_cdecl("s4_v21_accumulate_hist")
public func s4_v21_accumulate_hist(
    _ fine: UnsafePointer<UInt8>?,
    _ fx: Int32,
    _ fy: Int32,
    _ ft: Int32,
    _ dx: Int32,
    _ dy: Int32,
    _ dt: Int32,
    _ n_levels: Int32,
    _ out_counts: UnsafeMutablePointer<Int32>?
) -> Int32 {
    guard let fine, let out_counts else { return rcNullPtr }
    if fx <= 0 || fy <= 0 || ft <= 0 || dx <= 0 || dy <= 0 || dt <= 0 { return rcBadShape }
    if n_levels <= 0 || n_levels > 256 { return rcOutOfRange }
    if fx % dx != 0 || fy % dy != 0 || ft % dt != 0 { return rcBadShape }
    let ufx = Int(fx)
    let ufy = Int(fy)
    let uft = Int(ft)
    let udx = Int(dx)
    let udy = Int(dy)
    let udt = Int(dt)
    let cx = ufx / udx
    let cy = ufy / udy
    let ct = uft / udt
    let nl = Int(n_levels)
    let outLen = ct * cy * cx * 3 * nl
    var z = 0
    while z < outLen {
        out_counts[z] = 0
        z += 1
    }
    var fti = 0
    while fti < uft {
        var fyi = 0
        while fyi < ufy {
            var fxi = 0
            while fxi < ufx {
                let cvi = ((fti / udt) * cy + (fyi / udy)) * cx + (fxi / udx)
                var ch = 0
                while ch < 3 {
                    let fineIdx = ((fti * ufy + fyi) * ufx + fxi) * 3 + ch
                    let v = Int(fine[fineIdx])
                    if v >= nl { return rcOutOfRange }
                    out_counts[(cvi * 3 + ch) * nl + v] += 1
                    ch += 1
                }
                fxi += 1
            }
            fyi += 1
        }
        fti += 1
    }
    return rcOK
}

/// V2.1 GROUND-STATE CENTERING (SixFour.Spec.V21Field.centeredEnergy): subtract each curve's MINIMUM
/// so the energy is the excess above the ground state and the GIF byte (argmin) sits at energy 0. A
/// monotone shift, so s4_v21_collapse is unchanged. `curves` is [p*3*n_levels] (pixel-major, R,G,B,
/// then level); writes [p*3*n_levels] centered energies. Centering in i64; refuses (RC_OUT_OF_RANGE)
/// if a centered value leaves the i32 envelope rather than wrapping.
@_cdecl("s4_v21_centered_energy")
public func s4_v21_centered_energy(
    _ curves: UnsafePointer<Int32>?,
    _ p: Int32,
    _ n_levels: Int32,
    _ out_centered: UnsafeMutablePointer<Int32>?
) -> Int32 {
    guard let curves, let out_centered else { return rcNullPtr }
    if p <= 0 || n_levels <= 0 { return rcBadShape }
    let nl = Int(n_levels)
    let ncurves = Int(p) * 3
    var c = 0
    while c < ncurves {
        let base = c * nl
        var mn: Int32 = curves[base]
        var l = 1
        while l < nl {
            if curves[base + l] < mn { mn = curves[base + l] }
            l += 1
        }
        l = 0
        while l < nl {
            let e: Int64 = Int64(curves[base + l]) - Int64(mn)
            if e > s4I32Max || e < s4I32Min { return rcOutOfRange }
            out_centered[base + l] = Int32(e)
            l += 1
        }
        c += 1
    }
    return rcOK
}

/// V2.1 MODE-RELATIVE PRESENTATION (the encoder input; SixFour.Spec.V21Field.modeRelative): the
/// centered curve reindexed about its own mode (left-rotated by the argmin index), so the argmin is
/// pinned to relative-0 and the ABSOLUTE mode is WITHHELD (the GIF supplies it via s4_v21_anchor_at).
/// out[k] = curves[mode + k (mod n)] - min. `curves` is [p*3*n_levels]; writes [p*3*n_levels].
/// Refuses (RC_OUT_OF_RANGE) on a centering overflow, as s4_v21_centered_energy does.
@_cdecl("s4_v21_mode_relative")
public func s4_v21_mode_relative(
    _ curves: UnsafePointer<Int32>?,
    _ p: Int32,
    _ n_levels: Int32,
    _ out_rel: UnsafeMutablePointer<Int32>?
) -> Int32 {
    guard let curves, let out_rel else { return rcNullPtr }
    if p <= 0 || n_levels <= 0 { return rcBadShape }
    let nl = Int(n_levels)
    let ncurves = Int(p) * 3
    var c = 0
    while c < ncurves {
        let base = c * nl
        // argmin (lowest-index tie-break) = the mode; mn = the minimum value (the ground state).
        var bestI = 0
        var mn: Int32 = curves[base]
        var l = 1
        while l < nl {
            if curves[base + l] < mn {
                mn = curves[base + l]
                bestI = l
            }
            l += 1
        }
        var k = 0
        while k < nl {
            let src = (bestI + k) % nl
            let e: Int64 = Int64(curves[base + src]) - Int64(mn)
            if e > s4I32Max || e < s4I32Min { return rcOutOfRange }
            out_rel[base + k] = Int32(e)
            k += 1
        }
        c += 1
    }
    return rcOK
}

/// V2.1 ANCHOR (the left inverse of s4_v21_mode_relative GIVEN the GIF byte;
/// SixFour.Spec.V21Field.anchorAt): re-attach a mode-relative curve at its absolute mode level, so
/// anchor(mode, modeRelative(e)) == centeredEnergy(e) -- field + GIF reconstruct the field. `rel` is
/// [p*3*n_levels]; `modes` is [p*3] (the per-curve GIF level, e.g. from s4_v21_collapse); writes
/// [p*3*n_levels]. A pure permutation: out[l] = rel[(l - mode) mod n] (mode reduced into [0,n)).
@_cdecl("s4_v21_anchor_at")
public func s4_v21_anchor_at(
    _ rel: UnsafePointer<Int32>?,
    _ modes: UnsafePointer<Int32>?,
    _ p: Int32,
    _ n_levels: Int32,
    _ out_centered: UnsafeMutablePointer<Int32>?
) -> Int32 {
    guard let rel, let modes, let out_centered else { return rcNullPtr }
    if p <= 0 || n_levels <= 0 { return rcBadShape }
    let nl = Int(n_levels)
    let ncurves = Int(p) * 3
    let inl = Int64(nl)
    var c = 0
    while c < ncurves {
        let base = c * nl
        let m: Int64 = s4Mod64(Int64(modes[c]), inl) // mode reduced into [0, n)
        var l = 0
        while l < nl {
            let src = Int(s4Mod64(Int64(l) - m, inl)) // (l - mode) mod n
            out_centered[base + l] = rel[base + src]
            l += 1
        }
        c += 1
    }
    return rcOK
}

/// V2.1 PALETTE DELTA (the temporal metric weight; SixFour.Spec.V21Field.paletteDelta): the L1 /
/// total variation between two palettes' per-channel value histograms,
/// sum_{ch,v} |hist1(ch,v) - hist2(ch,v)|. PERMUTATION-INVARIANT (a palette's slot order is the index
/// gauge and does not change the count) and byte-exact, so it charges only a genuine change in the
/// colour DISTRIBUTION frame-to-frame, never the gauge. `pal1`/`pal2` are [k*3] u8 SLOT-MAJOR
/// (slot*3 + channel), each value in 0..n_levels-1; k is the slot count; writes the scalar delta to
/// out_pd[0]. A single signed accumulator carries the running difference (+1 per pal1 value, -1 per
/// pal2 value), then sums absolute values. Refuses (RC_OUT_OF_RANGE) n_levels>256 or a value>=n_levels.
@_cdecl("s4_v21_palette_delta")
public func s4_v21_palette_delta(
    _ pal1: UnsafePointer<UInt8>?,
    _ pal2: UnsafePointer<UInt8>?,
    _ k: Int32,
    _ n_levels: Int32,
    _ out_pd: UnsafeMutablePointer<Int32>?
) -> Int32 {
    guard let pal1, let pal2, let out_pd else { return rcNullPtr }
    if k <= 0 { return rcBadShape }
    if n_levels <= 0 || n_levels > 256 { return rcOutOfRange }
    let nl = Int(n_levels)
    let uk = Int(k)
    // Signed per-(channel,value) difference histogram, layout (ch*nl + value). Fixed 3*256 stack
    // buffer (n_levels is bounded by 256 above); only the first 3*nl entries are used.
    return withUnsafeTemporaryAllocation(of: Int32.self, capacity: 3 * 256) { diff in
        diff.initialize(repeating: 0)
        var s = 0
        while s < uk {
            var ch = 0
            while ch < 3 {
                let v1 = Int(pal1[s * 3 + ch])
                let v2 = Int(pal2[s * 3 + ch])
                if v1 >= nl || v2 >= nl { return rcOutOfRange }
                diff[ch * nl + v1] += 1
                diff[ch * nl + v2] -= 1
                ch += 1
            }
            s += 1
        }
        var pd: Int64 = 0
        var i = 0
        while i < 3 * nl {
            let d = Int64(diff[i])
            pd += d < 0 ? -d : d
            i += 1
        }
        if pd > 2_147_483_647 { return rcOutOfRange }
        out_pd[0] = Int32(pd)
        return rcOK
    }
}

/// V2.1 SOFT-SPLAT HISTOGRAM ACCUMULATION (the sub-LSB construction; SixFour.Spec.V21Field.accumulateHistSoft).
/// The distributional sibling of s4_v21_accumulate_hist that USES the 10-bit sensor bits the hard
/// round() throws away. Each `fine` sample is a HIGH-PRECISION position hi in 0 .. (n_levels-1)*w (its
/// linear value scaled by the sub-level budget w, so hi = level*w + subfraction). Instead of a hard +1
/// at round(hi/w), it SPLATS a unit of integer mass w across the two adjacent value levels: (w - hi%w)
/// at hi/w and hi%w at hi/w + 1. This is a partition of unity in integers (the two weights sum to w),
/// and the mass-weighted mean of the splat is EXACTLY hi (lawSoftSplatCentroidExact), so the discarded
/// sub-LSB fraction survives as the histogram's first moment. Each (voxel,channel) cell totals box*w.
/// `fine` is [ft*fy*fx*3] i32, layout (((ft*fy + y)*fx + x)*3 + ch); `out_counts` (zeroed here) is
/// [ct*cy*cx*3*n_levels], layout ((coarseVoxel*3 + ch)*n_levels + value). Dimensions must divide the
/// decimation factors. TOTAL: refuses (RC_OUT_OF_RANGE) w<=0, n_levels>256, or a hi outside
/// 0 .. (n_levels-1)*w. Feeds s4_v21_counts_to_energy exactly like the hard face.
@_cdecl("s4_v21_accumulate_hist_soft")
public func s4_v21_accumulate_hist_soft(
    _ fine: UnsafePointer<Int32>?,
    _ fx: Int32,
    _ fy: Int32,
    _ ft: Int32,
    _ dx: Int32,
    _ dy: Int32,
    _ dt: Int32,
    _ n_levels: Int32,
    _ w: Int32,
    _ out_counts: UnsafeMutablePointer<Int32>?
) -> Int32 {
    guard let fine, let out_counts else { return rcNullPtr }
    if fx <= 0 || fy <= 0 || ft <= 0 || dx <= 0 || dy <= 0 || dt <= 0 { return rcBadShape }
    if n_levels <= 0 || n_levels > 256 { return rcOutOfRange }
    if w <= 0 { return rcOutOfRange }
    if fx % dx != 0 || fy % dy != 0 || ft % dt != 0 { return rcBadShape }
    let ufx = Int(fx)
    let ufy = Int(fy)
    let uft = Int(ft)
    let udx = Int(dx)
    let udy = Int(dy)
    let udt = Int(dt)
    let cx = ufx / udx
    let cy = ufy / udy
    let ct = uft / udt
    let nl = Int(n_levels)
    let uw = Int64(w)
    let hiMax: Int64 = (Int64(n_levels) - 1) * uw // the top in-range position
    let outLen = ct * cy * cx * 3 * nl
    var z = 0
    while z < outLen {
        out_counts[z] = 0
        z += 1
    }
    var fti = 0
    while fti < uft {
        var fyi = 0
        while fyi < ufy {
            var fxi = 0
            while fxi < ufx {
                let cvi = ((fti / udt) * cy + (fyi / udy)) * cx + (fxi / udx)
                var ch = 0
                while ch < 3 {
                    let fineIdx = ((fti * ufy + fyi) * ufx + fxi) * 3 + ch
                    let hi = Int64(fine[fineIdx])
                    if hi < 0 || hi > hiMax { return rcOutOfRange }
                    let vlo = Int(hi / uw) // hi >= 0, so trunc == floor (@divTrunc)
                    let frac = Int32(hi % uw) // hi >= 0, so % == @mod
                    let cell = (cvi * 3 + ch) * nl
                    out_counts[cell + vlo] += w - frac // mass at the floor level
                    if frac != 0 && vlo + 1 < nl {
                        out_counts[cell + vlo + 1] += frac // remainder at the next level
                    }
                    ch += 1
                }
                fxi += 1
            }
            fyi += 1
        }
        fti += 1
    }
    return rcOK
}

/// V2.1 1-D WASSERSTEIN-1 PALETTE METRIC (SixFour.Spec.V21Field.paletteW1): the L1 distance between the
/// two palettes' per-channel value CDFs, sum_{ch,v} |CDF1(ch,v) - CDF2(ch,v)|. Where s4_v21_palette_delta
/// is the total variation (L1 of the HISTOGRAMS, horizontal-blind), this inserts a per-channel running
/// cumulative sum before the abs-sum, so it charges the GROUND DISTANCE mass must travel: a 1-level
/// drift costs 1 per unit mass, a far jump costs the full span. Byte-exact integer (cumsum is linear,
/// no division), permutation-invariant. `pal1`/`pal2` are [k*3] u8 SLOT-MAJOR (slot*3 + channel), each
/// value in 0..n_levels-1; writes the scalar to out_wd. REQUIRES equal per-channel total mass (both are
/// k-slot palettes, so each channel totals k); the running CDF difference returns to 0 at the last
/// level. Refuses (RC_OUT_OF_RANGE) n_levels>256 or a value >= n_levels.
@_cdecl("s4_v21_wdist1d")
public func s4_v21_wdist1d(
    _ pal1: UnsafePointer<UInt8>?,
    _ pal2: UnsafePointer<UInt8>?,
    _ k: Int32,
    _ n_levels: Int32,
    _ out_wd: UnsafeMutablePointer<Int32>?
) -> Int32 {
    guard let pal1, let pal2, let out_wd else { return rcNullPtr }
    if k <= 0 { return rcBadShape }
    if n_levels <= 0 || n_levels > 256 { return rcOutOfRange }
    let nl = Int(n_levels)
    let uk = Int(k)
    // Signed per-(channel,value) difference histogram, layout (ch*nl + value). Same build as
    // s4_v21_palette_delta; the only difference is the reduction below (cumsum then abs-sum).
    return withUnsafeTemporaryAllocation(of: Int32.self, capacity: 3 * 256) { diff in
        diff.initialize(repeating: 0)
        var s = 0
        while s < uk {
            var ch = 0
            while ch < 3 {
                let v1 = Int(pal1[s * 3 + ch])
                let v2 = Int(pal2[s * 3 + ch])
                if v1 >= nl || v2 >= nl { return rcOutOfRange }
                diff[ch * nl + v1] += 1
                diff[ch * nl + v2] -= 1
                ch += 1
            }
            s += 1
        }
        // W1 = sum over channels of sum_v |running cumulative diff up to v| (the L1 between the CDFs).
        var wd: Int64 = 0
        var ch = 0
        while ch < 3 {
            var run: Int64 = 0 // the CDF difference, reset per channel
            var v = 0
            while v < nl {
                run += Int64(diff[ch * nl + v])
                wd += run < 0 ? -run : run
                v += 1
            }
            ch += 1
        }
        if wd > 2_147_483_647 { return rcOutOfRange }
        out_wd[0] = Int32(wd)
        return rcOK
    }
}
