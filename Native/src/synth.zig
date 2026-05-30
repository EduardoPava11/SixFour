// SixFour synthetic-burst generator — the TRAINING data engine.
//
// Why this lives in the Zig core: the look-NN trainer (trainer/) needs labeled
// 64-frame bursts, but trainer/data/ is empty and on-device capture is offline.
// `s4_synth_burst` procedurally generates an OKLab Q16 burst that we then feed
// through the SAME deterministic kernels the device runs (s4_quantize_frame →
// s4_palette_oklab_to_srgb8 → s4_gif_assemble). So the per-frame palettes the
// trainer learns from are produced byte-identically to production — no
// train/deploy skew, and unlimited reproducible data from a seed.
//
// This is the ONE synthesized (not captured) surface in the pipeline. It is
// Mac-side training tooling; the device never runs it. The trainer's data loader
// is structured so dropping real captures into trainer/data/ is a one-line swap.
//
// Determinism: integer value-noise only (splitmix64 PRNG + integer bilinear
// upsample of a coarse control lattice + integer grain). No floats, no trig —
// same seed ⇒ same bytes, on any host. Output is interleaved OKLab Q16 triplets
// (the s4_quantize_frame input format), L∈[0,1]→[0,65536], a,b∈[-0.5,0.5]→[±32768].

const std = @import("std");
const kernels = @import("kernels.zig");

const Q16: i64 = kernels.Q16_ONE; // 65536
const RC_OK = kernels.RC_OK;
const RC_NULL_PTR = kernels.RC_NULL_PTR;
const RC_BAD_SHAPE = kernels.RC_BAD_SHAPE;

// Synthesis modes (mirror sixfour_native.h S4_SYNTH_*).
pub const SYNTH_COLOR: i32 = 0; // full OKLab burst (L,a,b all vary)
pub const SYNTH_GRAYSCALE: i32 = 1; // a=b=0 exactly — Milestone L training data

// Coarse control lattice resolution. A GRID×GRID set of OKLab anchors is bilinearly
// upsampled to side×side, giving smooth spatial gradients/blobs (not white noise).
const GRID: usize = 4;

// Default anchor ranges (Q16) the caller (zig_native.py) passes when it wants the
// canonical span. L_MIN..L_MAX is the default grey dynamic range; CHROMA the default
// chroma deviation bound. Now caller-controlled: L SETS the dynamic range.
pub const L_MIN: i32 = 5243; // ≈0.08
pub const L_MAX: i32 = 60293; // ≈0.92
pub const CHROMA: i32 = 18350; // ≈0.28 → a,b ∈ [-0.28, 0.28]

// ── deterministic PRNG ───────────────────────────────────────────────────────
inline fn splitmix64(state: *u64) u64 {
    state.* +%= 0x9E3779B97F4A7C15;
    var z = state.*;
    z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
    z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
    return z ^ (z >> 31);
}

/// Uniform integer in [lo, hi] (inclusive). hi ≥ lo assumed by callers.
inline fn randRange(state: *u64, lo: i64, hi: i64) i64 {
    const span: u64 = @intCast(hi - lo + 1);
    return lo + @as(i64, @intCast(splitmix64(state) % span));
}

/// Stateless hashed grain in [-grain, grain] from (seed, frame, x, y). Stateless
/// so a pixel's grain is independent of iteration order (reproducible per coord).
/// `grain` is range-proportional (see s4_synth_burst) so a NARROW dynamic range
/// still yields ≥ K distinct quantisable L-levels — load-bearing for significance.
inline fn grainAt(seed: u64, frame: usize, x: usize, y: usize, grain: i64) i64 {
    var h: u64 = seed ^ 0xD1B54A32D192ED03;
    h = (h ^ @as(u64, @intCast(frame))) *% 0x100000001B3;
    h = (h ^ @as(u64, @intCast(x *% 73856093))) *% 0x100000001B3;
    h = (h ^ @as(u64, @intCast(y *% 19349663))) *% 0x100000001B3;
    h ^= h >> 29;
    const span: u64 = @intCast(2 * grain + 1);
    return -grain + @as(i64, @intCast(h % span));
}

