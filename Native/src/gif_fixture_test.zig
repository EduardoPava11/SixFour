//! Cross-language GIF golden fixture test — the monolithic burst entrypoint.
//!
//! The Haskell driver (spec-fixtures, app/Fixtures.hs) emits into `fixture_dir`:
//!   * golden_input.halfs — a binary16 burst (T·H·W·3, exact dyadic halfs), and
//!   * golden.gif         — the byte-exact GIF the spec's COMPOSED fold produces
//!                          (widen→oklab→quantize→dither(FS)→palette→assemble).
//! This loads the SAME input, runs `s4_gif_encode_burst` (the single-call fold),
//! and asserts the produced bytes equal golden.gif EXACTLY — pinning the
//! monolithic entrypoint to the Haskell source of truth (the per-stage kernels
//! are already pinned individually; this pins their COMPOSITION).
//!
//! Small dims (2×8²×4) — composition correctness is size-independent. Floyd-
//! Steinberg dither (mode 0) so no STBN mask is needed. If the goldens are absent
//! (driver not run) the test skips — never a vacuous pass, never a red tree.

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

    // Match the Haskell golden's burst shape (app/Fixtures.hs burst* constants).
    const FC: i32 = 2;
    const SD: i32 = 32;
    const KK: i32 = 256;

    const bound = kernels.s4_gif_encode_burst_bound(FC, SD, KK);
    const out = try alloc.alloc(u8, bound);
    defer alloc.free(out);
    const scratch_bytes = kernels.s4_burst_scratch_bytes(FC, SD, KK);
    const scratch = try alloc.alloc(u8, scratch_bytes);
    defer alloc.free(scratch);

    var out_len: usize = 0;
    const rc = kernels.s4_gif_encode_burst(
        @ptrCast(@alignCast(in_halfs.ptr)),
        FC,
        SD,
        KK,
        0, // input_space = linear-sRGB halfs
        15, // lloyd_iters (matches burstLloyd)
        0, // dither_mode = Floyd-Steinberg (no STBN mask needed)
        0, // serpentine
        null, // stbn_mask (FS ignores it)
        5, // frame_delay_cs (20 fps)
        null, // comment
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
