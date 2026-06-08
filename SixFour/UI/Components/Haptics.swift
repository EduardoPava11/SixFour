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

    /// Play a haptic by its `SixFourCellMechanics.haptics` token ordinal — the ONLY
    /// bridge from the spec's closed `Haptic` alphabet to a concrete generator. The
    /// spec decides *when* (the FSM transition / cell-crossing); this decides *how*.
    /// Ordinals match `Spec.CellMechanics.Haptic`'s `fromEnum`:
    /// 0 liftPop · 1 cellTick · 2 edgeStop · 3 dropAccept · 4 dropReject.
    static func play(_ token: Int) {
        switch token {
        case 0: impact(.medium)              // liftPop — "you've grabbed it"
        case 1: selection()                  // cellTick — the per-cell detent
        case 2: impact(.rigid)               // edgeStop — clamped at the lattice edge
        case 3: notification(.success)       // dropAccept
        case 4: notification(.error)         // dropReject
        default: break                       // -1 / unknown = no haptic
        }
    }
}
