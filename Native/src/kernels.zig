// SixFour deterministic quantized core — C ABI surface (Stage 0 scaffold).
//
// These kernels replace the GPU/Swift palette+dither+GIF path with a fixed-point
// integer pipeline so the 64-frame GIF is produced 100% deterministically
// (bit-exact, cross-device). The compute boundary: Metal hands back linear-sRGB
// Float16 halfs; Zig does linear→OKLab (fixed-point cbrt) + quantize + dither +
// significance + OKLab→sRGB8 (fixed-point gamma) + LZW/GIF89a.
//
// Contract (matches s4_load_look_net): the caller owns ALL memory; no allocator
// crosses the boundary. Working memory is a caller-provided `scratch` buffer
// sized by s4_burst_scratch_bytes. Functions return i32 rc (0 == ok).
//
// Stage 0 lands the ABI + the pure size helpers; each kernel returns
// S4_RC_NOT_IMPLEMENTED until its spec-first stage (see plan
// stateful-spinning-lemon.md) ports it byte-exact against a Haskell golden.

const std = @import("std");

// ── logging: the core PUSHES evidence of work through a caller-registered
// callback (Swift forwards it to os.Logger). No-op until a callback is set, so
// the host fixture tests stay silent and zero-allocation. Logs never affect the
// returned bytes — they are telemetry, outside the deterministic contract.
const LogFn = *const fn (msg: [*c]const u8, len: usize) callconv(.c) void;
var g_log_cb: ?LogFn = null;

pub export fn s4_set_log_callback(cb: ?LogFn) void {
    g_log_cb = cb;
}

fn s4log(comptime fmt: []const u8, args: anytype) void {
    const cb = g_log_cb orelse return; // skip all formatting when no sink is set
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
    cb(msg.ptr, msg.len);
}

// ── return codes (mirror sixfour_native.h) ───────────────────────────────────
pub const RC_OK: i32 = 0;
pub const RC_NULL_PTR: i32 = 1;
pub const RC_BAD_SHAPE: i32 = 2;
pub const RC_SCRATCH_TOO_SMALL: i32 = 3;
pub const RC_OUTPUT_TOO_SMALL: i32 = 4;
pub const RC_INFEASIBLE_SIGNIFICANCE: i32 = 5;
pub const RC_BAD_DITHER_MODE: i32 = 6;
pub const RC_NOT_IMPLEMENTED: i32 = 100;

// ── fixed-point + shape constants ─────────────────────────────────────────────
// Q16: OKLab L∈[0,1]→[0,65536], a,b∈[-0.5,0.5]→[±32768]. Matches the production
// Metal scale (Shaders.metal ×2^16 / ÷65536). Distances accumulate in i64.
pub const Q16_SHIFT: u5 = 16;
pub const Q16_ONE: i32 = 1 << 16;

pub const SIDE: i32 = 64; // each frame is 64×64
pub const FRAME_COUNT: i32 = 64; // 64 frames per burst
pub const K: i32 = 256; // 256 palette entries per frame
pub const CHANNELS: i32 = 3; // OKLab / linear-RGB triplets

// ── pure size helpers (implemented now; stabilise the ABI for Swift) ──────────

/// Upper bound on the GIF89a byte length for a burst of `frame_count` frames,
/// each `side`×`side`, with `k`-entry local colour tables. Generous so the Swift
/// caller can size `out_gif` once. Returns 0 on a nonsensical shape.
pub export fn s4_gif_encode_burst_bound(frame_count: i32, side: i32, k: i32) usize {
    if (frame_count <= 0 or side <= 0 or k <= 0) return 0;
    const fc: usize = @intCast(frame_count);
    const p: usize = @as(usize, @intCast(side)) * @as(usize, @intCast(side));
    const kk: usize = @intCast(k);

    // Header + logical screen descriptor + Netscape loop extension.
    const file_overhead: usize = 6 + 7 + 19;
    // Generous slack for an optional comment-extension metadata block + trailer.
    const comment_slack: usize = 8192;

    // Per frame: graphics-control (8) + image descriptor (10) + local colour
    // table (3·k) + worst-case LZW (no compression: ~12-bit codes ⇒ <2·P bytes,
    // plus a 1-byte length per 255-byte sub-block, plus framing) + minCodeSize.
    const per_frame: usize = 8 + 10 + 3 * kk + (2 * p + p / 255 + 64);

    return file_overhead + comment_slack + fc * per_frame + 1;
}

/// Working-memory bytes the burst pipeline needs in `scratch`. Frames are
/// processed one at a time, so this is one frame's working set plus the
/// quantiser's 32³ moment histogram (the dominant term) plus the LZW dictionary.
pub export fn s4_burst_scratch_bytes(frame_count: i32, side: i32, k: i32) usize {
    _ = frame_count; // per-frame processing ⇒ independent of frame_count
    if (side <= 0 or k <= 0) return 0;
    const p: usize = @as(usize, @intCast(side)) * @as(usize, @intCast(side));
    const kk: usize = @intCast(k);

    const oklab_q16: usize = p * 3 * @sizeOf(i32); // one frame in OKLab Q16
    const err_q16: usize = p * 3 * @sizeOf(i32); // dither error buffer
    const centroids: usize = kk * 3 * @sizeOf(i32);
    const accum: usize = kk * 4 * @sizeOf(i64); // Lloyd: 3 channel sums + count
    const indices: usize = p; // one frame of u8 indices
    const palette_rgb: usize = kk * 3; // one frame of sRGB8
    // Wu/variance-cut seed histogram: 32³ cells × 10 moments × i64.
    const hist: usize = 32 * 32 * 32 * 10 * @sizeOf(i64);
    // LZW dictionary: open-addressed (prefix:u16, byte:u8)→code:u16, ≤4096 codes.
    const lzw_dict: usize = 8192 * @sizeOf(u32);
    const slack: usize = 64 * 1024;

    return oklab_q16 + err_q16 + centroids + accum + indices + palette_rgb +
        hist + lzw_dict + slack;
}

// ── kernel stubs (bodies land in their spec-first stages) ─────────────────────
// Signatures are final; only the bodies change. Unused params are intentional
// while these return NOT_IMPLEMENTED.

/// Whole-burst entrypoint: linear-sRGB halfs → deterministic GIF89a bytes.
pub export fn s4_gif_encode_burst(
    in_halfs: [*c]const u16,
    frame_count: i32,
    side: i32,
    k: i32,
    input_space: i32,
    lloyd_iters: i32,
    dither_mode: i32,
    serpentine: i32,
    stbn_mask: [*c]const u8,
    frame_delay_cs: u16,
    comment: [*c]const u8,
    comment_len: i32,
    out_gif: [*c]u8,
    out_cap: usize,
    out_len: [*c]usize,
    scratch: ?*anyopaque,
    scratch_cap: usize,
) i32 {
    _ = .{
        in_halfs,    frame_count, side,    k,          input_space,
        lloyd_iters, dither_mode, serpentine, stbn_mask, frame_delay_cs,
        comment,     comment_len, out_gif, out_cap,    out_len,
        scratch,     scratch_cap,
    };
    return RC_NOT_IMPLEMENTED;
}

/// Widen IEEE-half bytes to Q16 i32 with the pinned rounding rule.
pub export fn s4_widen_half_to_q16(halfs: [*c]const u16, n: i32, out_q16: [*c]i32) i32 {
    _ = .{ halfs, n, out_q16 };
    return RC_NOT_IMPLEMENTED;
}

// Ottosson M1 (linear sRGB→LMS) and M2 (LMS'→OKLab), Q16, row-major. These are
// the SAME integer literals as SixFour.Spec.ColorFixed — the byte-exact contract.
const M1_Q16 = [9]i64{ 27015, 35149, 3372, 13887, 44610, 7038, 5787, 18463, 41286 };
const M2_Q16 = [9]i64{ 13792, 52011, -267, 129630, -159160, 29530, 1698, 51300, -52997 };

inline fn clampPosOklab(v: i64) i64 {
    if (v < 0) return 0;
    if (v > 131072) return 131072; // linear ≤ 2.0 keeps icbrt inside i64
    return v;
}

/// Exact integer floor cube root in Q16: floor(cbrt(x/2^16) * 2^16), i.e. the
/// largest Y with Y³ ≤ x·2^32. Pure integer binary search — bit-for-bit
/// identical to SixFour.Spec.ColorFixed.icbrtQ16. x is clamped to [0, 131072]
/// so x·2^32 ≤ 2^49 and every mid³ ≤ 2^51 stays inside i64 (ReleaseSafe traps).
fn icbrtQ16(x_in: i64) i64 {
    if (x_in <= 0) return 0;
    const x: i64 = if (x_in > 131072) 131072 else x_in;
    const n: i64 = x << 32;
    var lo: i64 = 0;
    var hi: i64 = 1 << 17;
    while (lo < hi) {
        const mid = @divTrunc(lo + hi + 1, 2);
        if (mid * mid * mid <= n) {
            lo = mid;
        } else {
            hi = mid - 1;
        }
    }
    return lo;
}

