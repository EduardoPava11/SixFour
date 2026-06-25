-- COMPARTMENT: MLX-MODEL | tag:MacTag
{- |
Module      : SixFour.Spec.NudgeContamination
Description : The collapse-safety quarantine for a USER nudge — proving the user's taste steer enters ONLY the invented detail (the latent tail) and CANNOT move the self-supervised energy, which lives in the gated coarse/DC band. The priority-1 law the L,a,b nudge design language rests on.

The design language's most natural gesture — grab the whole palette cloud and pan it in
@(L,a,b)@ (a coarse-band 'SixFour.Spec.HierarchicalDelta' @ColourDelta@) — lands by construction
on the COARSE/DC band, which is exactly where the self-supervised JEPA target lives
("SixFour.Spec.RedownsampleGate" gates that band; "SixFour.Spec.JepaTarget" makes the target a
@θ@-free DATA-manufactured value). So an UNGUARDED coarse pan could drift the target and reopen the
@L_close@ collapse the whole architecture forbids. The fix must be STRUCTURAL, not a runtime
threshold: a user taste nudge must be unable, /by construction/, to reach the energy band.

This module supplies that quarantine on the integer octree floor. A cube splits @k@ levels into a
COARSE plane (the energy band the gate reads) plus invented DETAIL (the null space):

  * 'applyTaste' — a TASTE nudge edits ONLY the detail bands and re-synthesises against the cube's
    ORIGINAL coarse plane. It structurally cannot feed a changed coarse to the synthesiser, so it is
    the type-level quarantine: a taste signal has no path to the energy band.
  * 'applyLeaky' — the FORBIDDEN counterpart that DOES touch the coarse plane (the unguarded coarse
    pan). Present only to give the laws teeth.
  * 'lawUserNudgeIsTasteOffEnergy' — KEYSTONE: for ANY detail edit, the re-downsampled coarse band
    is INVARIANT (@redownsample (applyTaste …) == redownsample cube@) and the gate still passes — so
    a taste nudge cannot move the data-manufactured target. Collapse-safe by construction.
  * 'lawLeakyCoarseNudgeDriftsEnergy' — TEETH: a coarse-touching nudge DOES change the re-downsampled
    band and the gate REJECTS it. This is what makes the quarantine non-vacuous and why the coarse
    'SwatchVector' is demoted to a display-only preview pan until a steer is proven taste-only.
  * 'lawTasteNudgesShareGateNullSpace' — taste nudges live in the SAME null space
    "SixFour.Spec.RedownsampleGate" @lawGateIgnoresInventedDetail@ already exempts: any two taste
    nudges over one base both pass that base's gate.

Additive: composes "SixFour.Spec.RedownsampleGate" (@redownsample@/@passesGate@) and the proven
octant ops; re-pins nothing, emits no golden. GHC-boot-only. Laws QuickCheck'd in
"Properties.NudgeContamination".
-}
module SixFour.Spec.NudgeContamination
  ( -- * The taste / leak split (the structural quarantine)
    applyTaste
  , applyLeaky
  , bumpDetail
    -- * Laws (QuickCheck'd in @Properties.NudgeContamination@)
  , lawUserNudgeIsTasteOffEnergy
  , lawLeakyCoarseNudgeDriftsEnergy
  , lawTasteNudgesShareGateNullSpace
  ) where

import SixFour.Spec.OctreeCell    (Detail, octantDistill, octantSynthesize)
import SixFour.Spec.OctreeGenome  (octreeLeafCount)
import SixFour.Spec.RedownsampleGate (redownsample, passesGate)

-- | Bump all seven detail sub-bands by @b@ (a representative invented-detail edit).
bumpDetail :: Int -> Detail -> Detail
bumpDetail b (a,c,d,e,f,g,h) = (a+b, c+b, d+b, e+b, f+b, g+b, h+b)

-- | A TASTE nudge: edit ONLY the invented detail bands (here, bump them by @b@) and re-synthesise
-- against the cube's ORIGINAL coarse plane. The coarse plane is read once and fed back UNCHANGED —
-- there is no path by which the edit reaches it, so this is the type-level quarantine: taste lives in
-- the detail null space, never the energy band. (@b@ stands for any detail edit; the laws hold for all @b@.)
applyTaste :: Int -> Int -> [Int] -> [Int]
applyTaste k b cube =
  let (coarse, detail) = octantDistill k cube
  in octantSynthesize (coarse, map (map (bumpDetail b)) detail)

-- | The FORBIDDEN counterpart: a LEAKY nudge that touches the COARSE plane (the unguarded coarse
-- @(L,a,b)@ pan), bumping it by @1@ and re-synthesising. Exists only to give the quarantine teeth —
-- it is exactly the move the design language must keep off any committed steer.
applyLeaky :: Int -> [Int] -> [Int]
applyLeaky k cube =
  let (coarse, detail) = octantDistill k cube
  in octantSynthesize (map (+ 1) coarse, detail)

-- | Validity bound for the laws: a real @8^d@ cube, pooled @1 <= k <= d@ levels.
validCube :: Int -> Int -> [Int] -> Bool
validCube k d cube = d >= 1 && k >= 1 && k <= d && length cube == octreeLeafCount d

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.NudgeContamination)
-- ============================================================================

