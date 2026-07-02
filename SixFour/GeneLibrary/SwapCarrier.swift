import Foundation

/// Hand-written Swift port of `SixFour.Spec.SwapCarrier` — the S4GX gene-in-GIF codec:
/// ONE tradeable gene (registry name + lineage tag + Q16 weight words) in a second
/// GIF89a Application-Extension block (`"SIXFOUR1" + "X10"`, coexisting with S4GN).
/// Byte-exact against the generated `SwapCarrierGolden` (gated in `SwapCarrierTests`).
/// Foundation only.
///
/// The hybrid swap model is a WIRE fact here exactly as in the spec: `encode`
/// serializes ZERO weight words for a `.showcase` (the public file is viewable but
/// inert — it expresses as the deterministic floor), and a working `.grant` file is
/// minted only via the ledger gate (`SixFour.Spec.SwapCarrier.mintGrant`; the Swift
/// ledger port is the L2.8 step). Extraction is TOTAL with the spec's outcome order:
/// no marker → `.noBlock`; bad CRC/magic/structure → `.corrupt`; future MAJOR →
/// `.versionMismatch`; never a partial parse.
enum SwapCarrier {
    /// The two file profiles of the locked hybrid swap model.
    enum Profile: UInt8, Equatable {
        case showcase = 0
        case grant = 1
    }

    /// The lineage tag riding with the gene (mirrors `SixFour.Spec.Lineage.GeneTag`;
    /// gene/creator/parents are the full 64-bit GeneHash content-addresses (i64 on the wire).
    struct Tag: Equatable {
        var gene: Int
        var creator: Int
        var parents: [Int]
        var minted: Int
    }

    /// One carried gene. `weights` is empty on the wire for a `.showcase`.
    struct Payload: Equatable {
        var profile: Profile
        var geneName: String
        var tag: Tag
        var weights: [Int]
    }

    /// The EXACTLY-11-byte block identifier `"SIXFOUR1" + "X10"` (X = eXchange).
    static let identifier: [UInt8] = Array("SIXFOUR1X10".utf8)
    /// The body magic `"S4GX"`.
    static let magic: [UInt8] = Array("S4GX".utf8)
    /// Current wire versions.
    static let currentMajor: UInt8 = 2   // v2 (R2): gene/creator/parents are i64 (the 64-bit GeneHash id)
    static let currentMinor: UInt8 = 0

    private static var marker: [UInt8] { CarrierWire.appExtIntroducer + [0x0B] + identifier }

    /// The canonical wire form (mirrors the spec's `normalizePayload`): name ≤255
    /// latin-1 bytes, ids at Int64 width, weights/minted at Int32, ≤255 parents, ≤65535 weight words —
    /// and the load-bearing clause: a `.showcase` has NO weights.
    static func normalize(_ p: Payload) -> Payload {
        var q = p
        q.geneName = String(String.UnicodeScalarView(
            p.geneName.unicodeScalars.prefix(255).map { Unicode.Scalar(UInt8($0.value % 256)) }))
        q.tag.gene = p.tag.gene            // full 64-bit content-address (no truncation)
        q.tag.creator = p.tag.creator
        q.tag.minted = wrap32(p.tag.minted)   // epoch stays i32
        q.tag.parents = Array(p.tag.parents.prefix(255))
        q.weights = p.profile == .showcase ? [] : p.weights.prefix(65535).map(wrap32)
        return q
    }

    /// Serialize at the CURRENT version (normalizes first — the wire is canonical).
    static func encode(_ p: Payload) -> [UInt8] {
        encodeVersioned(major: currentMajor, minor: currentMinor, p)
    }

    /// Serialize at an explicit version (exists for the golden's negative vector;
    /// production uses `encode`).
    static func encodeVersioned(major: UInt8, minor: UInt8, _ payload: Payload) -> [UInt8] {
        let p = normalize(payload)
        let name = Array(p.geneName.unicodeScalars.map { UInt8($0.value % 256) })
        var body = magic
        body += [major, minor, p.profile.rawValue]
        body += [UInt8(name.count)] + name
        body += CarrierWire.i64LE(p.tag.gene)
        body += CarrierWire.i64LE(p.tag.creator)
        body += CarrierWire.i32LE(p.tag.minted)
        body += [UInt8(p.tag.parents.count)]
        for g in p.tag.parents { body += CarrierWire.i64LE(g) }
        body += CarrierWire.u16LE(UInt16(p.weights.count))
        for w in p.weights { body += CarrierWire.i32LE(w) }
        return CarrierWire.wrapBody(body, identifier: identifier)
    }

    /// Probe a GIF byte stream for the S4GX block (never decodes LZW frames).
    static func extract(_ stream: [UInt8]) -> Result<Payload, CarrierError> {
        guard let at = CarrierWire.findMarker(stream, marker) else { return .failure(.noBlock) }
        let whole = CarrierWire.gatherSubBlocks(stream, from: at + marker.count)
        guard whole.count >= 4 else { return .failure(.corrupt) }
        let preLen = whole.count - 4
        let body = Array(whole[0..<preLen])
        let crcGot = CarrierWire.readU32LE(whole, at: preLen)
        guard crcGot == CarrierWire.crc32(body) else { return .failure(.corrupt) }
        guard let (major, payload) = parseBody(body) else { return .failure(.corrupt) }
        guard major == currentMajor else { return .failure(.versionMismatch) }
        return .success(payload)
    }

    /// Parse a CRC-verified body; nil on any structural violation (requires exact
    /// consumption, so the wire form stays canonical).
    private static func parseBody(_ body: [UInt8]) -> (UInt8, Payload)? {
        var i = 0
        func take(_ n: Int) -> [UInt8]? {
            guard i + n <= body.count else { return nil }
            defer { i += n }
            return Array(body[i ..< i + n])
        }
        guard take(4) == magic else { return nil }
        guard let hdr = take(3) else { return nil }
        guard let profile = Profile(rawValue: hdr[2]) else { return nil }
        guard let nl = take(1), let nameB = take(Int(nl[0])) else { return nil }
        guard let ids = take(20) else { return nil }   // gene(8) + creator(8) + minted(4)
        guard let pc = take(1), let parB = take(8 * Int(pc[0])) else { return nil }
        guard let wc = take(2) else { return nil }
        let weightCount = Int(CarrierWire.readU16LE(wc, at: 0))
        guard let wB = take(4 * weightCount), i == body.count else { return nil }

        let tag = Tag(
            gene: CarrierWire.readI64LE(ids, at: 0),
            creator: CarrierWire.readI64LE(ids, at: 8),
            parents: stride(from: 0, to: parB.count, by: 8).map { CarrierWire.readI64LE(parB, at: $0) },
            minted: CarrierWire.readI32LE(ids, at: 16))
        let name = String(String.UnicodeScalarView(nameB.map { Unicode.Scalar($0) }))
        let weights = stride(from: 0, to: wB.count, by: 4).map { CarrierWire.readI32LE(wB, at: $0) }
        return (hdr[0], Payload(profile: profile, geneName: name, tag: tag, weights: weights))
    }

    private static func wrap32(_ v: Int) -> Int { Int(Int32(truncatingIfNeeded: v)) }
}
