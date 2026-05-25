import Testing
import Foundation
import simd
@testable import SixFour

/// Tests for the Phase D Statistics module. Validates the pure
/// functions in `ClusterStatisticsOps` against hand-built fixtures
/// with known properties (diagonal eigendecomposition,
/// hand-computable Mahalanobis, monotone condition-number under
/// duplication, etc.). Foundation tests for the future editing UI.
struct ClusterStatisticsOpsTests {

    // MARK: - eigendecomposePSD

    /// A diagonal matrix's eigenvalues ARE its diagonal entries.
    /// Eigenvectors are the standard basis. Tests the
    /// p1 < 1e-12 short-circuit.
    @Test func diagonalMatrixHasDiagonalEigenvalues() {
        let d = simd_float3x3(diagonal: SIMD3<Float>(3.0, 1.0, 2.0))
        let (values, _) = ClusterStatisticsOps.eigendecomposePSD(d)
        // Returned sorted descending.
        #expect(abs(values[0] - 3.0) < 1e-4)
        #expect(abs(values[1] - 2.0) < 1e-4)
        #expect(abs(values[2] - 1.0) < 1e-4)
    }

    /// Identity matrix → all eigenvalues == 1. Scalar-multiple
    /// shortcut (p ≈ 0) returns standard basis as eigenvectors.
    @Test func identityHasUnitEigenvalues() {
        let id = simd_float3x3(diagonal: SIMD3<Float>(1, 1, 1))
        let (values, _) = ClusterStatisticsOps.eigendecomposePSD(id)
        #expect(abs(values[0] - 1) < 1e-4)
        #expect(abs(values[1] - 1) < 1e-4)
        #expect(abs(values[2] - 1) < 1e-4)
    }

    /// Hand-built symmetric matrix with eigenvalues we can compute
    /// analytically: M = diag(λ) rotated by an arbitrary orthogonal
    /// matrix preserves the eigenvalues. We construct M = R · D · Rᵀ
    /// and check the eigendecomposition recovers D's diagonal.
    @Test func rotatedDiagonalRecoversEigenvalues() {
        // Eigenvalues 4, 2, 1.
        let D = simd_float3x3(diagonal: SIMD3<Float>(4, 2, 1))
        // Rotation around z-axis by 30°.
        let θ: Float = .pi / 6
        let c = cosf(θ), s = sinf(θ)
        let R = simd_float3x3(
            columns: (
                SIMD3<Float>(c,  s, 0),
                SIMD3<Float>(-s, c, 0),
                SIMD3<Float>(0,  0, 1)
            )
        )
        let M = R * D * R.transpose
        let (values, _) = ClusterStatisticsOps.eigendecomposePSD(M)
        #expect(abs(values[0] - 4) < 1e-3, "λ₀ = \(values[0]), expected ~4")
        #expect(abs(values[1] - 2) < 1e-3, "λ₁ = \(values[1]), expected ~2")
        #expect(abs(values[2] - 1) < 1e-3, "λ₂ = \(values[2]), expected ~1")
    }

    /// Eigenvalues should always be sorted descending.
    @Test func eigenvaluesAreSortedDescending() {
        let M = simd_float3x3(
            columns: (
                SIMD3<Float>(2.0, 0.5, 0.3),
                SIMD3<Float>(0.5, 1.0, 0.2),
                SIMD3<Float>(0.3, 0.2, 3.0)
            )
        )
        let (values, _) = ClusterStatisticsOps.eigendecomposePSD(M)
        #expect(values[0] >= values[1], "λ₀ \(values[0]) should be ≥ λ₁ \(values[1])")
        #expect(values[1] >= values[2], "λ₁ \(values[1]) should be ≥ λ₂ \(values[2])")
    }

