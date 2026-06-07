import Testing
import Foundation
import simd
@testable import SixFour

/// Gates the Swift move-operator mirror (`MoveContract`, generated from
/// `SixFour.Spec.MovableLayout`) + the AppSettings persistence round-trip. The laws
/// mirror `spec/test/Properties/MovableLayout.hs`; the persistence tests pin the
/// versioned-key / injectable-suite / corrupt-store contract.
@MainActor
struct MovableLayoutTests {

    private func eq(_ a: [ColorIdentity: (col: Int, row: Int)],
                    _ b: [ColorIdentity: (col: Int, row: Int)]) -> Bool {
        ColorIdentity.allCases.allSatisfy { a[$0]?.col == b[$0]?.col && a[$0]?.row == b[$0]?.row }
    }

    // MARK: - Move-operator laws (mirror Spec.MovableLayout)

    /// `selfCheck()` re-asserts the seed laws + the golden fold at runtime.
    @Test func contractSelfCheck() {
        #expect(MoveContract.selfCheck())
    }

    /// lawDefaultsDisjoint — the shipped seed placement is disjoint + in-bounds.
    @Test func defaultsDisjointInBounds() {
        let scene = MoveContract.placementScene(MoveContract.defaultPlacement)
        #expect(GridLayoutContract.isDisjoint(scene))
        #expect(scene.allSatisfy {
            $0.col >= 0 && $0.col + $0.w <= MoveContract.cols
                && $0.row >= 0 && $0.row + $0.h <= MoveContract.rows
        })
    }

    /// goldenMoveTrace — folding the generated `move` over `goldenScript` reproduces
    /// `goldenAfter` (cross-language bit-pin, the same fold `Surface.assertSpecParity` runs).
    @Test func goldenMoveTrace() {
        var p = MoveContract.defaultPlacement
        for step in MoveContract.goldenScript {
            p = MoveContract.move(p, step.id, dCol: step.dCol, dRow: step.dRow)
        }
        #expect(eq(p, MoveContract.goldenAfter))
    }

    /// lawSnapIdempotent — snapToAtom is idempotent on its own output.
    @Test func snapIdempotent() {
        let atom = SixFourLattice.gifPx
        for px in stride(from: -40, through: 40, by: 1) {
            let once = MoveContract.snapToAtom(px, atom: atom)
            #expect(MoveContract.snapToAtom(once, atom: atom) == once)
            #expect(once % atom == 0)   // lawMoveAtomAligned (snap lands on an atom)
        }
    }

    /// lawMovePreservesDisjoint + lawMoveInBounds — over a fuzz of deltas, every move
    /// result stays disjoint AND fully in-bounds (accept keeps it by the guard; reject
    /// returns the already-valid input).
    @Test func movePreservesDisjointAndBounds() {
        var s: UInt64 = 0xC0105EED
        func rnd(_ lo: Int, _ hi: Int) -> Int {
            s = s &* 6364136223846793005 &+ 1
            return lo + Int(s >> 40) % (hi - lo + 1)
        }
        for _ in 0 ..< 2000 {
            let i = ColorIdentity.allCases[rnd(0, ColorIdentity.allCases.count - 1)]
            let p = MoveContract.move(MoveContract.defaultPlacement, i,
                                      dCol: rnd(-120, 120), dRow: rnd(-240, 240))
            let scene = MoveContract.placementScene(p)
            #expect(GridLayoutContract.isDisjoint(scene))
            #expect(scene.allSatisfy {
                $0.col >= 0 && $0.col + $0.w <= MoveContract.cols
                    && $0.row >= 0 && $0.row + $0.h <= MoveContract.rows
            })
        }
    }

    /// lawRejectIsIdentity — driving Palette16 onto Field64 (the witness delta) returns
    /// the literal prior placement (exact snap-back, no partial move).
    @Test func rejectIsIdentity() {
        let before = MoveContract.defaultPlacement
        let after = MoveContract.move(before, .palette16, dCol: -24, dRow: -123)
        #expect(eq(after, before))
    }

    /// lawMoveOnlyTouchesTarget — a move never perturbs the other two identities.
    @Test func moveOnlyTouchesTarget() {
        let before = MoveContract.defaultPlacement
        let after = MoveContract.move(before, .field64, dCol: 18, dRow: 0)   // accepts (clamps to 36)
        for i in ColorIdentity.allCases where i != .field64 {
            #expect(after[i]?.col == before[i]?.col && after[i]?.row == before[i]?.row)
        }
        // And Field64 itself moved (clamped to cols-64 = 36).
        #expect(after[.field64]?.col == 36)
    }

    // MARK: - AppSettings persistence (injectable suite preserved)

    private func freshSuite() -> UserDefaults {
        let name = "movable.test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    /// Defaults come from the generated contract (no hand-typed literals).
    @Test func defaultsAreSpecDocks() {
        let s = AppSettings(defaults: freshSuite())
        #expect(s.field64Position == AppSettings.GridPoint(col: MoveContract.defaultCol(.field64),
                                                           row: MoveContract.defaultRow(.field64)))
        #expect(s.palette16Position == AppSettings.GridPoint(col: MoveContract.defaultCol(.palette16),
                                                             row: MoveContract.defaultRow(.palette16)))
        #expect(s.diversityRingPosition == AppSettings.GridPoint(col: MoveContract.defaultCol(.diversityRing),
                                                                 row: MoveContract.defaultRow(.diversityRing)))
    }

    /// Round-trip: a set position survives a relaunch (new AppSettings over the same suite).
    @Test func positionRoundTrips() {
        let suite = freshSuite()
        do {
            let s = AppSettings(defaults: suite)
            // Move Field64 to a valid in-bounds, disjoint spot.
            s.widgetPlacement = MoveContract.move(s.widgetPlacement, .field64, dCol: 10, dRow: 0)
        }
        let reloaded = AppSettings(defaults: suite)
        #expect(reloaded.field64Position.col == MoveContract.defaultCol(.field64) + 10)
        #expect(reloaded.field64Position.row == MoveContract.defaultRow(.field64))
    }

    /// Corrupt/overlapping persisted positions are rejected on load → defaultPlacement.
    @Test func corruptOverlappingStoreFallsBack() {
        let suite = freshSuite()
        // Force all three onto the same cell — an overlapping (invalid) scene.
        suite.set("0,0", forKey: "sixfour.field64Position.v1")
        suite.set("0,0", forKey: "sixfour.palette16Position.v1")
        suite.set("0,0", forKey: "sixfour.diversityRingPosition.v1")
        let s = AppSettings(defaults: suite)
        // Loaded scene must be the proven default (disjoint), NOT the corrupt overlap.
        #expect(s.field64Position == AppSettings.GridPoint(col: MoveContract.defaultCol(.field64),
                                                           row: MoveContract.defaultRow(.field64)))
        let scene = MoveContract.placementScene(s.widgetPlacement)
        #expect(GridLayoutContract.isDisjoint(scene))
    }

    /// Garbage strings parse to the spec default (existing fallback discipline).
    @Test func garbageStringFallsBack() {
        let suite = freshSuite()
        suite.set("not-a-point", forKey: "sixfour.field64Position.v1")
        let s = AppSettings(defaults: suite)
        #expect(s.field64Position == AppSettings.GridPoint(col: MoveContract.defaultCol(.field64),
                                                           row: MoveContract.defaultRow(.field64)))
    }
}
