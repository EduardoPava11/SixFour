import Testing
import CloudKit
import Foundation
@testable import SixFour

/// In-memory `GeneDatabase` for headless loop tests. A lock-guarded class (not an actor) so the
/// non-Sendable `CKRecord` never crosses an isolation boundary. `save` upserts by record id — the same
/// dedup substrate the real public database gives, so publish idempotence and adoption dedup are exact.
final class FakeGeneDatabase: GeneDatabase, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [String: CKRecord] = [:]

    @discardableResult func save(_ record: CKRecord) async throws -> CKRecord {
        lock.withLock { records[record.recordID.recordName] = record }
        return record
    }

    func record(with id: CKRecord.ID) async throws -> CKRecord? {
        lock.withLock { records[id.recordName] }
    }

    func records(ofType recordType: String, sortedBy key: String?, ascending: Bool) async throws -> [CKRecord] {
        lock.withLock {
            let ofType = records.values.filter { $0.recordType == recordType }
            guard let key else { return Array(ofType) }
            return ofType.sorted { a, b in
                if let ad = a[key] as? Date, let bd = b[key] as? Date { return ascending ? ad < bd : ad > bd }
                let ai = (a[key] as? Int) ?? (a[key] as? Int64).map(Int.init) ?? 0
                let bi = (b[key] as? Int) ?? (b[key] as? Int64).map(Int.init) ?? 0
                return ascending ? ai < bi : ai > bi
            }
        }
    }
}

/// Verifies the publish / browse / adopt loop headlessly against the fake DB + a real `GeneStore` +
/// real temp blob files. Only the CloudKit adapter is device-only; all loop LOGIC is proven here.
struct GeneExchangeTests {

    private func descriptor(hash: String, name: String, createdAt: TimeInterval) -> OrganDescriptor {
        OrganDescriptor(slot: .metric, name: name, hash: hash, generation: 0, parentHashes: [],
                        createdAt: Date(timeIntervalSince1970: createdAt), filename: "\(hash).json")
    }

    private func tempBlob(_ tag: String, _ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(tag)-\(UUID().uuidString).json")
        try Data(contents.utf8).write(to: url)
        return url
    }

    @Test func publishThenBrowseIsMostRecentFirst() async throws {
        let exchange = GeneExchange(db: FakeGeneDatabase(), store: try GeneStore())
        let creator = CreatorID(rawValue: "G:pub")

        try await exchange.publish(descriptor(hash: "hOld", name: "old", createdAt: 1000),
                                   blobURL: tempBlob("hOld", "{}"), creator: creator)
        try await exchange.publish(descriptor(hash: "hNew", name: "new", createdAt: 2000),
                                   blobURL: tempBlob("hNew", "{}"), creator: creator)

        let feed = try await exchange.browse()   // default: most-recent-first
        #expect(feed.map(\.hash) == ["hNew", "hOld"])
        #expect(feed.first?.creator == creator)
        #expect(feed.first?.name == "new")
    }

    @Test func adoptDownloadsBlobAndCountsEachAdopterOnce() async throws {
        let store = try GeneStore()
        let exchange = GeneExchange(db: FakeGeneDatabase(), store: store)
        let hash = "hGene-\(UUID().uuidString)"

        try await exchange.publish(descriptor(hash: hash, name: "warm", createdAt: 1000),
                                   blobURL: tempBlob("gene", "{\"w\":1}"),
                                   creator: CreatorID(rawValue: "G:pub"))

        try await exchange.adopt(geneHash: hash, by: CreatorID(rawValue: "G:adopt"))
        let stored = await store.descriptors[.metric] ?? []
        #expect(stored.contains { $0.hash == hash })          // blob landed in the local store
        #expect(try await exchange.popularity(of: hash) == 1)

        // Re-adopt by the same creator ⇒ idempotent (dedup by (adopter, gene) record id).
        try await exchange.adopt(geneHash: hash, by: CreatorID(rawValue: "G:adopt"))
        #expect(try await exchange.popularity(of: hash) == 1)

        // A distinct adopter raises popularity.
        try await exchange.adopt(geneHash: hash, by: CreatorID(rawValue: "G:other"))
        #expect(try await exchange.popularity(of: hash) == 2)
    }

    @Test func adoptMissingGeneThrows() async throws {
        let exchange = GeneExchange(db: FakeGeneDatabase(), store: try GeneStore())
        var threw = false
        do { try await exchange.adopt(geneHash: "absent", by: CreatorID(rawValue: "G:x")) }
        catch { threw = true }
        #expect(threw)
    }
}
