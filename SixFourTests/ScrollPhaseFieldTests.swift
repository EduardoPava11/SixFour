import Testing
@testable import SixFour

/// Gates for THE SCROLL surface (`ScrollPhaseField` over
/// `GridLayoutContract.scrollScene`) and the BOOT RESOLVE reveal ladder at the
/// UI seam — the Swift mirror of the `Spec.GridLayout` / `Spec.WangTiling`
/// theorems this phase composes.
@MainActor
struct ScrollPhaseFieldTests {

    /// Every widget the surface composes resolves in the PROVEN scene, the
    /// runtime self-check (now spanning scrollScene too) holds, and the hero
    /// rides EXACTLY the liveScene field64 band — entering/leaving the tube
    /// never moves the eye.
    @Test func scrollSceneResolvesEveryWidget() throws {
        let scene = GridLayoutContract.scrollScene
        for name in ["hero", "pour", "rail", "exit", "reseed"] {
            #expect(GridLayoutContract.region(name, in: scene) != nil, "missing \(name)")
        }
        #expect(scene.count == 5)
        #expect(GridLayoutContract.isDisjoint(scene))
        #expect(GridLayoutContract.selfCheck())

        let hero = try #require(GridLayoutContract.region("hero", in: scene))
        let band = try #require(GridLayoutContract.region("field64",
                                                          in: GridLayoutContract.liveScene))
        #expect((hero.col, hero.row, hero.w, hero.h) == (band.col, band.row, band.w, band.h))
    }

    /// Interactive region ⇒ declared control face (the lawControlFaceTotal
    /// mirror): the image hero wears BRACKETS, the two verbs wear FRAME, and the
    /// pour/rail instruments are display-only.
    @Test func facesFollowTheControlLanguage() throws {
        let scene = GridLayoutContract.scrollScene
        for r in scene where r.interactive {
            #expect(SixFourCellMechanics.controlFaces[r.name] != nil,
                    "interactive \(r.name) has no control face")
        }
        #expect(SixFourCellMechanics.controlFaces["hero"] == "brackets")
        #expect(SixFourCellMechanics.controlFaces["exit"] == "frame")
        #expect(SixFourCellMechanics.controlFaces["reseed"] == "frame")
        for name in ["pour", "rail"] {
            let r = try #require(GridLayoutContract.region(name, in: scene))
            #expect(!r.interactive, "\(name) must be display-only")
        }
    }

    /// BOOT RESOLVE: the reveal ladder the Live pyramid crystallizes on (and the
    /// scroll's refine-on-linger reuses) is the spec's 4/8/16 — coarse first, the
    /// pour played in reverse, nothing revealed at tick 0, everything by 16, and
    /// the √N reciprocity `revealTick p · unitsOf p = 16` pinned.
    @Test func revealLadderIsThePourInverse() {
        #expect(S4WangTiling.revealTick(.r16) == 4)
        #expect(S4WangTiling.revealTick(.r32) == 8)
        #expect(S4WangTiling.revealTick(.r64) == 16)
        #expect(S4WangTiling.revealAt(0).isEmpty)
        #expect(S4WangTiling.revealAt(4) == [.r16])
        #expect(S4WangTiling.revealAt(8) == [.r16, .r32])
        #expect(S4WangTiling.revealAt(16) == [.r16, .r32, .r64])
        for p in S4WangTiling.TubeRung.allCases {
            #expect(S4WangTiling.revealTick(p) * p.unitsOf == 16)
        }
    }

    /// The tube model is deterministic at its seams: the pinned default seed, the
    /// RESEED mixer (the same pinned SplitMix64 slice derivation), and the pour
    /// group loop (frame = tallySlot(4, tick) — one viewport loop = 4 ticks).
    @Test func tubeModelSeamsArePinned() {
        #expect(ScrollTubeModel.defaultTubeSeed == 0x5448_4554_5542_4531)
        let mixed = TubeSynth.sliceSeed(tubeSeed: ScrollTubeModel.defaultTubeSeed, slice: 1)
        #expect(mixed != ScrollTubeModel.defaultTubeSeed)
        // The 20 Hz loop covers the whole pour group, in order, every 4 ticks.
        #expect((0 ..< 8).map { ColorTimeDisplayMath.tallySlot(slots: 4, tick: $0) }
                == [0, 1, 2, 3, 0, 1, 2, 3])
    }

    /// The loader's PRE-GENERATION staleness probe: a request whose `wanted`
    /// check says no is skipped before the materialization cost is paid (nil,
    /// no generation), while a wanted request materializes the full pour group
    /// — so a fling's stale intermediate slices cost one probe each and the
    /// landing slice never waits behind their generations.
    @Test func loaderSkipsStaleRequestsPreGeneration() async {
        let loader = TubeLoader()
        let skipped = await loader.frames(tubeSeed: 1, gene: [], slice: 0) { false }
        #expect(skipped == nil)
        let made = await loader.frames(tubeSeed: 1, gene: [], slice: 0) { true }
        #expect(made?.count == TubeSynth.framesPerSlice)
    }
}
