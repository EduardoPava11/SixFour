import SwiftUI

@main
struct SixFourApp: App {
    var body: some Scene {
        WindowGroup {
            CaptureView()
                .preferredColorScheme(.dark)
                .statusBarHidden()
        }
    }
}
