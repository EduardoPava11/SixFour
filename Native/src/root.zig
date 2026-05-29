// SixFour native kernels — C ABI surface.
// Spike stub: a trivial exported function to validate the Zig→iOS toolchain
// (device + simulator) before any real kernel work lands here.

export fn s4_probe(x: u32) u32 {
    return x +% 1;
}
