module Properties.Display (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Data.List (sort)

import SixFour.Spec.Display
import SixFour.Spec.PairTreeFixed (OKLabI)
import SixFour.Spec.ColorFixed    (q16One)
import SixFour.Spec.CellGrid      (Place(..), Grid, section, gridJoinAll, placesH, placesW)
import SixFour.Spec.CellFiber     (Color(..))

-- | A Q16 OKLab leaf (mirrors the in-gamut ranges used elsewhere).
genOKLabI :: Gen OKLabI
genOKLabI = (,,)
  <$> choose (0, q16One)
  <*> choose (negate (q16One `div` 2), q16One `div` 2)
  <*> choose (negate (q16One `div` 2), q16One `div` 2)

-- | A power-of-two (256-leaf) palette so the Haar projections are exactly invertible.
genPalette :: Gen [OKLabI]
genPalette = vectorOf 256 genOKLabI

-- | Indices are in-gauge (@[0..255]@) so gather/relabel are well-defined.
genIndices :: Gen [Int]
genIndices = do
  n <- choose (0, 24 :: Int)
  vectorOf n (choose (0, 255))

genState :: Gen DisplayState
genState = DisplayState <$> genPalette <*> genIndices <*> choose (0, frameCount - 1)

genInput :: Gen Input
genInput = do
  n <- choose (0, 8 :: Int)
  Input <$> vectorOf n genOKLabI

-- | A permutation of @[0..255]@ — the @S_K@ gauge element for T6.
genPerm256 :: Gen [Int]
genPerm256 = shuffle [0 .. 255]

-- | A random FSM event (for the goldenPhaseTrace scanl property).
genEvent :: Gen Event
genEvent = elements allEvents

-- | A small Grid for the T9 citation (built via the public claim API, like
-- Properties.CellGrid).
genColor :: Gen Color
genColor = do
  l <- choose (0, q16One)
  a <- choose (negate (q16One `div` 2), q16One `div` 2)
  b <- choose (negate (q16One `div` 2), q16One `div` 2)
  pure (Color (l, a, b))

genGrid :: Gen Grid
genGrid = do
  n <- choose (0, 6 :: Int)
  cl <- vectorOf n ((,) <$> (Place <$> choose (0, placesH - 1) <*> choose (0, placesW - 1))
                        <*> genColor)
  pure (gridJoinAll [ section p c | (p, c) <- cl ])

tests :: TestTree
tests = testGroup "Display (the FSM M = (Σ, ι, δ, λ, Π, κ) — T1..T9 + composition)"
  [ -- T1 — the clock divides 60 and 120; holds are whole numbers {3,6}
    testProperty "T1 lawClockDivides (60%20=0, 120%20=0; holds=[3,6])" $
      once lawClockDivides

    -- T2 — exactly one clock κ
  , testProperty "T2 lawOneClock (single 20 Hz CADisplayLink)" $
      once lawOneClock

    -- T3 — the three grids cannot drift: shutter = level-4 coarsening of the SAME P,
    -- Haar exactly invertible (reuse PairTreeFixed round-trip)
  , testProperty "T3 lawProjectionsShareState (shutter = coarsen(P); reconstruct∘analyze=id)" $
      forAllBlind genState lawProjectionsShareState

    -- T4 — every view's pitch is atom × b_i (no free cellPt)
  , testProperty "T4 lawUniformAtom (pitch = gifPx × blockFactor; extent on lattice)" $
      once lawUniformAtom

    -- T5 — δ_capture writes every cell each tick (touched == fullLattice)
  , testProperty "T5 lawDeltaTotal (touched == fullLattice; total over 4096 places)" $
      forAllBlind genState $ \s -> forAll genInput (lawDeltaTotal s)

    -- T6 — gauge invariance: relabel by any σ ∈ S_K leaves the observation unchanged
  , testProperty "T6 lawGaugeInvariant (∀ σ ∈ S_256. λ(σ·Σ) == λ(Σ))" $
      forAllBlind genState $ \s -> forAll genPerm256 $ \sigma -> lawGaugeInvariant sigma s

    -- T7 — capture phase-lock: 20 Hz, N=64 ticks ↔ 64 frames (bijection)
  , testProperty "T7 lawCapturePhase (captureRate==20; 64 ticks ↔ 64 frames)" $
      once lawCapturePhase

    -- T8 — Moore observability: λ has no Input argument (by construction)
  , testProperty "T8 lawMoore (λ :: DisplayState -> [Pixel], no Input)" $
      once lawMoore

    -- T9 — gridJoin totality (spatial sibling of T5; reuse CellGrid)
  , testProperty "T9 lawGridJoinTotal (inherited totality over the 4096-place base)" $
      forAllBlind genGrid lawGridJoinTotal

    -- The composition theorem: all three Π are observers of the one Σ
  , testProperty "composition: equal Σ ⇒ equal projGif/projPalette/projShutter" $
      forAllBlind genState $ \s -> forAllBlind genState (lawComposition s)

    -- golden tick-trace: one Σ' per (Σ, ι); cursor advanced each step
  , testProperty "goldenTickTrace: |trace| == |inputs|, cursor advanced by δ_review" $
      forAllBlind genState $ \s -> forAll genInput $ \i ->
        let trace = goldenTickTrace [(s, i)]
        in length trace == 1
           && dsCursor (head trace) == (dsCursor s + 1) `mod` frameCount

    -- ===== The phase FSM (one surface, no screens) =====

    -- PHASE-T1 — step is total over every (phase, event)
  , testProperty "PHASE-T1 lawPhaseTotal (step total ∀ phase×event)" $
      once lawPhaseTotal

    -- PHASE-T2 — every phase reachable from Bootstrap (no dead UI)
  , testProperty "PHASE-T2 lawNoOrphanPhase (every phase reachable from Bootstrap)" $
      once lawNoOrphanPhase

    -- PHASE-T3 — the cell-field law: every phase IS a full cell-field config (no screens)
  , testProperty "PHASE-T3 lawPhaseIsCellGrid (|phaseField p| == |allPlaces| ∀ phase)" $
      forAllBlind genState lawPhaseIsCellGrid

    -- PHASE-T4 — Review is entered ONLY via Committed
  , testProperty "PHASE-T4 lawReviewExplicit (Review ⟸ only Committed)" $
      once lawReviewExplicit

    -- golden phase-trace: scanl step Bootstrap reproduces the FSM
  , testProperty "goldenPhaseTrace: |trace| == |events|+1; starts at Bootstrap" $
      forAll (listOf genEvent) $ \evs ->
        let tr = goldenPhaseTrace evs
        in length tr == length evs + 1 && head tr == Bootstrap
  ]
