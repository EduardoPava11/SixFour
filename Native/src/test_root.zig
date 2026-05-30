//! Test aggregation root for `zig build test`.
//!
//! Pulls in root.zig's own unit tests AND the cross-language fixture test
//! (fixture_test.zig). It is kept SEPARATE from root.zig because build-ios.sh
//! compiles root.zig directly with `zig build-lib` (no build system, hence no
//! `build_options` module) — so the fixture machinery, which depends on the
//! build-option-provided fixture path, must not live in root.zig's top level.

test {
    _ = @import("root.zig"); // the parser's own unit tests
    _ = @import("kernels.zig"); // quantized-core ABI: size helpers + color kernel + stubs
    _ = @import("color_fixture_test.zig"); // cross-language color golden (skip-if-absent)
    _ = @import("gif_assemble_fixture_test.zig"); // cross-language GIF-assembler golden
    _ = @import("significance_fixture_test.zig"); // cross-language significance golden
    _ = @import("dither_fixture_test.zig"); // cross-language spatial-dither golden
    _ = @import("quant_fixture_test.zig"); // cross-language quantizer golden
    _ = @import("gif_fixture_test.zig"); // cross-language full-burst GIF golden (Stage 6)
    _ = @import("fixture_test.zig"); // cross-language Python-fixture check
}
