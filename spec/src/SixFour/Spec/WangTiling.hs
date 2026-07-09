{- |
Module      : SixFour.Spec.WangTiling
Description : THE SCROLL's substrate — the Jeandel–Rao aperiodic Wang tiling as a random-access
              oracle in exact ℤ[φ] arithmetic, its 11 tiles read as the 11 landed S\/K\/I ops
              (the tiling IS the state machine), the gene as an ATTENTION row over those ops
              (modulates expression, never the schedule), the boot-resolve reveal ladder, and
              the tube's slice-of-4 (pour-group) schedule.

THE SCROLL (2026-07-08): a procedurally generated, INFINITE, NEVER-REPEATING tube of 64²
frames played in slices of 4 (the pour group — four fine frames = one coarse frame,
@docs\/UI-FORM-FOLLOWS-FUNCTION.md@ THE DESIGN). The user scrolls the tube; coarse rungs
materialize first and finer rungs where the user lingers; random access is mandatory (we
never know if\/when a slice is needed). This module pins the substrate as four theorems-first
layers:

== 1. The tile set (SYNTAX, theorem-guaranteed)

The 11-tile \/ 4-horizontal-color \/ 5-vertical-color Jeandel–Rao set T — Jeandel & Rao,
/An aperiodic set of 11 Wang tiles/, arXiv:1506.06492 (Advances in Combinatorics 2021:1),
Fig 3, = Labbé's T0 (arXiv:1903.06137 eq. (6)). A Wang tile is @(w,e,s,n)@ — WEST, EAST,
SOUTH, NORTH; horizontal colors live on w\/e, vertical on s\/n, SEPARATE alphabets. The set
is aperiodic (Thm 3) and minimal BOTH ways: no aperiodic Wang set has ≤ 10 tiles (Thm 1)
and none has < 4 colors (their ref [7]) — 'lawElevenTiles' \/ 'lawFourColors' pin the
citation constants. (T′, the 4-vertical-color variant, collapses 'Grade4' ↦ 'Grade0'; we
carry T because the toral oracle below emits T.)

== 2. The oracle (random access, exact, no floats)

Labbé, /Markov partitions for toral ℤ²-rotations featuring Jeandel-Rao Wang shift and model
sets/, arXiv:1903.06137 (Annales Henri Lebesgue 4 (2021) 283–324, doi 10.5802\/ahl.73):
the minimal subshift X ⊂ Ω₀ is the coding of the ℤ²-translation @R^n(x) = x + n@ on the
torus ℝ²\/Γ₀, Γ₀ = ⟨(φ,0), (1,φ+3)⟩, by the 24-atom polygonal partition P₀ (11 letters).
So @tile(m,n)@ = the atom containing @seed + (m,n)@ reduced into the fundamental domain
@[0,φ) × [0,φ+3)@ — O(1), no search, no context: THE SCROLL's random access. Edge-matching
is AUTOMATIC by construction (Prop 8.1: the west color of @(m+1,n)@ and the east color of
@(m,n)@ read the same Y-atom), which is exactly what 'lawOracleWindowsValid' re-verifies as
the QuickCheck keystone.

__Partition provenance__: the atom vertices are transcribed EXACTLY (ℚ(φ) coordinates)
from Labbé's companion code, the @slabbe@ package v0.8.0, @slabbe\/arXiv_1903_06137.py@
(@jeandel_rao_wang_shift_partition@ — 24 atoms, pairwise disjoint, total volume φ(φ+3) =
4φ+1), which also independently re-confirms the 11 quadruples. The transcription was
cross-gated three ways before landing: (i) 3000 random exact points agree with Labbé's
independent float @torus_to_code@ branch code, (ii) random 8×8 windows at coordinates up to
±10⁹ are edge-consistent, (iii) empirical tile frequencies over a 60×60 window match the
exact frequencies of arXiv:1903.06137 Prop 9.1 (ν(t7)=5\/(12φ+14) ≈ .1496 down to
ν(t2)=1\/(18φ+10) ≈ .0256). 'lawGoldenWindowPinned' carries an 8×8 golden window derived by
that independent exact-rational twin.

__Arithmetic__: every quantity is @a + bφ@ with RATIONAL a, b ('QPhi'), φ² = φ + 1. Sign
and floor are exact integer decisions (sign of @U + V√5@ by comparing @U²@ with @5V²@;
'floorQPhi' brackets by integer square root then corrects by exact sign) — NO floats,
cross-device bit-exact, Tier-2-portable by hand like every other floor kernel.

__Seed genericity__: 'seedPoint' = (1\/3, 1\/5). Every atom boundary is a line @x = c@,
@y = c@, @y − φx = c@ or @y − φ²x = c@ with c ∈ ℤ[φ] (the singular directions of Thm 1(iv)),
and the ℤ²-orbit only shifts coordinates by ℤ[φ] elements — so boundary incidence would need
1\/3 ∈ ℤ[φ] (x\/y lines), 1\/5 − φ\/3 ∈ ℤ[φ] or 1\/5 − φ²\/3 ∈ ℤ[φ] (slanted lines), all false
by denominators. The orbit NEVER touches a boundary; membership is strict-interior and total.

__Honest boundary__: the oracle emits the MINIMAL subshift X ⊊ Ω₀ (Labbé Thm 1) — the
measure-1, uniquely-ergodic core of the Jeandel-Rao shift. Tilings in Ω₀ \\ X exist that
this oracle can never emit; for THE SCROLL minimality is the FEATURE (every pattern recurs
with positive frequency — the tube is never-repeating yet statistically homogeneous).

== 3. The state machine (tiles = the 11 landed ops)

Daniel's brief verbatim: /define the tile operations so that we can have a STATE MACHINE and
a layer of ATTENTION atop — but it's just the GENE MAPPING/. The op alphabet already exists
in the repo and counts exactly 11 — @{I} ∪ {K_x,K_y,K_t} ∪ {S_x,S_y,S_t} ∪ {S_xy,S_xt,S_yt}
∪ {S_xyt}@ = 1+3+3+3+1, the "SixFour.Spec.OctantViews" Walsh–Hadamard grading 1+3+3+1 with
the mixed pairs split out ('opsCanonical'). Concretely each op acts on the 8-band vector:
@I@ = identity (the work-0 splitting, "SixFour.Spec.CombinatorExactSequence" @iSplit@);
@K_a@ = annihilate exactly the a-containing bands (the per-axis surjection — the SAME kill
set as the doubled axis wash of "SixFour.Spec.AxisSKI", 'lawKKillsItsBands'); @S_A@ = the
SECTION that rewrites exactly band A, whose zero-gene choice is @zeroDetail@ (the floor —
'lawSFloorIsZeroDetail' delegates @sSection@). The FSM reading is the paper's own transducer
reading: horizontal colors = the 4 'Carrier' states (a tile is a transition @w → e@),
vertical colors = the 5 'Grade' letters it reads\/writes — so a row of the tiling is a legal
op PIPELINE ('lawTilingRowIsLegalPipeline') and a column is a legal GRADE path
('lawTilingColumnIsGradePath'), both for free from edge-matching.

__DECISION OF RECORD ('lawOpAssignmentPinned')__ — the tile→op table 'opOf': every
grade-RAISING tile carries an S (t0 @+3@ → @S_xyt@, t1 @+2@ → @S_xy@, t10 @+1@ → @S_xt@),
K sits only on grade-LOWERING tiles (t4 → @K_x@, t6 → @K_y@, t9 → @K_t@), @I@ sits on t7 —
the MOST FREQUENT tile (ν(t7) = 5\/(12φ+14), Prop 9.1): the free op fires most often, the
"SixFour.Spec.PacketEconomy" floor. The flat tiles carry the pure\/remaining sections
(t3 → @S_x@, t5 → @S_y@, t8 → @S_t@, t2 → @S_yt@). The assignment is a pinned CHOICE (the
counts 1+3+3+3+1 = 11 motivate it; no theorem forces the pairing) — the laws pin its
structure so it cannot drift silently.

== 4. Gene = attention (SEMANTICS, modulates — never mutates)

A 'Gene' is the θ_up-shaped 21-word Q16 vector (7 detail bands × 3 channels, the
@Train\/CaptureGene.swift@ layout; bands ordered as the nonempty 'axisSubsets').
'attentionOf' derives the 11-op weight row deterministically from committed band ENERGIES
(exact ℤ → ℚ, no floats): each @S_A@ earns its band's energy (the gene spends S-packets
where it learned detail — "SixFour.Spec.AxisSKI" @lawAxisWashKillsItsBands@ makes band ↔
axis-op accountability a theorem), each @K_a@ earns the energy its bands LEFT ON THE TABLE
(a band the gene does not spend on is a band K may pool), @I@ keeps the uniform floor. One
Q16 unit of floor is added everywhere so the zero gene is EXACTLY uniform
('lawZeroGeneIsUniform') and the row is a strict distribution in exact rationals
('lawAttentionIsDistribution'). THE KEY LAW ('lawAttentionModulatesNotMutates'): the tile
schedule is theorem-fixed SYNTAX — 'scheduledOps' emits the SAME op sequence for every gene;
the gene only reweights how much compute each op expresses when its tile fires (decode-depth
= rung = halt = packet = ATTENTION, the "SixFour.Spec.BudgetHead" seam: an advisory schedule
that can only choose a coarser rung of the same ladder, never a different tiling).

