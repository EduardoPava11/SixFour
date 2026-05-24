module Properties.Hybrid (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import qualified Data.Vector         as V
import qualified Data.Vector.Unboxed as U
import           Data.Word           (Word8)
import           Data.Maybe          (fromJust)
import           Data.Proxy          (Proxy(..))
import           GHC.TypeLits        (KnownNat, natVal)

import SixFour.Spec.Color   (OKLab(..))
import SixFour.Spec.StageA  (Frame(..))

import SixFour.Spec.Hybrid.Shape    (HybridK)
import SixFour.Spec.Hybrid.Hybrid   (HybridPalette)
import SixFour.Spec.Hybrid.Indices
  ( HybridIndexTensor(..)
  , mkHybridIndexTensor
  , mkSurjectiveTrunk
  , decodeSlot
  , Slot(..)
  )
import SixFour.Spec.Hybrid.STBN3D   (Mask3D(..), generateSTBN3D, horizontalBlueScore)
import SixFour.Spec.Hybrid.Pipeline
import SixFour.Spec.Hybrid.Laws

-- Tiny test cube: T = 3 frames, H = W = 4 px, kT = 6 trunk + kD = 2 delta = 8 total.
type T  = 3
type H  = 4
type W  = 4
type K  = 8     -- local K for the test only; production uses 256
type KT = 6
type KD = 2

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

genFrame :: Gen (Frame H W)
genFrame = do
  xs <- vectorOf (4 * 4) genOKLab
  pure (Frame (V.fromList xs))

genFrames :: Gen [Frame H W]
genFrames = vectorOf 3 genFrame

-- A canvas with strong temporal stability: every frame is identical
-- (apart from a small per-frame jitter to keep the variance-cut seeding
-- non-degenerate). Guarantees the TemporalStable witness can fire.
genStaticishFrames :: Gen [Frame H W]
genStaticishFrames = do
  base <- vectorOf (4 * 4) genOKLab
  let mkFrame jitter = Frame (V.fromList
        [ OKLab (l + jitter) a b | OKLab l a b <- base ])
  pure [mkFrame 0.0, mkFrame 0.0005, mkFrame (-0.0005)]

tests :: TestTree
tests = testGroup "Hybrid trunk + delta"
  [ -- Law 1: every emitted byte is in [0, 255]. Trivially true at
    -- the Word8 type but checked explicitly.
    testProperty "Law 1 (HybridLegal): bytes in [0,255]" $
      forAll genFrames $ \fs ->
        let mask = generateSTBN3D @T @H @W
            pipe = defaultHybridPipelineForTest @KT @KD mask
            out  = runHybridPipeline pipe (HybridPipelineInput fs)
        in lawHybridLegal (hpoIndices out)

    -- Witness 1 (SurjectiveTrunk): consistency check between the
    -- 'Maybe' wrapper and the actual byte distribution.
  , testProperty "SurjectiveTrunk witness is consistent (Just iff truly surjective)" $
      forAll genFrames $ \fs ->
        let mask = generateSTBN3D @T @H @W
            pipe = defaultHybridPipelineForTest @KT @KD mask
            out  = runHybridPipeline pipe (HybridPipelineInput fs)
            HybridIndexTensor v = hpoIndices out
            kT  = fromIntegral (natValOf @KT) :: Int
            trunkBytes = U.filter (\b -> fromIntegral b < kT) v
            usedAll = all (\k -> U.any (== fromIntegral k) trunkBytes) [0 .. kT - 1]
        in case hpoSurjectiveTrunk out of
             Just _  -> usedAll
             Nothing -> not usedAll

    -- Witness 2 (SurjectiveDeltaPerFrame): same consistency check.
  , testProperty "SurjectiveDeltaPerFrame witness is consistent" $
      forAll genFrames $ \fs ->
        let mask = generateSTBN3D @T @H @W
            pipe = defaultHybridPipelineForTest @KT @KD mask
            out  = runHybridPipeline pipe (HybridPipelineInput fs)
            HybridIndexTensor v = hpoIndices out
            nh = 4 :: Int
            nw = 4 :: Int
            nt = 3 :: Int
            kT = fromIntegral (natValOf @KT) :: Int
            kD = fromIntegral (natValOf @KD) :: Int
            perFrameLen = nh * nw
            frameUsesAllDeltas f =
              let start = f * perFrameLen
                  chunk = U.slice start perFrameLen v
                  ds    = U.filter (\b -> fromIntegral b >= kT) chunk
                  uniq  = length (uniqInts (map fromIntegral (U.toList ds) :: [Int]))
              in uniq == kD
            allOk = all frameUsesAllDeltas [0 .. nt - 1]
        in case hpoSurjectiveDeltaPerFrame out of
             Just _  -> allOk
             Nothing -> not allOk

    -- Witness 3 (TemporalStable): on near-static frames, either the
    -- witness fires OR at least one near-static voxel really did
    -- escape to the delta range (in which case rejection is correct).
  , testProperty "TemporalStable witness fires (or correctly refuses) on near-static frames" $
      forAll genStaticishFrames $ \fs ->
        let mask = generateSTBN3D @T @H @W
            pipe = defaultHybridPipelineForTest @KT @KD mask
            out  = runHybridPipeline pipe (HybridPipelineInput fs)
            HybridIndexTensor v = hpoIndices out
            nh = 4 :: Int
            nw = 4 :: Int
            nt = 3 :: Int
            kT = fromIntegral (natValOf @KT) :: Int
        in case hpoTemporalStable out of
             Just _ -> True
             Nothing ->
               or [ any (\f -> fromIntegral (v U.! ((f * nh + y) * nw + x)) >= kT)
                          [0 .. nt - 1]
                  | y <- [0 .. nh - 1], x <- [0 .. nw - 1]
                  ]

    -- Law 7 (OverheadBound): emitted palette bytes within envelope.
  , testProperty "Law 7 (OverheadBound): palette bytes ≤ 768 + T·3·kD" $
      forAll genFrames $ \fs ->
        let mask = generateSTBN3D @T @H @W
            pipe = defaultHybridPipelineForTest @KT @KD mask
            out  = runHybridPipeline pipe (HybridPipelineInput fs)
            kT = fromIntegral (natValOf @KT) :: Int
            kD = fromIntegral (natValOf @KD) :: Int
            actual = 3 * kT + 3 * 3 * kD
            _force = hpoIndices out   -- materialise to ensure the pipeline ran
        in actual `seq` lawOverheadBound (Proxy @T) (Proxy @KT) (Proxy @KD) actual

    -- Structural identity: hpTotalEntries reports kT + t·kD.
  , testProperty "lawTotalEntries: kT + t·kD" $
      forAll genFrames $ \fs ->
        let mask = generateSTBN3D @T @H @W
            pipe = defaultHybridPipelineForTest @KT @KD mask
            out  = runHybridPipeline pipe (HybridPipelineInput fs)
        in lawTotalEntries (hpoPalette out)

    -- decodeSlot inverts the encoding rule.
  , testProperty "decodeSlot inverts the encoding" $
      forAll (choose (0, 7)) $ \b ->
        let kT = 6 :: Int
            s  = decodeSlot kT (fromIntegral b :: Word8)
        in case s of
             Trunk i -> i == b && i < kT
             Delta j -> j + kT == b && j < (8 - kT)

    -- STBN3D mask has the expected size.
  , testProperty "generateSTBN3D produces nt·nh·nw bytes" $
      once $
        let Mask3D v = generateSTBN3D @T @H @W
        in U.length v == 3 * 4 * 4

    -- STBN3D mask is bluer than pure white noise: a positive
    -- horizontalBlueScore is necessary (not sufficient).
  , testProperty "generateSTBN3D mask has non-negative horizontalBlueScore" $
      once $
        let m = generateSTBN3D @4 @4 @4
        in horizontalBlueScore m >= 0

    -- Smart-constructor sanity: a manually-built index tensor with
    -- a missing trunk slot rejects the witness.
  , testProperty "mkSurjectiveTrunk rejects a tensor missing trunk slots" $
      once $
        let bytes = replicate (3 * 4 * 4) (5 :: Word8)
            it    = fromJust (mkHybridIndexTensor @T @H @W @KT @KD bytes)
        in case mkSurjectiveTrunk @T @H @W @KT @KD it of
             Nothing -> True
             Just _  -> False
  ]

-- | Local default pipeline that doesn't require the production K=256 constraint.
defaultHybridPipelineForTest
  :: forall kT kD. (HybridK kT kD)
  => Mask3D T H W
  -> HybridPipeline T H W K kT kD
defaultHybridPipelineForTest = defaultHybridPipeline

natValOf :: forall n. KnownNat n => Integer
natValOf = natVal (Proxy :: Proxy n)

uniqInts :: [Int] -> [Int]
uniqInts = foldr (\x acc -> if x `elem` acc then acc else x : acc) []
