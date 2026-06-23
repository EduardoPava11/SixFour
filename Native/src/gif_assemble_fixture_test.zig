//! Cross-language GIF-assembler golden fixture test.
//!
//! `spec-fixtures` (Haskell, SixFour.Gen.GifWire — itself the byte-faithful port
//! of GIFEncoder.swift) writes a golden burst: gif_golden_indices.bin (T·P u8),
//! gif_golden_palettes.bin (T·K·3 sRGB8), gif_golden.json (shape + comment), and
//! gif_golden.gif (the expected byte stream). This test feeds the SAME indices +
//! palettes to `s4_gif_assemble` and asserts the produced GIF is BYTE-EXACTLY the
//! golden — pinning the Zig LZW + GIF89a serialiser to the Haskell/Swift source
//! of truth (no transcendental, just exact bytes).
//!
//! Skip-if-absent (build with `cd spec && cabal run spec-fixtures`).

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

test "cross-language: s4_gif_assemble reproduces the Haskell GIF golden byte-exactly" {
    const alloc = std.testing.allocator;
    const dir = build_options.fixture_dir;

    const meta_raw = readFileAlloc(alloc, dir, "gif_golden.json") catch |e| {
        if (e == error.SkipZigTest) {
            if (build_options.require_fixtures) {
                std.debug.print("\n  [FAIL] gif_golden.json absent but -Drequire_fixtures=true; produce the fixtures first\n", .{});
                return error.FixtureRequired;
            }
            std.debug.print(
                "\n  [skip] gif_golden.json not in '{s}'; run `cd spec && cabal run spec-fixtures`\n",
                .{dir},
            );
            return error.SkipZigTest;
        }
        return e;
    };
    defer alloc.free(meta_raw);

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, meta_raw, .{});
    defer parsed.deinit();
    const meta = parsed.value.object;

    const frame_count: i32 = @intCast(meta.get("frame_count").?.integer);
    const side: i32 = @intCast(meta.get("side").?.integer);
    const k: i32 = @intCast(meta.get("k").?.integer);
    const delay_cs: u16 = @intCast(meta.get("delay_cs").?.integer);
    const comment = meta.get("comment").?.string;

    const indices = try readFileAlloc(alloc, dir, "gif_golden_indices.bin");
    defer alloc.free(indices);
    const palettes = try readFileAlloc(alloc, dir, "gif_golden_palettes.bin");
    defer alloc.free(palettes);
    const golden = try readFileAlloc(alloc, dir, "gif_golden.gif");
    defer alloc.free(golden);

    // Shapes must line up with the binary payloads.
    const p: usize = @as(usize, @intCast(side)) * @as(usize, @intCast(side));
    try std.testing.expectEqual(@as(usize, @intCast(frame_count)) * p, indices.len);
    try std.testing.expectEqual(@as(usize, @intCast(frame_count)) * @as(usize, @intCast(k)) * 3, palettes.len);

    const bound = kernels.s4_gif_encode_burst_bound(frame_count, side, k);
    const out = try alloc.alloc(u8, bound);
    defer alloc.free(out);

    var out_len: usize = 0;
    const rc = kernels.s4_gif_assemble(
        indices.ptr,
        palettes.ptr,
        frame_count,
        side,
        k,
        delay_cs,
        comment.ptr,
        @intCast(comment.len),
        out.ptr,
        out.len,
        &out_len,
    );
    try std.testing.expectEqual(kernels.RC_OK, rc);
    try std.testing.expectEqualSlices(u8, golden, out[0..out_len]);
}