== 5. Boot resolve (the √N crystallize schedule) + the tube slices

At boot the pyramid must EARN its rungs: the 16² is statistically trustworthy after its
first full pour (4 banked ticks), the 32² after its own 4 realizes (tick 8), the 64² last
(tick 16) — the "SixFour.Spec.ColorTimeDisplay" pour played in REVERSE. 'revealTick' invents
NO constant: @revealTick p = framesPerRealize W16 · unitsOf (bootMirror p)@, and the √N
reciprocity @revealTick p · unitsOf p = 16@ (constant!) is 'lawBootResolveIsPourInverse',
every reveal landing on an aligned realize boundary of everything already revealed. The tube
is served in slices of 'sliceRows' = @framesPerRealize W16@ = 4 rows ('sliceWindow'), each
addressable independently ('lawSliceIsRandomAccess') and never vertically periodic
('lawSliceNeverRepeats', the bounded witness of Thm 3 aperiodicity).

Visual substrate seams (device side, not re-proven here): @s4_synth_burst@ seeds a
deterministic burst per slice, @s4_cube_expand_rung@ materializes coarse → fine where the
user lingers; genes warp the palette. GHC-boot-only: base + the landed spec modules.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.WangTiling
  ( -- * Exact ℤ[φ] arithmetic (the no-float substrate)
    QPhi (..)
  , phiQ
  , qFromInt
  , qAdd
  , qSub
  , qMul
  , signQPhi
  , floorQPhi
    -- * The Jeandel–Rao tile set T (arXiv:1506.06492 Fig 3 = Labbé T0)
  , Carrier (..)
  , Grade (..)
  , Tile (..)
  , jrTiles
  , edgeMatchH
  , edgeMatchV
  , windowValid
    -- * The toral oracle (arXiv:1903.06137) — random-access tile(m,n)
  , TorusPoint
  , seedPoint
  , reduceTorus
  , tileIndexAt
  , tileAt
  , oracleWindow
  , goldenWindow8
    -- * The state machine — tiles are transitions over carriers
  , TileOp (..)
  , opsCanonical
  , opOfIndex
  , opOf
  , fsmStep
  , runPipeline
  , BandVec
  , bandsOfBlock
  , opBands
    -- * Gene = attention (modulates expression, never the schedule)
  , Gene (..)
  , geneWords
  , zeroGene
  , geneBandEnergy
  , attentionOf
  , scheduledOps
    -- * Boot resolve — the √N crystallize schedule
  , bootMirror
  , revealTick
  , revealAt
    -- * The tube schedule — slices of 4 (the pour group)
  , sliceRows
  , sliceWidth
  , sliceWindow
  , sliceOps
    -- * Laws — tile set + oracle
  , lawElevenTiles
  , lawFourColors
  , lawOracleDeterministic
  , lawOracleWindowsValid
  , lawNonperiodicWitness
  , lawGoldenWindowPinned
    -- * Laws — state machine
  , lawEdgeMatchIsCompositionLegal
  , lawTilingRowIsLegalPipeline
  , lawTilingColumnIsGradePath
  , lawOpsAreElevenDistinct
  , lawOpAssignmentPinned
  , lawKKillsItsBands
  , lawSFloorIsZeroDetail
    -- * Laws — gene = attention
  , lawAttentionIsDistribution
  , lawZeroGeneIsUniform
  , lawAttentionModulatesNotMutates
    -- * Laws — boot resolve + tube
  , lawBootResolveMonotone
  , lawBootResolveIsPourInverse
  , lawBootResolveTerminates
  , lawSliceIsRandomAccess
  , lawSliceNeverRepeats
  ) where

import Data.List (elemIndex, isPrefixOf, nub, sort)
import Data.Maybe (fromMaybe, isJust)
import Data.Ratio (denominator, numerator, (%))

import SixFour.Spec.OctantViews (Axis (..), Block, axisSubsets, bandOf, blockFromList)
import SixFour.Spec.CombinatorExactSequence (iSplit, kSurj, sSection, zeroDetail)
import SixFour.Spec.OctreeCell (OctBand (..))
import SixFour.Spec.WeaveOrder (WeaveRung (..), sideOf, unitsOf)
import SixFour.Spec.ColorTimeDisplay
  ( Tick, displayPeriodTicks, framesPerRealize, realizesAt )

