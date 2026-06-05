{- |
Module      : SixFour.Spec.CellShapes
Description : Golden cell-mask geometry for the GRID HUD primitives (ring / disc / ring-band).

The source of truth for the @CellShapes@ Swift primitive — the closed drawing
vocabulary the capture HUD renders with (GRID §5). Two families:

  * __The 64-tick ring endpoint table__ (@ringTickEndpoints@). Each diversity-gauge
    tick @k@ terminates at a single cell, computed once here as
    @cell(cx + R·sin θ, cy − R·cos θ)@ with @θ = 2πk/64@ (k=0 at top, clockwise).
    The renderer indexes this table instead of recomputing @atan2@ for every cell —
    fixing the audited drift ("θ→cell recomputed live, no precomputed golden table").

  * __Disc / ring-band masks__ (@inDisc@ / @inAnnulus@), the shutter + gear geometry,
    consistent with the shutter closure proven in 'SixFour.Spec.Lattice'
    (@disc r=15@ + @ring t=2@ = radius 17 = @shutterCells/2@).

== Float portability (why @floor@, not @round@)

The endpoint is @(floor px, floor py)@. @floor@ of an IEEE-754 'Double' is identical
in Haskell and Swift, so the table ports bit-exactly. @round@ would NOT: Haskell
rounds half-to-even, Swift half-away-from-zero. The Swift @selfCheck()@ recomputes
the endpoints from @sin@/@cos@ and asserts equality with the generated table — a live
cross-language IEEE gate.

Laws (see @Properties.CellShapes@): 64 endpoints; the top tick is exactly @(30,1)@
(@sin 0@/@cos 0@ are exact); ticks advance clockwise; all endpoints lie inside the
60×60 sprite; the table is vertically symmetric (row @k@ = row @64−k@); no two
adjacent ticks merge into one cell; and a pinned disc-cell count.
-}
module SixFour.Spec.CellShapes
  ( -- * The 64-tick ring endpoint table
    ringTickRadius
  , cellAtRadius
  , ringTickEndpoint
  , ringTickEndpoints
    -- * Disc / ring-band masks
  , distToCenter
  , inDisc
  , inAnnulus
  , discCells
    -- * Laws
  , lawTickCount
  , lawTickTopExact
  , lawTickClockwise
  , lawTickInBounds
  , lawTickVerticalSymmetry
  , lawTickNoMerge
  , lawDiscCount
  , lawDiscRingClosure
  ) where

import SixFour.Spec.Lattice
  ( ringCells, ringTicks, shutterCells
  , shutterDiscRadiusCells, shutterRingThicknessCells )

-- The ring tick table -------------------------------------------------------

-- | The radius (in atoms, from the sprite centre) at which a gauge tick terminates:
-- one atom inside the rim, @ringCells/2 - 1@. Derived from 'ringCells' so it scales
-- with the gauge (v2.0: @ringCells = 20@ → 9; reproduces 29 for the old 60-atom ring).
ringTickRadius :: Double
ringTickRadius = fromIntegral (ringCells `div` 2) - 1

-- | The cell containing the point at @radius@ and tick angle @k@ on a @side×side@
-- sprite. @θ = 2πk/ringTicks@, measured 0 at top and increasing clockwise;
-- direction @(sin θ, −cos θ)@. @floor@ (not @round@) for exact Haskell↔Swift parity.
cellAtRadius :: Int -> Double -> Int -> (Int, Int)
cellAtRadius side radius k =
  let c0    = fromIntegral side / 2
      theta = 2 * pi * fromIntegral k / fromIntegral ringTicks
      px    = c0 + radius * sin theta
      py    = c0 - radius * cos theta
  in (floor px, floor py)

-- | Tick @k@'s outer endpoint cell on the canonical 60-cell gauge.
ringTickEndpoint :: Int -> (Int, Int)
ringTickEndpoint = cellAtRadius ringCells ringTickRadius

-- | All 64 tick endpoints, in tick order (k = 0 at top, clockwise).
ringTickEndpoints :: [(Int, Int)]
ringTickEndpoints = map ringTickEndpoint [0 .. ringTicks - 1]

-- Disc / ring-band masks ----------------------------------------------------

