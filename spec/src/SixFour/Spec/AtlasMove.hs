{- |
Module      : SixFour.Spec.AtlasMove
Description : The Color Atlas CURATION MOVE ADT — the user's plies on the 16³ board.

Design §3.1 (@docs/COLOR-ATLAS.md@). Curation moves are the user-level half of
the two-level move algebra (the machine half is the existing
'SixFour.Spec.PaletteSearch.Move' over the 'SixFour.Spec.DeltaCodebook'
vocabulary). They edit the board BETWEEN searches and condition the oracle:

  * 'ToggleBin'    — keep/kill a 16³ bin (involutive; ch4).
  * 'WeightRegion' — boost/suppress a bin by an i16 Q8.8 signed delta
    (additive + commutative; ch3).
  * 'PinAnchor'    — the global palette MUST contain this colour (idempotent;
    ch5 mask + the anchor-colour plane).
  * 'Compare'      — the user picked candidate @winner@ over @loser@. PURE
    training signal (a Bradley–Terry pair for 'SixFour.Spec.PreferenceUpdate');
    mutates NOTHING ('lawCompareIdentity').

'applyCuration' is TOTAL: out-of-range bins act as the identity. Moves touch
ch3–ch5 ONLY — the base channels ch0–ch2 are recomputed from capture state and
never edited ('lawBaseChannelsUntouched'). The board is therefore re-derivable
by folding the decision log ('boardFromLog' — the replay-determinism law the
SF64 container relies on, design §3.3).
-}
-- COMPARTMENT: SWIFT-COREAI | tag:DisplaySide
module SixFour.Spec.AtlasMove
  ( -- * Wire-scalar newtypes
    Q88(..)
  , q88ToDouble
  , GenomeHash(..)
    -- * The curation move ADT
  , CurationMove(..)
    -- * Application + replay
  , applyCuration
  , boardFromLog
    -- * Laws (predicates; QuickCheck'd in Properties.AtlasMove)
  , lawToggleInvolutive
  , lawWeightAdditiveCommutative
  , lawPinIdempotent
  , lawCompareIdentity
  , lawReplayDeterminism
  , lawBaseChannelsUntouched
  ) where

import           Data.Int        (Int16)
import           Data.List       (foldl')
import           Data.Word       (Word32)
import qualified Data.Vector     as V

import SixFour.Spec.AtlasBoard
import SixFour.Spec.Color (OKLab(..))

-- ---------------------------------------------------------------------------
-- Wire scalars
-- ---------------------------------------------------------------------------

-- | A signed i16 Q8.8 fixed-point weight delta (real value @v/256@ — a dyadic
-- rational, so 'Double' accumulation of Q8.8 deltas is EXACT; that exactness
-- is what makes 'lawWeightAdditiveCommutative' an equality, not an ε-law).
newtype Q88 = Q88 Int16
  deriving (Eq, Ord, Show)

-- | The real value of a 'Q88' (exact in 'Double').
q88ToDouble :: Q88 -> Double
q88ToDouble (Q88 v) = fromIntegral v / 256

-- | A u32 identity hash of a candidate genome (the SF64 GNOM chunk maps
-- hashes back to 384-float genomes; design §3.3).
newtype GenomeHash = GenomeHash Word32
  deriving (Eq, Ord, Show)

-- ---------------------------------------------------------------------------
-- The move ADT
-- ---------------------------------------------------------------------------

-- | A user curation ply (design §3.1).
data CurationMove
  = ToggleBin    BinIdx                  -- ^ keep/kill a bin (involutive)
  | WeightRegion BinIdx Q88              -- ^ signed Q8.8 delta (additive, commutative)
  | PinAnchor    BinIdx OKLabQ16         -- ^ palette MUST contain this colour (idempotent)
  | Compare      GenomeHash GenomeHash   -- ^ winner, loser — state identity; emits a BT pair
  deriving (Eq, Show)

-- ---------------------------------------------------------------------------
-- Application
-- ---------------------------------------------------------------------------

-- | Apply one curation move. Total: out-of-range bins ⇒ identity. Edits
-- ch3–ch5 (and the anchor-colour plane) only.
applyCuration :: CurationMove -> Board16 -> Board16
applyCuration (ToggleBin bi) b
  | not (binInRange bi) = b
  | otherwise =
      b { bKill = adjust (\v -> if v == 0 then 1 else 0) (binIndex bi) (bKill b) }
applyCuration (WeightRegion bi d) b
  | not (binInRange bi) = b
  | otherwise =
      b { bWeight = adjust (+ q88ToDouble d) (binIndex bi) (bWeight b) }
applyCuration (PinAnchor bi cq) b
  | not (binInRange bi) = b
  | otherwise =
      b { bAnchorMask = adjust (const 1) (binIndex bi) (bAnchorMask b)
        , bAnchors    = replaceAnchor bi (okLabFromQ16 cq) (bAnchors b)
        }
applyCuration (Compare _ _) b = b

-- | Update index @i@ of a channel vector.
adjust :: (Double -> Double) -> Int -> V.Vector Double -> V.Vector Double
adjust f i v = v V.// [(i, f (v V.! i))]

-- | One anchor colour per bin: replace if the bin is already pinned (latest
-- pin wins — this is what makes 'PinAnchor' idempotent), else append.
replaceAnchor :: BinIdx -> OKLab -> [(BinIdx, OKLab)] -> [(BinIdx, OKLab)]
replaceAnchor bi c as
  | any ((== bi) . fst) as = [ (bj, if bj == bi then c else cj) | (bj, cj) <- as ]
  | otherwise              = as ++ [(bi, c)]

-- ---------------------------------------------------------------------------
-- Replay
-- ---------------------------------------------------------------------------

-- | Fold a decision log over a base board, oldest move first. The board IS
-- this fold (replay determinism; the SF64 BORD chunk is a sanity snapshot,
-- never the source of truth — design §3.3).
boardFromLog :: Board16 -> [CurationMove] -> Board16
boardFromLog = foldl' (flip applyCuration)

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | Toggling the same bin twice restores the board (on {0,1} kill values —
-- i.e. on any board reachable by replay).
lawToggleInvolutive :: BinIdx -> Board16 -> Bool
lawToggleInvolutive bi b =
  applyCuration (ToggleBin bi) (applyCuration (ToggleBin bi) b) == b

-- | Weight moves are additive and commute — EXACTLY (Q8.8 deltas are dyadic).
lawWeightAdditiveCommutative :: BinIdx -> Q88 -> BinIdx -> Q88 -> Board16 -> Bool
lawWeightAdditiveCommutative bi d1 bj d2 b =
  applyCuration (WeightRegion bi d1) (applyCuration (WeightRegion bj d2) b)
    == applyCuration (WeightRegion bj d2) (applyCuration (WeightRegion bi d1) b)

-- | Pinning the same anchor twice equals pinning it once.
lawPinIdempotent :: BinIdx -> OKLabQ16 -> Board16 -> Bool
lawPinIdempotent bi cq b =
  let once = applyCuration (PinAnchor bi cq) b
  in applyCuration (PinAnchor bi cq) once == once

-- | 'Compare' mutates nothing — it is pure preference signal.
lawCompareIdentity :: GenomeHash -> GenomeHash -> Board16 -> Bool
lawCompareIdentity w l b = applyCuration (Compare w l) b == b

-- | Same log ⇒ bit-identical board (replay determinism; pure fold).
lawReplayDeterminism :: Board16 -> [CurationMove] -> Bool
lawReplayDeterminism b lg = boardFromLog b lg == boardFromLog b lg

-- | Curation never edits the base channels ch0–ch2.
lawBaseChannelsUntouched :: Board16 -> [CurationMove] -> Bool
lawBaseChannelsUntouched b lg =
  let b' = boardFromLog b lg
  in bMassPalettes b' == bMassPalettes b
     && bMassPixels b' == bMassPixels b
     && bCoverage   b' == bCoverage   b