-- ─────────────────────────────────────────────────────────────────────────────
-- Exact ℤ[φ] / ℚ(φ) arithmetic — no floats anywhere
-- ─────────────────────────────────────────────────────────────────────────────

-- | A number @a + b·φ@ with rational coefficients, φ = (1+√5)\/2, φ² = φ + 1.
-- The ONLY numeric carrier of the oracle: sign and floor are exact integer
-- decisions, so the emitted tiling is cross-device bit-exact by construction.
data QPhi = QPhi Rational Rational
  deriving (Eq, Show)

-- | φ itself: @0 + 1·φ@.
phiQ :: QPhi
phiQ = QPhi 0 1

-- | Embed an integer: @n + 0·φ@.
qFromInt :: Integer -> QPhi
qFromInt n = QPhi (fromInteger n) 0

-- | Exact addition.
qAdd :: QPhi -> QPhi -> QPhi
qAdd (QPhi a b) (QPhi c d) = QPhi (a + c) (b + d)

-- | Exact subtraction.
qSub :: QPhi -> QPhi -> QPhi
qSub (QPhi a b) (QPhi c d) = QPhi (a - c) (b - d)

-- | Exact multiplication through φ² = φ + 1:
-- @(a+bφ)(c+dφ) = ac+bd + (ad+bc+bd)φ@.
qMul :: QPhi -> QPhi -> QPhi
qMul (QPhi a b) (QPhi c d) = QPhi (a * c + b * d) (a * d + b * c + b * d)

-- Sign of U + V·√5 for integers U, V — pure integer case analysis (U² vs 5V²;
-- equality is impossible unless both vanish, √5 being irrational).
signRoot5 :: Integer -> Integer -> Int
signRoot5 0 0 = 0
signRoot5 u 0 = fromIntegral (signum u)
signRoot5 0 v = fromIntegral (signum v)
signRoot5 u v
  | u > 0 && v > 0 = 1
  | u < 0 && v < 0 = -1
  | u > 0 = if u * u > 5 * v * v then 1 else -1     -- v < 0
  | otherwise = if 5 * v * v > u * u then 1 else -1 -- u < 0, v > 0

-- Common-denominator integer view: a + bφ = (A + Bφ)/d with d > 0.
integerView :: QPhi -> (Integer, Integer, Integer)
integerView (QPhi a b) =
  let d = lcm (denominator a) (denominator b)
  in (numerator a * (d `div` denominator a), numerator b * (d `div` denominator b), d)

-- | Exact sign (−1, 0, +1): @a + bφ = (2A + B + B√5)\/(2d)@, decided by 'signRoot5'.
signQPhi :: QPhi -> Int
signQPhi q = let (bigA, bigB, _) = integerView q in signRoot5 (2 * bigA + bigB) bigB

-- Integer square root (Newton, exact, total on non-negatives).
isqrtI :: Integer -> Integer
isqrtI n
  | n < 2 = max n 0
  | otherwise = go n
  where
    go x = let y = (x + n `div` x) `div` 2 in if y >= x then x else go y

-- | Exact floor: bracket @V√5@ by 'isqrtI', then correct the candidate by one
-- exact 'signRoot5' test — the guessed integer is off by at most one, and the
-- final decision is a theorem, not an approximation.
floorQPhi :: QPhi -> Integer
floorQPhi q =
  let (bigA, bigB, d) = integerView q
      p = 2 * bigA + bigB
      v = bigB
      w = 2 * d
      s = if v >= 0 then isqrtI (5 * v * v) else negate (isqrtI (5 * v * v)) - 1
      n0 = (p + s) `div` w
  in if signRoot5 (p - (n0 + 1) * w) v >= 0 then n0 + 1 else n0

-- ─────────────────────────────────────────────────────────────────────────────
-- The Jeandel–Rao tile set T
-- ─────────────────────────────────────────────────────────────────────────────

-- | The HORIZONTAL edge alphabet (4 values) — the op-carrier types, i.e. the
-- STATES of the tile state machine (a tile is a transition @w → e@). Four is
-- minimal: no aperiodic Wang set exists with fewer than 4 colors
-- (arXiv:1506.06492, ref [7]) — 'lawFourColors'.
data Carrier = Car0 | Car1 | Car2 | Car3
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | The VERTICAL edge alphabet (5 values in set T) — the band-grade letters a
-- tile reads (south) and writes (north) in the paper's transducer reading.
-- (The 4-color minimal variant T′ collapses 'Grade4' ↦ 'Grade0'.)
data Grade = Grade0 | Grade1 | Grade2 | Grade3 | Grade4
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | A Wang tile @(w,e,s,n)@ — west, east, south, north (arXiv:1506.06492 §2.1).
-- Horizontal and vertical alphabets are SEPARATE; a west color never needs to
-- equal a north color even where the integers coincide.
data Tile = Tile
  { tileW :: Carrier  -- ^ West edge color (the FSM state consumed).
  , tileE :: Carrier  -- ^ East edge color (the FSM state produced).
  , tileS :: Grade    -- ^ South edge color (the grade letter read).
  , tileN :: Grade    -- ^ North edge color (the grade letter written).
  }
  deriving (Eq, Show)

-- | The 11 Jeandel–Rao tiles t0..t10 in Labbé's order (arXiv:1903.06137 eq. (6),
-- converted @(r,t,l,b) → (w,e,s,n) = (l,r,b,t)@; identical to the Fig 3 set of
-- arXiv:1506.06492). Aperiodic (Thm 3); minimal in tile count (Thm 1: ≤ 10 is
-- impossible) and in color count.
jrTiles :: [Tile]
jrTiles =
  [ mk 2 2 1 4  -- t0
  , mk 2 2 0 2  -- t1
  , mk 3 1 1 1  -- t2
  , mk 3 1 2 2  -- t3
  , mk 3 3 3 1  -- t4
  , mk 3 0 1 1  -- t5
  , mk 0 0 1 0  -- t6
  , mk 0 3 2 1  -- t7
  , mk 1 0 2 2  -- t8
  , mk 1 1 4 2  -- t9
  , mk 1 3 2 3  -- t10
  ]
  where mk w e s n = Tile (toEnum w) (toEnum e) (toEnum s) (toEnum n)

-- | Horizontal adjacency legality: @a@ immediately west of @b@ needs
-- @east(a) == west(b)@ (arXiv:1506.06492 §2.1 matching rule).
edgeMatchH :: Tile -> Tile -> Bool
edgeMatchH a b = tileE a == tileW b

-- | Vertical adjacency legality: @lo@ immediately south of @hi@ needs
-- @north(lo) == south(hi)@.
edgeMatchV :: Tile -> Tile -> Bool
edgeMatchV lo hi = tileN lo == tileS hi

