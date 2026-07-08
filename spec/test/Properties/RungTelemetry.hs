module Properties.RungTelemetry (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.RungTelemetry

tests :: TestTree
tests = testGroup "RungTelemetry (what the GRID shows per rung: exposure/arrival/significance/independence, both modes)"
  [ testGroup "Exposure state — one vocabulary"
      [ testProperty "optical (duration×ISO vs fine ref) == pooling-equivalent 2^k on the ladder (one integer k)" $
          \d0 iso k -> lawExposureVocabulariesAgreeOnLadder d0 iso k
      ]

  , testGroup "Arrival — the 320 cs window"
      [ testProperty "64/32/16 pulses per window, pulses × native interval == 320 cs" $
          once lawExpectedArrivalsPinned
      , testProperty "clean cadence: zero late, zero missing, spans the window" $
          once lawCleanCadenceIsHealthy
      , testProperty "a dropped pulse => exactly one late + one missing, span conserved (detectable from intervals)" $
          \r j -> lawDroppedPulseIsDetectable r j
      ]

  , testGroup "Significance — N and the √N meter"
      [ testProperty "derived N(k) = poolDepth·rungIdealNorm·N0 = 8^k·N0; rungs are the 1:8:64 lattice" $
          \n0 -> lawDerivedSignificanceLattice n0
      , testProperty "one rung buys ×8 samples = +3 bits of N" $
          \n0 k -> lawRungBuysThreeBits n0 k
      , testProperty "√N-monotone on squares: x <= y <=> x² <= y²" $
          \x y -> lawSignificanceSqrtMonotone x y
      , testProperty "independent-mode counts are monotone under new evidence" $
          \c cs -> lawIndependentCountsMonotone c cs
      ]

  , testGroup "Independence health — the exact co-movement statistic"
      [ testProperty "pooling composes: poolTo c . poolTo b == poolTo (b·c)" $
          \b c xs -> lawPoolCompose b c xs
      , testProperty "FOIL: derived pooling saturates the statistic (ratio == 1, isDerivedPool)" $
          \b fine -> lawDerivedPoolingIsMaximal b fine
      , testProperty "scale-equivariant: the derived verdict survives any further SHARED pool" $
          \b c fine -> lawDerivedStaysMaximalUnderSharedPool b c fine
      , testProperty "witness: dead-time photons push the statistic strictly below maximal" $
          once lawIndependentNoiseBoundedAway
      , testProperty "any sign disagreement drops the ratio below 1 (the warning light trips)" $
          \a b -> lawDisagreementIsDetected a b
      ]
  ]
