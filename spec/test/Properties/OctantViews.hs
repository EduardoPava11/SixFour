module Properties.OctantViews (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.OctantViews

-- A 2×2×2 block as 8 corner values (corners order; short lists pad with 0).
genBlock :: Gen [Integer]
genBlock = vectorOf 8 (choose (-4000, 4000))

-- A colored block: 24 values = 8 corners × (R,G,B).
genColorBlock :: Gen [Integer]
genColorBlock = vectorOf 24 (choose (-4000, 4000))

tests :: TestTree
tests = testGroup "OctantViews (2x2x2 <-> 1 + latents, graded by axis subsets)"
  [ testGroup "The grading is the binomial row (Walsh-Hadamard characters of (Z/2)^3)"
      [ testProperty "band counts per order = 1,3,3,1; detail total = 7 = rank A_7" $
          once lawBandCountIsBinomial
      ]

  , testGroup "Latents are compressions in different orders (the keystone)"
      [ testProperty "every band == the detail of its own view (pool complement first)" $
          forAll genBlock lawLatentIsViewDetail
      , testProperty "views + coarse determine the block: 8*v = sum of signed bands (Z[1/2])" $
          forAll genBlock lawViewsDetermineBlock
      ]

  , testGroup "x:y unordered, t:t+1 ordered (time's arrow lives only in the t-bands)"
      [ testProperty "swapping x<->y permutes latents by subset relabeling" $
          forAll genBlock lawXYSwapPermutesLatents
      , testProperty "reversing (t,t+1) negates exactly the four t-containing bands" $
          forAll genBlock lawTimeReversalFlipsTBands
      ]

  , testGroup "Pooling kills its bands (the latent-level t-collapse)"
      [ testProperty "t-pooling zeroes t-bands, doubles the rest (kernel = span of t-bands)" $
          forAll genBlock lawAxisPoolingKillsItsBands
      ]

  , testGroup "Color is a different dimensional space (a fiber over the base)"
      [ testProperty "the opponent (L,a,b) map commutes with all 8 bands: opp(band)==band(opp)" $
          forAll genColorBlock lawColorFiberCommutes
      ]
  ]
