import SwiftUI

/// OPTICAL-EV (Feature.opticalEV only): folds the three REAL-exposure rung tiles from the
/// engine into σ, LOOK-graded like the rest of the surface. Extracted into a `ViewModifier`
/// because inlining three more `.onChange` on `SurfaceView`'s already-long body tips the
/// SwiftUI type-checker past its expression-complexity limit ("unable to type-check in
/// reasonable time"). Flag off ⇒ these arrays stay empty (the session never builds the driver,
/// so `opticalTileCallback` never fires) and `InvertedPyramidField` falls back to
/// live-ladder / in-view pooling.
struct OpticalTileFolds: ViewModifier {
    let engine: CaptureViewModel
    let surface: Surface

    func body(content: Content) -> some View {
        content
            .onChange(of: engine.opticalTile64) { _, tile in
                if surface.phase == .live {
                    surface.opticalTile64 = engine.settings.captureLook.apply(to: tile)
                }
            }
            .onChange(of: engine.opticalTile32) { _, tile in
                if surface.phase == .live {
                    surface.opticalTile32 = engine.settings.captureLook.apply(to: tile)
                }
            }
            .onChange(of: engine.opticalTile16) { _, tile in
                if surface.phase == .live {
                    surface.opticalTile16 = engine.settings.captureLook.apply(to: tile)
                }
            }
    }
}
