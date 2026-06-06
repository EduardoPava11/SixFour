import SwiftUI

@main
struct SixFourApp: App {
    var body: some Scene {
        WindowGroup {
            // THE only mounted view: the one surface owns σ, κ, and the capture engine.
            SurfaceView()
        }
    }
}