-- | A rectangular window (rows south→north, each row west→east) is valid iff
-- every horizontal and vertical adjacency matches — the finite face of the
-- Wang tiling condition.
windowValid :: [[Tile]] -> Bool
windowValid rows =
     and [ edgeMatchH l r | row <- rows, (l, r) <- zip row (drop 1 row) ]
  && and [ edgeMatchV lo hi | (lorow, hirow) <- zip rows (drop 1 rows)
                            , (lo, hi) <- zip lorow hirow ]

-- ─────────────────────────────────────────────────────────────────────────────
-- The toral oracle — Labbé's 24-atom partition P₀, exact vertices
-- ─────────────────────────────────────────────────────────────────────────────

-- | A point of the fundamental domain @[0,φ) × [0,φ+3)@ of ℝ²\/Γ₀.
type TorusPoint = (QPhi, QPhi)

-- The x tick lattice: 0, φ⁻² = 2−φ, φ⁻¹ = φ−1, 1, φ.
xTicks :: [QPhi]
xTicks = [ QPhi 0 0, QPhi 2 (-1), QPhi (-1) 1, QPhi 1 0, QPhi 0 1 ]

-- The y rows A..F: 0, 1, 2, φ+1, φ+2, φ+3.
yA, yB, yC, yD, yE, yF :: QPhi
yA = QPhi 0 0
yB = QPhi 1 0
yC = QPhi 2 0
yD = QPhi 1 1
yE = QPhi 2 1
yF = QPhi 3 1

vtx :: QPhi -> Int -> TorusPoint
vtx row i = (xTicks !! i, row)

-- The 24 convex atoms (tile letter, CCW vertex list) — transcribed EXACTLY from
-- slabbe v0.8.0 @jeandel_rao_wang_shift_partition@ (vertices reordered CCW; the
-- convex hulls are unchanged). Pairwise disjoint, total volume φ(φ+3) = 4φ+1.
atoms :: [(Int, [TorusPoint])]
atoms =
  [ (0,  [ vtx yA 0, vtx yA 2, vtx yB 2 ])
  , (0,  [ vtx yA 2, vtx yA 3, vtx yB 3 ])
  , (0,  [ vtx yA 3, vtx yA 4, vtx yB 4 ])
  , (1,  [ vtx yA 0, vtx yB 2, vtx yB 0 ])
  , (1,  [ vtx yA 2, vtx yB 3, vtx yB 2 ])
  , (1,  [ vtx yA 3, vtx yB 4, vtx yB 3 ])
  , (2,  [ vtx yC 0, vtx yE 2, vtx yD 0 ])
  , (3,  [ vtx yB 3, vtx yC 4, vtx yE 4, vtx yC 3 ])
  , (4,  [ vtx yC 0, vtx yE 3, vtx yE 2 ])
  , (4,  [ vtx yE 2, vtx yE 3, vtx yF 3 ])
  , (5,  [ vtx yD 0, vtx yE 2, vtx yE 0 ])
  , (5,  [ vtx yE 0, vtx yE 1, vtx yF 1 ])
  , (5,  [ vtx yE 1, vtx yE 2, vtx yF 3 ])
  , (6,  [ vtx yE 0, vtx yF 1, vtx yF 0 ])
  , (6,  [ vtx yE 1, vtx yF 3, vtx yF 1 ])
  , (6,  [ vtx yE 3, vtx yF 4, vtx yF 3 ])
  , (7,  [ vtx yD 3, vtx yE 4, vtx yE 3 ])
  , (7,  [ vtx yE 3, vtx yE 4, vtx yF 4 ])
  , (7,  [ vtx yB 0, vtx yE 3, vtx yC 0 ])
  , (8,  [ vtx yB 2, vtx yE 4, vtx yC 2 ])
  , (9,  [ vtx yB 0, vtx yB 2, vtx yC 2 ])
  , (9,  [ vtx yB 2, vtx yB 3, vtx yC 3 ])
  , (9,  [ vtx yB 3, vtx yB 4, vtx yC 4 ])
  , (10, [ vtx yB 0, vtx yD 3, vtx yE 3 ])
  ]

-- Strict interior of a CCW convex polygon: every edge cross-product positive.
-- Strictness is safe: the generic seed's orbit never touches a boundary.
insideConvex :: [TorusPoint] -> TorusPoint -> Bool
insideConvex poly (px, py) =
  and [ signQPhi (cross a b) > 0 | (a, b) <- zip poly (drop 1 poly ++ take 1 poly) ]
  where
    cross (ax, ay) (bx, by) =
      qSub (qMul (qSub bx ax) (qSub py ay)) (qMul (qSub by ay) (qSub px ax))

