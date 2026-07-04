{- |
Module      : SixFour.Spec.SpineRing
Description : DECISION OF RECORD — the Morton gene. The octree spine's algebra is the PRODUCT ring (ℤ/2^k)³ (three independent 2-adic axes x, y, t), NOT an 8-adic ring. Morton interleaving is demoted to what it provably is: a CHART — a truncation-compatible bijection of rooted trees (spec/exploration/ModelAlgebra.hs, lawMortonIsTreeIso) that is not a ring homomorphism (lawMortonIsNotRingHom). At tree level the two spines are the same object; at ring level the choice is real, and this module proves it is FORCED by axis identity.

The forcing argument, each step a law below:

  1. The product ring carries three orthogonal AXIS IDEMPOTENTS e_x + e_y + e_t = 1
     ('lawAxisIdempotentsResolveIdentity') — the ring can say "the t axis" internally.
  2. Both 8-adic candidates are LOCAL rings and cannot: ℤ/2^{3k} (what mod-8^k Morton
     truncation actually is) has only the trivial idempotents 0 and 1
     ('lawMortonRingHasOnlyTrivialIdempotents', exhaustive); the unramified alternative
     W(𝔽₈) is local by theory (cited, not computed — see HONEST BOUNDARY).
  3. SixFour NEEDS to say "the t axis": V2.1 locks x,y to one shared linear metric while
     t is weighted at the per-frame palette delta, per-axis training is its own Spec
     module, and dropping t entirely IS the V2.1 GIF collapse. t-only coarsening in the
     product is an ideal quotient — honest algebra ('lawTCollapseKernelIsIdealInProduct',
     'lawTCoarseningIsRingHom').
  4. Transported through the Morton chart, the same kernel is not even an additive
     subgroup ('lawTCollapseKernelNotAdditiveInChart') and, from depth 2 on, matches
     NO ideal of the Morton-index ring ('lawTCollapseIsNoIdealOfMortonRing', all
     ideals enumerated): on the 8-adic side the time-collapse is a bit-mask, forever
     chart-level ('lawTMaskIsChartLevelOnly'), never a quotient. THE GENE TURNS ON AT
     DEPTH 2 — at depth 1 the t-bit is the top bit and dropping it is honestly a ring
     quotient; the first carry across an interleaved digit group forces the choice.
  5. The product filtration is three independent pyramids: axes coarsen independently
     and transitively ('lawAxesCoarsenIndependently') — 16³↔…↔256³ per axis, or per ONE
     axis, which the single-index truncation mod 8^j can never do (it coarsens all three
     axes in lockstep).

By the SES reading, a choice = where a gene lives: this gene is AXIS IDENTITY, and it
lives only in the product. The 8-adic tree survives as a VIEW (the Morton chart into
byte addresses — GIF frame indices, Documents filenames), which is exactly how the code
already uses it (Morton cells are addresses, never multiplied).

HONEST BOUNDARY: W(𝔽₈) (the honest unramified 8-adic integers) is not computed here;
its locality (unique maximal ideal (2), no nontrivial idempotents) is standard theory.
The exhaustive checks below cover ℤ/2^{3k}, which is what "truncate the Morton index
mod 8^k" literally produces. Provenance: deep-research wf_10d20158-707 (model-as-algebra
survey) via spec/exploration/ModelAlgebra.hs; see "SixFour.Spec.RingReduction" for the
per-axis reduction algebra this module's spine choice keeps compatible.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.SpineRing
  ( -- * The product ring (ℤ/2^k)³ — the spine algebra of record
    Triple
  , pAdd
  , pMul
  , pOne
  , axisIdempotents
    -- * The Morton chart (a tree isomorphism, deliberately NOT a ring map)
  , morton
  , unmorton
  , maskT
    -- * Per-axis coarsening (the t-collapse is the V2.1 time-axis drop)
  , coarsenT
  , tCollapseKernel
  , tCollapseKernelChart
  , mortonRingIdeals
    -- * Laws
  , lawAxisIdempotentsResolveIdentity
  , lawMortonRingHasOnlyTrivialIdempotents
  , lawMortonIsChart
  , lawMortonNotAdditive
  , lawTCollapseKernelIsIdealInProduct
  , lawTCoarseningIsRingHom
  , lawTCollapseKernelNotAdditiveInChart
  , lawTCollapseIsNoIdealOfMortonRing
  , lawTMaskIsChartLevelOnly
  , lawAxesCoarsenIndependently
  ) where

