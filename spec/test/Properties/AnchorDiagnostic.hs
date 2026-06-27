module Properties.AnchorDiagnostic (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.AnchorDiagnostic

tests :: TestTree
tests = testGroup "AnchorDiagnostic (L-anchor experiment #1: per-channel detail energy, two lenses)"
  [ testProperty "KEYSTONE: iso-luminant chromatic -> signal in Z[i] chroma ring, L at lattice floor"
      lawIsoLuminantSignalIsInChromaRingNotL
  , testProperty "luma ramp -> signal in L, chroma at floor (L-anchoring is right here)"
      lawLumaRampSignalIsInL
  , testProperty "flat scene -> all channels at floor (then the data engine, not the anchor, is the problem)"
      lawFlatSceneFloorsAllChannels
  , testProperty "high-freq -> both lenses light (a symmetric per-channel target would have signal everywhere)"
      lawHighFreqLightsAllChannels
  , testProperty "constant channel is ALWAYS the lattice floor (forces L-at-floor whenever iso-luminant)" $
      forAll (choose (-300, 300)) lawConstantChannelIsLatticeFloor
  ]
