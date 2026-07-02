module Properties.GuildScale (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.GuildScale

tests :: TestTree
tests = testGroup "GuildScale (the EARNED social-body sizes — council 7, guild cap 150, derived)"
  [ testProperty "the council is odd (tie-avoidance floor)" $
      once lawCouncilIsOdd
  , testProperty "an odd council breaks ties (no equal split of a binary vote)" $
      once lawCouncilBreaksTies
  , testProperty "an odd council has a unique median (why majority judgment needs odd)" $
      once lawOddCouncilHasUniqueMedian
  , testProperty "the quorum is a strict majority" $
      once lawQuorumIsStrictMajority
  , testProperty "the guild cap is the 4th Dunbar layer (135 <= 150 < 405)" $
      once lawGuildCapIsFourthLayer
  , testProperty "the council fits inside the guild" $
      once lawCouncilFitsGuild
  , testProperty "the council sits between support-clique (5) and sympathy-group (15)" $
      once lawCouncilBetweenLayers
  , testProperty "the Dunbar layers are geometric (ratio 3)" $
      \(NonNegative n) -> lawLayersGeometric n
  , testProperty "a schism splits members exactly and near-evenly" $
      \(NonNegative n) -> lawSchismHalves n
  ]
