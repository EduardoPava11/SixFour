module Properties.IsometryMove (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.PairTreeFixed (OKLabI)
import SixFour.Spec.IsometryMove

-- A Q16 OKLab triple (same bounds as Properties.LeafOverride).
genPxI :: Gen OKLabI
genPxI = (,,) <$> choose (0, 65536) <*> choose (-26214, 26214) <*> choose (-26214, 26214)

-- An axis sign — only ever ±1 (the isometry group; any other value is not a member).
genSign :: Gen Int
genSign = elements [-1, 1]

-- A bounded Q16 translation (the move radius the schedule will anneal).
genShift :: Gen OKLabI
genShift = (,,) <$> choose (-16384, 16384) <*> choose (-16384, 16384) <*> choose (-16384, 16384)

genMove :: Gen IsoMove
genMove = IsoMove <$> ((,,) <$> genSign <*> genSign <*> genSign) <*> genShift

tests :: TestTree
tests = testGroup "IsometryMove (exact delta-preserving Q16 move — no tolerance)"
  [ testProperty "T1 preserves EVERY pairwise squared distance exactly" $
      forAll genMove $ \m -> forAll genPxI $ \x -> forAll genPxI (lawMovePreservesPairwiseDelta m x)

  , testProperty "T2 is exactly reversible (byte round-trip)" $
      forAll genMove $ \m -> forAll genPxI (lawMoveReversible m)

  , testProperty "T3 identity move is a no-op" $
      forAll genPxI lawIdentityIsNoOp

  , testProperty "T4 sigmaMove negates a,b and fixes L" $
      forAll genPxI lawSigmaIsAMove

  , testProperty "T5 composition stays an exact isometry (the group is closed)" $
      forAll genMove $ \m2 -> forAll genMove $ \m1 ->
        forAll genPxI $ \x -> forAll genPxI (lawComposePreservesPairwiseDelta m2 m1 x)
  ]
