{-# LANGUAGE ScopedTypeVariables #-}

module Properties.AtlasGame (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import Data.Word (Word32)

import SixFour.Spec.AtlasMove (GenomeHash(..), CurationMove(Compare))
import SixFour.Spec.AtlasGame

-- The turn-based game wrapper: ONE move ADT over the three move systems. These laws pin the
-- three rules the game adds (Compare-is-reward, rung forbids synth-beyond, Q16 terminal
-- determinism) without touching PaletteSearch / AtlasMove.

genTier :: Gen Tier
genTier = elements [T16, T64, T256]

genRung :: Gen RungMove
genRung = elements [Ascend, Descend]

genHash :: Gen GenomeHash
genHash = GenomeHash <$> (arbitrary :: Gen Word32)

genState :: Gen GameState
genState = GameState <$> genTier <*> arbitrary

tests :: TestTree
tests = testGroup "AtlasGame (the unified turn-based move ADT)"

  [ testProperty "Compare is reward, never a legal ply (lawCompareIsReward)" $
      forAll genHash $ \w -> forAll genHash $ \l -> forAll genState $ \s ->
        lawCompareIsReward w l s

  , testProperty "Compare extracts to its BT pair, all other moves give no reward" $
      forAll genHash $ \w -> forAll genHash $ \l -> forAll genRung $ \r ->
        reward (Curate (Compare w l)) == Just (w, l) && reward (Rung r) == Nothing

  , testProperty "ascending 64->256 (synth-beyond) is not a legal rung (lawRungLegalityForbidsSynthBeyond)" $
      once lawRungLegalityForbidsSynthBeyond

  , testProperty "no legal rung ever reaches T256 (lawNoLegalRungReaches256)" $
      forAll genTier $ \t -> forAll genRung $ \m -> lawNoLegalRungReaches256 t m

  , testProperty "the captured ladder is tier-reversible (lawRungRoundTripCaptured)" $
      once lawRungRoundTripCaptured

  , testProperty "a terminal position admits no rung (lawTerminalHasNoMoves)" $
      forAll genTier $ \t -> forAll genRung $ \r -> lawTerminalHasNoMoves t r

  , testProperty "the terminal guard is NON-vacuous: live 16/64 admit their rung" $
      once $ legal (Rung Ascend) (GameState T16 False)
             && legal (Rung Descend) (GameState T64 False)

  , testProperty "Q16 terminal hash is idempotent (lawTerminalQuantizationIdempotent)" $
      forAll (choose (-1073741824, 1073741824) :: Gen Int) lawTerminalQuantizationIdempotent
  ]
