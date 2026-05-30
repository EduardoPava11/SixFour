// SixFour native kernels — C ABI surface.
//
// This is the single owned native core (see memory: sixfour-zig-quantized-core).
// Phase 1: byte-exact parsing of the look-NN deploy blob produced by
// trainer/export_look_net_blob.py. Pure integer/serialization work — squarely
// inside the byte-exact contract (no float compute crosses platforms here; we
// only locate the float32 payloads and hand back aliasing pointers).

const std = @import("std");

// This static lib is linked into a non-Zig (Swift/Obj-C) binary, so Zig's
// default panic handler — which references std.debug stack-trace printing — has
// no symbols to resolve against and fails the link. `no_panic` keeps safety
// checks (a failed check still traps) but drops the stack-trace machinery.
pub const panic = std.debug.no_panic;

// Pull the deterministic quantized-core kernels (kernels.zig) into this build.
// build-ios.sh compiles root.zig directly with `zig build-lib`, so referencing
// the file here is what forces its `export fn`s into libsixfour_native.a.
comptime {
    _ = @import("kernels.zig");
    _ = @import("synth.zig"); // synthetic-burst training-data generator (s4_synth_burst)
}

// ── toolchain/link smoke test ───────────────────────────────────────────────
export fn s4_probe(x: u32) u32 {
    return x +% 1;
}

// ── look-NN deploy blob ──────────────────────────────────────────────────────
// Mirrors S4LookNetWeights in Native/include/sixfour_native.h (extern = C ABI).
const HEAD_COUNT = 8;

// The blob has no inter-record padding, so float payloads land at arbitrary byte
// offsets. align(1) lets us alias into them without an alignment assertion; it is
// ABI-identical to C `const float *` (a pointer is 8 bytes regardless of pointee
// alignment) and arm64 tolerates unaligned scalar float loads on the consumer.
const F32Ptr = [*c]align(1) const f32;

pub const S4LookNetWeights = extern struct {
    phi: F32Ptr, // (64, 10)
    w1: F32Ptr, // (64, 64)
    w2: F32Ptr, // (64, 64)
    halt_w: F32Ptr, // (1, 2)
    halt_b: F32Ptr, // (1,)
    heads: [HEAD_COUNT]F32Ptr, // head i: (head_dims[i], 64)
    head_dims: [HEAD_COUNT]i32, // {3,3,6,12,24,48,96,192}
};

const MAGIC = [4]u8{ 'S', '4', 'L', 'N' };
const VERSION: u32 = 1;

// All 13 required tensors: bits 0..4 = phi,w1,w2,halt_w,halt_b; bits 5..12 = head0..7.
const REQUIRED_MASK: u32 = (1 << 13) - 1;

inline fn readU32(b: []const u8, off: usize) u32 {
    return std.mem.readInt(u32, b[off..][0..4], .little);
}
inline fn readI32(b: []const u8, off: usize) i32 {
    return std.mem.readInt(i32, b[off..][0..4], .little);
}

