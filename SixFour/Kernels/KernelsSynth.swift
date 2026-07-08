//  KernelsSynth.swift
//  Zig→Swift port of Native/src/synth.zig — (2026-07-06) byte-exact twin,
//  golden-gated.
//
//  SixFour synthetic-burst generator — the TRAINING data engine.
//
//  Why this lives in the kernel core: the look-NN trainer (trainer/) needs
//  labeled 64-frame bursts, but trainer/data/ is empty and on-device capture is
//  offline. `s4_synth_burst` procedurally generates an OKLab Q16 burst that we
//  then feed through the SAME deterministic kernels the device runs
//  (s4_quantize_frame → s4_palette_oklab_to_srgb8 → s4_gif_assemble). So the
//  per-frame palettes the trainer learns from are produced byte-identically to
//  production — no train/deploy skew, and unlimited reproducible data from a
//  seed.
//
//  This is the ONE synthesized (not captured) surface in the pipeline. It is
//  Mac-side training tooling; the device never runs it. The trainer's data
//  loader is structured so dropping real captures into trainer/data/ is a
//  one-line swap.
//
//  Determinism: integer value-noise only (splitmix64 PRNG + integer bilinear
//  upsample of a coarse control lattice + integer grain). No floats, no trig —
//  same seed ⇒ same bytes, on any host. Output is interleaved OKLab Q16 triplets
//  (the s4_quantize_frame input format), L∈[0,1]→[0,65536],
//  a,b∈[-0.5,0.5]→[±32768].

// Per-file constants (synth.zig pulls these from kernels.zig; replicated here
// as private, values pinned to kernels.zig / KernelsCore.swift).
private let Q16: Int64 = Int64(S4_Q16_ONE) // 65536 (kernels.Q16_ONE)
private let RC_OK: Int32 = 0 // kernels.RC_OK
private let RC_NULL_PTR: Int32 = 1 // kernels.RC_NULL_PTR
private let RC_BAD_SHAPE: Int32 = 2 // kernels.RC_BAD_SHAPE

// Synthesis modes (mirror sixfour_native.h S4_SYNTH_*).

/// Full OKLab burst (L,a,b all vary).
public let S4_SYNTH_COLOR: Int32 = 0
/// a=b=0 exactly — Milestone L training data.
public let S4_SYNTH_GRAYSCALE: Int32 = 1

/// Coarse control lattice resolution. A GRID×GRID set of OKLab anchors is
/// bilinearly upsampled to side×side, giving smooth spatial gradients/blobs
/// (not white noise). (Zig `const GRID: usize = 4` — private in Zig.)
private let GRID: Int = 4

// Default anchor ranges (Q16) the caller (zig_native.py) passes when it wants
// the canonical span. L_MIN..L_MAX is the default grey dynamic range; CHROMA the
// default chroma deviation bound. Now caller-controlled: L SETS the dynamic
// range. (Zig `pub const L_MIN/L_MAX/CHROMA`, not in sixfour_native.h; prefixed
// S4_SYNTH_ to keep the module namespace collision-free.)

/// Default grey dynamic-range floor: ≈0.08 in Q16.
public let S4_SYNTH_L_MIN: Int32 = 5243
/// Default grey dynamic-range ceiling: ≈0.92 in Q16.
public let S4_SYNTH_L_MAX: Int32 = 60293
/// Default chroma deviation bound: ≈0.28 → a,b ∈ [-0.28, 0.28].
public let S4_SYNTH_CHROMA: Int32 = 18350

/// Grain scale (Q16): multiplies the significance-floor grain to span the
/// DETAIL / spatial-frequency axis (the perceptual conditional load)
/// independently of the L range. 65536 (1.0) is the canonical level (the
/// original behaviour); > 65536 adds high-frequency detail.
/// (= `S4_SYNTH_DETAIL_Q16` in sixfour_native.h, `DETAIL_Q16` in synth.zig.)
public let S4_SYNTH_DETAIL_Q16: Int32 = 65536

// ── deterministic PRNG ────────────────────────────────────────────────────────

