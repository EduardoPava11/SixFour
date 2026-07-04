//! Bench for the GIF89a-camera color head: MEASURE THE LADDER IN COMPUTE.
//! Standalone (not in build.zig):
//!   zig build-exe -O ReleaseFast src/palette16_bench.zig -femit-bin=/tmp/p16bench && /tmp/p16bench
//!
//! Question under test: 64^3 plays at 20 fps; what does compute say 32^2 and
//! 16^2 pooling cost? Hypothesis: box-sum pooling is INPUT-BOUND — cost is set
//! by the sensor pixels read, nearly independent of the output rung — so the
//! ladder's frame rates are an information/GIF-standard decision, not a compute
//! one. This bench prints ns/frame, implied max fps, and headroom over the
//! GIF-exact ladder rate (20/10/5 fps from s4_ladder_delay_cs).

const std = @import("std");
const p16 = @import("palette16.zig");

fn fillLcg(buf: []u8, seed0: u64) void {
    var s: u64 = seed0;
    for (buf) |*b| {
        s = s *% 6364136223846793005 +% 1442695040888963407;
        b.* = @intCast((s >> 33) & 0xff);
    }
}

// Zig 0.16 removed std.time.Timer; use the libc monotonic clock directly.
fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec));
}

fn benchPool(frame: []const u8, side: i32, out_side: i32, iters: usize) !u64 {
    var sums: [64 * 64 * 3]u64 = undefined; // big enough for out_side <= 64
    const t0 = nowNs();
    var sink: u64 = 0;
    for (0..iters) |_| {
        const rc = p16.s4_pool_sums_srgb8(frame.ptr, side, out_side, &sums);
        if (rc != p16.S4_RC_OK) return error.KernelFailed;
        sink +%= sums[0];
    }
    const ns = nowNs() - t0;
    std.mem.doNotOptimizeAway(sink);
    return ns / iters;
}

pub fn main() !void {
    const gpa = std.heap.page_allocator;
    const print = std.debug.print;

    const inputs = [_]i32{ 256, 1024 };
    const rungs = [_]i32{ 16, 32, 64 };

    print("palette16 bench — pooling cost per frame (ReleaseFast)\n", .{});
    print("{s:>6} {s:>6} {s:>12} {s:>12} {s:>10} {s:>12} {s:>10}\n", .{ "in", "out", "ns/frame", "max fps", "GB/s in", "ladder fps", "headroom" });

    for (inputs) |side| {
        const n: usize = @as(usize, @intCast(side)) * @as(usize, @intCast(side)) * 3;
        const frame = try gpa.alloc(u8, n);
        defer gpa.free(frame);
        fillLcg(frame, 20260703);

        for (rungs) |out| {
            const iters: usize = if (side >= 1024) 200 else 2000;
            const ns = try benchPool(frame, side, out, iters);
            const fps_max = 1e9 / @as(f64, @floatFromInt(ns));
            const gbs = @as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(ns));
            const delay = p16.s4_ladder_delay_cs(out);
            const ladder_fps: f64 = if (delay > 0) 100.0 / @as(f64, @floatFromInt(delay)) else 0;
            const headroom = if (ladder_fps > 0) fps_max / ladder_fps else 0;
            print("{d:>6} {d:>6} {d:>12} {d:>12.0} {d:>10.2} {d:>12.1} {d:>9.0}x\n", .{ side, out, ns, fps_max, gbs, ladder_fps, headroom });
        }
    }

    // The measurement path: same pooling with the inverse-EOTF LUT in the loop.
    for (inputs) |side| {
        const n: usize = @as(usize, @intCast(side)) * @as(usize, @intCast(side)) * 3;
        const frame = try gpa.alloc(u8, n);
        defer gpa.free(frame);
        fillLcg(frame, 20260703);
        var sums: [64 * 64 * 3]u64 = undefined;
        for (rungs) |out| {
            const iters: usize = if (side >= 1024) 200 else 2000;
            const t0 = nowNs();
            var sink: u64 = 0;
            for (0..iters) |_| {
                _ = p16.s4_pool_sums_linear_srgb8(frame.ptr, side, out, &sums);
                sink +%= sums[0];
            }
            const ns = (nowNs() - t0) / iters;
            std.mem.doNotOptimizeAway(sink);
            print("lin {d:>5} {d:>6} {d:>12} ns/frame  ({d:.0} fps capacity)\n", .{ side, out, ns, 1e9 / @as(f64, @floatFromInt(ns)) });
        }
    }

    // The GCT end-to-end (pool to 16 + realize 768 bytes), the shipped call.
    var gct: [768]u8 = undefined;
    for (inputs) |side| {
        const n: usize = @as(usize, @intCast(side)) * @as(usize, @intCast(side)) * 3;
        const frame = try gpa.alloc(u8, n);
        defer gpa.free(frame);
        fillLcg(frame, 42);
        const iters: usize = if (side >= 1024) 200 else 2000;
        const t0 = nowNs();
        var sink: u64 = 0;
        for (0..iters) |_| {
            _ = p16.s4_palette16_gct(frame.ptr, side, &gct);
            sink +%= gct[0];
        }
        const ns = (nowNs() - t0) / iters;
        std.mem.doNotOptimizeAway(sink);
        print("gct {d:>4}x{d:<4} {d:>10} ns/frame  ({d:.0} fps capacity)\n", .{ side, side, ns, 1e9 / @as(f64, @floatFromInt(ns)) });
    }

    print("\nGIF-exact isotropic ladder (window 320 cs): ", .{});
    for ([_]i32{ 64, 32, 16, 8 }) |s| {
        const delay = p16.s4_ladder_delay_cs(s);
        print("{d}^3@{d:.1}fps(delay {d}cs) ", .{ s, 100.0 / @as(f64, @floatFromInt(delay)), delay });
    }
    print("| 128: delay {d} (NOT representable)\n", .{p16.s4_ladder_delay_cs(128)});
}
