//! Cross-language look / LUT-extraction golden fixture test.
//!
//! `spec-fixtures` (Haskell, SixFour.Spec.{ZoneProfile,LookTransfer,CubeLut})
//! writes lut_golden.json: a synthetic OKLab palette with its expected zone
//! profile, a set of look-transfer cases (incl. neutral / extreme adversarial
//! inputs), and a full small (5³) .cube. This test runs s4_zone_profile_q16 /
//! s4_look_transfer_q16 / s4_build_cube_q16 on the SAME inputs and asserts every
//! output is BIT-EXACTLY the spec's — proving the Zig integer port and the
//! Haskell source of truth agree (the preview look ≡ the exported LUT).
//!
//! Skip-if-absent (build the golden with `cd spec && cabal run spec-fixtures`).

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

fn i32at(arr: std.json.Value, idx: usize) i32 {
    return @intCast(arr.array.items[idx].integer);
}

test "cross-language: look transfer + LUT extraction match the Haskell golden byte-exactly" {
    const alloc = std.testing.allocator;
    const dir = build_options.fixture_dir;

    const raw = readFileAlloc(alloc, dir, "lut_golden.json") catch |e| {
        if (e == error.SkipZigTest) {
            std.debug.print(
                "\n  [skip] lut_golden.json not in '{s}'; run `cd spec && cabal run spec-fixtures`\n",
                .{dir},
            );
            return error.SkipZigTest;
        }
        return e;
    };
    defer alloc.free(raw);

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, raw, .{});
    defer parsed.deinit();
    const root = parsed.value.object;

    try std.testing.expectEqual(@as(i64, kernels.Q16_ONE), root.get("q16_one").?.integer);

    const num_zones: i32 = @intCast(root.get("num_zones").?.integer);
    const nz: usize = @intCast(num_zones);

    const params = root.get("transfer_params").?.object;
    const strength: i32 = @intCast(params.get("strength").?.integer);
    const chroma_min: i32 = @intCast(params.get("chroma_min").?.integer);
    const chroma_max: i32 = @intCast(params.get("chroma_max").?.integer);
    const polarity: i32 = @intCast(params.get("polarity").?.integer);
    const chroma_eps: i32 = @intCast(params.get("chroma_eps").?.integer);

    // ── 1. Zone profile ──────────────────────────────────────────────────────
    const pal = root.get("palette_oklab").?.array;
    const p: usize = pal.items.len;
    const pal_flat = try alloc.alloc(i32, p * 3);
    defer alloc.free(pal_flat);
    for (pal.items, 0..) |tri, i| {
        pal_flat[i * 3 + 0] = i32at(tri, 0);
        pal_flat[i * 3 + 1] = i32at(tri, 1);
        pal_flat[i * 3 + 2] = i32at(tri, 2);
    }

    const mean_a = try alloc.alloc(i32, nz);
    defer alloc.free(mean_a);
    const mean_b = try alloc.alloc(i32, nz);
    defer alloc.free(mean_b);
    const mean_c = try alloc.alloc(i32, nz);
    defer alloc.free(mean_c);
    var global = [3]i32{ 0, 0, 0 };

    try std.testing.expectEqual(kernels.RC_OK, kernels.s4_zone_profile_q16(
        pal_flat.ptr,
        @intCast(p),
        num_zones,
        mean_a.ptr,
        mean_b.ptr,
        mean_c.ptr,
        &global,
    ));

    const zp = root.get("zone_profile").?.object;
    const exp_a = zp.get("mean_a").?.array;
    const exp_b = zp.get("mean_b").?.array;
    const exp_c = zp.get("mean_c").?.array;
    const exp_g = zp.get("global").?;
    var z: usize = 0;
    while (z < nz) : (z += 1) {
        try std.testing.expectEqual(@as(i32, @intCast(exp_a.items[z].integer)), mean_a[z]);
        try std.testing.expectEqual(@as(i32, @intCast(exp_b.items[z].integer)), mean_b[z]);
        try std.testing.expectEqual(@as(i32, @intCast(exp_c.items[z].integer)), mean_c[z]);
    }
    try std.testing.expectEqual(i32at(exp_g, 0), global[0]);
    try std.testing.expectEqual(i32at(exp_g, 1), global[1]);
    try std.testing.expectEqual(i32at(exp_g, 2), global[2]);

    // ── 2. Look transfer cases ────────────────────────────────────────────────
    const cases = root.get("transfer_cases").?.array;
    try std.testing.expect(cases.items.len > 0);
    for (cases.items) |case| {
        const obj = case.object;
        const cin = obj.get("in").?;
        const cout = obj.get("out").?;
        var in = [3]i32{ i32at(cin, 0), i32at(cin, 1), i32at(cin, 2) };
        var out = [3]i32{ 0, 0, 0 };
        try std.testing.expectEqual(kernels.RC_OK, kernels.s4_look_transfer_q16(
            &in,
            1,
            mean_a.ptr,
            mean_b.ptr,
            mean_c.ptr,
            num_zones,
            strength,
            chroma_min,
            chroma_max,
            polarity,
            chroma_eps,
            &out,
        ));
        try std.testing.expectEqual(i32at(cout, 0), out[0]);
        try std.testing.expectEqual(i32at(cout, 1), out[1]);
        try std.testing.expectEqual(i32at(cout, 2), out[2]);
    }

    // ── 3. The whole N³ cube ──────────────────────────────────────────────────
    const cube_size: i32 = @intCast(root.get("cube_size").?.integer);
    const ncube: usize = @intCast(cube_size);
    const cube_len: usize = ncube * ncube * ncube * 3;
    const cube = try alloc.alloc(i32, cube_len);
    defer alloc.free(cube);
    try std.testing.expectEqual(kernels.RC_OK, kernels.s4_build_cube_q16(
        cube_size,
        mean_a.ptr,
        mean_b.ptr,
        mean_c.ptr,
        num_zones,
        strength,
        chroma_min,
        chroma_max,
        polarity,
        chroma_eps,
        cube.ptr,
        cube_len,
    ));

    const exp_cube = root.get("cube").?.array;
    try std.testing.expectEqual(cube_len, exp_cube.items.len * 3);
    for (exp_cube.items, 0..) |tri, i| {
        try std.testing.expectEqual(i32at(tri, 0), cube[i * 3 + 0]);
        try std.testing.expectEqual(i32at(tri, 1), cube[i * 3 + 1]);
        try std.testing.expectEqual(i32at(tri, 2), cube[i * 3 + 2]);
    }
}
