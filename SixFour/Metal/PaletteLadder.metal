#include <metal_stdlib>
using namespace metal;

/// GIF89a-camera color head, GPU path — the parallel counterpart of the Zig
/// floor `s4_pool_sums_bgra8` (palette16.zig). ONE THREAD PER BIN, each
/// accumulating its q×q block SEQUENTIALLY in registers: no atomics, no
/// threadgroup reduction, no float — a fixed accumulation order over integer
/// adds, so the output is BYTE-IDENTICAL to the Zig kernel by construction
/// (the parity test in ColorHeadTests compares them u64-for-u64 via u32).
///
/// Reads the CVPixelBuffer's raw 32BGRA bytes as a device buffer (memory
/// order B,G,R,A; rows `stride` bytes apart) — deliberately NOT a texture, so
/// no unorm→float conversion ever touches the bytes. Sums fit u32 for any
/// bin up to 4096×4096 px (255·2^24 < 2^32); the Swift side widens to the
/// u64 transitive carrier.
///
/// This kernel is throughput plumbing, not authority: the Zig kernel is the
/// deterministic floor, and any Metal/Zig mismatch is a bug in THIS file.

struct P16Params {
    uint stride;   // bytes per row
    uint x0;       // window origin (pixels)
    uint y0;
    uint side;     // window side (pixels)
    uint outSide;  // bins per axis (16 / 32 / 64)
};

kernel void p16PoolSumsBGRA(
    device const uchar *bgra   [[buffer(0)]],
    constant P16Params &p      [[buffer(1)]],
    device uint        *sums   [[buffer(2)]],  // [outSide*outSide*3], R,G,B per bin
    uint gid [[thread_position_in_grid]])
{
    const uint bins = p.outSide * p.outSide;
    if (gid >= bins) { return; }
    const uint q  = p.side / p.outSide;   // bin side in pixels
    const uint bx = gid % p.outSide;
    const uint by = gid / p.outSide;

    uint r = 0, g = 0, b = 0;
    for (uint dy = 0; dy < q; dy++) {
        const uint row = (p.y0 + by * q + dy) * p.stride;
        for (uint dx = 0; dx < q; dx++) {
            const uint px = row + (p.x0 + (bx * q + dx)) * 4;
            b += bgra[px];
            g += bgra[px + 1];
            r += bgra[px + 2];
        }
    }
    sums[gid * 3]     = r;
    sums[gid * 3 + 1] = g;
    sums[gid * 3 + 2] = b;
}
