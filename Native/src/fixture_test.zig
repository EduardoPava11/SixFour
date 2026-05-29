//! Cross-language byte-exactness fixture test.
//!
//! The Python producer (trainer/export_look_net_blob.py main()) writes the real
//! S4LN blob (trainer/out/look_net.s4ln) AND a sidecar of spot float32 values it
//! decoded (look_net.spot.json: per-tensor first-float bit pattern + a couple of
//! interior offsets). This test loads the SAME blob through the Zig parser and
//! asserts: rc==0, tensor_count==13, head_dims=={3,3,6,12,24,48,96,192}, the
//! phi/w1/w2 shapes, and that every spot value the Zig parser reads through its
//! aliasing pointers is BIT-EXACTLY the value Python decoded — proving the two
//! language paths agree on the wire format byte-for-byte.
//!
//! The fixture directory is threaded in by build.zig as the `fixture_dir` build
//! option (default ../trainer/out, override with -Dfixture_dir=...). If the
//! fixture is absent (producer not run), the test is skipped via error.SkipZigTest
//! so it never silently passes vacuously while still not blocking a clean tree.

const std = @import("std");
const root = @import("root.zig");
const build_options = @import("build_options");

const HEAD_DIMS = [8]i32{ 3, 3, 6, 12, 24, 48, 96, 192 };

fn readFileAlloc(alloc: std.mem.Allocator, dir: []const u8, name: []const u8) ![]u8 {
    const io = std.testing.io;
    const path = try std.fs.path.join(alloc, &.{ dir, name });
    defer alloc.free(path);
    return std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .unlimited) catch
        return error.SkipZigTest;
}

/// Bit-exact float32 compare: take the uint32 bit pattern Python wrote and
/// reinterpret it, comparing the raw bits to what the parser's pointer yields.
fn expectBits(actual: f32, expect_bits: u32) !void {
    try std.testing.expectEqual(expect_bits, @as(u32, @bitCast(actual)));
}

fn jsonU32(values: std.json.Value, tensor: []const u8, field: []const u8) u32 {
    const t = values.object.get(tensor).?.object;
    return @intCast(t.get(field).?.integer);
}

test "cross-language: Python-produced S4LN blob parses byte-exactly in Zig" {
    const alloc = std.testing.allocator;
    const dir = build_options.fixture_dir;

    const blob = readFileAlloc(alloc, dir, "look_net.s4ln") catch |e| {
        if (e == error.SkipZigTest) {
            std.debug.print(
                "\n  [skip] fixture not found in '{s}'; run trainer/export_look_net_blob.py\n",
                .{dir},
            );
            return error.SkipZigTest;
        }
        return e;
    };
    defer alloc.free(blob);

    const spot_raw = try readFileAlloc(alloc, dir, "look_net.spot.json");
    defer alloc.free(spot_raw);

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, spot_raw, .{});
    defer parsed.deinit();
    const spot = parsed.value.object;
    const values = spot.get("values").?;

    // --- structural agreement -------------------------------------------------
    try std.testing.expectEqual(
        @as(i64, @intCast(blob.len)),
        spot.get("nbytes").?.integer,
    );

    var w: root.S4LookNetWeights = undefined;
    const rc = root.s4_load_look_net(blob.ptr, blob.len, &w);
    try std.testing.expectEqual(@as(i32, 0), rc);

    // tensor_count the producer recorded == the 13 the parser requires.
    try std.testing.expectEqual(@as(i64, 13), spot.get("tensor_count").?.integer);

    // head dims as decoded from each head's leading shape dim.
    try std.testing.expectEqualSlices(i32, &HEAD_DIMS, &w.head_dims);

    // declared shapes for the trunk tensors (phi 64×10, w1/w2 64×64).
    try expectShape(values, "phi", &.{ 64, 10 });
    try expectShape(values, "w1", &.{ 64, 64 });
    try expectShape(values, "w2", &.{ 64, 64 });

    // --- byte-exact float spot-checks via the aliasing pointers ---------------
    try expectBits(w.phi[0], jsonU32(values, "phi", "f0_bits"));
    try expectBits(w.phi[5], jsonU32(values, "phi", "f5_bits"));
    try expectBits(w.w1[0], jsonU32(values, "w1", "f0_bits"));
    try expectBits(w.w1[63], jsonU32(values, "w1", "f63_bits"));
    try expectBits(w.w2[0], jsonU32(values, "w2", "f0_bits"));
    try expectBits(w.halt_w[0], jsonU32(values, "halt_w", "f0_bits"));
    try expectBits(w.halt_b[0], jsonU32(values, "halt_b", "f0_bits"));

    var hi: usize = 0;
    while (hi < 8) : (hi += 1) {
        var name_buf: [8]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "head{d}", .{hi}) catch unreachable;
        try expectBits(w.heads[hi][0], jsonU32(values, name, "f0_bits"));
    }

    // --- malformed inputs must be rejected (defensive, no OOB) ----------------
    {
        const bad = try alloc.dupe(u8, blob);
        defer alloc.free(bad);
        bad[0] = 'X'; // corrupt magic
        try std.testing.expect(root.s4_load_look_net(bad.ptr, bad.len, &w) != 0);
    }
    {
        const bad = try alloc.dupe(u8, blob);
        defer alloc.free(bad);
        bad[4] = 9; // bad version byte
        try std.testing.expectEqual(@as(i32, 3), root.s4_load_look_net(bad.ptr, bad.len, &w));
    }
    // truncation: any short length must be rejected, never deref past end.
    try std.testing.expect(root.s4_load_look_net(blob.ptr, blob.len - 1, &w) != 0);
    try std.testing.expectEqual(@as(i32, 1), root.s4_load_look_net(blob.ptr, 8, &w));
}

fn expectShape(values: std.json.Value, tensor: []const u8, expect: []const i64) !void {
    const shape = values.object.get(tensor).?.object.get("shape").?.array;
    try std.testing.expectEqual(expect.len, shape.items.len);
    for (expect, 0..) |e, i| {
        try std.testing.expectEqual(e, shape.items[i].integer);
    }
}
