// SixFour native kernels — C ABI surface.
//
// This is the single owned native core (see memory: sixfour-zig-quantized-core).
// root.zig is the link aggregator: it installs the no-panic handler, pulls the
// deterministic quantized-core kernels (kernels.zig) and the synthetic-burst
// generator (synth.zig) into the static lib, and exposes the toolchain smoke test.

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
    _ = @import("palette16.zig"); // GIF89a-camera color head: 16x16 bins -> GCT, ladder time law, EOTF LUT pooling
    _ = @import("kinematic.zig"); // kinematic certification: certified order / Newton prediction / residual loss
    _ = @import("multiscale.zig"); // multi-scale independence reads (The Loom): fast/mid/slow exposure reads + dead-time
    _ = @import("multiscale_integrate.zig"); // integrator: disjoint sub-exposures -> 3 independent volumes (conservation)
    _ = @import("render_select.zig"); // rung-1 select render: per-region pick the chosen independent scale, block-replicated
}

// ── toolchain/link smoke test ───────────────────────────────────────────────
export fn s4_probe(x: u32) u32 {
    return x +% 1;
}
