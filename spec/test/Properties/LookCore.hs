module Properties.LookCore (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import SixFour.Spec.Color    (OKLab(..))
import SixFour.Spec.PairTree (HaarPalette(..), reconstruct)
import SixFour.Spec.LookCore

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

-- A well-formed Haar palette of random depth (level i has 2^i offsets).
genHaar :: Gen HaarPalette
genHaar = do
  d   <- choose (0, 5 :: Int)
  rt  <- genOKLab
  lvs <- mapM (\i -> vectorOf (2 ^ i) genOKLab) [0 .. d - 1]
  pure (HaarPalette rt lvs)

-- A residual shaped like a given palette (same depth + level sizes), arbitrary values.
genResidualLike :: HaarPalette -> Gen HaarPalette
genResidualLike (HaarPalette _ lvls) = do
  rt  <- genResid
  lvs <- mapM (\lvl -> vectorOf (length lvl) genResid) lvls
  pure (HaarPalette rt lvs)
  where genResid = OKLab <$> choose (-5, 5) <*> choose (-5, 5) <*> choose (-5, 5)

tests :: TestTree
tests = testGroup "LookCore (Bures/k-means floor + bounded look residual — Path B)"
  [ -- Neutral identity: the no-look (zero) residual returns the floor exactly.
    testProperty "neutral residual ⇒ output is the floor (reset works)" $
      forAll genHaar lawNeutralIsFloor

  , -- Boundedness for ANY residual: each leaf moves ≤ (depth+1)·s off the floor.
    testProperty "bounded: every leaf moves ≤ (depth+1)·s for any residual" $
      forAll genHaar $ \floor' ->
        forAll (genResidualLike floor') $ \res ->
          lawBoundedLeaves 1e-9 floor' res

  , -- σ-equivariance is exact (tanh is odd) — the complement symmetry needs no loss term.
    testProperty "σ-equivariant: apply ∘ σ = σ ∘ apply, for any residual" $
      forAll genHaar $ \floor' ->
        forAll (genResidualLike floor') $ \res ->
          lawSigmaEquivariant 1e-9 floor' res

  , -- The bound is the stated (depth+1)·s.
    testProperty "leaf-displacement bound = (depth+1)·s" $
      forAll genHaar $ \floor' ->
        let d = length (levels floor')
        in abs (leafDisplacementBound lookCoreScale floor'
                - fromIntegral (d + 1) * lookCoreScale) < 1e-12

  , -- A maxed-out residual (all coords large ⇒ tanh ≈ ±1) actually approaches the
    -- bound on a deep tree — the bound is tight, not loose.
    testProperty "the bound is tight: a saturated residual nears (depth+1)·s" $
      once $
        let d = 4 :: Int
            floor' = HaarPalette (OKLab 0.5 0 0) [ replicate (2 ^ i) (OKLab 0 0 0) | i <- [0 .. d - 1] ]
            -- residual saturating the L channel positive at every node
            res = HaarPalette (OKLab 50 0 0) [ replicate (2 ^ i) (OKLab 50 0 0) | i <- [0 .. d - 1] ]
            leavesL = [ l | OKLab l _ _ <- reconstruct (applyLookCore lookCoreScale floor' res) ]
        in maximum leavesL > fromIntegral (d + 1) * lookCoreScale - 1e-3
  ]
