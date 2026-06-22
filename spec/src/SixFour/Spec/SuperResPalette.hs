{- |
Module      : SixFour.Spec.SuperResPalette
Description : The per-frame ≤K-colour palette constraint on the 256³ super-res, as a TYPE and a verified requantizer over "SixFour.Spec.Upscale256". "The 256³ must follow a per-frame 256-colour palette." Invented detail is free only as INDEX detail INSIDE each frame's ≤K table — never a (K+1)th colour.

The hard constraint the user pinned: every t-slice of the @256³@ output must quantize
to @≤ K@ colours (@K = 256@ in the app). On the octant @reconstruct256@ /
@pairedLift@ paths this is ILL-TYPED — they return a bare @[Int]@ index list with no
palette and no t-axis, so "distinct colours per frame" is uncomputable there. The
shipped super-res path that DOES carry a per-frame palette is "SixFour.Spec.Upscale256"
(@UpscaleOutput = (outPalettes, outCube)@ = per-frame palettes + index planes). So this
module sits over Upscale256:

  * 'PaletteFrame' — a BRAND (hidden constructor) certifying a frame's palette holds
    @≤ K@ DISTINCT colours; built only via 'mkPaletteFrame' (the smart constructor that
    is the refinement, value-level — no @DataKinds@).
  * 'requantizeSlice' — force a reconstructed t-slice into a @≤ K@ palette + index
    plane. WITHIN budget it is LOSSLESS (the palette is the exact distinct colours, the
    indices reproduce every pixel); OVER budget it picks @K@ representatives and assigns
    each pixel to its NEAREST entry.
  * 'upscaleWithinBudget' — the verifier on a whole "SixFour.Spec.Upscale256" output.

== Why the fidelity laws have teeth (killing the clamp cheat)

@≤ K@ alone is satisfiable by the degenerate "map every pixel to one colour" clamp. The
laws forbid it three ways: 'lawWithinBudgetLossless' (within budget the requantizer must
reproduce EVERY pixel — a clamp cannot), 'lawNearestMinimizesError' (over budget each
pixel takes its NEAREST entry, so an always-index-0 clamp is rejected), and
'lawMultiColourLegitimate' (a multi-colour slice with @K ≥ 2@ yields a multi-colour
palette — no collapse).

== The keystone tie

'lawUpscalePreservesLengthBudget': "SixFour.Spec.Upscale256" never grows a frame's
palette — @blendPalettesQ16@ and @applyAnchors@ both preserve length — so if every INPUT
per-frame palette has @≤ K@ slots, every OUTPUT frame does too (hence @≤ K@ distinct),
and every index addresses its palette (delegates @Upscale256.lawIndicesInRange@). This
is the proof that the per-frame budget SURVIVES the @64³→256³@ super-res. So "invent
free detail" is bounded: the super-res moves INDICES inside a fixed-size per-frame
alphabet, it never adds a @(K+1)@th colour.

Additive: a new sibling over Upscale256; nothing re-pinned. GHC-boot (@containers@,
@vector@). Colours are Q16 integers, so the brand and requantizer are bit-exact.
-}
module SixFour.Spec.SuperResPalette
  ( -- * The per-frame palette brand (hidden constructor; build via 'mkPaletteFrame')
    PaletteFrame
  , pfBudget
  , pfColors
  , mkPaletteFrame
    -- * Distinct-colour count + requantization
  , sliceDistinctColors
  , requantizeSlice
    -- * Verifier over an Upscale256 output
  , upscaleWithinBudget
    -- * Laws (QuickCheck'd in @Properties.SuperResPalette@)
  , lawWithinBudgetLossless
  , lawRequantSizeBounded
  , lawNearestMinimizesError
  , lawOverBudgetBeatsClamp
  , lawMultiColourLegitimate
  , lawBrandReflectsBudget
  , lawUpscalePreservesLengthBudget
  ) where

import           Data.List       (nub)
import qualified Data.Map.Strict as Map
import qualified Data.Set        as Set
import qualified Data.Vector     as V

import SixFour.Spec.SpatialDither (distSqQ16, nearestQ16)
import SixFour.Spec.Upscale256
  ( PxQ16, UpscaleInput(..), UpscaleOutput(..), upscale256 )

-- ---------------------------------------------------------------------------
-- The per-frame palette brand
-- ---------------------------------------------------------------------------

-- | A per-frame palette CERTIFIED to hold @≤ pfBudget@ distinct colours. The
-- constructor is hidden — build only via 'mkPaletteFrame', so a 'PaletteFrame' is a
-- runtime witness that the per-frame ≤K budget holds (the value-level analogue of
-- "SixFour.Spec.Significance" @SignificantVoxelVolume@, staying GHC-boot).
data PaletteFrame = PaletteFrame
  { pfBudget :: Int        -- ^ the colour budget @K@ this frame was checked against.
  , pfColors :: [PxQ16]    -- ^ the frame's colours (guaranteed @≤ pfBudget@ distinct).
  } deriving (Eq, Show)

-- | Brand a frame palette: @Just@ iff the budget is non-negative AND the palette holds
-- at most @k@ DISTINCT colours; @Nothing@ otherwise. The only way to obtain a
-- 'PaletteFrame'.
mkPaletteFrame :: Int -> [PxQ16] -> Maybe PaletteFrame
mkPaletteFrame k cs
  | k >= 0 && sliceDistinctColors cs <= k = Just (PaletteFrame k cs)
  | otherwise                             = Nothing

-- ---------------------------------------------------------------------------
-- Distinct count + requantization
-- ---------------------------------------------------------------------------

-- | The number of DISTINCT colours in a t-slice (the per-frame budget is on this, not
-- on pixel count).
sliceDistinctColors :: [PxQ16] -> Int
sliceDistinctColors = Set.size . Set.fromList

-- | Force a reconstructed t-slice into a @≤ k@ palette + index plane. WITHIN budget
-- (distinct @≤ k@) it is LOSSLESS: the palette is the slice's exact distinct colours and
-- each pixel indexes its own colour. OVER budget it takes @k@ representatives (the
-- lowest @k@ distinct colours, deterministic) and assigns each pixel to its NEAREST
-- entry. @k ≤ 0@ is the degenerate empty palette.
requantizeSlice :: Int -> [PxQ16] -> ([PxQ16], [Int])
requantizeSlice k pixels
  | k <= 0    = ([], replicate (length pixels) 0)
  | otherwise =
      let distinct = Set.toAscList (Set.fromList pixels)
      in if length distinct <= k
           then let m = Map.fromList (zip distinct [0 ..])
                in (distinct, [ m Map.! p | p <- pixels ])      -- exact, lossless
           else let pal = take k distinct
                in (pal, [ nearestQ16 pal p | p <- pixels ])    -- nearest of k reps

-- | Verify a whole "SixFour.Spec.Upscale256" output respects the per-frame budget:
-- every frame palette holds @≤ k@ distinct colours AND every index addresses its
-- palette.
upscaleWithinBudget :: Int -> UpscaleOutput -> Bool
upscaleWithinBudget k (UpscaleOutput pals cubes) =
     all (\p -> sliceDistinctColors p <= k) pals
  && and [ V.all (\i -> i >= 0 && i < length p) cube | (p, cube) <- zip pals cubes ]

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.SuperResPalette)
-- ============================================================================