/// Fixed-point linear-sRGB Q16 → OKLab Q16. Integer-only; truncating-toward-zero
/// division (@divTrunc == Haskell `quot`); exact floor cube root. Mirrors
/// SixFour.Spec.ColorFixed.linearToOklabQ16 byte-for-byte.
pub export fn s4_linear_to_oklab_q16(lin_q16: [*c]const i32, p: i32, out_oklab_q16: [*c]i32) i32 {
    if (lin_q16 == null or out_oklab_q16 == null) return RC_NULL_PTR;
    if (p <= 0) return RC_BAD_SHAPE;
    const q16: i64 = Q16_ONE;
    const n: usize = @intCast(p);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const r: i64 = @max(@as(i64, 0), @as(i64, lin_q16[i * 3 + 0]));
        const g: i64 = @max(@as(i64, 0), @as(i64, lin_q16[i * 3 + 1]));
        const b: i64 = @max(@as(i64, 0), @as(i64, lin_q16[i * 3 + 2]));
        const l = clampPosOklab(@divTrunc(M1_Q16[0] * r + M1_Q16[1] * g + M1_Q16[2] * b, q16));
        const m = clampPosOklab(@divTrunc(M1_Q16[3] * r + M1_Q16[4] * g + M1_Q16[5] * b, q16));
        const s = clampPosOklab(@divTrunc(M1_Q16[6] * r + M1_Q16[7] * g + M1_Q16[8] * b, q16));
        const lc = icbrtQ16(l);
        const mc = icbrtQ16(m);
        const sc = icbrtQ16(s);
        const big_l = @divTrunc(M2_Q16[0] * lc + M2_Q16[1] * mc + M2_Q16[2] * sc, q16);
        const a_out = @divTrunc(M2_Q16[3] * lc + M2_Q16[4] * mc + M2_Q16[5] * sc, q16);
        const b_out = @divTrunc(M2_Q16[6] * lc + M2_Q16[7] * mc + M2_Q16[8] * sc, q16);
        out_oklab_q16[i * 3 + 0] = @intCast(big_l);
        out_oklab_q16[i * 3 + 1] = @intCast(a_out);
        out_oklab_q16[i * 3 + 2] = @intCast(b_out);
    }
    return RC_OK;
}

