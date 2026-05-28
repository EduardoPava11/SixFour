module Properties.Quad4 (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import qualified Data.Vector.Unboxed as U

import SixFour.Spec.Color (OKLab(..))
import SixFour.Spec.Quad4

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

genSmallOffset :: Gen OKLab
genSmallOffset = OKLab <$> choose (-0.05, 0.05) <*> choose (-0.05, 0.05) <*> choose (-0.05, 0.05)

-- Arbitrary well-formed Quad4 tree (4 levels, 4^ℓ offset pairs at level ℓ).
genQuad4 :: Gen Quad4Palette
genQuad4 = do
  rt <- genOKLab
  lvls <- mapM (\l -> vectorOf (4 ^ l) ((,) <$> genOKLab <*> genOKLab))
                [0 .. quad4Depth - 1]
  pure (Quad4Palette rt lvls)

-- A well-formed tree with small offsets — guarantees gamut closure for the
-- bounded-leaf test below.
genBoundedQuad4 :: Gen Quad4Palette
genBoundedQuad4 = do
  rt <- OKLab <$> choose (0.4, 0.6) <*> choose (-0.02, 0.02) <*> choose (-0.02, 0.02)
  lvls <- mapM (\l -> vectorOf (4 ^ l) ((,) <$> genSmallOffset <*> genSmallOffset))
                [0 .. quad4Depth - 1]
  pure (Quad4Palette rt lvls)

inOKLabGamut :: OKLab -> Bool
inOKLabGamut (OKLab l a b) =
  l >= 0 && l <= 1 && a >= -0.4 && a <= 0.4 && b >= -0.4 && b <= 0.4

tests :: TestTree
tests = testGroup "Quad4 (depth-4 4-ary opponent-quadrant palette tree)"
  [ testProperty "dimensional accounting: depth=4, leaves=256, nodes=85, DOF=513" $
      once lawDOF513

  , testProperty "nodes per level = [1, 4, 16, 64]" $
      once $ quad4NodesPerLevel == [1, 4, 16, 64]

  , testProperty "well-formed tree reconstructs to exactly 256 leaves" $
      forAll genQuad4 lawLeafCount256

  , testProperty "balanced mean: mean of 256 leaves equals the root" $
      forAll genQuad4 (lawBalancedMean 1e-9)

  , testProperty "σ-equivariance: reconstruct(σ qp) = map σ (reconstruct qp)" $
      forAll genQuad4 (lawSigmaEquivariance 1e-12)

  , testProperty "reconstructFromVector ∘ toVector = reconstruct" $
      forAll genQuad4 (lawReconstructRoundTrip 1e-12)

  , testProperty "toVector has length quad4DegreesOfFreedom (513)" $
      forAll genQuad4 $ \qp ->
        U.length (toVector qp) == quad4DegreesOfFreedom

  , testProperty "reconstructFromVector rejects wrong-length input" $
      forAll genQuad4 $ \qp ->
        let v     = toVector qp
            short = U.take (U.length v - 1) v
        in reconstructFromVector short == Nothing

  , testProperty "saving over PairTree: 513 < 768 by 255 coefficients" $
      once $ (768 :: Int) - quad4DegreesOfFreedom == 255

  , -- A node with axis-aligned offsets δ₁ = (0, x, 0), δ₂ = (0, 0, y) places its
    -- 4 children in the 4 chromatic-opponent quadrants relative to the parent.
    testProperty "axis-aligned offsets at level 0 land children in 4 opponent quadrants" $
      forAll (choose (0.05, 0.2)) $ \x ->
      forAll (choose (0.05, 0.2)) $ \y ->
        let root = OKLab 0.5 0 0
            d1   = OKLab 0 x 0
            d2   = OKLab 0 0 y
            zero = OKLab 0 0 0
            qp   = Quad4Palette root
                     [ [(d1, d2)]
                     , replicate 4  (zero, zero)
                     , replicate 16 (zero, zero)
                     , replicate 64 (zero, zero)
                     ]
            -- With zero offsets at levels 1..3, every level-0 child propagates
            -- to a contiguous block of 64 leaves. Sample the 4 subtree roots:
            leaves     = reconstruct qp
            subtreeIxs = [0, 64, 128, 192]
            quartet    = [ leaves !! i | i <- subtreeIxs ]
            sgn (OKLab _ a b) = (compare a 0, compare b 0)
        in length (uniqList (map sgn quartet)) == 4

  , testProperty "bounded tree: every leaf stays in OKLab gamut" $
      forAll genBoundedQuad4 $ \qp ->
        all inOKLabGamut (reconstruct qp)
  ]

uniqList :: Eq a => [a] -> [a]
uniqList []     = []
uniqList (x:xs) = x : uniqList (filter (/= x) xs)
