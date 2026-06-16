module Properties.CanonicalPhase (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Data.Word (Word64)

import SixFour.Spec.CanonicalPhase
import SixFour.Spec.Upscale256 (fnv1a64)

-- A fixed cyclic sequence (with a tied max, exercising the necklace rule) — golden anchor.
goldenSeq :: [Int]
goldenSeq = [5, 3, 5, 9, 2, 9, 1, 7]

chk :: Show a => a -> Word64
chk x = fnv1a64 (map (fromIntegral . fromEnum) (show x))

-- Small Q16-ish key lists, value range chosen to MIX distinct and tied elements so the
-- gauge law is exercised on periodic loops too.
genKeys :: Gen [Int]
genKeys = do
  n <- choose (1, 8)
  vectorOf n (choose (0, 5))

genKeysPayload :: Gen ([Int], [Int])
genKeysPayload = do
  n  <- choose (1, 8)
  ks <- vectorOf n (choose (0, 5))
  pl <- vectorOf n (choose (0, 1000))
  pure (ks, pl)

tests :: TestTree
tests = testGroup "CanonicalPhase (loop gauge-fix: necklace canonical form)"
  [ testProperty "rotateBy composes: rotateBy i . rotateBy j = rotateBy (i+j)" $
      \(i :: Int) (j :: Int) -> forAll genKeys (lawRotateByComposes i j)

  , testProperty "canonical form is a genuine rotation (content preserved)" $
      forAll genKeys lawCanonicalRotationIsRotation

  , testProperty "phase is in range [0, n)" $
      forAll genKeys lawCanonicalPhaseInRange

  , -- THE keystone: rotation-invariance — every phase of one loop canonicalizes the same.
    testProperty "GAUGE-FIXED (EXACT): canonicalRotation (rotateBy k xs) = canonicalRotation xs" $
      \(k :: Int) -> forAll genKeys (lawCanonicalGaugeFixed k)

  , testProperty "canonical form is idempotent" $
      forAll genKeys lawCanonicalIdempotent

  , testProperty "application gauge-fix: rotating keys+payload together is invariant (unique phase)" $
      \(k :: Int) -> forAll genKeysPayload (\(ks, pl) -> lawCanonicalizeGaugeFixed k ks pl)

  , -- the worked counterexample from the module docs: the naive argmax+lowest-index
    -- rule would give different forms; the necklace form must give the SAME.
    testProperty "tie counterexample [5,3,5]: gauge-fixed where naive argmax fails" $
      once (and [ canonicalRotation (rotateBy k [5,3,5 :: Int]) == canonicalRotation [5,3,5]
                | k <- [0,1,2] ])

  , -- GOLDEN (Phase 4): the necklace canonical form of a fixed sequence (cross-language pin).
    testProperty "GOLDEN: canonicalRotation of the fixed sequence (FNV-1a-64 pin)" $
      once (chk (canonicalRotation goldenSeq) == (0x8b786b27a72ef2ba :: Word64))
  ]
