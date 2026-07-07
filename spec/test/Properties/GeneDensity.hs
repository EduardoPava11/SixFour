module Properties.GeneDensity (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.GeneDensity

-- A small alphabet-size seed for @levels@ (the laws re-derive their own bounded @levels@).
genLraw :: Gen Int
genLraw = choose (0, 64)

-- Small non-negative payloads (drive 'warpOf' between the identity and reversal branches).
genPayload :: Gen [Int]
genPayload = choose (0, 8) >>= \n -> vectorOf n (choose (0, 6))

-- Raw density / field seeds (cycled into small non-negative counts inside each law).
genSeed :: Gen [Int]
genSeed = choose (0, 40) >>= \n -> vectorOf n (choose (-8, 8))

tests :: TestTree
tests = testGroup "GeneDensity (gene = mass-preserving-up-to-warp pushforward on the colour density)"
  [ testProperty "MASS CONSERVED: Σ(g·ρ) = Σρ exactly (the augmentation is invariant)" $
      forAll genLraw $ \l -> forAll genPayload $ \p -> forAll genSeed $ \s ->
        lawGeneMassConserved l p s
  , testProperty "ACTION IS PUSHFORWARD: act = pushDensity φ_g, single-target (Monge) point map" $
      forAll genLraw $ \l -> forAll genPayload $ \p -> forAll genSeed $ \s ->
        lawActionIsPushforward l p s
  , testProperty "COMPOSES: functorial in the warp + composeWarp non-abelian" $
      forAll genLraw $ \l -> forAll genPayload $ \g -> forAll genPayload $ \h ->
        forAll genSeed $ \s -> lawActionComposes l g h s
  , testProperty "IDENTITY GENE: warpOf idGene = identityWarp, idGene·ρ = ρ" $
      forAll genLraw $ \l -> forAll genSeed $ \s -> lawIdentityGeneIsIdentityWarp l s
  , testProperty "BI-LIPSCHITZ: manufactured warp passes the admissibility (no-collapse) gate" $
      forAll genLraw $ \l -> forAll genPayload $ \p -> lawWarpBiLipschitz l p
  , testProperty "SCALE-EQUIVARIANT: warp-then-pool = pool-then-warp (same at 16/32/64)" $
      forAll genLraw $ \l -> forAll genLraw $ \sd -> forAll genLraw $ \f ->
        forAll genSeed $ \s -> lawScaleEquivariant l sd f s
  , testProperty "RECOMBINATION CLOSED: displacement-interpolation child is a valid gene-warp" $
      forAll genLraw $ \l -> forAll genPayload $ \a -> forAll genPayload $ \b ->
        forAll genSeed $ \s -> lawRecombinationClosed l a b s
  , testProperty "COMMUTES WITH K: dcOf (the DC) is invariant under the action" $
      forAll genLraw $ \l -> forAll genPayload $ \p -> forAll genSeed $ \s ->
        lawWarpCommutesWithK l p s
  , testProperty "EXPRESSED ENERGY: invariant under floor-fixing permutation, bounded by mass" $
      forAll genLraw $ \l -> forAll genSeed $ \s -> lawExpressedEnergyBounded l s
  ]