-- | KEYSTONE — a user TASTE nudge is off the energy. For ANY detail edit @b@, the re-downsampled
-- coarse band (the data-manufactured JEPA-target band the "SixFour.Spec.RedownsampleGate" reads) is
-- INVARIANT, and the gate still passes the same coarse. So the user's taste steer provably cannot move
-- the self-supervised target — the @L_close@ collapse a coarse drift would cause is structurally
-- impossible for a taste nudge. Teeth: a nudge that leaked into the coarse plane would change
-- @redownsample@ ('lawLeakyCoarseNudgeDriftsEnergy'); this one cannot, because 'applyTaste' re-feeds the
-- original coarse.
lawUserNudgeIsTasteOffEnergy :: Int -> Int -> Int -> [Int] -> Bool
lawUserNudgeIsTasteOffEnergy k d b cube =
  not (validCube k d cube)
    || let coarse0 = redownsample k cube
           tasted  = applyTaste k b cube
       in redownsample k tasted == coarse0      -- the energy band is invariant under taste
          && passesGate k coarse0 tasted         -- ...so the target gate still passes

-- | TEETH — the quarantine is non-vacuous: a LEAKY coarse-touching nudge DOES drift the energy band
-- and the gate REJECTS it. This is precisely the unguarded coarse @(L,a,b)@ pan, and why the coarse
-- 'SwatchVector' must be demoted to a display-only preview until a steer is proven taste-only. Teeth:
-- if 'applyLeaky' were secretly detail-only this would falsely pass.
lawLeakyCoarseNudgeDriftsEnergy :: Int -> Int -> [Int] -> Bool
lawLeakyCoarseNudgeDriftsEnergy k d cube =
  not (validCube k d cube)
    || let coarse0 = redownsample k cube
           leaky   = applyLeaky k cube
       in redownsample k leaky /= coarse0        -- a coarse-touching nudge DOES drift the band
          && not (passesGate k coarse0 leaky)     -- ...and the gate rejects it

-- | Taste nudges live in the SAME null space "SixFour.Spec.RedownsampleGate"
-- @lawGateIgnoresInventedDetail@ already exempts: any two taste nudges (@b1@, @b2@) over one base both
-- pass that base's gate. So "the user's taste is invented detail" is the same theorem as "genuine
-- super-res is never rejected" — one null space, two readings. Teeth: a taste edit that touched coarse
-- would fail one of the two gates.
lawTasteNudgesShareGateNullSpace :: Int -> Int -> Int -> Int -> [Int] -> Bool
lawTasteNudgesShareGateNullSpace k d b1 b2 cube =
  not (validCube k d cube)
    || let coarse0 = redownsample k cube
       in passesGate k coarse0 (applyTaste k b1 cube)
          && passesGate k coarse0 (applyTaste k b2 cube)
