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
    /// Which of the three Sinkhorn modes the user picked.
    let paletteMode: PaletteGenerator.Mode

    static let baselineName = "Baseline"
    var isBaseline: Bool { name == Composition.baselineName }

    init(
        name: String,
        metric: String?,
        createdAt: Date,
        paletteMode: PaletteGenerator.Mode = .perFrame
    ) {
        self.name = name
        self.metric = metric
        self.createdAt = createdAt
        self.paletteMode = paletteMode
    }

    /// Backwards-compatible decode. Older JSON files include
    /// postProc/dither/ranker hashes; we silently drop them (the slots
    /// no longer exist). The pre-v3 `paletteMode` encoded `.global` as
    /// `θ → ∞`; today that maps to `.global` directly. The old
    /// `.spectrum(θ)` case is rounded to `.shared` (the nearest live
    /// endpoint).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name       = try c.decode(String.self, forKey: .name)
        self.metric     = try c.decodeIfPresent(String.self, forKey: .metric)
        self.createdAt  = try c.decode(Date.self, forKey: .createdAt)
        let mode = (try? c.decode(PaletteGenerator.Mode.self,
                                  forKey: .paletteMode)) ?? .perFrame
        self.paletteMode = mode
    }

    static let classicalBaseline = Composition(
        name: Composition.baselineName,
        metric: nil,
        createdAt: Date(timeIntervalSince1970: 0),
        paletteMode: .perFrame
    )
}
