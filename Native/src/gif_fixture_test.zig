//! Cross-language GIF golden fixture test (Stage 0 scaffold).
//!
//! The plan (stateful-spinning-lemon.md, Tier B) has a Haskell driver emit, into
//! the `fixture_dir` build-option path, a golden burst: the linear-sRGB half
//! input plus the byte-exact `golden.gif` the Haskell spec produces. This test
//! will load the SAME input, run `s4_gif_encode_burst`, and assert the produced
//! GIF byte stream equals `golden.gif` exactly — pinning the Zig core to the
//! Haskell source of truth the way fixture_test.zig pins the S4LN parser.
//!
//! Until the GIF/quantize kernels land (Stages 2 & 5) the golden does not exist,
//! so this skips via error.SkipZigTest — never a vacuous pass, never a red tree.

const std = @import("std");
const kernels = @import("kernels.zig");
const build_options = @import("build_options");

fn readFileAlloc(alloc: std.mem.Allocator, dir: []const u8, name: []const u8) ![]u8 {
    const io = std.testing.io;
    const path = try std.fs.path.join(alloc, &.{ dir, name });
    defer alloc.free(path);
    return std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .unlimited) catch
        return error.SkipZigTest;
}

test "cross-language: Haskell golden GIF reproduced byte-exactly by the Zig core" {
    const alloc = std.testing.allocator;
    const dir = build_options.fixture_dir;

    // golden.gif is the byte-exact GIF the Haskell driver emits for a fixed burst.
    const golden = readFileAlloc(alloc, dir, "golden.gif") catch |e| {
        if (e == error.SkipZigTest) {
            std.debug.print(
                "\n  [skip] golden.gif not found in '{s}'; GIF golden lands in Stage 2/6\n",
                .{dir},
            );
            return error.SkipZigTest;
        }
        return e;
    };
    defer alloc.free(golden);

    // The matching input (linear-sRGB Float16 halfs, T·H·W·3) the golden was made
    // from. Absent today; once present, the body below runs the real comparison.
    const in_halfs = readFileAlloc(alloc, dir, "golden_input.halfs") catch
        return error.SkipZigTest;
    defer alloc.free(in_halfs);

    // Stage 0: the encoder is a stub, so reaching here with a real golden would
    // (correctly) fail. The golden does not exist yet, so we never get here.
    const bound = kernels.s4_gif_encode_burst_bound(kernels.FRAME_COUNT, kernels.SIDE, kernels.K);
    const out = try alloc.alloc(u8, bound);
    defer alloc.free(out);
    const scratch_bytes = kernels.s4_burst_scratch_bytes(kernels.FRAME_COUNT, kernels.SIDE, kernels.K);
    const scratch = try alloc.alloc(u8, scratch_bytes);
    defer alloc.free(scratch);

    var out_len: usize = 0;
    const rc = kernels.s4_gif_encode_burst(
        @ptrCast(@alignCast(in_halfs.ptr)),
        kernels.FRAME_COUNT,
        kernels.SIDE,
        kernels.K,
        0, // input_space = linear-sRGB halfs
        15, // lloyd_iters (pinned by spec constant)
        2, // dither_mode = blue-noise spatiotemporal
        0, // serpentine
        null, // stbn_mask (filled when the dither stage lands)
        5, // frame_delay_cs
        null,
        0,
        out.ptr,
        out.len,
        &out_len,
        scratch.ptr,
        scratch.len,
    );
    try std.testing.expectEqual(kernels.RC_OK, rc);
    try std.testing.expectEqualSlices(u8, golden, out[0..out_len]);
}
