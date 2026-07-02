import Foundation
import GameKit
import UIKit

// The swap economy's identity binding: SixFour.Spec.Trade.CreatorId ↔ Game Center player.
//
// `CreatorID` is the stable, opaque token the economy records key on (publisher of a Gene, adopter in
// an Adoption). Its SOURCE is the authenticated local player's `gamePlayerID` — per-team-scoped and
// opaque (NEVER the Apple ID), which is exactly the "who" the public records need without leaking a
// real identity. The pure `CreatorID` mapping is unit-tested headlessly; `GameCenterIdentity` (which
// authenticates) is device-only — it presents sign-in UI and needs a signed-in (sandbox) account, so
// it is NOT exercised by the headless tests. Requires the `com.apple.developer.game-center` entitlement.

/// A stable creator identity for the swap economy. Wraps the Game Center `gamePlayerID` so economy
/// code depends on a type, not a raw string, and the source can evolve without touching call sites.
struct CreatorID: Hashable, Codable, Sendable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
}

extension CreatorID {
    /// The identity of an AUTHENTICATED Game Center player, or nil if not authenticated. `gamePlayerID`
    /// is stable and opaque — the correct per-player key for our public records.
    init?(player: GKLocalPlayer) {
        guard player.isAuthenticated else { return nil }
        self.init(rawValue: player.gamePlayerID)
    }
}

/// Production identity source: the authenticated Game Center local player. DEVICE-ONLY — authentication
/// presents UI and needs a signed-in account, so it is guarded here and not headlessly tested; the
/// pure `CreatorID(player:)` mapping is. The economy layer depends on the resolved `CreatorID`, not on
/// this class, so tests inject a fixed id.
@MainActor
final class GameCenterIdentity {
    /// The resolved identity once authentication has settled, else nil.
    private(set) var creator: CreatorID?

    /// Authenticate the local player. `present` is called with Game Center's sign-in view controller
    /// when user interaction is required (the app hosts it); the identity resolves once authentication
    /// settles. Idempotent — a resolved identity is cached and returned directly.
    func authenticate(present: @escaping @MainActor (UIViewController) -> Void) async -> CreatorID? {
        if let creator { return creator }
        let resolved: CreatorID? = await withCheckedContinuation { continuation in
            var resumed = false
            func finish(_ id: CreatorID?) {
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: id)
            }
            GKLocalPlayer.local.authenticateHandler = { viewController, _ in
                if let viewController {
                    present(viewController)            // user must sign in; await the next callback
                    return
                }
                finish(CreatorID(player: GKLocalPlayer.local))
            }
        }
        creator = resolved
        return resolved
    }
}
