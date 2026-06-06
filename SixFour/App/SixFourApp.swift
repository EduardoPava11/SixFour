import SwiftUI

@main
struct SixFourApp: App {
    var body: some Scene {
        WindowGroup {
            SurfaceView()
                .preferredColorScheme(.dark)
                .statusBarHidden()
        }
    }
}