// ── integer triangle wave: 0 → 1 → 0 across the burst, in Q16 ──────────────────
fn triangleQ16(frame: usize, frame_count: usize) i64 {
    if (frame_count <= 1) return 0;
    // phase ∈ [0, 2·Q16] over the burst; fold the second half back down.
    const phase = @divTrunc(@as(i64, @intCast(frame)) * 2 * Q16, @as(i64, @intCast(frame_count - 1)));
    return if (phase <= Q16) phase else 2 * Q16 - phase;
}

// ── integer bilinear upsample of one channel of the lattice ────────────────────
// lattice: GRID·GRID i64 (single channel, row-major). Returns the Q16 value at
// pixel (x,y) of a side×side frame.
fn bilerp(lattice: []const i64, x: usize, y: usize, side: usize) i64 {
    const w: i64 = @intCast(side - 1); // denominator; side ≥ 2 enforced by caller
    const g: i64 = @intCast(GRID - 1);

    const gx = @as(i64, @intCast(x)) * g; // ∈ [0, w·g]
    var cx: usize = @intCast(@divTrunc(gx, w));
    var fx = gx - @as(i64, @intCast(cx)) * w; // remainder ∈ [0, w]
    if (cx >= GRID - 1) {
        cx = GRID - 2;
        fx = w;
    }
    const gy = @as(i64, @intCast(y)) * g;
    var cy: usize = @intCast(@divTrunc(gy, w));
    var fy = gy - @as(i64, @intCast(cy)) * w;
    if (cy >= GRID - 1) {
        cy = GRID - 2;
        fy = w;
    }

    const v00 = lattice[cy * GRID + cx];
    const v10 = lattice[cy * GRID + cx + 1];
    const v01 = lattice[(cy + 1) * GRID + cx];
    const v11 = lattice[(cy + 1) * GRID + cx + 1];

    // Bilinear blend with weights in units of w (so divide by w² at the end).
    const top = v00 * (w - fx) + v10 * fx;
    const bot = v01 * (w - fx) + v11 * fx;
    return @divTrunc(top * (w - fy) + bot * fy, w * w);
}

inline fn clampOklab(channel: usize, v: i64) i32 {
    // L ∈ [0, Q16]; a,b ∈ [-Q16/2, Q16/2] (matches the kernels.zig Q16 contract).
    if (channel == 0) return @intCast(std.math.clamp(v, 0, Q16));
    return @intCast(std.math.clamp(v, -@divTrunc(Q16, 2), @divTrunc(Q16, 2)));
}

