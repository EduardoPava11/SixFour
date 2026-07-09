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

    /// A single retained, PREPARED selection generator (the per-cell detent fires up to
    /// once per 20 fps frame, so a warm engine matters). Re-`prepare()`d after each tick to
    /// keep the Taptic engine ready for the next frame's `cellTick` — far crisper than
    /// allocating a fresh unprepared generator per call. Delivery is still a MainActor hop
    /// (UIKit generators are main-actor-bound); the *decision* is frame-locked upstream.
    @MainActor private static let selector: UISelectionFeedbackGenerator = {
        let g = UISelectionFeedbackGenerator()
        g.prepare()
        return g
    }()

    static func selection() {
        Task { @MainActor in
            selector.selectionChanged()
            selector.prepare()              // warm for the next frame's detent tick
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
