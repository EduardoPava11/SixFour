{- |
Module      : Properties.Upscale256
Description : Property tests for 'SixFour.Spec.Upscale256' — the deterministic
              two-cube → 256³ endgame.

Cubes are kept tiny (T ≤ 3, S ≤ 2, palettes of 2–4) — the rules are
size-parametric, the app instantiates 64/64/256. The golden checksum pins the
full pipeline on a fixed synthetic cube pair.
-}
module Properties.Upscale256 (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import qualified Data.Vector as V

import SixFour.Spec.AtlasCascade (PixelStat(..), deriveExit)
import SixFour.Spec.Upscale256

genPx :: Gen PxQ16
genPx = (,,) <$> choose (0, 65536) <*> choose (-32768, 32768) <*> choose (-32768, 32768)

genStat :: Gen PixelStat
genStat = PixelStat
  <$> choose (0, 255)
  <*> choose (-200, 200) <*> choose (-200, 200) <*> choose (-200, 200)
  <*> choose (-32, 32)   <*> choose (-32, 32)
  <*> choose (-32, 32)

-- | A Show-able seed for a full upscale input (UpscaleInput carries a
-- function field, so the generator works through this record).
data Seed = Seed
  { sFrames    :: Int
  , sSide      :: Int
  , sPalettes  :: [[PxQ16]]
  , sMaps      :: [[Int]]
  , sGlobal    :: [PxQ16]
  , sCubeB     :: [[Int]]
  , sCubeA     :: [[Int]]
  , sAnchors   :: [PxQ16]
  , sStats     :: [PixelStat]
  , sLambda    :: Int
  , sKillAbove :: Maybe Int   -- ^ kill colours with L above this (Nothing = none)
  } deriving Show

genSeed :: Gen Seed
genSeed = do
  t  <- choose (1, 3)
  s  <- choose (1, 2)
  p  <- choose (2, 4)
  g  <- choose (2, 4)
  Seed t s
    <$> vectorOf t (vectorOf p genPx)
    <*> vectorOf t (vectorOf p (choose (0, 255)))
    <*> vectorOf g genPx
    <*> vectorOf t (vectorOf (s * s) (choose (0, p - 1)))
    <*> vectorOf t (vectorOf (s * s) (choose (0, g - 1)))
    <*> resize 2 (listOf genPx)
    <*> resize 24 (listOf genStat)
    <*> elements [0, 1]
    <*> frequency [ (2, pure Nothing), (1, Just <$> choose (0, 65536)) ]

mkInput :: Seed -> UpscaleInput
mkInput sd = UpscaleInput
  { upFrames   = sFrames sd
  , upSide     = sSide sd
  , upPalettes = sPalettes sd
  , upMap      = sMaps sd
  , upGlobal   = sGlobal sd
  , upCubeB    = map V.fromList (sCubeB sd)
  , upCubeA    = map V.fromList (sCubeA sd)
  , upKilled   = \(l, _, _) -> maybe False (l >) (sKillAbove sd)
  , upExit     = deriveExit 1 (sStats sd)
  , upAnchors  = sAnchors sd
  , upLambda   = sLambda sd
  }

-- | The fixed synthetic cube pair behind the golden checksum: T = 2, S = 2,
-- two-slot palettes, one anchor, λ = 1, a drift-bearing exit state.
goldenInput :: UpscaleInput
goldenInput = UpscaleInput
  { upFrames   = 2
  , upSide     = 2
  , upPalettes = [ [(0, 0, 0), (65536, 8192, -8192)]
                 , [(4096, 0, 0), (61440, 4096, -4096)] ]
  , upMap      = [ [3, 7], [3, 7] ]
  , upGlobal   = [ (0, 0, 0), (32768, 0, 0), (65536, 0, 0) ]
  , upCubeB    = [ V.fromList [0, 1, 1, 0], V.fromList [1, 1, 0, 0] ]
  , upCubeA    = [ V.fromList [0, 2, 2, 0], V.fromList [2, 2, 0, 0] ]
  , upKilled   = \(l, _, _) -> l > 63000
  , upExit     = deriveExit 1
      [ PixelStat 3 (-40) 5 (-5) 1 0 2, PixelStat 7 60 (-3) 3 0 1 (-2) ]
  , upAnchors  = [ (32768, 16384, 0) ]
  , upLambda   = 1
  }

-- | Pinned FNV-1a-64 of the golden output (the spec-side stand-in for the
-- device's SHA-256 WYSIWYG badge).
goldenChecksum :: Integer
goldenChecksum = 0x4b53edb975ab34ac

tests :: TestTree
tests = testGroup "Upscale256 (two-cube -> 256^3 deterministic endgame)"
  [ testProperty "k=0 reproduces P_t byte-identically" $
      forAll genSeed $ \sd ->
        let pals = sPalettes sd
            pt   = head pals
            pn   = last pals
        in forAll (vectorOf (length pt) (choose (0, length pn - 1))) $ \sigma ->
             lawK0PaletteExact pt pn sigma
  , testProperty "lambda=0 quantizer IS nearestQ16 (ties -> lowest)" $
      forAll (resize 6 (listOf1 genPx)) $ \pal ->
      forAll (resize 6 (listOf (choose (0, 200000)))) $ \priors ->
      forAll genPx $ \x -> lawLambda0IsNearestQ16 pal priors x
  , testProperty "PINNED: lambda=1 /= lambda=0 on the consumption fixture (anti-latent-carry)" $
      property lawLambdaConsumptionDiffers
  , testProperty "anchors appear VERBATIM in the anchored palette" $
      forAll (resize 3 (listOf genPx)) $ \anchors ->
      forAll (resize 6 (listOf1 genPx)) $ \pal ->
        lawAnchorsVerbatim anchors pal
  , testProperty "blend is integer-closed (stays inside the input interval)" $
      forAll arbitrary $ \k -> forAll genPx $ \a -> forAll genPx $ \b ->
        lawIntegerClosed k a b
  , testProperty "every output index addresses its frame's output palette" $
      withMaxSuccess 50 $ forAll genSeed $ \sd -> lawIndicesInRange (mkInput sd)
  , testProperty "output shape: 4T frames of (4S)^2 pixels" $
      withMaxSuccess 50 $ forAll genSeed $ \sd ->
        let out  = upscale256 (mkInput sd)
            sOut = upscaleFactor * sSide sd
        in length (outPalettes out) == upscaleFactor * sFrames sd
             && all ((== sOut * sOut) . V.length) (outCube out)
  , testProperty "anchors survive into EVERY output palette" $
      withMaxSuccess 50 $ forAll genSeed $ \sd ->
        let inp = mkInput sd
            as  = take 1 (sAnchors sd)   -- 1 anchor <= every palette size
        in all (\p -> all (`elem` p) as)
               (outPalettes (upscale256 inp { upAnchors = as }))
  , testProperty "alignSlots indices address P_{t+1}" $
      forAll genSeed $ \sd ->
        let pals = sPalettes sd
            maps = sMaps sd
            pt = head pals; pn = last pals
            mt = head maps; mn = last maps
        in all (\j -> j >= 0 && j < length pn) (alignSlots mt mn pt pn)
  , testProperty "GOLDEN: fixed synthetic cube pair checksum" $
      property (fromIntegral (outputChecksum (upscale256 goldenInput)) == goldenChecksum)
  ]