/// Generate a synthetic OKLab Q16 burst into the caller-owned `out_oklab_q16`
/// buffer (frame_count · side · side · 3 i32, interleaved L,a,b row-major).
///
/// **L SETS THE DYNAMIC RANGE:** lightness anchors are drawn from
/// @[l_min_q16, l_max_q16]@ (the grey-axis dynamic range), and a,b are signed
/// DEVIATIONS from the grey centre in @[-chroma_max_q16, +chroma_max_q16]@.
/// `mode` SYNTH_GRAYSCALE forces a=b=0 exactly (the σ-fixed grey axis). The burst
/// sweeps between two random control lattices via a triangle wave (distinct
/// per-frame palettes, seamless loop). Grain scales with the L range so even a
/// narrow range yields ≥K distinct levels (significance). Deterministic in `seed`.
/// Validates @0 ≤ l_min < l_max ≤ 65536@ and @0 ≤ chroma_max ≤ 32768@.
pub export fn s4_synth_burst(
    seed: u64,
    mode: i32,
    frame_count: i32,
    side: i32,
    l_min_q16: i32,
    l_max_q16: i32,
    chroma_max_q16: i32,
    out_oklab_q16: [*c]i32,
) i32 {
    if (out_oklab_q16 == null) return RC_NULL_PTR;
    if (frame_count <= 0 or side < 2) return RC_BAD_SHAPE;
    if (mode != SYNTH_COLOR and mode != SYNTH_GRAYSCALE) return RC_BAD_SHAPE;
    if (l_min_q16 < 0 or l_max_q16 <= l_min_q16 or l_max_q16 > Q16) return RC_BAD_SHAPE;
    if (chroma_max_q16 < 0 or chroma_max_q16 > @divTrunc(Q16, 2)) return RC_BAD_SHAPE;
    const grayscale = (mode == SYNTH_GRAYSCALE);

    const l_min: i64 = l_min_q16;
    const l_max: i64 = l_max_q16;
    const chroma: i64 = chroma_max_q16;
    // Range-proportional grain (≥1): narrow ranges still get enough micro-variation
    // to yield ≥K distinct quantisable L-levels. ≈ range/128 (matches the old fixed
    // GRAIN=393 at the default ~55050 span).
    const grain: i64 = @max(@as(i64, 1), @divTrunc(l_max - l_min, 128));

    const fc: usize = @intCast(frame_count);
    const sd: usize = @intCast(side);
    const p: usize = sd * sd;

    // Two keyframe lattices (A, B), 3 channels each, drawn from the seed. The burst
    // interpolates A↔B per frame to produce temporal palette drift.
    var state: u64 = seed *% 0x2545F4914F6CDD1D +% 1;
    var latA: [GRID * GRID * 3]i64 = undefined;
    var latB: [GRID * GRID * 3]i64 = undefined;
    var n: usize = 0;
    while (n < GRID * GRID) : (n += 1) {
        latA[n * 3 + 0] = randRange(&state, l_min, l_max);
        latB[n * 3 + 0] = randRange(&state, l_min, l_max);
        if (grayscale) {
            latA[n * 3 + 1] = 0;
            latA[n * 3 + 2] = 0;
            latB[n * 3 + 1] = 0;
            latB[n * 3 + 2] = 0;
        } else {
            latA[n * 3 + 1] = randRange(&state, -chroma, chroma);
            latA[n * 3 + 2] = randRange(&state, -chroma, chroma);
            latB[n * 3 + 1] = randRange(&state, -chroma, chroma);
            latB[n * 3 + 2] = randRange(&state, -chroma, chroma);
        }
    }

    var frame: usize = 0;
    while (frame < fc) : (frame += 1) {
        const t = triangleQ16(frame, fc); // Q16 blend A↔B

        // Per-frame lattice = lerp(A, B, t), split into single-channel views.
        var latL: [GRID * GRID]i64 = undefined;
        var latA_ch: [GRID * GRID]i64 = undefined;
        var latB_ch: [GRID * GRID]i64 = undefined;
        n = 0;
        while (n < GRID * GRID) : (n += 1) {
            latL[n] = latA[n * 3 + 0] + @divTrunc((latB[n * 3 + 0] - latA[n * 3 + 0]) * t, Q16);
            latA_ch[n] = latA[n * 3 + 1] + @divTrunc((latB[n * 3 + 1] - latA[n * 3 + 1]) * t, Q16);
            latB_ch[n] = latA[n * 3 + 2] + @divTrunc((latB[n * 3 + 2] - latA[n * 3 + 2]) * t, Q16);
        }

        const fbase = frame * p * 3;
        var y: usize = 0;
        while (y < sd) : (y += 1) {
            var x: usize = 0;
            while (x < sd) : (x += 1) {
                const idx = fbase + (y * sd + x) * 3;
                const gr = grainAt(seed, frame, x, y, grain);
                out_oklab_q16[idx + 0] = clampOklab(0, bilerp(&latL, x, y, sd) + gr);
                if (grayscale) {
                    out_oklab_q16[idx + 1] = 0; // exact a=0
                    out_oklab_q16[idx + 2] = 0; // exact b=0
                } else {
                    out_oklab_q16[idx + 1] = clampOklab(1, bilerp(&latA_ch, x, y, sd) + gr);
                    out_oklab_q16[idx + 2] = clampOklab(2, bilerp(&latB_ch, x, y, sd) + gr);
                }
            }
        }
    }
    return RC_OK;
}

