import SwiftUI
import UIKit

/// Full-screen fallback when camera authorization is denied. Opens iOS
/// Settings via deep link so the user can grant access without leaving the
/// app's mental model.
struct UnauthorizedView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
            Text("Camera access denied")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("SixFour captures 64 frames at 20 fps to build a 64×64 animated GIF. Enable camera access in Settings to continue.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 32)
            Button {
                openSettings()
            } label: {
                Label("Open Settings", systemImage: "gear")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

/// Full-screen fallback when bootstrap or capture fails for a reason the
/// user can act on (or at least understand). Retry re-runs `bootstrap`.
struct FailureView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.yellow)
            Text("Something went wrong")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text(message)
                .font(.system(.callout, design: .monospaced))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 32)
                .lineLimit(6)
            Button("Try again", action: onRetry)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }
}

/// Pre-bootstrap skeleton — a subtle pulse while the AVCaptureSession is
/// being configured. Avoids the "black screen with nothing happening"
/// state that the previous `.configuring` phase left visible.
struct BootstrapSkeleton: View {
    @State private var animate = false
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(animate ? 0.10 : 0.04))
                    .aspectRatio(1, contentMode: .fit)
                    .padding(.horizontal, 24)
                Text("Configuring camera…")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.vertical, 60)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Configuring the camera")
    }
}