/// Private helper — the Zig `inline fn splitmix64` (Steele/Lea/Flood SplitMix64,
/// exact constants: γ = 0x9E3779B97F4A7C15, mixers 0xBF58476D1CE4E5B9 /
/// 0x94D049BB133111EB, shifts 30/27/31; all wrapping u64 arithmetic).
@inline(__always)
private func splitmix64(_ state: inout UInt64) -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
}

/// Uniform integer in [lo, hi] (inclusive). hi ≥ lo assumed by callers.
/// Private helper — the Zig `inline fn randRange` (modulo reduction, exactly as
/// the Zig source: the tiny modulo bias is part of the pinned byte stream).
@inline(__always)
private func randRange(_ state: inout UInt64, _ lo: Int64, _ hi: Int64) -> Int64 {
    let span = UInt64(hi - lo + 1)
    return lo + Int64(splitmix64(&state) % span)
}

/// Stateless hashed grain in [-grain, grain] from (seed, frame, x, y). Stateless
/// so a pixel's grain is independent of iteration order (reproducible per
/// coord). `grain` is range-proportional (see s4_synth_burst) so a NARROW
/// dynamic range still yields ≥ K distinct quantisable L-levels — load-bearing
/// for significance. Private helper — the Zig `inline fn grainAt` (FNV-style:
/// prime 0x100000001B3, salt 0xD1B54A32D192ED03, coord salts 73856093/19349663,
/// final `h ^= h >> 29`).
@inline(__always)
private func grainAt(_ seed: UInt64, _ frame: Int, _ x: Int, _ y: Int, _ grain: Int64) -> Int64 {
    var h: UInt64 = seed ^ 0xD1B5_4A32_D192_ED03
    h = (h ^ UInt64(frame)) &* 0x100_0000_01B3
    h = (h ^ UInt64(bitPattern: Int64(x &* 73_856_093))) &* 0x100_0000_01B3
    h = (h ^ UInt64(bitPattern: Int64(y &* 19_349_663))) &* 0x100_0000_01B3
    h ^= h >> 29
    let span = UInt64(2 * grain + 1)
    return -grain + Int64(h % span)
}

// ── integer triangle wave: 0 → 1 → 0 across the burst, in Q16 ────────────────

/// Private helper — the Zig `fn triangleQ16`.
@inline(__always)
private func triangleQ16(_ frame: Int, _ frameCount: Int) -> Int64 {
    if frameCount <= 1 { return 0 }
    // phase ∈ [0, 2·Q16] over the burst; fold the second half back down.
    let phase = (Int64(frame) * 2 * Q16) / Int64(frameCount - 1) // @divTrunc
    return phase <= Q16 ? phase : 2 * Q16 - phase
}

// ── integer bilinear upsample of one channel of the lattice ──────────────────

/// lattice: GRID·GRID i64 (single channel, row-major). Returns the Q16 value at
/// pixel (x,y) of a side×side frame. Private helper — the Zig `fn bilerp`.
@inline(__always)
private func bilerp(_ lattice: UnsafePointer<Int64>, _ x: Int, _ y: Int, _ side: Int) -> Int64 {
    let w = Int64(side - 1) // denominator; side ≥ 2 enforced by caller
    let g = Int64(GRID - 1)

    let gx = Int64(x) * g // ∈ [0, w·g]
    var cx = Int(gx / w) // @divTrunc, nonnegative
    var fx = gx - Int64(cx) * w // remainder ∈ [0, w]
    if cx >= GRID - 1 {
        cx = GRID - 2
        fx = w
    }
    let gy = Int64(y) * g
    var cy = Int(gy / w)
    var fy = gy - Int64(cy) * w
    if cy >= GRID - 1 {
        cy = GRID - 2
        fy = w
    }

    let v00 = lattice[cy * GRID + cx]
    let v10 = lattice[cy * GRID + cx + 1]
    let v01 = lattice[(cy + 1) * GRID + cx]
    let v11 = lattice[(cy + 1) * GRID + cx + 1]

    // Bilinear blend with weights in units of w (so divide by w² at the end).
    let top = v00 * (w - fx) + v10 * fx
    let bot = v01 * (w - fx) + v11 * fx
    return (top * (w - fy) + bot * fy) / (w * w) // @divTrunc
}

