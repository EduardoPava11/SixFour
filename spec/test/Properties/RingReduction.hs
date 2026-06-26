module Properties.RingReduction (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.RingReduction

tests :: TestTree
tests = testGroup "RingReduction (reenterQ16 generalized: big→small grid crossing)"
  [ testGroup "reduce is a RETRACTION onto the grid (grid points are fixpoints)"
      [ testProperty "reduce . embed == id" $
          forAll (choose (-1000000, 1000000)) lawReduceEmbedId
      , testProperty "idempotent terminal quantization: reduce . embed . reduce == reduce" $
          forAll (choose (-100000000, 100000000)) lawReduceIdempotent
      ]

  , testGroup "The half-to-even commit + the honest non-homomorphism boundary"
      [ testProperty "half-to-even: 0.5→0, 1.5→2, 2.5→2, -0.5→0" $ once lawReduceHalfToEven
      , testProperty "reduce is NOT additive (a quantizer, not a ring hom): 0.5+0.5 rounds to 1≠0" $
          once lawReduceIsNotAdditive
      ]

  , testGroup "Elementwise (no cross-band coupling)"
      [ testProperty "batched reduce distributes over concatenation" $
          forAll (listOf (choose (-100000000, 100000000))) $ \xs ->
            forAll (listOf (choose (-100000000, 100000000))) $ \ys ->
              lawReduceBatchedIsElementwise xs ys
      ]
  ]
