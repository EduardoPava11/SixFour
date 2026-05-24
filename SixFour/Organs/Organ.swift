import Foundation
import CoreML

/// Pipeline insertion points. Only `.metric` ships today: the
/// `trainer/train_metric.py` MLX trainer produces 6-float PSD organs
/// that `MetricOrgan.swift` loads. Other slots (post-process, dither,
/// ranker) were removed pending real trainers — they were CoreML
/// loaders for files no trainer in this repo emits, which the project's
/// no-stubs rule forbids. Re-add a case here only when its trainer + tests
/// ship in the same change set.
enum OrganSlot: String, Codable, Sendable, CaseIterable {
    case metric
}

/// Metadata about a single organ file.
struct OrganDescriptor: Sendable, Codable, Hashable {
    let slot: OrganSlot
    let name: String              // human-readable
    let hash: String              // content hash of the JSON
    let generation: Int           // generations from initial seed
    let parentHashes: [String]    // 0, 1, or 2 parents
    let createdAt: Date
    /// On-disk path is resolved by GeneStore.
    let filename: String
}

/// Abstract handle to a loaded organ.
protocol Organ: Sendable {
    var descriptor: OrganDescriptor { get }
}

/// Errors during organ load / inference.
enum OrganError: Error {
    case fileMissing(URL)
    case decodeFailed(underlying: Error?)
    case wrongSlot(expected: OrganSlot, got: OrganSlot)
    case mlModelLoadFailed(underlying: Error)
}
