import Testing
@testable import SixFour

/// Gates for the decision surface (`DecideSurface` over
/// `GridLayoutContract.decisionScene` — rebuilt around the TWO VERBS, THE DESIGN D3).
@MainActor
struct DecideSurfaceTests {

    /// Every widget the surface composes resolves in the PROVEN scene, and the
    /// runtime self-check (spanning all scenes) holds.
    @Test func decisionSceneResolvesEveryWidget() {
        let scene = GridLayoutContract.decisionScene
        for name in ["hero", "coarse", "tally", "signal", "pour",
                     "fold", "advanced", "again", "accept"] {
            #expect(GridLayoutContract.region(name, in: scene) != nil, "missing \(name)")
        }
        #expect(scene.count == 9)   // THE MERGE added signal + pour (fab48df)
        #expect(GridLayoutContract.isDisjoint(scene))
        #expect(GridLayoutContract.selfCheck())
    }

    /// D3: the two verbs are the clearest controls in the app — 44×16 cells each
    /// (4× the 11-cell touch floor in width), and every interactive region of the
    /// rebuilt scene declares a control face (the lawControlFaceTotal mirror the
    /// lint also polices). The coarse/tally judgment aids are display-only.
    @Test func verbsAndFacesFollowTheDesign() throws {
        let scene = GridLayoutContract.decisionScene
        for name in ["again", "accept"] {
            let r = try #require(GridLayoutContract.region(name, in: scene))
            #expect(r.w == 44 && r.h == 16, "\(name) is not the 44×16 verb face")
            #expect(r.interactive)
        }
        for r in scene where r.interactive {
            #expect(SixFourCellMechanics.controlFaces[r.name] != nil,
                    "interactive \(r.name) has no control face")
        }
        #expect(SixFourCellMechanics.controlFaces["hero"] == "brackets")
        #expect(SixFourCellMechanics.controlFaces["fold"] == "frame")
        for name in ["coarse", "tally"] {
            let r = try #require(GridLayoutContract.region(name, in: scene))
            #expect(!r.interactive, "\(name) must be display-only")
        }
    }

    /// The paint knob reaches the model boundary: painting one control cell on a
    /// channel shows up in `SixFourModelInput.nudge` at the Morton cell, and the
    /// gauge toggle rides `miGauge`. Zero paint stays the neutral floor.
    @Test func decideModelAssemblesTheModelInput() {
        let model = DecideModel(tiles: [], gene: nil)
        #expect(model.modelInput().nudge == SixFourModelIO.neutralNudge())

        model.paint.paint(x: 3, y: 5, z: 0, channel: 8, value: 32)
        model.paint.gauge = true
        let input = model.modelInput()
        let cell = NudgePaintModel.mortonIndex(x: 3, y: 5, z: 0)
        #expect(input.nudge[cell][8] == 32)
        #expect(input.gauge)
        #expect(input.nudge.enumerated().allSatisfy { i, row in
            i == cell || row.allSatisfy { $0 == 0 }
        })
    }

    /// The gene knob defaults honestly: no somatic gene ⇒ the floor (and the
    /// toggle is pinned there); a trained gene ⇒ ride it.
    @Test func geneToggleDefaultsToPresence() {
        #expect(DecideModel(tiles: [], gene: nil).useGene == false)
        let gene = CaptureGene.ThetaUp(theta: [Float](repeating: 0, count: 21),
                                       committed: [Int](repeating: 0, count: 7),
                                       loss: 0, floorLoss: 0, trainMillis: 0,
                                       channel: 0, frames: 64, side: 64)
        #expect(DecideModel(tiles: [], gene: gene).useGene == true)
    }

    /// One time axis drives both widgets: the scrubbed burst frame derives the
    /// 16³ paint layer as t/4 (64 frames → 16 layers), clamped at the ends.
    @Test func scrubDerivesThePaintLayer() {
        let tiles = (0 ..< 64).map { f in
            OKLabTile(side: 2, pixels: Array(repeating: SIMD3<Float>(0, 0, 0), count: 4),
                      captureNanos: UInt64(f), palette: [], finalShift: 0)
        }
        let model = DecideModel(tiles: tiles, gene: nil)
        model.frame = 0;  #expect(model.paintLayer == 0)
        model.frame = 7;  #expect(model.paintLayer == 1)
        model.frame = 32; #expect(model.paintLayer == 8)
        model.frame = 63; #expect(model.paintLayer == 15)
    }
}