/// Per-frame quantise → k centroids + assignment. Maximin (farthest-first)
/// seeding (the diversity-optimal Gonzalez-1985 rule, the per-frame COVERAGE
/// objective), then `lloyd_iters` optional Lloyd refinements (`@divTrunc` means,
/// empty cluster keeps its old centroid), then nearest-centroid assignment
/// (strict-<, lowest index). Mirrors SixFour.Spec.QuantFixed byte-for-byte.
/// k ≤ 256 (u8 indices). `scratch` ≥ p·8 + 3·k·8 + k·4 bytes.
pub export fn s4_quantize_frame(
    oklab_q16: [*c]const i32,
    p: i32,
    k: i32,
    lloyd_iters: i32,
    out_centroids_q16: [*c]i32,
    out_indices: [*c]u8,
    scratch: ?*anyopaque,
    scratch_cap: usize,
) i32 {
    if (oklab_q16 == null or out_centroids_q16 == null or out_indices == null) return RC_NULL_PTR;
    // k > p would make maximin return duplicate seeds (a silent degenerate
    // palette); fail loud instead. Shipped shape (p=4096, k=256) is unaffected.
    if (p <= 0 or k <= 0 or k > 256 or k > p) return RC_BAD_SHAPE;
    const pp: usize = @intCast(p);
    const kk: usize = @intCast(k);

    const need = pp * @sizeOf(i64) + 3 * kk * @sizeOf(i64) + kk * @sizeOf(i32);
    if (scratch == null or scratch_cap < need) return RC_SCRATCH_TOO_SMALL;
    const base: [*]u8 = @ptrCast(scratch.?);
    const mind: [*]i64 = @ptrCast(@alignCast(base));
    const sums: [*]i64 = @ptrCast(@alignCast(base + pp * @sizeOf(i64)));
    const counts: [*]i32 = @ptrCast(@alignCast(base + pp * @sizeOf(i64) + 3 * kk * @sizeOf(i64)));

    // ── maximin (farthest-first) seeding ──────────────────────────────────────
    var sl: i64 = 0;
    var sa: i64 = 0;
    var sb: i64 = 0;
    var i: usize = 0;
    while (i < pp) : (i += 1) {
        sl += oklab_q16[i * 3 + 0];
        sa += oklab_q16[i * 3 + 1];
        sb += oklab_q16[i * 3 + 2];
    }
    const ml = @divTrunc(sl, @as(i64, p));
    const ma = @divTrunc(sa, @as(i64, p));
    const mb = @divTrunc(sb, @as(i64, p));

    // first seed = pixel farthest from the integer mean (strict >, lowest index)
    var first: usize = 0;
    var bd: i64 = -1;
    i = 0;
    while (i < pp) : (i += 1) {
        const d = distSqCentroid(oklab_q16, i, ml, ma, mb);
        if (d > bd) {
            bd = d;
            first = i;
        }
    }
    out_centroids_q16[0] = oklab_q16[first * 3 + 0];
    out_centroids_q16[1] = oklab_q16[first * 3 + 1];
    out_centroids_q16[2] = oklab_q16[first * 3 + 2];
    {
        const fl: i64 = oklab_q16[first * 3 + 0];
        const fa: i64 = oklab_q16[first * 3 + 1];
        const fb: i64 = oklab_q16[first * 3 + 2];
        i = 0;
        while (i < pp) : (i += 1) mind[i] = distSqCentroid(oklab_q16, i, fl, fa, fb);
    }

    var chosen: usize = 1;
    while (chosen < kk) : (chosen += 1) {
        var next_i: usize = 0;
        var bm: i64 = -1;
        i = 0;
        while (i < pp) : (i += 1) {
            if (mind[i] > bm) {
                bm = mind[i];
                next_i = i;
            }
        }
        out_centroids_q16[chosen * 3 + 0] = oklab_q16[next_i * 3 + 0];
        out_centroids_q16[chosen * 3 + 1] = oklab_q16[next_i * 3 + 1];
        out_centroids_q16[chosen * 3 + 2] = oklab_q16[next_i * 3 + 2];
        const nl: i64 = oklab_q16[next_i * 3 + 0];
        const na: i64 = oklab_q16[next_i * 3 + 1];
        const nb: i64 = oklab_q16[next_i * 3 + 2];
        i = 0;
        while (i < pp) : (i += 1) {
            const d = distSqCentroid(oklab_q16, i, nl, na, nb);
            if (d < mind[i]) mind[i] = d;
        }
    }

    // ── Lloyd refinement (optional; 0 = pure maximin) ─────────────────────────
    var iter: i32 = 0;
    while (iter < lloyd_iters) : (iter += 1) {
        @memset(sums[0 .. 3 * kk], 0);
        @memset(counts[0..kk], 0);
        i = 0;
        while (i < pp) : (i += 1) {
            const j = nearestCentroidQ16(out_centroids_q16, kk, oklab_q16[i * 3 + 0], oklab_q16[i * 3 + 1], oklab_q16[i * 3 + 2]);
            sums[j * 3 + 0] += oklab_q16[i * 3 + 0];
            sums[j * 3 + 1] += oklab_q16[i * 3 + 1];
            sums[j * 3 + 2] += oklab_q16[i * 3 + 2];
            counts[j] += 1;
        }
        var j: usize = 0;
        while (j < kk) : (j += 1) {
            if (counts[j] > 0) {
                const n: i64 = counts[j];
                out_centroids_q16[j * 3 + 0] = @intCast(@divTrunc(sums[j * 3 + 0], n));
                out_centroids_q16[j * 3 + 1] = @intCast(@divTrunc(sums[j * 3 + 1], n));
                out_centroids_q16[j * 3 + 2] = @intCast(@divTrunc(sums[j * 3 + 2], n));
            } // else keep old centroid
        }
    }

    // ── final nearest-centroid assignment ─────────────────────────────────────
    i = 0;
    while (i < pp) : (i += 1) {
        out_indices[i] = @intCast(nearestCentroidQ16(out_centroids_q16, kk, oklab_q16[i * 3 + 0], oklab_q16[i * 3 + 1], oklab_q16[i * 3 + 2]));
    }
    s4log("quantize  p={d} k={d} lloyd={d} (maximin seed)", .{ p, k, lloyd_iters });
    return RC_OK;
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
pub export fn s4_global_collapse(
    palettes_q16: [*c]const i32,
    t: i32,
    k_in: i32,
    k_out: i32,
    out_leaves_q16: [*c]i32,
    out_indices: [*c]u8,
    scratch: ?*anyopaque,
    scratch_cap: usize,
) i32 {
    if (palettes_q16 == null or out_leaves_q16 == null or out_indices == null) return RC_NULL_PTR;
    if (t <= 0 or k_in <= 0) return RC_BAD_SHAPE;
    // Pooled candidate count = t·k_in. Guard the i32 product (ReleaseSafe traps).
    const p64: i64 = @as(i64, t) * @as(i64, k_in);
    if (p64 > 2147483647) return RC_BAD_SHAPE;
    const p: i32 = @intCast(p64);
    // The pooled cloud is already contiguous, so the maximin seed phase of the
    // per-frame quantiser (lloyd_iters = 0) IS the collapse; its final assignment
    // is the per-frame re-index (flattened). One byte-exact code path, two scales.
    const rc = s4_quantize_frame(palettes_q16, p, k_out, 0, out_leaves_q16, out_indices, scratch, scratch_cap);
    if (rc == RC_OK) s4log("collapse  t={d} k_in={d} k_out={d} (pooled maximin)", .{ t, k_in, k_out });
    return rc;
}

// ── owned integer Haar (reversible lifting / S-transform) ─────────────────────
// The palette's dimensional space as EXACT integer math: a node stores the full
// detail d = x - y and a lifted floor-average parent = y + floor(d/2); the inverse
// recovers (x, y) exactly for all integers. So reconstruct∘analyze = id BYTE-EXACT
// (no tolerance) and a coefficient move (+δ then −δ) is exactly reversible. Mirrors
// SixFour.Spec.PairTreeFixed. n must be a power of two; offsets are laid out
// coarsest-first (level ℓ's 2^ℓ details at indices [2^ℓ−1 .. 2^(ℓ+1)−1)).

fn isPow2(n: i32) bool {
    return n > 0 and (n & (n - 1)) == 0;
}

/// Forward integer Haar: 2^D leaves → root + (2^D − 1) detail offsets (Q16,
/// interleaved L,a,b). `scratch` ≥ n·3·4 bytes (a working copy of the leaves).
pub export fn s4_haar_analyze(
    leaves_q16: [*c]const i32,
    n: i32,
    out_root_q16: [*c]i32,
    out_offsets_q16: [*c]i32,
    scratch: ?*anyopaque,
    scratch_cap: usize,
) i32 {
    if (leaves_q16 == null or out_root_q16 == null or out_offsets_q16 == null) return RC_NULL_PTR;
    if (!isPow2(n)) return RC_BAD_SHAPE;
    const nn: usize = @intCast(n);
    const need = nn * 3 * @sizeOf(i32);
    if (scratch == null or scratch_cap < need) return RC_SCRATCH_TOO_SMALL;
    const work: [*]i32 = @ptrCast(@alignCast(scratch.?));
    var i: usize = 0;
    while (i < nn * 3) : (i += 1) work[i] = leaves_q16[i];

    var cur: usize = nn;
    while (cur > 1) {
        const half = cur / 2;
        const out_start = half - 1; // 2^ℓ − 1
        i = 0;
        while (i < half) : (i += 1) {
            var c: usize = 0;
            while (c < 3) : (c += 1) {
                const x = work[(2 * i) * 3 + c];
                const y = work[(2 * i + 1) * 3 + c];
                const d = x - y;
                work[i * 3 + c] = y + @divFloor(d, 2); // lifted parent
                out_offsets_q16[(out_start + i) * 3 + c] = d; // detail
            }
        }
        cur = half;
    }
    out_root_q16[0] = work[0];
    out_root_q16[1] = work[1];
    out_root_q16[2] = work[2];
    s4log("haar_an   n={d} (reversible lifting)", .{n});
    return RC_OK;
}

/// Inverse integer Haar: root + (2^D − 1) offsets → 2^D leaves. Exact inverse of
/// `s4_haar_analyze`. In-place expansion (no scratch).
pub export fn s4_haar_reconstruct(
    root_q16: [*c]const i32,
    offsets_q16: [*c]const i32,
    n: i32,
    out_leaves_q16: [*c]i32,
) i32 {
    if (root_q16 == null or offsets_q16 == null or out_leaves_q16 == null) return RC_NULL_PTR;
    if (!isPow2(n)) return RC_BAD_SHAPE;
    const nn: usize = @intCast(n);
    out_leaves_q16[0] = root_q16[0];
    out_leaves_q16[1] = root_q16[1];
    out_leaves_q16[2] = root_q16[2];

    var cur: usize = 1;
    while (cur < nn) {
        const out_start = cur - 1; // 2^ℓ − 1
        var i: usize = cur;
        while (i > 0) {
            i -= 1;
            var c: usize = 0;
            while (c < 3) : (c += 1) {
                const node = out_leaves_q16[i * 3 + c];
                const d = offsets_q16[(out_start + i) * 3 + c];
                const y = node - @divFloor(d, 2);
                out_leaves_q16[(2 * i) * 3 + c] = y + d; // x
                out_leaves_q16[(2 * i + 1) * 3 + c] = y; // y
            }
        }
        cur *= 2;
    }
    s4log("haar_rec  n={d} (reversible lifting)", .{n});
    return RC_OK;
}

// Error-diffusion taps: (dx, dy, num, den). FS = 7/3/5/1 ÷ 16; Atkinson = 6 × 1/8.
const FS_TAPS = [4][4]i32{ .{ 1, 0, 7, 16 }, .{ -1, 1, 3, 16 }, .{ 0, 1, 5, 16 }, .{ 1, 1, 1, 16 } };
const ATKINSON_TAPS = [6][4]i32{ .{ 1, 0, 1, 8 }, .{ 2, 0, 1, 8 }, .{ -1, 1, 1, 8 }, .{ 0, 1, 1, 8 }, .{ 1, 1, 1, 8 }, .{ 0, 2, 1, 8 } };

// Squared Q16 distance, point→centroid j. SCALAR i64 — deliberately NOT a
// @Vector(4,i64): aarch64/NEON has no 64-bit-lane SIMD integer multiply, so a
// v2i64 multiply scalarizes in LLVM and only adds pack/unpack overhead. The
// scalar i64 multiply is a native arm64 op. The real SIMD win lives at the
// SoA-across-centroids level (i32 diffs + widening SMULL/vmull i32×i32→i64),
// not inside a single 3-channel distance — see the deferred SoA quantize path.
inline fn distSqCentroid(c: [*c]const i32, j: usize, l: i64, a: i64, b: i64) i64 {
    const dl = l - c[j * 3 + 0];
    const da = a - c[j * 3 + 1];
    const db = b - c[j * 3 + 2];
    return dl * dl + da * da + db * db;
}

// Nearest centroid index; strict < ⇒ lowest index on ties.
fn nearestCentroidQ16(c: [*c]const i32, k: usize, l: i64, a: i64, b: i64) usize {
    var best: usize = 0;
    var bd: i64 = distSqCentroid(c, 0, l, a, b);
    var j: usize = 1;
    while (j < k) : (j += 1) {
        const d = distSqCentroid(c, j, l, a, b);
        if (d < bd) {
            bd = d;
            best = j;
        }
    }
    return best;
}

// Two nearest centroid indices {i0 closest, i1 second}; i1 == i0 only when k == 1.
// Single fused k-scan (vs the old two-pass argmin) — halves the distSqCentroid
// calls on the blue-noise path. Byte-identical: near0 keeps the strict-< global
// min (lowest index on ties); when a new global min appears the old best demotes
// to near1, so near1 is the strict-< min over j≠near0 (lowest index on ties).
fn nearest2CentroidQ16(c: [*c]const i32, k: usize, l: i64, a: i64, b: i64) [2]usize {
    var near0: usize = 0;
    var bd0: i64 = distSqCentroid(c, 0, l, a, b);
    var near1: usize = 0;
    var bd1: i64 = std.math.maxInt(i64);
    var j: usize = 1;
    while (j < k) : (j += 1) {
        const d = distSqCentroid(c, j, l, a, b);
        if (d < bd0) {
            bd1 = bd0;
            near1 = near0;
            bd0 = d;
            near0 = j;
        } else if (d < bd1) {
            bd1 = d;
            near1 = j;
        }
    }
    if (k == 1) near1 = near0;
    return .{ near0, near1 };
}

/// Per-frame dither against a fixed palette → indices. Mirrors Dither.swift /
/// SixFour.Spec.SpatialDither byte-for-byte.
/// dither_mode: 0=FloydSteinberg, 1=Atkinson, 2=blueNoise spatiotemporal, 3=frozen.
/// (modes 2 and 3 are identical at the kernel level — the caller chooses which
/// STBN3D slice to pass.) Error-diffusion modes need `scratch` ≥ 3·p·4 bytes.
pub export fn s4_dither_frame(
    oklab_q16: [*c]const i32,
    centroids_q16: [*c]const i32,
    p: i32,
    k: i32,
    dither_mode: i32,
    serpentine: i32,
    stbn_slice: [*c]const u8,
    out_indices: [*c]u8,
    scratch: ?*anyopaque,
    scratch_cap: usize,
) i32 {
    if (oklab_q16 == null or centroids_q16 == null or out_indices == null) return RC_NULL_PTR;
    if (p <= 0 or k <= 0 or k > 256) return RC_BAD_SHAPE;
    const pp: usize = @intCast(p);
    const kk: usize = @intCast(k);

    // ── ordered blue-noise (modes 2, 3): independent per pixel ────────────────
    if (dither_mode >= 2) {
        if (stbn_slice == null) return RC_BAD_DITHER_MODE;
        var i: usize = 0;
        while (i < pp) : (i += 1) {
            const pl: i64 = oklab_q16[i * 3 + 0];
            const pa: i64 = oklab_q16[i * 3 + 1];
            const pb: i64 = oklab_q16[i * 3 + 2];
            const nn = nearest2CentroidQ16(centroids_q16, kk, pl, pa, pb);
            if (nn[0] == nn[1]) {
                out_indices[i] = @intCast(nn[0]);
                continue;
            }
            const c0l: i64 = centroids_q16[nn[0] * 3 + 0];
            const c0a: i64 = centroids_q16[nn[0] * 3 + 1];
            const c0b: i64 = centroids_q16[nn[0] * 3 + 2];
            const axl = centroids_q16[nn[1] * 3 + 0] - c0l;
            const axa = centroids_q16[nn[1] * 3 + 1] - c0a;
            const axb = centroids_q16[nn[1] * 3 + 2] - c0b;
            const denom = axl * axl + axa * axa + axb * axb;
            const num = (pl - c0l) * axl + (pa - c0a) * axa + (pb - c0b) * axb;
            var s_q16: i64 = 0;
            if (denom > 0) {
                s_q16 = @divTrunc(num * 65536, denom);
                if (s_q16 < 0) s_q16 = 0;
                if (s_q16 > 65536) s_q16 = 65536;
            }
            const t_q16: i64 = (2 * @as(i64, stbn_slice[i]) + 1) * 128;
            out_indices[i] = if (s_q16 > t_q16) @intCast(nn[1]) else @intCast(nn[0]);
        }
        s4log("dither    p={d} k={d} mode={d} (blue-noise)", .{ p, k, dither_mode });
        return RC_OK;
    }

    // ── error diffusion (modes 0, 1): sequential, mutate a working copy ───────
    if (dither_mode != 0 and dither_mode != 1) return RC_BAD_DITHER_MODE;
    const side_i = isqrt64(@as(i64, p));
    if (side_i * side_i != @as(i64, p)) return RC_BAD_SHAPE;
    const side: usize = @intCast(side_i);

    const need = pp * 3 * @sizeOf(i32);
    if (scratch == null or scratch_cap < need) return RC_SCRATCH_TOO_SMALL;
    const buf: [*]i32 = @ptrCast(@alignCast(scratch.?));
    var ci: usize = 0;
    while (ci < pp * 3) : (ci += 1) buf[ci] = oklab_q16[ci];

    const taps: []const [4]i32 = if (dither_mode == 0) FS_TAPS[0..] else ATKINSON_TAPS[0..];
    const serp = serpentine != 0;
    const side_i64: i64 = @intCast(side);

    var y: usize = 0;
    while (y < side) : (y += 1) {
        const l2r = !serp or (y % 2 == 0);
        var xi: usize = 0;
        while (xi < side) : (xi += 1) {
            const x: usize = if (l2r) xi else side - 1 - xi;
            const idx = y * side + x;
            const hl: i64 = buf[idx * 3 + 0];
            const ha: i64 = buf[idx * 3 + 1];
            const hb: i64 = buf[idx * 3 + 2];
            const best_k = nearestCentroidQ16(centroids_q16, kk, hl, ha, hb);
            out_indices[idx] = @intCast(best_k);
            const el = hl - centroids_q16[best_k * 3 + 0];
            const ea = ha - centroids_q16[best_k * 3 + 1];
            const eb = hb - centroids_q16[best_k * 3 + 2];
            for (taps) |tap| {
                const dx: i64 = if (l2r) tap[0] else -tap[0];
                const nx: i64 = @as(i64, @intCast(x)) + dx;
                const ny: i64 = @as(i64, @intCast(y)) + tap[1];
                if (nx < 0 or nx >= side_i64 or ny < 0 or ny >= side_i64) continue;
                const nidx: usize = @intCast(ny * side_i64 + nx);
                const num: i64 = tap[2];
                const den: i64 = tap[3];
                buf[nidx * 3 + 0] += @intCast(@divTrunc(el * num, den));
                buf[nidx * 3 + 1] += @intCast(@divTrunc(ea * num, den));
                buf[nidx * 3 + 2] += @intCast(@divTrunc(eb * num, den));
            }
        }
    }
    s4log("dither    p={d} k={d} mode={d} serp={d} (error-diffusion)", .{ p, k, dither_mode, serpentine });
    return RC_OK;
}

// Exact integer floor square root (binary search) — mirrors
// SixFour.Spec.SignificanceFixed.isqrtInt. hi = 2^20 keeps mid² ≤ 2^40 in i64.
fn isqrt64(n: i64) i64 {
    if (n <= 0) return 0;
    var lo: i64 = 0;
    var hi: i64 = 1 << 20;
    while (lo < hi) {
        const mid = @divTrunc(lo + hi + 1, 2);
        if (mid * mid <= n) {
            lo = mid;
        } else {
            hi = mid - 1;
        }
    }
    return lo;
}

/// Significance split-fill: rebalance indices so every slot has ≥ min_population
/// pixels; optionally emit per-slot cell stats (mean3, std3, count) into
/// out_cell_stats (k × 7 i32) — pass null to skip. Mirrors the app's
/// SignificantSplitFill.rescue (+ cells) and SixFour.Spec.SignificanceFixed
/// byte-for-byte: nearest-to-centroid donor, strict-< (lowest index) tie-break,
/// donor must have count > min_population. k ≤ 256 (stack-resident accumulators).
pub export fn s4_significance_fill(
    oklab_q16: [*c]const i32,
    centroids_q16: [*c]const i32,
    p: i32,
    k: i32,
    min_population: i32,
    io_indices: [*c]u8,
    out_cell_stats: [*c]i32,
    scratch: ?*anyopaque,
    scratch_cap: usize,
) i32 {
    _ = scratch;
    _ = scratch_cap;
    if (oklab_q16 == null or centroids_q16 == null or io_indices == null) return RC_NULL_PTR;
    if (p <= 0 or k <= 0 or k > 256 or min_population < 0) return RC_BAD_SHAPE;
    const pp: usize = @intCast(p);
    const kk: usize = @intCast(k);
    const nmin: i32 = min_population;
    if (@as(i64, p) < @as(i64, nmin) * @as(i64, k)) return RC_INFEASIBLE_SIGNIFICANCE;

    var counts: [256]i32 = undefined;
    @memset(counts[0..kk], 0);
    var i: usize = 0;
    while (i < pp) : (i += 1) counts[io_indices[i]] += 1;

    var all_ok = true;
    {
        var t: usize = 0;
        while (t < kk) : (t += 1) {
            if (counts[t] < nmin) {
                all_ok = false;
                break;
            }
        }
    }

    var moves: i32 = 0;
    if (!all_ok) {
        var slot: usize = 0;
        while (slot < kk) : (slot += 1) {
            if (counts[slot] >= nmin) continue;
            const tl: i64 = centroids_q16[slot * 3 + 0];
            const ta: i64 = centroids_q16[slot * 3 + 1];
            const tb: i64 = centroids_q16[slot * 3 + 2];
            while (counts[slot] < nmin) {
                var best_i: i64 = -1;
                var best_d: i64 = std.math.maxInt(i64);
                var j: usize = 0;
                while (j < pp) : (j += 1) {
                    const s: usize = io_indices[j];
                    if (s == slot or counts[s] <= nmin) continue;
                    const d = distSqCentroid(oklab_q16, j, tl, ta, tb);
                    if (d < best_d) {
                        best_d = d;
                        best_i = @intCast(j);
                    }
                }
                if (best_i < 0) break; // infeasible (unreachable when p ≥ nmin·k)
                const bi: usize = @intCast(best_i);
                counts[io_indices[bi]] -= 1;
                io_indices[bi] = @intCast(slot);
                counts[slot] += 1;
                moves += 1;
            }
        }
    }
    s4log("signif    p={d} k={d} minPop={d} rebalanced={d} px", .{ p, k, min_population, moves });

    if (out_cell_stats != null) {
        var sum_l: [256]i64 = undefined;
        var sum_a: [256]i64 = undefined;
        var sum_b: [256]i64 = undefined;
        @memset(sum_l[0..kk], 0);
        @memset(sum_a[0..kk], 0);
        @memset(sum_b[0..kk], 0);
        var ci: usize = 0;
        while (ci < pp) : (ci += 1) {
            const t: usize = io_indices[ci];
            sum_l[t] += oklab_q16[ci * 3 + 0];
            sum_a[t] += oklab_q16[ci * 3 + 1];
            sum_b[t] += oklab_q16[ci * 3 + 2];
        }
        var mean_l: [256]i64 = undefined;
        var mean_a: [256]i64 = undefined;
        var mean_b: [256]i64 = undefined;
        var t: usize = 0;
        while (t < kk) : (t += 1) {
            if (counts[t] > 0) {
                const n: i64 = counts[t];
                mean_l[t] = @divTrunc(sum_l[t], n);
                mean_a[t] = @divTrunc(sum_a[t], n);
                mean_b[t] = @divTrunc(sum_b[t], n);
            } else {
                mean_l[t] = centroids_q16[t * 3 + 0];
                mean_a[t] = centroids_q16[t * 3 + 1];
                mean_b[t] = centroids_q16[t * 3 + 2];
            }
        }
        var var_l: [256]i64 = undefined;
        var var_a: [256]i64 = undefined;
        var var_b: [256]i64 = undefined;
        @memset(var_l[0..kk], 0);
        @memset(var_a[0..kk], 0);
        @memset(var_b[0..kk], 0);
        var vi: usize = 0;
        while (vi < pp) : (vi += 1) {
            const t2: usize = io_indices[vi];
            const dl = @as(i64, oklab_q16[vi * 3 + 0]) - mean_l[t2];
            const da = @as(i64, oklab_q16[vi * 3 + 1]) - mean_a[t2];
            const db = @as(i64, oklab_q16[vi * 3 + 2]) - mean_b[t2];
            var_l[t2] += dl * dl;
            var_a[t2] += da * da;
            var_b[t2] += db * db;
        }
        var ti: usize = 0;
        while (ti < kk) : (ti += 1) {
            out_cell_stats[ti * 7 + 0] = @intCast(mean_l[ti]);
            out_cell_stats[ti * 7 + 1] = @intCast(mean_a[ti]);
            out_cell_stats[ti * 7 + 2] = @intCast(mean_b[ti]);
            if (counts[ti] > 0) {
                const n: i64 = counts[ti];
                out_cell_stats[ti * 7 + 3] = @intCast(isqrt64(@divTrunc(var_l[ti], n)));
                out_cell_stats[ti * 7 + 4] = @intCast(isqrt64(@divTrunc(var_a[ti], n)));
                out_cell_stats[ti * 7 + 5] = @intCast(isqrt64(@divTrunc(var_b[ti], n)));
            } else {
                out_cell_stats[ti * 7 + 3] = 0;
                out_cell_stats[ti * 7 + 4] = 0;
                out_cell_stats[ti * 7 + 5] = 0;
            }
            out_cell_stats[ti * 7 + 6] = counts[ti];
        }
    }

    return RC_OK;
}

// Inverse matrices, Q16 — SAME integer literals as SixFour.Spec.ColorFixed.
// M2⁻¹ (OKLab→l'm's'): the a,b coefficients added to L.
const M2I_LA: i64 = 25974;
const M2I_LB: i64 = 14143;
const M2I_MA: i64 = -6918;
const M2I_MB: i64 = -4185;
const M2I_SA: i64 = -5864;
const M2I_SB: i64 = -84639;
// M1⁻¹ (LMS→linear sRGB), row-major.
const M1INV_Q16 = [9]i64{ 267173, -216774, 15137, -83128, 171033, -22369, -275, -46099, 111910 };

// The shared inverse-gamma LUT, generated by `spec-fixtures` from the Double
// linearToSRGB and embedded byte-for-byte. Index = clamped Q16 linear ∈ [0,65536];
// value = round(255·sRGB). Deterministic on every device — no runtime pow.
const GAMMA_LUT: []const u8 = @embedFile("gamma_lut.bin");
comptime {
    if (GAMMA_LUT.len != 65537) @compileError("gamma_lut.bin must be 65537 bytes; run `cd spec && cabal run spec-fixtures`");
}

inline fn cubeQ16(v: i64) i64 {
    return @divTrunc(v * v * v, 4294967296); // (v/2^16)^3 in Q16 = v^3 / 2^32
}

inline fn gammaByte(lin: i64) u8 {
    const idx: i64 = if (lin < 0) 0 else if (lin > 65536) 65536 else lin;
    return GAMMA_LUT[@intCast(idx)];
}

/// OKLab Q16 centroids → sRGB8 palette: M2⁻¹ matmul, exact integer cube, M1⁻¹
/// matmul, clamp, gamma LUT. Mirrors SixFour.Spec.ColorFixed.oklabToSrgb8Q16
/// byte-for-byte. `scratch` is unused (pure per-entry map).
pub export fn s4_palette_oklab_to_srgb8(
    centroids_q16: [*c]const i32,
    k: i32,
    out_rgb: [*c]u8,
    scratch: ?*anyopaque,
    scratch_cap: usize,
) i32 {
    _ = scratch;
    _ = scratch_cap;
    if (centroids_q16 == null or out_rgb == null) return RC_NULL_PTR;
    if (k <= 0) return RC_BAD_SHAPE;
    const q16: i64 = Q16_ONE;
    const n: usize = @intCast(k);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const big_l: i64 = centroids_q16[i * 3 + 0];
        const a: i64 = centroids_q16[i * 3 + 1];
        const b: i64 = centroids_q16[i * 3 + 2];
        const l_ = @divTrunc(q16 * big_l + M2I_LA * a + M2I_LB * b, q16);
        const m_ = @divTrunc(q16 * big_l + M2I_MA * a + M2I_MB * b, q16);
        const s_ = @divTrunc(q16 * big_l + M2I_SA * a + M2I_SB * b, q16);
        const l = cubeQ16(l_);
        const m = cubeQ16(m_);
        const s = cubeQ16(s_);
        const r = @divTrunc(M1INV_Q16[0] * l + M1INV_Q16[1] * m + M1INV_Q16[2] * s, q16);
        const g = @divTrunc(M1INV_Q16[3] * l + M1INV_Q16[4] * m + M1INV_Q16[5] * s, q16);
        const bl = @divTrunc(M1INV_Q16[6] * l + M1INV_Q16[7] * m + M1INV_Q16[8] * s, q16);
        out_rgb[i * 3 + 0] = gammaByte(r);
        out_rgb[i * 3 + 1] = gammaByte(g);
        out_rgb[i * 3 + 2] = gammaByte(bl);
    }
    s4log("palette   k={d} OKLab->sRGB8 (gamma LUT)", .{k});
    return RC_OK;
}

