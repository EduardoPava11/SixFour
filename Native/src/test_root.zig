//! Test aggregation root for `zig build test`.
//!
//! Pulls in root.zig's own unit tests AND the cross-language fixture test
//! (fixture_test.zig). It is kept SEPARATE from root.zig because build-ios.sh
//! compiles root.zig directly with `zig build-lib` (no build system, hence no
//! `build_options` module) — so the fixture machinery, which depends on the
//! build-option-provided fixture path, must not live in root.zig's top level.

test {
    _ = @import("root.zig"); // the parser's own unit tests
    _ = @import("fixture_test.zig"); // cross-language Python-fixture check
}
