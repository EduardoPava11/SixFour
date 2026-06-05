import SwiftUI
import UIKit
import simd

/// Full-screen fallback when camera authorization is denied. Opens iOS
/// Settings via deep link so the user can grant access without leaving the
/// app's mental model.
struct UnauthorizedView: View {
    var body: some View {
        VStack(spacing: 18) {
            CellSymbol(systemName: "camera.metering.unknown", box: 28, ink: Color(srgb8: SIMD3(180, 180, 180)))
            CellText("Camera access denied", rows: 11, ink: .white)
            // Prose paragraph kept as system Text (it must wrap) — §6.8 prose exemption.
            Text("SixFour captures 64 frames at 20 fps to build a 64×64 animated GIF. Enable camera access in Settings to continue.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 32)
            Button { openSettings() } label: {
                HStack(spacing: GlobalLattice.pt(2)) {
                    CellSymbol(systemName: "gear", box: 8, ink: .white)
                    CellText("Open Settings", rows: 11, ink: .white)
                }
                .padding(.horizontal, GlobalLattice.pt(6))
                .frame(minHeight: 44)
                .background(Color(srgb8: SFTheme.ledGhost))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Settings")
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
            CellSymbol(systemName: "exclamationmark.triangle", box: 24, ink: Color(srgb8: SIMD3(225, 200, 70)))
            CellText("Something went wrong", rows: 11, ink: .white)
            // Prose error message kept as system Text (must wrap) — §6.8 prose exemption.
            Text(message)
                .font(.system(.callout, design: .monospaced))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 32)
                .lineLimit(6)
            Button(action: onRetry) {
                CellText("Try again", rows: 11, ink: Color(srgb8: SIMD3(20, 20, 20)))
                    .padding(.horizontal, GlobalLattice.pt(6))
                    .frame(minHeight: 44)
                    .background(Color(srgb8: SIMD3(245, 245, 245)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Try again")
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
                CellText("Configuring camera…", rows: 8, ink: Color(srgb8: SIMD3(150, 150, 150)))
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
