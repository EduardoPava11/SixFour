module Properties.GeneDensity3D (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.GeneDensity3D

-- A small alphabet-size seed for @L@ (the laws re-derive their own bounded @L@ ∈ {2,3,4}).
genLraw :: Gen Int
genLraw = choose (0, 64)

-- Small non-negative payloads (drive 'warpOf3' over the B3 group).
genPayload :: Gen [Int]
genPayload = choose (0, 8) >>= \n -> vectorOf n (choose (0, 6))

-- Raw density / field seeds (cycled into small non-negative counts inside each law).
genSeed :: Gen [Int]
genSeed = choose (0, 40) >>= \n -> vectorOf n (choose (-8, 8))

-- A raw int (drives per-axis identity/reversal selection in the marginal-embedding law).
genSign :: Gen Int
genSign = choose (0, 8)

tests :: TestTree
tests = testGroup "GeneDensity3D (gene = mass-preserving joint pushforward on the RGB colour cube; admissible = B3, order 48)"
  [ testProperty "MASS CONSERVED (3-D): Σ(g·ρ) = Σρ exactly over the L³ cube" $
      forAll genLraw $ \l -> forAll genPayload $ \p -> forAll genSeed $ \s ->
        lawGeneMassConserved3 l p s
  , testProperty "ACTION IS PUSHFORWARD (3-D): act3 = pushDensity3 φ_g, cube bijection (Monge)" $
      forAll genLraw $ \l -> forAll genPayload $ \p -> forAll genSeed $ \s ->
        lawActionIsPushforward3 l p s
  , testProperty "COMPOSES (3-D): functorial in the warp + composeWarp3 NON-ABELIAN (semidirect twist)" $
      forAll genLraw $ \l -> forAll genPayload $ \g -> forAll genPayload $ \h ->
        forAll genSeed $ \s -> lawActionComposes3 l g h s
  , testProperty "IDENTITY GENE (3-D): warpOf3 idGene = identityWarp3, idGene·ρ = ρ" $
      forAll genLraw $ \l -> forAll genSeed $ \s -> lawIdentityGeneIsIdentityWarp3 l s
  , testProperty "BI-LIPSCHITZ (3-D): warp passes admissible3 (κ=1 isometry); B3 is EXACTLY admissible (=48 at L=2)" $
      forAll genLraw $ \l -> forAll genPayload $ \p -> lawWarpBiLipschitz3 l p
  , testProperty "SCALE-EQUIVARIANT (3-D): warp-then-pool = pool-then-warp (same at 16/32/64)" $
      forAll genLraw $ \l -> forAll genLraw $ \sd -> forAll genLraw $ \f ->
        forAll genSeed $ \s -> lawScaleEquivariant3 l sd f s
  , testProperty "RECOMBINATION CLOSED (3-D): child stays in B3, conserves mass, single-target" $
      forAll genLraw $ \l -> forAll genPayload $ \a -> forAll genPayload $ \b ->
        forAll genSeed $ \s -> lawRecombinationClosed3 l a b s
  , testProperty "COMMUTES WITH K (3-D): dcOf3 (the DC) is invariant under the action" $
      forAll genLraw $ \l -> forAll genPayload $ \p -> forAll genSeed $ \s ->
        lawWarpCommutesWithK3 l p s
  , testProperty "EXPRESSED ENERGY (3-D): invariant under floor-fixing B3, bounded by mass" $
      forAll genLraw $ \l -> forAll genSeed $ \s -> lawExpressedEnergyBounded3 l s
  , testProperty "CROWN 1/2: hueRotate is admissible + mass-preserving, fixes grey, CHANNEL-COUPLED" $
      forAll genLraw $ \l -> forAll genSeed $ \s -> lawHueRotationIsChannelCoupled l s
  , testProperty "★ CROWN 2/2: hueRotate#ρ ≠ ANY product-of-marginals (R-marginal support splits 1→2)" $
      once (property lawHueRotationNotMarginal)
  , testProperty "MARGINAL EMBEDS: per-axis warps = (Z₂)³ product subgroup, NORMAL, quotient S3 (order 6)" $
      forAll genLraw $ \l -> forAll genSign $ \a -> forAll genSign $ \b -> forAll genSign $ \c ->
        forAll genSeed $ \s -> lawMarginalEmbedsInJoint l a b c s
  ]
