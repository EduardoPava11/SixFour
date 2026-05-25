import Foundation

/// A "signature look" — currently just an optional metric organ plus a
/// palette-mode choice. Earlier revisions held postProc / dither / ranker
/// slots; those were removed when their organs got deleted (no trainers,
/// no tests = stubs by the project rule). Stored as a small JSON file
/// inside a `.sixfour-genes` bundle.
struct Composition: Codable, Sendable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let metric: String?     // descriptor hash of the metric organ, or nil
    let createdAt: Date
    /// Which per-frame palette-extraction algorithm the user picked.
    /// This is now the single creative palette control — every capture
    /// produces a complete per-frame 64×64×64 voxel volume; the former
    /// `.shared` / `.global` cross-frame Sinkhorn modes were removed.
    /// Default `.kMeans` matches the original behavior.
    let extractorChoice: ExtractorChoice

    /// User-facing palette-extraction algorithm choice. Each case
    /// maps to one `PaletteExtractor` implementation; the mapping
    /// is centralized in `makeExtractor(engines:)` so the UI only
    /// needs to know the enum value.
    enum ExtractorChoice: String, Codable, Sendable, Hashable, CaseIterable {
        /// Iterative refinement — GPU Lloyd k-means (today's default,
        /// fastest, good for high-variance content).
        case kMeans
        /// Recursive bipartition — Wu 1992 variance-based splits.
        /// Naturally produces per-cluster covariance; highest-fidelity
        /// statistics for downstream editing tools.
        case wu
        /// Hierarchical merging — octree with reduce-to-K. Most
        /// predictable structure; best for flat-colored content.
        case octree

        /// Short human label for the UI picker.
        var label: String {
            switch self {
            case .kMeans: return "K-means"
            case .wu:     return "Wu"
            case .octree: return "Octree"
            }
        }
    }

    /// Instantiate the right `PaletteExtractor` for this composition's
    /// choice. Called by `GIFRenderer.render` at the start of each
    /// burst. Returns an `any PaletteExtractor` (existential) since
    /// the choice is data-driven and there's no compile-time
    /// information to specialize on.
    func makeExtractor(engines: PaletteEngines) -> any PaletteExtractor {
        switch extractorChoice {
        case .kMeans: return KMeansExtractor(pipeline: engines.kMeans)
        case .wu:     return WuExtractor(pipeline: engines.wu)
        case .octree: return OctreeExtractor(pipeline: engines.octree)
        }
    }

    static let baselineName = "Baseline"
    var isBaseline: Bool { name == Composition.baselineName }

    init(
        name: String,
        metric: String?,
        createdAt: Date,
        extractorChoice: ExtractorChoice = .kMeans
    ) {
        self.name = name
        self.metric = metric
        self.createdAt = createdAt
        self.extractorChoice = extractorChoice
    }

    /// Returns a copy with the given fields overridden; any field left `nil`
    /// is carried over unchanged. Replaces the full 5-argument
    /// re-construction that previously appeared at every mutation site — so
    /// adding a new stored field touches only this method and the
    /// initializer, not each caller. `metric`/`createdAt` are always carried
    /// over (callers never partially override them; the compose screen builds
    /// a fresh "custom" composition directly instead).
    func with(
        name: String? = nil,
        extractorChoice: ExtractorChoice? = nil
    ) -> Composition {
        Composition(
            name: name ?? self.name,
            metric: self.metric,
            createdAt: self.createdAt,
            extractorChoice: extractorChoice ?? self.extractorChoice
        )
    }

    /// Backwards-compatible decode. Older JSON files carry now-removed keys
    /// (postProc/dither/ranker hashes, and the pre-deprecation `paletteMode`
    /// for the old `.shared` / `.global` Sinkhorn modes); they are simply not
    /// read, so old gene bundles still decode. Pre-Phase-C JSON has no
    /// `extractorChoice` key; we default to `.kMeans` so existing saved
    /// compositions reproduce the original behavior.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name       = try c.decode(String.self, forKey: .name)
        self.metric     = try c.decodeIfPresent(String.self, forKey: .metric)
        self.createdAt  = try c.decode(Date.self, forKey: .createdAt)
        let choice = (try? c.decode(ExtractorChoice.self,
                                    forKey: .extractorChoice)) ?? .kMeans
        self.extractorChoice = choice
    }

    static let classicalBaseline = Composition(
        name: Composition.baselineName,
        metric: nil,
        createdAt: Date(timeIntervalSince1970: 0),
        extractorChoice: .kMeans
    )
}
