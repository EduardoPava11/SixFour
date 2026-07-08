//  KernelsCore.swift
//  THE OWNED SWIFT KERNEL CORE — shared surface of the Zig→Swift port (2026-07-06).
//
//  This directory replaces Native/src/*.zig as the byte-exact integer source of
//  truth. The determinism contract is UNCHANGED: every kernel is integer-exact,
//  allocation-free on the hot path, and gated by the Haskell spec's golden
//  vectors — bit-exactness is a property of the ALGORITHMS (integer arithmetic,
//  explicit overflow semantics), not of the implementation language.
//
//  ABI CONTRACT: every exported kernel keeps its exact C name and signature via
//  @_cdecl, mirroring Native/include/sixfour_native.h. Two consumers:
//    * the iOS app calls them as ordinary Swift functions (the @_cdecl name is
//      also the Swift name; all parameters unlabeled, matching the C import the
//      call sites were written against), and
//    * the Mac trainer loads the same sources compiled as a dylib
//      (libsixfour_kernels.dylib) via ctypes — the SAME code the iPhone runs,
//      so there is no train/deploy skew, exactly as with the Zig dylib before.
//
//  TRANSLATION SEMANTICS (the Zig→Swift dictionary every kernel file follows):
//    Zig `+`/`-`/`*` (trap on overflow)  → Swift `+`/`-`/`*` (also trapping)
//    Zig `+%`/`-%`/`*%` (wrapping)       → Swift `&+`/`&-`/`&*`
//    Zig `@truncate`                     → init(truncatingIfNeeded:)
//    Zig `@intCast` (trapping)           → numeric init (trapping)
//    Zig `@divTrunc` / `/` on ints       → Swift `/` (truncates toward zero)
//    Zig `@divFloor`                     → explicit floor-division helper
//    Zig `>>` on signed (arithmetic)     → Swift `>>` on signed (arithmetic)
//    Zig `@bitCast`                      → Swift bitPattern initializers

/// C-ABI log callback (mirrors `S4LogCallback` in sixfour_native.h):
/// `void (*)(const uint8_t *msg, size_t len)`.
public typealias S4LogCallback = @convention(c) (UnsafePointer<UInt8>?, Int) -> Void

/// The one global the core owns. C-style: set-once-ish from the app's logging
/// bootstrap; reads race benignly like the Zig `g_log_cb` did.
nonisolated(unsafe) private var gLogCallback: S4LogCallback?

/// Install (or clear, with nil) the log sink. Kernels format nothing until a
/// sink is set — logging must cost zero when unobserved.
@_cdecl("s4_set_log_callback")
public func s4_set_log_callback(_ cb: S4LogCallback?) {
    gLogCallback = cb
}

/// Internal logging helper (the Zig `s4log` twin): formats only when a sink is
/// installed, truncates to 256 bytes like the Zig fixed buffer.
@inline(__always)
func s4log(_ message: @autoclosure () -> String) {
    guard let cb = gLogCallback else { return }
    var bytes = Array(message().utf8)
    if bytes.count > 256 { bytes.removeLast(bytes.count - 256) }
    bytes.withUnsafeBufferPointer { cb($0.baseAddress, $0.count) }
}

/// Link-sanity probe (root.zig twin): proves the kernel core is present and
/// callable. Returns x + 1 (wrapping).
@_cdecl("s4_probe")
public func s4_probe(_ x: UInt32) -> UInt32 {
    x &+ 1
}

// ── Shared kernel constants (kernels.zig) ────────────────────────────────────

/// OKLab fixed-point shift: Q16.
public let S4_Q16_SHIFT: Int32 = 16
/// Q16 unit: 1 << 16.
public let S4_Q16_ONE: Int32 = 1 << 16
/// Frame side: 64.
public let S4_SIDE: Int32 = 64
/// Frames per burst: 64.
public let S4_FRAME_COUNT: Int32 = 64
/// Palette entries per frame: 256.
public let S4_K: Int32 = 256
/// Channels per sample (OKLab / linear RGB): 3.
public let S4_CHANNELS: Int32 = 3

/// Floor division on Int32 (the Zig `@divFloor` twin — Swift `/` truncates
/// toward zero, which differs from floor on negative operands).
@inline(__always)
func s4DivFloor(_ a: Int32, _ b: Int32) -> Int32 {
    let q = a / b
    let r = a % b
    return (r != 0 && ((r < 0) != (b < 0))) ? q - 1 : q
}

/// Floor division on Int64 (same law, wider carrier).
@inline(__always)
func s4DivFloor64(_ a: Int64, _ b: Int64) -> Int64 {
    let q = a / b
    let r = a % b
    return (r != 0 && ((r < 0) != (b < 0))) ? q - 1 : q
}
