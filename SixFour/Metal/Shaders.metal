#include <metal_stdlib>
using namespace metal;

// MARK: - sRGB transfer

inline float srgbToLinear(float x) {
    return x <= 0.04045f ? x / 12.92f : pow((x + 0.055f) / 1.055f, 2.4f);
}

inline float3 srgbToLinear3(float3 c) {
    return float3(srgbToLinear(c.r), srgbToLinear(c.g), srgbToLinear(c.b));
}

// MARK: - ITU-R BT.709 transfer
//
// The opto-electronic transfer of Rec.709 (α = 1.099, β = 0.018, γ = 0.45)
// is materially different from sRGB in the toe: replacing one with the
// other introduces ~63% linear error in dark tones (~162× the 8-bit
// quantization error). Use this on the YCbCr10 capture path to avoid
// crushing shadows.
//
// Inverse: V_linear = V / 4.5                            for V < 0.081
//          V_linear = ((V + 0.099) / 1.099) ^ (1/0.45)   otherwise

inline float rec709ToLinear(float v) {
    return v < 0.081f
        ? v / 4.5f
        : pow((v + 0.099f) / 1.099f, 1.0f / 0.45f);
}

inline float3 rec709ToLinear3(float3 c) {
    return float3(rec709ToLinear(c.r), rec709ToLinear(c.g), rec709ToLinear(c.b));
}

// MARK: - HLG inverse OETF (ITU-R BT.2100 Table 5)
//
// Maps signal V ∈ [0,1] to scene-linear in [0,12]. The two-segment curve
// is exact: a square law in the toe, an exponential in the body. We do
// NOT apply the OOTF — downstream consumers (OKLab) expect scene-linear
// for SDR display, and the OOTF would re-introduce a tone-curve that
// makes the GIF look gamma-corrected twice.

inline float hlgToScene(float v) {
    const float a = 0.17883277f;
    const float b = 0.28466892f;   // 1 - 4a
    const float c = 0.55991073f;   // 0.5 - a·ln(4a)
    return v <= 0.5f
        ? (v * v) / 3.0f
        : (exp((v - c) / a) + b) / 12.0f;
}

// MARK: - Apple Log inverse OETF (Apple "Apple Log Profile" white paper)
//
// Cineon-style log curve: V = 0.247190·ln(48·E + 1) − 0.097347 for E ≥ ε.
// Inverse: E = (exp((V + 0.097347) / 0.247190) − 1) / 48.
// Apple gates this format to movie-file output on iPhone Pro; data-output
// grants are rare (CaptureSession warns when seen). Implementation is
// provided so the pipeline doesn't crash if the format ever surfaces.

inline float appleLogToScene(float v) {
    return (exp((v + 0.097347f) / 0.247190f) - 1.0f) / 48.0f;
}

// MARK: - Color-space primary conversions
//
// Both matrices take linear RGB in the source primaries and return
// linear RGB in sRGB (BT.709) primaries. Derived from the standard
// chromaticities: BT.2020 (R, G, B at 0.708/0.292, 0.170/0.797,
// 0.131/0.046) and Display P3 (0.680/0.320, 0.265/0.690,
// 0.150/0.060), both with D65 white point.

inline float3 bt2020ToSRGB(float3 c) {
    return float3(
         1.6605f * c.r - 0.5876f * c.g - 0.0728f * c.b,
        -0.1246f * c.r + 1.1329f * c.g - 0.0083f * c.b,
        -0.0182f * c.r - 0.1006f * c.g + 1.1187f * c.b
    );
}

inline float3 p3ToSRGB(float3 c) {
    return float3(
         1.2249f * c.r - 0.2247f * c.g + 0.0000f * c.b,
        -0.0420f * c.r + 1.0419f * c.g + 0.0000f * c.b,
        -0.0197f * c.r - 0.0786f * c.g + 1.0979f * c.b
    );
}

// MARK: - OKLab (operates on linear-light sRGB)

inline float3 linearSRGBToOKLab(float3 rgb) {
    float l = 0.4122214708f * rgb.r + 0.5363325363f * rgb.g + 0.0514459929f * rgb.b;
    float m = 0.2119034982f * rgb.r + 0.6806995451f * rgb.g + 0.1073969566f * rgb.b;
    float s = 0.0883024619f * rgb.r + 0.2817188376f * rgb.g + 0.6299787005f * rgb.b;

    float l_ = sign(l) * pow(abs(l), 1.0f / 3.0f);
    float m_ = sign(m) * pow(abs(m), 1.0f / 3.0f);
    float s_ = sign(s) * pow(abs(s), 1.0f / 3.0f);

    return float3(
        0.2104542553f * l_ + 0.7936177850f * m_ - 0.0040720468f * s_,
        1.9779984951f * l_ - 2.4285922050f * m_ + 0.4505937099f * s_,
        0.0259040371f * l_ + 0.7827717662f * m_ - 0.8086757660f * s_
    );
}