/// Parse a look-NN deploy blob. `blob`/`len` describe the caller-owned buffer;
/// on success `out` is populated with float32 pointers that ALIAS into `blob`
/// (no copy, no allocation). Returns 0 on success, non-zero on a malformed blob.
///
/// The blob has no inter-record padding, so float payloads land at arbitrary
/// byte offsets; we therefore (a) parse all integer fields with unaligned-safe
/// reads and (b) materialise the float pointers via @ptrFromInt so no alignment
/// assertion fires. arm64 tolerates unaligned scalar float loads on the consumer
/// side; SIMD/Metal consumers must re-pack or copy first.
pub export fn s4_load_look_net(blob: [*c]const u8, len: usize, out: *S4LookNetWeights) i32 {
    if (len < 16) return 1;
    const bytes: []const u8 = blob[0..len];

    if (!std.mem.eql(u8, bytes[0..4], &MAGIC)) return 2;
    if (readU32(bytes, 4) != VERSION) return 3;
    const count = readU32(bytes, 8);
    // bytes[12..16] = reserved, ignored.

    const base = @intFromPtr(blob);
    var off: usize = 16;
    var seen: u32 = 0;

    var rec: u32 = 0;
    while (rec < count) : (rec += 1) {
        if (off + 4 > len) return 10;
        const name_len = readU32(bytes, off);
        off += 4;
        if (off + name_len > len) return 11;
        const name = bytes[off .. off + name_len];
        off += name_len;

        if (off + 4 > len) return 12;
        const ndim = readU32(bytes, off);
        off += 4;
        if (off + 4 *% ndim > len or ndim == 0) return 13;

        var nelem: usize = 1;
        var dim0: i32 = 0;
        var d: u32 = 0;
        while (d < ndim) : (d += 1) {
            const dv = readI32(bytes, off + 4 * d);
            if (dv < 0) return 14;
            if (d == 0) dim0 = dv;
            nelem *= @intCast(dv);
        }
        off += 4 * ndim;

        const data_bytes = nelem * 4;
        if (off + data_bytes > len) return 15;
        const data_ptr: F32Ptr = @ptrFromInt(base + off);
        off += data_bytes;

        // Positional-by-name dispatch (names are self-describing per the format).
        if (std.mem.eql(u8, name, "phi")) {
            out.phi = data_ptr;
            seen |= 1 << 0;
        } else if (std.mem.eql(u8, name, "w1")) {
            out.w1 = data_ptr;
            seen |= 1 << 1;
        } else if (std.mem.eql(u8, name, "w2")) {
            out.w2 = data_ptr;
            seen |= 1 << 2;
        } else if (std.mem.eql(u8, name, "halt_w")) {
            out.halt_w = data_ptr;
            seen |= 1 << 3;
        } else if (std.mem.eql(u8, name, "halt_b")) {
            out.halt_b = data_ptr;
            seen |= 1 << 4;
        } else if (name.len == 5 and std.mem.eql(u8, name[0..4], "head")) {
            const c = name[4];
            if (c < '0' or c > '7') return 20;
            const idx: usize = c - '0';
            out.heads[idx] = data_ptr;
            out.head_dims[idx] = dim0;
            seen |= @as(u32, 1) << @intCast(5 + idx);
        }
        // Unknown names are skipped (their bytes are still consumed correctly).
    }

    if (off != len) return 30; // trailing bytes — corruption/short payload
    if ((seen & REQUIRED_MASK) != REQUIRED_MASK) return 31; // missing tensor(s)
    return 0;
}

// ── tests (host: `zig test src/root.zig`) ────────────────────────────────────
pub const HEAD_DIMS = [HEAD_COUNT]i32{ 3, 3, 6, 12, 24, 48, 96, 192 };

