import Testing
@testable import SixFour

/// Byte-exact golden gates for the two hand-written gene-carrier codecs
/// (`GenomeCarrier` = S4GN, `SwapCarrier` = S4GX) against the spec-generated
/// `GenomeCarrierGolden` / `SwapCarrierGolden` — the Swift half of the
/// cross-language pin (`cabal test` proves the Haskell half).
struct SwapCarrierTests {

    // MARK: S4GN (look genome)

    private var genomeGolden: GenomeCarrier.Payload {
        let h = GenomeCarrierGolden.header
        return GenomeCarrier.Payload(
            header: GenomeCarrier.Header(
                major: UInt8(h[0]), minor: UInt8(h[1]), flags: UInt16(h[2]),
                dof: UInt16(h[3]), radix: UInt8(h[4]),
                deviceIdHash: UInt32(h[5]), btCompares: UInt32(h[6])),
            coeffs: GenomeCarrierGolden.coeffs)
    }

    @Test func genomeEncodeMatchesGoldenBytes() {
        #expect(GenomeCarrier.encode(genomeGolden) == GenomeCarrierGolden.encoded)
    }

    @Test func genomeExtractRoundTrips() throws {
        let p = try GenomeCarrier.extract(GenomeCarrierGolden.encoded).get()
        #expect(p == genomeGolden)
    }

    @Test func genomeAbsentIsNoBlockNotCorrupt() {
        // A plain GIF header + trailer: no S4GN marker anywhere.
        let plain: [UInt8] = Array("GIF89a".utf8) + [0, 1, 0, 1, 0x70, 0, 0, 0x3B]
        #expect(GenomeCarrier.extract(plain) == .failure(.noBlock))
    }

    // MARK: S4GX (swap carrier)

    private var grantGolden: SwapCarrier.Payload {
        SwapCarrier.Payload(
            profile: .grant,
            geneName: SwapCarrierGolden.geneName,
            tag: SwapCarrier.Tag(
                gene: SwapCarrierGolden.tag[0],
                creator: SwapCarrierGolden.tag[1],
                parents: SwapCarrierGolden.parents,
                minted: SwapCarrierGolden.tag[2]),
            weights: SwapCarrierGolden.weights)
    }

    @Test func swapEncodeMatchesGoldenBytes() {
        #expect(SwapCarrier.encode(grantGolden) == SwapCarrierGolden.encodedGrant)
        var showcase = grantGolden
        showcase.profile = .showcase
        #expect(SwapCarrier.encode(showcase) == SwapCarrierGolden.encodedShowcase)
    }

    @Test func swapGrantExtractRoundTrips() throws {
        let p = try SwapCarrier.extract(SwapCarrierGolden.encodedGrant).get()
        #expect(p == grantGolden)
        #expect(p.weights.count == 21)   // the theta-up registry size
    }

    /// The hybrid model's wire fact: a showcase carries ZERO weight words —
    /// the extracted public file is inert (expresses as the deterministic floor).
    @Test func swapShowcaseIsInertOnTheWire() throws {
        let p = try SwapCarrier.extract(SwapCarrierGolden.encodedShowcase).get()
        #expect(p.weights.isEmpty)
        #expect(p.profile == .showcase)
        #expect(p.geneName == grantGolden.geneName)
        #expect(p.tag == grantGolden.tag)   // lineage still rides along
    }

    @Test func swapNegativeVectorsRefuse() {
        #expect(SwapCarrier.extract(SwapCarrierGolden.corruptEncoded) == .failure(.corrupt))
        #expect(SwapCarrier.extract(SwapCarrierGolden.versionMismatchEncoded) == .failure(.versionMismatch))
    }

    /// Both blocks share one GIF stream; each extractor finds ONLY its own
    /// (mirrors the spec's `lawBlocksCoexist`).
    @Test func blocksCoexistInOneStream() throws {
        let both = GenomeCarrierGolden.encoded + SwapCarrierGolden.encodedGrant
        #expect(try GenomeCarrier.extract(both).get() == genomeGolden)
        #expect(try SwapCarrier.extract(both).get() == grantGolden)
        #expect(SwapCarrier.extract(GenomeCarrierGolden.encoded) == .failure(.noBlock))
        #expect(GenomeCarrier.extract(SwapCarrierGolden.encodedGrant) == .failure(.noBlock))
    }
}
