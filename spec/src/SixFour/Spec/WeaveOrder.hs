{- |
Module      : SixFour.Spec.WeaveOrder
Description : THE TEMPORAL WEAVE — ordering the rung frames is the user's simplest creative act, and this module makes it exact: a weave word is an ORDERED COMPOSITION of the 320 cs GIF window into rung frames (64→1 unit, 32→2, 16→4 base-frame units of 5 cs), every weave word is GIF89a-legal because the GCE delay is per-frame ('lawWeaveIsGifRepresentable'), every weave word of the same window integrates IDENTICAL color-time ('lawWeaveColorTimeConserved' — the "three paths" 1×16 = 2×32 = 4×64 = any mix are equal by partition invariance of the measure), and the ORDER ITSELF is invisible to every conserved marginal ('lawOrderIsInvisibleToTheMeasure') — which is precisely why the shutter must RECORD it ("SixFour.Spec.CaptureRecord") or it is gone. The S/K/I reading is landed literally: a small combinator term algebra in which @S x y z → x z (y z)@ with @x=16³, y=32³, z=64³@ reduces to @16³ 64³ (32³ 64³)@ — S DUPLICATES the fine substrate (the one measured signal both coarser views are K-images of, "SixFour.Spec.MixSKI"), and an n-layer S-tower costs 2^n substrate references ('lawSTowerCostsExponential') while the semantic K-chain saturates at ladder height 2 (washes compose, MixSKI 'SixFour.Spec.MixSKI.lawSectionFactorsThroughChain') — syntax is bottomless, semantics is 2 rungs deep, so depth beyond the ladder buys DUPLICATION (compute, the gene-economy S-packet) not new views, and extra layers are only worth their cost when each layer carries a DIFFERENT learned section.

== The block arithmetic (the user's mechanic, exact)

At the shipped cadence (64 frames @ 20 fps = 320 cs, @Native/src/palette16.zig
s4_ladder_delay_cs@) the timeline quantum is one 5 cs unit. A rung-k frame
occupies @2^k@ units ('unitsOf' = 'SixFour.Spec.ColorTime.poolDepth'):

  * one 16³ frame = 4 units — the same span as @[32,32]@, @[32,64,64]@,
    @[64,32,64]@, @[64,64,32]@, or @[64,64,64,64]@: exactly SIX orders per
    4-unit block ('lawBlockHasSixWeaves'), counted by the composition
    recurrence @f(n) = f(n-1) + f(n-2) + f(n-4)@ ('weaveCount',
    'lawCountMatchesEnumeration').
  * @32:16@ is the 2:1 word @[W32,W16]@ and @16:32@ the 1:2 word @[W16,W32]@ —
    same multiset, same delays, same color-time, DIFFERENT word: the order is
    the only thing that distinguishes them, and the measure cannot see it
    ('lawOrderIsInvisibleToTheMeasure', witness multiset @{32,64,64}@ has
    'orderingsOfMultiset' = 3).
  * the whole window admits 'windowWeaveCount' = 2,610,226,433,308,951 weave
    words (≈ 2^51: a 51-bit creative decision space per capture,
    'lawWindowWeaveCountPinned').

== Energy (why the 16 is "low energy")

The coarsest rung is PALETTE-EXACT: 16² = 256 pixels = the 256 GCT slots, so
'pixelsPerColor' 2 = 1 and there is nothing to dither — the 16-view IS the
palette ("SixFour.Spec.V21Pyramid"'s realisable basis). The finer rungs carry
dither pressure 4 (32²) and 16 (64²) pixels per palette colour — and the
light ladder pays for it exactly: dither pressure × color-time factor is
RUNG-INVARIANT, @4^(2−k) · 4^k = 16@ ('lawDitherPressureBalancesColorTime',
via 'SixFour.Spec.ColorTime.lawColorTimeQuartic'). What a rung lacks in
chromatic exposure it owes in dither work; the ladder has no free rung, the
weave only chooses WHERE the energy is spent.

== Honest boundary

Pure combinatorics + the exact 'Rational' color-time measure; the combinator
algebra is syntactic (fuel-bounded normal-order reduction on finite terms).
Semantic saturation of the K-chain is MixSKI's landed law, referenced not
re-proven. GIF realization of a mixed schedule rides the per-frame GCE delay;
the Zig floor's uniform-ladder law @s4_ladder_delay_cs@ is the diagonal of
this module's 'delayCsOf' ('lawDelayMatchesFloorLaw'). GHC-boot-only.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.WeaveOrder
  ( -- * Rung frames and the timeline quantum
    WeaveRung (..)
  , rungIndex
  , sideOf
  , unitsOf
  , delayCsOf
  , windowUnits
  , windowCs
    -- * Weave words — ordered compositions of the window
  , WeaveWord
  , weaveUnits
  , isWeaveOf
  , enumWeaves
  , weaveCount
  , windowWeaveCount
  , blockWeaves
  , orderingsOfMultiset
    -- * Color-time of a weave (the equality of the three paths)
  , colorTimeOfWeave
  , partColorTimePooled
  , partColorTimeLongShutter
    -- * Dither energy
  , pixelsPerColor
    -- * The combinator algebra on rungs
  , Term (..)
  , step
  , reduceFuel
  , countRung
  , sTower
    -- * Laws
  , lawDelayMatchesFloorLaw
  , lawWeaveIsGifRepresentable
  , lawCountMatchesEnumeration
  , lawBlockHasSixWeaves
  , lawWindowWeaveCountPinned
  , lawWeaveColorTimeConserved
  , lawPartPathsEqualColorTime
  , lawOrderIsInvisibleToTheMeasure
  , lawOrderCarriesInformation
  , lawCoarsestIsPaletteExact
  , lawDitherPressureBalancesColorTime
  , lawSExpandsToTheWeaveReading
  , lawSDuplicatesTheSubstrate
  , lawKForgetsTheFine
  , lawIIsFree
  , lawSTowerCostsExponential
  ) where

import Data.List (sort)

import SixFour.Spec.ColorTime
  ( Seconds, poolDepth, coarseSide, colorTimeOfWindow, shutterAtRung )

-- ─────────────────────────────────────────────────────────────────────────────
-- Rung frames and the timeline quantum
-- ─────────────────────────────────────────────────────────────────────────────

-- | A frame of one of the three prime resolutions. The ladder index is
-- 'rungIndex' (0 = finest), matching "SixFour.Spec.ColorTime".
data WeaveRung = W64 | W32 | W16
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | The rung's ladder index k: @W64 → 0@, @W32 → 1@, @W16 → 2@ — the ONE
-- integer of the ladder unification (coarsening, pooling, stops).
rungIndex :: WeaveRung -> Int
rungIndex = fromEnum

-- | The rung's spatial side (64, 32, 16) — 'coarseSide' of its index.
sideOf :: WeaveRung -> Int
sideOf = coarseSide . rungIndex

-- | Timeline units a rung frame occupies: @2^k@ base-frame units of 5 cs.
-- One 16³ frame is 4 units deep = 2 × 32³ = 4 × 64³ — the user's block
-- arithmetic, and exactly 'poolDepth' of the rung index.
unitsOf :: WeaveRung -> Int
unitsOf = fromInteger . poolDepth . rungIndex

-- | The GIF89a GCE delay of a rung frame, in centiseconds: 5·'unitsOf'
-- (64 → 5, 32 → 10, 16 → 20).
delayCsOf :: WeaveRung -> Int
delayCsOf p = baseDelayCs * unitsOf p

-- | The 5 cs timeline quantum (one 64-rung frame at 20 fps).
baseDelayCs :: Int
baseDelayCs = 5

-- | The shipped burst window in units: 64 (× 5 cs = 'windowCs').
windowUnits :: Int
windowUnits = 64

-- | The shipped burst window in centiseconds: 320 (= @S4_WINDOW_CS@,
-- @Native/src/palette16.zig@).
windowCs :: Int
windowCs = baseDelayCs * windowUnits

-- ─────────────────────────────────────────────────────────────────────────────
-- Weave words
-- ─────────────────────────────────────────────────────────────────────────────

-- | An ordered composition of a timeline span into rung frames. The ORDER is
-- the content; the multiset is what the measure sees.
type WeaveWord = [WeaveRung]

-- | Total units a word occupies.
weaveUnits :: WeaveWord -> Int
weaveUnits = sum . map unitsOf

-- | Does the word fill exactly n units?
isWeaveOf :: Int -> WeaveWord -> Bool
isWeaveOf n w = weaveUnits w == n

-- | Every weave word of exactly n units (first frame first). Exponential in
-- n — enumeration is for the small-n laws; counting is 'weaveCount'.
enumWeaves :: Int -> [WeaveWord]
enumWeaves n
  | n < 0     = []
  | n == 0    = [[]]
  | otherwise = [ p : w
                | p <- [W64, W32, W16]
                , unitsOf p <= n
                , w <- enumWeaves (n - unitsOf p) ]

-- | The number of weave words of n units — the composition recurrence for
-- parts {1,2,4}: @f(n) = f(n−1) + f(n−2) + f(n−4)@, memoised on a lazy list.
weaveCount :: Int -> Integer
weaveCount n
  | n < 0     = 0
  | otherwise = table !! n
  where
    table = map f [0 :: Int ..]
    f 0 = 1
    f m = get (m - 1) + get (m - 2) + get (m - 4)
    get k | k < 0     = 0
          | otherwise = table !! k

-- | 'weaveCount' 'windowUnits' — the size of the per-capture decision space.
windowWeaveCount :: Integer
windowWeaveCount = weaveCount windowUnits

-- | The six fills of one 4-unit block (the span of a single 16³ frame).
blockWeaves :: [WeaveWord]
blockWeaves = enumWeaves 4

-- | Distinct orderings of a word's MULTISET: the multinomial
-- @n! / ∏ cᵣ!@ — how many words the measure cannot tell apart.
orderingsOfMultiset :: WeaveWord -> Integer
orderingsOfMultiset w =
  fact (length w) `div` product [ fact (count r) | r <- [W64, W32, W16] ]
  where
    count r = length (filter (== r) w)
    fact m  = product [1 .. toInteger m]

-- ─────────────────────────────────────────────────────────────────────────────
-- Color-time of a weave
-- ─────────────────────────────────────────────────────────────────────────────

-- | The color-time a rung frame integrates when POOLED from the base burst:
-- @2^k@ base exposures of Δ₀ each — the shipped capture path (one burst,
-- rungs derived by exact u64 adds).
partColorTimePooled :: Seconds -> WeaveRung -> Seconds
partColorTimePooled d0 p = colorTimeOfWindow (replicate (unitsOf p) d0)

-- | The color-time of the same frame shot as ONE long exposure filling its
-- slot: a single shutter of @2^k · Δ₀@ — the optical path (the LOOM's
-- independent exposures, @Capture/MultiScaleLadder.swift@).
partColorTimeLongShutter :: Seconds -> WeaveRung -> Seconds
partColorTimeLongShutter d0 p =
  colorTimeOfWindow [shutterAtRung d0 (rungIndex p)]

-- | Total color-time of a weave word (pooled reading): the measure of its
-- whole window.
colorTimeOfWeave :: Seconds -> WeaveWord -> Seconds
colorTimeOfWeave d0 = colorTimeOfWindow . concatMap (\p -> replicate (unitsOf p) d0)

-- ─────────────────────────────────────────────────────────────────────────────
-- Dither energy
-- ─────────────────────────────────────────────────────────────────────────────

-- | Dither pressure of rung k: pixels per GCT colour, @(side_k)² / 256@ —
-- 16 for 64², 4 for 32², 1 for 16².
pixelsPerColor :: Int -> Int
pixelsPerColor k = sq (coarseSide k) `div` 256
  where sq s = s * s

-- ─────────────────────────────────────────────────────────────────────────────
-- The combinator algebra on rungs
-- ─────────────────────────────────────────────────────────────────────────────

-- | Applicative combinator terms over rung generators. The intended reading
-- (grounded in "SixFour.Spec.CombinatorExactSequence" / "SixFour.Spec.MixSKI"):
-- @Rung r :@ t@ = "the r-view rendered over substrate t"; K keeps the coarse
-- and forgets the fine; I is the free reversible lift; S is the section that
-- shares ONE substrate between two views.
data Term
  = S
  | K
  | I
  | Rung WeaveRung
  | App Term Term
  deriving (Eq, Show)

-- | One normal-order (leftmost-outermost) reduction step, if any.
step :: Term -> Maybe Term
step (App I x)                 = Just x
step (App (App K x) _)         = Just x
step (App (App (App S f) g) x) = Just (App (App f x) (App g x))
step (App a b) =
  case step a of
    Just a' -> Just (App a' b)
    Nothing -> App a <$> step b
step _ = Nothing

-- | Reduce with fuel (terms here are finite and small; fuel keeps totality
-- obvious). Returns the term when no redex remains or fuel runs out.
reduceFuel :: Int -> Term -> Term
reduceFuel n t
  | n <= 0    = t
  | otherwise = maybe t (reduceFuel (n - 1)) (step t)

-- | Occurrences of a rung generator in a term — the substrate-reference
-- count, i.e. the decode-compute the term owes (each reference is a packet).
countRung :: WeaveRung -> Term -> Int
countRung r (Rung r') = if r == r' then 1 else 0
countRung r (App a b) = countRung r a + countRung r b
countRung _ _         = 0

-- | The n-layer S-tower: @tower 0 = 64³@;
-- @tower (n+1) = S 16³ 32³ (tower n)@ — one combinator, layered.
sTower :: Int -> Term
sTower n
  | n <= 0    = Rung W64
  | otherwise = App (App (App S (Rung W16)) (Rung W32)) (sTower (n - 1))

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws
-- ─────────────────────────────────────────────────────────────────────────────

-- | The bridge to the Zig floor: 'delayCsOf' equals @s4_ladder_delay_cs@'s
-- law @320 / side@ on every rung — 64 → 5, 32 → 10, 16 → 20.
lawDelayMatchesFloorLaw :: Bool
lawDelayMatchesFloorLaw =
  and [ delayCsOf p == windowCs `div` sideOf p | p <- [W64, W32, W16] ]

-- | EVERY weave word is GIF89a-legal: each frame's delay is a positive whole
-- centisecond, and a window-filling word's delays sum to exactly 320 cs. The
-- per-frame GCE delay is what makes MIXED schedules representable — the
-- uniform ladder was never the only legal word.
lawWeaveIsGifRepresentable :: WeaveWord -> Bool
lawWeaveIsGifRepresentable w =
  all ((> 0) . delayCsOf) w
    && (not (isWeaveOf windowUnits w)
          || sum (map delayCsOf w) == windowCs)

-- | The recurrence counts the enumeration, exactly, on checkable sizes.
lawCountMatchesEnumeration :: Int -> Bool
lawCountMatchesEnumeration n =
  let m = max 0 (min 12 (abs n))
  in toInteger (length (enumWeaves m)) == weaveCount m

-- | One 16³-frame span (4 units) admits exactly SIX orders:
-- [16], [32,32], [32,64,64], [64,32,64], [64,64,32], [64,64,64,64].
lawBlockHasSixWeaves :: Bool
lawBlockHasSixWeaves =
  length blockWeaves == 6
    && sort blockWeaves
         == sort [ [W16]
                 , [W32, W32]
                 , [W32, W64, W64]
                 , [W64, W32, W64]
                 , [W64, W64, W32]
                 , [W64, W64, W64, W64] ]

-- | The full window's decision space, pinned: 2,610,226,433,308,951 weave
-- words (≈ 2^51.2) — the size of the ordering gene the network learns.
lawWindowWeaveCountPinned :: Bool
lawWindowWeaveCountPinned = windowWeaveCount == 2610226433308951

-- | THE EQUALITY OF THE PATHS: every weave word of the same span integrates
-- the SAME total color-time, @n · Δ₀@ — 1×16 = 2×32 = 4×64 = any mixed order.
-- Partition invariance of the color-time measure, nothing else.
lawWeaveColorTimeConserved :: Seconds -> WeaveWord -> WeaveWord -> Bool
lawWeaveColorTimeConserved d0 a b =
  weaveUnits a /= weaveUnits b
    || colorTimeOfWeave d0 a == colorTimeOfWeave d0 b

-- | Per frame, the two capture paths agree: pooling @2^k@ base exposures
-- (the shipped burst) and one long @2^k·Δ₀@ shutter (the LOOM's independent
-- exposure) integrate identical color-time.
lawPartPathsEqualColorTime :: Seconds -> Bool
lawPartPathsEqualColorTime d0 =
  and [ partColorTimePooled d0 p == partColorTimeLongShutter d0 p
      | p <- [W64, W32, W16] ]

-- | THE ORDER IS INVISIBLE TO THE MEASURE: any two words with the same
-- multiset agree in units, delay multiset, and color-time. Witnessed by the
-- user's 2:1 vs 1:2 pair — @[W32,W16]@ vs @[W16,W32]@ — and quantified over
-- any permutation pair.
lawOrderIsInvisibleToTheMeasure :: Seconds -> WeaveWord -> WeaveWord -> Bool
lawOrderIsInvisibleToTheMeasure d0 a b =
  sort a /= sort b
    || ( weaveUnits a == weaveUnits b
           && sort (map delayCsOf a) == sort (map delayCsOf b)
           && colorTimeOfWeave d0 a == colorTimeOfWeave d0 b )

-- | …and yet the order is REAL information: the single block multiset
-- {32,64,64} admits 3 distinct words, and the 2:1 / 1:2 pair are distinct
-- words the previous law proves measure-identical. This is the exact reason
-- the shutter must persist the weave word ("SixFour.Spec.CaptureRecord"):
-- what the sums cannot carry, the record must.
lawOrderCarriesInformation :: Bool
lawOrderCarriesInformation =
  orderingsOfMultiset [W32, W64, W64] == 3
    && [W32, W16] /= [W16, W32]
    && lawOrderIsInvisibleToTheMeasure 1 [W32, W16] [W16, W32]

-- | The 16 is palette-exact: 256 pixels for 256 GCT slots — dither pressure
-- 1, nothing to invent. The user's "low energy" rung, exactly.
lawCoarsestIsPaletteExact :: Bool
lawCoarsestIsPaletteExact =
  pixelsPerColor 2 == 1 && sideOf W16 * sideOf W16 == 256

-- | ENERGY BALANCE: dither pressure × the light-ladder color-time factor is
-- RUNG-INVARIANT — @4^(2−k) · 4^k = 16@ for every rung. The fine rung's
-- dither debt is exactly the coarse rung's chromatic credit; the weave
-- reallocates energy, it never creates or destroys it.
lawDitherPressureBalancesColorTime :: Bool
lawDitherPressureBalancesColorTime =
  and [ toInteger (pixelsPerColor k) * (4 ^ k) == 16 | k <- [0 .. 2] ]

-- | The user's expansion, verbatim: @S 16³ 32³ 64³ → 16³ 64³ (32³ 64³)@ —
-- one step of the S-rule, with the three resolutions in the three slots.
lawSExpandsToTheWeaveReading :: Bool
lawSExpandsToTheWeaveReading =
  step (App (App (App S (Rung W16)) (Rung W32)) (Rung W64))
    == Just (App (App (Rung W16) (Rung W64))
                 (App (Rung W32) (Rung W64)))

-- | S DUPLICATES the substrate: the fine 64³ occurs once before and twice
-- after the S-step — the algebraic face of "the three streams are K-images
-- of ONE signal", and the packet the gene-compute economy charges for.
lawSDuplicatesTheSubstrate :: Bool
lawSDuplicatesTheSubstrate =
  let t  = App (App (App S (Rung W16)) (Rung W32)) (Rung W64)
      t' = reduceFuel 1 t
  in countRung W64 t == 1 && countRung W64 t' == 2

-- | K keeps the coarse and forgets the fine: @K 16³ 64³ → 16³@ — the
-- surjection of the exact sequence, at the weave level.
lawKForgetsTheFine :: Bool
lawKForgetsTheFine =
  step (App (App K (Rung W16)) (Rung W64)) == Just (Rung W16)

-- | I is free: it passes any term through unchanged and duplicates nothing
-- (substrate counts are preserved) — the reversible lift costs zero packets.
lawIIsFree :: Bool
lawIIsFree =
  and [ step (App I t) == Just t
          && countRung W64 (reduceFuel 1 (App I t)) == countRung W64 t
      | t <- [Rung W64, sTower 2] ]

-- | HOW DEEP CAN ONE COMBINATOR GO: an n-layer S-tower fully reduces to a
-- term holding exactly 2^n references to the fine substrate. Syntactic depth
-- is unbounded but costs exponentially; the semantic K-chain saturates at
-- ladder height 2 (MixSKI: washes compose) — so layers beyond the ladder
-- height buy duplication, not new views.
lawSTowerCostsExponential :: Bool
lawSTowerCostsExponential =
  and [ countRung W64 (reduceFuel 4096 (sTower n)) == 2 ^ n
      | n <- [0 .. 6] ]
