import Foundation
import Observation

/// Centralised, persisted user preferences — the single source of truth for
/// values that survive launches. Extracted from `CaptureViewModel`, which
/// previously buried two `@AppStorage` keys and their encode/decode glue in
/// the middle of capture orchestration.
///
/// This is the seam the in-app Settings screen will bind to: present a
/// `SettingsView` that edits these properties (e.g. via `@Bindable`), and the
/// capture screen automatically picks up the new defaults. New options are
/// added here once — one stored property + one `Key` — without touching the
/// capture pipeline.
///
/// Backed by `UserDefaults` (inject a custom suite in tests). Persistence
/// keys are preserved verbatim from the original `@AppStorage` so existing
/// installs keep their saved choices. Sensitive data must not live here — use
/// the Keychain for that.
@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let ditherMethod = "sixfour.ditherMethod.v1"
        static let ditherKernel = "sixfour.ditherKernel.v1"
        static let ditherSerpentine = "sixfour.ditherSerpentine.v1"
        static let blueNoiseTemporal = "sixfour.blueNoiseTemporal.v1"
        // New seams (no UI yet; default to today's behavior).
        static let openInPixelatedPreview = "sixfour.openInPixelatedPreview.v1"
        static let autoSaveToPhotos       = "sixfour.autoSaveToPhotos.v1"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Dither sampler (the residual-shaping estimator) restored on launch /
    /// persisted on change. This is the only creative-but-statistical control;
    /// it lives in Settings, not on the capture screen.
    var defaultDitherMethod: DitherMethod {
        didSet { defaults.set(defaultDitherMethod.rawValue, forKey: Key.ditherMethod) }
    }

    /// Error-diffusion kernel (mean- vs contrast-preserving). Used only when
    /// `defaultDitherMethod == .errorDiffusion`.
    var ditherKernel: DitherKernelChoice {
        didSet { defaults.set(ditherKernel.rawValue, forKey: Key.ditherKernel) }
    }

    /// Serpentine (boustrophedon) error-diffusion scan — whitens the
    /// scan-direction anisotropy. Used only when `.errorDiffusion`.
    var ditherSerpentine: Bool {
        didSet { defaults.set(ditherSerpentine, forKey: Key.ditherSerpentine) }
    }

    /// Blue-noise temporal residual spectrum (3-D spatiotemporal vs frozen
    /// 2-D). Used only when `defaultDitherMethod == .blueNoise`.
    var blueNoiseTemporal: BlueNoiseTemporalMode {
        didSet { defaults.set(blueNoiseTemporal.rawValue, forKey: Key.blueNoiseTemporal) }
    }

    /// The full sampler configuration assembled from the persisted fields —
    /// the single value the render pipeline consumes.
    var ditherConfig: DitherConfig {
        DitherConfig(
            method: defaultDitherMethod,
            kernel: ditherKernel,
            serpentine: ditherSerpentine,
            temporal: blueNoiseTemporal
        )
    }

    /// Whether the camera opens in the 64×64 pixelated preview rather than
    /// full-res. (Settings-screen seam; defaults to full-res = today.)
    var openInPixelatedPreview: Bool {
        didSet { defaults.set(openInPixelatedPreview, forKey: Key.openInPixelatedPreview) }
    }

    /// Whether each rendered GIF is auto-saved to the Photos library.
    /// (Settings-screen seam; defaults to off = today.)
    var autoSaveToPhotos: Bool {
        didSet { defaults.set(autoSaveToPhotos, forKey: Key.autoSaveToPhotos) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // `didSet` does not fire during init, so these reads don't write back.
        self.defaultDitherMethod = DitherMethod(
            rawValue: defaults.string(forKey: Key.ditherMethod) ?? ""
        ) ?? .errorDiffusion
        self.ditherKernel = DitherKernelChoice(
            rawValue: defaults.string(forKey: Key.ditherKernel) ?? ""
        ) ?? .floydSteinberg
        // Absent key → false = raster (today's default).
        self.ditherSerpentine = defaults.bool(forKey: Key.ditherSerpentine)
        self.blueNoiseTemporal = BlueNoiseTemporalMode(
            rawValue: defaults.string(forKey: Key.blueNoiseTemporal) ?? ""
        ) ?? .spatiotemporal
        self.openInPixelatedPreview = defaults.bool(forKey: Key.openInPixelatedPreview)
        self.autoSaveToPhotos = defaults.bool(forKey: Key.autoSaveToPhotos)
    }
}
