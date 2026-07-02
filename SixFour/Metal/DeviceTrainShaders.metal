#include <metal_stdlib>
using namespace metal;

// ============================================================================
// V3.0 rung cascade — Metal INTEGER twins of the Zig rung ops + the fused
// per-capture training dispatch (workflow B2, docs/V3-BUILD-WORKFLOW.md §3.5).
//
// The cascade shape is [int lift] → [learned float layer] → [Q16 commit + int
// unlift] inside ONE command buffer, so a rung never round-trips device memory
// through the CPU. That requires the byte-exact floor ops to exist ON the GPU:
// these kernels are line-for-line ports of the spec's integer math
// (OctreeCell.liftOct / RGBTLift.liftQuad), gated in RungDispatchTests against
// the Zig oracle `s4_octant_lift` — the same twin discipline as
// v21AccumulateHistKernel vs s4_v21_accumulate_hist. Zig stays the CPU source
// of truth; these are its accelerator twins.
//
// INTEGER DISCIPLINE: the spec's S-transform uses FLOOR division (Haskell
// `div`, Python `//`). C-family `/` truncates toward zero, which differs on
// negative odd values — fdiv2 below is the explicit floor, and every negative
// detail band in the parity test exercises it.
// ============================================================================

/// floor(x / 2) — Haskell `div 2`, NOT C truncation-toward-zero.
static inline int fdiv2(int x) {
    int q = x / 2;
    if ((x % 2) != 0 && x < 0) { q -= 1; }
    return q;
}

/// The 1-D reversible S-transform (RGBTLift.sLift): (x,y) -> (lo, hi).
static inline void s_lift(int x, int y, thread int &lo, thread int &hi) {
    int d = x - y;
    hi = d;
    lo = y + fdiv2(d);
}

/// Exact inverse (RGBTLift.sUnlift): (lo, hi) -> (x, y).
static inline void s_unlift(int lo, int hi, thread int &x, thread int &y) {
    y = lo - fdiv2(hi);
    x = y + hi;
}

/// 2×2 → (R,G,B,T) (RGBTLift.liftQuad): rows, then columns.
static inline void lift_quad(int a, int b, int c, int d,
                             thread int &r, thread int &g, thread int &bb, thread int &t) {
    int la, ha, lc, hc;
    s_lift(a, b, la, ha);
    s_lift(c, d, lc, hc);
    s_lift(la, lc, r, g);    // (ll, lh)
    s_lift(ha, hc, bb, t);   // (hl, hh)
}

/// Exact inverse (RGBTLift.unliftQuad): columns, then rows.
static inline void unlift_quad(int r, int g, int bb, int t,
                               thread int &a, thread int &b, thread int &c, thread int &d) {
    int la, lc, ha, hc;
    s_unlift(r, g, la, lc);
    s_unlift(bb, t, ha, hc);
    s_unlift(la, ha, a, b);
    s_unlift(lc, hc, c, d);
}

/// 2×2×2 → [coarse, g0,b0,t0, g1,b1,t1, dz] (OctreeCell.liftOct; the layout
/// matches `s4_octant_lift`). `blk`/`out` are one octant's 8 lanes.
static inline void lift_oct(const device int *blk, device int *out) {
    int r0, g0, b0, t0, r1, g1, b1, t1, rr, dz;
    lift_quad(blk[0], blk[1], blk[2], blk[3], r0, g0, b0, t0);   // near-z face
    lift_quad(blk[4], blk[5], blk[6], blk[7], r1, g1, b1, t1);   // far-z face
    s_lift(r0, r1, rr, dz);                                       // Haar along z
    out[0] = rr;
    out[1] = g0; out[2] = b0; out[3] = t0;
    out[4] = g1; out[5] = b1; out[6] = t1;
    out[7] = dz;
}

/// Exact inverse (OctreeCell.unliftOct).
static inline void unlift_oct(const device int *bands, device int *blk) {
    int r0, r1;
    s_unlift(bands[0], bands[7], r0, r1);
    int a, b, c, d, e, f, g, h;   // thread-local (the &-params are thread space)
    unlift_quad(r0, bands[1], bands[2], bands[3], a, b, c, d);
    unlift_quad(r1, bands[4], bands[5], bands[6], e, f, g, h);
    blk[0] = a; blk[1] = b; blk[2] = c; blk[3] = d;
    blk[4] = e; blk[5] = f; blk[6] = g; blk[7] = h;
}

