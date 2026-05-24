import Foundation
import simd

/// Pure-function operations over `ClusterStatistics`. The editing-tool
/// math layer. No state, no I/O — just transforms from
/// `[ClusterStatistics.Cluster]` to derived quantities the editing UI
/// will eventually surface (χ² admission, principal-axis splits,
/// multicollinearity diagnostics).
///
/// Why "Ops" not "Statistics" — Phase B/C already produce a
/// `ClusterStatistics` type; this module consumes that type and
/// derives further quantities. Naming separates the *data* (Phase B/C)
/// from the *operations* on the data (Phase D).
///
/// Grounded in Fahmy's *Mathematics of Statistical Modelling*:
/// - Ch 1 §6 multivariate moments (already in `ClusterStatistics.Cluster`)
/// - Ch 2 + App A §4 PSD geometry + Mahalanobis (here)
/// - App B quadratic forms + App C multivariate Normal (here)
/// - App E χ² critical-values table (here)
/// - Ch 6 multicollinearity diagnostics (here)
enum ClusterStatisticsOps {

    // MARK: - 3×3 symmetric eigendecomposition (Smith 1961 closed-form)

    /// Real-symmetric 3×3 eigendecomposition via the analytical
    /// algorithm (Smith 1961). For real-symmetric M the characteristic
    /// polynomial is a depressed cubic after substitution
    /// `B = (M − qI)/p` (q = trace/3, p = scale); its three real
    /// roots give the eigenvalues directly via Cardano's trigonometric
    /// form. No iteration, no LAPACK Fortran interop, sub-microsecond
    /// per call.
    ///
    /// Returns eigenvalues ordered descending (λ₀ ≥ λ₁ ≥ λ₂) and
    /// eigenvectors as the **columns** of the returned matrix.
    /// Eigenvectors are normalized to unit length. For PSD inputs
    /// (which all `Cluster.covariance` matrices are), all eigenvalues
    /// are real ≥ 0.
    ///
    /// Edge cases:
    /// - Diagonal M (off-diagonal entries ≈ 0) → eigenvalues are the
    ///   diagonal entries, eigenvectors are the standard basis.
    /// - p ≈ 0 (M ≈ qI, scalar multiple of identity) → same as above
    ///   (all eigenvalues equal to trace/3, any orthonormal basis
    ///   works as eigenvectors).
    static func eigendecomposePSD(_ m: simd_float3x3) -> (values: SIMD3<Float>, vectors: simd_float3x3) {
        // M is assumed symmetric. We don't symmetrize defensively
        // because (a) it costs cycles and (b) all inputs from
        // `Cluster.covariance` are constructed as symmetric upper-
        // triangle assignments — symmetry is an upstream invariant.

        let p1 = m[0, 1] * m[0, 1] + m[0, 2] * m[0, 2] + m[1, 2] * m[1, 2]
        let q  = (m[0, 0] + m[1, 1] + m[2, 2]) / 3
        if p1 < 1e-12 {
            // Diagonal. Eigenvalues = diagonal entries (already sorted
            // by index, may not be in descending order — sort below).
            let raw = SIMD3<Float>(m[0, 0], m[1, 1], m[2, 2])
            return sortDescending(values: raw,
                                  vectors: simd_float3x3(diagonal: SIMD3<Float>(1, 1, 1)))
        }
        let d0 = m[0, 0] - q
        let d1 = m[1, 1] - q
        let d2 = m[2, 2] - q
        let p2 = d0 * d0 + d1 * d1 + d2 * d2 + 2 * p1
        let p  = sqrt(p2 / 6)
        if p < 1e-12 {
            // Scalar multiple of identity. All eigenvalues = q.
            let raw = SIMD3<Float>(q, q, q)
            return (raw, simd_float3x3(diagonal: SIMD3<Float>(1, 1, 1)))
        }

        // B = (M − qI) / p; det(B)/2 ∈ [-1, 1] for real-symmetric M.
        // Tiny numerical overflow happens; clamp before acos.
        let B = simd_float3x3(
            columns: (
                SIMD3<Float>(d0 / p, m[0, 1] / p, m[0, 2] / p),
                SIMD3<Float>(m[1, 0] / p, d1 / p, m[1, 2] / p),
                SIMD3<Float>(m[2, 0] / p, m[2, 1] / p, d2 / p)
            )
        )
        let r = simd_determinant(B) / 2
        let rClamped = max(-Float(1), min(Float(1), r))
        let phi = acosf(rClamped) / 3
        // Closed-form roots (Cardano trig). Sorted descending by
        // construction: λ₀ = q + 2p cos(φ) is the largest.
        let twoP = 2 * p
        let λ0 = q + twoP * cosf(phi)
        let λ2 = q + twoP * cosf(phi + 2 * .pi / 3)
        let λ1 = 3 * q - λ0 - λ2  // trace invariance saves one cos

        // Eigenvectors via cross-product null-space: rows of
        // (M − λᵢI) span a 2D subspace whose normal is the eigenvector.
        // Picking the cross product of the two longest rows avoids
        // near-zero results when one row is degenerate.
        let v0 = nullSpaceVector(matrix: m, eigenvalue: λ0)
        let v1 = nullSpaceVector(matrix: m, eigenvalue: λ1)
        let v2 = nullSpaceVector(matrix: m, eigenvalue: λ2)
        let vectors = simd_float3x3(columns: (v0, v1, v2))
        return (SIMD3<Float>(λ0, λ1, λ2), vectors)
    }

