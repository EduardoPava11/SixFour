{- |
Module      : SixFour.Spec.LocalPonder
Description : Per-(level,octant) adaptive refinement — "rungs accelerate/decelerate in deltas" made operational. Generalizes "SixFour.Spec.ScalePonder" from a LEVEL-uniform halt (one bool per octree depth, applied identically to every octant) to a PER-OCTANT mask, so refinement bits are spent on high-residual octants and saved on flat ones. Ties the bit saving to "SixFour.Spec.DetailEntropy".

"SixFour.Spec.ScalePonder" @applyPonder@ takes ONE bool per octree LEVEL and applies
it to every octant at that level (@zipWith keep ps dets@ — a level is kept or halted as
a whole). That is an EXPRESSIVITY proof (a non-contiguous level pattern beats a single
stop-depth), but it is NOT a data-dependent ALLOCATION: it cannot keep one octant and
drop its sibling at the same level. "Rungs accelerate/decelerate in deltas" — spend more
refinement where the local residual is unpredictable, coast where it is flat — needs a
mask per (level, octant). This module is that generalization; the per-level Ponder is
recovered as the all-octants-agree special case ('lawLevelUniformSubsumed').

  * 'lawRefineAllLocalIsLossless' — the all-True per-octant mask is the exact reversible
    floor (delegates the octant round-trip).
  * 'lawLevelUniformSubsumed' — a per-level "SixFour.Spec.ScalePonder" @Ponder@ lifted to
    a local mask gives the SAME result as @applyPonder@ (the special case is faithful).
  * 'lawLocalExceedsLevel' — a mask that keeps one octant and drops its SIBLING is
    UNREACHABLE by any per-level mask (a per-level mask cannot mix a level), and it
    changes the reconstruction (the dropped sibling carried real detail). Strictly more
    expressive — the genuinely new capability.
  * 'lawHaltingALevelZeroesItsBits' — halting a varied level drives its
    "SixFour.Spec.DetailEntropy" coded-bit budget from positive to ZERO: the bit saving
    is real and MEASURED (not a True-count). This is the tie that makes adaptive deltas
    an efficiency claim, not just expressivity.

Additive: imports "SixFour.Spec.ScalePonder" (for the per-level type it subsumes),
"SixFour.Spec.OctreeCell" (the octant ops) and "SixFour.Spec.DetailEntropy" (the bit
measure). No golden contract touched. GHC-boot (@base@).
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.LocalPonder
  ( -- * The per-(level,octant) mask
    LocalMask
  , refineAllLocal
  , liftPerLevelToLocal
  , applyLocal
    -- * Laws (QuickCheck'd in @Properties.LocalPonder@)
  , lawRefineAllLocalIsLossless
  , lawLevelUniformSubsumed
  , lawLocalExceedsLevel
  , lawHaltingALevelZeroesItsBits
  ) where

import Control.Monad (replicateM)

import SixFour.Spec.OctreeCell    (Detail, octantDistill, octantSynthesize)
import SixFour.Spec.ScalePonder   (Ponder, applyPonder)
import SixFour.Spec.DetailEntropy (detailEntropyBits)

-- | A per-(level,octant) refine decision, same shape as the distilled detail
-- @[[Detail]]@: @maskᵢⱼ@ decides octant @j@ at level @i@ (@True@ = refine/keep,
-- @False@ = halt to the zero-detail floor).
type LocalMask = [[Bool]]

-- | The zero-detail floor an halted octant truncates to.
zero7 :: Detail
zero7 = (0, 0, 0, 0, 0, 0, 0)

-- | Refine every octant at every level — full compute, all detail kept (shaped to a
-- distilled detail stack).
refineAllLocal :: [[Detail]] -> LocalMask
refineAllLocal = map (map (const True))

-- | Lift a per-level "SixFour.Spec.ScalePonder" @Ponder@ to the equivalent per-octant
-- mask: each level's single bool is replicated across that level's octants (so the
-- per-level halt is exactly the all-octants-agree local mask).
liftPerLevelToLocal :: [[Detail]] -> Ponder -> LocalMask
liftPerLevelToLocal dets ps = zipWith (\lvl b -> replicate (length lvl) b) dets ps

-- | Apply a per-octant mask to a distilled cube: keep each octant's detail where
-- refined, zero it where halted. Coarse/DC untouched (as in @applyPonder@).
applyLocal :: LocalMask -> ([Int], [[Detail]]) -> ([Int], [[Detail]])
applyLocal mask (coarse, dets) = (coarse, zipWith keepLevel mask dets)
  where
    keepLevel bs ds = zipWith keep bs ds
    keep True  d = d
    keep False _ = zero7

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.LocalPonder)
-- ============================================================================

-- | The all-True per-octant mask is the exact reversible floor (full compute ⇒
-- identity), delegating "SixFour.Spec.OctreeCell"'s octant round-trip. Gated to a
-- well-formed @8^d@ length.
lawRefineAllLocalIsLossless :: Int -> [Int] -> Bool
lawRefineAllLocalIsLossless d xs =
  not (d >= 0 && length xs == 8 ^ d)
    || let dist@(_, dets) = octantDistill d (take (8 ^ d) xs)
       in octantSynthesize (applyLocal (refineAllLocal dets) dist) == take (8 ^ d) xs

-- | A per-level @Ponder@ lifted to a local mask gives the SAME result as
-- "SixFour.Spec.ScalePonder" @applyPonder@ — the per-level halt is the all-octants-agree
-- special case of the per-octant mask. Teeth: rejects an @applyLocal@/@liftPerLevelToLocal@
-- that does not coincide with @applyPonder@ on uniform masks (e.g. a wrong octant order
-- or an off-by-one level alignment).
lawLevelUniformSubsumed :: Int -> [Int] -> [Bool] -> Bool
lawLevelUniformSubsumed d xs psRaw =
  not (d >= 0 && length xs == 8 ^ d)
    || let dist@(_, dets) = octantDistill d (take (8 ^ d) xs)
           ps = take (length dets) (psRaw ++ repeat True)   -- size to the level count
       in applyLocal (liftPerLevelToLocal dets ps) dist == applyPonder ps dist

-- | THE new capability: a mask that keeps one octant and drops its SIBLING at the same
-- level is unreachable by ANY per-level mask, and it changes the reconstruction. Teeth:
--
--   * UNREACHABLE — universally quantified over EVERY per-level lift (all @2^levels@
--     of them): a per-level mask sets all octants at a level equal, so it can never
--     produce the mixed finest level. Mirrors "SixFour.Spec.ScalePonder"
--     @lawPonderExceedsScalarHalt@'s @all (\\k -> …)@. Rejects an @applyLocal@ that is
--     secretly per-level.
--   * CHANGES-RECON — on @[0..63]@ the finest octant details are nonzero, so dropping a
--     sibling moves the reconstruction off the lossless floor. Rejects a vacuous witness
--     whose dropped octant carried no detail (the dropped sibling must matter).
lawLocalExceedsLevel :: Bool
lawLocalExceedsLevel =
  let d   = 2
      n   = 8 ^ d
      xs  = [0 .. n - 1]
      dist@(_, dets) = octantDistill d xs
      witness = case dets of
        (fine : rest) -> mixHead fine : map (map (const True)) rest
        []            -> []
      mixHead lvl = case lvl of
        (_ : _ : zs) -> True : False : map (const True) zs   -- keep oct0, drop oct1
        other        -> map (const True) other
      nL       = length dets
      allLifts = [ liftPerLevelToLocal dets bs | bs <- replicateM nL [True, False] ]
      unreachable  = all (/= witness) allLifts
      changesRecon = octantSynthesize (applyLocal witness dist) /= xs
  in nL >= 1
       && (case dets of (fine : _) -> length fine >= 2; _ -> False)
       && unreachable
       && changesRecon

-- | The "SixFour.Spec.DetailEntropy" tie: halting a VARIED level drives its coded-bit
-- budget from STRICTLY POSITIVE to ZERO — a real, MEASURED bit saving (not a count of
-- @False@s). Witness: the squares cube @[(i·i) mod 97]@ has a high-entropy finest level
-- (≈124 bits); halting it (all octants @False@) zeros that. Teeth: rejects a no-op halt
-- (the @before > 0@ guard ensures the level genuinely carried bits) and pins that the
-- bit measure responds to the halt (the @after == 0@ clause).
lawHaltingALevelZeroesItsBits :: Bool
lawHaltingALevelZeroesItsBits =
  let d   = 2
      n   = 8 ^ d
      xs  = [ (i * i) `mod` 97 | i <- [0 .. n - 1] ]
      dist@(_, dets) = octantDistill d xs
      mask = case dets of
        (fine : rest) -> map (const False) fine : map (map (const True)) rest
        []            -> []
      (_, dets') = applyLocal mask dist
  in case (dets, dets') of
       (fine : _, fine' : _) ->
         detailEntropyBits fine > 1e-9 && detailEntropyBits fine' < 1e-9
       _ -> False