// ── The twins, as kernels ───────────────────────────────────────────────────

/// N octant lifts: blocks (N×8 int) → bands (N×8 int = [coarse, 7 detail] each).
kernel void octantLiftKernel(const device int  *blocks [[buffer(0)]],
                             device int        *bands  [[buffer(1)]],
                             constant uint     &count  [[buffer(2)]],
                             uint gid [[thread_position_in_grid]]) {
    if (gid >= count) { return; }
    lift_oct(blocks + gid * 8, bands + gid * 8);
}

/// N octant unlifts: bands (N×8) → blocks (N×8). The reversibility twin.
kernel void octantUnliftKernel(const device int *bands  [[buffer(0)]],
                               device int       *blocks [[buffer(1)]],
                               constant uint    &count  [[buffer(2)]],
                               uint gid [[thread_position_in_grid]]) {
    if (gid >= count) { return; }
    unlift_oct(bands + gid * 8, blocks + gid * 8);
}

// ── The volume up-rung (one octant rung in the DEVICE layout) ────────────────

struct CubeExpandParams {
    uint side;         // coarse cube side; out is (2*side)^3
    uint has_details;  // 0 = the zero-detail floor; 1 = per-voxel committed bands
};

/// ONE up-rung of a scalar cube in the DEVICE volume layout ((t*side + r)*side + c,
/// col fastest): thread gid = one coarse voxel; its 2×2×2 output block is the
/// octant unlift of [v, 7 detail bands] scattered at (2t+dt, 2r+dr, 2c+dc), lane
/// order (dt,dr,dc) — near-t face first, the octant z axis IS the time axis.
/// `details` is [side³×7] voxel-major COMMITTED Q16 bands (a somatic θ_up's
/// invention, already through the Q16 crossing) or ignored when has_details==0
/// (the deterministic floor; zero-gene == floor). PURE INTEGER — the θ float
/// layer stays outside this kernel (the cascade-sandwich stage discipline).
/// Byte-exact twin of the Zig oracle `s4_cube_expand_rung`
/// (= Spec.SelfSimilarReconstruct.expandRungVolume), gated in RungDispatchTests.
kernel void cubeExpandRungKernel(const device int *vol            [[buffer(0)]],
                                 const device int *details        [[buffer(1)]],
                                 device int       *out            [[buffer(2)]],
                                 constant CubeExpandParams &p     [[buffer(3)]],
                                 uint gid [[thread_position_in_grid]]) {
    uint s = p.side;
    if (gid >= s * s * s) { return; }
    uint t = gid / (s * s);
    uint rest = gid % (s * s);
    uint r = rest / s;
    uint c = rest % s;

    int d0 = 0, d1 = 0, d2 = 0, d3 = 0, d4 = 0, d5 = 0, d6 = 0;
    if (p.has_details != 0) {
        const device int *dd = details + gid * 7;
        d0 = dd[0]; d1 = dd[1]; d2 = dd[2]; d3 = dd[3]; d4 = dd[4]; d5 = dd[5]; d6 = dd[6];
    }
    int r0, r1;
    s_unlift(vol[gid], d6, r0, r1);          // Haar along t
    int a, b, cc, d, e, f, g, h;
    unlift_quad(r0, d0, d1, d2, a, b, cc, d); // near-t face
    unlift_quad(r1, d3, d4, d5, e, f, g, h);  // far-t face

    uint s2 = 2 * s;
    uint bt = 2 * t, br = 2 * r, bc = 2 * c;
    out[(bt * s2 + br) * s2 + bc]             = a;
    out[(bt * s2 + br) * s2 + bc + 1]         = b;
    out[(bt * s2 + br + 1) * s2 + bc]         = cc;
    out[(bt * s2 + br + 1) * s2 + bc + 1]     = d;
    out[((bt + 1) * s2 + br) * s2 + bc]       = e;
    out[((bt + 1) * s2 + br) * s2 + bc + 1]   = f;
    out[((bt + 1) * s2 + br + 1) * s2 + bc]   = g;
    out[((bt + 1) * s2 + br + 1) * s2 + bc + 1] = h;
}