import Data.List (nub, sort)

-- | A point of the product ring @(ℤ/2^k)³@: per-axis 2-adic coordinates @(x, y, t)@.
-- The axes are NOT interchangeable in SixFour (x,y share one linear metric; t is
-- palette-delta-weighted), and this representation is the algebra that can say so.
type Triple = (Integer, Integer, Integer)

modK :: Int -> Integer -> Integer
modK k n = n `mod` (2 ^ k)

-- | Componentwise addition in @(ℤ/2^k)³@.
pAdd :: Int -> Triple -> Triple -> Triple
pAdd k (a, b, c) (d, e, f) = (modK k (a + d), modK k (b + e), modK k (c + f))

-- | Componentwise multiplication in @(ℤ/2^k)³@.
pMul :: Int -> Triple -> Triple -> Triple
pMul k (a, b, c) (d, e, f) = (modK k (a * d), modK k (b * e), modK k (c * f))

-- | The multiplicative identity @(1,1,1)@.
pOne :: Triple
pOne = (1, 1, 1)

-- | The three orthogonal axis idempotents @e_x, e_y, e_t@ — the product ring's internal
-- names for its axes. No local ring has these; that is the whole decision.
axisIdempotents :: [Triple]
axisIdempotents = [(1, 0, 0), (0, 1, 0), (0, 0, 1)]

-- | The Morton chart at depth k: interleave the axis bits into one index in @[0, 8^k)@.
-- Bit i of x lands at position 3i, of y at 3i+1, of t at 3i+2.
morton :: Int -> Triple -> Integer
morton k (x, y, t) =
  sum [ bitOf x i * 2 ^ (3 * i) + bitOf y i * 2 ^ (3 * i + 1) + bitOf t i * 2 ^ (3 * i + 2)
      | i <- [0 .. k - 1] ]
  where bitOf n i = (n `div` 2 ^ i) `mod` 2

-- | The inverse chart: de-interleave a Morton index back to per-axis coordinates.
unmorton :: Int -> Integer -> Triple
unmorton k n = (gather 0, gather 1, gather 2)
  where gather o = sum [ ((n `div` 2 ^ (3 * i + o)) `mod` 2) * 2 ^ i | i <- [0 .. k - 1] ]

-- | t-only coarsening to depth j: keep x and y at full depth, truncate t mod 2^j.
-- At j = 0 this drops the time axis entirely — the V2.1 GIF collapse.
coarsenT :: Int -> Triple -> Triple
coarsenT j (x, y, t) = (x, y, t `mod` 2 ^ j)

-- | The kernel of the full t-collapse (j = 0) inside the product ring at depth k:
-- @{(0,0,t)}@ — an ideal (componentwise ideals are ideals of the product).
tCollapseKernel :: Int -> [Triple]
tCollapseKernel k = [ (0, 0, t) | t <- [0 .. 2 ^ k - 1] ]

-- | The same kernel transported through the Morton chart into ℤ/2^{3k}.
tCollapseKernelChart :: Int -> [Integer]
tCollapseKernelChart k = map (morton k) (tCollapseKernel k)

-- | Every ideal of the Morton-index ring ℤ/2^{3k} (all are principal, generated by the
-- divisors 2^i), listed as element sets — the complete stock against which the
-- transported kernel is checked and found missing.
mortonRingIdeals :: Int -> [[Integer]]
mortonRingIdeals k =
  [ sort (nub [ (c * 2 ^ i) `mod` m | c <- [0 .. m - 1] ]) | i <- [0 .. 3 * k] ]
  where m = 2 ^ (3 * k)

