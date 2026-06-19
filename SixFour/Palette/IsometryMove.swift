import Foundation
import simd

/// The EXACT delta-preserving move on Q16 OKLab — the Swift port of `SixFour.Spec.IsometryMove`.
///
/// A lattice isometry = per-axis sign-flips (each ±1 on L,a,b) + an integer Q16 translation. These
/// are the ONLY moves that preserve every pairwise OKLab distance with NO tolerance (the translation
/// cancels in any difference; sign² = 1). So applying ONE move to a whole palette shifts every colour
/// coherently — the relative deltas WITHIN a frame cannot change at all, and applied identically to
/// all 64 frames, neither can the deltas BETWEEN frames. Pure integer negate+add per channel ⇒
/// SIMD-native. Verified bit-for-bit against the Haskell laws in `IsometryMoveTests`.
struct IsoMove: Equatable {
    /// Per-axis ±1 sign-flip on (L, a, b).
    var signs: SIMD3<Int32>
    /// Q16 translation added after the flip.
    var shift: SIMD3<Int32>

    static let identity = IsoMove(signs: SIMD3(1, 1, 1), shift: .zero)
    /// σ = (L, −a, −b) — the canonical reflection (`PairTree.lawSigmaEuclideanIsometry`).
    static let sigma = IsoMove(signs: SIMD3(1, -1, -1), shift: .zero)
    /// A pure translation — the continuous A/B knob.
    static func translate(_ t: SIMD3<Int32>) -> IsoMove { IsoMove(signs: SIMD3(1, 1, 1), shift: t) }

    /// Apply the move to one colour: flip each axis, then add the translation.
    func apply(_ c: SIMD3<Int32>) -> SIMD3<Int32> { signs &* c &+ shift }

    /// The inverse move (`apply(invert.apply(c)) == c`): re-use the signs, translate by −(s·t).
    var inverse: IsoMove { IsoMove(signs: signs, shift: SIMD3<Int32>.zero &- (signs &* shift)) }

    /// Squared Q16 distance (Int, to avoid Int32 overflow on the ~1.3e5 max difference).
    static func distSq(_ a: SIMD3<Int32>, _ b: SIMD3<Int32>) -> Int {
        let dx = Int(a.x) - Int(b.x), dy = Int(a.y) - Int(b.y), dz = Int(a.z) - Int(b.z)
        return dx * dx + dy * dy + dz * dz
    }
}

/// The Swift port of `SixFour.Spec.MoveRadiusSchedule` — anneal the move magnitude (wide early →
/// JND floor) + a hard cumulative-displacement cap, all exact Q16. The "visible reload without drift"
/// schedule: early rounds move a visible amount, late rounds a JND, the look never drifts past ±0.25
/// OKLab from the capture. Verified against the Haskell laws in `IsometryMoveTests`.
enum MoveRadiusSchedule {
    static let radiusMax: Int32 = 8192   // ≈ 0.125 OKLab — cold-start (A/B visibly different)
    static let radiusMin: Int32 = 1024   // ≈ 0.0156 (one JND) — every round still moves
    static let halfLife: Int32 = 8       // picks to halve the excess radius
    static let cumCap: Int32 = 16384     // ≈ 0.25 — hard per-axis cap on cumulative drift

    /// Per-round move radius (Q16): `rMin + (rMax−rMin)·halfLife / (n+halfLife)`. Integer division
    /// ⇒ exact + deterministic. `rMax` at n=0, monotone ↓ to `rMin`.
    static func radius(_ n: Int) -> Int32 {
        let nn = Int32(max(0, n))
        return radiusMin + ((radiusMax - radiusMin) * halfLife) / (nn + halfLife)
    }

    /// Project a cumulative displacement into the L∞ ball of radius `cumCap` — the chosen look can
    /// never drift more than `cumCap` from the original capture, however many rounds accrue.
    static func clampToCap(_ t: SIMD3<Int32>) -> SIMD3<Int32> {
        SIMD3(min(cumCap, max(-cumCap, t.x)),
              min(cumCap, max(-cumCap, t.y)),
              min(cumCap, max(-cumCap, t.z)))
    }
}
