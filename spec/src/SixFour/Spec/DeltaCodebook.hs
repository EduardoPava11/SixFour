{- |
Module      : SixFour.Spec.DeltaCodebook
Description : The finite genome-move vocabulary — 127 Haar slots × 12 σ-paired deltas.

Design §3.2 (@docs/COLOR-ATLAS.md@). Machine plies inside a search are EXACTLY
the existing 'SixFour.Spec.PaletteSearch.Move' — lossless, 'invertMove'-
reversible, 'wellFormed'-preserving — with the delta drawn from a finite
12-entry codebook so the policy head has a FINITE move vocabulary to emit
logits over (design §2: @deltaLogits@ [12], @nodeLogits@ [127]).

The codebook: ±L, ±a, ±b at two magnitudes {0.04, 0.01}, ordered in adjacent
σ-pairs (rows @2i@/@2i+1@ are closed under the chroma reflection
'sigmaReflect': the L pairs are pointwise σ-fixed, the chroma pairs swap).
Per-level scaling: a move at Haar level @ℓ@ uses @2^−ℓ@ times the codebook
delta — magnitude halves per level (coarse moves big, fine moves small), and
the scaling is exact in 'Double' (powers of two).

THE COUNT (judge resolution, §3.2): a depth-7 σ-pair tree has
@1 + 2 + … + 64 = 127@ addressable level slots; 'PaletteSearch.applyMove' only
modifies the LEVELS list — the root is UNADDRESSABLE. The vocabulary is
therefore @127 × 12 = 1524@, not 1536 ('lawVocab1524' pins it).
-}
-- COMPARTMENT: ZIG-FLOOR | tag:DeviceTag | STRADDLER
module SixFour.Spec.DeltaCodebook
  ( -- * The 12-entry σ-paired codebook
    deltaCodebook
  , codebookSize
  , codebookMagnitudes
  , deltaAt
    -- * The finite move vocabulary (depth-7 σ-pair genome)
  , addressableSlots
  , numAddressableSlots
  , moveVocab
  , vocabSize
    -- * Laws (predicates; QuickCheck'd in Properties.DeltaCodebook)
  , lawTwelvePerLevel
  , lawSigmaClosed
  , lawMagnitudeHalvesPerLevel
  , lawVocab1524
  , lawWellFormedPreserving
  ) where

import SixFour.Spec.Color         (OKLab(..))
import SixFour.Spec.PairTree      (HaarPalette(..), wellFormed, sigmaReflect)
import SixFour.Spec.PaletteSearch (Move(..), applyMove)
import SixFour.Spec.SigmaPairHead (sigmaPairDepth)

-- ---------------------------------------------------------------------------
-- The codebook
-- ---------------------------------------------------------------------------

-- | The two base magnitudes (the 'PaletteOracle.referencePolicy' step 0.04
-- plus a fine 0.01 step).
codebookMagnitudes :: [Double]
codebookMagnitudes = [0.04, 0.01]

-- | The 12 base deltas, in adjacent σ-pairs. Per magnitude @m@:
-- @[+L, −L, +a, −a, +b, −b]@ — rows @(0,1)@ σ-fixed pointwise, rows @(2,3)@
-- and @(4,5)@ swapped by σ ('lawSigmaClosed').
deltaCodebook :: [OKLab]
deltaCodebook =
  [ d | m <- codebookMagnitudes
      , d <- [ OKLab m 0 0, OKLab (negate m) 0 0
             , OKLab 0 m 0, OKLab 0 (negate m) 0
             , OKLab 0 0 m, OKLab 0 0 (negate m) ] ]

-- | Codebook row count (= 12; the @deltaLogits@ width).
codebookSize :: Int
codebookSize = length deltaCodebook

-- | The level-scaled delta: codebook row @k@ at Haar level @lv@ is the base
-- delta times @2^−lv@ (exact in 'Double'). Total: out-of-range @k@ wraps to
-- a zero delta (the identity move).
deltaAt :: Int -> Int -> OKLab
deltaAt lv k
  | k < 0 || k >= codebookSize = OKLab 0 0 0
  | otherwise =
      let OKLab l a b = deltaCodebook !! k
          s           = 2 ^^ negate lv
      in OKLab (s * l) (s * a) (s * b)

-- ---------------------------------------------------------------------------
-- The vocabulary
-- ---------------------------------------------------------------------------

-- | The addressable @(level, index)@ slots of a depth-7 tree:
-- @[ (lv, ix) | lv ∈ [0..6], ix ∈ [0..2^lv) ]@ — 127 slots. The ROOT is not
-- among them ('applyMove' never touches it).
addressableSlots :: [(Int, Int)]
addressableSlots =
  [ (lv, ix) | lv <- [0 .. sigmaPairDepth - 1], ix <- [0 .. 2 ^ lv - 1] ]

-- | @1 + 2 + … + 64 = 127@ (the @nodeLogits@ width).
numAddressableSlots :: Int
numAddressableSlots = length addressableSlots

-- | The full finite move vocabulary: every addressable slot × every codebook
-- row, with the level-scaled delta. Replay encodes a genome move as its index
-- in THIS list (design §3.3, VDST chunk).
moveVocab :: [Move]
moveVocab =
  [ Move lv ix (deltaAt lv k)
  | (lv, ix) <- addressableSlots
  , k <- [0 .. codebookSize - 1] ]

-- | @127 × 12 = 1524@.
vocabSize :: Int
vocabSize = length moveVocab

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | Exactly 12 codebook rows, and exactly 12 vocabulary moves per slot.
lawTwelvePerLevel :: Bool
lawTwelvePerLevel =
  codebookSize == 12
    && all (\slot -> length [ () | Move lv ix _ <- moveVocab, (lv, ix) == slot ] == 12)
           addressableSlots

-- | Each adjacent row pair @(2i, 2i+1)@ is closed under σ as a SET (the
-- chroma pairs swap; the L pairs are pointwise fixed). This is the row-swap
-- mask structure the delta head's σ-equivariance is built on (design §4.2).
lawSigmaClosed :: Bool
lawSigmaClosed =
  all pairClosed [0 .. codebookSize `div` 2 - 1]
  where
    pairClosed i =
      let r0 = deltaCodebook !! (2 * i)
          r1 = deltaCodebook !! (2 * i + 1)
      in setEq [sigmaReflect r0, sigmaReflect r1] [r0, r1]
    setEq xs ys = all (`elem` ys) xs && all (`elem` xs) ys

-- | The scaled delta at level @lv+1@ is COMPONENTWISE exactly half the delta
-- at level @lv@ (powers of two are exact in 'Double').
lawMagnitudeHalvesPerLevel :: Bool
lawMagnitudeHalvesPerLevel =
  and [ halfOf (deltaAt (lv + 1) k) (deltaAt lv k)
      | lv <- [0 .. sigmaPairDepth - 2], k <- [0 .. codebookSize - 1] ]
  where
    halfOf (OKLab l1 a1 b1) (OKLab l0 a0 b0) =
      l1 == l0 / 2 && a1 == a0 / 2 && b1 == b0 / 2

-- | The judge-pinned count: 127 slots (root unaddressable), 1524 moves.
lawVocab1524 :: Bool
lawVocab1524 =
  numAddressableSlots == sum [ 2 ^ lv | lv <- [0 .. sigmaPairDepth - 1] ]
    && numAddressableSlots == 127
    && vocabSize == 1524

-- | Every vocabulary move preserves 'wellFormed' on a well-formed depth-7
-- tree, and targets an in-range slot.
lawWellFormedPreserving :: HaarPalette -> Bool
lawWellFormedPreserving hp =
  not (wellFormed hp && length (levels hp) == sigmaPairDepth) ||
  all ok moveVocab
  where
    ok m@(Move lv ix _) =
      lv >= 0 && lv < sigmaPairDepth
        && ix >= 0 && ix < 2 ^ lv
        && wellFormed (applyMove m hp)
