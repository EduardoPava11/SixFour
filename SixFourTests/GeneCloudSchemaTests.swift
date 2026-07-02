import Testing
import CloudKit
import Foundation
@testable import SixFour

/// Verifies the CloudKit schema MAPPING headlessly (CKRecord/CKAsset construct with no container):
/// an `OrganDescriptor` round-trips losslessly through a `Gene` record, the content hash IS the
/// record identity (so re-publish is idempotent), and adoptions dedup by (adopter, gene). The live
/// publicCloudDatabase operations are deferred (need the container entitlement + an account) and are
/// intentionally NOT exercised here.
struct GeneCloudSchemaTests {

    private func sampleDescriptor() -> OrganDescriptor {
        OrganDescriptor(slot: .metric,
                        name: "warm dusk",
                        hash: "abc123def",
                        generation: 3,
                        parentHashes: ["p1", "p2"],
                        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                        filename: "abc123def.json")
    }

    @Test func organDescriptorRoundTrips() {
        let d = sampleDescriptor()
        let blobURL = FileManager.default.temporaryDirectory.appending(path: d.filename)
        let record = GeneCloudSchema.geneRecord(for: d, creator: CreatorID(rawValue: "player-42"), blobURL: blobURL)

        // The content hash is the record identity ⇒ intrinsic, dedup-able.
        #expect(record.recordID.recordName == d.hash)
        #expect(record[GeneCloudSchema.GeneKey.creator] as? String == "player-42")
        #expect(record[GeneCloudSchema.GeneKey.blob] is CKAsset)

        let back = GeneCloudSchema.descriptor(from: record)
        #expect(back == d)
    }

    @Test func genealogyEdgesSurvive() {
        let d = sampleDescriptor()
        let record = GeneCloudSchema.geneRecord(
            for: d, creator: CreatorID(rawValue: "player-42"),
            blobURL: FileManager.default.temporaryDirectory.appending(path: d.filename))
        #expect(record[GeneCloudSchema.GeneKey.parents] as? [String] == ["p1", "p2"])
        #expect(GeneCloudSchema.descriptor(from: record)?.generation == 3)
    }

    @Test func adoptionNameDedupsByPair() {
        // Same (adopter, gene) ⇒ identical record name ⇒ CloudKit rejects the duplicate.
        let a = GeneCloudSchema.adoptionRecord(adopter: CreatorID(rawValue: "player-42"), geneHash: "abc123def")
        let b = GeneCloudSchema.adoptionRecord(adopter: CreatorID(rawValue: "player-42"), geneHash: "abc123def")
        #expect(a.recordID.recordName == b.recordID.recordName)
        // Different adopter ⇒ different record (a distinct adoption, counted once).
        let c = GeneCloudSchema.adoptionRecord(adopter: CreatorID(rawValue: "player-99"), geneHash: "abc123def")
        #expect(a.recordID.recordName != c.recordID.recordName)
        #expect(a[GeneCloudSchema.AdoptionKey.gene] as? String == "abc123def")
    }
}