-- | LAW (axis identity exists in the product): the three axis idempotents are
-- orthogonal (@e_i · e_j = 0@ for i ≠ j), idempotent (@e_i² = e_i@), and resolve the
-- identity (@e_x + e_y + e_t = 1@) — at every depth.
lawAxisIdempotentsResolveIdentity :: Int -> Bool
lawAxisIdempotentsResolveIdentity k =
  foldr (pAdd k) (0, 0, 0) axisIdempotents == pOne
    && and [ pMul k e e == e | e <- axisIdempotents ]
    && and [ pMul k e f == (0, 0, 0)
           | (i, e) <- zip [0 :: Int ..] axisIdempotents
           , (j, f) <- zip [0 :: Int ..] axisIdempotents, i /= j ]

-- | LAW (axis identity cannot exist on the 8-adic side): ℤ/2^{3k} — the ring the
-- Morton index actually lives in under mod-8^k truncation — is local: its only
-- idempotents are 0 and 1, checked exhaustively. A ring with no nontrivial idempotents
-- has no internal name for "the t axis".
lawMortonRingHasOnlyTrivialIdempotents :: Int -> Bool
lawMortonRingHasOnlyTrivialIdempotents k =
  [ e | e <- [0 .. m - 1], (e * e) `mod` m == e ] == [0, 1]
  where m = 2 ^ (3 * k)

-- | LAW (the chart is faithful at tree level): Morton is a bijection
-- @(ℤ/2^k)³ ↔ [0, 8^k)@ with exact inverse, and it commutes with simultaneous
-- truncation: @morton (x mod 2^j, y mod 2^j, t mod 2^j) == morton (x,y,t) mod 8^j@.
-- The 8-adic tree and the product tree are the SAME rooted tree.
lawMortonIsChart :: Int -> Bool
lawMortonIsChart k = bijective && truncCompatible
  where
    dom  = [ (x, y, t) | x <- [0 .. 2 ^ k - 1], y <- [0 .. 2 ^ k - 1], t <- [0 .. 2 ^ k - 1] ]
    imgs = map (morton k) dom
    bijective =
      length (nub imgs) == 8 ^ k
        && all (\v -> 0 <= v && v < 8 ^ k) imgs
        && all (\p -> unmorton k (morton k p) == p) dom
    truncCompatible =
      and [ morton k (x `mod` 2 ^ j, y `mod` 2 ^ j, t `mod` 2 ^ j)
              == morton k (x, y, t) `mod` 8 ^ j
          | (x, y, t) <- dom, j <- [0 .. k] ]

-- | LAW (the chart is not algebra): Morton is not additive — carries propagate
-- per-axis in the product but across interleaved positions in the index.
lawMortonNotAdditive :: Bool
lawMortonNotAdditive =
  morton 3 (1, 0, 0) + morton 3 (1, 0, 0) /= morton 3 (2, 0, 0)

-- | LAW (the t-collapse is honest algebra in the product): its kernel {(0,0,t)} is an
-- IDEAL — closed under addition and under multiplication by EVERY ring element,
-- checked exhaustively at depth k. Quotienting by it is a ring construction.
lawTCollapseKernelIsIdealInProduct :: Int -> Bool
lawTCollapseKernelIsIdealInProduct k =
  and [ pAdd k a b `elem` kern | a <- kern, b <- kern ]
    && and [ pMul k r a `elem` kern | r <- ring, a <- kern ]
  where
    kern = tCollapseKernel k
    ring = [ (x, y, t) | x <- [0 .. 2 ^ k - 1], y <- [0 .. 2 ^ k - 1], t <- [0 .. 2 ^ k - 1] ]

