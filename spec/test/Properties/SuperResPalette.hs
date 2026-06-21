module Properties.SuperResPalette (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import qualified Data.Vector as V

import SixFour.Spec.AtlasCascade  (PixelStat(..), deriveExit)
import SixFour.Spec.Upscale256    (PxQ16, UpscaleInput(..))
import SixFour.Spec.SuperResPalette

-- Pixels drawn from a SMALL fixed colour set so distinct counts are controllable and
-- both the within-budget (distinct <= k) and over-budget (distinct > k) regimes fire.
genSmallPx :: Gen PxQ16
genSmallPx = elements
  [ (0,0,0), (65536,0,0), (0,65536,0), (0,0,65536)
  , (32768,16384,0), (16384,0,32768), (8192,8192,8192), (65536,65536,65536) ]

genSlice :: Gen [PxQ16]
genSlice = listOf genSmallPx

genK :: Gen Int
genK = choose (0, 6)

-- A full Upscale256 input, replicating the Seed/mkInput pattern from
-- Properties.Upscale256. Every per-frame palette has the SAME length p, so k=p makes
-- the budget antecedent hold.
data Seed = Seed Int Int Int Int [[PxQ16]] [[Int]] [PxQ16] [[Int]] [[Int]] [PixelStat] Int
  deriving Show

genPx :: Gen PxQ16
genPx = (,,) <$> choose (0, 65536) <*> choose (-32768, 32768) <*> choose (-32768, 32768)

genStat :: Gen PixelStat
genStat = PixelStat
  <$> choose (0, 255)
  <*> choose (-200, 200) <*> choose (-200, 200) <*> choose (-200, 200)
  <*> choose (-32, 32)   <*> choose (-32, 32) <*> choose (-32, 32)

genSeed :: Gen Seed
genSeed = do
  t <- choose (1, 3)
  s <- choose (1, 2)
  p <- choose (2, 4)
  g <- choose (2, 4)
  Seed t s p g
    <$> vectorOf t (vectorOf p genPx)
    <*> vectorOf t (vectorOf p (choose (0, 255)))
    <*> vectorOf g genPx
    <*> vectorOf t (vectorOf (s * s) (choose (0, p - 1)))
    <*> vectorOf t (vectorOf (s * s) (choose (0, g - 1)))
    <*> resize 24 (listOf genStat)
    <*> elements [0, 1]

mkInput :: Seed -> UpscaleInput
mkInput (Seed t s _ _ pals maps glob cubeB cubeA stats lam) = UpscaleInput
  { upFrames   = t
  , upSide     = s
  , upPalettes = pals
  , upMap      = maps
  , upGlobal   = glob
  , upCubeB    = map V.fromList cubeB
  , upCubeA    = map V.fromList cubeA
  , upKilled   = const False
  , upExit     = deriveExit 1 stats
  , upAnchors  = []
  , upLambda   = lam
  }

-- The per-frame palette budget = the (uniform) input palette length p.
seedBudget :: Seed -> Int
seedBudget (Seed _ _ p _ _ _ _ _ _ _ _) = p

tests :: TestTree
tests = testGroup "SuperResPalette (per-frame <=K palette brand + requantizer over Upscale256)"
  [ testProperty "within budget the requantizer is LOSSLESS (every pixel reproduced)" $
      forAll genK $ \k -> forAll genSlice $ \px -> lawWithinBudgetLossless k px

  , testProperty "requantized palette never exceeds the budget" $
      forAll genK $ \k -> forAll genSlice $ \px -> lawRequantSizeBounded k px

  , testProperty "over budget, each pixel takes its NEAREST palette entry (no clamp)" $
      forAll genK $ \k -> forAll genSlice $ \px -> lawNearestMinimizesError k px

  , testProperty "a multi-colour slice yields a multi-colour palette (no collapse)" $
      forAll genK $ \k -> forAll genSlice $ \px -> lawMultiColourLegitimate k px

  , testProperty "the brand admits a palette IFF it is within budget" $
      forAll genK $ \k -> forAll genSlice $ \px -> lawBrandReflectsBudget k px

  , testProperty "KEYSTONE: Upscale256 preserves the per-frame palette budget (no (k+1)th colour)" $
      withMaxSuccess 50 $ forAll genSeed $ \sd ->
        lawUpscalePreservesLengthBudget (seedBudget sd) (mkInput sd)
  ]