-- | The generic seed point p = (1\/3, 1\/5) ∈ ℚ(φ)². Its ℤ²-orbit avoids every
-- atom boundary (see the module header's denominator argument), so 'tileIndexAt'
-- is total and unambiguous. A different generic seed emits a different (equally
-- theorem-valid) tiling of the same minimal subshift.
seedPoint :: TorusPoint
seedPoint = (QPhi (1 / 3) 0, QPhi (1 / 5) 0)

-- | Reduce a plane point into the fundamental domain @[0,φ) × [0,φ+3)@ modulo
-- Γ₀ = ⟨(φ,0), (1,φ+3)⟩: subtract @k₂·(1,φ+3)@ (k₂ = ⌊y\/(φ+3)⌋), then
-- @k₁·(φ,0)@ (k₁ = ⌊x\/φ⌋). O(1) — two exact floors, no search. The needed
-- inverses live in ℚ(φ): 1\/(φ+3) = (4−φ)\/11, 1\/φ = φ−1.
reduceTorus :: TorusPoint -> TorusPoint
reduceTorus (x, y) =
  let k2 = floorQPhi (qMul y (QPhi (4 / 11) ((-1) / 11)))
      x1 = qSub x (qFromInt k2)
      y1 = qSub y (qMul (qFromInt k2) (QPhi 3 1))
      k1 = floorQPhi (qMul x1 (QPhi (-1) 1))
      x2 = qSub x1 (qMul (qFromInt k1) phiQ)
  in (x2, y1)

-- Which atom (tile letter 0..10) contains an in-domain generic point.
atomIndexOf :: TorusPoint -> Int
atomIndexOf p =
  case [ t | (t, poly) <- atoms, insideConvex poly p ] of
    (t : _) -> t
    [] -> error "WangTiling.atomIndexOf: boundary point (non-generic seed?)"

-- | THE ORACLE, index form: the tile letter at cell @(m,n)@ — the atom of
-- @seedPoint + (m,n)@ reduced into the fundamental domain. Random access:
-- O(1), context-free, total for the generic seed, exact for any 'Integer'.
tileIndexAt :: (Integer, Integer) -> Int
tileIndexAt (m, n) =
  atomIndexOf (reduceTorus (qAdd (fst seedPoint) (qFromInt m), qAdd (snd seedPoint) (qFromInt n)))

-- | THE ORACLE: the Jeandel–Rao tile at cell @(m,n)@. Edge-matching with all
-- four neighbours is a THEOREM of the construction (arXiv:1903.06137 Prop 8.1),
-- re-verified by 'lawOracleWindowsValid'.
tileAt :: (Integer, Integer) -> Tile
tileAt = (jrTiles !!) . tileIndexAt

-- | A w×h window anchored at @(m0,n0)@: rows n0..n0+h−1 (south→north), each row
-- m0..m0+w−1 (west→east). Any window is addressable independently.
oracleWindow :: (Integer, Integer) -> Int -> Int -> [[Tile]]
oracleWindow (m0, n0) w h =
  [ [ tileAt (m0 + fromIntegral i, n0 + fromIntegral j) | i <- [0 .. w - 1] ]
  | j <- [0 .. h - 1] ]

-- | The pinned 8×8 golden window at the origin (rows n = 0..7, cols m = 0..7),
-- derived by an INDEPENDENT exact-rational twin of this arithmetic (Python
-- @fractions@ over the same ℤ[φ] sign\/floor algorithms, from the slabbe
-- partition data) — the transcription gate 'lawGoldenWindowPinned' re-derives it.
goldenWindow8 :: [[Int]]
goldenWindow8 =
  [ [0, 0, 0, 1, 1, 0, 0, 0]
  , [9, 9, 9, 10, 3, 9, 9, 9]
  , [7, 3, 10, 4, 3, 10, 3, 8]
  , [5, 7, 4, 5, 7, 4, 3, 10]
  , [5, 6, 6, 6, 6, 6, 7, 4]
  , [0, 1, 1, 1, 1, 1, 0, 0]
  , [9, 10, 3, 8, 7, 3, 9, 9]
  , [10, 4, 3, 10, 2, 8, 7, 3]
  ]

-- ─────────────────────────────────────────────────────────────────────────────
-- The state machine — the 11 tiles as the 11 landed S/K/I ops
-- ─────────────────────────────────────────────────────────────────────────────

-- | One of the 11 landed ops: the identity\/splitting @I@, a per-axis surjection
-- @K_a@ ("SixFour.Spec.AxisSKI"), or a section @S_A@ over a nonempty axis subset
-- ("SixFour.Spec.CombinatorExactSequence" — the gene lives only on S).
data TileOp
  = OpI          -- ^ The splitting: identity on the band vector, work 0.
  | OpK Axis     -- ^ The per-axis surjection: kills the a-containing bands.
  | OpS [Axis]   -- ^ The section over one band: rewrites exactly that band
                 --   (zero-gene choice = @zeroDetail@, the floor).
  deriving (Eq, Show)

-- | The canonical op alphabet, graded 1+3+3+3+1 = 11 — the
-- "SixFour.Spec.OctantViews" Walsh–Hadamard grading with the mixed pairs split
-- out. Order pinned; 'attentionOf' rows index into it.
opsCanonical :: [TileOp]
opsCanonical =
  [ OpI
  , OpK AxX, OpK AxY, OpK AxT
  , OpS [AxX], OpS [AxY], OpS [AxT]
  , OpS [AxX, AxY], OpS [AxX, AxT], OpS [AxY, AxT]
  , OpS [AxX, AxY, AxT]
  ]

-- | The tile → op DECISION OF RECORD, by tile index t0..t10 (see the module
-- header and 'lawOpAssignmentPinned' for the rationale pins).
opOfIndex :: Int -> TileOp
opOfIndex i = table !! i
  where
    table =
      [ OpS [AxX, AxY, AxT]  -- t0  (grade +3: the full section)
      , OpS [AxX, AxY]       -- t1  (grade +2: spatial pair)
      , OpS [AxY, AxT]       -- t2  (flat, rarest tile)
      , OpS [AxX]            -- t3  (flat: pure x refresh)
      , OpK AxX              -- t4  (grade −2)
      , OpS [AxY]            -- t5  (flat: pure y refresh)
      , OpK AxY              -- t6  (grade −1)
      , OpI                  -- t7  (most frequent tile: the free op)
      , OpS [AxT]            -- t8  (flat: pure t refresh)
      , OpK AxT              -- t9  (grade −2)
      , OpS [AxX, AxT]       -- t10 (grade +1: the time-mixing pair)
      ]

-- | The op a tile fires. Total on 'jrTiles' (every oracle output).
opOf :: Tile -> TileOp
opOf t =
  case elemIndex t jrTiles of
    Just i -> opOfIndex i
    Nothing -> error "WangTiling.opOf: not a Jeandel-Rao tile"

-- | One FSM transition: from carrier state @c@, tile @t@ fires iff its west
-- color is @c@, producing its east color — the paper's transducer reading
-- (a tile IS the transition @w → e@ reading s writing n).
fsmStep :: Carrier -> Tile -> Maybe Carrier
fsmStep c t = if tileW t == c then Just (tileE t) else Nothing

-- | Run a row of tiles as an op pipeline from a start carrier: 'Just' the final
-- carrier iff every consecutive hand-off is legal.
runPipeline :: Carrier -> [Tile] -> Maybe Carrier
runPipeline = foldl (\mc t -> mc >>= (`fsmStep` t)) . Just

-- | The 8-entry Walsh–Hadamard band vector, in 'axisSubsets' order (head =
-- coarse\/DC, then the 7 detail bands) — the substrate the ops act on.
type BandVec = [Integer]

-- | The band vector of a 2×2×2 block (delegates "SixFour.Spec.OctantViews"
-- 'bandOf' over 'axisSubsets').
bandsOfBlock :: Block Integer -> BandVec
bandsOfBlock v = map (bandOf v) axisSubsets

-- | The op's CONCRETE action on a band vector: @I@ = identity ('iSplit' is the
-- work-0 splitting); @K_a@ = annihilate exactly the a-containing bands (the
-- "SixFour.Spec.AxisSKI" kill set, 'lawKKillsItsBands'); @S_A@ = rewrite exactly
-- band A with the gene's choice — at the ZERO gene that choice is 'zeroDetail'
-- (the "SixFour.Spec.CombinatorExactSequence" floor, 'lawSFloorIsZeroDetail'),
-- so the floor action writes 0 into its band and touches nothing else.
opBands :: TileOp -> BandVec -> BandVec
opBands OpI bv = bv
opBands (OpK a) bv = [ if a `elem` s then 0 else x | (s, x) <- zip axisSubsets bv ]
opBands (OpS ax) bv = [ if s == ax then 0 else x | (s, x) <- zip axisSubsets bv ]

-- ─────────────────────────────────────────────────────────────────────────────
-- Gene = attention
-- ─────────────────────────────────────────────────────────────────────────────

