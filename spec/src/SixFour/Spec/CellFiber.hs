{- |
Module      : SixFour.Spec.CellFiber
Description : The WHAT axis — the per-Place colour fiber as a bounded join-semilattice.

This is the FIBER half of the base/fiber cell algebra (the spatial BASE lives in
'SixFour.Spec.CellGrid'). A single 'Cell' is the set of OKLab-Q16 'Color's that
several sources have claimed at one 'SixFour.Spec.CellGrid.Place'; it is a bounded
join-semilattice under set union, with '⊥' = the empty claim and '⊕' = 'join' =
'Data.Set.union'.

== NO BLEND. Overlap is detected, never averaged (the product law)

The single most important rule: 'render' NEVER synthesises a colour. A clean cell
shows its owner's colour verbatim; a contested cell (two widgets claimed one Place)
shows a reserved 'contestedSentinel' — a loud, unmistakable marker so a collision
is impossible to miss ("if it happens I want to know"). The colour produced by any
observer is ALWAYS one of: '⊥' ↦ 'neutralColor', a singleton ↦ that exact colour,
or ≥2 ↦ the 'contestedSentinel'. It is never a mixture of the claimants. This is
proven by 'lawNoSynthesis'. ('SixFour.Spec.CellGrid.renderGridAt' adds the opt-in
effect path: a Place flagged as an effect-zone 'shimmer's its claimants on the
20 fps clock instead of showing the sentinel — still never a blend, only ever a
real claimant per tick, proven by 'lawShimmerIsClaimant'.)

== Why provenance is NOT in the carrier (critic hole #1)

The carrier 'Cell' is a @Set Color@. @Color@ is the Q16 OKLab cube, which the
ingestion guard 'ingest' restricts to the finite valid gamut; the displayed
palette has at most @K = 256@ leaves, so a cell ranges over a finite carrier
bounded by @K@ — NOT @K × |Source|@. Ownership/provenance
('SixFour.Spec.CellGrid.Owner' / '.Source') lives on the BASE, never on the value.

GHC-boot-only: base, containers (Data.Set). No QuickCheck (test-suite only).
-}
module SixFour.Spec.CellFiber
  ( -- * The fiber carrier
    Color(..)
  , Cell
    -- * Bounded join-semilattice ops
  , bottom            -- ^ ⊥ = the empty claim (Data.Set.empty)
  , join              -- ^ ⊕ = Data.Set.union
  , (<+>)             -- ^ infix alias for 'join'
  , singletonCell     -- ^ a single claim
  , claims            -- ^ Data.Set.toAscList (the canonical, arrival-free order)
    -- * Contention (you always KNOW; never an error, never a blend)
  , isContested       -- ^ |cell| > 1 : two+ widgets claimed one Place
    -- * The TOTAL ingestion guard (re-establishes the gamut precondition)
  , inGamut           -- ^ Q16 validity predicate (finite, in [0,Q16_ONE]³ box)
  , ingest            -- ^ Maybe-reject NaN / out-of-[0,1]³, else clamp-to-cube
  , clampColor        -- ^ saturating clamp to the valid Q16 box
    -- * Observation (NO blend)
  , neutralColor      -- ^ the ⊥-render anchor (mid-grey L=½, a=b=0) = "clear/unpainted"
  , contestedSentinel -- ^ the reserved loud marker shown at a contested Place
  , render            -- ^ Cell -> Color : ⊥↦neutral, singleton↦self, ≥2↦sentinel
  , shimmerAt         -- ^ Int -> Cell -> Color : the opt-in effect — a REAL claimant per tick
    -- * Laws (predicates; QuickCheck'd in Properties.CellFiber)
  , lawJoinAssoc
  , lawJoinComm
  , lawJoinIdem
  , lawBottomIdentity
  , lawRenderTotal
  , lawRenderSingleton
  , lawRenderBottomNeutral
  , lawNoSynthesis         -- ^ render never invents a colour (the no-blend theorem)
  , lawContestedDetect     -- ^ isContested is exact
  , lawRenderContested     -- ^ contested ⇒ the loud sentinel
  , lawShimmerIsClaimant   -- ^ shimmer only ever shows a real claimant
  , lawIngestGuardsDomain
  , lawCarrierBoundedByK
  ) where

import           Data.Set (Set)
import qualified Data.Set as Set

import SixFour.Spec.ColorFixed   (q16One)

-- | The Q16 OKLab triple. Kept local so the fiber carrier needs no export from
-- SpatialDither.
type Px = (Int, Int, Int)

-- | One OKLab colour in Q16: @(L, a, b)@ each @value · 2^16@.
-- @L ∈ [0, q16One]@ (i.e. [0,1]); @a, b ∈ [-q16One \`div\` 2, q16One \`div\` 2]@.
-- 'Ord' is derived (lexicographic on the Int triple) and IS the canonical
-- arrival-free order for 'claims' — render is a function of the SET, so claim
-- ARRIVAL ORDER is irrelevant (hole #2 closed by the set carrier itself).
newtype Color = Color { unColor :: Px }
  deriving (Eq, Ord, Show)

-- | A cell: the SET of colours claimed at one Place. Join-semilattice carrier.
type Cell = Set Color

-- | ⊥ — the empty claim. 'render' ⊥ = 'neutralColor'.
bottom :: Cell
bottom = Set.empty

-- | ⊕ — the join, set union (idempotent, commutative, associative by Data.Set).
join :: Cell -> Cell -> Cell
join = Set.union

infixl 6 <+>
-- | Infix alias for 'join'.
(<+>) :: Cell -> Cell -> Cell
(<+>) = join

-- | A single claim.
singletonCell :: Color -> Cell
singletonCell = Set.singleton

-- | The claims in canonical ascending order (arrival-free).
claims :: Cell -> [Color]
claims = Set.toAscList

-- | Contention: did TWO+ widgets claim this Place? This is the total, exact
-- "I want to know" predicate — never throws, never blends, just tells you.
-- The BASE companion 'SixFour.Spec.CellGrid.contestedPlaces' lists every such Place.
isContested :: Cell -> Bool
isContested c = Set.size c > 1

-- | Validity: the triple is inside the finite Q16 gamut box.
inGamut :: Color -> Bool
inGamut (Color (l, a, b)) =
     l >= 0 && l <= q16One
  && a >= negate halfQ && a <= halfQ
  && b >= negate halfQ && b <= halfQ
  where halfQ = q16One `div` 2

-- | Saturating clamp into the valid Q16 box.
clampColor :: Color -> Color
clampColor (Color (l, a, b)) =
  Color (clamp 0 q16One l, clamp (negate halfQ) halfQ a, clamp (negate halfQ) halfQ b)
  where halfQ      = q16One `div` 2
        clamp lo hi = max lo . min hi

-- | TOTAL ingestion guard. Input is a real OKLab triple straight off the camera
-- / NN (Double). REJECT (Nothing) iff any channel is NaN/±Inf or out of the
-- @[0,1]×[-½,½]×[-½,½]@ domain (hole #4). Otherwise ROUND half-away-from-zero to
-- Q16 (hole #5) and 'clampColor'. After 'ingest', every 'Color' satisfies 'inGamut'.
ingest :: (Double, Double, Double) -> Maybe Color
ingest (l, a, b)
  | any bad [l, a, b]                 = Nothing   -- NaN / ±Inf reject
  | l < 0 || l > 1                    = Nothing   -- L out of [0,1]
  | a < (-0.5) || a > 0.5             = Nothing   -- a out of [-½,½]
  | b < (-0.5) || b > 0.5             = Nothing   -- b out of [-½,½]
  | otherwise = Just (clampColor (Color (q16 l, q16 a, q16 b)))
  where
    bad x = isNaN x || isInfinite x
    q16 v = let s = v * fromIntegral q16One
            in if s >= 0 then floor (s + 0.5) else ceiling (s - 0.5)

-- | The ⊥-render anchor: mid-grey @L = ½, a = b = 0@. Represents "clear /
-- unpainted"; a fixed gamut-valid colour so 'render' is TOTAL on the empty cell.
neutralColor :: Color
neutralColor = Color (q16One `div` 2, 0, 0)

-- | The reserved CONTESTED marker: a vivid, unmistakable magenta
-- @(L=½, a=+½ max-chroma, b=-¼)@ — gamut-valid but visually screaming, so an
-- accidental two-widget overlap cannot be confused with any tasteful palette
-- colour. Shown by 'render' at any contested Place (the loud default, option c).
contestedSentinel :: Color
contestedSentinel = Color (q16One `div` 2, q16One `div` 2, negate (q16One `div` 4))

-- | Observable colour — NO BLEND. ⊥ ↦ 'neutralColor'; singleton ↦ that exact
-- claim; ≥2 (contested) ↦ the loud 'contestedSentinel'. There is no fold and no
-- arithmetic mixing of claimants: 'render' only ever returns a colour that was
-- actually claimed, the neutral anchor, or the sentinel ('lawNoSynthesis').
render :: Cell -> Color
render c = case claims c of
  []  -> neutralColor
  [x] -> x
  _   -> contestedSentinel

-- | The opt-in OVERLAP EFFECT (used only inside a flagged effect-zone): instead
-- of the loud sentinel, time-multiplex the claimants on the 20 fps clock — show
-- claimant @tick \`mod\` n@. Total (⊥ ↦ neutral); and crucially it shows a REAL
-- claimant every tick, never a synthesised mixture ('lawShimmerIsClaimant'). The
-- conflict is still visible (the cell shimmers) — that is the "cool effect".
shimmerAt :: Int -> Cell -> Color
shimmerAt tick c = case claims c of
  [] -> neutralColor
  cs -> cs !! (tick `mod` length cs)

-- LAWS (semilattice, on the carrier) ----------------------------------------

-- | ⊕ associative. Discharge: Data.Set.union associativity.
lawJoinAssoc :: Cell -> Cell -> Cell -> Bool
lawJoinAssoc x y z = (x <+> y) <+> z == x <+> (y <+> z)

-- | ⊕ commutative. Discharge: Data.Set.union commutativity.
lawJoinComm :: Cell -> Cell -> Bool
lawJoinComm x y = x <+> y == y <+> x

-- | ⊕ idempotent. Discharge: Data.Set.union idempotence.
lawJoinIdem :: Cell -> Bool
lawJoinIdem x = x <+> x == x

-- | ⊥ is the join identity. Discharge: union with empty set.
lawBottomIdentity :: Cell -> Bool
lawBottomIdentity x = (bottom <+> x == x) && (x <+> bottom == x)

-- LAWS (the no-blend observation) -------------------------------------------

-- | 'render' is TOTAL and in-gamut for every cell. Discharge: case-complete over
-- {neutral, claim, sentinel}, each in-gamut.
lawRenderTotal :: Cell -> Bool
lawRenderTotal c = inGamut (render c)

-- | A clean (single-owner) cell shows its colour verbatim — the no-blend base case.
lawRenderSingleton :: Color -> Bool
lawRenderSingleton x = inGamut x ==> (render (singletonCell x) == x)
  where p ==> q = not p || q

-- | ⊥ renders to the neutral anchor.
lawRenderBottomNeutral :: Bool
lawRenderBottomNeutral = render bottom == neutralColor

-- | THE NO-BLEND THEOREM: 'render' never synthesises a colour. Its output is
-- always the neutral anchor, the sentinel, or one of the actual claims — never a
-- mixture. Discharge: the three-case definition, each branch a member of that set.
lawNoSynthesis :: Cell -> Bool
lawNoSynthesis c = render c `elem` (neutralColor : contestedSentinel : claims c)

-- | Contention detection is exact: 'isContested' iff ≥2 distinct claims. Discharge:
-- 'Data.Set.size'. This is how you always KNOW an overlap happened.
lawContestedDetect :: Cell -> Bool
lawContestedDetect c = isContested c == (length (claims c) > 1)

-- | A contested cell renders to the loud sentinel (the option-c default). Discharge:
-- the @_ -> contestedSentinel@ branch.
lawRenderContested :: Cell -> Bool
lawRenderContested c = isContested c ==> (render c == contestedSentinel)
  where p ==> q = not p || q

-- | The shimmer effect only ever shows a REAL claimant — never a synthesised
-- colour. Discharge: list indexing into 'claims'.
lawShimmerIsClaimant :: Int -> Cell -> Bool
lawShimmerIsClaimant t c = (not (Set.null c)) ==> (shimmerAt t c `elem` claims c)
  where p ==> q = not p || q

-- | The ingestion guard rejects exactly the out-of-domain reals. Discharge:
-- arithmetic on the 'ingest' guards (NaN, [0,1], [-½,½]).
lawIngestGuardsDomain :: (Double, Double, Double) -> Bool
lawIngestGuardsDomain t@(l, a, b) =
  case ingest t of
    Nothing -> isNaN l || isInfinite l || isNaN a || isInfinite a
            || isNaN b || isInfinite b
            || l < 0 || l > 1 || a < (-0.5) || a > 0.5 || b < (-0.5) || b > 0.5
    Just c  -> inGamut c

-- | The rendered carrier is bounded by K = 256 (palette leaves), NOT K·|Source|.
-- Discharge: 'render' ∈ the finite gamut box; provenance is on the BASE.
lawCarrierBoundedByK :: Cell -> Bool
lawCarrierBoundedByK c = inGamut (render c)
