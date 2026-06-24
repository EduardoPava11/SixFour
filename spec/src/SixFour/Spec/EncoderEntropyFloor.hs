{- |
Module      : SixFour.Spec.EncoderEntropyFloor
Description : The source-coding LOWER BOUND on the learned allocator — the last earning theorem. The Hamilton corpus-mean floor ("SixFour.Spec.EncoderWidthAlloc" over the corpus-mean load) is the entropy share each modality is OWED; a learned allocator may give a modality MORE channels than its floor but PROVABLY NEVER LESS. The active-floor dual of "SixFour.Spec.NeuronRedundancy" @varianceFloorPenalty@: a hinge that is 0 at/above the floor and strictly positive below it, so starving a modality is a measurable penalty, not a silent clamp.

Resolves the static-vs-learned question: STATIC = the floor (this theorem), LEARNED = the surplus
above it (empirical). The floor is a corpus invariant + a θ-constraint, never a per-clip reshape.

  * 'corpusFloor' — @floor_m = largestRemainder 512 (corpus-mean loads)@; sums to 512 by Hamilton,
    so "SixFour.Spec.HalfwayLatent" @lawFuseIsMidpoint@ still holds.
  * 'channelFloorPenalty' — @Σ_m max 0 (floor_m − alloc_m)@: 0 iff every modality is at/above floor,
    @> 0@ the moment one drops below (the @varianceFloorPenalty@ pattern, dual'd to integer channels).
  * 'lawCorpusFloorIsEntropyShare' — the floor IS the Hamilton entropy share over the corpus mean
    (sums to 512, follows load order). Killer mutant: a uniform @[171,171,170]@ floor breaks the order.
  * 'lawEncoderChannelsAtLeastEntropyShare' — a learned allocation at/above the floor PASSES; one
    below it (the sub-floor witness) FAILS. Killer mutant: an allocator that starves a modality.

Verified falsifiable in cabal repl (mutation audit, workflow wuhhsad8m): @corpusFloor witnessCorpus
= [50,320,142]@; sub-floor @[50,300,200]@ ⇒ @channelFloorPenalty = 20 > 0@ ⇒ law False.
GHC-boot-only; re-pins nothing. Byte-exact path untouched (encoders sit above @reenterQ16@).
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.EncoderEntropyFloor
  ( corpusFloor
  , channelFloorPenalty
  , lawCorpusFloorIsEntropyShare
  , lawEncoderChannelsAtLeastEntropyShare
  ) where

import SixFour.Spec.EncoderWidthAlloc (largestRemainder)
import SixFour.Spec.HalfwayLatent     (vitDModel)

-- | The corpus-mean entropy-share floor: average the per-clip @(index,palette,perceptual)@ loads
-- over the corpus, then Hamilton-apportion the 512 waist. Sums to EXACTLY @vitDModel@ (so the
-- @lawFuseIsMidpoint@ waist survives), and each @floor_m@ is the channels modality @m@ is OWED.
corpusFloor :: [[Double]] -> [Int]
corpusFloor corpusLoads
  | null corpusLoads = []
  | otherwise =
      let n    = fromIntegral (length corpusLoads)
          mean = map (/ n) (foldr1 (zipWith (+)) corpusLoads)
      in largestRemainder vitDModel mean

-- | The active channel floor penalty — the dual of "SixFour.Spec.NeuronRedundancy"
-- @varianceFloorPenalty@: @Σ_m max 0 (floor_m − alloc_m)@. Zero iff every modality is at or above
-- its entropy-share floor; strictly positive the moment one is starved below it. An active floor,
-- not a passive clamp.
channelFloorPenalty :: [Int] -> [Int] -> Int
channelFloorPenalty floors alloc =
  sum [ max 0 (f - a) | (f, a) <- zip floors alloc ]

-- =============================================================================
-- Witnesses
-- =============================================================================

-- | A 3-clip corpus; mean load @[14,90,40]@ ⇒ Hamilton floor @[50,320,142]@.
witnessCorpus :: [[Double]]
witnessCorpus = [ [10,100,50], [20,80,40], [12,90,30] ]

-- | A learned allocation giving every modality MORE than its floor (the head earned extra capacity
-- above the source-coding bound). PASSES.
allocAbove :: [Int]
allocAbove = zipWith (+) (corpusFloor witnessCorpus) [8, 20, 5]   -- [58,340,147]

-- | A SUB-FLOOR allocation: palette below its 320 floor (the head under-allocated colour). The
-- floor law MUST reject it.
allocSubFloor :: [Int]
allocSubFloor = [50, 300, 200]   -- palette 300 < 320 ⇒ below floor

-- =============================================================================
-- Laws
-- =============================================================================

-- | The floor IS the Hamilton entropy share over the corpus mean: it sums to exactly @vitDModel@
-- (so @lawFuseIsMidpoint@ holds) and follows the corpus load order (palette > perceptual > index).
-- A uniform @[171,171,170]@ floor would break the strict order.
lawCorpusFloorIsEntropyShare :: Bool
lawCorpusFloorIsEntropyShare =
  let f = corpusFloor witnessCorpus
  in sum f == vitDModel
     && case f of
          [i, p, c] -> p > c && c > i
          _         -> False

-- | THE SOURCE-CODING LOWER BOUND: the learned allocator may exceed the entropy-share floor but
-- never fall below it. An allocation at or above the floor reads zero penalty and PASSES; a
-- sub-floor allocation reads positive penalty and FAILS. Falsifiable by the sub-floor witness.
lawEncoderChannelsAtLeastEntropyShare :: Bool
lawEncoderChannelsAtLeastEntropyShare =
  let f = corpusFloor witnessCorpus
  in  channelFloorPenalty f f          == 0   -- exactly the floor: admitted
   && channelFloorPenalty f allocAbove == 0   -- learned gave MORE: admitted
   && channelFloorPenalty f allocSubFloor > 0 -- sub-floor: REJECTED (palette starved)
   && and (zipWith (>=) allocAbove f)         -- the ≥-floor predicate the penalty encodes
   && not (and (zipWith (>=) allocSubFloor f))