-- | The θ_up-shaped somatic gene: 21 committed Q16 words — 7 detail bands
-- (nonempty 'axisSubsets', in order) × 3 channels, band-major (the
-- @Train\/CaptureGene.swift@ layout). Weights are derived from COMMITTED Q16
-- integers, honouring the "SixFour.Spec.GeneSimilarity" house rule (equal
-- expression ⇒ equal words ⇒ equal attention row).
newtype Gene = Gene [Integer]
  deriving (Eq, Show)

-- | The 21 words, padded\/truncated to shape (QuickCheck-friendly, like
-- 'blockFromList').
geneWords :: Gene -> [Integer]
geneWords (Gene ws) = take 21 (ws ++ repeat 0)

-- | The zero gene — the deterministic floor (zero-detail section everywhere).
zeroGene :: Gene
zeroGene = Gene (replicate 21 0)

-- The nonempty axis subsets = the 7 detail bands, in canonical order.
detailSubsets :: [[Axis]]
detailSubsets = drop 1 axisSubsets

-- | The gene's L1 energy on one detail band: the sum of |word| over the band's
-- 3 channels. The deterministic, exact spend-signal the attention row reads.
geneBandEnergy :: Gene -> [Axis] -> Integer
geneBandEnergy g s =
  case elemIndex s detailSubsets of
    Just i -> sum (map abs (take 3 (drop (3 * i) (geneWords g))))
    Nothing -> 0

-- One Q16 unit — the uniform floor share every op keeps.
q16One :: Integer
q16One = 65536

-- | THE GENE MAPPING: the 11-op attention row, exact rationals over
-- 'opsCanonical'. Each @S_A@ earns its band's energy; each @K_a@ earns what the
-- a-containing bands left on the table (@Σ_{A∋a} (eMax − e_A)@ — a band the gene
-- does not spend on is a band K may pool); @I@ keeps the floor. One 'q16One'
-- floor everywhere makes the zero gene exactly uniform; normalization is exact.
attentionOf :: Gene -> [Rational]
attentionOf g =
  let es = [ geneBandEnergy g s | s <- detailSubsets ]
      eMax = maximum es
      raw OpI = q16One
      raw (OpS s) = q16One + geneBandEnergy g s
      raw (OpK a) = q16One + sum [ eMax - e | (s, e) <- zip detailSubsets es, a `elem` s ]
      rs = map raw opsCanonical
      total = sum rs
  in map (% total) rs

-- | The gene-facing schedule surface: slice @s@'s op sequence, each op carrying
-- its attention weight. THE SEAM WHERE A BUG COULD LET THE GENE MUTATE THE
-- SCHEDULE — 'lawAttentionModulatesNotMutates' pins that the op sequence (fst)
-- is byte-identical for every gene; only the weights (snd) move. This is the
-- "SixFour.Spec.BudgetHead" discipline: an advisory per-op packet schedule.
scheduledOps :: Gene -> Integer -> [(TileOp, Rational)]
scheduledOps g s =
  let row = attentionOf g
      wOf op = fromMaybe (error "WangTiling.scheduledOps: op outside opsCanonical")
                         (lookup op (zip opsCanonical row))
  in [ (op, wOf op) | t <- concat (sliceWindow s), let op = opOf t ]

-- ─────────────────────────────────────────────────────────────────────────────
-- Boot resolve — the √N crystallize schedule
-- ─────────────────────────────────────────────────────────────────────────────

-- | The boot mirror: the reveal ladder plays the pour ladder in REVERSE — the
-- finest rung waits the coarsest rung's units (W64 ↔ W16, W32 self-mirrored).
bootMirror :: WeaveRung -> WeaveRung
bootMirror W64 = W16
bootMirror W32 = W32
bootMirror W16 = W64

-- | The tick at which rung @p@ becomes statistically trustworthy at boot:
-- @framesPerRealize W16 · unitsOf (bootMirror p)@ — 4 \/ 8 \/ 16 for the 16² \/
-- 32² \/ 64². NO new constant: the 16² earns trust at its FIRST full pour (its
-- 'framesPerRealize' = 4 banked ticks), the 32² after its own 4 realizes
-- (4 × its 'displayPeriodTicks' = 8), the 64² last — the √N reciprocity
-- @revealTick p · unitsOf p = 16@ ('lawBootResolveIsPourInverse').
revealTick :: WeaveRung -> Tick
revealTick p = framesPerRealize W16 * unitsOf (bootMirror p)

-- | The rungs revealed (trustworthy) at tick @t@, coarse-first — the UI's boot
-- crystallize readout. Empty at tick 0: nothing has banked, nothing is shown as
-- trustworthy (honest physics, never an animation constant).
revealAt :: Tick -> [WeaveRung]
revealAt t = [ p | p <- [W16, W32, W64], t >= revealTick p ]

-- ─────────────────────────────────────────────────────────────────────────────
-- The tube schedule — slices of 4 (the pour group)
-- ─────────────────────────────────────────────────────────────────────────────

-- | Rows per tube slice: 'framesPerRealize' 'W16' = 4 — THE POUR group (four
-- fine frames = one coarse frame), never a free constant.
sliceRows :: Int
sliceRows = framesPerRealize W16

-- | Columns per tube slice: 'sideOf' 'W16' = 16 — the coarse palette-basis
-- width (keeps the law windows bounded; the device tube tiles this widthwise).
sliceWidth :: Int
sliceWidth = sideOf W16

-- | Slice @s@ of the tube: the 4-row window at rows @4s..4s+3@ — one coarse
-- frame's worth of fine rows, addressable independently (random access).
sliceWindow :: Integer -> [[Tile]]
sliceWindow s = oracleWindow (0, fromIntegral sliceRows * s) sliceWidth sliceRows

-- | The op sequence slice @s@ fires (row-major over 'sliceWindow') — the
-- SYNTAX the gene's attention row modulates but never mutates.
sliceOps :: Integer -> [TileOp]
sliceOps = map opOf . concat . sliceWindow

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws — tile set + oracle
-- ─────────────────────────────────────────────────────────────────────────────

-- | CITATION CONSTANTS (arXiv:1506.06492 Thm 1): exactly 11 pairwise-distinct
-- tiles — and 11 is MINIMAL, no aperiodic Wang set has ≤ 10 tiles. Also pins
-- that the oracle's letters index this exact list.
lawElevenTiles :: Bool
lawElevenTiles =
     length jrTiles == 11
  && length (nub jrTiles) == 11
  && all (\i -> tileIndexAt (fromIntegral i, 0) `elem` [0 .. 10]) [0 :: Int .. 3]