    /// Cross-product null-space helper. (M − λI) has rank ≤ 2 for an
    /// eigenvalue λ of M; its rows span a plane, and any vector
    /// perpendicular to that plane (i.e., the cross product of two
    /// linearly independent rows) lies in the null space — that's
    /// the eigenvector. Picking the cross product of the two longest
    /// rows avoids the degenerate-row trap.
    private static func nullSpaceVector(matrix m: simd_float3x3, eigenvalue λ: Float) -> SIMD3<Float> {
        // Rows of (M − λI). For symmetric M, rows == columns; we
        // use Apple's column-major .columns accessor.
        let r0 = SIMD3<Float>(m[0, 0] - λ, m[0, 1], m[0, 2])
        let r1 = SIMD3<Float>(m[1, 0], m[1, 1] - λ, m[1, 2])
        let r2 = SIMD3<Float>(m[2, 0], m[2, 1], m[2, 2] - λ)
        let v01 = simd_cross(r0, r1)
        let v02 = simd_cross(r0, r2)
        let v12 = simd_cross(r1, r2)
        let m01 = simd_length_squared(v01)
        let m02 = simd_length_squared(v02)
        let m12 = simd_length_squared(v12)
        let v: SIMD3<Float>
        if m01 >= m02 && m01 >= m12 {
            v = v01
        } else if m02 >= m12 {
            v = v02
        } else {
            v = v12
        }
        let len = simd_length(v)
        if len < 1e-12 {
            // Pathological — return an axis-aligned guess. Caller
            // should treat eigenvector validity as conditional on
            // eigenvalue magnitude anyway.
            return SIMD3<Float>(1, 0, 0)
        }
        return v / len
    }

    private static func sortDescending(values: SIMD3<Float>, vectors: simd_float3x3)
        -> (values: SIMD3<Float>, vectors: simd_float3x3)
    {
        var pairs: [(λ: Float, v: SIMD3<Float>)] = [
            (values[0], SIMD3<Float>(vectors[0, 0], vectors[0, 1], vectors[0, 2])),
            (values[1], SIMD3<Float>(vectors[1, 0], vectors[1, 1], vectors[1, 2])),
            (values[2], SIMD3<Float>(vectors[2, 0], vectors[2, 1], vectors[2, 2]))
        ]
        pairs.sort { $0.λ > $1.λ }
        return (
            SIMD3<Float>(pairs[0].λ, pairs[1].λ, pairs[2].λ),
            simd_float3x3(columns: (pairs[0].v, pairs[1].v, pairs[2].v))
        )
    }

    // MARK: - χ²₃ admission

    /// χ²₃ critical values (the 3-degree-of-freedom chi-squared
    /// distribution's quantiles). Used to gate cluster admission:
    /// a cluster's centroid is "statistically significant" relative
    /// to the population if its squared Mahalanobis distance from
    /// the population mean exceeds the α-level critical value.
    /// (Fahmy App E.) Table covers the 5 α values the editing UI
    /// will expose; interpolation would be needed for other α.
    enum ChiSquare3 {
        /// Right-tail critical values: P(χ²₃ > value) = α.
        static func critical(alpha α: Float) -> Float {
            switch α {
            case 0.001: return 16.266
            case 0.01:  return 11.345
            case 0.025: return 9.348
            case 0.05:  return 7.815
            case 0.10:  return 6.251
            default:    return 7.815  // safe default = α=0.05
            }
        }
    }

