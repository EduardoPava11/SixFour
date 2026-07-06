//! THE INTEGRATOR — assemble the three INDEPENDENT volumes from the raw laddered
//! capture. DEPENDENCY-FREE: imports nothing, pure integer, C ABI, i64 carrier,
//! i32 rc (0 == ok). Host-testable via multiscale_integrate_test.zig. Byte-exact
//! twin of Spec.MultiScaleIntegrate.
//!
//! INDEPENDENCE IS PHYSICAL, BY CONSERVATION: a photon is absorbed once, so the
//! interleaved exposure ladder ALLOCATES each raw sub-exposure to exactly one
//! scale (the `owner` array — the device's real interleaving pattern; any total
//! assignment is a valid disjoint cover). Each scale's volume is the exact i64
//! sum of the sub-exposures it OWNS — disjoint photons, so no scale's volume is a
//! function of another's, and the three volumes sum back to the raw stream (every
//! photon counted once: Spec.lawConservesPhotons).
//!
//! 10-BIT × 3, ABSORBED: `photons` are u16 in 0..1023; accumulation is i64, whose
//! headroom the width contract guarantees (Spec.lawIntegrateCarrierWidthSuffices).
//! `n_scales` volumes come out; `photons` is laid out cell-major
//! (`photons[cell*n_subslices + s]`), `owner[s]` names the scale of sub-slice s,
//! `out[scale*n_cells + cell]` receives the integrated volume.

const RC_OK: i32 = 0;
const RC_BAD_ARGS: i32 = 1;
const TEN_BIT_MAX: u16 = 1023;

inline fn clamp10(v: u16) u16 {
    return if (v > TEN_BIT_MAX) TEN_BIT_MAX else v;
}

/// Integrate the raw sub-exposure stream into `n_scales` per-cell volumes by the
/// `owner` disjoint schedule. `out` must have `n_scales * n_cells` i64 slots.
/// Returns RC_BAD_ARGS on non-positive sizes or an out-of-range owner.
pub export fn s4_multiscale_integrate(
    out: [*]i64,
    photons: [*]const u16,
    owner: [*]const i32,
    n_scales: i32,
    n_cells: i32,
    n_subslices: i32,
) i32 {
    if (n_scales <= 0 or n_cells <= 0 or n_subslices <= 0) return RC_BAD_ARGS;
    const ns: usize = @intCast(n_scales);
    const nc: usize = @intCast(n_cells);
    const nsub: usize = @intCast(n_subslices);

    // every owner must name a valid scale (else the partition is malformed).
    var s: usize = 0;
    while (s < nsub) : (s += 1) {
        if (owner[s] < 0 or owner[s] >= n_scales) return RC_BAD_ARGS;
    }

    // zero the output volumes.
    var i: usize = 0;
    while (i < ns * nc) : (i += 1) out[i] = 0;

    // accumulate: each sub-slice adds into its OWNED scale's volume, per cell.
    var cell: usize = 0;
    while (cell < nc) : (cell += 1) {
        s = 0;
        while (s < nsub) : (s += 1) {
            const scale: usize = @intCast(owner[s]);
            const v: i64 = @intCast(clamp10(photons[cell * nsub + s]));
            out[scale * nc + cell] += v;
        }
    }
    return RC_OK;
}
