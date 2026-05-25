#include <metal_stdlib>
using namespace metal;

/// Blue-noise (ordered) palette assignment — the parallel GPU counterpart of
/// `Dither.blueNoiseSIMD`. One thread per pixel; no inter-pixel dependency
/// (that's what makes it GPU-eligible, unlike sequential error diffusion).
///
/// Each thread finds its pixel's two nearest centroids, then picks between
/// them by where the pixel sits on the c0→c1 axis (`s ∈ [0,1]`) versus the
/// per-voxel blue-noise threshold. Mirrors the CPU logic bit-for-bit modulo
/// float rounding (the parity test compares reconstruction MSE).
///
/// Layout note: Metal `float3` and Swift `SIMD3<Float>` are both 16-byte
/// stride/aligned, so pixel/centroid buffers upload as `[SIMD3<Float>]`
/// directly with no packing.
kernel void blueNoiseAssignKernel(
    device const float3 *pixels      [[buffer(0)]],
    device const float3 *centroids   [[buffer(1)]],
    device const uchar  *thresholds  [[buffer(2)]],
    device uchar        *out         [[buffer(3)]],
    constant uint       &K           [[buffer(4)]],
    constant uint       &N           [[buffer(5)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= N) { return; }
    float3 p = pixels[gid];

    // Two nearest centroids (smallest squared distances).
    float d0 = INFINITY, d1 = INFINITY;
    uint i0 = 0, i1 = 0;
    for (uint k = 0; k < K; ++k) {
        float3 d = centroids[k] - p;
        float dd = dot(d, d);
        if (dd < d0) { d1 = d0; i1 = i0; d0 = dd; i0 = k; }
        else if (dd < d1) { d1 = dd; i1 = k; }
    }

    if (i0 == i1) { out[gid] = uchar(i0); return; }

    // Position of p along c0→c1, clamped to [0,1].
    float3 c0 = centroids[i0];
    float3 c1 = centroids[i1];
    float3 axis = c1 - c0;
    float denom = dot(axis, axis);
    float s = denom > 0.0 ? clamp(dot(p - c0, axis) / denom, 0.0, 1.0) : 0.0;

    float t = (float(thresholds[gid]) + 0.5) / 256.0;
    out[gid] = uchar(s > t ? i1 : i0);
}