// MARK: - 10-bit YpCbCr (video range) → linear-light sRGB
//
// Dispatches on `colorSpaceTag` (matches CaptureSession.ActiveColorSpaceTag
// raw values) to handle the four selectable capture color spaces:
//
//   0 = Rec.709        — BT.709 YCbCr matrix, Rec.709 OETF inverse,
//                        already in sRGB primaries.
//   1 = HLG_BT2020     — BT.2020 NCL YCbCr matrix, HLG inverse OETF
//                        (BT.2100 Table 5), then BT.2020 → sRGB primaries.
//   2 = Apple Log      — BT.2020 NCL YCbCr matrix, Apple Log inverse,
//                        then BT.2020 → sRGB primaries.
//   3 = Display P3     — BT.709 YCbCr matrix (iOS path), sRGB transfer,
//                        then Display P3 → sRGB primaries.
//
// Input rationale (common to all tags):
//   Apple delivers 10-bit YCbCr biplanar into a R16Unorm luma plane and a
//   RG16Unorm chroma plane. 10-bit values are stored in the *upper* 10 bits of
//   each 16-bit word, so reading [0,1]-normalized from MTL gives ~r * 1.001 of
//   the 10-bit "normalized" value. We stretch video range
//   ([64..940]/[64..960] → [0..1]/[-0.5..0.5]) and apply the per-tag
//   matrix + OETF inverse + primary conversion below.
//
// Clamp policy: clamp to [0,1] sRGB *after* the OETF inverse. Clamping
// before the OETF (the original Rec.709-only code did this) crushes HDR
// highlights because HLG/Apple Log carry signal above SDR reference white.

inline float3 ycbcr10VideoRangeToLinearSRGB(float y_raw, float cb_raw, float cr_raw, uchar tag) {
    // Stretch video range. The 1.000962 scale corrects for 10-bit-in-top-bits
    // R16Unorm storage (= 65535/65472, per Apple's CVPixelBuffer docs).
    float Y  = (y_raw  * 1.000962f - 0.0625610f) / 0.856305f;
    float Cb = (cb_raw * 1.000962f - 0.500489f) / 0.875855f;
    float Cr = (cr_raw * 1.000962f - 0.500489f) / 0.875855f;

    // YCbCr → R'G'B' matrix selection. HLG_BT2020 and Apple Log both use
    // BT.2020 non-constant-luminance coefficients; Rec.709 and P3 use
    // the BT.709 coefficients (P3 capture on iOS reuses 709 YCbCr).
    float R, G, B;
    if (tag == 1u || tag == 2u) {
        // BT.2020 NCL (ITU-R BT.2020 §3.3.5).
        R = Y + 1.4746f   * Cr;
        G = Y - 0.16455f  * Cb - 0.57135f * Cr;
        B = Y + 1.8814f   * Cb;
    } else {
        // BT.709.
        R = Y + 1.5748f * Cr;
        G = Y - 0.1873f * Cb - 0.4681f * Cr;
        B = Y + 1.8556f * Cb;
    }

    // OETF inverse + primary conversion per tag.
    float3 lin;
    if (tag == 1u) {            // HLG_BT2020
        lin = float3(hlgToScene(R), hlgToScene(G), hlgToScene(B));
        lin = bt2020ToSRGB(lin);
    } else if (tag == 2u) {     // Apple Log
        lin = float3(appleLogToScene(R), appleLogToScene(G), appleLogToScene(B));
        lin = bt2020ToSRGB(lin);
    } else if (tag == 3u) {     // Display P3
        lin = srgbToLinear3(float3(R, G, B));
        lin = p3ToSRGB(lin);
    } else {                    // Rec.709 (default)
        lin = rec709ToLinear3(float3(R, G, B));
    }

    return clamp(lin, 0.0f, 1.0f);
}

// Fused crop + linearize + area-average for 10-bit YCbCr 4:2:0 biplanar
// input. Reads Y at full res and CbCr at half res (sampled at sx/2, sy/2
// for each luma position). This is the only entry point into the GPU
// pipeline — the device must deliver YCbCr10 video-range, enforced by
// `CaptureSession.configure()`.