// ── unit tests ────────────────────────────────────────────────────────────────

test "s4_synth_burst is deterministic in the seed" {
    const fc = 4;
    const side = 8;
    const n = fc * side * side * 3;
    var a: [n]i32 = undefined;
    var b: [n]i32 = undefined;
    try std.testing.expectEqual(RC_OK, s4_synth_burst(12345, SYNTH_COLOR, fc, side, L_MIN, L_MAX, CHROMA, &a));
    try std.testing.expectEqual(RC_OK, s4_synth_burst(12345, SYNTH_COLOR, fc, side, L_MIN, L_MAX, CHROMA, &b));
    try std.testing.expectEqualSlices(i32, &a, &b);
    // A different seed must change the output.
    var c: [n]i32 = undefined;
    try std.testing.expectEqual(RC_OK, s4_synth_burst(12346, SYNTH_COLOR, fc, side, L_MIN, L_MAX, CHROMA, &c));
    try std.testing.expect(!std.mem.eql(i32, &a, &c));
}

test "grayscale mode emits a=b=0 exactly and L in range" {
    const fc = 4;
    const side = 8;
    const p = side * side;
    const n = fc * p * 3;
    var out: [n]i32 = undefined;
    try std.testing.expectEqual(RC_OK, s4_synth_burst(777, SYNTH_GRAYSCALE, fc, side, L_MIN, L_MAX, CHROMA, &out));
    var i: usize = 0;
    while (i < fc * p) : (i += 1) {
        const l = out[i * 3 + 0];
        try std.testing.expect(l >= 0 and l <= kernels.Q16_ONE);
        try std.testing.expectEqual(@as(i32, 0), out[i * 3 + 1]);
        try std.testing.expectEqual(@as(i32, 0), out[i * 3 + 2]);
    }
}

test "frames differ (temporal palette drift) and chroma stays in gamut" {
    const fc = 8;
    const side = 16;
    const p = side * side;
    const n = fc * p * 3;
    const alloc = std.testing.allocator;
    const out = try alloc.alloc(i32, n);
    defer alloc.free(out);
    try std.testing.expectEqual(RC_OK, s4_synth_burst(2024, SYNTH_COLOR, fc, side, L_MIN, L_MAX, CHROMA, out.ptr));

    // Frame 0 and the midpoint frame must differ (the triangle wave moved A→B).
    const f0 = out[0 .. p * 3];
    const fm = out[(fc / 2) * p * 3 .. (fc / 2 + 1) * p * 3];
    try std.testing.expect(!std.mem.eql(i32, f0, fm));

    // a,b within the declared Q16 chroma bound.
    const half = @divTrunc(kernels.Q16_ONE, 2);
    var i: usize = 0;
    while (i < fc * p) : (i += 1) {
        try std.testing.expect(out[i * 3 + 1] >= -half and out[i * 3 + 1] <= half);
        try std.testing.expect(out[i * 3 + 2] >= -half and out[i * 3 + 2] <= half);
    }
}

