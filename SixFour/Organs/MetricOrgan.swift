import Foundation
import simd

/// The metric organ is so small (≤ 9 floats) that it ships as JSON, NOT Core ML.
/// File format: `{"m": [a00, a01, a02, a11, a12, a22]}` — upper triangle of PSD M.
/// On disk: `<hash>.metric.json`.
struct MetricOrgan: Organ, Sendable {
    let descriptor: OrganDescriptor
    let metric: LearnedPSDMetric

    init(descriptor: OrganDescriptor, fileURL: URL) throws {
        if descriptor.slot != .metric {
            throw OrganError.wrongSlot(expected: .metric, got: descriptor.slot)
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw OrganError.fileMissing(fileURL)
        }
        let data: Data
        do { data = try Data(contentsOf: fileURL) }
        catch { throw OrganError.decodeFailed(underlying: error) }

        let payload: JSONPayload
        do { payload = try JSONDecoder().decode(JSONPayload.self, from: data) }
        catch { throw OrganError.decodeFailed(underlying: error) }

        guard payload.m.count == 6 else {
            throw OrganError.decodeFailed(underlying: nil)
        }
        let mat = simd_float3x3(rows: [
            SIMD3(payload.m[0], payload.m[1], payload.m[2]),
            SIMD3(payload.m[1], payload.m[3], payload.m[4]),
            SIMD3(payload.m[2], payload.m[4], payload.m[5])
        ])
        self.descriptor = descriptor
        self.metric = LearnedPSDMetric(matrix: mat)
    }

    private struct JSONPayload: Codable {
        let m: [Float]
    }
}
