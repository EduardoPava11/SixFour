import Testing
import Foundation
import simd
@testable import SixFour

/// Round-trip tests for CaptureBundle Codable conformance. The
/// bundle's Codable surface is the contract for disk persistence —
/// breaking it means existing on-disk bundles fail to load on
/// upgrade. These tests pin the bit-exact round-trip behavior.
struct CaptureBundleCodableTests {

    /// Minimal fixture bundle — 2 tiles, 4 clusters each, hand-built
    /// values that exercise every field of every nested type
    /// (covariance with non-zero off-diagonal, assignments with
    /// mixed values, BurstTiming with realistic numbers, etc.).
    private static func fixture() -> CaptureBundle {
        let side = 64
        let pixels = (0..<(side * side)).map { i in
            SIMD3<Float>(Float(i) / Float(side * side), 0.1, -0.1)
        }
        let tile = OKLabTile(
            side: side,
            pixels: pixels,
            captureNanos: 1_234_567_890,
            palette: [],
            finalShift: 0
        )
        let clusters: [ClusterStatistics.Cluster] = (0..<4).map { k in
            ClusterStatistics.Cluster(
                mean: SIMD3<Float>(Float(k) * 0.2, 0.05, -0.05),
                covariance: simd_float3x3(
                    columns: (
                        SIMD3<Float>(0.01, 0.002, 0.001),
                        SIMD3<Float>(0.002, 0.008, 0.0005),
                        SIMD3<Float>(0.001, 0.0005, 0.006)
                    )
                ),
                count: UInt32(100 + k)
            )
        }
        let stats = ClusterStatistics(
            clusters: clusters,
            assignments: Array(repeating: 0, count: side * side),
            provenance: ClusterStatistics.Provenance(
                family: .recursiveBipartitionWu,
                parameters: .wu(histogramBinsPerAxis: 32),
                extractMillis: 12,
                mse: 0.0123
            )
        )
        return CaptureBundle(
            id: UUID(uuidString: "DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF")!,
            captureTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
            burstTiming: CaptureSession.BurstTiming(
                frameCount: 64,
                durationMs: 3150.5,
                meanIntervalMs: 49.97,
                stdIntervalMs: 0.31,
                minIntervalMs: 49.5,
                maxIntervalMs: 50.5,
                targetIntervalMs: 50.0,
                worstAbsDeviationMs: 0.5,
                droppedFrameCount: 0
            ),
            colorSpaceTag: .hlgBT2020,
            tiles: [tile, tile],
            perFrameStatistics: [stats, stats]
        )
    }

    /// Encode → decode → verify every field survives.
    @Test func roundTripPreservesAllFields() throws {
        let bundle = Self.fixture()
        let encoder = JSONEncoder()
        let data = try encoder.encode(bundle)
        let decoded = try JSONDecoder().decode(CaptureBundle.self, from: data)

        #expect(decoded.id == bundle.id)
        #expect(decoded.captureTimestamp == bundle.captureTimestamp)
        #expect(decoded.colorSpaceTag == bundle.colorSpaceTag)
        #expect(decoded.tiles.count == bundle.tiles.count)
        #expect(decoded.perFrameStatistics.count == bundle.perFrameStatistics.count)

        // Tile pixels bit-exact (Codable for SIMD3<Float> uses Float
        // → JSON Number → Float, which preserves Float exactly for
        // values that fit in a Double — all OKLab values do).
        for (i, decodedTile) in decoded.tiles.enumerated() {
            let origTile = bundle.tiles[i]
            #expect(decodedTile.side == origTile.side)
            #expect(decodedTile.captureNanos == origTile.captureNanos)
            #expect(decodedTile.pixels.count == origTile.pixels.count)
            for (j, dp) in decodedTile.pixels.enumerated() {
                let op = origTile.pixels[j]
                #expect(dp.x == op.x && dp.y == op.y && dp.z == op.z,
                        "tile \(i) pixel \(j) drifted on round-trip")
            }
        }

        // BurstTiming.
        #expect(decoded.burstTiming.frameCount == bundle.burstTiming.frameCount)
        #expect(decoded.burstTiming.durationMs == bundle.burstTiming.durationMs)
        #expect(decoded.burstTiming.meanIntervalMs == bundle.burstTiming.meanIntervalMs)

        // ClusterStatistics provenance.
        let decProv = decoded.perFrameStatistics[0].provenance
        let origProv = bundle.perFrameStatistics[0].provenance
        #expect(decProv.family == origProv.family)
        #expect(decProv.parameters == origProv.parameters)
        #expect(decProv.extractMillis == origProv.extractMillis)
        #expect(decProv.mse == origProv.mse)

        // Cluster covariance — custom Codable flattens to 6 floats.
        let decCluster = decoded.perFrameStatistics[0].clusters[2]
        let origCluster = bundle.perFrameStatistics[0].clusters[2]
        #expect(decCluster.mean == origCluster.mean)
        #expect(decCluster.count == origCluster.count)
        // Symmetric Σ — compare all 6 upper-triangle entries.
        #expect(decCluster.covariance[0, 0] == origCluster.covariance[0, 0])
        #expect(decCluster.covariance[0, 1] == origCluster.covariance[0, 1])
        #expect(decCluster.covariance[0, 2] == origCluster.covariance[0, 2])
        #expect(decCluster.covariance[1, 1] == origCluster.covariance[1, 1])
        #expect(decCluster.covariance[1, 2] == origCluster.covariance[1, 2])
        #expect(decCluster.covariance[2, 2] == origCluster.covariance[2, 2])
        // Symmetry preserved on decode.
        #expect(decCluster.covariance[0, 1] == decCluster.covariance[1, 0])
        #expect(decCluster.covariance[0, 2] == decCluster.covariance[2, 0])
        #expect(decCluster.covariance[1, 2] == decCluster.covariance[2, 1])
    }

    /// save() → load() round-trip via a temp file (exercises the
    /// real disk path, not just in-memory Data).
    @Test func saveLoadRoundTripViaTempFile() throws {
        let bundle = Self.fixture()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sixfour_bundle_roundtrip_\(UUID().uuidString).json")
        try bundle.save(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let loaded = try CaptureBundle.load(from: tmp)
        #expect(loaded != nil, "load() returned nil for a file that exists")
        #expect(loaded?.id == bundle.id)
        #expect(loaded?.tiles.count == bundle.tiles.count)
    }

    /// load() returns nil when the file doesn't exist (caller
    /// shouldn't throw on first launch).
    @Test func loadMissingFileReturnsNil() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sixfour_does_not_exist_\(UUID().uuidString).json")
        let loaded = try CaptureBundle.load(from: tmp)
        #expect(loaded == nil)
    }
}
