import Foundation

/// Swift port of `SixFour.Spec.GenomeCarrier` — the S4GN genome-in-GIF codec: the chosen 384-DOF
/// σ-pair genome serialized as **Int32 LE Q16** inside a standards-compliant GIF89a
/// Application-Extension (`0x21 0xFF`), CRC32-protected, so every exported GIF is self-describing
/// and shareable (a receiver pulls it out and blends it). Mirrors the spec byte-for-byte; gated by
/// `GenomeCarrierTests` against `Codegen.GenomeCarrier` (the 6 carrier laws are CI-proven in
/// `Properties.GenomeCarrier`).
enum GenomeCarrier {

    struct Header: Equatable {
        var major: UInt8; var minor: UInt8; var flags: UInt16
        var dof: UInt16; var radix: UInt8; var deviceIdHash: UInt32; var btCompares: UInt32
    }
    struct Payload: Equatable { var header: Header; var coeffs: [Int] }   // Int32 Q16 coefficients
    enum CarrierError: Error, Equatable { case noBlock, corrupt, versionMismatch }

    static let appExtIntroducer: [UInt8] = [0x21, 0xFF]
    static let blockIdentifier: [UInt8] = Array("SIXFOUR1G10".utf8)
    private static let magic: [UInt8] = [0x53, 0x34, 0x47, 0x4E]   // "S4GN"
    private static let headerLen = 24
    private static let currentMajor: UInt8 = 1

    // MARK: - CRC32 (ISO-HDLC, polynomial 0xEDB88320, table-free)

    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for b in bytes {
            crc ^= UInt32(b)
            for _ in 0..<8 { crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1 }
        }
        return ~crc
    }

    // MARK: - LE byte helpers

    private static func u16LE(_ w: UInt16) -> [UInt8] { [UInt8(w & 0xFF), UInt8((w >> 8) & 0xFF)] }
    private static func u32LE(_ w: UInt32) -> [UInt8] { (0..<4).map { UInt8((w >> (8 * UInt32($0))) & 0xFF) } }
    private static func i32LE(_ n: Int) -> [UInt8] { u32LE(UInt32(bitPattern: Int32(truncatingIfNeeded: n))) }

    private static func ix(_ b: [UInt8], _ i: Int) -> UInt8 { (i >= 0 && i < b.count) ? b[i] : 0 }
    private static func readU16LE(_ b: [UInt8], _ o: Int) -> UInt16 {
        UInt16(ix(b, o)) | (UInt16(ix(b, o + 1)) << 8)
    }
    private static func readU32LE(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(ix(b, o)) | (UInt32(ix(b, o + 1)) << 8) | (UInt32(ix(b, o + 2)) << 16) | (UInt32(ix(b, o + 3)) << 24)
    }
    private static func readI32LE(_ b: [UInt8], _ o: Int) -> Int { Int(Int32(bitPattern: readU32LE(b, o))) }

    // MARK: - Encode

    private static func encodeHeader(_ h: Header) -> [UInt8] {
        magic + [h.major, h.minor] + u16LE(h.flags) + u16LE(h.dof) + [h.radix, 0]
            + u32LE(h.deviceIdHash) + u32LE(h.btCompares) + [0, 0, 0, 0]
    }

    private static func encodeBody(_ p: Payload) -> [UInt8] {
        let pre = encodeHeader(p.header) + p.coeffs.flatMap(i32LE)
        return pre + u32LE(crc32(pre))
    }

    private static func subBlockify(_ xs: [UInt8]) -> [UInt8] {
        var out = [UInt8](); var i = 0
        while i < xs.count {
            let chunk = Array(xs[i..<min(i + 255, xs.count)])
            out.append(UInt8(chunk.count)); out += chunk; i += 255
        }
        return out
    }

    /// Serialize a payload into the full GIF89a Application-Extension byte stream.
    static func encode(_ p: Payload) -> [UInt8] {
        appExtIntroducer + [0x0B] + blockIdentifier + subBlockify(encodeBody(p)) + [0x00]
    }

    // MARK: - Extract (total; NoBlock ≠ Corrupt ≠ VersionMismatch)

    private static func gatherSubBlocks(_ xs: [UInt8]) -> [UInt8] {
        var out = [UInt8](); var i = 0
        while i < xs.count {
            let len = Int(xs[i]); if len == 0 { break }
            i += 1
            out += xs[i..<min(i + len, xs.count)]
            i += len
        }
        return out
    }

    private static func firstIndex(ofMarker m: [UInt8], in s: [UInt8]) -> Int? {
        guard m.count <= s.count else { return nil }
        for start in 0...(s.count - m.count) where Array(s[start..<start + m.count]) == m { return start }
        return nil
    }

    /// Probe a GIF byte stream for the S4GN block (never decodes LZW frames).
    static func extract(_ stream: [UInt8]) -> Result<Payload, CarrierError> {
        let marker = appExtIntroducer + [0x0B] + blockIdentifier
        guard let start = firstIndex(ofMarker: marker, in: stream) else { return .failure(.noBlock) }
        let body = gatherSubBlocks(Array(stream[(start + marker.count)...]))
        let n = body.count
        if n < headerLen + 4 { return .failure(.corrupt) }
        if Array(body[0..<4]) != magic { return .failure(.corrupt) }
        let preLen = n - 4
        if readU32LE(body, preLen) != crc32(Array(body[0..<preLen])) { return .failure(.corrupt) }
        if ix(body, 4) != currentMajor { return .failure(.versionMismatch) }
        let header = Header(
            major: ix(body, 4), minor: ix(body, 5),
            flags: readU16LE(body, 6), dof: readU16LE(body, 8), radix: ix(body, 10),
            deviceIdHash: readU32LE(body, 12), btCompares: readU32LE(body, 16))
        let coeffBs = Array(body[headerLen..<preLen])
        let coeffs = stride(from: 0, to: coeffBs.count, by: 4).map { readI32LE(coeffBs, $0) }
        return .success(Payload(header: header, coeffs: coeffs))
    }
}
