module Properties.Significance (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import qualified Data.Vector as V
import           Data.Maybe  (fromJust, isJust)
import           Data.Proxy  (Proxy(..))

import SixFour.Spec.Color        (OKLab(..))
import SixFour.Spec.Gauge        (Permutation, mkPermutation)
import SixFour.Spec.Significance

-- Tiny, *boundary-tight* shape: K = 4 slots, P = H*W = 8 pixels, so
-- P = minPopulation * K exactly (2 * 4 = 8). This is the hardest feasible
-- case — every slot must get exactly minPopulation pixels — so passing here
-- pins the "cannot fail" guarantee at the boundary. T = 2 frames.
type T = 2
type H = 2
type W = 4
type K = 4

perFrame :: Int
perFrame = 8

kVal :: Int
kVal = 4

-- | OKLab in the working range.
genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

-- | A frame of 'perFrame' pixels with arbitrary colours (rich regime likely).
genFrame :: Gen [OKLab]
genFrame = vectorOf perFrame genOKLab

-- | A *colour-poor* frame: 'perFrame' pixels drawn from only 1–2 distinct
-- colours (the regime where naive surjectivity rescue would have donated
-- outliers). Significance must STILL hold: 4 slots × 2 identical-colour
-- pixels each, every count ≥ minPopulation.
genPoorFrame :: Gen [OKLab]
genPoorFrame = do
  nDistinct <- choose (1, 2)
  palette   <- vectorOf nDistinct genOKLab
  vectorOf perFrame (elements palette)

genPerm :: Gen (Permutation K)
genPerm = fromJust . mkPermutation @K <$> shuffle [0 .. kVal - 1]

-- | A frame cell set straight from the producer.
frameCellsOf :: [OKLab] -> FrameCells K
frameCellsOf pixels = FrameCells (V.fromList (fst (splitFillFrame kVal pixels)))

tests :: TestTree
tests = testGroup "Significance (per-frame palette, MATH.md §10)"
  [ -- Def 21
    testProperty "Def 21: every cell's range box contains its centroid" $
      forAll genFrame $ \px ->
        all lawSigRangeWellFormed (V.toList (unFrameCells (frameCellsOf px)))

    -- Def 22
  , testProperty "Def 22: cells partition all P pixels (Σ count = P)" $
      forAll genFrame $ \px ->
        lawSigMassConservation perFrame (frameCellsOf px)

    -- Def 23 — the headline guarantee, on rich frames …
  , testProperty "Def 23: every slot is significant (count ≥ n_min) — rich frame" $
      forAll genFrame $ \px ->
        lawSigAllSignificant (frameCellsOf px)

    -- … and on colour-poor frames, where donation used to inject outliers.
  , testProperty "Def 23: all slots significant even on a 1–2 colour frame" $
      forAll genPoorFrame $ \px ->
        lawSigAllSignificant (frameCellsOf px)

    -- The flat-scene fixture: 8 identical pixels, 4 slots. Must still be all
    -- significant (2 each) — never a count-1 outlier.
  , testProperty "Def 23: a fully flat frame yields 4 significant slots, none degenerate" $
      once $
        let flat  = replicate perFrame (OKLab 0.5 0.1 (-0.2))
            cells = V.toList (unFrameCells (frameCellsOf flat))
        in length cells == kVal
           && all isSignificant cells
           && all ((/= Degenerate) . cProv) cells
           && sum (map cCount cells) == perFrame

    -- significanceFeasible matches the shape arithmetic.
  , testProperty "shape feasibility: P = n_min·K is feasible; one fewer slot of pixels is not" $
      once $
        significanceFeasible perFrame kVal
          && not (significanceFeasible (perFrame - 1) kVal)

    -- Thm 7 — significance is population; the donated-outlier signature is rejected.
  , testProperty "Thm 7: significance ⇔ population ≥ n_min" $
      forAll (choose (0, 20)) $ \n ->
        lawSigSignificanceIsPopulation (Cell (OKLab 0.5 0 0) zeroSigma n Extracted)
  , testProperty "Thm 7: a count-1 donated slot is NOT significant" $
      once $
        not (isSignificant (Cell (OKLab 0.5 0 0) zeroSigma 1 Degenerate))

    -- Thm 6 — χ² distinctness.
  , testProperty "Thm 6: a centroid at the pooled mean is not admitted (Mahalanobis = 0)" $
      forAll genOKLab $ \mu ->
        lawSigAdmissionAtMeanRejected mu (Sigma6 0.01 0 0 0.01 0 0.01) 0.05
  , testProperty "Thm 6: a far centroid IS admitted (Mahalanobis > χ²₃ critical)" $
      once $
        mahalanobisSquared (OKLab 1 0 0) (OKLab 0 0 0) (Sigma6 0.01 0 0 0.01 0 0.01)
          > chiSquare3Critical 0.05

    -- Thm 9 — S_K gauge invariance.
  , testProperty "Thm 9: permuting palette slots preserves the significance verdict & coverage" $
      forAll ((,) <$> genFrame <*> genPerm) $ \(px, sigma) ->
        lawSigGaugeInvariant sigma (frameCellsOf px)

    -- Def 24 — maximin variety floor …
  , testProperty "Def 24: significant palette occupies ≥ 1 gamut bin" $
      forAll genFrame $ \px ->
        lawSigMaximinVariety (Proxy :: Proxy K) px

    -- … and full spread on well-separated input (4 corners → 4 occupied bins).
  , testProperty "Def 24: well-separated colours give full coverage (= K bins)" $
      once $
        let corners = [ OKLab 0.05 (-0.3) (-0.3), OKLab 0.95 0.3 (-0.3)
                      , OKLab 0.5 (-0.3) 0.3,     OKLab 0.5 0.3 0.3 ]
            px = concatMap (replicate 2) corners            -- 8 pixels, 4 colours ×2
            cells = fst (splitFillFrame kVal px)
        in length cells == kVal && all isSignificant cells

    -- Producer totality / brand construction on the SixFour-style shape.
  , testProperty "buildSignificantVolume returns a brand for every well-shaped burst" $
      forAll (vectorOf 2 genFrame) $ \frs ->
        isJust (buildSignificantVolume @T @H @W @K
                  (V.fromList (map V.fromList frs)))

    -- The brand cannot be forged from an under-populated (donated) frame:
    -- a frame whose cells include a count-1 slot must be rejected.
  , testProperty "brand rejects a frame containing a count-1 (outlier) slot" $
      once $
        let goodFrame   = frameCellsOf (replicate perFrame (OKLab 0.4 0 0))
            -- forge a frame: 3 fat slots + 1 starved (count 1) slot, mass = 8
            forged = FrameCells (V.fromList
                       [ Cell (OKLab 0.4 0 0) zeroSigma 3 Extracted
                       , Cell (OKLab 0.4 0 0) zeroSigma 2 Extracted
                       , Cell (OKLab 0.4 0 0) zeroSigma 2 Extracted
                       , Cell (OKLab 0.4 0 0) zeroSigma 1 Degenerate ])
        in lawSigAllSignificant goodFrame
           && not (lawSigAllSignificant forged)
  ]
