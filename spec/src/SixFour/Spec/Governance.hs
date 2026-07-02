{- |
Module      : SixFour.Spec.Governance
Description : A guild's CONSTITUTION as a pure ranking function — @govern :: Constitution -> [Member] -> [Member]@. Each socio-political form (meritocracy, gerontocracy, majority judgment, monarchy) is a total order over members derived from the trade-ledger scalars; the council is the top 'councilSize' of that order. The default 'MajorityJudgment' is tie-free (its equivalence classes are exactly equal grade multisets, 'lawMjTieClassesAreMultisets') — which is why "SixFour.Spec.GuildScale" earns an ODD council.

Governance is "a function that has a form": a guild picks ONE 'Constitution', and self-rule is just
running it over the roster. Nothing here is stored — 'Member' is itself a fold of
"SixFour.Spec.Trade" (@mPrestige = demand@, @mReliability = reliability@) plus tenure and the ballots
(an accepted trade is a graded ballot). So @same ledger ⇒ same hierarchy@, deterministically.

  * 'Constitution' — the four simplest forms. 'Meritocracy' ranks by prestige, 'Gerontocracy' by
    tenure, 'MajorityJudgment' by median 'Grade' (the strategy-resistant, tie-free one), 'Monarchy'
    pins a fixed sovereign above a prestige-ranked rest.
  * 'govern' — the constitution applied: members most-authority-first, ties broken by 'CreatorId' so
    the order is TOTAL and deterministic ('lawGovernIsPermutation', 'lawGovernIdempotentOrder').
  * 'leader' \/ 'council' — the head of the order, and its top 'councilSize' (the derived odd body).
  * 'mjCompare' — the majority-judgment order: compare medians, and on a tie drop one median grade
    from each side and recurse (the standard tie-break). Its ties are EXACTLY equal grade multisets.

GHC-boot-only. Laws QuickCheck'd in @Properties.Governance@.
-}
-- COMPARTMENT: SWIFT-APP-SOCIAL | tag:DisplaySide
module SixFour.Spec.Governance
  ( -- * Members (a fold of the ledger)
    Grade(..)
  , Member(..)
    -- * Constitutions
  , Constitution(..)
  , govern
  , rankCompare
  , leader
  , council
    -- * Majority judgment
  , median
  , mjCompare
    -- * Laws (QuickCheck'd in @Properties.Governance@)
  , lawGovernIsPermutation
  , lawGovernIdempotentOrder
  , lawMeritocracyRanksByPrestige
  , lawGerontocracyRanksByTenure
  , lawMonarchLeads
  , lawCouncilBoundedBySize
  , lawMjTieClassesAreMultisets
  ) where

import           Data.List  (sort, sortBy)
import           Data.Maybe (listToMaybe)

import           SixFour.Spec.GuildScale (councilSize)
import           SixFour.Spec.Trade      (CreatorId)

-- ─────────────────────────────────────────────────────────────────────────────
-- Members — a fold of the trade ledger.
-- ─────────────────────────────────────────────────────────────────────────────

-- | An ordinal ballot grade (majority judgment's named scale). An accepted trade is a graded ballot.
data Grade = Reject | Poor | Fair | Good | Excellent
  deriving (Eq, Ord, Enum, Bounded, Show)

-- | A rankable member. Every field is derivable from "SixFour.Spec.Trade": @mPrestige = demand@,
-- @mReliability = reliability@; tenure is epochs since first publish; grades are received ballots.
data Member = Member
  { mId          :: CreatorId  -- ^ identity
  , mPrestige    :: Int        -- ^ demand (trades taken) — the rank scalar
  , mTenure      :: Int        -- ^ epochs since first publish — the seniority scalar
  , mReliability :: Double     -- ^ trust in @[0,1]@ — the gate scalar
  , mGrades      :: [Grade]    -- ^ ballots received (an accepted trade is a graded ballot)
  } deriving (Eq, Show)

-- ─────────────────────────────────────────────────────────────────────────────
-- Constitutions.
-- ─────────────────────────────────────────────────────────────────────────────

-- | The four simplest socio-political forms a guild can adopt. Each is a total ranking function.
data Constitution
  = Meritocracy            -- ^ order by prestige (demand)
  | Gerontocracy           -- ^ order by tenure (seniority)
  | MajorityJudgment       -- ^ order by median grade (tie-free on an odd panel)
  | Monarchy CreatorId     -- ^ a fixed sovereign on top, the rest by prestige
  deriving (Eq, Show)

-- | Compare two members under a constitution: @GT@ means @a@ outranks @b@ (more authority). This is
-- the constitution's PRIMARY key; 'govern' adds the 'CreatorId' tie-break to make it total.
rankCompare :: Constitution -> Member -> Member -> Ordering
rankCompare Meritocracy     a b = compare (mPrestige a) (mPrestige b)
rankCompare Gerontocracy    a b = compare (mTenure a) (mTenure b)
rankCompare MajorityJudgment a b = mjCompare (mGrades a) (mGrades b)
rankCompare (Monarchy k)    a b =
  case (mId a == k, mId b == k) of
    (True,  False) -> GT
    (False, True)  -> LT
    _              -> compare (mPrestige a) (mPrestige b)

-- | Apply a constitution: members ordered most-authority-first. Ties in the constitution's key fall
-- to ascending 'CreatorId', so the result is a TOTAL, deterministic order (a permutation of input).
govern :: Constitution -> [Member] -> [Member]
govern c = sortBy cmp
  where
    cmp x y = case rankCompare c y x of   -- flip: higher rank first
                EQ -> compare (mId x) (mId y)
                o  -> o

-- | The head of the governed order (highest authority), or 'Nothing' for an empty roster.
leader :: Constitution -> [Member] -> Maybe Member
leader c = listToMaybe . govern c

-- | The council: the top 'councilSize' (the derived odd body) of the governed order.
council :: Constitution -> [Member] -> [Member]
council c = take councilSize . govern c

-- ─────────────────────────────────────────────────────────────────────────────
-- Majority judgment.
-- ─────────────────────────────────────────────────────────────────────────────

-- | The (lower) median grade of a ballot multiset, or 'Nothing' when empty.
median :: [Grade] -> Maybe Grade
median [] = Nothing
median gs = Just (sort gs !! ((length gs - 1) `div` 2))

-- | The majority-judgment order: compare median grades; on a tie, remove one median grade from each
-- side and recurse (the standard tie-break). Terminates (both lists strictly shrink). Its ties are
-- exactly equal grade multisets ('lawMjTieClassesAreMultisets').
mjCompare :: [Grade] -> [Grade] -> Ordering
mjCompare a b =
  case (median a, median b) of
    (Nothing, Nothing) -> EQ
    (Nothing, _)       -> LT
    (_, Nothing)       -> GT
    (Just ma, Just mb) ->
      case compare ma mb of
        EQ -> mjCompare (removeOne ma a) (removeOne mb b)
        o  -> o
  where
    removeOne _ []       = []
    removeOne x (y : ys) = if x == y then ys else y : removeOne x ys

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws (QuickCheck'd in @Properties.Governance@).
-- ─────────────────────────────────────────────────────────────────────────────

-- | 'govern' is a permutation: it reorders the roster, never adds or drops a member.
lawGovernIsPermutation :: Constitution -> [Member] -> Bool
lawGovernIsPermutation c ms =
  sort (map mId (govern c ms)) == sort (map mId ms)

-- | The governed order is stable: re-governing an already-governed roster leaves it unchanged.
lawGovernIdempotentOrder :: Constitution -> [Member] -> Bool
lawGovernIdempotentOrder c ms =
  map mId (govern c (govern c ms)) == map mId (govern c ms)

-- | Under 'Meritocracy', prestige is non-increasing down the ranking (highest prestige leads).
lawMeritocracyRanksByPrestige :: [Member] -> Bool
lawMeritocracyRanksByPrestige ms =
  nonIncreasing (map mPrestige (govern Meritocracy ms))

-- | Under 'Gerontocracy', tenure is non-increasing down the ranking (most senior leads).
lawGerontocracyRanksByTenure :: [Member] -> Bool
lawGerontocracyRanksByTenure ms =
  nonIncreasing (map mTenure (govern Gerontocracy ms))

-- | Under 'Monarchy' k, if the sovereign is on the roster they lead it, whatever their prestige.
lawMonarchLeads :: CreatorId -> [Member] -> Bool
lawMonarchLeads k ms =
  (k `notElem` map mId ms) || (fmap mId (leader (Monarchy k) ms) == Just k)

-- | The council never exceeds the derived 'councilSize', nor the roster size.
lawCouncilBoundedBySize :: Constitution -> [Member] -> Bool
lawCouncilBoundedBySize c ms =
  let n = length (council c ms)
  in n <= councilSize && n <= length ms

-- | Majority judgment ties EXACTLY on equal grade multisets: @mjCompare a b == EQ@ iff @a@ and @b@
-- are the same multiset of grades. So distinct opinion profiles never tie — the tie-freeness that
-- makes an odd council decisive (cf. "SixFour.Spec.GuildScale").
lawMjTieClassesAreMultisets :: [Grade] -> [Grade] -> Bool
lawMjTieClassesAreMultisets a b =
  (mjCompare a b == EQ) == (sort a == sort b)

-- | A list is non-increasing (each element @≥@ the next).
nonIncreasing :: Ord a => [a] -> Bool
nonIncreasing xs = and (zipWith (>=) xs (drop 1 xs))
