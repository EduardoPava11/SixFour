import UIKit

/// Centralised haptic feedback.
///
/// These were three `nonisolated private static` helpers on
/// `CaptureViewModel`, fired from ~15 sites. Pulling them into one type gives
/// a single place to later gate on a user "Haptics" preference
/// (`AppSettings.hapticsEnabled`, Phase 4) instead of touching every call
/// site, and keeps the view model focused on capture/render orchestration.
///
/// Each call hops to the MainActor (UIKit feedback generators are
/// main-actor-bound) and returns immediately, so callers can stay nonisolated.
enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        Task { @MainActor in
            UIImpactFeedbackGenerator(style: style).impactOccurred()
        }
    }

    static func notification(_ kind: UINotificationFeedbackGenerator.FeedbackType) {
        Task { @MainActor in
            UINotificationFeedbackGenerator().notificationOccurred(kind)
        }
    }

    static func selection() {
        Task { @MainActor in
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}