test "synth → quantize → palette → assemble runs end-to-end (grayscale)" {
    // Proves the synth output is a valid s4_quantize_frame input and the whole
    // grayscale data-gen chain produces a GIF through the real device kernels.
    const fc = 2;
    const side = 8;
    const k = 16;
    const p = side * side;
    const alloc = std.testing.allocator;

    const burst = try alloc.alloc(i32, fc * p * 3);
    defer alloc.free(burst);
    try std.testing.expectEqual(RC_OK, s4_synth_burst(99, SYNTH_GRAYSCALE, fc, side, L_MIN, L_MAX, CHROMA, burst.ptr));

    const need = p * @sizeOf(i64) + 3 * @as(usize, k) * @sizeOf(i64) + @as(usize, k) * @sizeOf(i32);
    const scratch = try alloc.alloc(u8, need);
    defer alloc.free(scratch);

    const indices = try alloc.alloc(u8, fc * p);
    defer alloc.free(indices);
    const palettes = try alloc.alloc(u8, fc * @as(usize, k) * 3);
    defer alloc.free(palettes);
    var centroids: [16 * 3]i32 = undefined;

    var f: usize = 0;
    while (f < fc) : (f += 1) {
        const frame = burst[f * p * 3 .. (f + 1) * p * 3];
        try std.testing.expectEqual(RC_OK, kernels.s4_quantize_frame(
            frame.ptr,
            p,
            k,
            2,
            &centroids,
            indices[f * p ..].ptr,
            scratch.ptr,
            scratch.len,
        ));
        // Grayscale invariant survives quantization: every centroid has a=b=0.
        var j: usize = 0;
        while (j < k) : (j += 1) {
            try std.testing.expectEqual(@as(i32, 0), centroids[j * 3 + 1]);
            try std.testing.expectEqual(@as(i32, 0), centroids[j * 3 + 2]);
        }
        try std.testing.expectEqual(RC_OK, kernels.s4_palette_oklab_to_srgb8(
            &centroids,
            k,
            palettes[f * @as(usize, k) * 3 ..].ptr,
            null,
            0,
        ));
        // Neutral grey ⇒ R=G=B in the emitted sRGB8 table.
        j = 0;
        while (j < k) : (j += 1) {
            const base = f * @as(usize, k) * 3 + j * 3;
            try std.testing.expectEqual(palettes[base + 0], palettes[base + 1]);
            try std.testing.expectEqual(palettes[base + 1], palettes[base + 2]);
        }
    }

    const bound = kernels.s4_gif_encode_burst_bound(fc, side, k);
    const gif = try alloc.alloc(u8, bound);
    defer alloc.free(gif);
    var out_len: usize = 0;
    try std.testing.expectEqual(RC_OK, kernels.s4_gif_assemble(
        indices.ptr,
        palettes.ptr,
        fc,
        side,
        k,
        5,
        null,
        0,
        gif.ptr,
        gif.len,
        &out_len,
    ));
    try std.testing.expect(out_len > 6);
    try std.testing.expectEqualSlices(u8, "GIF89a", gif[0..6]);
}

