{- |
Module      : SixFour.Spec.OptionTree
Description : The Merkle-MCTS option tree — PUCT search over (surfaced, held) nodes keyed by the Q16 hash.

The "merkle tree of options" of the KataGo/AlphaZero design, over the existing
types. A NODE is a @(surfaced 16³, held latent remainder)@ pair, but its IDENTITY
is only the Merkle hash of the SURFACED, Q16-quantized leaves ("SixFour.Spec.AtlasGame"
@quantizeQ16@ / "SixFour.Spec.AtlasMove" 'GenomeHash') — the held remainder is never
hashed (the "describe the visual, not the latent" boundary). Equal surfaced looks
therefore collapse to one node: 'transposition' makes the tree a Merkle DAG, not a
plain tree.

An EDGE carries the AlphaZero statistics @{N, W, P}@ (with @Q = W/N@) per action;
selection is 'puct'. The training target is the visit-count distribution
('visitPolicy'), not the prior. This is the surfaced-tier AlphaZero half of the
hybrid (the latent synth-beyond half plans MuZero-style and is off-spec here).

Per the 2026-06-20 reframe there is ONE swipe-navigated search (A/B retired); a
@GameMove@ edge is an @(a,b)@ swipe (`Edit`), a `Rung` refine/halt, or `HALT`.

GHC-boot-only. Laws QuickCheck'd in @Properties.OptionTree@.
-}
module SixFour.Spec.OptionTree
  ( -- * Nodes and edges
    OptionNode(..)
  , OptionEdge(..)
    -- * Selection + dedup
  , transposition
  , puct
  , edgePuct
  , qValue
  , edgeQ
  , visitPolicy
    -- * Laws (QuickCheck'd in @Properties.OptionTree@)
  , lawTranspositionByHash
  , lawPuctUnvisitedIsPrior
  , lawQValueIsMean
  , lawVisitPolicySumsToOne
  , lawPuctMonotoneInPrior
  , lawPuctGolden
  ) where

import Data.Word              (Word32)
import SixFour.Spec.AtlasMove (GenomeHash(..))
import SixFour.Spec.AtlasGame (Tier(..))

-- | A search node: identity is the Merkle hash of the SURFACED Q16 leaves only
-- (the held remainder is latent, never hashed). @onTier@/@onTerminal@ are metadata,
-- NOT part of identity.
data OptionNode = OptionNode
  { onHash     :: GenomeHash   -- ^ Merkle hash of the surfaced Q16 leaves
  , onTier     :: Tier         -- ^ which cube-ladder rung this node is at
  , onTerminal :: Bool         -- ^ committed (a HALT / shippable look)?
  }

-- | An edge's AlphaZero statistics for one action (the action key is held by the
-- tree, e.g. a @Map GameMove OptionEdge@). @Q = W / N@.
data OptionEdge = OptionEdge
  { oeN :: Int      -- ^ visit count @N(s,a)@
  , oeW :: Double   -- ^ total action value @W(s,a)@
  , oeP :: Double   -- ^ prior @P(s,a)@ from the policy head
  } deriving (Eq, Show)

-- | Two nodes transpose (are the same DAG node) iff they have the same surfaced
-- hash — tier/terminal are ignored. This is the Merkle dedup / transposition table.
transposition :: OptionNode -> OptionNode -> Bool
transposition a b = onHash a == onHash b

-- | The PUCT score: @Q + c_puct · P · √(ΣN) / (1 + N)@.
puct :: Double -> Double -> Double -> Int -> Int -> Double
puct cpuct q p n sumN =
  q + cpuct * p * sqrt (fromIntegral (max 0 sumN)) / (1 + fromIntegral (max 0 n))

-- | The mean action value @Q = W / N@ (0 at an unvisited edge).
qValue :: Double -> Int -> Double
qValue w n = if n <= 0 then 0 else w / fromIntegral n

-- | PUCT of a concrete edge against the parent's total visit count.
edgePuct :: Double -> Int -> OptionEdge -> Double
edgePuct cpuct sumN e = puct cpuct (edgeQ e) (oeP e) (oeN e) sumN

-- | The @Q@ of a concrete edge.
edgeQ :: OptionEdge -> Double
edgeQ e = qValue (oeW e) (oeN e)

-- | The visit-count policy target: visit counts normalised to a distribution
-- (all-zero counts map to all-zero).
visitPolicy :: [Int] -> [Double]
visitPolicy ns =
  let tot = fromIntegral (sum (map (max 0) ns)) :: Double
  in if tot <= 0 then map (const 0) ns
                 else map (\n -> fromIntegral (max 0 n) / tot) ns

-- | Transposition is hash-equality (independent of tier/terminal): equal surfaced
-- looks reached by different paths are ONE node.
lawTranspositionByHash :: Word32 -> Word32 -> Bool
lawTranspositionByHash h1 h2 =
  transposition (OptionNode (GenomeHash h1) T16 False) (OptionNode (GenomeHash h2) T64 True)
    == (h1 == h2)

-- | At an unvisited edge (@N=0@) PUCT reduces to @Q + c_puct·P·√(ΣN)@ (the
-- exploration term is undamped — unvisited actions are explored).
lawPuctUnvisitedIsPrior :: Double -> Double -> Double -> Int -> Bool
lawPuctUnvisitedIsPrior cpuct q p sumN =
  puct cpuct q p 0 sumN == q + cpuct * p * sqrt (fromIntegral (max 0 sumN))

-- | @Q = W/N@ for any visited edge.
lawQValueIsMean :: Double -> Int -> Bool
lawQValueIsMean w n = n <= 0 || qValue w n == w / fromIntegral n

-- | The visit-count policy sums to 1 whenever any action was visited.
lawVisitPolicySumsToOne :: [Int] -> Bool
lawVisitPolicySumsToOne ns =
  let cs = map (max 0) ns
  in sum cs == 0 || abs (sum (visitPolicy cs) - 1) < 1e-9

-- | PUCT is monotone non-decreasing in the prior @P@ (more prior ⇒ more explored).
lawPuctMonotoneInPrior :: Double -> Double -> Double -> Int -> Int -> Bool
lawPuctMonotoneInPrior cpuct' p1' p2' n sumN =
  let cpuct = abs cpuct'
      p1    = min p1' p2'
      p2    = max p1' p2'
  in puct cpuct 0 p1 n sumN <= puct cpuct 0 p2 n sumN

-- | Golden pin: @puct 1.0 0.5 0.5 0 4 = 0.5 + 0.5·2 = 1.5@.
lawPuctGolden :: Bool
lawPuctGolden = puct 1.0 0.5 0.5 0 4 == 1.5
