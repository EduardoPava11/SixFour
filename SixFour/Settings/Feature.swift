import Foundation

/// Compile-time feature gates for SixFour.
///
/// These are build-level constants (not user settings) for staging features across versions.
/// They default OFF and are flipped by an engineer when a version ships, mirroring the dormant
/// `rgbt4dEnabled` / `colorAtlasEnabled` pattern.
enum Feature {

    /// The global (single) colour palette — the GIFB collapse path. **DEFERRED TO V2.**
    ///
    /// MVP1 ships **per-frame palettes only**. The global path is implemented, compiled, and
    /// golden-gated (Haskell ≡ Swift ≡ Zig), but every entry point to it is guarded by this flag,
    /// so with it `false` the global render is statically unreachable on device. Flip to `true`
    /// to re-enable the global path in V2.
    ///
    /// Guard sites (see `docs/SIXFOUR-GLOBAL-PALETTE-RETIREMENT-WORKFLOW.md` §2): the capture
    /// router (GS1), the Review Ship/Export rung (GS2), the group-pick (GS3) and cut-lever (GS4)
    /// preview tools, and the Color Atlas curation + curated-leaves injection (GS5). A stale
    /// persisted `paletteScope == .global` is sanitised to per-frame while this is off (SAN).
    static let globalPaletteV2 = false

    /// The per-frame orthogonal A/B candidate picker (Pillar B). Surfaces the two
    /// `GenomePair.sampleOrthogonalPair` candidate looks in Review; tapping one records a Compare.
    /// OFF in MVP1 (the surfacing is new and runs only on device); flip on to test the A/B flow.
    /// See `docs/SIXFOUR-PER-FRAME-GENOME-AB-MIGRATION-WORKFLOW.md` Pillar B / Phase 3.
    static let abCandidatePicker = true
}