-- | LAW (per-axis coarsening is a ring homomorphism): @coarsenT j@ preserves both
-- operations into the mixed-depth product @(ℤ/2^k)² × (ℤ/2^j)@.
lawTCoarseningIsRingHom :: Int -> Int -> Triple -> Triple -> Bool
lawTCoarseningIsRingHom k j a b =
  j > k
    || (coarsenT j (pAdd k a b) == mixAdd (coarsenT j a) (coarsenT j b)
         && coarsenT j (pMul k a b) == mixMul (coarsenT j a) (coarsenT j b))
  where
    mixAdd (p, q, r) (s, u, v) = (modK k (p + s), modK k (q + u), (r + v) `mod` 2 ^ j)
    mixMul (p, q, r) (s, u, v) = (modK k (p * s), modK k (q * u), (r * v) `mod` 2 ^ j)

-- | LAW (the same kernel dies in the chart): transported through Morton, the
-- t-collapse kernel is not even closed under addition in ℤ/2^{3k} (witness at k = 2:
-- 4 + 4 = 8 escapes {0,4,32,36}) — so it is a fortiori the kernel of no ring map.
lawTCollapseKernelNotAdditiveInChart :: Bool
lawTCollapseKernelNotAdditiveInChart =
  not (and [ (a + b) `mod` m `elem` kc | a <- kc, b <- kc ])
  where
    kc = tCollapseKernelChart 2
    m  = 2 ^ (6 :: Int)

-- | LAW (no ideal of the Morton ring does the job, DEPTH ≥ 2): the transported kernel
-- equals NONE of the ideals of ℤ/2^{3k} — enumerated completely, since every ideal of
-- ℤ/2^m is principal on a divisor. On the 8-adic side the time-collapse is not a
-- quotient of rings at all.
--
-- THE GENE TURNS ON AT DEPTH 2: at k = 1 the t-bit is the TOP bit of the index, so
-- dropping it is honestly @mod 2^{3k-1}@ — a ring quotient (the transported kernel
-- {0,4} IS the ideal (4) of ℤ/8). A one-level spine cannot distinguish the product
-- from the 8-adic ring; the first CARRY across an interleaved digit group (depth 2)
-- is what forces the choice. Stated for k ≥ 2 accordingly.
lawTCollapseIsNoIdealOfMortonRing :: Int -> Bool
lawTCollapseIsNoIdealOfMortonRing k =
  k < 2 || sort (tCollapseKernelChart k) `notElem` mortonRingIdeals k

-- | The t-mask on Morton indices: keep every x and y bit, zero the t bits at depths
-- ≥ j. What the time-collapse IS on the 8-adic side: a bit-mask, defined directly on
-- index bits, with no ring structure in sight.
maskT :: Int -> Int -> Integer -> Integer
maskT k j n =
  sum [ keep o i * ((n `div` 2 ^ (3 * i + o)) `mod` 2) * 2 ^ (3 * i + o)
      | i <- [0 .. k - 1], o <- [0, 1, 2] ]
  where keep o i = if o == 2 && i >= j then 0 else 1

-- | LAW (chart-level equivalence of the two descriptions): the direct bit-mask equals
-- the transport of per-axis coarsening through the chart,
-- @maskT k j == morton k . coarsenT j . unmorton k@, exhaustively.
lawTMaskIsChartLevelOnly :: Int -> Bool
lawTMaskIsChartLevelOnly k =
  and [ maskT k j n == morton k (coarsenT j (unmorton k n))
      | n <- [0 .. 8 ^ k - 1], j <- [0 .. k] ]

-- | LAW (three independent pyramids): per-axis truncations commute across axes and
-- compose transitively within an axis — the product filtration is the product of
-- per-axis scale pyramids, coarsenable one axis at a time.
lawAxesCoarsenIndependently :: Int -> Triple -> Bool
lawAxesCoarsenIndependently k (x, y, t) =
  and [ cx i (coarsenT j p) == coarsenT j (cx i p) | i <- ds, j <- ds ]
    && and [ coarsenT j (coarsenT i p) == coarsenT (min i j) p | i <- ds, j <- ds ]
  where
    p  = (modK k x, modK k y, modK k t)
    ds = [0 .. k]
    cx i (a, b, c) = (a `mod` 2 ^ i, b, c)