// ── GIF89a + LZW (byte-faithful port of GIFEncoder.swift) ─────────────────────

// Open-addressed LZW dictionary, keyed by (prefix_code<<8 | byte). Power-of-two
// slot count; holds ≤ ~3837 live entries (load < 0.5). Stack-resident (≤48 KB).
const LZW_SLOTS: usize = 8192;
const LZW_EMPTY: u32 = 0xFFFFFFFF;

inline fn lzwHash(key: u32) usize {
    return @intCast((key *% 2654435761) >> (32 - 13)); // top 13 bits → [0, 8191]
}

// Append-only writer over a caller-owned buffer; flags (never overruns) overflow.
const GifWriter = struct {
    out: [*c]u8,
    cap: usize,
    pos: usize,
    overflow: bool,

    fn byte(self: *GifWriter, b: u8) void {
        if (self.pos >= self.cap) {
            self.overflow = true;
            return;
        }
        self.out[self.pos] = b;
        self.pos += 1;
    }
    fn bytes(self: *GifWriter, s: []const u8) void {
        for (s) |b| self.byte(b);
    }
    fn u16le(self: *GifWriter, v: u16) void {
        self.byte(@intCast(v & 0xFF));
        self.byte(@intCast((v >> 8) & 0xFF));
    }
};

