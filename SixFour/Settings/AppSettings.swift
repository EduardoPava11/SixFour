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
        static let useDeterministicCore   = "sixfour.useDeterministicCore.v1"
        // Palette-structure visualisation (Review screen).
        static let showPaletteTree        = "sixfour.showPaletteTree.v1"
        static let paletteBranching       = "sixfour.paletteBranching.v1"
        static let paletteScope           = "sixfour.paletteScope.v1"
        static let paletteRepresentation  = "sixfour.paletteRepresentation.v1"
        static let gridAxisX              = "sixfour.gridAxisX.v1"
        static let gridAxisY              = "sixfour.gridAxisY.v1"
        // Voxel-cube explorer (Review .voxel3D mode).
        static let voxelProvenanceMode    = "sixfour.voxelProvenanceMode.v1"
        static let voxelLumaFloor         = "sixfour.voxelLumaFloor.v1"
        static let voxelAutoRotate        = "sixfour.voxelAutoRotate.v1"
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

    /// Whether to render through the deterministic fixed-point Zig core (the
    /// per-stage pipeline whose bytes are reproducible, surfaced as a SHA-256 in
    /// Review) rather than the GPU float path. Defaults ON — determinism is the
    /// product; the GPU path stays as a silent fallback if a kernel ever fails.
    var useDeterministicCore: Bool {
        didSet { defaults.set(useDeterministicCore, forKey: Key.useDeterministicCore) }
    }

    /// Whether the Review screen shows the palette explorer (structure treemap /
    /// coordinate grid) beneath the GIF. Defaults **ON** — seeing the 256 colours
    /// is the point; the user can hide it in Settings.
    var showPaletteTree: Bool {
        didSet { defaults.set(showPaletteTree, forKey: Key.showPaletteTree) }
    }

    /// Which branching the palette-structure view uses: `16² / 4⁴ / 2⁸` — all
    /// views of the one median-cut tree. Defaults to the flat `16²` grid.
    var paletteBranching: PaletteBranching {
        didSet { defaults.set(paletteBranching.rawValue, forKey: Key.paletteBranching) }
    }

    /// Whether the Review structure view shows the per-frame palettes (NN input) or the
    /// collapsed global palette (NN output, editable). Defaults to per-frame.
    var paletteScope: PaletteScope {
        didSet { defaults.set(paletteScope.rawValue, forKey: Key.paletteScope) }
    }

    /// Which dimensional view the palette tool shows: the median-cut `.structure`
    /// treemap, or the user-assignable `.grid` (16×16 coordinate grid). Defaults to structure.
    var paletteRepresentation: PaletteRepresentation {
        didSet { defaults.set(paletteRepresentation.rawValue, forKey: Key.paletteRepresentation) }
    }

    /// The dimension the grid's x axis encodes (defaults to OKLab `a`, green→red).
    var gridAxisX: GridAxis {
        didSet { defaults.set(gridAxisX.rawValue, forKey: Key.gridAxisX) }
    }

    /// The dimension the grid's y axis encodes (defaults to OKLab `L`, lightness).
    var gridAxisY: GridAxis {
        didSet { defaults.set(gridAxisY.rawValue, forKey: Key.gridAxisY) }
    }

    /// Voxel cube provenance filter: 0 = all, 1 = extracted only, 2 = split only.
    /// Defaults to 0 (the honest all-solid verifier).
    var voxelProvenanceMode: Int {
        didSet { defaults.set(voxelProvenanceMode, forKey: Key.voxelProvenanceMode) }
    }

    /// Voxel cube luminance air floor (0…255). Defaults to 0 (fully solid cube).
    var voxelLumaFloor: Int {
        didSet { defaults.set(voxelLumaFloor, forKey: Key.voxelLumaFloor) }
    }

    /// Whether the voxel cube auto-rotates. Defaults off (rest = flat 2D view).
    var voxelAutoRotate: Bool {
        didSet { defaults.set(voxelAutoRotate, forKey: Key.voxelAutoRotate) }
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
        // Absent key → deterministic core ON (the default product behaviour).
        self.useDeterministicCore = defaults.object(forKey: Key.useDeterministicCore) as? Bool ?? true
        // Absent key → explorer ON (so the palette views are visible by default).
        self.showPaletteTree = defaults.object(forKey: Key.showPaletteTree) as? Bool ?? true
        self.paletteBranching = PaletteBranching(
            rawValue: defaults.string(forKey: Key.paletteBranching) ?? ""
        ) ?? .b16
        self.paletteScope = PaletteScope(
            rawValue: defaults.string(forKey: Key.paletteScope) ?? ""
        ) ?? .perFrame
        self.paletteRepresentation = PaletteRepresentation(
            rawValue: defaults.string(forKey: Key.paletteRepresentation) ?? ""
        ) ?? .structure
        self.gridAxisX = GridAxis(rawValue: defaults.string(forKey: Key.gridAxisX) ?? "") ?? .a
        self.gridAxisY = GridAxis(rawValue: defaults.string(forKey: Key.gridAxisY) ?? "") ?? .L
        // Absent keys → 0 / 0 / false (all-solid, no air, no auto-rotate).
        self.voxelProvenanceMode = defaults.integer(forKey: Key.voxelProvenanceMode)
        self.voxelLumaFloor = defaults.integer(forKey: Key.voxelLumaFloor)
        self.voxelAutoRotate = defaults.bool(forKey: Key.voxelAutoRotate)
    }
}
