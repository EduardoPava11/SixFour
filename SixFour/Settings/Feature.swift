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
    /// ON: the review bench shows FIELD (the two probability widgets) and AIRDROP (GIF + field tensor),
    /// both built from the committed burst. Not read by the capture engine, so it only lights the UI.
    static let v21Capture = true

    /// V3.0 on-device SOMATIC training at the capture seam. **ON while V3 is built.**
    ///
    /// With this on, `CaptureSession.finishBurst` trains the per-capture θ_up gene
    /// (`CaptureGene.train`: burst tiles → Q16 volume → one fused GPU dispatch,
    /// `docs/V3-BUILD-WORKFLOW.md` B2.3) and carries it on `BurstResult.thetaUp`.
    /// The gene is optional everywhere — zero-gene == the deterministic floor — so
    /// flipping this off (or any failure) degrades to exactly today's output.
    static let v3SomaticTrain = true

    /// The meta-INIT W₀ start for the per-capture somatic gene. **OFF until a real
    /// corpus validates it.**
    ///
    /// With this on, `CaptureGene.train` starts the fused descent from `MetaInit.deployedW0`
    /// (a shipped `metainit-w0.bin` blob, or the synthetic stand-in) instead of the zero
    /// floor — the offline-amortised few-step fit (`docs/PER-CAPTURE-LEARNING-RESEARCH.md`
    /// §5). It is OFF because the only W₀ available today is trained on SYNTHETIC captures,
    /// which may not transfer to real scenes; flipping it on before a real-corpus blob
    /// ships could make live captures worse than the zero start. The plumbing (kernel
    /// buffer 7, `trainOnVolume(w0:)`, the loader) is inert while this is false — the gene
    /// starts from zero exactly as today.
    static let metaInitW0 = false

    /// The Loom's multi-scale INDEPENDENT capture (16³/32³/64³ = three independent
    /// exposure reads, not pools of one source). **OFF — device-only, in bring-up.**
    ///
    /// With this on, `MultiScaleLadder` configures the interleaved EV/gain exposure
    /// ladder (`CaptureDiversity` recipe: coarse long-exposure-high-gain → fine
    /// short-exposure-low-gain, tiled to cover the scene DR) and routes the frames
    /// into `SixFourNative.multiScaleIntegrate` → three independent volumes →
    /// `SixFourNative.renderSelect`. The whole pure-math floor is golden-gated
    /// (Haskell ≡ Zig), but the AVFoundation exposure scheduling only runs on a real
    /// device (custom exposure is unavailable/ignored in the Simulator), so this
    /// stays OFF until validated on an iPhone 17 Pro. With it off, capture is exactly
    /// today's single-exposure path — the ladder is statically unreachable.
    static let multiScaleLadder = false

    /// The yin-yang circuit LIVE at the capture seam. **ON while the color head ships.**
    ///
    /// With this on, every burst tick also runs the 16/32/64 ladder (`ColorHead`:
    /// x420 measurement path → exact u64 sums at 20/10/5 Hz), and `finishBurst`
    /// trains the S_t yang band head on the burst's OWN manufactured t-band pairs
    /// (`BandHeadTrainer`, plain Metal, the YinYangCircuitTests conventions) —
    /// the yin ladder makes the labels, the yang head consumes them, per capture,
    /// on the phone. Telemetry-only for now (log + `bandHeadCallback`); no GIF
    /// byte depends on it, so flipping this off degrades to exactly today's output.
    static let yinYangBands = true

    /// The LIVE-LADDER preview realization — the inverted-pyramid's 32²/16² rungs
    /// read the REAL device ladder instead of view-pooling the 64² index tile.
    /// **OFF — device-only, in bring-up (mirrors `multiScaleLadder`).**
    ///
    /// With this on, a persistent preview-side `ColorHead` ingests the idle x420
    /// preview buffers on the delegate queue, realizes its `latest32` / `latest16`
    /// linear16 BT.2020 sums to sRGB8 via the inverse-EOTF kernel
    /// (`s4_sums_bt2020_to_srgb8`, `Spec.RadiometricRealize`), and publishes them as
    /// two direct RGB tiles onto σ; `InvertedPyramidField` reads those for its 32²/16²
    /// tiles. With it OFF the preview head is never constructed, the ladder callback
    /// never fires, `surface.previewTile32/16` stay empty, and the pyramid's 32²/16²
    /// rungs fall through BYTE-FOR-BYTE to today's in-view `ColorHead.poolSpatial2`
    /// pooling + digital gain. The shipped 64-frame burst→GIF path (the separate
    /// per-burst `colorHead`, `finishBurst`, v21/θ_up) is unaffected either way.
    ///
    /// Display-only: no GIF byte depends on it. The x420 sums are HLG-linearized
    /// telemetry, so the realized 32²/16² tiles are a gauge, not a colorimetric
    /// match to the GPU 64² index-palette preview — flip on and confirm on an
    /// iPhone 17 Pro before considering the default.
    static let liveLadder = false

    /// OPTICAL-EV — REAL exposure bracketing, NO digital gain. When true the live preview
    /// runs `ExposureBracketDriver`: it cycles `setExposureModeCustom` across three real
    /// exposures and routes each settled frame to
    /// its tile — a monotonic light ladder (64²=base / 32²=+1 stop / 16²=+2 stops, so the 16²
    /// gets 4× the light of the 64², mirroring its 4-frame temporal pooling).
    /// DEVICE-ONLY (the Simulator has no camera; the driver no-ops without a real
    /// sensor). Preview-only — the shipped 64-frame burst→GIF path is untouched. Takes
    /// precedence over `liveLadder`/in-view pooling in `InvertedPyramidField`.
    static let opticalEV = false

    /// The R3D `.cube` LUT export on the Exported bench. **DEPRECATED — OFF
    /// (Daniel's call, 2026-07-08: not needed for this app).**
    ///
    /// With this off the EXPORT LUT button never renders, so the 65³
    /// `s4_build_cube_q16` dispatch + ~8 MB text assembly it ran ON THE MAIN
    /// ACTOR (the audited Review-screen hitch) is statically unreachable. The
    /// kernels and `LUTFile` stay compiled and golden-gated
    /// (`lut_fixture_test` battery) — gate, don't delete.
    static let lutExport = false

    /// MULTISCALE RENDER — the always-on adaptive 16/32/64 GIF. When true, `renderOnce` swaps the
    /// uniform 64³ tiles for the halt-floor multiscale cube (fused via `MultiScaleRender` →
    /// `s4_render_select`): motion regions stay 64³, static regions collapse to chunky block-16³.
    /// DERIVED capture (the three volumes pooled from one 64³ burst; independent EV-bracketed
    /// capture is the `multiScaleLadder` device upgrade). SAFETY: an all-depth-2 field reproduces
    /// the current renderer bit-for-bit (`MultiScaleRenderTests`), so the default (flag off) path
    /// is untouched.
    static let multiScaleRender = false
}
