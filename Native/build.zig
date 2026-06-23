//! Host build for the SixFour native Zig core.
//!
//! `zig build test` runs the unit tests in src/root.zig (the byte-exact S4LN
//! parser + the cross-language fixture check). The iOS static-lib path stays in
//! build-ios.sh (invoked from the Xcode preBuildScript); this build.zig is the
//! host/test entry point only.
//!
//! The cross-language test reads the fixture the Python producer writes
//! (trainer/out/look_net.s4ln + look_net.spot.json). build.zig threads the
//! repo-relative fixture directory in as a build option so the test can locate
//! it regardless of the process cwd; `-Dfixture_dir=...` overrides it.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Repo layout: Native/ is one level under the repo root; the producer
    // writes to trainer/out/. Default to that path relative to this build root.
    const default_fixture_dir = b.pathFromRoot("../trainer/out");
    const fixture_dir = b.option(
        []const u8,
        "fixture_dir",
        "Directory holding look_net.s4ln + look_net.spot.json (default: ../trainer/out)",
    ) orelse default_fixture_dir;

    // require_fixtures=true turns the cross-language fixture tests from SKIP-if-absent
    // (dev convenience) into FAIL-if-absent (the gate), so the GIF + blob goldens can
    // never pass green vacuously. gate.sh produces the fixtures then sets this.
    const require_fixtures = b.option(
        bool,
        "require_fixtures",
        "Fail (not skip) the cross-language fixture tests if their artifacts are absent (default: false)",
    ) orelse false;

    const opts = b.addOptions();
    opts.addOption([]const u8, "fixture_dir", fixture_dir);
    opts.addOption(bool, "require_fixtures", require_fixtures);

    // Host shared library for the Python trainer (ctypes can't dlopen a static
    // .a). `zig build` installs zig-out/lib/libsixfour_native.dylib; the trainer's
    // trainer/zig_native.py loads it to call s4_synth_burst + the GIF kernels —
    // the SAME code the iOS build-ios.sh static lib compiles, so training-data
    // generation runs through the production kernels byte-for-byte.
    const lib = b.addLibrary(.{
        .name = "sixfour_native",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(lib);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test_root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    tests.root_module.addImport("build_options", opts.createModule());

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run the native core unit + fixture tests");
    test_step.dependOn(&run_tests.step);
}