-- | CITATION CONSTANTS: the horizontal alphabet is EXACTLY the 4 carriers (4 is
-- minimal — no aperiodic set with < 4 colors, arXiv:1506.06492 ref [7]) and the
-- vertical alphabet is exactly the 5 grades of set T.
lawFourColors :: Bool
lawFourColors =
     sort (nub (concatMap (\t -> [tileW t, tileE t]) jrTiles)) == [minBound .. maxBound]
  && sort (nub (concatMap (\t -> [tileS t, tileN t]) jrTiles)) == [minBound .. maxBound]

-- | DETERMINISM + RANDOM ACCESS: the tile at @(m,n)@ recomputes identically and
-- equals the same cell read out of a differently-anchored window — the oracle
-- is context-free (no neighbour is ever consulted), which is what lets THE
-- SCROLL materialize any slice at any time.
lawOracleDeterministic :: (Integer, Integer) -> Bool
lawOracleDeterministic (m, n) =
     tileAt (m, n) == tileAt (m, n)
  && (oracleWindow (m - 1, n - 1) 3 3 !! 1) !! 1 == tileAt (m, n)

-- | THE KEYSTONE: every oracle window is a VALID Wang tiling patch — all
-- horizontal and vertical edges match (arXiv:1903.06137 Prop 8.1 made
-- checkable). This is the rigid gate on the whole transcription: one wrong atom
-- vertex or tile quadruple and random windows violate matching immediately.
lawOracleWindowsValid :: (Integer, Integer) -> Bool
lawOracleWindowsValid p = windowValid (oracleWindow p 4 4)

-- | APERIODICITY WITNESS (bounded): for every candidate period vector with
-- |components| ≤ 2 there is a defect inside the 12×12 origin window. The full
-- statement — NO period whatsoever — is arXiv:1506.06492 Thm 3 (and minimality,
-- arXiv:1903.06137 Thm 1, makes every window recur without ever repeating
-- globally); the law checks the small-period face the tube schedule leans on.
lawNonperiodicWitness :: Bool
lawNonperiodicWitness =
  and [ any (\(m, n) -> tileIndexAt (m, n) /= tileIndexAt (m + v1, n + v2)) probe
      | (v1, v2) <- [(1, 0), (0, 1), (1, 1), (2, 0), (0, 2), (2, 1), (1, 2), (2, 2)] ]
  where probe = [ (m, n) | m <- [0 .. 11], n <- [0 .. 11] ]

-- | THE TRANSCRIPTION GATE: the oracle re-derives the pinned 8×8 golden window
-- ('goldenWindow8', computed by the independent exact-rational twin from the
-- slabbe partition data). Any drift in the atoms, the tiles, the seed or the
-- ℤ[φ] arithmetic breaks this byte-for-byte.
lawGoldenWindowPinned :: Bool
lawGoldenWindowPinned =
  [ [ tileIndexAt (m, n) | m <- [0 .. 7] ] | n <- [0 .. 7] ] == goldenWindow8

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws — state machine
-- ─────────────────────────────────────────────────────────────────────────────

-- | EDGE MATCH = COMPOSITION LEGALITY: for any two tiles (indices mod 11), the
-- horizontal edge match holds iff the FSM can hand @a@'s output carrier to @b@
-- — the tiling's matching rule IS the op pipeline's typing rule.
lawEdgeMatchIsCompositionLegal :: Int -> Int -> Bool
lawEdgeMatchIsCompositionLegal i j =
  let a = jrTiles !! (abs i `mod` 11)
      b = jrTiles !! (abs j `mod` 11)
  in edgeMatchH a b == isJust (fsmStep (tileE a) b)

-- | ANY ORACLE ROW IS A LEGAL PIPELINE: a width-8 row runs end-to-end through
-- 'runPipeline' from its first tile's west carrier — the tiling schedules only
-- well-typed op words (edge-matching horizontally = carrier hand-off).
lawTilingRowIsLegalPipeline :: (Integer, Integer) -> Bool
lawTilingRowIsLegalPipeline p =
  case oracleWindow p 8 1 of
    [row] -> runPipeline (tileW (head row)) row == Just (tileE (last row))
    _ -> False

-- | ANY ORACLE COLUMN IS A LEGAL GRADE PATH: vertically, each tile writes the
-- grade letter the next reads — the transducer's read\/write tape is consistent
-- up the tube (the vertical face of the same matching theorem).
lawTilingColumnIsGradePath :: (Integer, Integer) -> Bool
lawTilingColumnIsGradePath p =
  let col = map head (oracleWindow p 1 8)
  in and [ edgeMatchV lo hi | (lo, hi) <- zip col (drop 1 col) ]

-- | THE OP ALPHABET IS HONESTLY ELEVEN: 'opsCanonical' has 11 pairwise-distinct
-- citizens graded 1 I + 3 K + 3+3+1 S, and they are distinct AS FUNCTIONS — on
-- the witness band vector [1..8] all 11 actions produce pairwise-distinct
-- outputs (no two ops secretly coincide).
lawOpsAreElevenDistinct :: Bool
lawOpsAreElevenDistinct =
     length opsCanonical == 11
  && length (nub opsCanonical) == 11
  && length [ () | OpK _ <- opsCanonical ] == 3
  && length [ () | OpS s <- opsCanonical, length s == 1 ] == 3
  && length [ () | OpS s <- opsCanonical, length s == 2 ] == 3
  && length [ () | OpS s <- opsCanonical, length s == 3 ] == 1
  && length (nub [ opBands o [1 .. 8] | o <- opsCanonical ]) == 11