-- | Euclidean distance from cell @(c,r)@'s centre to the sprite centre, in cells.
-- Cell centre is @(c+0.5, r+0.5)@ — the same convention as Swift @CellGeom.dist@.
distToCenter :: Int -> Int -> Int -> Double
distToCenter side c r =
  let c0 = fromIntegral side / 2
      dx = fromIntegral c + 0.5 - c0
      dy = fromIntegral r + 0.5 - c0
  in sqrt (dx * dx + dy * dy)

-- | Cell @(c,r)@ is inside the filled disc of @radius@ (@d ≤ radius@).
inDisc :: Int -> Double -> Int -> Int -> Bool
inDisc side radius c r = distToCenter side c r <= radius

-- | Cell @(c,r)@ is inside the half-open annulus @(r0, r1]@ (@r0 < d ≤ r1@).
inAnnulus :: Int -> Double -> Double -> Int -> Int -> Bool
inAnnulus side r0 r1 c r = let d = distToCenter side c r in d > r0 && d <= r1

-- | Every cell of a filled disc, row-major.
discCells :: Int -> Double -> [(Int, Int)]
discCells side radius =
  [ (c, r) | r <- [0 .. side - 1], c <- [0 .. side - 1], inDisc side radius c r ]

-- Laws ----------------------------------------------------------------------

-- | The table has exactly @ringTicks@ (64) endpoints.
lawTickCount :: Bool
lawTickCount = length ringTickEndpoints == ringTicks

-- | The top tick (k=0) is exactly @(30, 1)@: @sin 0 = 0@, @cos 0 = 1@ are exact,
-- so there is no float epsilon — @px = 30.0@, @py = 1.0@.
lawTickTopExact :: Bool
lawTickTopExact = ringTickEndpoint 0 == (ringCells `div` 2, 1)

-- | Ticks advance clockwise. At the coarse v2.0 atom (Ø20 ring) adjacent ticks may
-- share a rim cell, so we assert the quarter-turn progression rather than a strict
-- per-tick rightward step: the 3-o'clock tick (k = ringTicks/4) is right of the top,
-- and the 6-o'clock tick (k = ringTicks/2) is below it.
lawTickClockwise :: Bool
lawTickClockwise =
     fst (ringTickEndpoint (ringTicks `div` 4)) > fst (ringTickEndpoint 0)
  && snd (ringTickEndpoint (ringTicks `div` 2)) > snd (ringTickEndpoint 0)

-- | Every endpoint lies inside the 60×60 sprite, @0 ≤ c,r < ringCells@.
lawTickInBounds :: Bool
lawTickInBounds =
  all (\(c, r) -> c >= 0 && c < ringCells && r >= 0 && r < ringCells) ringTickEndpoints

-- | Vertical-axis symmetry: tick @k@ and tick @64−k@ share a row (cos is even in θ),
-- so the gauge mirrors left↔right. Exact: @py(64−k)@ is the same float as @py(k)@.
lawTickVerticalSymmetry :: Bool
lawTickVerticalSymmetry =
  and [ snd (ringTickEndpoint k) == snd (ringTickEndpoint (ringTicks - k))
      | k <- [1 .. ringTicks `div` 2 - 1] ]

-- | The tick arc is GAP-FREE: consecutive ticks are the same cell or 8-adjacent —
-- the coverage arc never jumps a hole. (v2.0: at the Ø20 atom ring the rim holds
-- ~56 cells for 64 frames, so adjacent frames MAY merge into one fat-pixel cell;
-- the old "≥ 1 clear cell between every tick" is geometrically impossible at the
-- atom resolution and is replaced by this contiguity invariant.)
lawTickNoMerge :: Bool
lawTickNoMerge =
  and [ let (c0, r0) = ringTickEndpoint k
            (c1, r1) = ringTickEndpoint ((k + 1) `mod` ringTicks)
        in abs (c1 - c0) <= 1 && abs (r1 - r0) <= 1
      | k <- [0 .. ringTicks - 1] ]

-- | Pinned golden: a radius-3 disc on a 7×7 sprite covers exactly 29 cells.
lawDiscCount :: Bool
lawDiscCount = length (discCells 7 3) == 29

-- | The disc + ring band close to the shutter radius (consistent with
-- 'SixFour.Spec.Lattice'): @discRadius + ringThickness = shutterCells / 2@.
lawDiscRingClosure :: Bool
lawDiscRingClosure =
  shutterDiscRadiusCells + shutterRingThicknessCells == shutterCells `div` 2
