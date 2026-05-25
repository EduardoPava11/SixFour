#include <metal_stdlib>
using namespace metal;

// Per-cluster statistics from CPU-provided assignments — the GPU stage of the
// octree hybrid pipeline. Octree's insert + greedy merge are inherently
// sequential and run on CPU (OctreeQuantizer.assign); this kernel is the
// parallel "second pass" that turns (pixels, assignments) into per-cluster
// moments. One thread per pixel atomically accumulates 10 fixed-point (×2^16)
// moments into its cluster's bin.
//
// Bin layout: K clusters × 10 ints, indexed [k*10 + field]:
//   0 = count (unscaled), 1..3 = sumL/A/B, 4..6 = sumLL/AA/BB, 7..9 = sumLA/LB/AB.
// Because the partition (assignments) is identical to the CPU oracle, parity
// is just fixed-point vs Double on these sums — no greedy-split divergence.

constant float OCT_SCALE = 65536.0;  // must match OctreePalettePipeline.fixedPointScale

kernel void octreeStatsKernel(
    device const float4* pixels      [[buffer(0)]],   // xyz = OKLab (Float32)
    device const ushort* assignments [[buffer(1)]],   // per-pixel cluster slot
    device atomic_int*   bins        [[buffer(2)]],   // K*10 ints
    constant uint&       pixelCount  [[buffer(3)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= pixelCount) { return; }
    int base = int(assignments[gid]) * 10;
    float3 lab = pixels[gid].xyz;
    float L = lab.x, A = lab.y, B = lab.z;
    atomic_fetch_add_explicit(&bins[base + 0], 1,                            memory_order_relaxed);
    atomic_fetch_add_explicit(&bins[base + 1], int(round(L * OCT_SCALE)),     memory_order_relaxed);
    atomic_fetch_add_explicit(&bins[base + 2], int(round(A * OCT_SCALE)),     memory_order_relaxed);
    atomic_fetch_add_explicit(&bins[base + 3], int(round(B * OCT_SCALE)),     memory_order_relaxed);
    atomic_fetch_add_explicit(&bins[base + 4], int(round(L * L * OCT_SCALE)), memory_order_relaxed);
    atomic_fetch_add_explicit(&bins[base + 5], int(round(A * A * OCT_SCALE)), memory_order_relaxed);
    atomic_fetch_add_explicit(&bins[base + 6], int(round(B * B * OCT_SCALE)), memory_order_relaxed);
    atomic_fetch_add_explicit(&bins[base + 7], int(round(L * A * OCT_SCALE)), memory_order_relaxed);
    atomic_fetch_add_explicit(&bins[base + 8], int(round(L * B * OCT_SCALE)), memory_order_relaxed);
    atomic_fetch_add_explicit(&bins[base + 9], int(round(A * B * OCT_SCALE)), memory_order_relaxed);
}