// LZW bit/sub-block sink — LSB-first codes packed into ≤255-byte sub-blocks,
// each length-prefixed. Mirrors GIFEncoder.lzwEncode's outputCode/flushSubBlock.
const BitSink = struct {
    w: *GifWriter,
    code_size: u32,
    buf: u32 = 0,
    cnt: u32 = 0,
    sub: [255]u8 = undefined,
    sub_len: usize = 0,

    fn flushSub(self: *BitSink) void {
        if (self.sub_len != 0) {
            self.w.byte(@intCast(self.sub_len));
            self.w.bytes(self.sub[0..self.sub_len]);
            self.sub_len = 0;
        }
    }
    fn pushByte(self: *BitSink, b: u8) void {
        self.sub[self.sub_len] = b;
        self.sub_len += 1;
        if (self.sub_len == 255) self.flushSub();
    }
    fn emit(self: *BitSink, code: u32) void {
        self.buf |= code << @as(u5, @intCast(self.cnt)); // cnt < 8 at every entry
        self.cnt += self.code_size;
        while (self.cnt >= 8) {
            self.pushByte(@intCast(self.buf & 0xFF));
            self.buf >>= 8;
            self.cnt -= 8;
        }
    }
    fn finish(self: *BitSink) void {
        if (self.cnt > 0) self.pushByte(@intCast(self.buf & 0xFF));
        self.flushSub();
    }
};

