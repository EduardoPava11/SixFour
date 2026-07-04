//! KINEMATIC CERTIFICATION — the exact on-device observables of
//! Spec.KinematicLadder / Spec.KinematicHaltPrior, in dependency-free Zig
//! (imports NOTHING; pure i64 arithmetic, caller owns memory, C ABI).
//!
//! A slot trajectory f(0..n-1) (one palette particle's channel over the
//! capture window) has:
//!   * s4_certified_order: the smallest k < cap with Δ^{k+1} ≡ 0 on the
//!     window — the trajectory's certified kinematic order. Computable BEFORE
//!     any learning; this is the PonderNet halting-prior floor (the cheapest
//!     zero-loss halt, Spec.KinematicHaltPrior keystone).
//!   * s4_newton_predict: the order-m truncated Newton–Mahler prediction
//!     f̂(t) = Σ_{k≤m} C(t,k)·Δ^k f(0) — the S-map at kinematic order m.
//!   * s4_residual_loss: L_m = Σ_t |f(t) − f̂(t)| — the exact Integer
//!     per-depth loss; L_m == 0 iff m ≥ certified order (minimal sufficiency).
//!
//! TOTALITY: a window too short to falsify Δ^{k+1} ≡ 0 (n < k+2) must not
//! vacuously certify — s4_certified_order REFUSES cap ≥ n-1 with
//! S4K_RC_BAD_ARGS rather than certifying on an empty difference row (this is
//! STRICTER than the Haskell law harness, which always uses long windows).
//! Overflow honesty: differences and Newton terms stay well inside i64 for
//! byte/10-bit-code trajectories over ≤64-tick windows (|f| ≤ 2^20, C(63,k)
//! ≤ C(63,31) < 2^60 only for k>20 with alternating-sign Δ^k bounded by
//! 2^{k}·max|f| — the caller keeps cap ≤ 8, documented in the header).

pub const S4K_RC_BAD_ARGS: i32 = -1;

const MAX_WINDOW: usize = 256;

fn nthDiffHead(f: [*c]const i64, n: usize, k: usize) [MAX_WINDOW]i64 {
    // Returns the k-th difference row in the first n-k entries of the buffer.
    var buf: [MAX_WINDOW]i64 = undefined;
    var i: usize = 0;
    while (i < n) : (i += 1) buf[i] = f[i];
    var level: usize = 0;
    while (level < k) : (level += 1) {
        var j: usize = 0;
        while (j + 1 < n - level) : (j += 1) buf[j] = buf[j + 1] - buf[j];
    }
    return buf;
}

/// The certified kinematic order: smallest k < cap with Δ^{k+1} ≡ 0 on the
/// whole window; cap if none certifies. Refuses null / n < 2 / cap < 0 /
/// windows too short to falsify (need n ≥ cap+2) / n > 256.
pub export fn s4_certified_order(f: [*c]const i64, n: i32, cap: i32) i32 {
    if (f == null or n < 2 or cap < 0) return S4K_RC_BAD_ARGS;
    const nu: usize = @intCast(n);
    const capu: usize = @intCast(cap);
    if (nu > MAX_WINDOW or nu < capu + 2) return S4K_RC_BAD_ARGS;

    var k: usize = 0;
    while (k < capu) : (k += 1) {
        const row = nthDiffHead(f, nu, k + 1);
        var allZero = true;
        var j: usize = 0;
        while (j < nu - (k + 1)) : (j += 1) {
            if (row[j] != 0) allZero = false;
        }
        if (allZero) return @intCast(k);
    }
    return cap;
}

fn binomial(t: i64, k: i64) i64 {
    if (k < 0 or k > t) return 0;
    var acc: i64 = 1;
    var i: i64 = 1;
    while (i <= k) : (i += 1) {
        acc = @divExact(acc * (t - k + i), i); // running product stays integral
    }
    return acc;
}

/// The order-m truncated Newton–Mahler prediction at tick t:
/// f̂(t) = Σ_{k≤m} C(t,k) · Δ^k f(0). Returns 0 on bad args (prediction is a
/// value, not an rc — callers validate via s4_residual_loss's rc path).
pub export fn s4_newton_predict(f: [*c]const i64, n: i32, order: i32, t: i32) i64 {
    if (f == null or n < 1 or order < 0 or t < 0) return 0;
    const nu: usize = @intCast(n);
    if (nu > MAX_WINDOW) return 0;
    const m: usize = @min(@as(usize, @intCast(order)), nu - 1);
    var acc: i64 = 0;
    var k: usize = 0;
    while (k <= m) : (k += 1) {
        const row = nthDiffHead(f, nu, k);
        acc += binomial(@intCast(t), @intCast(k)) * row[0];
    }
    return acc;
}

/// The exact per-depth loss L_order = Σ_t |f(t) − f̂_order(t)| over the whole
/// window. −1 on bad args; otherwise ≥ 0, and 0 iff order ≥ certified order.
pub export fn s4_residual_loss(f: [*c]const i64, n: i32, order: i32) i64 {
    if (f == null or n < 1 or order < 0) return -1;
    const nu: usize = @intCast(n);
    if (nu > MAX_WINDOW) return -1;
    var acc: i64 = 0;
    var t: usize = 0;
    while (t < nu) : (t += 1) {
        const d = f[t] - s4_newton_predict(f, n, order, @intCast(t));
        acc += if (d < 0) -d else d;
    }
    return acc;
}
