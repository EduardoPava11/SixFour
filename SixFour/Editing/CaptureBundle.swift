import Foundation

/// In-memory archive of one capture's raw + extracted state. Held by
/// `CaptureViewModel.currentBundle` after every successful render,
/// discarded only when the next capture starts.
///
/// ## Purpose
///
/// The user wants editing tools to be able to re-process a captured
/// burst — apply a different extractor, tweak parameters, etc. —
/// without retaking the shot. That requires keeping the *inputs* to
/// the extraction (raw OKLab tiles) alive after the GIF is encoded,
/// not just the *outputs* (the palette baked into the GIF).
///
/// This struct is the contract those tools will bind against. It's
/// the smallest set of data that's both:
/// (a) **lossless re-extractability**: any PaletteExtractor can be
///     re-run on `tiles` to produce a new `perFrameStatistics`.
/// (b) **rich downstream consumption**: `perFrameStatistics` carries
///     per-cluster (mean, covariance, count) + per-pixel assignments
///     + algorithm provenance, enough for χ²-test significance,
///     principal-axis splitting, etc.
///
/// ## Lifecycle
///
/// - **Created**: by `CaptureViewModel` after a successful capture
///   and render. Assigned to `currentBundle`.
/// - **Replaced**: when the next capture starts (previous bundle
///   becomes garbage immediately).
/// - **Discarded**: app relaunch loses the bundle entirely (no disk
///   archive yet — that's deferred future work).
///
/// ## Memory
///
/// One bundle = 64 OKLab tiles × 4096 pixels × 12 bytes (SIMD3<Float>)
///             = 3 MB raw tile pixels
///           + 64 per-frame ClusterStatistics × 256 clusters × ~60 B
///             = ~1 MB stats
///           ≈ 4 MB total per bundle.
///
/// One bundle live at a time → 4 MB ceiling.
///
/// ## Why not stored on disk yet
///
/// Disk persistence is deferred to when the editing-tool UI lands.
/// At that point we'll add `Codable` conformance + write to
/// `Documents/sixfour_bundles/<uuid>/` so bundles survive app
/// relaunch. For now, the in-memory single-bundle path is enough
/// to validate the editing-tool integration story.
struct CaptureBundle: Sendable, Codable {
    /// Stable UUID for this capture. Same value if/when the bundle
    /// gets persisted to disk later, so editing-tool state can refer
    /// to "the X capture" durably.
    let id: UUID
    /// When the shutter was pressed (sample-buffer first-frame time
    /// is in `burstTiming` for sub-millisecond precision).
    let captureTimestamp: Date
    /// 63 inter-frame intervals: mean, σ, min, max. Surfaced as
    /// timing summary in the StatsFooter.
    let burstTiming: CaptureSession.BurstTiming
    /// Color-space tag at capture time — drives the Metal kernel's
    /// per-tag YCbCr10 decode path. Editing tools that re-render the
    /// bundle must use the same tag so the OKLab interpretation
    /// matches.
    let colorSpaceTag: CaptureSession.ActiveColorSpaceTag
    /// 64 raw OKLab tiles, each 64×64 = 4096 pixels. The
    /// re-extractable input.
    let tiles: [OKLabTile]
    /// 64 ClusterStatistics, one per tile — the output of the
    /// extractor that produced the currently-displayed GIF. Mutable
    /// so editing tools can replace specific frames with re-extracted
    /// stats without rebuilding the whole bundle.
    var perFrameStatistics: [ClusterStatistics]

    /// Canonical on-disk filename. Single-bundle persistence for
    /// now: the most-recent bundle overwrites the previous one.
    /// A future "browse old captures" UI will move to one-file-per-
    /// UUID under `Documents/sixfour_bundles/<uuid>.json`.
    static let canonicalFilename = "sixfour_bundle.json"

    /// Path to the canonical single-bundle file in Documents.
    static func canonicalURL() -> URL? {
        guard let docs = try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return nil }
        return docs.appendingPathComponent(canonicalFilename)
    }

    /// Serialize to JSON + write to the canonical Documents path.
    /// Best-effort: failures are logged at the call site, not
    /// thrown — bundle persistence is a nice-to-have, not a
    /// blocker for the render flow.
    /// Size estimate: ~4 MB JSON-encoded (3 MB tiles + 1 MB stats).
    /// Writes are off the main actor via the caller's
    /// Task.detached.
    func save(to url: URL = canonicalURL() ?? URL(fileURLWithPath: "/dev/null")) throws {
        let encoder = JSONEncoder()
        // Compact encoding: no pretty-printing (the file is for
        // machine round-trip, not human inspection).
        let data = try encoder.encode(self)
        try data.write(to: url, options: [.atomic])
    }

    /// Read + decode from the canonical Documents path. Returns nil
    /// if the file doesn't exist; throws if it exists but can't be
    /// decoded (caller decides whether to surface or swallow).
    static func load(from url: URL = canonicalURL() ?? URL(fileURLWithPath: "/dev/null")) throws -> CaptureBundle? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CaptureBundle.self, from: data)
    }
}