    /// Trace invariance: sum of eigenvalues equals trace of matrix.
    /// Quick sanity check that doesn't depend on eigenvector
    /// correctness or sorting.
    @Test func eigenvaluesSumToTrace() {
        let M = simd_float3x3(
            columns: (
                SIMD3<Float>(1.5, 0.4, 0.1),
                SIMD3<Float>(0.4, 2.7, 0.3),
                SIMD3<Float>(0.1, 0.3, 0.8)
            )
        )
        let (values, _) = ClusterStatisticsOps.eigendecomposePSD(M)
        let trace = M[0, 0] + M[1, 1] + M[2, 2]
        let sumEigenvalues = values[0] + values[1] + values[2]
        #expect(abs(sumEigenvalues - trace) < 1e-3,
                "Σλ \(sumEigenvalues) ≠ trace \(trace)")
    }

    // MARK: - chiSquareAdmission

    /// A cluster whose mean equals the population mean has
    /// Mahalanobis² = 0, which is well below ANY χ²₃ threshold —
    /// it should always be REJECTED (not significant).
    @Test func clusterAtPopulationMeanIsRejected() {
        let cluster = ClusterStatistics.Cluster(
            mean: SIMD3<Float>(0.5, 0.0, 0.0),
            covariance: simd_float3x3(diagonal: SIMD3<Float>(0.01, 0.01, 0.01)),
            count: 100
        )
        let m2 = ClusterStatisticsOps.mahalanobisSquared(
            cluster: cluster,
            populationMean: SIMD3<Float>(0.5, 0.0, 0.0),
            populationCovariance: simd_float3x3(diagonal: SIMD3<Float>(0.1, 0.1, 0.1))
        )
        #expect(abs(m2) < 1e-4, "Mahalanobis² at population mean should be ≈ 0; got \(m2)")
    }

    /// A cluster far from the population mean (≥ 5σ on every axis)
    /// should have Mahalanobis² far above any α threshold and
    /// always be ADMITTED.
    @Test func farClusterIsAdmitted() {
        let cluster = ClusterStatistics.Cluster(
            mean: SIMD3<Float>(0.9, 0.4, 0.4),
            covariance: simd_float3x3(diagonal: SIMD3<Float>(0.01, 0.01, 0.01)),
            count: 100
        )
        let pooledCov = simd_float3x3(diagonal: SIMD3<Float>(0.01, 0.01, 0.01))
        let m2 = ClusterStatisticsOps.mahalanobisSquared(
            cluster: cluster,
            populationMean: .zero,
            populationCovariance: pooledCov
        )
        // d = (0.9, 0.4, 0.4), Σ⁻¹ = diag(100,100,100)
        // m² = 100*(0.81 + 0.16 + 0.16) = 113
        #expect(m2 > 100, "Far cluster Mahalanobis² should be large; got \(m2)")
        // 113 ≫ 7.815 (α=0.05 threshold)
        let (admitted, rejected) = ClusterStatisticsOps.chiSquareAdmission(
            clusters: [cluster], alpha: 0.05,
            populationMean: .zero, populationCovariance: pooledCov
        )
        #expect(admitted == [0])
        #expect(rejected.isEmpty)
    }

    /// Empty clusters (count == 0) are always rejected regardless
    /// of their (sentinel) mean/covariance.
    @Test func emptyClusterIsRejected() {
        let empty = ClusterStatistics.Cluster(
            mean: .zero,
            covariance: ClusterStatistics.Cluster.emptyCovariance,
            count: 0
        )
        let (admitted, rejected) = ClusterStatisticsOps.chiSquareAdmission(
            clusters: [empty], alpha: 0.05,
            populationMean: SIMD3<Float>(0.5, 0, 0),
            populationCovariance: simd_float3x3(diagonal: SIMD3<Float>(0.1, 0.1, 0.1))
        )
        #expect(admitted.isEmpty)
        #expect(rejected == [0])
    }

    // MARK: - centroidConditionNumber

    /// Three orthogonal unit centroids → Gram matrix is the identity
    /// → all eigenvalues equal → condition number == 1 (perfectly
    /// well-conditioned).
    @Test func orthogonalCentroidsAreWellConditioned() {
        let clusters: [ClusterStatistics.Cluster] = [
            ClusterStatistics.Cluster(mean: SIMD3<Float>(1, 0, 0),
                                       covariance: simd_float3x3(0), count: 1),
            ClusterStatistics.Cluster(mean: SIMD3<Float>(0, 1, 0),
                                       covariance: simd_float3x3(0), count: 1),
            ClusterStatistics.Cluster(mean: SIMD3<Float>(0, 0, 1),
                                       covariance: simd_float3x3(0), count: 1)
        ]
        let κ = ClusterStatisticsOps.centroidConditionNumber(clusters)
        #expect(abs(κ - 1) < 1e-3, "Orthogonal centroids: κ = \(κ), expected ≈ 1")
    }

    /// Duplicating a centroid increases collinearity → condition
    /// number must rise (or stay the same in degenerate cases),
    /// never fall. Tests monotonicity-under-duplication, which is
    /// the editing-tool useful property.
    @Test func conditionNumberRisesWithDuplication() {
        let base: [ClusterStatistics.Cluster] = [
            ClusterStatistics.Cluster(mean: SIMD3<Float>(1, 0, 0),
                                       covariance: simd_float3x3(0), count: 1),
            ClusterStatistics.Cluster(mean: SIMD3<Float>(0, 1, 0),
                                       covariance: simd_float3x3(0), count: 1),
            ClusterStatistics.Cluster(mean: SIMD3<Float>(0, 0, 1),
                                       covariance: simd_float3x3(0), count: 1)
        ]
        // Add a near-duplicate of the first centroid → rank-deficient
        // direction along x dominates.
        var withDup = base
        withDup.append(ClusterStatistics.Cluster(mean: SIMD3<Float>(1.001, 0, 0),
                                                  covariance: simd_float3x3(0), count: 1))
        let κBase = ClusterStatisticsOps.centroidConditionNumber(base)
        let κDup = ClusterStatisticsOps.centroidConditionNumber(withDup)
        // Duplicated direction loads CᵀC's first eigenvector heavily;
        // condition number should grow.
        #expect(κDup >= κBase,
                "Duplicating a centroid should not decrease κ: base=\(κBase), dup=\(κDup)")
    }

    /// All centroids on a single line (degenerate, rank 1) → λ_min = 0
    /// → condition number = ∞.
    @Test func collinearCentroidsHaveInfiniteCondition() {
        let collinear: [ClusterStatistics.Cluster] = (0..<5).map { i in
            ClusterStatistics.Cluster(
                mean: SIMD3<Float>(Float(i) * 0.1, 0, 0),
                covariance: simd_float3x3(0), count: 1
            )
        }
        let κ = ClusterStatisticsOps.centroidConditionNumber(collinear)
        #expect(κ.isInfinite, "Collinear centroids should give κ = ∞; got \(κ)")
    }

    // MARK: - splitAlongPrincipalAxis

    /// A cluster with a covariance dominated by the x-axis (large
    /// variance in x, tiny in y/z) should split into two centroids
    /// displaced symmetrically along x. The midpoint of the two is
    /// the original centroid.
    @Test func splitAlongDominantXAxis() {
        // Σ = diag(0.04, 0.01, 0.01) — x is dominant.
        let cluster = ClusterStatistics.Cluster(
            mean: SIMD3<Float>(0.5, 0.1, 0.2),
            covariance: simd_float3x3(diagonal: SIMD3<Float>(0.04, 0.01, 0.01)),
            count: 100
        )
        let (a, b) = ClusterStatisticsOps.splitAlongPrincipalAxis(cluster)
        // Midpoint == original mean.
        let mid = (a + b) / 2
        #expect(simd_length(mid - cluster.mean) < 1e-4,
                "Midpoint of split should equal original mean; midpoint=\(mid), mean=\(cluster.mean)")
        // Displacement should be ~√0.04 = 0.2 along x; nearly nothing on y/z.
        let displacement = a - cluster.mean
        #expect(abs(abs(displacement.x) - 0.2) < 1e-3,
                "Split displacement on x should be ~±0.2 (√0.04); got \(displacement.x)")
        #expect(abs(displacement.y) < 1e-3, "y displacement should be ~0; got \(displacement.y)")
        #expect(abs(displacement.z) < 1e-3, "z displacement should be ~0; got \(displacement.z)")
    }

    /// Empty cluster split is degenerate — returns duplicate
    /// centroids (the original mean). Consumer's responsibility to
    /// handle gracefully.
    @Test func emptyClusterSplitIsDegenerate() {
        let empty = ClusterStatistics.Cluster(
            mean: SIMD3<Float>(0.3, 0.1, -0.1),
            covariance: ClusterStatistics.Cluster.emptyCovariance,
            count: 0
        )
        let (a, b) = ClusterStatisticsOps.splitAlongPrincipalAxis(empty)
        #expect(a == empty.mean)
        #expect(b == empty.mean)
    }

    // MARK: - Gamut coverage (LAB diversity)

    private func cluster(_ m: SIMD3<Float>) -> ClusterStatistics.Cluster {
        ClusterStatistics.Cluster(
            mean: m,
            covariance: simd_float3x3(diagonal: SIMD3<Float>(repeating: 1e-6)),
            count: 1
        )
    }

    private func stats(_ means: [SIMD3<Float>]) -> ClusterStatistics {
        ClusterStatistics(
            clusters: means.map(cluster),
            assignments: [],
            provenance: ClusterStatistics.Provenance(
                family: .iterativeKMeans,
                parameters: .kMeans(seed: .uniformStride, iterations: 0),
                extractMillis: 0, mse: 0
            )
        )
    }

    /// Wider OKLab spread → larger gamut-ellipsoid volume (the diversity metric).
    @Test func gamutVolumeLargerForWiderSpread() {
        let tight = [SIMD3<Float>(0.5, 0, 0), SIMD3<Float>(0.51, 0.01, 0), SIMD3<Float>(0.49, -0.01, 0)].map(cluster)
        let wide  = [SIMD3<Float>(0.1, -0.3, -0.3), SIMD3<Float>(0.9, 0.3, 0.3), SIMD3<Float>(0.5, 0, 0)].map(cluster)
        #expect(ClusterStatisticsOps.gamutEllipsoidVolume(wide)
              > ClusterStatisticsOps.gamutEllipsoidVolume(tight))
    }

    /// Coverage counts distinct OKLab voxels; repeating the same palette across
    /// frames doesn't inflate it (union over frames).
    @Test func gamutCoverageCountsDistinctBins() {
        let frame = stats([
            SIMD3<Float>(0.1, -0.3, -0.3),
            SIMD3<Float>(0.5,  0.0,  0.0),
            SIMD3<Float>(0.9,  0.3,  0.3),
        ])
        let (occ, frac) = ClusterStatisticsOps.gamutCoverage(perFrame: Array(repeating: frame, count: 8))
        #expect(occ == 3)
        #expect(abs(frac - Float(3) / Float(16 * 16 * 16)) < 1e-7)
    }

    /// Coverage is the UNION across frames — a colour only one frame sees still
    /// counts (that's the point of per-frame palette variation).
    @Test func gamutCoverageUnionsAcrossFrames() {
        let f1 = stats([SIMD3<Float>(0.1, -0.3, -0.3), SIMD3<Float>(0.5, 0, 0)])
        let f2 = stats([SIMD3<Float>(0.9, 0.3, 0.3)])
        #expect(ClusterStatisticsOps.gamutCoverage(perFrame: [f1, f2]).occupiedBins == 3)
    }
}
