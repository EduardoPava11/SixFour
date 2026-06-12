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
        // Capture-screen LOOK (swipe to cycle); also what Export LUT bakes for R3D.
        static let captureLook            = "sixfour.captureLook.v1"
        static let paletteRepresentation  = "sixfour.paletteRepresentation.v1"
        static let gridAxisX              = "sixfour.gridAxisX.v1"
        static let gridAxisY              = "sixfour.gridAxisY.v1"
        // Unified player (Review GIF hero): which render mode the 2D/3D toggle shows.
        // Debug-only ownership overlay (full-lattice identity-badge bitmap). Default OFF.
        static let debugOwnershipOverlay  = "sixfour.debugOwnershipOverlay.v1"
        // Color Atlas — the 16³ curation board + curated-global-palette seam
        // (docs/COLOR-ATLAS.md). Default OFF: the production path is
        // byte-identical while false.
        static let colorAtlasEnabled      = "sixfour.colorAtlas.v1"
        static let paletteControlEnabled  = "sixfour.paletteControl.v1"
        // Movable ColorWidget positions (col,row in atoms). Defaults = the spec docks.
        static let field64Position        = "sixfour.field64Position.v1"
        static let palette16Position      = "sixfour.palette16Position.v1"
        static let diversityRingPosition  = "sixfour.diversityRingPosition.v1"
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

    /// The capture-screen LOOK (swipe to cycle): a data-driven OKLab palette→palette
    /// transform derived from the live palette's luminance-zone profile, recolouring
    /// the preview + palette/shutter. The SAME look is what Export LUT bakes for R3D.
    /// Defaults to `.off` (honest, ungraded).
    var captureLook: LookVariant {
        didSet { defaults.set(captureLook.rawValue, forKey: Key.captureLook) }
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

    /// Debug-only: paint the full 100×218 ownership identity-badge bitmap as the
    /// outermost overlay on the surface. Defaults **OFF** — shipping UI is byte-
    /// identical with this false (the `.overlay` branch yields `EmptyView`).
    var debugOwnershipOverlay: Bool {
        didSet { defaults.set(debugOwnershipOverlay, forKey: Key.debugOwnershipOverlay) }
    }

    /// Whether the Color Atlas curation surface (the 16³ board, the Compare
    /// gallery, and the curated-global-palette render seam) is enabled.
    /// Defaults **OFF** — with this false the review field, the collapse seam,
    /// and the rendered bytes are byte-identical to the pre-Atlas app.
    var colorAtlasEnabled: Bool {
        didSet { defaults.set(colorAtlasEnabled, forKey: Key.colorAtlasEnabled) }
    }

    /// Whether the global-palette CREATION control (the PALETTE sub-state: radix-face
    /// selector + LAB rank axes + a live 16×16 preview that equals the exported GIFB) is
    /// reachable from Review. Defaults **OFF** — the default render/UI path is
    /// byte-identical with this false. SIXFOUR-WIDGETS Family 2 / docs/SIXFOUR-GLOBAL-PALETTE-CONTROL.md.
    var paletteControlEnabled: Bool {
        didSet { defaults.set(paletteControlEnabled, forKey: Key.paletteControlEnabled) }
    }

    // MARK: - Movable ColorWidget positions (the ONE shared layout)

    /// A user-set widget position, in lattice atoms (col,row). Stored as a small
    /// `Equatable` struct (cleaner than a tuple for `@Observable`/round-trip tests).
    /// Persisted as a human-readable `"col,row"` String per the design.
    struct GridPoint: Equatable, Sendable {
        var col: Int
        var row: Int
    }

    /// `Field64`'s global position (preview ≡ gif-render ≡ review hero). Persisted on
    /// change; defaults to the generated spec dock (`MoveContract.defaultCol/Row`).
    var field64Position: GridPoint {
        didSet { defaults.set("\(field64Position.col),\(field64Position.row)", forKey: Key.field64Position) }
    }

    /// `Palette16`'s global position (the 256-colour palette ≡ the capture shutter).
    var palette16Position: GridPoint {
        didSet { defaults.set("\(palette16Position.col),\(palette16Position.row)", forKey: Key.palette16Position) }
    }

    /// `DiversityRing`'s global position (the re-introduced diversity gauge).
    var diversityRingPosition: GridPoint {
        didSet { defaults.set("\(diversityRingPosition.col),\(diversityRingPosition.row)", forKey: Key.diversityRingPosition) }
    }

    /// The ONE shared movable layout: identity → position, the same `Placement` shape
    /// the spec uses. Reading assembles the three stored properties; writing fans a
    /// whole `Placement` back out to them (the `didSet`s persist each). Callers move a
    /// single widget by reading this, calling `MoveContract.move`, and writing it back.
    var widgetPlacement: [ColorIdentity: (col: Int, row: Int)] {
        get {
            [.field64: (field64Position.col, field64Position.row),
             .palette16: (palette16Position.col, palette16Position.row),
             .diversityRing: (diversityRingPosition.col, diversityRingPosition.row)]
        }
        set {
            if let p = newValue[.field64] { field64Position = GridPoint(col: p.col, row: p.row) }
            if let p = newValue[.palette16] { palette16Position = GridPoint(col: p.col, row: p.row) }
            if let p = newValue[.diversityRing] { diversityRingPosition = GridPoint(col: p.col, row: p.row) }
        }
    }

    /// Parse a stored `"col,row"` String into a `GridPoint`; absent/garbage → the spec
    /// default (the existing fallback discipline — defaults are the generated dock, never
    /// hand-typed literals).
    private static func parsePosition(_ stored: String?, _ identity: ColorIdentity) -> GridPoint {
        let fallback = GridPoint(col: MoveContract.defaultCol(identity),
                                 row: MoveContract.defaultRow(identity))
        guard let stored else { return fallback }
        let parts = stored.split(separator: ",")
        guard parts.count == 2, let c = Int(parts[0]), let r = Int(parts[1]) else { return fallback }
        return GridPoint(col: c, row: r)
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
        self.captureLook = LookVariant(
            rawValue: defaults.string(forKey: Key.captureLook) ?? ""
        ) ?? .off
        self.paletteRepresentation = PaletteRepresentation(
            rawValue: defaults.string(forKey: Key.paletteRepresentation) ?? ""
        ) ?? .structure
        self.gridAxisX = GridAxis(rawValue: defaults.string(forKey: Key.gridAxisX) ?? "") ?? .a
        self.gridAxisY = GridAxis(rawValue: defaults.string(forKey: Key.gridAxisY) ?? "") ?? .L
        // Absent key → false ⇒ overlay OFF (shipping UI byte-identical).
        self.debugOwnershipOverlay = defaults.bool(forKey: Key.debugOwnershipOverlay)
        // Absent key → false ⇒ Color Atlas OFF (production path byte-identical).
        self.colorAtlasEnabled = defaults.bool(forKey: Key.colorAtlasEnabled)
        self.paletteControlEnabled = defaults.bool(forKey: Key.paletteControlEnabled)

        // Movable ColorWidget positions: parse each stored "col,row" (absent/garbage →
        // the generated spec dock).
        var parsed: [ColorIdentity: GridPoint] = [
            .field64: Self.parsePosition(defaults.string(forKey: Key.field64Position), .field64),
            .palette16: Self.parsePosition(defaults.string(forKey: Key.palette16Position), .palette16),
            .diversityRing: Self.parsePosition(defaults.string(forKey: Key.diversityRingPosition), .diversityRing),
        ]
        // Defense-in-depth: a corrupt store can never yield an overlapping live scene.
        // Re-validate the parsed Placement through the generated MoveContract; if it is
        // out-of-bounds or overlapping, fall back to the proven default placement.
        let scene = MoveContract.placementScene(parsed.mapValues { ($0.col, $0.row) })
        let inBounds = scene.allSatisfy {
            $0.col >= 0 && $0.col + $0.w <= MoveContract.cols
                && $0.row >= 0 && $0.row + $0.h <= MoveContract.rows
        }
        if !inBounds || !GridLayoutContract.isDisjoint(scene) {
            for (i, pos) in MoveContract.defaultPlacement {
                parsed[i] = GridPoint(col: pos.col, row: pos.row)
            }
        }
        // `didSet` does not fire during init — so these reads do not write back.
        self.field64Position = parsed[.field64]!
        self.palette16Position = parsed[.palette16]!
        self.diversityRingPosition = parsed[.diversityRing]!
    }
}
