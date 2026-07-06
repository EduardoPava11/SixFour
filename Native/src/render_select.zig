//! THE SELECT RENDER (rung 1 of The Loom) — the byte-exact Zig twin of
//! Spec.RenderSelect. DEPENDENCY-FREE: imports nothing, pure integer, C ABI,
//! i32 rc (0 == ok), caller owns all memory. Host-testable via
//! render_select_test.zig.
//!
//! Given THREE INDEPENDENT volumes — V16 (side/4), V32 (side/2), V64 (side) —
//! and a per-region depth field (one depth 0/1/2 per 4×4×4 region = the 16³
//! paint grid), fill the `side`³ output so each region shows its CHOSEN scale's
//! OWN measurement, block-replicated on the shared 4:2:1 clock (a depth-0 voxel
//! is a 4×4×4 spacetime block of the coarse read; depth-1 a 2×2×2 of the mid;
//! depth-2 a single fine voxel).
//!
//! SELECT, NOT POOL (the independence-preserving distinction): this reads V_d
//! DIRECTLY — a coarse region is the long-exposure measurement itself, untouched
//! by V64 (Spec.lawSelectReadsChosenSourceOnly). It never pools the fine volume,
//! so the coarse pixels stay what the outside world gave them. `side` is the
//! device output (64 in the app; the golden uses 8 to match the spec exactly);
//! it must be a positive multiple of 4.

const RC_OK: i32 = 0;
const RC_BAD_ARGS: i32 = 1;

inline fn clampDepth(d: i32) i32 {
    return if (d < 0) 0 else if (d > 2) 2 else d;
}

/// The spacetime block a depth-d region replicates: 4 (V16), 2 (V32), 1 (V64).
inline fn blockSide(d: i32) usize {
    return switch (d) {
        0 => 4,
        1 => 2,
        else => 1,
    };
}

/// Fill `out[side^3]` by per-region select from the three independent volumes.
/// `v16` is (side/4)³, `v32` is (side/2)³, `v64` is side³; `depth` is one value
/// per 4×4×4 region, region-major over the (side/4)³ region grid.
pub export fn s4_render_select(
    out: [*]i32,
    v16: [*]const i32,
    v32: [*]const i32,
    v64: [*]const i32,
    depth: [*]const i32,
    side: i32,
) i32 {
    if (side < 4 or @mod(side, 4) != 0) return RC_BAD_ARGS;
    const n: usize = @intCast(side);
    const rgs: usize = n / 4; // region grid side (= the 16³ paint grid at device scale)

    var t: usize = 0;
    while (t < n) : (t += 1) {
        var y: usize = 0;
        while (y < n) : (y += 1) {
            var x: usize = 0;
            while (x < n) : (x += 1) {
                const region = ((t / 4) * rgs + (y / 4)) * rgs + (x / 4);
                const d = clampDepth(depth[region]);
                const b = blockSide(d);
                const src_side = n / b;
                const si = ((t / b) * src_side + (y / b)) * src_side + (x / b);
                out[(t * n + y) * n + x] = switch (d) {
                    0 => v16[si],
                    1 => v32[si],
                    else => v64[si],
                };
            }
        }
    }
    return RC_OK;
}