-- | THE DECISION OF RECORD, pinned so it cannot drift: 'opOf' is a BIJECTION
-- onto 'opsCanonical'; every grade-RAISING tile carries an S (only a section
-- invents detail); every K sits on a grade-LOWERING tile (pooling never raises
-- the written grade); and @I@ sits on t7, the most frequent tile
-- (ν(t7) = 5\/(12φ+14), arXiv:1903.06137 Prop 9.1 — the free op fires most
-- often, the packet economy's floor).
lawOpAssignmentPinned :: Bool
lawOpAssignmentPinned =
     length (nub [ opOfIndex i | i <- [0 .. 10] ]) == 11
  && all (`elem` opsCanonical) [ opOfIndex i | i <- [0 .. 10] ]
  && and [ isS (opOfIndex i) | i <- [0 .. 10], gd i > 0 ]
  && and [ gd i < 0 | i <- [0 .. 10], isK (opOfIndex i) ]
  && opOfIndex 7 == OpI
  where
    gd i = let t = jrTiles !! i in fromEnum (tileN t) - fromEnum (tileS t)
    isS (OpS _) = True
    isS _ = False
    isK (OpK _) = True
    isK _ = False

-- | K'S KILL SET IS AXISSKI'S: on any block's band vector, @K_a@ zeroes exactly
-- the a-containing bands and keeps the rest — and the DOUBLED integer axis wash
-- (the "SixFour.Spec.AxisSKI" operator, restated as the pair-sum block)
-- annihilates the SAME bands while doubling the survivors. Same surjection,
-- same accountability: the gene decomposes by axis.
lawKKillsItsBands :: [Integer] -> Bool
lawKKillsItsBands xs =
     and [ opBands (OpK a) bv == [ if a `elem` s then 0 else bandOf v s | s <- axisSubsets ]
         | a <- axes ]
  && and [ bandOf (washed a) s == (if a `elem` s then 0 else 2 * bandOf v s)
         | a <- axes, s <- axisSubsets ]
  where
    axes = [AxX, AxY, AxT]
    v = blockFromList xs
    bv = bandsOfBlock v
    washed a (x, y, t) = case a of
      AxX -> v (0, y, t) + v (1, y, t)
      AxY -> v (x, 0, t) + v (x, 1, t)
      AxT -> v (x, y, 0) + v (x, y, 1)

-- | S AT THE ZERO GENE CHOOSES THE ZERO DETAIL: applying all seven section
-- floors flattens every detail band to 0 while the coarse survives untouched —
-- and the delegation is direct: "SixFour.Spec.CombinatorExactSequence"'s
-- @sSection@ lifts a coarse value with @zeroDetail@ (@K∘S = id@ on it). A
-- learned θ is a different representative in the same coset; the FLOOR is this.
lawSFloorIsZeroDetail :: [Integer] -> Int -> Bool
lawSFloorIsZeroDetail xs c =
     foldl (flip opBands) bv (map OpS detailSubsets) == take 1 bv ++ replicate 7 0
  && kSurj (sSection c) == c
  && ocDetail (iSplit (sSection c)) == zeroDetail
  where bv = bandsOfBlock (blockFromList xs)

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws — gene = attention
-- ─────────────────────────────────────────────────────────────────────────────

-- | THE ROW IS A DISTRIBUTION, exactly: 11 weights, all strictly positive
-- (every op keeps its floor share), summing to 1 in exact rational arithmetic —
-- never a float, never a rounding residue.
lawAttentionIsDistribution :: [Integer] -> Bool
lawAttentionIsDistribution ws =
  let row = attentionOf (Gene ws)
  in length row == 11 && all (> 0) row && sum row == 1

-- | THE ZERO GENE IS THE UNIFORM FLOOR: no learned detail ⇒ no preference —
-- every op gets exactly 1\/11 (the deterministic-floor face of zero-gene ==
-- floor).
lawZeroGeneIsUniform :: Bool
lawZeroGeneIsUniform = attentionOf zeroGene == replicate 11 (1 % 11)

-- | THE KEY LAW — attention MODULATES, never MUTATES: for any gene, the op
-- sequence 'scheduledOps' emits is byte-identical to the zero gene's (and to
-- the raw 'sliceOps' syntax). The tiling schedule is theorem-fixed; the gene
-- reaches only the weight column. /A layer of attention atop — but it's just/
-- /the gene mapping./
lawAttentionModulatesNotMutates :: [Integer] -> Integer -> Bool
lawAttentionModulatesNotMutates ws s =
  let g = Gene ws
  in map fst (scheduledOps g s) == map fst (scheduledOps zeroGene s)
     && map fst (scheduledOps g s) == sliceOps s

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws — boot resolve + tube schedule
-- ─────────────────────────────────────────────────────────────────────────────

-- | BOOT REVEALS COARSE→FINE AND NEVER RETRACTS: the reveal ticks strictly
-- ascend 16² < 32² < 64², 'revealAt' is a prefix of the coarse-first order, and
-- it is monotone in the tick (once trustworthy, always trustworthy).
lawBootResolveMonotone :: Int -> Bool
lawBootResolveMonotone t =
  let t' = abs t
  in revealTick W16 < revealTick W32
     && revealTick W32 < revealTick W64
     && revealAt t' `isPrefixOf` [W16, W32, W64]
     && all (`elem` revealAt (t' + 1)) (revealAt t')

-- | THE REVEAL IS THE POUR PLAYED BACKWARDS: every reveal tick is an aligned
-- realize boundary of EVERY rung revealed by then; the √N reciprocity
-- @revealTick p · unitsOf p = framesPerRealize W16 · unitsOf W16@ (= 16) holds
-- for all three rungs; each reveal doubles the last; the 16² earns trust at its
-- first full pour and the 32² after its own 4 realizes. Zero new physics — a
-- reveal schedule derived from banked pour counts.
lawBootResolveIsPourInverse :: Bool
lawBootResolveIsPourInverse =
     and [ realizesAt q (revealTick p) | p <- rungs, q <- revealAt (revealTick p) ]
  && and [ revealTick p * unitsOf p == framesPerRealize W16 * unitsOf W16 | p <- rungs ]
  && revealTick W32 == 2 * revealTick W16
  && revealTick W64 == 2 * revealTick W32
  && revealTick W16 == framesPerRealize W16
  && revealTick W32 == 4 * displayPeriodTicks W32
  where rungs = [W64, W32, W16]

-- | BOOT TERMINATES AT A PINNED TICK: all three rungs are revealed at
-- @framesPerRealize W16 · framesPerRealize W16@ = 16 (and stay revealed for
-- every later tick); at tick 0 NOTHING is trustworthy — the crystallize is
-- earned, not animated.
lawBootResolveTerminates :: Int -> Bool
lawBootResolveTerminates t =
     revealTick W64 == framesPerRealize W16 * framesPerRealize W16
  && revealAt (revealTick W64) == [W16, W32, W64]
  && revealAt (max (abs t) (revealTick W64)) == [W16, W32, W64]
  && null (revealAt 0)

-- | SLICES ARE RANDOM-ACCESS AND POUR-SHAPED: slice @s@ computed directly
-- equals the same rows extracted from a double-height window (different access
-- paths agree — no hidden context), and every slice is exactly
-- 'sliceRows' × 'sliceWidth' (4-into-1 pour rows by palette-basis width).
lawSliceIsRandomAccess :: Integer -> Bool
lawSliceIsRandomAccess s =
  let w2 = oracleWindow (0, fromIntegral sliceRows * s) sliceWidth (2 * sliceRows)
  in sliceWindow s == take sliceRows w2
     && sliceWindow (s + 1) == drop sliceRows w2
     && length (sliceWindow s) == sliceRows
     && all ((== sliceWidth) . length) (sliceWindow s)

-- | THE TUBE NEVER REPEATS (bounded witness): for every candidate vertical
-- period up to the pour group (p = 1..4 slices), some slice in the first nine
-- differs from its p-shifted sibling. The unbounded statement is aperiodicity
-- (arXiv:1506.06492 Thm 3): a vertically-periodic tube would be a periodic
-- tiling, which T does not admit.
lawSliceNeverRepeats :: Bool
lawSliceNeverRepeats =
  and [ any (\s -> sliceOps s /= sliceOps (s + p)) [0 .. 8] | p <- [1 .. 4] ]
