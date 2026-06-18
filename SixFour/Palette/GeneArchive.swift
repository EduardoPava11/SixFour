import Foundation

/// On-device archive of learned genes — the "saved learnings" store
/// (`docs/SIXFOUR-AB-GAME-EXPORT-LEARNINGS-WORKFLOW.md` §4). Each exported look's 384-DOF genome
/// (Q16 coefficients) is kept so the NEXT session warm-starts near the user's taste instead of cold.
///
/// This is the honest FIRST version: a flat archive with nearest-by-distance retrieval. The full
/// Phase 7/8 object is a CVT-MAP-Elites cell store with `genomeInner` similarity on a SIMT substrate
/// (migration workflow §9) — same persistence + retrieval contract, richer index. Persisted as JSON
/// in Application Support (per-device, never cloud — like `PersonalTasteStore`). The genome wire
/// format for sharing is `GenomeCarrier` (S4GN-in-GIF).
struct Gene: Codable, Equatable {
    var coeffs: [Int]   // Int32 Q16 σ-pair coefficients
    var compares: Int   // Compare count of the producing genome (provenance)
}

enum GeneArchive {
    private static let fileName = "sixfour-gene-archive-v1.json"
    static let cap = 64   // keep the most recent N genes

    static func url() -> URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    static func load() -> [Gene] {
        guard let url = url(), let data = try? Data(contentsOf: url),
              let genes = try? JSONDecoder().decode([Gene].self, from: data) else { return [] }
        return genes
    }

    static func save(_ genes: [Gene]) {
        guard let url = url(), let data = try? JSONEncoder().encode(genes) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Append a gene, evicting the oldest beyond `cap`.
    static func add(_ gene: Gene) {
        var genes = load()
        genes.append(gene)
        if genes.count > cap { genes.removeFirst(genes.count - cap) }
        save(genes)
    }

    /// Squared L2 distance between two coefficient vectors (zero-padded to the longer).
    static func distanceSq(_ a: [Int], _ b: [Int]) -> Int {
        let n = max(a.count, b.count)
        var s = 0
        for i in 0..<n {
            let d = (i < a.count ? a[i] : 0) - (i < b.count ? b[i] : 0)
            s += d * d
        }
        return s
    }

    /// The archived gene nearest to `query` (pure; testable without disk).
    static func nearest(to query: [Int], in genes: [Gene]) -> Gene? {
        genes.min { distanceSq($0.coeffs, query) < distanceSq($1.coeffs, query) }
    }

    /// Warm-start: the saved gene nearest the current working point, or nil for a cold start.
    static func seed(near query: [Int]) -> Gene? { nearest(to: query, in: load()) }
}
