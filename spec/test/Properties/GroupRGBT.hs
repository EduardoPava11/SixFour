module Properties.GroupRGBT (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Collapse   (PxQ16, globalCollapseQ16)
import SixFour.Spec.GroupRGBT

-- A Q16 OKLab triple (same bounds as the other Q16 generators).
genPxI :: Gen PxQ16
genPxI = (,,) <$> choose (0, 65536) <*> choose (-26214, 26214) <*> choose (-26214, 26214)

-- A frame's palette: 1..8 candidates (small, so collapse is cheap).
genFrame :: Gen [PxQ16]
genFrame = do
  m <- choose (1, 8)
  vectorOf m genPxI

-- A burst of 0..32 frames (covers partial last groups + the 16-group shape).
genFrames :: Gen [[PxQ16]]
genFrames = do
  n <- choose (0, 32)
  vectorOf n genFrame

-- A mask of arbitrary length (shorter/longer than the group count both exercised).
genMask :: Gen GroupMask
genMask = do
  n <- choose (0, 20)
  vectorOf n arbitrary

genK :: Gen Int
genK = choose (1, 12)

tests :: TestTree
tests = testGroup "GroupRGBT (64 frames = 16 RGBT groups; group-SELECT drives the collapse)"
  [ testProperty "groupSize=4, numGroups=16 (64-frame burst)" $
      once $ groupSize == 4 && numGroups == 16

  , testProperty "concat . groupsOf4 = id (never loses/reorders frames)" $
      forAll genFrames $ \fs -> concat (groupsOf4 fs) == fs

  , testProperty "selecting ALL groups ≡ today's globalCollapseQ16 (backward-compat golden)" $
      forAll genK $ \k -> forAll genFrames (lawAllSelectedEqualsToday k)

  , testProperty "selected pool is a SUBSET of the full pool (selection only removes)" $
      forAll genMask $ \m -> forAll genFrames (lawSelectedPoolIsSubset m)

  , testProperty "deselecting a group removes EXACTLY that group's frames" $
      forAll genFrames $ \fs -> forAll (choose (0, 1000)) $ \g ->
        lawDeselectExcludesGroupFrames g fs

  , testProperty "empty selection ⇒ empty pool" $
      forAll genFrames lawEmptySelectionEmptyPool

  , testProperty "empty selection ⇒ empty collapse for any k" $
      forAll genK $ \k -> forAll genFrames $ \fs ->
        null (groupCollapseQ16 k (replicate (length (groupsOf4 fs)) False) fs)

  , testProperty "selecting a SINGLE group ≡ collapsing that group's 4 frames alone (picks are real)" $
      forAll genK $ \k -> forAll genFrames $ \fs ->
        let groups = groupsOf4 fs
            n = length groups
        in n > 0 ==> forAll (choose (0, n - 1)) (\j ->
             let mask = [ i == j | i <- [0 .. n - 1] ]
             in groupCollapseQ16 k mask fs == globalCollapseQ16 k (groups !! j))
  ]
