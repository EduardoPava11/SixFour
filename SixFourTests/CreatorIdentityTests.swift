import Testing
import Foundation
@testable import SixFour

/// Verifies the pure `CreatorID` identity binding headlessly. `GameCenterIdentity.authenticate` itself
/// is device-only (presents sign-in UI, needs an account) and is intentionally not exercised here;
/// what IS tested is the typed token — its Codable round-trip and that it keys the economy records.
struct CreatorIdentityTests {

    @Test func creatorIDCodableRoundTrips() throws {
        let c = CreatorID(rawValue: "G:1234567890")
        let data = try JSONEncoder().encode(c)
        let back = try JSONDecoder().decode(CreatorID.self, from: data)
        #expect(back == c)
    }

    @Test func creatorKeysGeneRecord() {
        let d = OrganDescriptor(slot: .metric, name: "n", hash: "h1",
                                generation: 0, parentHashes: [],
                                createdAt: Date(timeIntervalSince1970: 0), filename: "h1.json")
        let creator = CreatorID(rawValue: "G:abc")
        let record = GeneCloudSchema.geneRecord(
            for: d, creator: creator,
            blobURL: FileManager.default.temporaryDirectory.appending(path: d.filename))
        #expect(record[GeneCloudSchema.GeneKey.creator] as? String == creator.rawValue)
    }

    @Test func adoptionKeyedByCreator() {
        let creator = CreatorID(rawValue: "G:xyz")
        let name = GeneCloudSchema.adoptionName(adopter: creator, geneHash: "h1")
        #expect(name == "adopt-G:xyz-h1")
    }
}