// ── The fused rung training dispatch (the B2 seed) ──────────────────────────

struct FusedTrainParams {
    uint  n;       // octant pairs in the batch (≤ kMaxFusedPairs)
    uint  steps;   // GD steps (DeviceTrainGolden.steps)
    float eta;     // learning rate (DeviceTrainGolden.eta)
};

#define kMaxFusedPairs 64u
#define kBands 7u
#define kFeats 3u
#define kQ16 65536.0f

/// ONE dispatch = the whole rung fine-tune: [int lift (pair manufacture)] →
/// [fp32 mean-gradient GD on θ_up, entirely in registers] → [Q16 commit].
/// No device-memory round trip between the floor op and the learned layer —
/// the cascade property the A19 tensor units reward.
///
/// θ_up's working set is 21 weights + 21 grads (`GeneTaxonomy
/// foldsIntoRungDispatch` — 168 bytes against the 32 KiB budget), which is why
/// this gene folds and the value head does not.
///
/// SEED SCOPE (honest): a single thread runs the serial descent — correctness
/// first, gated on DeviceTrainGolden.committed. The per-capture batch version
/// (thousands of pairs, threadgroup parallel-reduction over the gradient, and
/// the Metal-4 tensor-op forward) is B2.2 and gates on the SAME bytes.
/// `n` is clamped to kMaxFusedPairs.
///
/// Outputs: pairsOut (n×8: the manufactured [coarse, detail] rows — the host
/// parity-checks these against the Zig oracle), thetaOut (21, spec row-major
/// θ_j·k), committedOut (7: f_θ at pairsOut[0]'s coarse, re-entered to Q16 by
/// rint = round-half-to-even — the golden gate bytes).
kernel void deviceTrainFusedKernel(const device int          *blocks       [[buffer(0)]],
                                   device int                *pairsOut     [[buffer(1)]],
                                   device float              *thetaOut     [[buffer(2)]],
                                   device int                *committedOut [[buffer(3)]],
                                   constant FusedTrainParams &p            [[buffer(4)]],
                                   uint gid [[thread_position_in_grid]]) {
    if (gid != 0) { return; }
    const uint n = min(p.n, kMaxFusedPairs);
    if (n == 0) { return; }

    // 1. INT LIFT — manufacture the supervision pairs on-GPU (the exact pool).
    for (uint i = 0; i < n; i++) {
        lift_oct(blocks + i * 8, pairsOut + i * 8);
    }

    // Stage the float view: φ(v) = [1, ṽ, ṽ²], targets t̃ = detail / 2¹⁶.
    float phi[kMaxFusedPairs][kFeats];
    float tgt[kMaxFusedPairs][kBands];
    for (uint i = 0; i < n; i++) {
        const float v = float(pairsOut[i * 8]) / kQ16;
        phi[i][0] = 1.0f; phi[i][1] = v; phi[i][2] = v * v;
        for (uint j = 0; j < kBands; j++) {
            tgt[i][j] = float(pairsOut[i * 8 + 1 + j]) / kQ16;
        }
    }

    // 2. LEARNED LAYER — mean-gradient GD from the zero floor (the
    //    Spec.DeviceTrainStep.trainDevice twin, fp32).
    float theta[kBands * kFeats];
    for (uint i = 0; i < kBands * kFeats; i++) { theta[i] = 0.0f; }
    const float scale = p.eta / float(n);
    for (uint s = 0; s < p.steps; s++) {
        float grad[kBands * kFeats];
        for (uint i = 0; i < kBands * kFeats; i++) { grad[i] = 0.0f; }
        for (uint i = 0; i < n; i++) {
            for (uint j = 0; j < kBands; j++) {
                float raw = 0.0f;
                for (uint k = 0; k < kFeats; k++) { raw += theta[j * kFeats + k] * phi[i][k]; }
                const float err = raw - tgt[i][j];
                for (uint k = 0; k < kFeats; k++) { grad[j * kFeats + k] += err * phi[i][k]; }
            }
        }
        for (uint i = 0; i < kBands * kFeats; i++) { theta[i] -= scale * grad[i]; }
    }
    for (uint i = 0; i < kBands * kFeats; i++) { thetaOut[i] = theta[i]; }

    // 3. Q16 COMMIT — the single sanctioned float→device crossing at the first
    //    pair's coarse: rint = round-half-to-even (ByteCarrier.reenterQ16).
    for (uint j = 0; j < kBands; j++) {
        float raw = 0.0f;
        for (uint k = 0; k < kFeats; k++) { raw += theta[j * kFeats + k] * phi[0][k]; }
        committedOut[j] = int(rint(raw * kQ16));
    }
}