// LZW-compress one frame's indices into the GIF image-data stream: the
// minCodeSize byte, length-prefixed sub-blocks, then the 0x00 terminator.
fn lzwEncodeFrame(w: *GifWriter, pixels: []const u8, k: i32) void {
    var mcs: u32 = 2;
    while ((@as(u32, 1) << @as(u5, @intCast(mcs))) < @as(u32, @intCast(k))) mcs += 1;
    w.byte(@intCast(mcs));

    const clear_code: u32 = @as(u32, 1) << @as(u5, @intCast(mcs));
    const end_code: u32 = clear_code + 1;
    const max_code: u32 = 4095;

    var keys: [LZW_SLOTS]u32 = undefined;
    var vals: [LZW_SLOTS]u16 = undefined;
    @memset(keys[0..], LZW_EMPTY);

    var sink = BitSink{ .w = w, .code_size = mcs + 1 };
    var next_code: u32 = end_code + 1;

    sink.emit(clear_code);
    if (pixels.len == 0) {
        sink.emit(end_code);
        sink.finish();
        w.byte(0x00);
        return;
    }

    var current: u32 = pixels[0];
    var i: usize = 1;
    while (i < pixels.len) : (i += 1) {
        const px: u32 = pixels[i];
        const key: u32 = (current << 8) | px;
        var slot = lzwHash(key);
        var found: ?u16 = null;
        while (keys[slot] != LZW_EMPTY) {
            if (keys[slot] == key) {
                found = vals[slot];
                break;
            }
            slot = (slot + 1) & (LZW_SLOTS - 1);
        }
        if (found) |v| {
            current = v;
        } else {
            sink.emit(current);
            if (next_code <= max_code) {
                keys[slot] = key; // `slot` is the empty slot the probe stopped on
                vals[slot] = @intCast(next_code);
                next_code += 1;
                if (next_code > (@as(u32, 1) << @as(u5, @intCast(sink.code_size))) and sink.code_size < 12) {
                    sink.code_size += 1;
                }
            } else {
                sink.emit(clear_code); // at the CURRENT (pre-reset) code size
                @memset(keys[0..], LZW_EMPTY);
                sink.code_size = mcs + 1;
                next_code = end_code + 1;
            }
            current = px;
        }
    }
    sink.emit(current);
    sink.emit(end_code);
    sink.finish();
    w.byte(0x00);
}

/// LZW + GIF89a serialisation from per-frame indices + sRGB8 palettes. Mirrors
/// GIFEncoder.swift / SixFour.Gen.GifWire byte-for-byte. `k` must be a power of
/// two ≤ 256. Writes the GIF length to `out_len`.
pub export fn s4_gif_assemble(
    indices: [*c]const u8,
    palettes_rgb: [*c]const u8,
    frame_count: i32,
    side: i32,
    k: i32,
    frame_delay_cs: u16,
    comment: [*c]const u8,
    comment_len: i32,
    out_gif: [*c]u8,
    out_cap: usize,
    out_len: [*c]usize,
) i32 {
    if (indices == null or palettes_rgb == null or out_gif == null or out_len == null) return RC_NULL_PTR;
    if (frame_count <= 0 or side <= 0 or k <= 0 or k > 256) return RC_BAD_SHAPE;
    if ((k & (k - 1)) != 0) return RC_BAD_SHAPE; // power of two
    const fc: usize = @intCast(frame_count);
    const sidez: usize = @intCast(side);
    const p: usize = sidez * sidez;
    const kk: usize = @intCast(k);

    var w = GifWriter{ .out = out_gif, .cap = out_cap, .pos = 0, .overflow = false };

    w.bytes(&[_]u8{ 0x47, 0x49, 0x46, 0x38, 0x39, 0x61 }); // "GIF89a"
    w.u16le(@intCast(side)); // logical screen width
    w.u16le(@intCast(side)); // height
    w.byte(0x70); // packed: no GCT, colour-res 7
    w.byte(0x00); // background colour index
    w.byte(0x00); // pixel aspect ratio
    // NETSCAPE2.0 loop-forever block
    w.bytes(&[_]u8{ 0x21, 0xFF, 0x0B, 0x4E, 0x45, 0x54, 0x53, 0x43, 0x41, 0x50, 0x45, 0x32, 0x2E, 0x30, 0x03, 0x01, 0x00, 0x00, 0x00 });

    if (comment != null and comment_len > 0) {
        w.bytes(&[_]u8{ 0x21, 0xFE });
        const clen: usize = @intCast(comment_len);
        var off: usize = 0;
        while (off < clen) {
            const chunk = @min(@as(usize, 255), clen - off);
            w.byte(@intCast(chunk));
            var j: usize = 0;
            while (j < chunk) : (j += 1) w.byte(comment[off + j]);
            off += chunk;
        }
        w.byte(0x00);
    }

    // Image-descriptor LCT-size field: 2^(field+1) == k.
    var field: u32 = 0;
    while ((@as(u32, 1) << @as(u5, @intCast(field + 1))) < @as(u32, @intCast(k))) field += 1;
    const packed_desc: u8 = 0x80 | @as(u8, @intCast(field));

    var f: usize = 0;
    while (f < fc) : (f += 1) {
        // Graphic control extension (disposal 1, delay).
        w.bytes(&[_]u8{ 0x21, 0xF9, 0x04, 0x04 });
        w.u16le(frame_delay_cs);
        w.byte(0x00);
        w.byte(0x00);
        // Image descriptor with LCT.
        w.byte(0x2C);
        w.u16le(0);
        w.u16le(0);
        w.u16le(@intCast(side));
        w.u16le(@intCast(side));
        w.byte(packed_desc);
        // Local colour table (k × RGB8) — bulk copy (same overflow semantics as
        // GifWriter.byte: write nothing + flag overflow if it wouldn't fit).
        const lct_len = kk * 3;
        if (w.pos + lct_len > w.cap) {
            w.overflow = true;
        } else {
            @memcpy(w.out[w.pos .. w.pos + lct_len], palettes_rgb[f * lct_len .. f * lct_len + lct_len]);
            w.pos += lct_len;
        }
        // LZW image data.
        lzwEncodeFrame(&w, indices[f * p .. f * p + p], k);
    }

    w.byte(0x3B); // trailer

    if (w.overflow) return RC_OUTPUT_TOO_SMALL;
    out_len[0] = w.pos;
    s4log("gif       frames={d} side={d} k={d} -> {d} bytes (LZW)", .{ frame_count, side, k, w.pos });
    return RC_OK;
}

// ── sRGB8 → OKLab Q16 (the decode-side inverse of s4_palette_oklab_to_srgb8) ──
// Embedded sRGB→linear LUT: 256 little-endian i32 of round(srgbToLinear(b/255)·2^16),
// emitted by spec/app/Fixtures.hs from the SAME SixFour.Spec.Color.srgbToLinear, so
// Zig and Haskell agree byte-for-byte. Inverse of the forward gamma path.
const SRGB_LIN_LUT: []const u8 = @embedFile("srgb_linear_lut.bin");
comptime {
    if (SRGB_LIN_LUT.len != 1024) @compileError("srgb_linear_lut.bin must be 1024 bytes (256·i32); run `cd spec && cabal run spec-fixtures`");
}
inline fn srgbLinLut(b: u8) i32 {
    return std.mem.readInt(i32, SRGB_LIN_LUT[@as(usize, b) * 4 ..][0..4], .little);
}

/// k sRGB8 triples → k OKLab Q16 triples. Decodes a GIF colour table back into the
/// OKLab the quantiser/token builder consume. Lossy inverse (OKLab→sRGB8 already
/// rounded): exact at the byte level only. `out` may alias `rgb`-derived storage.
pub export fn s4_srgb8_to_oklab_q16(rgb: [*c]const u8, k: i32, out_oklab_q16: [*c]i32) i32 {
    if (rgb == null or out_oklab_q16 == null) return RC_NULL_PTR;
    if (k <= 0) return RC_BAD_SHAPE;
    const n: usize = @intCast(k);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        out_oklab_q16[i * 3 + 0] = srgbLinLut(rgb[i * 3 + 0]);
        out_oklab_q16[i * 3 + 1] = srgbLinLut(rgb[i * 3 + 1]);
        out_oklab_q16[i * 3 + 2] = srgbLinLut(rgb[i * 3 + 2]);
    }
    // In-place linear→OKLab: s4_linear_to_oklab_q16 reads each triple before writing it.
    return s4_linear_to_oklab_q16(out_oklab_q16, k, out_oklab_q16);
}

