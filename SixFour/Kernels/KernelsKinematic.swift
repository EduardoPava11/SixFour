//  KernelsKinematic.swift
//  Swift port of Native/src/kinematic.zig (2026-07-06); byte-exact twin, golden-gated.
//
//  KINEMATIC CERTIFICATION — the exact on-device observables of
//  Spec.KinematicLadder / Spec.KinematicHaltPrior, dependency-free
//  (imports NOTHING; pure i64 arithmetic, caller owns memory, C ABI).
//
//  A slot trajectory f(0..n-1) (one palette particle's channel over the
//  capture window) has:
//    * s4_certified_order: the smallest k < cap with Δ^{k+1} ≡ 0 on the
//      window — the trajectory's certified kinematic order. Computable BEFORE
//      any learning; this is the PonderNet halting-prior floor (the cheapest
//      zero-loss halt, Spec.KinematicHaltPrior keystone).
//    * s4_newton_predict: the order-m truncated Newton–Mahler prediction
//      f̂(t) = Σ_{k≤m} C(t,k)·Δ^k f(0) — the S-map at kinematic order m.
//    * s4_residual_loss: L_m = Σ_t |f(t) − f̂(t)| — the exact Integer
//      per-depth loss; L_m == 0 iff m ≥ certified order (minimal sufficiency).
//
//  TOTALITY: a window too short to falsify Δ^{k+1} ≡ 0 (n < k+2) must not
//  vacuously certify — s4_certified_order REFUSES cap ≥ n-1 with
//  S4K_RC_BAD_ARGS rather than certifying on an empty difference row (this is
//  STRICTER than the Haskell law harness, which always uses long windows).
//  Overflow honesty: differences and Newton terms stay well inside i64 for
//  byte/10-bit-code trajectories over ≤64-tick windows (|f| ≤ 2^20, C(63,k)
//  ≤ C(63,31) < 2^60 only for k>20 with alternating-sign Δ^k bounded by
//  2^{k}·max|f| — the caller keeps cap ≤ 8, documented in the header).

/// kinematic.zig's own bad-args rc (-1); refuse, never absorb.
let S4K_RC_BAD_ARGS: Int32 = -1

/// The maximum window length (the Zig stack-buffer bound).
private let MAX_WINDOW: Int = 256

/// Writes the k-th difference row into the first n-k entries of `buf`
/// (capacity MAX_WINDOW; the Zig by-value stack array, passed as scratch).
@inline(__always)
private func nthDiffHead(
    _ f: UnsafePointer<Int64>, _ n: Int, _ k: Int,
    _ buf: UnsafeMutablePointer<Int64>
) {
    for i in 0..<n { buf[i] = f[i] }
    for level in 0..<k {
        var j = 0
        while j + 1 < n - level {
            buf[j] = buf[j + 1] - buf[j]
            j += 1
        }
    }
}

/// The certified kinematic order: smallest k < cap with Δ^{k+1} ≡ 0 on the
/// whole window; cap if none certifies. Refuses null / n < 2 / cap < 0 /
/// windows too short to falsify (need n ≥ cap+2) / n > 256.
@_cdecl("s4_certified_order")
public func s4_certified_order(_ f: UnsafePointer<Int64>?, _ n: Int32, _ cap: Int32) -> Int32 {
    guard let f = f else { return S4K_RC_BAD_ARGS }
    if n < 2 || cap < 0 { return S4K_RC_BAD_ARGS }
    let nu = Int(n)
    let capu = Int(cap)
    if nu > MAX_WINDOW || nu < capu + 2 { return S4K_RC_BAD_ARGS }

    return withUnsafeTemporaryAllocation(of: Int64.self, capacity: MAX_WINDOW) { rowBuf in
        let row = rowBuf.baseAddress!
        for k in 0..<capu {
            nthDiffHead(f, nu, k + 1, row)
            var allZero = true
            for j in 0..<(nu - (k + 1)) {
                if row[j] != 0 { allZero = false }
            }
            if allZero { return Int32(k) }
        }
        return cap
    }
}

/// C(t,k) as an exact integer running product (Zig @divExact: the running
/// product `acc * (t-k+i)` is always divisible by `i`, so plain `/` is faithful).
@inline(__always)
private func binomial(_ t: Int64, _ k: Int64) -> Int64 {
    if k < 0 || k > t { return 0 }
    var acc: Int64 = 1
    var i: Int64 = 1
    while i <= k {
        acc = (acc * (t - k + i)) / i // running product stays integral
        i += 1
    }
    return acc
}

/// The order-m truncated Newton–Mahler prediction at tick t:
/// f̂(t) = Σ_{k≤m} C(t,k) · Δ^k f(0). Returns 0 on bad args (prediction is a
/// value, not an rc — callers validate via s4_residual_loss's rc path).
@_cdecl("s4_newton_predict")
public func s4_newton_predict(_ f: UnsafePointer<Int64>?, _ n: Int32, _ order: Int32, _ t: Int32) -> Int64 {
    guard let f = f else { return 0 }
    if n < 1 || order < 0 || t < 0 { return 0 }
    let nu = Int(n)
    if nu > MAX_WINDOW { return 0 }
    let m = min(Int(order), nu - 1)
    return withUnsafeTemporaryAllocation(of: Int64.self, capacity: MAX_WINDOW) { rowBuf in
        let row = rowBuf.baseAddress!
        var acc: Int64 = 0
        for k in 0...m {
            nthDiffHead(f, nu, k, row)
            acc += binomial(Int64(t), Int64(k)) * row[0]
        }
        return acc
    }
}

/// The exact per-depth loss L_order = Σ_t |f(t) − f̂_order(t)| over the whole
/// window. −1 on bad args; otherwise ≥ 0, and 0 iff order ≥ certified order.
@_cdecl("s4_residual_loss")
public func s4_residual_loss(_ f: UnsafePointer<Int64>?, _ n: Int32, _ order: Int32) -> Int64 {
    guard let f = f else { return -1 }
    if n < 1 || order < 0 { return -1 }
    let nu = Int(n)
    if nu > MAX_WINDOW { return -1 }
    var acc: Int64 = 0
    for t in 0..<nu {
        let d = f[t] - s4_newton_predict(f, n, order, Int32(t))
        acc += d < 0 ? -d : d
    }
    return acc
}