/// Private helper — the Zig `inline fn clampOklab`:
/// L ∈ [0, Q16]; a,b ∈ [-Q16/2, Q16/2] (matches the kernels.zig Q16 contract).
@inline(__always)
private func clampOklab(_ channel: Int, _ v: Int64) -> Int32 {
    if channel == 0 { return Int32(min(max(v, 0), Q16)) }
    let half = Q16 / 2
    return Int32(min(max(v, -half), half))
}

/// Generate a synthetic OKLab Q16 burst into the caller-owned `out_oklab_q16`
/// buffer (frame_count · side · side · 3 i32, interleaved L,a,b row-major).
///
/// **L SETS THE DYNAMIC RANGE:** lightness anchors are drawn from
/// `[l_min_q16, l_max_q16]` (the grey-axis dynamic range), and a,b are signed
/// DEVIATIONS from the grey centre in `[-chroma_max_q16, +chroma_max_q16]`.
/// `mode` SYNTH_GRAYSCALE forces a=b=0 exactly (the σ-fixed grey axis). The
/// burst sweeps between two random control lattices via a triangle wave
/// (distinct per-frame palettes, seamless loop). Grain scales with the L range
/// so even a narrow range yields ≥K distinct levels (significance).
/// Deterministic in `seed`. Validates `0 ≤ l_min < l_max ≤ 65536` and
/// `0 ≤ chroma_max ≤ 32768`. Private helper — the Zig `fn synthBurstImpl`.
private func synthBurstImpl(
    _ seed: UInt64,
    _ mode: Int32,
    _ frame_count: Int32,
    _ side: Int32,
    _ l_min_q16: Int32,
    _ l_max_q16: Int32,
    _ chroma_max_q16: Int32,
    _ detail_q16: Int32,
    _ out_oklab_q16: UnsafeMutablePointer<Int32>?
) -> Int32 {
    guard let out = out_oklab_q16 else { return RC_NULL_PTR }
    if frame_count <= 0 || side < 2 { return RC_BAD_SHAPE }
    if mode != S4_SYNTH_COLOR && mode != S4_SYNTH_GRAYSCALE { return RC_BAD_SHAPE }
    if l_min_q16 < 0 || l_max_q16 <= l_min_q16 || Int64(l_max_q16) > Q16 { return RC_BAD_SHAPE }
    if chroma_max_q16 < 0 || Int64(chroma_max_q16) > Q16 / 2 { return RC_BAD_SHAPE }
    if detail_q16 < 0 { return RC_BAD_SHAPE }
    let grayscale = (mode == S4_SYNTH_GRAYSCALE)

    let lMin = Int64(l_min_q16)
    let lMax = Int64(l_max_q16)
    let chroma = Int64(chroma_max_q16)
    // Significance-floor grain (≥1, ≈range/128) guarantees ≥K distinct quantisable
    // L-levels; detail_q16 scales it UP to add high-frequency detail (the
    // perceptual/detail axis). The floor is never breached, so significance holds
    // at every detail level.
    let sigGrain = max(Int64(1), (lMax - lMin) / 128) // @divTrunc
    let grain = max(sigGrain, (sigGrain * Int64(detail_q16)) / Q16) // @divTrunc

    let fc = Int(frame_count)
    let sd = Int(side)
    let p = sd * sd

    // Two keyframe lattices (A, B), 3 channels each, drawn from the seed. The
    // burst interpolates A↔B per frame to produce temporal palette drift.
    // (Zig stack arrays; here raw allocations — hot path stays on raw pointers.)
    var state: UInt64 = seed &* 0x2545_F491_4F6C_DD1D &+ 1
    let latA = UnsafeMutablePointer<Int64>.allocate(capacity: GRID * GRID * 3)
    let latB = UnsafeMutablePointer<Int64>.allocate(capacity: GRID * GRID * 3)
    let latL = UnsafeMutablePointer<Int64>.allocate(capacity: GRID * GRID)
    let latACh = UnsafeMutablePointer<Int64>.allocate(capacity: GRID * GRID)
    let latBCh = UnsafeMutablePointer<Int64>.allocate(capacity: GRID * GRID)
    defer {
        latA.deallocate()
        latB.deallocate()
        latL.deallocate()
        latACh.deallocate()
        latBCh.deallocate()
    }
    var n = 0
    while n < GRID * GRID {
        // PRNG call ORDER is the byte stream — preserved exactly from the Zig.
        latA[n * 3 + 0] = randRange(&state, lMin, lMax)
        latB[n * 3 + 0] = randRange(&state, lMin, lMax)
        if grayscale {
            latA[n * 3 + 1] = 0
            latA[n * 3 + 2] = 0
            latB[n * 3 + 1] = 0
            latB[n * 3 + 2] = 0
        } else {
            latA[n * 3 + 1] = randRange(&state, -chroma, chroma)
            latA[n * 3 + 2] = randRange(&state, -chroma, chroma)
            latB[n * 3 + 1] = randRange(&state, -chroma, chroma)
            latB[n * 3 + 2] = randRange(&state, -chroma, chroma)
        }
        n += 1
    }

    var frame = 0
    while frame < fc {
        let t = triangleQ16(frame, fc) // Q16 blend A↔B

        // Per-frame lattice = lerp(A, B, t), split into single-channel views.
        n = 0
        while n < GRID * GRID {
            latL[n] = latA[n * 3 + 0] + ((latB[n * 3 + 0] - latA[n * 3 + 0]) * t) / Q16
            latACh[n] = latA[n * 3 + 1] + ((latB[n * 3 + 1] - latA[n * 3 + 1]) * t) / Q16
            latBCh[n] = latA[n * 3 + 2] + ((latB[n * 3 + 2] - latA[n * 3 + 2]) * t) / Q16
            n += 1
        }

        let fbase = frame * p * 3
        var y = 0
        while y < sd {
            var x = 0
            while x < sd {
                let idx = fbase + (y * sd + x) * 3
                let gr = grainAt(seed, frame, x, y, grain)
                out[idx + 0] = clampOklab(0, bilerp(latL, x, y, sd) + gr)
                if grayscale {
                    out[idx + 1] = 0 // exact a=0
                    out[idx + 2] = 0 // exact b=0
                } else {
                    out[idx + 1] = clampOklab(1, bilerp(latACh, x, y, sd) + gr)
                    out[idx + 2] = clampOklab(2, bilerp(latBCh, x, y, sd) + gr)
                }
                x += 1
            }
            y += 1
        }
        frame += 1
    }
    return RC_OK
}

