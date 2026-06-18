import Foundation

/// COLOR ATLAS — the preference-training KILL-SWITCH (port of `SixFour.Spec.GLRM`;
/// docs/SIXFOUR-ALPHAZERO-COLLAPSE-DESIGN §5.4, §6 RLHF-hygiene).
///
/// Before any preference net trains on the user's A/B (Bradley-Terry) picks,
/// regress the logged outcomes on the deterministic, golden-computable features
/// `[coverage, beauty, ‖chroma‖²]` by ordinary least squares. If the data carries
/// no stable linear signal — a singular design, or `R²` below `r2Floor` — the
/// preference data is noise and training is BLOCKED. This is the
/// reward-model-calibration discipline that stops the value/policy net from
/// chasing a phantom utility (the "did not train well" failure the supervised
/// look-net hit).
///
/// Byte-exact vs the Haskell spec (`GLRMGoldenTests` pins the same goldens): the
/// summation order of every dot/normal-equation matches `Spec.GLRM`, so the
/// `Double` arithmetic is bit-identical. The small Gauss-Jordan solve is
/// hand-written here, not borrowed.
enum GLRM {

    /// The three deterministic regressors: `(coverage, beauty, ‖chroma‖²)`.
    typealias Features = (coverage: Double, beauty: Double, chromaSq: Double)

    /// The OLS design row WITH intercept: `[1, coverage, beauty, ‖chroma‖²]`.
    static func designRow(_ f: Features) -> [Double] { [1, f.coverage, f.beauty, f.chromaSq] }

    /// Number of fitted parameters (intercept + 3 features).
    static let nParams = 4
    /// The minimum explained variance for training to proceed.
    static let r2Floor = 0.1
    /// The singular-pivot threshold.
    static let pivotEps = 1e-12
    /// Below this embedding separation, a BT pair carries ~no gradient.
    static let informativeThreshold = 1e-6

    /// An OLS fit: the coefficient vector (`designRow` order) and `R²`.
    struct Fit: Equatable { var coeffs: [Double]; var r2: Double }

    private static func isFinite(_ x: Double) -> Bool { !x.isNaN && !x.isInfinite }

    /// `Σ aᵢ·bᵢ`, left-to-right (matches `Spec.GLRM.dot`).
    private static func dot(_ a: [Double], _ b: [Double]) -> Double {
        var s = 0.0
        for i in 0 ..< min(a.count, b.count) { s += a[i] * b[i] }
        return s
    }

    /// Solve `A x = b` for a square `A` by Gauss-Jordan with partial pivoting.
    /// `nil` iff `A` is singular (a pivot magnitude below `pivotEps`) — exactly the
    /// "no information in the design" case the kill-switch must catch. Mirrors
    /// `Spec.GLRM.solveLinear`.
    static func solveLinear(_ a: [[Double]], _ b: [Double]) -> [Double]? {
        let n = b.count
        var m = (0 ..< n).map { a[$0] + [b[$0]] } // augmented rows
        var k = 0
        while k < n {
            // partial pivot: the row (≥ k) with the largest |m[i][k]|
            var pr = k
            var pv = abs(m[k][k])
            var i = k + 1
            while i < n { let v = abs(m[i][k]); if v > pv { pv = v; pr = i }; i += 1 }
            if pv < pivotEps { return nil }
            if pr != k { m.swapAt(k, pr) }
            let piv = m[k][k]
            let pivRow = m[k].map { $0 / piv }
            var r = 0
            while r < n {
                if r == k {
                    m[r] = pivRow
                } else {
                    let f = m[r][k]
                    m[r] = zip(m[r], pivRow).map { $0 - f * $1 }
                }
                r += 1
            }
            k += 1
        }
        return m.map { $0[n] }
    }

    /// Fit `y ~ [1, coverage, beauty, ‖chroma‖²]` by OLS. `nil` when the fit is
    /// meaningless: fewer than `nParams` samples, no variance in `y` (R² undefined),
    /// a singular normal-equation system, or non-finite coefficients. Mirrors
    /// `Spec.GLRM.fitGLRM`.
    static func fit(_ samples: [(Features, Double)]) -> Fit? {
        guard samples.count >= nParams else { return nil }
        let xs = samples.map { designRow($0.0) }
        let ys = samples.map { $0.1 }
        let ybar = ys.reduce(0, +) / Double(ys.count)
        var sstot = 0.0
        for y in ys { sstot += (y - ybar) * (y - ybar) }
        guard sstot > 0 else { return nil }

        // Normal equations: (XᵀX) β = Xᵀy, accumulated in spec order.
        var xtx = [[Double]](repeating: [Double](repeating: 0, count: nParams), count: nParams)
        for i in 0 ..< nParams {
            for j in 0 ..< nParams {
                var s = 0.0
                for row in xs { s += row[i] * row[j] }
                xtx[i][j] = s
            }
        }
        var xty = [Double](repeating: 0, count: nParams)
        for i in 0 ..< nParams {
            var s = 0.0
            for (row, y) in zip(xs, ys) { s += row[i] * y }
            xty[i] = s
        }

        guard let beta = solveLinear(xtx, xty), beta.allSatisfy(isFinite) else { return nil }
        var ssres = 0.0
        for (row, y) in zip(xs, ys) { let p = dot(beta, row); ssres += (y - p) * (y - p) }
        let r2 = 1 - ssres / sstot
        guard isFinite(r2) else { return nil }
        return Fit(coeffs: beta, r2: r2)
    }

    /// The kill-switch: train ONLY if there is a stable fit clearing `r2Floor`.
    /// Otherwise STOP (the preference data is noise). Mirrors `Spec.GLRM.shouldTrain`.
    static func shouldTrain(_ samples: [(Features, Double)]) -> Bool {
        guard let f = fit(samples) else { return false }
        return f.r2 >= r2Floor && f.coeffs.allSatisfy(isFinite)
    }

    /// Squared L2 distance between two candidate embeddings.
    static func embDistSq(_ a: [Double], _ b: [Double]) -> Double {
        var s = 0.0
        for i in 0 ..< min(a.count, b.count) { let d = a[i] - b[i]; s += d * d }
        return s
    }

    /// The training weight of a gallery pair: 0 for a degenerate (too-close) pair,
    /// else 1. Mirrors `Spec.GLRM.pairWeight`.
    static func pairWeight(_ a: [Double], _ b: [Double]) -> Double {
        embDistSq(a, b) < informativeThreshold ? 0 : 1
    }
}