// ── GIF89a decoder — byte-faithful port of SixFour.Gen.GifDecode (the inverse of
// s4_gif_assemble). Parses the app dialect (no GCT, per-frame LCT, NETSCAPE loop,
// optional Comment ext, disposal-1 frames) + the standard variable-width LZW. ──

/// Working bytes s4_gif_decode needs: one frame's de-framed payload (≤ gif_len) +
/// the 4096-entry LZW dictionary (prefix i32 + suffix u8 + first u8) + a 4096-byte
/// reconstruction stack + slack. 0 on gif_len == 0.
pub export fn s4_gif_decode_scratch_bytes(gif_len: usize) usize {
    if (gif_len == 0) return 0;
    return gif_len + 4096 * @sizeOf(i32) + 4096 + 4096 + 4096 + 1024;
}

const GifReader = struct {
    g: []const u8,
    pos: usize = 0,
    fn byte(self: *GifReader) ?u8 {
        if (self.pos >= self.g.len) return null;
        const b = self.g[self.pos];
        self.pos += 1;
        return b;
    }
    fn u16le(self: *GifReader) ?u16 {
        if (self.pos + 2 > self.g.len) return null;
        const v = @as(u16, self.g[self.pos]) | (@as(u16, self.g[self.pos + 1]) << 8);
        self.pos += 2;
        return v;
    }
    fn skip(self: *GifReader, n: usize) bool {
        if (self.pos + n > self.g.len) return false;
        self.pos += n;
        return true;
    }
};

// De-frame length-prefixed sub-blocks into `payload`; returns payload length or null.
fn gifReadSubBlocks(r: *GifReader, payload: []u8) ?usize {
    var n: usize = 0;
    while (true) {
        const len = r.byte() orelse return null;
        if (len == 0) return n;
        const l: usize = len;
        if (r.pos + l > r.g.len or n + l > payload.len) return null;
        @memcpy(payload[n .. n + l], r.g[r.pos .. r.pos + l]);
        n += l;
        r.pos += l;
    }
}

// Read one `size`-bit code, LSB-first (bit j of the code = stream bit pos+j).
fn gifReadCode(payload: []const u8, total_bits: usize, bitpos: *usize, size: u5) ?i32 {
    if (bitpos.* + size > total_bits) return null;
    var code: i32 = 0;
    var j: usize = 0;
    while (j < size) : (j += 1) {
        const i = bitpos.* + j;
        const bit: i32 = (payload[i >> 3] >> @as(u3, @intCast(i & 7))) & 1;
        code |= bit << @as(u5, @intCast(j));
    }
    bitpos.* += size;
    return code;
}

// Emit code's byte sequence (walk prefix chain into `emit`, output reversed). false on overflow.
fn gifEmit(code: i32, prefix: []const i32, suffix: []const u8, emit: []u8, out: []u8, out_n: *usize) bool {
    var n: usize = 0;
    var k: i32 = code;
    while (prefix[@intCast(k)] != -1) {
        if (n >= emit.len) return false;
        emit[n] = suffix[@intCast(k)];
        n += 1;
        k = prefix[@intCast(k)];
    }
    if (n >= emit.len or out_n.* + n + 1 > out.len) return false;
    emit[n] = suffix[@intCast(k)]; // root literal
    n += 1;
    var t: usize = 0;
    while (t < n) : (t += 1) out[out_n.* + t] = emit[n - 1 - t];
    out_n.* += n;
    return true;
}

// Decode one frame's LZW payload into `out`; returns pixel count or null on malformed.
fn gifLzwDecode(payload: []const u8, mcs: u5, prefix: []i32, suffix: []u8, first: []u8, emit: []u8, out: []u8) ?usize {
    const clear_code: i32 = @as(i32, 1) << mcs;
    const end_code: i32 = clear_code + 1;
    const total_bits = payload.len * 8;
    var bitpos: usize = 0;
    var out_n: usize = 0;

    // base table: literals 0..clear_code-1
    var c: i32 = 0;
    while (c < clear_code) : (c += 1) {
        prefix[@intCast(c)] = -1;
        suffix[@intCast(c)] = @intCast(c);
        first[@intCast(c)] = @intCast(c);
    }

    var size: u5 = mcs + 1;
    var code = gifReadCode(payload, total_bits, &bitpos, size) orelse return out_n;
    if (code == clear_code)
        code = gifReadCode(payload, total_bits, &bitpos, size) orelse return out_n;
    if (code == end_code) return out_n;
    if (!gifEmit(code, prefix, suffix, emit, out, &out_n)) return null;
    var prev_code: i32 = code;
    var next: i32 = end_code + 1;

    while (true) {
        const cd = gifReadCode(payload, total_bits, &bitpos, size) orelse break;
        if (cd == end_code) break;
        if (cd == clear_code) {
            size = mcs + 1;
            const lit = gifReadCode(payload, total_bits, &bitpos, size) orelse break;
            if (lit == end_code) break;
            if (!gifEmit(lit, prefix, suffix, emit, out, &out_n)) return null;
            prev_code = lit;
            next = end_code + 1;
            continue;
        }
        var head: u8 = undefined;
        if (cd < next) {
            if (!gifEmit(cd, prefix, suffix, emit, out, &out_n)) return null;
            head = first[@intCast(cd)];
        } else { // KwKwK: cd == next, entry = prevEntry ++ [head prevEntry]
            head = first[@intCast(prev_code)];
            if (!gifEmit(prev_code, prefix, suffix, emit, out, &out_n)) return null;
            if (out_n >= out.len) return null;
            out[out_n] = head;
            out_n += 1;
        }
        if (next < 4096) {
            prefix[@intCast(next)] = prev_code;
            suffix[@intCast(next)] = head;
            first[@intCast(next)] = first[@intCast(prev_code)];
        }
        next += 1;
        if (next == (@as(i32, 1) << size) and size < 12) size += 1;
        prev_code = cd;
    }
    return out_n;
}

