import CloudKit
import Foundation

// The CloudKit schema for the swap economy — the CLOUD version of AirDropHandler's local
// `.sixfour-genes` bundle. A gene is an Organ (`OrganDescriptor` + its content blob); publishing it
// = one `Gene` record in the PUBLIC database, adopting it = one append-only `Adoption` record.
//
// The record ⇄ model MAPPING is pure and unit-tested headlessly (CKRecord/CKAsset construct with no
// container). The LIVE operations (CKContainer.publicCloudDatabase save/fetch/query) and the
// CloudKit-Dashboard index flags are DEFERRED — they need the iCloud container entitlement, an
// account, and the `creator` ↔ Game Center player-id binding (still open). This file is the schema +
// mapping only, so the wiring can be verified the moment those land.
//
// Spec linkage: `Gene.parents` = the SixFour.Spec.Lineage DAG edges; `Gene.generation` =
// Lineage.generation; `creator` = SixFour.Spec.Trade.CreatorId; `Adoption` count = the demand /
// popularity scalar (folded, NOT a racy server counter — one record per (adopter, gene), deduped by
// recordName).

/// Field-key + record-type constants, and the pure `OrganDescriptor` ⇄ `CKRecord` mapping.
enum GeneCloudSchema {

    // ── Record types ──────────────────────────────────────────────────────────
    static let geneType = "Gene"
    static let adoptionType = "Adoption"

    // ── Gene record field keys ─────────────────────────────────────────────────
    // Dashboard index intent (documented here; set in the CloudKit console):
    //   slot        Queryable   — filter by organ type
    //   name        Searchable  — TOKENMATCHES text/tag search (discoverability)
    //   creator     Queryable   — "genes by @handle"
    //   parents     Queryable   — genealogy lookups
    //   generation  Sortable    — lineage-depth feeds
    //   createdAt   Sortable    — recency feeds
    //   adoptCount  Sortable    — popularity feeds  (denormalized; source of truth = Adoption records)
    enum GeneKey {
        static let slot = "slot"
        static let name = "name"
        static let creator = "creator"
        static let parents = "parents"
        static let generation = "generation"
        static let createdAt = "createdAt"
        static let adoptCount = "adoptCount"
        static let filename = "filename"  // local storage filename (as in the AirDrop manifest)
        static let blob = "blob"          // CKAsset — the organ content file
    }

    enum AdoptionKey {
        static let gene = "gene"          // adopted gene's content hash
        static let adopter = "adopter"    // adopter's creator id
    }

    /// Build the public-DB `Gene` record for an organ. The record NAME is the content hash, so
    /// identity is intrinsic and re-publishing the same gene is idempotent (first publisher wins).
    static func geneRecord(for d: OrganDescriptor, creator: CreatorID, blobURL: URL) -> CKRecord {
        let record = CKRecord(recordType: geneType,
                              recordID: CKRecord.ID(recordName: d.hash))
        record[GeneKey.slot] = d.slot.rawValue
        record[GeneKey.name] = d.name
        record[GeneKey.creator] = creator.rawValue
        record[GeneKey.parents] = d.parentHashes
        record[GeneKey.generation] = d.generation
        record[GeneKey.createdAt] = d.createdAt
        record[GeneKey.filename] = d.filename
        record[GeneKey.blob] = CKAsset(fileURL: blobURL)
        return record
    }

    /// Reconstruct the `OrganDescriptor` from a fetched `Gene` record. `hash` = the record name; the
    /// blob itself is downloaded separately via the `blob` CKAsset's `fileURL`.
    static func descriptor(from record: CKRecord) -> OrganDescriptor? {
        guard record.recordType == geneType,
              let slotRaw = record[GeneKey.slot] as? String,
              let slot = OrganSlot(rawValue: slotRaw),
              let name = record[GeneKey.name] as? String,
              let parents = record[GeneKey.parents] as? [String],
              let generation = intField(record, GeneKey.generation),
              let createdAt = record[GeneKey.createdAt] as? Date,
              let filename = record[GeneKey.filename] as? String
        else { return nil }
        return OrganDescriptor(slot: slot, name: name, hash: record.recordID.recordName,
                               generation: generation, parentHashes: parents,
                               createdAt: createdAt, filename: filename)
    }

    /// Build an append-only `Adoption` record. The record NAME encodes (adopter, gene) so a creator
    /// can adopt a given gene at most once — free dedup, no racy counter. Popularity = count of these.
    static func adoptionRecord(adopter: CreatorID, geneHash: String) -> CKRecord {
        let record = CKRecord(recordType: adoptionType,
                              recordID: CKRecord.ID(recordName: adoptionName(adopter: adopter, geneHash: geneHash)))
        record[AdoptionKey.gene] = geneHash
        record[AdoptionKey.adopter] = adopter.rawValue
        return record
    }

    /// The deterministic, dedup-enforcing record name for an adoption.
    static func adoptionName(adopter: CreatorID, geneHash: String) -> String {
        "adopt-\(adopter.rawValue)-\(geneHash)"
    }

    /// Read an integer field robustly across a locally-built record (`Int`) and a server-fetched one
    /// (CloudKit returns `Int64` / `NSNumber`).
    private static func intField(_ record: CKRecord, _ key: String) -> Int? {
        if let i = record[key] as? Int { return i }
        if let i = record[key] as? Int64 { return Int(i) }
        if let n = record[key] as? NSNumber { return n.intValue }
        return nil
    }
}
