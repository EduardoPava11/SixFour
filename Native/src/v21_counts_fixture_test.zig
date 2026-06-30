//! Cross-language V2.1 captured-bin energy golden fixture test (the make_bins core).
//!
//! `spec-fixtures` (Haskell, SixFour.Spec.V21Field.countsToEnergy) writes v21_counts_golden.json:
//! p*3 count histograms of n_levels each, their energy curves (E = total - count), and their modes
//! (collapse of the energy). This test:
//!   1. runs `s4_v21_counts_to_energy` and asserts BIT-EXACT agreement on the energy curves;
//!   2. runs `s4_v21_collapse` on those energies and asserts they reproduce the modes (collapse of
//!      the captured-bin energy == the most-observed value);
//!   3. cross-checks RESPECT FOR THE EXISTING ALGORITHM: runs the existing `s4_board_counts_to_mass_q16`
//!      on the SAME counts and asserts its argmax (the mass face) equals the mode (order-duality),
//!      so the V2.1 energy face and the shipped mass kernel agree on one fixture.
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

// argmax over a Q16 mass slice, lowest index winning ties (strict >).
fn argmaxLowest(xs: []const i32) usize {
    var best_i: usize = 0;
    var best_v: i32 = xs[0];
    var i: usize = 1;
    while (i < xs.len) : (i += 1) {
        if (xs[i] > best_v) {
            best_v = xs[i];
            best_i = i;
        }
    }
    return best_i;
}

test "cross-language: s4_v21_counts_to_energy matches the Haskell captured-bin golden + duality" {
    const alloc = std.testing.allocator;
    const dir = build_options.fixture_dir;

    const raw = readFileAlloc(alloc, dir, "v21_counts_golden.json") catch |e| {
        if (e == error.SkipZigTest) {
            std.debug.print(
                "\n  [skip] v21_counts_golden.json not in '{s}'; run `cd spec && cabal run spec-fixtures`\n",
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

    const p: i32 = @intCast(root.get("p").?.integer);
    const n_levels: i32 = @intCast(root.get("n_levels").?.integer);
    const counts_json = root.get("counts").?.array;
    const energy_json = root.get("energy").?.array;
    const modes_json = root.get("modes").?.array;

    const nl: usize = @intCast(n_levels);
    const ncurves: usize = @intCast(p * 3);

    // Flatten the count histograms into [ncurves*nl] (curve-major, level-contiguous).
    const counts = try alloc.alloc(i32, ncurves * nl);
    defer alloc.free(counts);
    for (counts_json.items, 0..) |curve, c| {
        for (curve.array.items, 0..) |v, l| {
            counts[c * nl + l] = @intCast(v.integer);
        }
    }

    // (1) energy curves bit-exact.
    const energy = try alloc.alloc(i32, ncurves * nl);
    defer alloc.free(energy);
    try std.testing.expectEqual(kernels.RC_OK, kernels.s4_v21_counts_to_energy(counts.ptr, p, n_levels, energy.ptr));
    for (energy_json.items, 0..) |curve, c| {
        for (curve.array.items, 0..) |want, l| {
            try std.testing.expectEqual(@as(i32, @intCast(want.integer)), energy[c * nl + l]);
        }
    }

    // (2) collapse of the energy == the mode (the captured byte is the most-observed value).
    const collapsed = try alloc.alloc(u8, ncurves);
    defer alloc.free(collapsed);
    try std.testing.expectEqual(kernels.RC_OK, kernels.s4_v21_collapse(energy.ptr, p, n_levels, collapsed.ptr));
    for (modes_json.items, 0..) |want, c| {
        try std.testing.expectEqual(@as(u8, @intCast(want.integer)), collapsed[c]);
    }

    // (3) RESPECT THE ALGO: the existing s4_board_counts_to_mass_q16 (the mass face) argmaxes to the
    //     same mode -> the V2.1 energy face and the shipped mass kernel are order-dual.
    const mass = try alloc.alloc(i32, nl);
    defer alloc.free(mass);
    var c: usize = 0;
    while (c < ncurves) : (c += 1) {
        var total: i32 = 0;
        var l: usize = 0;
        while (l < nl) : (l += 1) total += counts[c * nl + l];
        try std.testing.expectEqual(kernels.RC_OK, kernels.s4_board_counts_to_mass_q16(counts.ptr + c * nl, n_levels, total, mass.ptr));
        const mode: usize = @intCast(modes_json.items[c].integer);
        try std.testing.expectEqual(mode, argmaxLowest(mass));
    }
}
