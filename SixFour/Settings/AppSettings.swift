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
        // Preserved from the original @AppStorage in CaptureViewModel.
        static let paletteMode = "sixfour.paletteMode.v2"
        static let extractor   = "sixfour.extractor.v1"
        // New seams (no UI yet; default to today's behavior).
        static let openInPixelatedPreview = "sixfour.openInPixelatedPreview.v1"
        static let autoSaveToPhotos       = "sixfour.autoSaveToPhotos.v1"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Palette mode restored on launch / persisted on change. Stored as a
    /// versioned string so adding modes later needs no Int↔enum table; legacy
    /// `"0"`/`"1"` decode to `.perFrame`/`.shared`.
    var defaultPaletteMode: PaletteGenerator.Mode {
        didSet { defaults.set(Self.encode(defaultPaletteMode), forKey: Key.paletteMode) }
    }

    /// Per-frame extractor family restored on launch / persisted on change.
    var defaultExtractor: Composition.ExtractorChoice {
        didSet { defaults.set(defaultExtractor.rawValue, forKey: Key.extractor) }
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
        self.defaultPaletteMode = Self.decodeMode(defaults.string(forKey: Key.paletteMode))
        self.defaultExtractor = Composition.ExtractorChoice(
            rawValue: defaults.string(forKey: Key.extractor) ?? ""
        ) ?? .kMeans
        self.openInPixelatedPreview = defaults.bool(forKey: Key.openInPixelatedPreview)
        self.autoSaveToPhotos = defaults.bool(forKey: Key.autoSaveToPhotos)
    }

    private static func decodeMode(_ raw: String?) -> PaletteGenerator.Mode {
        switch raw {
        case "perFrame": return .perFrame
        case "shared":   return .shared
        case "global":   return .global
        // Legacy pre-v2 storage encoded 0/1 (perFrame/global); round to the
        // nearest live endpoint so old installs keep their pick.
        case "0":        return .perFrame
        case "1":        return .shared
        default:         return .perFrame
        }
    }

    private static func encode(_ mode: PaletteGenerator.Mode) -> String {
        switch mode {
        case .perFrame: return "perFrame"
        case .shared:   return "shared"
        case .global:   return "global"
        }
    }
}
