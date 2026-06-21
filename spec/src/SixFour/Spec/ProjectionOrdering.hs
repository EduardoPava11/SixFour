{- |
Module      : SixFour.Spec.ProjectionOrdering
Description : A valid projection-ordering of the six "SixFour.Spec.Dim6" axes — carrier pair (L:t) fixed coarse, the search pairing {x,y}<->{a,b} carried as a FIRST-CLASS XOR\/Z2 choice, plus a referenceable hash and a (compose\/identity\/inverse) group action.

Frontier step 2. Frontier step 1 ("SixFour.Spec.Dim6") gave the six axes
@(L,A,B,x,y,t)@ as ONE flat alphabet with the @x<->a, y<->b, t<->L@ involution
'phi6' and the universal carrier @{L,t}@ ('isUniversal'). This module turns an
/ordering/ of those axes into a type and pins the encoding condition the user
fixed (2026-06-21):

  * __Carrier fixed.__ Every GIF frame has its own dynamic-range\/white-balance
    distribution shape, and @t=L@ is the highest latent proxy for TIME — the
    universal carrier. So the @(L:t)@ pair is ALWAYS the coarse\/DC lane and is
    pinned to the head of the ordering, in the order @L@ then @t@
    ('mkOrdering' rejects anything else).

  * __Search pairing is a bijection = XOR\/Z2.__ The four search axes
    @{x,y}@ (position) and @{a,b}@ (chroma) are matched by a /bijection/: a
    position carries a chroma, and "if @x@ carries @a@ then @y@ carries @b@"
    (and vice-versa). There are exactly TWO such diagonals — the two cosets of
    the @Z2@ swap:

      > P1 = [(L:t), (x:a), (y:b)]      -- 'XorStraight'
      > P2 = [(L:t), (x:b), (y:a)]      -- 'XorCross'

    'searchBit' reads which diagonal an ordering carries; 'xorOf' is the
    boolean. The choice is __nearly one bit__ — the projection-mode is the XOR
    bit (plus a small ordering coset, see VOCABULARY below).

  * __Orthogonality.__ Because the pairing is a bijection, @x@ and @y@ ALWAYS
    carry /different/ chroma — the two search projections stay ORTHOGONAL
    ('lawOrthogonalProjections'). Modelling the pairing as a first-class XOR is
    exactly what keeps the model in projection-mode.

  * __Reversibility = the Z2 inverse.__ The swap is its own inverse, so applying
    it twice is the identity ('lawXorSelfInverse' / 'lawComposeInverse'). No
    cleanup state is needed: reversibility is automatic, the group inverse.

== The search-pairing algebra

The pure search degree of freedom is the cyclic group @Z2 = {Straight, Cross}@
acting by the @a<->b@ chroma swap on the two search pairs (equivalently the
@x<->y@ position swap — same coset). This is the @Z2@ FACTOR of the larger
ordering-symmetry group; see VOCABULARY.

== Vocabulary (counted by enumeration; see "Properties.ProjectionOrdering")

With the carrier @(L:t)@ fixed at the head and the search tail required to be two
adjacent @(position, chroma)@ pairs forming a bijection, the number of valid
orderings factors as a product of independent @Z2@ choices:

  > 2 (XOR diagonal)  x  2 (pair-order: x-pair first | y-pair first)  x  2x2 (within-pair flips) = 16

The user's __XOR-as-the-projection-mode__ reading pins pair-order and
within-pair order (the carrier-then-position-then-chroma convention), leaving the
pure @Z2@ search bit:

  > t=L fixed  +  XOR bijection only  =  2

'allOrderings' is the canonical XOR-only vocabulary (2 elements); the wider
coset counts are documented and checked in the test module.

== Hash

'orderingHash' is a @Word32@ identity token (the OptionTree\/GenomeHash idiom of
"SixFour.Spec.AtlasMove" applied to a projection-mode): a projection-mode is a
referenceable byte-token, so an OptionTree node can name a projection by hash
('lawHashInjective').

== Group action

The valid orderings are acted on by a small group of /relabelings/
('OrderOp' = the @Z2@ search-swap, here). 'composeOp'\/'identityOp'\/'invertOp'
are given as FUNCTIONS with laws ('lawComposeAssoc', 'lawIdentityUnit',
'lawComposeInverse'), NOT a @Group@ typeclass instance — closure on the valid
set is proven by the laws first (per the spec methodology: no total instance
until closure is proven).

GHC-boot-only (base + Data.List + Data.Word). Smart-ctor newtype; laws are
exported predicates, QuickCheck'd in "Properties.ProjectionOrdering".
-}
module SixFour.Spec.ProjectionOrdering
  ( -- * The ordering type (smart-ctor newtype)
    Ordering6
  , unOrdering
  , mkOrdering
    -- * The carrier and search lanes
  , carrierPair
  , searchTail
    -- * The XOR \/ Z2 search pairing
  , XorBit(..)
  , searchBit
  , xorOf
  , withXor
    -- * The canonical vocabulary
  , allOrderings
  , canonicalStraight
  , canonicalCross
    -- * Hash (referenceable projection-mode token)
  , orderingHash
    -- * Group action on orderings (functions + laws, not a typeclass)
  , OrderOp(..)
  , identityOp
  , composeOp
  , invertOp
  , applyOp
    -- * Laws (QuickCheck'd in @Properties.ProjectionOrdering@)
  , lawMkRoundTrips
  , lawMkRejectsBadCarrier
  , lawCarrierIsLT
  , lawOrthogonalProjections
  , lawXorSelfInverse
  , lawXorTwoCosets
  , lawHashInjective
  , lawIdentityUnit
  , lawComposeAssoc
  , lawComposeInverse
  , lawApplyClosed
  , lawVocabularyCount
  ) where

import Data.Bits (xor, (.&.))
import Data.List (sort, nub, foldl')
import Data.Word (Word32)

import SixFour.Spec.Dim6 (Dim6(..), allDims, isUniversal)

-- ---------------------------------------------------------------------------
-- The ordering type
-- ---------------------------------------------------------------------------

-- | A VALID projection-ordering of the six 'Dim6' axes: the carrier @(L:t)@ at
-- the head (coarse lane) followed by the search tail @[x|y, a|b, x|y, a|b]@
-- forming a position<->chroma bijection. Construct only via 'mkOrdering'.
newtype Ordering6 = Ordering6
  { unOrdering :: [Dim6]  -- ^ the underlying 6-axis list (carrier head + search tail).
  }
  deriving (Eq, Ord, Show)

-- | The two chroma (search-colour) axes.
chrAxes :: [Dim6]
chrAxes = [DimA, DimB]

isPos :: Dim6 -> Bool
isPos d = d == DimX || d == DimY

isChr :: Dim6 -> Bool
isChr d = d == DimA || d == DimB

-- | Smart constructor. Accepts a 6-list iff it is a valid projection-ordering:
--
--   1. it is a permutation of all six 'Dim6' axes (closed coverage);
--   2. the carrier @(L:t)@ is fixed at the head, in the order @L@ then @t@;
--   3. the four-axis search tail is two adjacent @(position, chroma)@ pairs
--      whose positions are @{x,y}@ and chroma are @{a,b}@ — a bijection (so the
--      two search projections are orthogonal).
--
-- Returns 'Nothing' otherwise. This is the only door into 'Ordering6'.
mkOrdering :: [Dim6] -> Maybe Ordering6
mkOrdering ds
  | isPermutation ds
  , take 2 ds == [DimL, DimT]
  , validSearchTail (drop 2 ds)
  = Just (Ordering6 ds)
  | otherwise
  = Nothing
  where
    isPermutation xs = sort xs == sort allDims && length (nub xs) == 6

-- | The search tail of an /accepted/ ordering is @[x, c1, y, c2]@ with
-- @{c1,c2} = {a,b}@: the carrier-then-position-then-chroma convention with
-- pair-order fixed (@x@-pair first) and within-pair order fixed (position then
-- chroma). The ONLY remaining degree of freedom is the chroma DIAGONAL — the
-- XOR\/Z2 search bit. So @mkOrdering@ accepts exactly two orderings (the
-- projection-choice is nearly one bit); the wider cosets (free pair-order, free
-- within-pair flips: 4 and 16) are documented and enumerated in the test module
-- but are NOT distinct projection-modes here.
validSearchTail :: [Dim6] -> Bool
validSearchTail [DimX, c1, DimY, c2] =
  isChr c1 && isChr c2 && c1 /= c2
validSearchTail _ = False

-- | The fixed carrier pair @(L,t)@ of any valid ordering — always @(DimL, DimT)@.
carrierPair :: Ordering6 -> (Dim6, Dim6)
carrierPair _ = (DimL, DimT)

-- | The four-axis search tail @[p1,c1,p2,c2]@.
searchTail :: Ordering6 -> [Dim6]
searchTail (Ordering6 ds) = drop 2 ds

-- ---------------------------------------------------------------------------
-- The XOR / Z2 search pairing
-- ---------------------------------------------------------------------------

-- | The near-one-bit projection-mode: which diagonal pairs position to chroma.
--
--   * 'XorStraight' — @x@ carries @a@, @y@ carries @b@  (@P1@).
--   * 'XorCross'    — @x@ carries @b@, @y@ carries @a@  (@P2@).
--
-- The two cosets of the @Z2@ chroma swap. \"If @x@ carries @a@ then @y@ carries
-- @b@\" is enforced by construction: there is no third inhabitant.
data XorBit = XorStraight | XorCross
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | Read the XOR diagonal of a valid ordering: look at the chroma the FIRST
-- position axis is paired with, then ask whether that respects the
-- @x->a, y->b@ straight diagonal. (The bijection guarantees the second pair is
-- forced, so one lookup determines the bit.)
searchBit :: Ordering6 -> XorBit
searchBit o =
  case searchTail o of
    -- accepted orderings are [x, c1, y, c2]; x's partner determines the diagonal
    [DimX, DimA, DimY, _] -> XorStraight   -- x->a (=> y->b)  : P1
    [DimX, DimB, DimY, _] -> XorCross      -- x->b (=> y->a)  : P2
    _                     -> XorStraight   -- unreachable for valid orderings

-- | The XOR bit as a 'Bool' (@True@ = 'XorCross' = the swapped diagonal).
xorOf :: Ordering6 -> Bool
xorOf o = searchBit o == XorCross

-- | Build the canonical ordering carrying a given XOR diagonal (pair-order and
-- within-pair order pinned to the canonical @x-pair, position-then-chroma@
-- convention). Total: every 'XorBit' yields a valid ordering.
withXor :: XorBit -> Ordering6
withXor XorStraight = canonicalStraight
withXor XorCross    = canonicalCross

-- ---------------------------------------------------------------------------
-- Canonical vocabulary
-- ---------------------------------------------------------------------------

-- | @P1@: the straight diagonal @[(L:t),(x:a),(y:b)]@.
canonicalStraight :: Ordering6
canonicalStraight = Ordering6 [DimL, DimT, DimX, DimA, DimY, DimB]

-- | @P2@: the cross diagonal @[(L:t),(x:b),(y:a)]@.
canonicalCross :: Ordering6
canonicalCross = Ordering6 [DimL, DimT, DimX, DimB, DimY, DimA]

-- | The canonical XOR-only vocabulary: exactly the two projection-modes
-- @{P1, P2}@ once @t=L@ is fixed and pair-order\/within-pair order are pinned.
-- This is the count the enumeration in "Properties.ProjectionOrdering" confirms
-- (@2@), the @Z2@ search bit.
allOrderings :: [Ordering6]
allOrderings = [canonicalStraight, canonicalCross]

-- ---------------------------------------------------------------------------
-- Hash
-- ---------------------------------------------------------------------------

-- | A @Word32@ identity hash of an ordering — a referenceable projection-mode
-- token (the GenomeHash\/OptionTree idiom). FNV-1a over the axis indices, so an
-- OptionTree node can name a projection-mode by a single byte-token.
orderingHash :: Ordering6 -> Word32
orderingHash (Ordering6 ds) = foldl' step 0x811c9dc5 ds
  where
    step :: Word32 -> Dim6 -> Word32
    step h d = (h `xor` (fromIntegral (fromEnum d) .&. 0xff)) * 0x01000193

-- ---------------------------------------------------------------------------
-- Group action (functions + laws, NOT a typeclass instance)
-- ---------------------------------------------------------------------------

-- | The search-pairing symmetry group element: the @Z2@ that swaps the chroma
-- diagonal (Straight <-> Cross). 'OpId' is the identity, 'OpSwap' the
-- self-inverse generator. (A larger coset group could be added later; the
-- closure we PROVE here is on this @Z2@ over 'allOrderings'.)
data OrderOp = OpId | OpSwap
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | The group identity.
identityOp :: OrderOp
identityOp = OpId

-- | Group multiplication: @Z2@ addition (swap composed with swap = id).
composeOp :: OrderOp -> OrderOp -> OrderOp
composeOp OpId  g    = g
composeOp g     OpId = g
composeOp OpSwap OpSwap = OpId

-- | Group inverse. In @Z2@ every element is its own inverse — reversibility is
-- automatic.
invertOp :: OrderOp -> OrderOp
invertOp = id

-- | Act on an ordering. 'OpSwap' flips the XOR diagonal (and only that); the
-- result is always a valid 'Ordering6' (closure, 'lawApplyClosed').
applyOp :: OrderOp -> Ordering6 -> Ordering6
applyOp OpId  o = o
applyOp OpSwap o = withXor (flipBit (searchBit o))
  where
    flipBit XorStraight = XorCross
    flipBit XorCross    = XorStraight

-- ---------------------------------------------------------------------------
-- Laws (predicates; QuickCheck'd in Properties.ProjectionOrdering)
-- ---------------------------------------------------------------------------

-- | 'mkOrdering' round-trips a valid ordering: @mkOrdering . unOrdering = Just@.
lawMkRoundTrips :: Ordering6 -> Bool
lawMkRoundTrips o = mkOrdering (unOrdering o) == Just o

-- | 'mkOrdering' REJECTS any list whose head is not the @(L,t)@ carrier — the
-- carrier-fixed condition is enforced, not assumed.
lawMkRejectsBadCarrier :: [Dim6] -> Bool
lawMkRejectsBadCarrier ds =
  case mkOrdering ds of
    Just _  -> take 2 ds == [DimL, DimT]
    Nothing -> True

-- | Every valid ordering's carrier is the universal pair @{L,t}@ at the head.
lawCarrierIsLT :: Ordering6 -> Bool
lawCarrierIsLT o =
  let (c1, c2) = carrierPair o
  in isUniversal c1 && isUniversal c2 && (c1, c2) == (DimL, DimT)
     && take 2 (unOrdering o) == [DimL, DimT]

-- | ORTHOGONAL projections: @x@ and @y@ always carry DIFFERENT chroma (the
-- bijection). Reading each position's partner chroma in the tail gives two
-- distinct chroma axes.
lawOrthogonalProjections :: Ordering6 -> Bool
lawOrthogonalProjections o =
  case searchTail o of
    [_p1, c1, _p2, c2] -> c1 /= c2 && c1 `elem` chrAxes && c2 `elem` chrAxes
    _                  -> False

-- | The XOR swap is its own inverse: flipping the diagonal twice restores the
-- ordering. Reversibility = the @Z2@ inverse.
lawXorSelfInverse :: Ordering6 -> Bool
lawXorSelfInverse o = applyOp OpSwap (applyOp OpSwap o) == o

-- | The pairing has exactly TWO cosets: 'searchBit' is onto @{Straight, Cross}@
-- and 'withXor' inverts it.
lawXorTwoCosets :: XorBit -> Bool
lawXorTwoCosets b = searchBit (withXor b) == b

-- | The hash is injective on the canonical vocabulary: distinct projection-modes
-- get distinct tokens.
lawHashInjective :: Bool
lawHashInjective =
  let hs = map orderingHash allOrderings
  in length (nub hs) == length hs

-- | @OpId@ is a two-sided unit for 'composeOp'.
lawIdentityUnit :: OrderOp -> Bool
lawIdentityUnit g =
  composeOp identityOp g == g && composeOp g identityOp == g

-- | 'composeOp' is associative.
lawComposeAssoc :: OrderOp -> OrderOp -> OrderOp -> Bool
lawComposeAssoc f g h =
  composeOp f (composeOp g h) == composeOp (composeOp f g) h

-- | 'invertOp' is a two-sided inverse: @g . g^{-1} = id@ both ways.
lawComposeInverse :: OrderOp -> Bool
lawComposeInverse g =
  composeOp g (invertOp g) == identityOp
    && composeOp (invertOp g) g == identityOp

-- | The group action is CLOSED on valid orderings: 'applyOp' of any op to any
-- valid ordering re-parses as a valid ordering, and the action respects
-- composition (@apply (f.g) = apply f . apply g@).
lawApplyClosed :: OrderOp -> OrderOp -> Ordering6 -> Bool
lawApplyClosed f g o =
     mkOrdering (unOrdering (applyOp f o)) == Just (applyOp f o)
  && applyOp (composeOp f g) o == applyOp f (applyOp g o)

-- | The canonical XOR-only vocabulary has exactly two projection-modes (the
-- @Z2@ search bit), and they are the straight and cross diagonals.
lawVocabularyCount :: Bool
lawVocabularyCount =
     length allOrderings == 2
  && nub allOrderings == allOrderings
  && map searchBit allOrderings == [XorStraight, XorCross]
