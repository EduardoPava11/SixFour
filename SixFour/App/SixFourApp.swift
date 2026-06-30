import SwiftUI
import Foundation

@main
struct SixFourApp: App {
    // Earliest user code in the process. NSLog (NOT os_log .debug, which is filtered from the device
    // console) so a launch crash is bracketed from the first instruction. Trace prefix "SF-".
    init() { NSLog("SF-A: app init") }

    var body: some Scene {
        WindowGroup {
            // THE only mounted view: the one surface owns σ, κ, and the capture engine.
            SurfaceView()
        }
    }
}