// ── The capture-octant gather (B2.3) ────────────────────────────────────────

struct OctGatherParams {
    uint frames;    // t extent (even)
    uint side;      // spatial extent (even)
    uint channel;   // OKLab channel to train on (0=L, 1=a, 2=b)
};

/// Gather EVERY 2×2×2 octant block of one channel of a captured OKLab Q16
/// volume (layout: ((f·side + row)·side + col)·3 + ch — the `s4_synth_burst` /
/// capture buffer layout) into the N×8 block rows the trainer consumes.
/// Lane order: (df, drow, dcol), col fastest — the near-t face is lanes 0–3, so
/// the octant lift's z axis IS the time axis (the temporal-Haar convention).
///
/// This is the B2.3 fusion stage: chained before `deviceTrainSimtKernel` in the
/// SAME command buffer, the capture's supervision pairs are manufactured and
/// consumed entirely on-GPU — the burst never round-trips the CPU on its way
/// into θ_up.
kernel void captureOctantsKernel(const device int         *volume [[buffer(0)]],
                                 device int               *blocks [[buffer(1)]],
                                 constant OctGatherParams &p      [[buffer(2)]],
                                 uint gid [[thread_position_in_grid]]) {
    const uint fh = p.frames / 2, sh = p.side / 2;
    const uint nOct = fh * sh * sh;
    if (gid >= nOct) { return; }
    const uint F = gid / (sh * sh);
    const uint rem = gid % (sh * sh);
    const uint R = rem / sh;
    const uint C = rem % sh;
    for (uint df = 0; df < 2; df++) {
        for (uint dr = 0; dr < 2; dr++) {
            for (uint dc = 0; dc < 2; dc++) {
                const uint flat = (((2 * F + df) * p.side + (2 * R + dr)) * p.side
                                   + (2 * C + dc)) * 3 + p.channel;
                blocks[gid * 8 + df * 4 + dr * 2 + dc] = volume[flat];
            }
        }
    }
}

// ── The deterministic-SIMT batch trainer (B2.2) ─────────────────────────────
//
// THE SIMT STANDARD for rung kernels (the OneSix deterministic-SIMT-spine
// discipline, adopted here):
//   1. ONE threadgroup per problem, power-of-two width (kSimtThreads);
//   2. STRIDED pair assignment (thread t owns pairs t, t+T, t+2T, …) — each
//      thread's private accumulation order is fixed;
//   3. FIXED-ORDER binary tree reduction in threadgroup memory — fp32 addition
//      is non-associative, so determinism is a property of the ORDER, and the
//      tree pins it: the same input bits give the same output bits, run after
//      run (bitwise-reproducibility is a test, not a hope);
//   4. barriers only at phase seams (accumulate → reduce → update);
//   5. the gate is always the post-commit bytes.
//
// Threadgroup working set: θ (84 B) + the 21-wide reduction tree
// (kSimtThreads × 21 × 4 = 21,504 B) ≈ 21.6 KiB — inside the 32 KiB budget
// that `GeneTaxonomy.foldsIntoRungDispatch` pins for θ_up. The budget law is
// now literally this allocation.

#define kSimtThreads 256u
#define kParamsD (kBands * kFeats)   // 21