kernel void cropDownsampleLinearizeKernel(
    texture2d<float, access::read> luma   [[texture(0)]],
    texture2d<float, access::read> chroma [[texture(1)]],
    texture2d<float, access::write> destination [[texture(2)]],
    constant int2  &srcOffset      [[buffer(0)]],
    constant int   &scale          [[buffer(1)]],
    constant uchar &colorSpaceTag  [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint dw = destination.get_width();
    uint dh = destination.get_height();
    if (gid.x >= dw || gid.y >= dh) return;

    int sx0 = srcOffset.x + (int)gid.x * scale;
    int sy0 = srcOffset.y + (int)gid.y * scale;
    int yw = (int)luma.get_width();
    int yh = (int)luma.get_height();
    int cw = (int)chroma.get_width();
    int ch = (int)chroma.get_height();

    float3 sum = float3(0.0f);
    int count = 0;
    for (int dy = 0; dy < scale; ++dy) {
        int sy = sy0 + dy;
        if (sy < 0 || sy >= yh) continue;
        int cy = clamp(sy / 2, 0, ch - 1);
        for (int dx = 0; dx < scale; ++dx) {
            int sx = sx0 + dx;
            if (sx < 0 || sx >= yw) continue;
            int cx = clamp(sx / 2, 0, cw - 1);
            float Y  = luma.read(uint2((uint)sx, (uint)sy)).r;
            float2 CC = chroma.read(uint2((uint)cx, (uint)cy)).rg;
            sum += ycbcr10VideoRangeToLinearSRGB(Y, CC.x, CC.y, colorSpaceTag);
            count++;
        }
    }
    float3 lin = count > 0 ? sum / float(count) : float3(0.0f);
    destination.write(float4(lin, 1.0f), gid);
}

// MARK: - Linear RGB → OKLab
//
// Expects RGBA16F linear input; writes RGBA16F OKLab. Channel mapping:
// out.r = L, out.g = a, out.b = b, out.a = 1.

kernel void linearToOklabKernel(
    texture2d<float, access::read>  source [[texture(0)]],
    texture2d<float, access::write> destination [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint dw = destination.get_width();
    uint dh = destination.get_height();
    if (gid.x >= dw || gid.y >= dh) return;
    float3 lin = source.read(gid).rgb;
    float3 lab = linearSRGBToOKLab(lin);
    destination.write(float4(lab, 1.0f), gid);
}

// MARK: - Unsharp mask on OKLab L channel
//
// Computes a 3×3 Gaussian blur of the L channel, then adds back the high-frequency
// detail (original − blur) scaled by `amount`. Operates ONLY on L so chroma is
// untouched — no hue shifts at edges, which is the failure mode of naive RGB unsharp.
// Recommended amount: 0.3 – 0.8.

kernel void unsharpMaskLKernel(
    texture2d<float, access::read>  source [[texture(0)]],
    texture2d<float, access::write> destination [[texture(1)]],
    constant float &amount [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = destination.get_width();
    uint h = destination.get_height();
    if (gid.x >= w || gid.y >= h) return;

    // 3×3 Gaussian: 1 2 1 / 2 4 2 / 1 2 1, normalized by 16.
    const float kernelGauss[9] = {
        1.0f/16.0f, 2.0f/16.0f, 1.0f/16.0f,
        2.0f/16.0f, 4.0f/16.0f, 2.0f/16.0f,
        1.0f/16.0f, 2.0f/16.0f, 1.0f/16.0f
    };
    float L_blur = 0.0f;
    int k = 0;
    for (int dy = -1; dy <= 1; ++dy) {
        int sy = clamp((int)gid.y + dy, 0, (int)h - 1);
        for (int dx = -1; dx <= 1; ++dx) {
            int sx = clamp((int)gid.x + dx, 0, (int)w - 1);
            float L = source.read(uint2((uint)sx, (uint)sy)).r;
            L_blur += L * kernelGauss[k];
            k++;
        }
    }

    float4 here = source.read(gid);
    float L_high = here.r - L_blur;
    float L_new = clamp(here.r + amount * L_high, 0.0f, 1.0f);
    destination.write(float4(L_new, here.g, here.b, here.a), gid);
}

// MARK: - GPU Lloyd k-means (Stage A inner loop)
//
// Three kernels — seed, assign+accumulate (fused), finalize — make up one
// Lloyd iteration. The CPU driver dispatches them in sequence in a single
// command buffer per frame, with a fixed iteration count. This replaces the
// previous CPU loop in `KMeansLab.run` that incurred ~400 M existential
// dispatches per burst (4096 × 256 × 6 × 64). At K=256 with 4096 samples,
// the GPU finishes a full 15-iteration k-means in ~3 ms on iPhone 17 Pro.
//
// Fixed-point accumulation strategy
// ---------------------------------
// Metal global atomics support only `atomic_int` / `atomic_uint`. We scale
// each OKLab channel by 2^16 and atomic-add into int32 bins. Worst-case
// sum: 4096 samples × 65536 ≈ 268 M, well under int32 max (2.1 B).
//
// Buffer layout
// -------------
// centroidsBuf    : 256 × float4    (xyz = OKLab, w unused)
// binsBuf         : 256 × KMeansBin (4 sum atomics + 6 outer-product atomics + count)
// shiftBuf        : single atomic_uint, accumulated Σ‖μ' − μ‖² × 2^16
// assignmentsBuf  : pixels × ushort  (per-pixel cluster index, last-iter wins)
// covariancesBuf  : 256 × 6 floats   (upper triangle of per-cluster Σ: LL, La, Lb, aa, ab, bb)
//
// Outer-product atomics enable per-cluster covariance derivation without
// a CPU pass over the pixel array. Cost: 6 extra atomic adds per pixel
// per Lloyd iteration (negligible). The new `kmeansFinalizeStatsKernel`
// runs ONCE after the Lloyd loop, computes Σ = E[xxᵀ] − μμᵀ from the
// accumulated outer products + final centroids, and writes 6 floats
// per cluster for the host to assemble into simd_float3x3.

struct KMeansBin {
    atomic_int  sum_L;
    atomic_int  sum_a;
    atomic_int  sum_b;
    atomic_uint count;
    // Outer-product accumulators for covariance. Same fixed-point
    // scale (×2^16) as the linear sums. Worst-case |p_i × p_j| ≤ 1,
    // so 4096 × 65536 ≈ 268M — fits in int32 with headroom.
    atomic_int  sum_LL;
    atomic_int  sum_La;
    atomic_int  sum_Lb;
    atomic_int  sum_aa;
    atomic_int  sum_ab;
    atomic_int  sum_bb;
};

// Seed step: write K initial centroids as uniform-stride samples from the
// OKLab tile. The CPU side promises K is a power-of-two divisor of the
// pixel count (256 ≤ 4096), so stride math is exact.
kernel void kmeansSeedKernel(
    texture2d<float, access::read>  tile [[texture(0)]],
    device float4*                  centroids [[buffer(0)]],
    constant uint&                  K [[buffer(1)]],
    uint                            k [[thread_position_in_grid]]
) {
    if (k >= K) return;
    uint side = tile.get_width();
    uint pixels = side * side;
    uint stride = max(1u, pixels / K);
    uint p = (k * stride) % pixels;
    uint x = p % side;
    uint y = p / side;
    float4 lab = tile.read(uint2(x, y));
    centroids[k] = float4(lab.rgb, 0.0f);
}

// Reset step: zero the bins + shift accumulator before each Lloyd iteration.
// Dispatched with max(K, 1) threads so we can reset shift in the same kernel.
kernel void kmeansResetKernel(
    device KMeansBin*    bins [[buffer(0)]],
    device atomic_uint*  shiftFP [[buffer(1)]],
    constant uint&       K [[buffer(2)]],
    uint                 k [[thread_position_in_grid]]
) {
    if (k == 0) {
        atomic_store_explicit(shiftFP, 0u, memory_order_relaxed);
    }
    if (k >= K) return;
    atomic_store_explicit(&bins[k].sum_L, 0, memory_order_relaxed);
    atomic_store_explicit(&bins[k].sum_a, 0, memory_order_relaxed);
    atomic_store_explicit(&bins[k].sum_b, 0, memory_order_relaxed);
    atomic_store_explicit(&bins[k].count, 0u, memory_order_relaxed);
    // Outer-product accumulators for covariance — same zero-reset
    // pattern. The Σ = E[xxᵀ] − μμᵀ math needs a clean slate per
    // iteration, same as the linear sums.
    atomic_store_explicit(&bins[k].sum_LL, 0, memory_order_relaxed);
    atomic_store_explicit(&bins[k].sum_La, 0, memory_order_relaxed);
    atomic_store_explicit(&bins[k].sum_Lb, 0, memory_order_relaxed);
    atomic_store_explicit(&bins[k].sum_aa, 0, memory_order_relaxed);
    atomic_store_explicit(&bins[k].sum_ab, 0, memory_order_relaxed);
    atomic_store_explicit(&bins[k].sum_bb, 0, memory_order_relaxed);
}

// Fused assignment + accumulation. One thread per pixel: find nearest of
// K centroids by squared OKLab distance, atomic-add this pixel into the
// chosen bin. The centroids are pulled into threadgroup memory once per
// threadgroup so the inner loop is cache-resident.
kernel void kmeansAssignAccumulateKernel(
    texture2d<float, access::read>  tile [[texture(0)]],
    device const float4*            centroids [[buffer(0)]],
    device KMeansBin*               bins [[buffer(1)]],
    constant uint&                  K [[buffer(2)]],
    device ushort*                  assignments [[buffer(3)]],
    uint                            gid [[thread_position_in_grid]],
    uint                            tid [[thread_position_in_threadgroup]],
    uint                            tgSize [[threads_per_threadgroup]]
) {
    threadgroup float4 tgCentroids[256];

    // Cooperatively load up to K centroids into threadgroup memory.
    for (uint k = tid; k < K; k += tgSize) {
        tgCentroids[k] = centroids[k];
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    uint side = tile.get_width();
    uint pixels = side * side;
    if (gid >= pixels) return;
    uint x = gid % side;
    uint y = gid / side;
    float3 lab = tile.read(uint2(x, y)).rgb;

    float bestD = INFINITY;
    uint  bestK = 0;
    for (uint k = 0; k < K; ++k) {
        float3 c = tgCentroids[k].xyz;
        float3 d = lab - c;
        float  sq = d.x * d.x + d.y * d.y + d.z * d.z;
        if (sq < bestD) { bestD = sq; bestK = k; }
    }

    // Linear sums (existing).
    int sL = int(round(lab.x * 65536.0f));
    int sA = int(round(lab.y * 65536.0f));
    int sB = int(round(lab.z * 65536.0f));
    atomic_fetch_add_explicit(&bins[bestK].sum_L, sL, memory_order_relaxed);
    atomic_fetch_add_explicit(&bins[bestK].sum_a, sA, memory_order_relaxed);
    atomic_fetch_add_explicit(&bins[bestK].sum_b, sB, memory_order_relaxed);
    atomic_fetch_add_explicit(&bins[bestK].count, 1u,  memory_order_relaxed);

    // Outer-product sums for covariance. Same ×2^16 fixed-point scale.
    // Worst case |p_i × p_j| ≤ 1; 4096 × 65536 ≈ 268M fits in int32.
    int sLL = int(round(lab.x * lab.x * 65536.0f));
    int sLa = int(round(lab.x * lab.y * 65536.0f));
    int sLb = int(round(lab.x * lab.z * 65536.0f));
    int saa = int(round(lab.y * lab.y * 65536.0f));
    int sab = int(round(lab.y * lab.z * 65536.0f));
    int sbb = int(round(lab.z * lab.z * 65536.0f));
    atomic_fetch_add_explicit(&bins[bestK].sum_LL, sLL, memory_order_relaxed);
    atomic_fetch_add_explicit(&bins[bestK].sum_La, sLa, memory_order_relaxed);
    atomic_fetch_add_explicit(&bins[bestK].sum_Lb, sLb, memory_order_relaxed);
    atomic_fetch_add_explicit(&bins[bestK].sum_aa, saa, memory_order_relaxed);
    atomic_fetch_add_explicit(&bins[bestK].sum_ab, sab, memory_order_relaxed);
    atomic_fetch_add_explicit(&bins[bestK].sum_bb, sbb, memory_order_relaxed);

    // Per-pixel assignment — last-iter wins (each Lloyd iter overwrites
    // the same slot). The Swift caller reads `assignments` after the
    // final iteration; intermediate values are never observed.
    assignments[gid] = ushort(bestK);
}

// Finalize: K threads. For each centroid k, divide the bin sum by the
// bin count (or keep the old centroid if count is zero — the
// canonical "empty cluster" handling, matching KMeansLab.swift), then
// accumulate ‖μ' − μ‖² (in fixed-point) into the shift sum.
kernel void kmeansFinalizeKernel(
    device KMeansBin*    bins [[buffer(0)]],
    device float4*       centroids [[buffer(1)]],
    device atomic_uint*  shiftFP [[buffer(2)]],
    constant uint&       K [[buffer(3)]],
    uint                 k [[thread_position_in_grid]]
) {
    if (k >= K) return;
    uint count = atomic_load_explicit(&bins[k].count, memory_order_relaxed);
    float4 oldC = centroids[k];
    float4 newC;
    if (count == 0u) {
        newC = oldC;
    } else {
        int sL = atomic_load_explicit(&bins[k].sum_L, memory_order_relaxed);
        int sA = atomic_load_explicit(&bins[k].sum_a, memory_order_relaxed);
        int sB = atomic_load_explicit(&bins[k].sum_b, memory_order_relaxed);
        float inv = 1.0f / (65536.0f * float(count));
        newC = float4(float(sL) * inv, float(sA) * inv, float(sB) * inv, 0.0f);
    }
    float3 delta = newC.xyz - oldC.xyz;
    float distSq = delta.x * delta.x + delta.y * delta.y + delta.z * delta.z;
    // Scale the shift sum so 1.0 OKLab unit² of total movement ≈ 65536.
    // The driver decodes the readback the same way.
    uint distFP = uint(clamp(distSq, 0.0f, 64.0f) * 65536.0f);
    atomic_fetch_add_explicit(shiftFP, distFP, memory_order_relaxed);
    centroids[k] = newC;
}

// Finalize statistics: K threads, one per cluster. Reads the outer-product
// atomics + linear sums accumulated during the LAST Lloyd iteration and
// computes per-cluster sample covariance:
//
//   Σ = E[xxᵀ] − μμᵀ
//
// where μ is the cluster mean (centroid) and E[xxᵀ] is the average outer
// product over the assigned pixels. Σ is symmetric 3×3 PSD — we write
// only the upper triangle (6 floats per cluster: LL, La, Lb, aa, ab, bb)
// to halve the buffer footprint and skip redundant reads. The host
// assembles a `simd_float3x3` from these 6 values.
//
// Empty-cluster convention: writes (1e-6, 0, 0, 1e-6, 0, 1e-6) — a tiny
// isotropic Σ. Consumers MUST check `count > 0` before treating it as
// meaningful (the value is just numerically safe; not statistically real).
//
// Output layout: covariances[k * 6 + 0..5] = (LL, La, Lb, aa, ab, bb).
kernel void kmeansFinalizeStatsKernel(
    device const KMeansBin* bins        [[buffer(0)]],
    device float*           covariances [[buffer(1)]],
    constant uint&          K           [[buffer(2)]],
    uint                    k           [[thread_position_in_grid]]
) {
    if (k >= K) return;
    uint count = atomic_load_explicit(&bins[k].count, memory_order_relaxed);
    uint base = k * 6u;
    if (count == 0u) {
        covariances[base + 0u] = 1e-6f;
        covariances[base + 1u] = 0.0f;
        covariances[base + 2u] = 0.0f;
        covariances[base + 3u] = 1e-6f;
        covariances[base + 4u] = 0.0f;
        covariances[base + 5u] = 1e-6f;
        return;
    }
    float inv = 1.0f / (65536.0f * float(count));
    float mL = float(atomic_load_explicit(&bins[k].sum_L,  memory_order_relaxed)) * inv;
    float ma = float(atomic_load_explicit(&bins[k].sum_a,  memory_order_relaxed)) * inv;
    float mb = float(atomic_load_explicit(&bins[k].sum_b,  memory_order_relaxed)) * inv;
    float ELL = float(atomic_load_explicit(&bins[k].sum_LL, memory_order_relaxed)) * inv;
    float ELa = float(atomic_load_explicit(&bins[k].sum_La, memory_order_relaxed)) * inv;
    float ELb = float(atomic_load_explicit(&bins[k].sum_Lb, memory_order_relaxed)) * inv;
    float Eaa = float(atomic_load_explicit(&bins[k].sum_aa, memory_order_relaxed)) * inv;
    float Eab = float(atomic_load_explicit(&bins[k].sum_ab, memory_order_relaxed)) * inv;
    float Ebb = float(atomic_load_explicit(&bins[k].sum_bb, memory_order_relaxed)) * inv;
    covariances[base + 0u] = ELL - mL * mL;
    covariances[base + 1u] = ELa - mL * ma;
    covariances[base + 2u] = ELb - mL * mb;
    covariances[base + 3u] = Eaa - ma * ma;
    covariances[base + 4u] = Eab - ma * mb;
    covariances[base + 5u] = Ebb - mb * mb;
}

// MARK: - Voxel cube raymarch (Review .voxel3D mode)
//
// Orthographic DDA (Amanatides–Woo) over a 64³ R8Uint index volume. Depth-slice
// z shows frame f(z) = (cursor−63+z) mod 64, so the near face (z=63) is the
// current frame and earlier frames recede — face-on the cube is byte-identical
// to the 2D GIF, orbit blooms it. Per-(t,k) provenance is packed in the palette
// texture's alpha (0=degenerate→air, 1=extracted, 2=split→one dark step).
// See docs/SIXFOUR-VOXEL-CUBE.md. Mirrors Swift VoxelUniforms / Renderer.orbit.

struct VoxelUniforms {
    float yaw;
    float pitch;
    float2 resolution;
    int frame;
    int tLo;
    int tHi;
    int lumaFloor;
    float halfSpan;
    int provMode;     // 0 = all, 1 = extracted only, 2 = split only
    int brushedIndex; // shared cross-view brush: palette index to highlight, -1 = none
    int brushMode;    // brush set per radix: 0 single (16²) / 1 quad (4⁴) / 2 σ-pair (2⁸)
    int isolate;      // FRAME-ISOLATION (palette study): 0 off / 1 on — focus frame opaque, rest ghosted
    float ghostAlpha; // alpha of non-focus slices in isolate mode (0 = pure isolation, ~0.12 = ghost)
};

// Cube/palette dimensions — the kernel's single home for these magic numbers, mirroring
// the shape contract (SixFourShape T=W=64, K=256; Swift routes VoxelCubeData.side/
// frameCount/paletteCount). Keep in lockstep with that contract.
#define S4_SIDE   64    // cube edge in voxels (x,y)
#define S4_FRAMES 64    // depth/time slices (T)
#define S4_K      256   // palette colours per frame (K)

// Camera basis for an orbit: yaw about world-Y, then pitch about the camera-RIGHT
// axis (the yaw-rotated world-X). This keeps the projection ORTHONORMAL and, at the
// 8-bit isometric "hero" pose yaw=45°/pitch=30°, makes world-X and world-Z each
// project to a screen slope of exactly 1:2 — the canonical 2:1 DIMETRIC projection
// of 8-bit games (sin30° = 0.5 ⇒ floor edges step 2 px across : 1 down). At
// yaw=pitch=0 it is the identity, so the flat rest pose stays byte-1:1 with the 2D
// GIF (RULE-CUBE-2D-IDENTITY). Mirrored by Swift VoxelIso.orbit.
static inline float3 voxelOrbit(float3 v, float yaw, float pitch) {
    float cy = cos(yaw), sy = sin(yaw);
    float3 a = float3(cy * v.x + sy * v.z, v.y, -sy * v.x + cy * v.z);  // yaw about world Y
    float3 r = float3(cy, 0.0, -sy);                                    // camera-right axis
    float cp = cos(pitch), sp = sin(pitch);
    return a * cp + cross(r, a) * sp + r * dot(r, a) * (1.0 - cp);      // Rodrigues about r
}

static inline float2 voxelBoxHit(float3 o, float3 d) {
    float3 inv = 1.0 / d;
    float3 t0 = (float3(0.0) - o) * inv;
    float3 t1 = (float3(float(S4_SIDE)) - o) * inv;
    float3 tmin = min(t0, t1), tmax = max(t0, t1);
    return float2(max(max(max(tmin.x, tmin.y), tmin.z), 0.0),
                  min(min(tmax.x, tmax.y), tmax.z));
}

kernel void voxel_raymarch(
    texture3d<uint,  access::read>   indexTex   [[texture(0)]],
    texture2d<float, access::sample> paletteTex [[texture(1)]],
    texture2d<float, access::write>  outTex     [[texture(2)]],
    constant VoxelUniforms& U                   [[buffer(0)]],
    uint2 gid                                   [[thread_position_in_grid]])
{
    if (gid.x >= (uint)U.resolution.x || gid.y >= (uint)U.resolution.y) return;

    float4 bg = float4(0.0, 0.0, 0.0, 1.0);

    float side = min(U.resolution.x, U.resolution.y);
    float2 off = (U.resolution - side) * 0.5;
    float2 px = float2(gid) + 0.5 - off;
    if (px.x < 0.0 || px.y < 0.0 || px.x >= side || px.y >= side) { outTex.write(bg, gid); return; }

    // 8-BIT PIXELATION: snap to a fixed ART_RES×ART_RES art-pixel grid so the cube
    // renders as CHUNKY pixels (and the 2:1 dimetric edges resolve as visible
    // stairsteps), then nearest-upscales to the drawable. ART_RES = 128 = 2 art-pixels
    // per voxel (64-wide face) — an EXACT multiple, so each voxel maps to 2 aligned
    // art-pixels of its single constant colour and the flat rest pose stays byte-1:1
    // with the 2D GIF (RULE-CUBE-2D-IDENTITY). All drawable pixels inside one art cell
    // share its centre's raymarch result, giving hard 8-bit edges at any resolution.
    constexpr float ART_RES = 128.0;
    float artPx = side / ART_RES;
    float2 cell = floor(px / artPx);
    float2 uv = (cell + 0.5) * artPx / side;

    float2 plane = (uv - 0.5) * 2.0 * U.halfSpan;
    float3 Xb = voxelOrbit(float3(1, 0, 0), U.yaw, U.pitch);
    float3 Yb = voxelOrbit(float3(0, 1, 0), U.yaw, U.pitch);
    float3 Zb = voxelOrbit(float3(0, 0, 1), U.yaw, U.pitch);
    float3 center = float3(32.0);
    float3 o = center + plane.x * Xb + plane.y * Yb + 200.0 * Zb;
    float3 d = -Zb;

    float2 hit = voxelBoxHit(o, d);
    if (hit.y < hit.x) { outTex.write(bg, gid); return; }

    float3 p = o + d * (hit.x + 1e-3);
    int3 voxel = int3(floor(p));
    int3 stp = int3(sign(d));
    float3 inv = 1.0 / d;
    float3 tMax = (float3(voxel) + max(float3(stp), float3(0.0)) - o) * inv;
    float3 tDelta = abs(inv);

    int tLo = clamp(U.tLo, 0, S4_FRAMES - 1);
    int tHi = clamp(U.tHi, 0, S4_FRAMES - 1);
    int cursor = clamp(U.frame, 0, S4_FRAMES - 1);

    // Front-to-back alpha accumulation. Outside isolate mode every voxel is opaque
    // (a = 1), so the first hit sets aAccum = 1 and we break — IDENTICAL to the old
    // first-hit raymarch (RULE-CUBE-2D-IDENTITY intact). In isolate mode the focus
    // frame stays opaque and other slices get ghostAlpha, so the user sees one frame's
    // palette floating with the rest transparent (design §0.3, owner-signed-off).
    float3 accum = float3(0.0);
    float aAccum = 0.0;
    int axis = -1;

    // REST-POSE IDENTITY (RULE-CUBE-2D-IDENTITY): at the flat pose every depth cue
    // and every cull becomes a pure no-op, so the near face (z=63) renders frame
    // `cursor` with the EXACT palette colour — byte-1:1 with the 2D GIF hero. The
    // cube may diverge only once orbited (flat == false). See VoxelRestPoseIdentityTests.
    bool flat = (U.yaw * U.yaw + U.pitch * U.pitch) < 1e-6;

    for (int i = 0; i < 220; ++i) {
        bool inside = voxel.x >= 0 && voxel.x < S4_SIDE &&
                      voxel.y >= 0 && voxel.y < S4_SIDE &&
                      voxel.z >= 0 && voxel.z < S4_FRAMES;
        if (!inside) break;

        // Depth-band cull is flat-gated: at rest the near face (z=63) must always
        // render, regardless of a seeded trail band, or the front face would show a
        // different frame than the 2D GIF.
        // Isolate mode bypasses the trail-depth band (the focus frame must always be
        // reachable); the per-voxel alpha below does the hiding instead.
        if (flat || U.isolate != 0 || (voxel.z >= tLo && voxel.z <= tHi)) {
            int fz = ((cursor - (S4_FRAMES - 1) + voxel.z) % S4_FRAMES + S4_FRAMES) % S4_FRAMES;
            uint k = indexTex.read(uint3(uint(voxel.x), uint(voxel.y), uint(fz))).r;
            constexpr sampler s(coord::normalized, filter::nearest, address::clamp_to_edge);
            float2 pc = float2(float(k) + 0.5, float(fz) + 0.5) / float2(float(S4_K), float(S4_FRAMES));
            float4 rgba = paletteTex.sample(s, pc);

            // Provenance (palette alpha): 0 degenerate / 1 extracted / 2 split.
            int prov = int(round(rgba.a * 255.0));
            // Air/provenance cull flat-gated: at rest every slot the 2D GIF shows
            // must render (the GIF colour table is the same sRGB8 palette).
            bool air = !flat && ( (prov == 0)
                    || (U.provMode == 1 && prov != 1)
                    || (U.provMode == 2 && prov != 2) );

            if (!air) {
                float luma255 = (0.2126 * rgba.r + 0.7152 * rgba.g + 0.0722 * rgba.b) * 255.0;
                if (flat || luma255 >= float(U.lumaFloor)) {
                    // At rest: no face shading, no split darkening (the 2D GIF has
                    // neither). axis == -1 on the first hit already gives face=1.0;
                    // the flat guard makes both cues provably inert.
                    float face = flat ? 1.0 : ((axis == 0) ? 0.82 : (axis == 2 ? 0.90 : 1.0));
                    float split = (flat || prov != 2) ? 1.0 : 0.6;   // split = one discrete dark step
                    // Cross-view brush: when orbited (!flat), the brushed palette
                    // index keeps full colour and every other voxel dims by ONE
                    // discrete opaque step (GRID Law #2 — never alpha). Gated !flat so
                    // the flat 2D rest pose is never disturbed (RULE-CUBE-2D-IDENTITY).
                    // Cross-view brush set per radix (BrushSet.kernelHit): single
                    // (16²), the opponent quad sharing k&~3 (4⁴), or the σ-pair k^1
                    // (2⁸). The matched set keeps full colour; the rest dim by one
                    // discrete opaque step. Gated !flat so the 2D rest pose is exact.
                    int bk = U.brushedIndex;
                    bool hit = (int(k) == bk);
                    if (U.brushMode == 2)      hit = hit || (int(k) == (bk ^ 1));
                    else if (U.brushMode == 1) hit = hit || ((int(k) & ~3) == (bk & ~3));
                    float brush = (!flat && bk >= 0 && !hit) ? 0.28 : 1.0;

                    // Per-voxel alpha: opaque everywhere unless isolating, where only the
                    // FOCUS frame (cursor, the near face) stays opaque and the rest fade
                    // to ghostAlpha. a == 1 makes the compositing collapse to first-hit.
                    float a = 1.0;
                    if (U.isolate != 0 && !flat) {
                        a = (fz == cursor) ? 1.0 : clamp(U.ghostAlpha, 0.0, 1.0);
                    }
                    if (a > 0.0) {
                        float3 rgb = rgba.rgb * face * split * brush;
                        accum += (1.0 - aAccum) * a * rgb;       // front-to-back over
                        aAccum += (1.0 - aAccum) * a;
                        if (aAccum >= 0.999) break;              // fully opaque → done
                    }
                }
            }
        }

        if (tMax.x < tMax.y) {
            if (tMax.x < tMax.z) { voxel.x += stp.x; tMax.x += tDelta.x; axis = 0; }
            else                 { voxel.z += stp.z; tMax.z += tDelta.z; axis = 2; }
        } else {
            if (tMax.y < tMax.z) { voxel.y += stp.y; tMax.y += tDelta.y; axis = 1; }
            else                 { voxel.z += stp.z; tMax.z += tDelta.z; axis = 2; }
        }
    }

    // Composite over the black background (accum is premultiplied foreground).
    outTex.write(float4(accum, 1.0), gid);
}
