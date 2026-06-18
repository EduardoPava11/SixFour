import Testing
import Foundation
@testable import SixFour

/// Gate for DECN v2 = embeddings (canonical-path step 2b storage). The device
/// persists Codable JSON (`AtlasDecisionRecord`); the SF64 binary twin is the
/// additive `CMPE` chunk in `Spec.DecisionLog` (golden-gated there). These pin the
/// device side: a v1 log (no embedding keys) decodes with `nil` embeddings
/// (backward compatible, no version bump), and a record carrying the 770-D
/// winner/loser embeddings round-trips intact.
struct DecisionLogV2Tests {

    /// A v1 JSON log (written before embeddings existed) decodes cleanly with
    /// `nil` embeddings — old logs keep replaying.
    @Test func v1JsonDecodesWithoutEmbeddings() throws {
        let v1 = Data("""
        {"version":1,"entries":[{"tag":3,"x":0,"y":0,"z":0,"wDelta":0,"flags":0,\
        "anchorL":0,"anchorA":0,"anchorB":0,"winHash":7,"loseHash":9,"pad":0}]}
        """.utf8)
        let log = try JSONDecoder().decode(AtlasDecisionLog.self, from: v1)
        #expect(log.entries.count == 1)
        #expect(log.entries[0].winEmbedding == nil)
        #expect(log.entries[0].loseEmbedding == nil)
        #expect(log.entries[0].move != nil) // still a valid Compare
        #expect(log.compareCount == 1)
    }

    /// A record carrying 770-D embeddings JSON-round-trips byte-for-byte.
    @Test func embeddingsRoundTrip() throws {
        var rec = AtlasDecisionRecord(.compare(winner: 7, loser: 9))
        rec.winEmbedding = (0 ..< 770).map { Float($0) * 0.001 }
        rec.loseEmbedding = (0 ..< 770).map { Float($0) * -0.002 }
        let log = AtlasDecisionLog(version: 1, entries: [rec])

        let data = try JSONEncoder().encode(log)
        let back = try JSONDecoder().decode(AtlasDecisionLog.self, from: data)

        #expect(back == log)
        #expect(back.entries[0].winEmbedding?.count == 770)
        #expect(back.entries[0].loseEmbedding?[769] == Float(769) * -0.002)
    }
}
