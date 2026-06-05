module Properties.PlaybackClock (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.PlaybackClock

-- A frame count in the realistic range (1..128), plus the canonical N=64.
newtype N = N Int deriving (Show)
instance Arbitrary N where
  arbitrary = N <$> choose (1, 128)

-- An arbitrary (possibly out-of-range) scrub index.
newtype Idx = Idx Int deriving (Show)
instance Arbitrary Idx where
  arbitrary = Idx <$> choose (-50, 200)

tests :: TestTree
tests = testGroup "PlaybackClock (the single 2D/3D/analyzer frame clock)"
  [ testProperty "monotonicModN: frameAfter advances one frame, mod N" $
      \(N n) -> forAll (choose (0, n - 1)) $ \f ->
        frameAfter n f === (f + 1) `mod` n

  , testProperty "wrapAtBoundary: frame N-1 wraps to 0" $
      \(N n) -> frameAfter n (n - 1) === 0

  , testProperty "scrubClamped: clampFrame lands in [0, N)" $
      \(N n) (Idx i) ->
        let c = clampFrame n i in (c >= 0) .&&. (c < n)

  , testProperty "scrubClamped is identity in-range" $
      \(N n) -> forAll (choose (0, n - 1)) $ \i ->
        clampFrame n i === i

  , testProperty "freezeIsFrameZero: reduce-motion never leaves frame 0" $
      \(N n) -> forAll (choose (0, 500)) $ \k ->
        (frozenStream n !! k) === 0

  , testProperty "twoViewsAgree: 2D image frame == 3D flat front face" $
      \(N n) (Idx i) ->
        twoDFrame n i === threeDFrontFace n i

  , testProperty "frontFace at z=N-1 equals the clamped cursor (kernel reduction)" $
      \(N n) -> forAll (choose (0, n - 1)) $ \cur ->
        frontFaceFrame n cur (n - 1) === cur

  , testProperty "paletteAtFrameDeterminism: same (palettes,i) -> same palette" $
      \(NonEmpty ps) (Idx i) ->
        paletteAt (ps :: [Int]) i === paletteAt ps i

  , testProperty "analyzersAgreeWithPlayer: palette index == player frame" $
      \(NonEmpty ps) (Idx i) ->
        paletteAt (ps :: [Int]) i
          === Just (ps !! twoDFrame (length ps) i)

  , testProperty "totalDefinedOnEmpty: N<=0 frame is 0, empty palette is Nothing" $
      \(Idx i) ->
        (frameAfter 0 i === 0)
          .&&. (clampFrame 0 i === 0)
          .&&. (paletteAt ([] :: [Int]) i === Nothing)

  , testProperty "golden advance table for N=64 is [1..63,0]" $
      once $ goldenAdvanceTable 64 === ([1 .. 63] ++ [0])

  , testProperty "golden freeze vector is all zeros" $
      \(NonNegative k) -> goldenFreezeVector k === replicate k 0
  ]