/// Decode a GIF89a (the app dialect) into per-frame indices + sRGB8 palettes.
/// Pass null `out_indices`/`out_palettes_rgb` to SHAPE-PROBE: fills only
/// out_frame_count/out_side/out_k and returns RC_OK without writing pixels (so the
/// caller can size the buffers). Otherwise `out_indices` is frame_count·side·side u8
/// and `out_palettes_rgb` is frame_count·k·3 u8. `scratch` ≥ s4_gif_decode_scratch_bytes.
pub export fn s4_gif_decode(
    gif: [*c]const u8,
    gif_len: usize,
    out_indices: [*c]u8,
    out_palettes_rgb: [*c]u8,
    out_frame_count: [*c]i32,
    out_side: [*c]i32,
    out_k: [*c]i32,
    scratch: ?*anyopaque,
    scratch_cap: usize,
) i32 {
    if (gif == null or out_frame_count == null or out_side == null or out_k == null) return RC_NULL_PTR;
    if (gif_len < 14) return RC_BAD_SHAPE;
    const probe = (out_indices == null or out_palettes_rgb == null);

    var r = GifReader{ .g = gif[0..gif_len] };
    // header "GIF89a"
    if (!std.mem.eql(u8, r.g[0..6], &[_]u8{ 0x47, 0x49, 0x46, 0x38, 0x39, 0x61 })) return RC_BAD_SHAPE;
    r.pos = 6;
    _ = r.u16le() orelse return RC_BAD_SHAPE; // canvas w
    _ = r.u16le() orelse return RC_BAD_SHAPE; // canvas h
    const lsd_packed = r.byte() orelse return RC_BAD_SHAPE;
    _ = r.byte() orelse return RC_BAD_SHAPE; // bg
    _ = r.byte() orelse return RC_BAD_SHAPE; // aspect
    if ((lsd_packed & 0x80) != 0) { // skip a Global Colour Table (app never writes one)
        const gct = 3 * (@as(usize, 1) << @as(u6, @intCast((lsd_packed & 0x07) + 1)));
        if (!r.skip(gct)) return RC_BAD_SHAPE;
    }

    // scratch layout (full decode only)
    var payload: []u8 = &.{};
    var prefix: []i32 = &.{};
    var suffix: []u8 = &.{};
    var first: []u8 = &.{};
    var emit: []u8 = &.{};
    if (!probe) {
        const need = s4_gif_decode_scratch_bytes(gif_len);
        if (scratch == null or scratch_cap < need) return RC_SCRATCH_TOO_SMALL;
        const base: [*]u8 = @ptrCast(scratch.?);
        var off: usize = 0;
        prefix = @as([*]i32, @ptrCast(@alignCast(base + off)))[0..4096];
        off += 4096 * @sizeOf(i32);
        suffix = base[off .. off + 4096];
        off += 4096;
        first = base[off .. off + 4096];
        off += 4096;
        emit = base[off .. off + 4096];
        off += 4096;
        payload = base[off .. off + gif_len];
    }

    var frame_count: i32 = 0;
    var side: i32 = 0;
    var k: i32 = 0;

    while (true) {
        const tag = r.byte() orelse return RC_BAD_SHAPE;
        if (tag == 0x3B) break; // trailer
        if (tag == 0x21) { // extension: label + sub-blocks (we skip the payload)
            _ = r.byte() orelse return RC_BAD_SHAPE; // label
            while (true) {
                const len = r.byte() orelse return RC_BAD_SHAPE;
                if (len == 0) break;
                if (!r.skip(len)) return RC_BAD_SHAPE;
            }
            continue;
        }
        if (tag != 0x2C) return RC_BAD_SHAPE; // unknown block
        // image descriptor: left,top,iw,ih (u16) + packed
        _ = r.u16le() orelse return RC_BAD_SHAPE;
        _ = r.u16le() orelse return RC_BAD_SHAPE;
        const iw = r.u16le() orelse return RC_BAD_SHAPE;
        const ih = r.u16le() orelse return RC_BAD_SHAPE;
        const img_packed = r.byte() orelse return RC_BAD_SHAPE;
        if ((img_packed & 0x80) == 0) return RC_BAD_SHAPE; // app always writes an LCT
        const lct_size: usize = @as(usize, 1) << @as(u6, @intCast((img_packed & 0x07) + 1));

        if (frame_count == 0) {
            side = @intCast(iw);
            k = @intCast(lct_size);
        } else if (iw != side or ih != iw or @as(usize, @intCast(k)) != lct_size) {
            return RC_BAD_SHAPE; // non-uniform frames break the (T,side,k) contract
        }
        if (iw != ih) return RC_BAD_SHAPE; // square frames only

        const f: usize = @intCast(frame_count);
        if (probe) {
            if (!r.skip(lct_size * 3)) return RC_BAD_SHAPE; // skip LCT
            _ = r.byte() orelse return RC_BAD_SHAPE; // minCodeSize
            while (true) { // skip image sub-blocks
                const len = r.byte() orelse return RC_BAD_SHAPE;
                if (len == 0) break;
                if (!r.skip(len)) return RC_BAD_SHAPE;
            }
        } else {
            // copy LCT → out_palettes_rgb[f]
            if (r.pos + lct_size * 3 > r.g.len) return RC_BAD_SHAPE;
            @memcpy(out_palettes_rgb[f * lct_size * 3 .. f * lct_size * 3 + lct_size * 3], r.g[r.pos .. r.pos + lct_size * 3]);
            r.pos += lct_size * 3;
            const mcs_byte = r.byte() orelse return RC_BAD_SHAPE;
            const payload_len = gifReadSubBlocks(&r, payload) orelse return RC_BAD_SHAPE;
            const p: usize = @as(usize, @intCast(iw)) * @as(usize, @intCast(ih));
            const out_frame = out_indices[f * p .. f * p + p];
            const got = gifLzwDecode(payload[0..payload_len], @intCast(mcs_byte), prefix, suffix, first, emit, out_frame) orelse return RC_OUTPUT_TOO_SMALL;
            if (got != p) return RC_BAD_SHAPE; // pixel count must match iw·ih
        }
        frame_count += 1;
    }

    out_frame_count[0] = frame_count;
    out_side[0] = side;
    out_k[0] = k;
    s4log("gif_decode frames={d} side={d} k={d} (probe={d})", .{ frame_count, side, k, @intFromBool(probe) });
    return RC_OK;
}

// ── unit tests: prove the ABI links + the size helpers are sane ───────────────
test "size helpers return sane bounds for the canonical 64×64×256 shape" {
    const bound = s4_gif_encode_burst_bound(FRAME_COUNT, SIDE, K);
    // Must comfortably exceed the raw index payload (64 × 4096 = 262144 bytes).
    try std.testing.expect(bound > 262144);
    // Local colour tables alone are 64 × 768 = 49152 bytes; bound dwarfs them.
    try std.testing.expect(bound > 49152);

    const scratch = s4_burst_scratch_bytes(FRAME_COUNT, SIDE, K);
    // Histogram (32³·10·8 = 2.62 MB) dominates; sanity-floor it.
    try std.testing.expect(scratch > 2_600_000);

    // Degenerate shapes return 0 rather than trapping.
    try std.testing.expectEqual(@as(usize, 0), s4_gif_encode_burst_bound(0, 64, 256));
    try std.testing.expectEqual(@as(usize, 0), s4_burst_scratch_bytes(64, 0, 256));
}

test "linear_to_oklab_q16 reproduces the golden anchors and guards bad args" {
    var out: [3]i32 = undefined;

    var blk = [3]i32{ 0, 0, 0 };
    try std.testing.expectEqual(RC_OK, s4_linear_to_oklab_q16(&blk, 1, &out));
    try std.testing.expectEqualSlices(i32, &[_]i32{ 0, 0, 0 }, &out);

    var wht = [3]i32{ 65536, 65536, 65536 };
    try std.testing.expectEqual(RC_OK, s4_linear_to_oklab_q16(&wht, 1, &out));
    try std.testing.expectEqualSlices(i32, &[_]i32{ 65535, 2, 0 }, &out);

    var red = [3]i32{ 65536, 0, 0 };
    try std.testing.expectEqual(RC_OK, s4_linear_to_oklab_q16(&red, 1, &out));
    try std.testing.expectEqualSlices(i32, &[_]i32{ 41153, 14735, 8248 }, &out);

    try std.testing.expectEqual(RC_NULL_PTR, s4_linear_to_oklab_q16(null, 1, &out));
    try std.testing.expectEqual(RC_BAD_SHAPE, s4_linear_to_oklab_q16(&blk, 0, &out));
}

test "palette_oklab_to_srgb8 maps black→0 and white→255 and guards bad args" {
    var rgb: [3]u8 = undefined;

    var blk = [3]i32{ 0, 0, 0 };
    try std.testing.expectEqual(RC_OK, s4_palette_oklab_to_srgb8(&blk, 1, &rgb, null, 0));
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0, 0, 0 }, &rgb);

    // White OKLab from the forward golden ([65535, 2, 0]) → ~opaque white.
    var wht = [3]i32{ 65535, 2, 0 };
    try std.testing.expectEqual(RC_OK, s4_palette_oklab_to_srgb8(&wht, 1, &rgb, null, 0));
    try std.testing.expect(rgb[0] >= 254 and rgb[1] >= 254 and rgb[2] >= 254);

    try std.testing.expectEqual(RC_NULL_PTR, s4_palette_oklab_to_srgb8(null, 1, &rgb, null, 0));
    try std.testing.expectEqual(RC_BAD_SHAPE, s4_palette_oklab_to_srgb8(&blk, 0, &rgb, null, 0));
}

var test_log_count: usize = 0;
var test_log_last: [256]u8 = undefined;
var test_log_last_len: usize = 0;
fn testLogSink(msg: [*c]const u8, len: usize) callconv(.c) void {
    test_log_count += 1;
    const n = @min(len, test_log_last.len);
    @memcpy(test_log_last[0..n], msg[0..n]);
    test_log_last_len = n;
}

test "log callback fires from a kernel and is silent when unset" {
    var blk = [3]i32{ 0, 0, 0 };
    var out: [3]u8 = undefined;

    // No sink registered → no logging, no formatting.
    test_log_count = 0;
    try std.testing.expectEqual(RC_OK, s4_palette_oklab_to_srgb8(&blk, 1, &out, null, 0));
    try std.testing.expectEqual(@as(usize, 0), test_log_count);

    // Sink registered → the core pushes a line tagged "palette".
    s4_set_log_callback(testLogSink);
    defer s4_set_log_callback(null); // restore for the other tests
    try std.testing.expectEqual(RC_OK, s4_palette_oklab_to_srgb8(&blk, 1, &out, null, 0));
    try std.testing.expect(test_log_count >= 1);
    try std.testing.expect(std.mem.indexOf(u8, test_log_last[0..test_log_last_len], "palette") != null);
}

test "icbrtQ16 floor cube-root invariant on a sweep" {
    var x: i64 = 0;
    while (x <= 131072) : (x += 257) {
        const y = icbrtQ16(x);
        const n = x << 32;
        try std.testing.expect(y * y * y <= n);
        try std.testing.expect((y + 1) * (y + 1) * (y + 1) > n);
    }
}

test "kernel stubs are exported and return NOT_IMPLEMENTED" {
    var out_len: usize = 0;
    try std.testing.expectEqual(RC_NOT_IMPLEMENTED, s4_widen_half_to_q16(null, 0, null));
    try std.testing.expectEqual(RC_NOT_IMPLEMENTED, s4_gif_encode_burst(null, 0, 0, 0, 0, 0, 0, 0, null, 5, null, 0, null, 0, &out_len, null, 0));
}