-- | WITHIN budget the requantizer is LOSSLESS: every pixel is reproduced exactly by its
-- palette entry. Teeth: a clamp-to-one-colour requantizer would map distinct pixels to
-- the same entry and FAIL here — this is the primary fidelity guarantee. Guarded to the
-- within-budget case (distinct @≤ k@, @k ≥ 1@) so it is not vacuous.
lawWithinBudgetLossless :: Int -> [PxQ16] -> Bool
lawWithinBudgetLossless k pixels =
  k < 1 || sliceDistinctColors pixels > k
    || let (pal, idx) = requantizeSlice k pixels
       in length idx == length pixels
          && and [ pal !! i == p | (i, p) <- zip idx pixels ]

-- | The requantized palette never exceeds the budget. Teeth: rejects a requantizer that
-- emits more than @k@ palette entries.
lawRequantSizeBounded :: Int -> [PxQ16] -> Bool
lawRequantSizeBounded k pixels =
  let (pal, _) = requantizeSlice k pixels in length pal <= max 0 k

-- | OVER budget, each pixel is assigned to a NEAREST palette entry: no other entry is
-- closer. Teeth: rejects an always-index-0 clamp (a pixel nearer another entry would
-- expose it). Guarded to the over-budget case (distinct @> k ≥ 1@), where the palette is
-- non-empty, so it is the genuine lossy regime.
lawNearestMinimizesError :: Int -> [PxQ16] -> Bool
lawNearestMinimizesError k pixels =
  k < 1 || sliceDistinctColors pixels <= k
    || let (pal, idx) = requantizeSlice k pixels
           n = length pal
       in and [ all (\j -> distSqQ16 p (pal !! i) <= distSqQ16 p (pal !! j)) [0 .. n - 1]
              | (i, p) <- zip idx pixels ]

