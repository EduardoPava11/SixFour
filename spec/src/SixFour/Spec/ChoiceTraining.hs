{- |
Module      : SixFour.Spec.ChoiceTraining
Description : TRAINING LOOKS DIFFERENT NOW — run the three scales as three GIFs, mix them, and let the USER'S CHOICE be the training signal. The arms the user decides between are mixed renders of the SAME capture under different influence fields ("SixFour.Spec.PullField"), and mixing is FREE: every mixed render is a REGIONWISE SPLICE of the three pure GIFs ('lawMixIsRegionwiseSplice' — render once at each rung, assemble any mix by copying regions; arm generation costs zero re-renders). The choice signal is CRISP where paint is not: two arms differing in a single region render byte-identical everywhere else ('lawSingleRegionChoiceIsUnambiguous', the PullField locality law applied to pairs), so a pick isolates exactly one variable — and a two-comparison tournament per region recovers ANY target field exactly ('lawTournamentIdentifiesField').

PAINT IS FUN BUT AMBIGUOUS, made exact ('lawPaintUnderdeterminesDepth'): the
committed W1 paint mask is BINARY per region (allowed / floor) while the
influence field is TERNARY (16/32/64-rung depth) — 3^n fields collapse onto
2^n masks, so paint provably cannot express which depth the user wants, only
where depth is permitted. Paint stays as the fun, local hint (WHERE);
choice-between-renders is the unambiguous signal (HOW DEEP), and the two
compose: paint constrains the arm space, choices resolve it.

THE TRAINING LOOP (design, referenced not landed here): the user's pick is a
Bradley–Terry preference observation over fields — the on-device machinery
has a proof in the repo's own history (AtlasTrainer: BT value training,
12.4 ms/step, bit-identical Mac↔iPhone, 2026-06-12). Inference-time choice
IS the training example (the yin-yang closed with the user as the gate): the
pick both selects the shipped GIF and updates the halting/influence policy —
the certified-order floor ("SixFour.Spec.KinematicHaltPrior") and the W = 1
skip ("SixFour.Spec.TriScaleTraining") prune regions where no choice is
needed, so the user is only ever asked about regions where influence is
genuinely contested.

HONEST BOUNDARY: this module gates the ARM ALGEBRA (splice, isolation,
identifiability, the paint-ambiguity pigeonhole) in exact arithmetic. The
Bradley–Terry update itself (a sigmoid over utility differences) is
Double-land trainer machinery and is deliberately not re-landed here; the
tournament law uses a deterministic single-peaked chooser (utility
−|depth − target|) as the identifiability witness, not a stochastic model.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.ChoiceTraining
  ( -- * Arms: mixed renders over influence fields
    fieldFromList
  , paintMaskOf
    -- * The tournament chooser (the identifiability witness)
  , tournamentRecover
    -- * Laws
  , lawMixIsRegionwiseSplice
  , lawSingleRegionChoiceIsUnambiguous
  , lawPaintUnderdeterminesDepth
  , lawTournamentIdentifiesField
  ) where

import SixFour.Spec.PullField
  ( Volume, volumeFromList, Field, regionOf, renderPull, side )

-- | A field from its 8 region depths (clamped to 0..2; short lists pad 0).
fieldFromList :: [Int] -> Field
fieldFromList ds r = max 0 (min 2 (padded !! max 0 (min 7 r)))
  where padded = take 8 (ds ++ repeat 0)

-- | The W1 paint mask a field induces: a region is painted iff its depth is
-- above the floor. BINARY — which is exactly the ambiguity.
paintMaskOf :: Field -> [Bool]
paintMaskOf f = [ f r > 0 | r <- [0 .. 7] ]

allVoxels :: [(Int, Int, Int)]
allVoxels = [ (x, y, t) | t <- [0 .. side - 1], y <- [0 .. side - 1], x <- [0 .. side - 1] ]

-- | LAW (mixing is free): every mixed render equals, at every voxel, the PURE
-- render of that voxel's own region depth — any mix is a regionwise splice
-- of the three pure GIFs. Render the three rungs once; assemble arms by
-- copying regions, zero re-renders. (A contract law: cross-region smoothing
-- in a future render would break it, loudly.)
lawMixIsRegionwiseSplice :: [Int] -> [Integer] -> Bool
lawMixIsRegionwiseSplice ds xs =
  and [ renderPull f v p == renderPull (const (f (regionOf p))) v p
      | p <- allVoxels ]
  where
    f = fieldFromList ds
    v = volumeFromList xs

-- | LAW (the choice isolates one variable): two arms whose fields agree
-- outside region r render BYTE-IDENTICAL outside r — the user's pick between
-- them can only be about r. Locality is what makes choice unambiguous.
lawSingleRegionChoiceIsUnambiguous :: Int -> [Int] -> Int -> Int -> [Integer] -> Bool
lawSingleRegionChoiceIsUnambiguous rRaw ds dA dB xs =
  and [ regionOf p == r || armA p == armB p | p <- allVoxels ]
  where
    r = abs rRaw `mod` 8
    base = fieldFromList ds
    mk d q = if q == r then max 0 (min 2 d) else base q
    v = volumeFromList xs
    armA = renderPull (mk dA) v
    armB = renderPull (mk dB) v

-- | LAW (paint is fun but ambiguous, exactly): the field→mask map is
-- provably non-injective — the all-1 and all-2 fields induce the SAME
-- all-painted mask while rendering differently, and by counting, 3^8 = 6561
-- fields collapse onto 2^8 = 256 masks. Paint says WHERE; it cannot say HOW
-- DEEP.
lawPaintUnderdeterminesDepth :: Bool
lawPaintUnderdeterminesDepth =
  paintMaskOf f1 == paintMaskOf f2
    && [ f1 r | r <- [0 .. 7] ] /= [ f2 r | r <- [0 .. 7] ]
    && (3 :: Integer) ^ (8 :: Int) > 2 ^ (8 :: Int)
  where
    f1 = fieldFromList (replicate 8 1)
    f2 = fieldFromList (replicate 8 2)

-- | The two-comparison-per-region tournament: compare depths 0 vs 1, then
-- the winner vs 2, with a single-peaked chooser (utility −|d − target|).
-- Returns the recovered field.
tournamentRecover :: (Int -> Int) -> [Int]
tournamentRecover target = [ pick r | r <- [0 .. 7] ]
  where
    pick r =
      let better a b = if abs (a - target r) <= abs (b - target r) then a else b
          w1 = better 1 0   -- ties break toward the deeper arm (single-peaked: no ties off-peak)
      in better 2 w1

-- | LAW (choices identify the field): for ANY target field, the
-- two-comparison tournament recovers it exactly — 16 pairwise picks fully
-- determine all 3^8 possibilities. The user trains the influence policy by
-- deciding, never by describing.
lawTournamentIdentifiesField :: [Int] -> Bool
lawTournamentIdentifiesField ds =
  tournamentRecover tau == [ tau r | r <- [0 .. 7] ]
  where tau = fieldFromList ds
