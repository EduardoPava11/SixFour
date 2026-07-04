{- |
Module      : SixFour.Spec.LabBleed
Description : WE CAN GENERATE EQUATIONS — the RGB→Lab (opponent) conversion as DATA, with variable distance at different scales and enough BLEED to generate compression and entropy, all exact. The conversion equations are generated from a coefficient matrix and law-checked against the pointwise function ('lawOpponentEquationsMatchFunction') — ready for Codegen emission to Swift/Zig/Python instead of hand-copies per tier. The matrix has determinant 6 = 2·3 ('lawOpponentDetIsSix'): inversion divides by 6, and the 3 is the familiar non-unit — the index-3 sublattice Λ = {L ≡ a+b (mod 3)} story (V2-SKI digest) surfaces here as the exact reason the inverse leaves ℤ[1/2].

VARIABLE DISTANCE AT DIFFERENT SCALES IS FORCED, NOT CHOSEN
('lawMetricDilatesWithCarrier'): the opponent map is linear and pooling is
summation, so a uniform 2×2×2 block pools to 8× its value and the L1 opponent
metric dilates by EXACTLY 8 per rung on the sums carrier. One byte-level
bleed radius ρ IS a whole ladder of radii 8^k·ρ — the per-scale metric family
is a corollary of the carrier, no per-rung tuning exists to get wrong.

BLEED = box quantization at radius ρ (floor-division cells per opponent
axis). Its two products, both exact:
  * COMPRESSION ('lawBleedGeneratesCompression'): a coarser bleed never
    increases index transitions — runs only merge (equal fine cells stay
    equal in any coarser partition, 'lawBleedNestsAcrossScales'), and
    transitions are what LZW charges ("SixFour.Spec.PullField"
    lawInteriorRunsAreFree is the ρ→∞ endpoint of this law).
  * ENTROPY ('lawBleedGeneratesEntropyLedger'): merging bleed cells divides
    the microstate count W exactly — W(fine) = W(coarse) × ∏ within-cell W
    ("SixFour.Spec.PaletteKinetics" chain rule, now DRIVEN by the radius
    knob). The entropy shed by a bleed step is a computable Integer quotient,
    never an estimate.
So ρ is the single knob trading entropy kept against bytes spent, with both
sides of the trade landed as integer arithmetic.

HONEST BOUNDARY: the opponent (L,a,b) is the V2 INTEGER opponent latent
(L = R+G+B, a = R−G, b = R+G−2B — the locked stored-b sign), not CIE L*a*b*;
perceptual uniformity was consciously traded for byte-exactness in the
Eisenstein round. The L1 cell metric is the box quantizer's own metric —
the d6/energy metric family lives in "SixFour.Spec.Dim6" and friends; this
module gates the scale/bleed algebra, not perceptual color science.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.LabBleed
  ( -- * The generated conversion equations (coefficients as data)
    opponentRows
  , opponentEquations
  , applyRows
  , opponentDet
    -- * The scale-dilated metric and the bleed quantizer
  , l1Opp
  , bleedCell
    -- * Laws
  , lawOpponentEquationsMatchFunction
  , lawOpponentDetIsSix
  , lawMetricDilatesWithCarrier
  , lawBleedNestsAcrossScales
  , lawBleedGeneratesCompression
  , lawBleedGeneratesEntropyLedger
  ) where

import Data.List (nub)

import SixFour.Spec.OctantViews (RGB, opponent)
import SixFour.Spec.PaletteKinetics (microstates)

-- | The conversion as DATA: named coefficient rows over (R, G, B). This is
-- the single source the equations are GENERATED from — Codegen emits these
-- rows, never a hand-written copy.
opponentRows :: [(String, [Integer])]
opponentRows =
  [ ("L", [1, 1, 1])
  , ("a", [1, -1, 0])
  , ("b", [1, 1, -2])
  ]

-- | The generated human/codegen-readable equations, e.g. @L = R + G + B@ —
-- rendered from 'opponentRows', so they cannot drift from the coefficients.
opponentEquations :: [String]
opponentEquations = [ name ++ " = " ++ render row | (name, row) <- opponentRows ]
  where
    render row = dropPlus (concat (zipWith term row ["R", "G", "B"]))
    term 0 _    = ""
    term 1 v    = " + " ++ v
    term (-1) v = " - " ++ v
    term c v    = (if c > 0 then " + " else " - ") ++ show (abs c) ++ v
    dropPlus (' ' : '+' : ' ' : rest) = rest
    dropPlus s                        = s

-- | Apply the coefficient rows to an RGB triple.
applyRows :: RGB -> RGB
applyRows (r, g, b) = (row 0, row 1, row 2)
  where row i = let cs = snd (opponentRows !! i)
                in head cs * r + cs !! 1 * g + cs !! 2 * b

-- | The determinant of the opponent matrix (cofactor expansion, exact).
opponentDet :: Integer
opponentDet = det3 (map snd opponentRows)
  where
    det3 [[a, b, c], [d, e, f], [g, h, i]] =
      a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    det3 _ = error "opponentRows is 3x3 by construction"

-- | The L1 metric on opponent triples — the box quantizer's own metric.
l1Opp :: RGB -> RGB -> Integer
l1Opp (l1, a1, b1) (l2, a2, b2) = abs (l1 - l2) + abs (a1 - a2) + abs (b1 - b2)

-- | The bleed quantizer at radius ρ: floor-division cells per opponent axis.
-- Two colors bleed together iff they share a cell.
bleedCell :: Integer -> RGB -> (Integer, Integer, Integer)
bleedCell rho (l, a, b) = (l `div` rho, a `div` rho, b `div` rho)

-- | LAW (the equations are generated, not asserted): the coefficient rows,
-- the rendered equations, and the pointwise 'opponent' function agree — and
-- the rendered strings are pinned so Codegen output is deterministic.
lawOpponentEquationsMatchFunction :: [Integer] -> Bool
lawOpponentEquationsMatchFunction raw =
  applyRows (r, g, b) == opponent (r, g, b)
    && opponentEquations == ["L = R + G + B", "a = R - G", "b = R + G - 2B"]
  where [r, g, b] = take 3 (raw ++ repeat 0)

-- | LAW: det = 6 = 2·3 — the inverse divides by 6; the 2 is a unit of
-- ℤ[1/2], the 3 is NOT (the index-3 sublattice Λ boundary made numeric).
lawOpponentDetIsSix :: Bool
lawOpponentDetIsSix = opponentDet == 6

-- | LAW (variable distance per scale is FORCED): pooling a uniform 2×2×2
-- block multiplies opponent values by 8 (linearity over the sums carrier),
-- and the L1 metric is homogeneous — so the metric dilates by EXACTLY 8 per
-- rung: d(8·u, 8·v) == 8 · d(u, v). One byte radius ρ is the whole ladder
-- 8^k·ρ.
lawMetricDilatesWithCarrier :: [Integer] -> Bool
lawMetricDilatesWithCarrier raw =
  l1Opp (s u) (s v) == 8 * l1Opp u v
    && opponent (s rgb1) == s (opponent rgb1)   -- linearity: pool commutes
  where
    [r1, g1, b1, r2, g2, b2] = take 6 (raw ++ repeat 0)
    rgb1 = (r1, g1, b1)
    u = opponent rgb1
    v = opponent (r2, g2, b2)
    s (x, y, z) = (8 * x, 8 * y, 8 * z)

-- | LAW (bleeds nest): if ρ' = m·ρ then equal ρ-cells are equal ρ'-cells —
-- the coarser bleed is a coarsening of the finer partition (floor-division
-- composes), so the scale family is a filtration, never a re-shuffle.
lawBleedNestsAcrossScales :: Integer -> Integer -> [Integer] -> Bool
lawBleedNestsAcrossScales rhoRaw mRaw raw =
  bleedCell rho u /= bleedCell rho v
    || bleedCell (m * rho) u == bleedCell (m * rho) v
  where
    rho = 1 + abs rhoRaw `mod` 16
    m = 2 + abs mRaw `mod` 4
    [r1, g1, b1, r2, g2, b2] = take 6 (raw ++ repeat 0)
    u = opponent (r1, g1, b1)
    v = opponent (r2, g2, b2)

-- | LAW (bleed generates compression): quantizing an index stream by a
-- coarser bleed NEVER increases the number of transitions — runs only merge,
-- and transitions are what LZW charges.
lawBleedGeneratesCompression :: Integer -> Integer -> [Integer] -> Bool
lawBleedGeneratesCompression rhoRaw mRaw raw =
  transitions (cells (m * rho)) <= transitions (cells rho)
  where
    rho = 1 + abs rhoRaw `mod` 16
    m = 2 + abs mRaw `mod` 4
    stream = triples (take 48 (raw ++ repeat 0))
    triples (x : y : z : rest) = opponent (x, y, z) : triples rest
    triples _ = []
    cells p = map (bleedCell p) stream
    transitions xs = length (filter id (zipWith (/=) xs (drop 1 xs)))

-- | LAW (bleed generates entropy, exactly): merging bleed cells divides the
-- microstate count W exactly — W(fine cells) == W(coarse totals) × ∏ over
-- coarse cells of W(fine counts within). The entropy shed by one bleed step
-- is the Integer quotient; the chain rule of PaletteKinetics driven by ρ.
lawBleedGeneratesEntropyLedger :: Integer -> Integer -> [Integer] -> Bool
lawBleedGeneratesEntropyLedger rhoRaw mRaw raw =
  microstates fineCounts
    == microstates coarseTotals
       * product [ microstates [ n | (fc, n) <- zip fineCells fineCounts
                                   , coarsen fc == cc ]
                 | cc <- coarseCells ]
  where
    rho = 1 + abs rhoRaw `mod` 8
    m = 2 + abs mRaw `mod` 3
    stream = triples (take 24 (raw ++ repeat 0))
    triples (x : y : z : rest) = opponent (x, y, z) : triples rest
    triples _ = []
    fineCells = nub (map (bleedCell rho) stream)
    fineCounts = [ toInteger (length (filter ((== fc) . bleedCell rho) stream))
                 | fc <- fineCells ]
    coarsen (l, a, b) = (l `div` m, a `div` m, b `div` m)  -- cell-level coarsening
    coarseCells = nub (map coarsen fineCells)
    coarseTotals = [ sum [ n | (fc, n) <- zip fineCells fineCounts, coarsen fc == cc ]
                   | cc <- coarseCells ]