    /// Mahalanobis² distance of `cluster.mean` from `populationMean`
    /// under metric `populationCovariance`. Squared form (no sqrt)
    /// because the χ² test compares against a squared critical value.
    /// Returns +∞ if the population covariance is numerically
    /// singular (consumer should treat as "always significant").
    static func mahalanobisSquared(
        cluster: ClusterStatistics.Cluster,
        populationMean μ: SIMD3<Float>,
        populationCovariance Σ: simd_float3x3
    ) -> Float {
        let d = cluster.mean - μ
        // Determinant test for invertibility — at 3×3 it's cheap and
        // avoids NaN propagation when Σ is near-singular.
        let det = simd_determinant(Σ)
        if abs(det) < 1e-12 { return .infinity }
        let Σinv = simd_inverse(Σ)
        let Md = SIMD3<Float>(
            Σinv[0, 0] * d.x + Σinv[1, 0] * d.y + Σinv[2, 0] * d.z,
            Σinv[0, 1] * d.x + Σinv[1, 1] * d.y + Σinv[2, 1] * d.z,
            Σinv[0, 2] * d.x + Σinv[1, 2] * d.y + Σinv[2, 2] * d.z
        )
        return simd_dot(d, Md)
    }

    /// Returns the indices of clusters whose centroids pass the χ²₃
    /// admission test at level α — i.e., are statistically far enough
    /// from the population mean to reject "this cluster is just noise"
    /// at confidence (1 − α). Empty clusters (count == 0) are
    /// automatically excluded — they have no population presence to
    /// be significant relative to.
    ///
    /// Editing-tool consumption: a cluster failing this test is a
    /// candidate for pruning + refill via `splitAlongPrincipalAxis`
    /// of a surviving high-variance cluster.
    static func chiSquareAdmission(
        clusters: [ClusterStatistics.Cluster],
        alpha: Float,
        populationMean μ: SIMD3<Float>,
        populationCovariance Σ: simd_float3x3
    ) -> (admitted: [Int], rejected: [Int]) {
        let threshold = ChiSquare3.critical(alpha: alpha)
        var admitted: [Int] = []
        var rejected: [Int] = []
        for (i, c) in clusters.enumerated() {
            if c.count == 0 {
                rejected.append(i)
                continue
            }
            let m2 = mahalanobisSquared(cluster: c, populationMean: μ, populationCovariance: Σ)
            if m2 > threshold {
                admitted.append(i)
            } else {
                rejected.append(i)
            }
        }
        return (admitted, rejected)
    }

    /// Population (pooled) mean of a cluster set — count-weighted
    /// average of cluster means. Used as the χ² test's reference μ.
    static func pooledMean(_ clusters: [ClusterStatistics.Cluster]) -> SIMD3<Float> {
        var sum: SIMD3<Float> = .zero
        var n: Float = 0
        for c in clusters where c.count > 0 {
            sum += c.mean * Float(c.count)
            n += Float(c.count)
        }
        if n < 1 { return .zero }
        return sum / n
    }

    /// Population (pooled) covariance — count-weighted sum of
    /// per-cluster Σs plus the between-cluster scatter (law of total
    /// covariance). For χ²₃ test purposes, the pooled within +
    /// between is the "noise floor" against which cluster means
    /// are compared.
    static func pooledCovariance(
        _ clusters: [ClusterStatistics.Cluster],
        pooledMean μ_p: SIMD3<Float>
    ) -> simd_float3x3 {
        var pooled = simd_float3x3(0)
        var n: Float = 0
        for c in clusters where c.count > 0 {
            let nk = Float(c.count)
            n += nk
            // Within-cluster contribution: n_k * Σ_k
            pooled.columns.0 += c.covariance.columns.0 * nk
            pooled.columns.1 += c.covariance.columns.1 * nk
            pooled.columns.2 += c.covariance.columns.2 * nk
            // Between-cluster scatter: n_k * (μ_k - μ_p)(μ_k - μ_p)ᵀ
            let d = c.mean - μ_p
            let outer = simd_float3x3(
                columns: (
                    SIMD3<Float>(d.x * d.x, d.y * d.x, d.z * d.x),
                    SIMD3<Float>(d.x * d.y, d.y * d.y, d.z * d.y),
                    SIMD3<Float>(d.x * d.z, d.y * d.z, d.z * d.z)
                )
            )
            pooled.columns.0 += outer.columns.0 * nk
            pooled.columns.1 += outer.columns.1 * nk
            pooled.columns.2 += outer.columns.2 * nk
        }
        if n < 1 { return ClusterStatistics.Cluster.emptyCovariance }
        let inv = 1 / n
        var scaled = simd_float3x3(0)
        scaled.columns.0 = pooled.columns.0 * inv
        scaled.columns.1 = pooled.columns.1 * inv
        scaled.columns.2 = pooled.columns.2 * inv
        return scaled
    }

