import Foundation

/// A "signature look" — an optional metric organ plus the dither-method
/// choice. Earlier revisions held postProc / ranker slots and a per-frame
/// palette-extraction *algorithm* choice (K-means / Wu / Octree); those were
/// collapsed once the research showed Wu-initialized k-means is the single
/// quality leader (the others were strictly higher-error options). Stored as a
/// small JSON file inside a `.sixfour-genes` bundle.
struct Composition: Codable, Sendable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let metric: String?     // descriptor hash of the metric organ, or nil
    let createdAt: Date
    /// Which dithering method the user picked — the single creative palette
    /// control now (the extraction algorithm is fixed at Wu-initialized
    /// k-means). Default `.errorDiffusion` matches the original look.
    let ditherMethod: DitherMethod

    static let baselineName = "Baseline"
    var isBaseline: Bool { name == Composition.baselineName }

    init(
        name: String,
        metric: String?,
        createdAt: Date,
        ditherMethod: DitherMethod = .errorDiffusion
    ) {
        self.name = name
        self.metric = metric
        self.createdAt = createdAt
        self.ditherMethod = ditherMethod
    }

    /// Returns a copy with the given fields overridden; any field left `nil`
    /// is carried over unchanged.
    func with(
        name: String? = nil,
        ditherMethod: DitherMethod? = nil
    ) -> Composition {
        Composition(
            name: name ?? self.name,
            metric: self.metric,
            createdAt: self.createdAt,
            ditherMethod: ditherMethod ?? self.ditherMethod
        )
    }

    /// Backwards-compatible decode. Older JSON files carry now-removed keys
    /// (postProc/ranker hashes, the pre-deprecation `paletteMode`, and the
    /// collapsed `extractorChoice`); they are simply not read, so old gene
    /// bundles still decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name       = try c.decode(String.self, forKey: .name)
        self.metric     = try c.decodeIfPresent(String.self, forKey: .metric)
        self.createdAt  = try c.decode(Date.self, forKey: .createdAt)
        let dm = (try? c.decode(DitherMethod.self,
                                forKey: .ditherMethod)) ?? .errorDiffusion
        self.ditherMethod = dm
    }

    static let classicalBaseline = Composition(
        name: Composition.baselineName,
        metric: nil,
        createdAt: Date(timeIntervalSince1970: 0),
        ditherMethod: .errorDiffusion
    )
}