test "SOLID round-trip: s4_gif_decode(s4_gif_assemble(...)) == (indices, palettes)" {
    // Encode a COLOUR synth burst, decode it back, assert index- and byte-exact
    // identity — the SOLID-GIF contract (round-trip A). k=16 exercises the k<256
    // LCT + minCodeSize path; a colour burst drives LZW dictionary growth.
    const fc = 3;
    const side = 16;
    const k = 16;
    const p = side * side;
    const alloc = std.testing.allocator;

    const burst = try alloc.alloc(i32, fc * p * 3);
    defer alloc.free(burst);
    try std.testing.expectEqual(RC_OK, s4_synth_burst(2718, SYNTH_COLOR, fc, side, L_MIN, L_MAX, CHROMA, burst.ptr));

    const need = p * @sizeOf(i64) + 3 * @as(usize, k) * @sizeOf(i64) + @as(usize, k) * @sizeOf(i32);
    const scratch = try alloc.alloc(u8, need);
    defer alloc.free(scratch);
    const indices = try alloc.alloc(u8, fc * p);
    defer alloc.free(indices);
    const palettes = try alloc.alloc(u8, fc * @as(usize, k) * 3);
    defer alloc.free(palettes);
    var centroids: [16 * 3]i32 = undefined;

    var f: usize = 0;
    while (f < fc) : (f += 1) {
        const frame = burst[f * p * 3 .. (f + 1) * p * 3];
        try std.testing.expectEqual(RC_OK, kernels.s4_quantize_frame(frame.ptr, p, k, 2, &centroids, indices[f * p ..].ptr, scratch.ptr, scratch.len));
        try std.testing.expectEqual(RC_OK, kernels.s4_palette_oklab_to_srgb8(&centroids, k, palettes[f * @as(usize, k) * 3 ..].ptr, null, 0));
    }

    const bound = kernels.s4_gif_encode_burst_bound(fc, side, k);
    const gif = try alloc.alloc(u8, bound);
    defer alloc.free(gif);
    var out_len: usize = 0;
    try std.testing.expectEqual(RC_OK, kernels.s4_gif_assemble(indices.ptr, palettes.ptr, fc, side, k, 5, null, 0, gif.ptr, gif.len, &out_len));

    // Shape probe first (null outputs) → recover (frame_count, side, k).
    var dfc: i32 = 0;
    var dside: i32 = 0;
    var dk: i32 = 0;
    try std.testing.expectEqual(RC_OK, kernels.s4_gif_decode(gif.ptr, out_len, null, null, &dfc, &dside, &dk, null, 0));
    try std.testing.expectEqual(@as(i32, fc), dfc);
    try std.testing.expectEqual(@as(i32, side), dside);
    try std.testing.expectEqual(@as(i32, k), dk);

    // Full decode → assert index-exact + palette-byte-exact identity.
    const dscratch = try alloc.alloc(u8, kernels.s4_gif_decode_scratch_bytes(out_len));
    defer alloc.free(dscratch);
    const dec_idx = try alloc.alloc(u8, fc * p);
    defer alloc.free(dec_idx);
    const dec_pal = try alloc.alloc(u8, fc * @as(usize, k) * 3);
    defer alloc.free(dec_pal);
    try std.testing.expectEqual(RC_OK, kernels.s4_gif_decode(gif.ptr, out_len, dec_idx.ptr, dec_pal.ptr, &dfc, &dside, &dk, dscratch.ptr, dscratch.len));
    try std.testing.expectEqualSlices(u8, indices, dec_idx);
    try std.testing.expectEqualSlices(u8, palettes, dec_pal);
}

test "Z6: a NARROW L dynamic range still yields ≥ K distinct L-levels (range-proportional grain)" {
    // A grey range of just [0.40, 0.45]. With the OLD fixed grain a span this narrow
    // could collapse below 256 distinct quantisable levels and break significance;
    // range-proportional grain keeps ≥ K=256 distinct L values in a 64×64 frame.
    const side = 64;
    const p = side * side;
    const alloc = std.testing.allocator;
    const l_min: i32 = 26214; // ≈0.40
    const l_max: i32 = 29491; // ≈0.45

    const burst = try alloc.alloc(i32, p * 3);
    defer alloc.free(burst);
    try std.testing.expectEqual(RC_OK, s4_synth_burst(31337, SYNTH_GRAYSCALE, 1, side, l_min, l_max, 0, burst.ptr));

    const ls = try alloc.alloc(i32, p);
    defer alloc.free(ls);
    var i: usize = 0;
    while (i < p) : (i += 1) ls[i] = burst[i * 3];
    std.mem.sort(i32, ls, {}, std.sort.asc(i32));
    // every L stays inside the requested dynamic range
    try std.testing.expect(ls[0] >= l_min and ls[p - 1] <= l_max);
    var distinct: usize = 1;
    i = 1;
    while (i < p) : (i += 1) if (ls[i] != ls[i - 1]) {
        distinct += 1;
    };
    try std.testing.expect(distinct >= 256);
}

test "s4_synth_burst rejects an invalid dynamic range" {
    var out: [4 * 3]i32 = undefined; // side=2 ⇒ 4 px
    // l_max ≤ l_min
    try std.testing.expectEqual(RC_BAD_SHAPE, s4_synth_burst(1, SYNTH_GRAYSCALE, 1, 2, 30000, 30000, 0, &out));
    // l_max > Q16
    try std.testing.expectEqual(RC_BAD_SHAPE, s4_synth_burst(1, SYNTH_COLOR, 1, 2, 0, 70000, 0, &out));
    // chroma_max out of range
    try std.testing.expectEqual(RC_BAD_SHAPE, s4_synth_burst(1, SYNTH_COLOR, 1, 2, 0, 65536, 40000, &out));
}