    // MARK: - Multicollinearity (Fahmy Ch 6)

    /// Condition number of the K-centroid matrix C ∈ ℝ^(K×3),
    /// computed as κ(C) = √(λ_max(CᵀC) / λ_min(CᵀC)) where CᵀC is
    /// the 3×3 Gram matrix. High κ → centroids are nearly
    /// linearly dependent → the palette has wasted slots that the
    /// editing UI should prune + refill.
    ///
    /// Returns +∞ for rank-deficient sets (e.g., all centroids on a
    /// plane → λ_min ≈ 0). Empty clusters are skipped.
    static func centroidConditionNumber(_ clusters: [ClusterStatistics.Cluster]) -> Float {
        // Build CᵀC (3×3) incrementally: it's Σ_k μ_k * μ_kᵀ for
        // non-empty clusters. Avoids materializing the full K×3 matrix.
        var gram = simd_float3x3(0)
        var anyCluster = false
        for c in clusters where c.count > 0 {
            anyCluster = true
            let μ = c.mean
            gram.columns.0 += SIMD3<Float>(μ.x * μ.x, μ.y * μ.x, μ.z * μ.x)
            gram.columns.1 += SIMD3<Float>(μ.x * μ.y, μ.y * μ.y, μ.z * μ.y)
            gram.columns.2 += SIMD3<Float>(μ.x * μ.z, μ.y * μ.z, μ.z * μ.z)
        }
        if !anyCluster { return .infinity }
        let (eigenvalues, _) = eigendecomposePSD(gram)
        // Eigenvalues already sorted descending. λ_min is index 2.
        let λMax = max(0, eigenvalues[0])
        let λMin = max(0, eigenvalues[2])
        if λMin < 1e-12 { return .infinity }
        return sqrt(λMax / λMin)
    }

    // MARK: - PCA split

    /// Split a cluster along its principal axis: returns two new
    /// centroids displaced by ±√λ₁ along the top eigenvector of the
    /// cluster's covariance. The editing UI uses this to backfill
    /// palette slots vacated by χ² admission rejections — replace
    /// one rejected slot with two new centroids extracted from the
    /// surviving cluster with the largest principal eigenvalue
    /// (most "splittable" — highest spread along its top axis).
    ///
    /// Returned pair is symmetric around the original `cluster.mean`;
    /// caller assigns each to a palette slot. The two new centroids
    /// don't yet have populated counts/covariances — those will come
    /// from re-running the dither (or re-extraction) against the
    /// new palette.
    ///
    /// Edge case: empty cluster or near-zero λ₁ → returns
    /// `(cluster.mean, cluster.mean)` (duplicate; consumer must
    /// handle gracefully — typically by picking a different cluster
    /// to split).
    static func splitAlongPrincipalAxis(_ cluster: ClusterStatistics.Cluster)
        -> (SIMD3<Float>, SIMD3<Float>)
    {
        if cluster.count == 0 { return (cluster.mean, cluster.mean) }
        let (values, vectors) = eigendecomposePSD(cluster.covariance)
        let λ1 = max(0, values[0])
        if λ1 < 1e-8 { return (cluster.mean, cluster.mean) }
        let v1 = SIMD3<Float>(vectors[0, 0], vectors[0, 1], vectors[0, 2])
        let displacement = v1 * sqrt(λ1)
        return (cluster.mean + displacement, cluster.mean - displacement)
    }
}