/// Batch fine-tune: N fine blocks (N×8 int, N up to buffer capacity — the real
/// per-capture regime, thousands of pairs) → [strided int lift] →
/// [deterministic-SIMT mean-gradient GD] → [Q16 commit at pair 0's coarse].
/// Dispatch EXACTLY kSimtThreads threads in ONE threadgroup.
///
/// `scratch` is N×(kFeats+kBands) floats (host-allocated): the staged φ rows
/// and Q16-normalised targets, written in phase 0, read every step.
/// `lossOut[0]` receives the final summed supervised loss (telemetry;
/// Spec.DeviceTrainStep.deviceLossSum).
kernel void deviceTrainSimtKernel(const device int          *blocks       [[buffer(0)]],
                                  device int                *pairsOut     [[buffer(1)]],
                                  device float              *thetaOut     [[buffer(2)]],
                                  device int                *committedOut [[buffer(3)]],
                                  constant FusedTrainParams &p            [[buffer(4)]],
                                  device float              *scratch      [[buffer(5)]],
                                  device float              *lossOut      [[buffer(6)]],
                                  uint tid [[thread_position_in_threadgroup]]) {
    const uint n = p.n;
    if (n == 0) { return; }

    threadgroup float th[kParamsD];
    threadgroup float red[kSimtThreads * kParamsD];

    // ── Phase 0: strided INT LIFT (pair manufacture) + float staging ────────
    for (uint i = tid; i < n; i += kSimtThreads) {
        lift_oct(blocks + i * 8, pairsOut + i * 8);
        const float v = float(pairsOut[i * 8]) / kQ16;
        device float *row = scratch + i * (kFeats + kBands);
        row[0] = 1.0f; row[1] = v; row[2] = v * v;
        for (uint j = 0; j < kBands; j++) {
            row[kFeats + j] = float(pairsOut[i * 8 + 1 + j]) / kQ16;
        }
    }
    if (tid == 0) {
        for (uint c = 0; c < kParamsD; c++) { th[c] = 0.0f; }   // the zero floor
    }
    threadgroup_barrier(mem_flags::mem_device | mem_flags::mem_threadgroup);

    // ── Phase 1: the descent (accumulate → tree-reduce → update, per step) ──
    const float scale = p.eta / float(n);
    for (uint s = 0; s < p.steps; s++) {
        float g[kParamsD];
        for (uint c = 0; c < kParamsD; c++) { g[c] = 0.0f; }
        for (uint i = tid; i < n; i += kSimtThreads) {           // strided, fixed order
            const device float *row = scratch + i * (kFeats + kBands);
            for (uint j = 0; j < kBands; j++) {
                float raw = 0.0f;
                for (uint k = 0; k < kFeats; k++) { raw += th[j * kFeats + k] * row[k]; }
                const float err = raw - row[kFeats + j];
                for (uint k = 0; k < kFeats; k++) { g[j * kFeats + k] += err * row[k]; }
            }
        }
        for (uint c = 0; c < kParamsD; c++) { red[tid * kParamsD + c] = g[c]; }
        threadgroup_barrier(mem_flags::mem_threadgroup);
        for (uint offset = kSimtThreads / 2; offset > 0; offset >>= 1) {   // fixed tree
            if (tid < offset) {
                for (uint c = 0; c < kParamsD; c++) {
                    red[tid * kParamsD + c] += red[(tid + offset) * kParamsD + c];
                }
            }
            threadgroup_barrier(mem_flags::mem_threadgroup);
        }
        if (tid == 0) {
            for (uint c = 0; c < kParamsD; c++) { th[c] -= scale * red[c]; }
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    // ── Phase 2: final loss (same reduction), θ out, Q16 commit ─────────────
    float sse = 0.0f;
    for (uint i = tid; i < n; i += kSimtThreads) {
        const device float *row = scratch + i * (kFeats + kBands);
        for (uint j = 0; j < kBands; j++) {
            float raw = 0.0f;
            for (uint k = 0; k < kFeats; k++) { raw += th[j * kFeats + k] * row[k]; }
            const float d = raw - row[kFeats + j];
            sse += d * d;
        }
    }
    red[tid * kParamsD] = sse;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint offset = kSimtThreads / 2; offset > 0; offset >>= 1) {
        if (tid < offset) { red[tid * kParamsD] += red[(tid + offset) * kParamsD]; }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (tid == 0) {
        lossOut[0] = 0.5f * red[0];
        for (uint c = 0; c < kParamsD; c++) { thetaOut[c] = th[c]; }
        const device float *row0 = scratch;                       // pair 0's φ
        for (uint j = 0; j < kBands; j++) {
            float raw = 0.0f;
            for (uint k = 0; k < kFeats; k++) { raw += th[j * kFeats + k] * row0[k]; }
            committedOut[j] = int(rint(raw * kQ16));
        }
    }
}
