#include <metal_stdlib>
using namespace metal;

// Wu (1992) 3-D moment histogram — the genuinely data-parallel stage of the
// recursive-bipartition quantizer. One thread per pixel quantizes its OKLab
// value to a 32³ cell and atomically accumulates 10 moments. The CPU then does
// the inherently-sequential prefix-sum + greedy box-split (see WuQuantizer.swift
// / WuPalettePipeline.swift).
//
// Moments are stored as 10 separate fixed-point int buffers (×2^16, matching the
// k-means KMeansBin convention), one entry per cell, indexed [iL*N*N + ia*N + ib]
// — mirroring WuQuantizer's 10 Double tables so readback parity is trivial.
// `cellOfPixel` is written per pixel; it is integer-exact vs the CPU because both
// quantize the identical Float32 OKLab values, so the parity gap is confined to
// the fixed-point moment sums.

constant int   WU_N     = 32;        // bins per axis (must match WuQuantizer.binsPerAxis)
constant float WU_SCALE = 65536.0;   // 2^16 fixed-point (must match WuPalettePipeline.fixedPointScale)

inline int wuQuantizeL(float v) {
    int i = int(v * float(WU_N));
    return min(max(0, i), WU_N - 1);
}
inline int wuQuantizeAB(float v) {
    int i = int((v + 0.5) * float(WU_N));
    return min(max(0, i), WU_N - 1);
}

kernel void wuHistogramKernel(
    device const float4*  pixels      [[buffer(0)]],   // xyz = OKLab (Float32), w unused
    device atomic_int*    histT       [[buffer(1)]],   // count (unscaled)
    device atomic_int*    sumLT       [[buffer(2)]],
    device atomic_int*    sumAT       [[buffer(3)]],
    device atomic_int*    sumBT       [[buffer(4)]],
    device atomic_int*    sumLLT      [[buffer(5)]],
    device atomic_int*    sumAAT      [[buffer(6)]],
    device atomic_int*    sumBBT      [[buffer(7)]],
    device atomic_int*    sumLAT      [[buffer(8)]],
    device atomic_int*    sumLBT      [[buffer(9)]],
    device atomic_int*    sumABT      [[buffer(10)]],
    device uint*          cellOfPixel [[buffer(11)]],
    constant uint&        pixelCount  [[buffer(12)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= pixelCount) { return; }
    float3 lab = pixels[gid].xyz;
    int iL = wuQuantizeL(lab.x);
    int ia = wuQuantizeAB(lab.y);
    int ib = wuQuantizeAB(lab.z);
    int cell = iL * WU_N * WU_N + ia * WU_N + ib;
    cellOfPixel[gid] = uint(cell);

    float L = lab.x, A = lab.y, B = lab.z;
    atomic_fetch_add_explicit(&histT[cell],  1,                            memory_order_relaxed);
    atomic_fetch_add_explicit(&sumLT[cell],  int(round(L * WU_SCALE)),     memory_order_relaxed);
    atomic_fetch_add_explicit(&sumAT[cell],  int(round(A * WU_SCALE)),     memory_order_relaxed);
    atomic_fetch_add_explicit(&sumBT[cell],  int(round(B * WU_SCALE)),     memory_order_relaxed);
    atomic_fetch_add_explicit(&sumLLT[cell], int(round(L * L * WU_SCALE)), memory_order_relaxed);
    atomic_fetch_add_explicit(&sumAAT[cell], int(round(A * A * WU_SCALE)), memory_order_relaxed);
    atomic_fetch_add_explicit(&sumBBT[cell], int(round(B * B * WU_SCALE)), memory_order_relaxed);
    atomic_fetch_add_explicit(&sumLAT[cell], int(round(L * A * WU_SCALE)), memory_order_relaxed);
    atomic_fetch_add_explicit(&sumLBT[cell], int(round(L * B * WU_SCALE)), memory_order_relaxed);
    atomic_fetch_add_explicit(&sumABT[cell], int(round(A * B * WU_SCALE)), memory_order_relaxed);
}
