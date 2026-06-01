{- |
Module      : Properties.PaletteSearch
Description : Property tests for the keystone 'SixFour.Spec.PaletteSearch'.

Exercises the EXPORTED laws of the MCTS-over-global-palette search against the
deterministic 'stubOracle' and generated well-formed Haar palettes. (Imports the
module under test; does not re-implement it.)
-}
module Properties.PaletteSearch (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import SixFour.Spec.Color        (OKLab(..))
import SixFour.Spec.PairTree     (HaarPalette(..))
import SixFour.Spec.PaletteSearch

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

-- | A well-formed Haar palette (level i has 2^i offsets) of small random depth.
genHaar :: Gen HaarPalette
genHaar = do
  d    <- choose (1, 4) :: Gen Int
  rt   <- genOKLab
  lvls <- mapM (\i -> vectorOf (2 ^ i) genOKLab) [0 .. d - 1]
  pure (HaarPalette rt lvls)

-- | A move whose (level, index) is in range for the given palette.
genMoveFor :: HaarPalette -> Gen Move
genMoveFor (HaarPalette _ lvls) = do
  let d = length lvls
  lv <- choose (0, max 0 (d - 1))
  ix <- choose (0, max 0 (2 ^ lv - 1))
  Move lv ix <$> genOKLab

-- | A tree after a small deterministic search from a random root.
genSearched :: Gen SearchTree
genSearched = do
  rt   <- genHaar
  n    <- choose (1, 60)
  seed <- choose (1, 1000000)
  pure (runSearch stubOracle defaultHyperparams (HaltOnVisits n) seed (leafNode 1.0 rt))

tests :: TestTree
tests = testGroup "PaletteSearch (MCTS over global-palette candidates)"
  [ testProperty "move round-trips (lossless + reversible, ε)" $
      forAll genHaar $ \s -> forAll (genMoveFor s) $ \m -> lawMoveRoundTrip m s
  , testProperty "move preserves well-formedness" $
      forAll genHaar $ \s -> forAll (genMoveFor s) $ \m -> lawMovePreservesWellFormed m s
  , testProperty "PUCT at c=0 is pure exploitation (= mean value)" $
      forAll genSearched $ \res -> forAll (choose (1, 50)) $ \pN ->
        all (\c -> lawPuctExploitLimit pN c) (map snd (stChildren res))
  , testProperty "backup counts visits: N iterations ⇒ +N root visits" $
      forAll genHaar $ \rt -> forAll (choose (0, 40)) $ \n -> forAll (choose (1, 1000000)) $ \seed ->
        lawBackupCountsVisits stubOracle n seed (leafNode 1.0 rt)
  , testProperty "deterministic: same seed ⇒ identical tree" $
      forAll genHaar $ \rt -> forAll (choose (0, 40)) $ \n -> forAll (choose (1, 1000000)) $ \seed ->
        lawDeterministic stubOracle n seed (leafNode 1.0 rt)
  , testProperty "gallery is bounded by k" $
      forAll genSearched $ \res -> forAll (choose (0, 8)) $ \k -> lawGalleryBounded k res
  ]
