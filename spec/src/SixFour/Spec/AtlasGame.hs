{- |
Module      : SixFour.Spec.AtlasGame
Description : The turn-based game wrapper — ONE move ADT over the three existing move systems.

The AlphaZero reframe (design doc SIXFOUR-ALPHAZERO-COLLAPSE-DESIGN §2, §7 #3) treats
look-finding as a turn-based game: a /position/ on the cube ladder, edited by reversible
moves, scored by an A/B preference. Three move systems already exist, typed apart and never
unified:

  * 'SixFour.Spec.PaletteSearch.Move' — the EDIT substrate (a reversible float OKLab Haar
    offset at @(level, index)@). This is where search perturbs the palette.
  * 'SixFour.Spec.AtlasMove.CurationMove' — the CURATE actions (toggle/weight/pin a bin) PLUS
    'SixFour.Spec.AtlasMove.Compare', which is NOT a state transition: it emits a Bradley-Terry
    preference pair and mutates nothing (@lawCompareIdentity@).
  * The cube-ladder TIER transition ('SixFour.Spec.CubeLadder'): 16³↔64³ is a lossless,
    reversible abstraction step; 64³→256³ is @synthBeyond@, which INVENTS detail and is not
    reversible.

This module is the thin, non-invasive wrapper that unifies them as one @GameMove@ and pins the
game's three load-bearing rules, WITHOUT editing 'PaletteSearch' or 'AtlasMove':

  1. 'Compare' is lifted OUT of the move space into the REWARD channel ('reward') — it is never a
     legal ply ('lawCompareIsReward'). (Conflict #3 in the design doc.)
  2. A 'Rung' move may descend (coarsen, lossless) or ascend within the CAPTURED ladder
     (16→64, lossless), but may NEVER ascend beyond capture (64→256, synth-beyond):
     'lawRungLegalityForbidsSynthBeyond', 'lawNoLegalRungReaches256'. The captured ladder is
     reversible at the tier level ('lawRungRoundTripCaptured').
  3. The determinism boundary is the Q16 TERMINAL hash, not a per-move invariant (design §3.4):
     the Edit substrate is float and only epsilon-reversible, so determinism is asserted at the
     terminal, where the palette is quantized to Q16 and that quantization is idempotent
     ('lawTerminalQuantizationIdempotent'). A 'terminal' position admits no further play
     ('lawTerminalHasNoMoves').
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none | STRADDLER
module SixFour.Spec.AtlasGame
  ( -- * The unified move ADT
    Tier(..)
  , RungMove(..)
  , GameMove(..)
    -- * The game position
  , GameState(..)
    -- * Semantics
  , applyRung
  , reward
  , legal
  , terminal
    -- * The Q16 terminal boundary
  , quantizeQ16
  , toQ16
    -- * Laws (predicates; QuickCheck'd in Properties.AtlasGame)
  , lawCompareIsReward
  , lawRungLegalityForbidsSynthBeyond
  , lawNoLegalRungReaches256
  , lawRungRoundTripCaptured
  , lawTerminalHasNoMoves
  , lawTerminalQuantizationIdempotent
  ) where

import Data.Maybe (isJust)

import SixFour.Spec.PaletteSearch (Move)
import SixFour.Spec.AtlasMove     (CurationMove(..), GenomeHash)

-- =============================================================================
-- The unified move ADT
-- =============================================================================

-- | A position on the cube ladder. Only the CAPTURED tiers @T16@/@T64@ are legal play
-- positions; @T256@ is the synth-beyond export tier, reachable only by the (forbidden as a
-- reversible move) @synthBeyond@, never by a legal 'Rung'.
data Tier = T16 | T64 | T256
  deriving (Eq, Show, Enum, Bounded)

-- | A ladder transition: 'Descend' coarsens (64→16, lossless 'distill'); 'Ascend' refines
-- within capture (16→64, the exact inverse). Ascending FROM @T64@ (to @T256@) is synth-beyond
-- and is deliberately NOT representable as a legal rung.
data RungMove = Ascend | Descend
  deriving (Eq, Show, Enum, Bounded)

-- | One game ply, unifying the three move systems. 'Edit' and 'Curate' wrap the existing
-- types verbatim (no edit to those modules); 'Rung' is the ladder transition. 'Compare' lives
-- inside 'CurationMove' for wire-compatibility but is rejected as a ply (see 'legal'/'reward').
data GameMove
  = Edit   Move           -- ^ reversible OKLab Haar offset (the search substrate)
  | Curate CurationMove   -- ^ a curation action; a 'Compare' is reward, not a move
  | Rung   RungMove        -- ^ a cube-ladder abstraction transition
  deriving (Eq, Show)

-- | The game position: the current ladder tier and whether the look is committed (terminal).
-- (The editable palette substrate itself lives in 'SixFour.Spec.PaletteSearch.SearchState';
-- this wrapper pins only the tier/terminal rules the game adds on top.)
data GameState = GameState
  { gsTier     :: !Tier   -- ^ current ladder tier (legal play: 'T16'\/'T64')
  , gsTerminal :: !Bool   -- ^ committed: no further play, only the Q16 terminal hash
  } deriving (Eq, Show)

-- =============================================================================
-- Semantics
-- =============================================================================

-- | The legal tier transitions. 'Nothing' marks an illegal rung — crucially
-- @applyRung Ascend T64 = Nothing@ (synth-beyond is not a reversible move), and @T256@ is
-- never produced (it is off the legal board).
applyRung :: RungMove -> Tier -> Maybe Tier
applyRung Ascend  T16 = Just T64   -- refine within capture (lossless)
applyRung Descend T64 = Just T16   -- coarsen (lossless distill)
applyRung _       _   = Nothing    -- everything else, incl. Ascend T64 (synth-beyond)

-- | A 'Compare' ply carries a Bradley-Terry @(winner, loser)@ preference and is lifted out of
-- the move space into the reward channel; every other move yields no reward.
reward :: GameMove -> Maybe (GenomeHash, GenomeHash)
reward (Curate (Compare w l)) = Just (w, l)
reward _                      = Nothing

-- | Whether a move is a legal ply in a position. A terminal position admits nothing; a
-- 'Compare' is never a ply (it is reward); a 'Rung' is legal iff 'applyRung' permits it.
legal :: GameMove -> GameState -> Bool
legal _ s | gsTerminal s        = False
legal (Curate (Compare _ _)) _  = False           -- reward, not a move
legal (Curate _) _              = True
legal (Edit _)   _              = True
legal (Rung m)   s              = isJust (applyRung m (gsTier s))

-- | A position is terminal iff committed.
terminal :: GameState -> Bool
terminal = gsTerminal

-- =============================================================================
-- The Q16 terminal boundary (the determinism contract lives HERE, not per-move)
-- =============================================================================

-- | Round a scene value to the Q16 fixed-point grid (the on-disk / cross-device terminal
-- representation). This is the single point where the float Edit substrate becomes a
-- byte-exact, replayable integer.
quantizeQ16 :: Double -> Int
quantizeQ16 x = round (x * 65536)

-- | The inverse view of a Q16 integer as a Double.
toQ16 :: Int -> Double
toQ16 q = fromIntegral q / 65536

-- =============================================================================
-- Laws (QuickCheck'd in Properties.AtlasGame)
-- =============================================================================

-- | 'Compare' is reward, not a move: it is never legal, and it extracts to its BT pair.
lawCompareIsReward :: GenomeHash -> GenomeHash -> GameState -> Bool
lawCompareIsReward w l s =
  not (legal (Curate (Compare w l)) s)
  && reward (Curate (Compare w l)) == Just (w, l)

-- | Ascending from the captured tier (64) to 256 is synth-beyond and is not a legal rung.
lawRungLegalityForbidsSynthBeyond :: Bool
lawRungLegalityForbidsSynthBeyond = applyRung Ascend T64 == Nothing

-- | No legal rung ever lands on @T256@ (it is reachable only by the lossy @synthBeyond@).
lawNoLegalRungReaches256 :: Tier -> RungMove -> Bool
lawNoLegalRungReaches256 t m = applyRung m t /= Just T256

-- | The captured ladder is reversible at the tier level: refine-then-coarsen and
-- coarsen-then-refine are identities (the tier-level shadow of @lawLadderBijective@).
lawRungRoundTripCaptured :: Bool
lawRungRoundTripCaptured =
  (applyRung Ascend T16 >>= applyRung Descend) == Just T16
  && (applyRung Descend T64 >>= applyRung Ascend) == Just T64

-- | A terminal position admits no further play: the terminal guard is the first, move-agnostic
-- clause of 'legal', so no 'Rung' is legal at any terminal tier (non-vacuous, since the same
-- rung is legal when the position is live — see @Properties.AtlasGame@).
lawTerminalHasNoMoves :: Tier -> RungMove -> Bool
lawTerminalHasNoMoves t r = not (legal (Rung r) (GameState t True))

-- | The Q16 terminal hash is a fixed point of quantization: re-quantizing an already-Q16
-- value is identity. This is why determinism is anchored at the terminal, not per (float) move.
lawTerminalQuantizationIdempotent :: Int -> Bool
lawTerminalQuantizationIdempotent q = quantizeQ16 (toQ16 q) == q
