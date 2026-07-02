import CloudKit
import Foundation

// The live publish / browse / adopt loop for the swap economy — the cloud counterpart of
// AirDropHandler. The database is behind the `GeneDatabase` seam so the loop LOGIC (idempotent
// publish, adopt-into-GeneStore, dedup, popularity) is verified headlessly against an in-memory fake;
// only `CloudKitGeneDatabase` (the thin CKDatabase adapter) is device-only and needs the CloudKit
// entitlement + an iCloud account. Identity is a `CreatorID` (Game Center); mapping is `GeneCloudSchema`.

/// A summary of a published gene for the browse feed — everything the UI needs WITHOUT downloading the
/// blob. Reconstructed from a `Gene` record.
struct GeneSummary: Sendable, Equatable {
    let hash: String
    let name: String
    let slot: OrganSlot
    let generation: Int
    let creator: CreatorID
    let createdAt: Date

    init?(record: CKRecord) {
        guard let d = GeneCloudSchema.descriptor(from: record),
              let creatorRaw = record[GeneCloudSchema.GeneKey.creator] as? String
        else { return nil }
        self.hash = d.hash
        self.name = d.name
        self.slot = d.slot
        self.generation = d.generation
        self.creator = CreatorID(rawValue: creatorRaw)
        self.createdAt = d.createdAt
    }
}

/// The database seam. `CloudKitGeneDatabase` is production; tests inject an in-memory fake. Keeping the
/// loop above this line means its logic is testable without CloudKit servers.
protocol GeneDatabase: Sendable {
    /// Upsert a record (idempotent by record id — the swap economy's dedup substrate).
    @discardableResult func save(_ record: CKRecord) async throws -> CKRecord
    /// Fetch one record by id, or nil if absent.
    func record(with id: CKRecord.ID) async throws -> CKRecord?
    /// All records of a type, optionally sorted by a (Sortable) field.
    func records(ofType recordType: String, sortedBy key: String?, ascending: Bool) async throws -> [CKRecord]
}

/// Errors surfaced by the exchange.
enum GeneExchangeError: Error {
    case geneNotFound(String)
    case malformedRecord(String)
    case blobUnavailable(String)
}

/// The publish / browse / adopt loop. Pure over its injected `GeneDatabase` + `GeneStore`.
struct GeneExchange: Sendable {
    let db: GeneDatabase
    let store: GeneStore

    init(db: GeneDatabase, store: GeneStore) {
        self.db = db
        self.store = store
    }

    /// Publish one of your organs to the public database. Idempotent: the record id is the content
    /// hash, so re-publishing the same gene is a no-op upsert (first publisher owns the provenance).
    func publish(_ descriptor: OrganDescriptor, blobURL: URL, creator: CreatorID) async throws {
        let record = GeneCloudSchema.geneRecord(for: descriptor, creator: creator, blobURL: blobURL)
        try await db.save(record)
    }

    /// The browse feed: published genes, sorted by a feed key (default: most-recent-first).
    func browse(sortedBy key: String = GeneCloudSchema.GeneKey.createdAt,
                ascending: Bool = false) async throws -> [GeneSummary] {
        let records = try await db.records(ofType: GeneCloudSchema.geneType, sortedBy: key, ascending: ascending)
        return records.compactMap(GeneSummary.init(record:))
    }

    /// Adopt a gene: download its blob into the local `GeneStore`, then append an `Adoption` record.
    /// The adoption's record id encodes (adopter, gene), so a second adoption by the same creator is a
    /// no-op upsert — popularity counts each adopter once.
    func adopt(geneHash: String, by adopter: CreatorID) async throws {
        guard let record = try await db.record(with: CKRecord.ID(recordName: geneHash)) else {
            throw GeneExchangeError.geneNotFound(geneHash)
        }
        guard let descriptor = GeneCloudSchema.descriptor(from: record) else {
            throw GeneExchangeError.malformedRecord(geneHash)
        }
        guard let asset = record[GeneCloudSchema.GeneKey.blob] as? CKAsset,
              let assetURL = asset.fileURL else {
            throw GeneExchangeError.blobUnavailable(geneHash)
        }
        let content = try Data(contentsOf: assetURL)
        try await store.addOrgan(descriptor: descriptor, content: content)
        try await db.save(GeneCloudSchema.adoptionRecord(adopter: adopter, geneHash: geneHash))
    }

    /// Popularity = the number of distinct adopters of a gene (the demand scalar; folded from the
    /// append-only, dedup-by-id `Adoption` records — never a racy server counter).
    func popularity(of geneHash: String) async throws -> Int {
        let adoptions = try await db.records(ofType: GeneCloudSchema.adoptionType, sortedBy: nil, ascending: false)
        return adoptions.filter { ($0[GeneCloudSchema.AdoptionKey.gene] as? String) == geneHash }.count
    }
}

// MARK: - Production adapter (device-only)

/// The production `GeneDatabase`: the app's public CloudKit database. DEVICE-ONLY — needs the CloudKit
/// entitlement + a signed-in iCloud account, so it is not exercised by the headless loop tests (those
/// inject an in-memory fake). The sort keys map to the Sortable fields documented in `GeneCloudSchema`.
struct CloudKitGeneDatabase: GeneDatabase {
    let database: CKDatabase

    /// The app's public database in the default container.
    init(container: CKContainer = .default()) {
        self.database = container.publicCloudDatabase
    }

    @discardableResult func save(_ record: CKRecord) async throws -> CKRecord {
        try await database.save(record)
    }

    func record(with id: CKRecord.ID) async throws -> CKRecord? {
        do {
            return try await database.record(for: id)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func records(ofType recordType: String, sortedBy key: String?, ascending: Bool) async throws -> [CKRecord] {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        if let key {
            query.sortDescriptors = [NSSortDescriptor(key: key, ascending: ascending)]
        }
        let (results, _) = try await database.records(matching: query)
        return results.compactMap { try? $0.1.get() }
    }
}