/// Public ABI (UNCHANGED): the canonical synth burst at the default detail
/// level (1.0).
@_cdecl("s4_synth_burst")
public func s4_synth_burst(
    _ seed: UInt64,
    _ mode: Int32,
    _ frame_count: Int32,
    _ side: Int32,
    _ l_min_q16: Int32,
    _ l_max_q16: Int32,
    _ chroma_max_q16: Int32,
    _ out_oklab_q16: UnsafeMutablePointer<Int32>?
) -> Int32 {
    return synthBurstImpl(
        seed, mode, frame_count, side,
        l_min_q16, l_max_q16, chroma_max_q16,
        S4_SYNTH_DETAIL_Q16, out_oklab_q16)
}

/// Public ABI: synth burst with an explicit DETAIL scale (Q16).
/// `detail_q16 > 65536` adds high-frequency detail ABOVE the significance floor
/// — spans the perceptual/detail entropy axis at real scale without disturbing
/// the ≥K-distinct guarantee. `65536` == `s4_synth_burst`. Same seed + params ⇒
/// same bytes.
@_cdecl("s4_synth_burst_detail")
public func s4_synth_burst_detail(
    _ seed: UInt64,
    _ mode: Int32,
    _ frame_count: Int32,
    _ side: Int32,
    _ l_min_q16: Int32,
    _ l_max_q16: Int32,
    _ chroma_max_q16: Int32,
    _ detail_q16: Int32,
    _ out_oklab_q16: UnsafeMutablePointer<Int32>?
) -> Int32 {
    return synthBurstImpl(
        seed, mode, frame_count, side,
        l_min_q16, l_max_q16, chroma_max_q16,
        detail_q16, out_oklab_q16)
}