-- | OVER budget, the @k@ chosen representatives genuinely BEAT a single-colour clamp: the
-- total squared nearest-error of the requantization is STRICTLY LESS than mapping every
-- pixel to one representative. This certifies the over-budget representative choice — the
-- regime the other fidelity laws left unconstrained (a degenerate rep set, or a requantizer
-- that effectively clamped, would lose this bound). It holds because each representative is
-- itself a slice colour, so the pixel equal to a non-clamp rep contributes ZERO error under
-- the @k@ reps but POSITIVE error under the clamp; every other pixel takes its nearest, so
-- the total can only improve. Guarded to the genuine over-budget regime (distinct @> k ≥ 2@),
-- where @pal@ holds @k ≥ 2@ distinct reps.
lawOverBudgetBeatsClamp :: Int -> [PxQ16] -> Bool
lawOverBudgetBeatsClamp k pixels =
  k < 2 || sliceDistinctColors pixels <= k
    || let (pal, idx) = requantizeSlice k pixels
           reqErr     = sum [ distSqQ16 p (pal !! i) | (i, p) <- zip idx pixels ]
           clampErr   = sum [ distSqQ16 p (head pal)  | p <- pixels ]   -- map every pixel to rep 0
       in not (null pal) && reqErr < clampErr

-- | A multi-colour slice yields a multi-colour palette (no collapse): if the slice has
-- @≥ 2@ distinct colours and @k ≥ 2@, the requantized palette has @≥ 2@ distinct
-- colours. Teeth: rejects the collapse-to-one cheat even structurally.
lawMultiColourLegitimate :: Int -> [PxQ16] -> Bool
lawMultiColourLegitimate k pixels =
  k < 2 || sliceDistinctColors pixels < 2
    || let (pal, _) = requantizeSlice k pixels in length (nub pal) >= 2

-- | The brand admits a palette IFF it is within budget: @mkPaletteFrame k cs@ is @Just@
-- exactly when @k ≥ 0@ and the palette holds @≤ k@ distinct colours. Teeth: rejects a
-- brand that admits an over-budget palette (or rejects a within-budget one).
lawBrandReflectsBudget :: Int -> [PxQ16] -> Bool
lawBrandReflectsBudget k cs =
  case mkPaletteFrame k cs of
    Just pf -> k >= 0 && sliceDistinctColors cs <= k && pfColors pf == cs && pfBudget pf == k
    Nothing -> not (k >= 0 && sliceDistinctColors cs <= k)

-- | THE keystone tie: "SixFour.Spec.Upscale256" never grows a frame's palette, so the
-- per-frame budget SURVIVES the @64³→256³@ super-res. If every INPUT per-frame palette
-- has @≤ k@ slots, then every OUTPUT frame palette has @≤ k@ slots (hence @≤ k@ distinct)
-- and every index addresses its palette. Teeth: rejects a super-res that introduces a
-- @(k+1)@th colour per frame (the user's exact fear) — guarded so the antecedent (all
-- input palettes @≤ k@) is the satisfiable, frequently-hit case.
lawUpscalePreservesLengthBudget :: Int -> UpscaleInput -> Bool
lawUpscalePreservesLengthBudget k inp =
  not (all (\p -> length p <= k) (upPalettes inp))
    || upscaleWithinBudget k (upscale256 inp)
