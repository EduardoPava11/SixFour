import Foundation
import os

/// COLOR ATLAS — the on-device decision log (docs/COLOR-ATLAS.md §3.3).
///
/// Swift mirror (UI-track stub) of the PLANNED spec module
/// `SixFour.Spec.DecisionLog`. The wire contract of record is the SF64 TLV
/// container (binary, golden-pinned, Mac↔iPhone only); the app persists the SAME
/// `AtlasDecisionRecord` fields as Codable JSON today — replayable on day 1 and
/// losslessly transcodable to SF64 when the spec encoder lands (DEFERRED debt
/// `decision-log-binary-codec`: `Spec.DecisionLog` defines the binary CMPE chunk,
/// but no Zig/Swift SF64 codec exists — persistence is JSON-only today, which is
/// sufficient for n=0; binary is only needed for Mac↔iPhone transcode at step 3+).
/// Data never
/// leaves the device (no network; a plain file in Application Support).
struct AtlasDecisionLog: Codable, Equatable, Sendable {
    /// Format version (the JSON twin of the SF64 header's `version u32 = 1`).
    var version: Int = 1
    /// The append-only decision records, in play order (the replay fold's input).
    var entries: [AtlasDecisionRecord] = []

    /// Number of Compare entries — the Bradley-Terry `n` (the β = n/(n+50) ramp's input).
    var compareCount: Int { entries.count { $0.tag == 3 } }
}

/// Loads/saves the ONE decision log file. Pure file I/O, no caching — the log is
/// small (32 logical bytes per move) and the owner (`AtlasState`) holds the live copy.
enum AtlasDecisionLogStore {
    private static let logger = Logger(subsystem: "com.sixfour", category: "atlas.log")
    private static let fileName = "sixfour-atlas-decisions-v1.json"

    /// `Application Support/sixfour-atlas-decisions-v1.json` (directory created on demand).
    static func url() -> URL? {
        guard let dir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    /// Load the persisted log; a missing/corrupt file yields the empty log
    /// (curation always starts; it never blocks on a bad file).
    static func load() -> AtlasDecisionLog {
        guard let url = url(), let data = try? Data(contentsOf: url) else {
            return AtlasDecisionLog()
        }
        do {
            return try JSONDecoder().decode(AtlasDecisionLog.self, from: data)
        } catch {
            logger.error("atlas log decode failed (starting empty): \(String(describing: error))")
            return AtlasDecisionLog()
        }
    }

    /// Persist the log (best-effort; a write failure is logged, never fatal —
    /// the in-memory log still drives the session).
    static func save(_ log: AtlasDecisionLog) {
        guard let url = url() else { return }
        do {
            let data = try JSONEncoder().encode(log)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("atlas log save failed: \(String(describing: error))")
        }
    }
}
