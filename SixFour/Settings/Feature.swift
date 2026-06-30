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

    /// The V2.1 pre-collapse capture/preview surface. **DEFERRED, OFF in MVP1.**
    ///
    /// V2.1 captures, per 64x64 bin, a probability curve per colour channel (the histogram of
    /// the camera box). The shipped GIF is the COLLAPSE (the mode, argmin energy of each curve);
    /// the model trains on the curves. `V21FieldView` surfaces that data structure: the collapsed
    /// result, the underlying per-cell R/G/B curves, and the per-cell uncertainty (curve spread).
    ///
    /// The view is compiled and golden-able, but every entry point is guarded by this flag, so
    /// with it `false` the V2.1 surface is statically unreachable and MVP1 is untouched. Flip to
    /// `true` to wire it into the post-capture surface in V2.1. Mirrors `globalPaletteV2`.
    static let v21Capture = false
}
