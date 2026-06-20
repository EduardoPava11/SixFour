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
import SixFour.Spec.PairTree     (HaarPalette(..), wellFormed, reconstruct)
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

-- | DEPTH-7 generator (the Atlas σ-pair root depth — design COLOR-ATLAS §4.0:
-- the old suite only generated depths 1–4, so the documented "768-D embedding"
-- claim was never exercised; at depth 7 'reconstruct' yields 128 leaves = 384
-- floats, which is exactly why 'SixFour.Spec.AtlasState' re-roots embedding
-- and reward at 'reconstructPaired').
genHaarDeep :: Gen HaarPalette
genHaarDeep = do
  d    <- choose (1, 7) :: Gen Int
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
    -- Discovered-style laws (the value QuickSpec would surface, written explicitly):
  , testProperty "gallery options are all well-formed palettes" $
      forAll genSearched $ \res -> forAll (choose (1, 5)) $ \k ->
        all wellFormed (galStates (extractGallery k 1.0 0.5 res))
  , testProperty "a move never changes the leaf count (2^depth)" $
      forAll genHaar $ \s -> forAll (genMoveFor s) $ \m ->
        length (reconstruct (applyMove m s)) == length (reconstruct s)
  , testProperty "moves commute (additive perturbations, ε)" $
      forAll genHaar $ \s -> forAll (genMoveFor s) $ \m1 -> forAll (genMoveFor s) $ \m2 ->
        colorsClose 1e-9 (reconstruct (applyMove m1 (applyMove m2 s)))
                         (reconstruct (applyMove m2 (applyMove m1 s)))
    -- Depth-7 coverage (COLOR-ATLAS §4.0): the embedding length is pinned PER
    -- DEPTH — 3·2^d floats, i.e. 384 (not 768) at the σ-pair root depth 7.
  , testProperty "paletteEmbedding has exactly 3*2^depth entries (384 at depth 7)" $
      forAll genHaarDeep $ \s ->
        length (paletteEmbedding s) == 3 * length (reconstruct s)
          && length (reconstruct s) == 2 ^ length (levels s)
  , testProperty "depth-7: move round-trips + preserves well-formedness" $
      forAll genHaarDeep $ \s -> forAll (genMoveFor s) $ \m ->
        lawMoveRoundTrip m s && lawMovePreservesWellFormed m s
    -- Model-based / state-machine law: a search only GROWS the tree, never corrupts it.
  , testProperty "model-based: search grows monotonically + keeps states well-formed" $
      forAll genHaar $ \rt -> forAll (listOf1 (choose (1, 12))) $ \batches ->
      forAll (choose (1, 1000000)) $ \seed ->
        let r0     = leafNode 1.0 rt
            snaps  = scanl (\t n -> runSearch stubOracle defaultHyperparams (HaltOnVisits n) seed t) r0 batches
            consec = zip snaps (drop 1 snaps)
        in conjoin
             [ counterexample "root visits non-decreasing"
                 (property (all (\(a, b) -> stVisits b >= stVisits a) consec))
             , counterexample "subtree visits non-decreasing"
                 (property (all (\(a, b) -> subtreeVisits b >= subtreeVisits a) consec))
             , counterexample "once expanded, stays expanded"
                 (property (all (\(a, b) -> not (stExpanded a) || stExpanded b) consec))
             , counterexample "children are never removed"
                 (property (all (\(a, b) -> length (stChildren a) <= length (stChildren b)) consec))
             , counterexample "every node state stays well-formed"
                 (property (all (all wellFormed . nodeStates) snaps))
             ]
  , testProperty "depth-bounded: expansion never exceeds hpMaxDepth (the shallow depth-2-3 proposer)" $
      forAll genHaar $ \s -> forAll (choose (0, 40)) $ \n -> forAll (choose (1, 1000000)) $ \seed ->
        forAll (choose (1, 3)) $ \d ->
          lawDepthBounded stubOracle (defaultHyperparams { hpMaxDepth = d }) n seed s
  ]

-- | ε-approximate equality of two colour lists (FP add/sub is not exact).
colorsClose :: Double -> [OKLab] -> [OKLab] -> Bool
colorsClose eps xs ys = length xs == length ys && and (zipWith ok xs ys)
  where ok (OKLab a b c) (OKLab a' b' c') =
          abs (a - a') < eps && abs (b - b') < eps && abs (c - c') < eps

-- | Every node's state in a search tree (root first).
nodeStates :: SearchTree -> [HaarPalette]
nodeStates t = stState t : concatMap (nodeStates . snd) (stChildren t)