// Build a real-shaped blob into `alloc`, with each tensor's first float set to a
// recognisable sentinel so we can verify the returned pointers alias correctly.
fn buildBlob(alloc: std.mem.Allocator) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    const Tensor = struct { name: []const u8, shape: []const i32 };
    const tensors = [_]Tensor{
        .{ .name = "phi", .shape = &[_]i32{ 64, 10 } },
        .{ .name = "w1", .shape = &[_]i32{ 64, 64 } },
        .{ .name = "w2", .shape = &[_]i32{ 64, 64 } },
        .{ .name = "halt_w", .shape = &[_]i32{ 1, 2 } },
        .{ .name = "halt_b", .shape = &[_]i32{1} },
        .{ .name = "head0", .shape = &[_]i32{ 3, 64 } },
        .{ .name = "head1", .shape = &[_]i32{ 3, 64 } },
        .{ .name = "head2", .shape = &[_]i32{ 6, 64 } },
        .{ .name = "head3", .shape = &[_]i32{ 12, 64 } },
        .{ .name = "head4", .shape = &[_]i32{ 24, 64 } },
        .{ .name = "head5", .shape = &[_]i32{ 48, 64 } },
        .{ .name = "head6", .shape = &[_]i32{ 96, 64 } },
        .{ .name = "head7", .shape = &[_]i32{ 192, 64 } },
    };

    try buf.appendSlice(alloc, &MAGIC);
    var hdr: [12]u8 = undefined;
    std.mem.writeInt(u32, hdr[0..4], VERSION, .little);
    std.mem.writeInt(u32, hdr[4..8], tensors.len, .little);
    std.mem.writeInt(u32, hdr[8..12], 0, .little);
    try buf.appendSlice(alloc, &hdr);

    for (tensors, 0..) |t, ti| {
        var scratch: [8]u8 = undefined;
        std.mem.writeInt(u32, scratch[0..4], @intCast(t.name.len), .little);
        try buf.appendSlice(alloc, scratch[0..4]);
        try buf.appendSlice(alloc, t.name);
        std.mem.writeInt(u32, scratch[0..4], @intCast(t.shape.len), .little);
        try buf.appendSlice(alloc, scratch[0..4]);
        var nelem: usize = 1;
        for (t.shape) |dv| {
            std.mem.writeInt(i32, scratch[0..4], dv, .little);
            try buf.appendSlice(alloc, scratch[0..4]);
            nelem *= @intCast(dv);
        }
        // float payload: first element = sentinel (ti+1), rest = 0.
        for (0..nelem) |i| {
            const v: f32 = if (i == 0) @floatFromInt(ti + 1) else 0.0;
            std.mem.writeInt(u32, scratch[0..4], @bitCast(v), .little);
            try buf.appendSlice(alloc, scratch[0..4]);
        }
    }
    return buf.toOwnedSlice(alloc);
}

test "look-net blob parses with correct head dims and aliasing pointers" {
    const alloc = std.testing.allocator;
    const blob = try buildBlob(alloc);
    defer alloc.free(blob);

    var w: S4LookNetWeights = undefined;
    const rc = s4_load_look_net(blob.ptr, blob.len, &w);
    try std.testing.expectEqual(@as(i32, 0), rc);

    try std.testing.expectEqualSlices(i32, &HEAD_DIMS, &w.head_dims);

    // Pointers alias into the blob → first float is the per-tensor sentinel.
    try std.testing.expectEqual(@as(f32, 1.0), w.phi[0]); // tensor index 0 → 1
    try std.testing.expectEqual(@as(f32, 2.0), w.w1[0]);
    try std.testing.expectEqual(@as(f32, 6.0), w.heads[0][0]); // head0 is tensor index 5 → 6
    try std.testing.expectEqual(@as(f32, 13.0), w.heads[7][0]); // head7 is tensor index 12 → 13

    // Pointer must lie inside the blob (true aliasing, no copy).
    const phi_addr = @intFromPtr(w.phi);
    try std.testing.expect(phi_addr >= @intFromPtr(blob.ptr));
    try std.testing.expect(phi_addr < @intFromPtr(blob.ptr) + blob.len);
}

test "rejects bad magic, version, truncation, trailing bytes" {
    const alloc = std.testing.allocator;
    const blob = try buildBlob(alloc);
    defer alloc.free(blob);
    var w: S4LookNetWeights = undefined;

    // bad magic
    {
        const bad = try alloc.dupe(u8, blob);
        defer alloc.free(bad);
        bad[0] = 'X';
        try std.testing.expectEqual(@as(i32, 2), s4_load_look_net(bad.ptr, bad.len, &w));
    }
    // bad version
    {
        const bad = try alloc.dupe(u8, blob);
        defer alloc.free(bad);
        bad[4] = 9;
        try std.testing.expectEqual(@as(i32, 3), s4_load_look_net(bad.ptr, bad.len, &w));
    }
    // truncated (drop last byte) → trailing/short mismatch (non-zero)
    {
        try std.testing.expect(s4_load_look_net(blob.ptr, blob.len - 1, &w) != 0);
    }
    // too short for header
    {
        try std.testing.expectEqual(@as(i32, 1), s4_load_look_net(blob.ptr, 8, &w));
    }
}
