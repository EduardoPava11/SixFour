import Foundation
import os

/// Swift surface over the native Zig kernels.
///
/// The implementations live in `Native/src/*.zig` (C ABI declared in
/// `Native/include/sixfour_native.h`, bridged via `SixFour-Bridging-Header.h`)
/// and are compiled to `libsixfour_native.a` by `Native/build-ios.sh` during
/// the build. Each entry point mirrors a Swift reference implementation that
/// stays in the tree as the parity oracle.
enum SixFourNative {
    private static let log = Logger(subsystem: "com.sixfour", category: "native")

    /// Toolchain/link smoke test — returns `x + 1` from the Zig static lib.
    /// Proves the FFI is wired end-to-end; remove once a real kernel ships.
    static func probe(_ x: UInt32) -> UInt32 {
        s4_probe(x)
    }
}
