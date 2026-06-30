import SwiftUI
import Foundation

@main
struct SixFourApp: App {
    // Earliest user code in the process. NSLog (NOT os_log .debug, which is filtered from the device
    // console) so a launch crash is bracketed from the first instruction. Trace prefix "SF-".
    // Kick the StageGround Metal core build OFF the main thread from the first instruction, so the
    // heavy render-PSO compile (makeDefaultLibrary + makeFunction + makeRenderPipelineState) runs in
    // parallel with launch instead of stalling the first CATransaction during SurfaceView's first body.
    init() {
        NSLog("SF-A: app init")
        FieldMetalCore.prime()
    }

    var body: some Scene {
        WindowGroup {
            // THE only mounted view: the one surface owns σ, κ, and the capture engine.
            SurfaceView()
        }
    }
}
