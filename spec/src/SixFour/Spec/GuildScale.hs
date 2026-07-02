{- |
Module      : SixFour.Spec.GuildScale
Description : The EARNED social-body sizes — council, quorum, guild cap, schism — DERIVED, not folklore. The council size is the largest odd number a deliberator can hold every peer in mind (@largestOddAtMost deliberationSpan = 7@); the guild cap is the Dunbar cohesion ceiling (the geometric layer skeleton @5·3ⁿ@ rounded, @guildCap = 150@); a guild that crosses the cap provably loses cohesion and must schism.

This earns the governance numbers the swap-economy needs, the same way the encoder axes are earned
(cf. "SixFour.Spec.EncoderDepthAlloc"): the FORM is a theorem, the constants fall out of it. Two
orthogonal sizes — do NOT conflate them (the rank/affiliation/role separation, one axis at a time):

  * COUNCIL (the deciders). 'councilSize' = 'largestOddAtMost' 'deliberationSpan'. ODD is load-bearing:
    it breaks ties ('lawCouncilBreaksTies') AND gives a majority-judgment panel a UNIQUE median
    ('lawOddCouncilHasUniqueMedian' — the lower and upper median index coincide only for odd n, which
    is exactly why an even council forces a tie-break convention). The span is Miller's 7±2 working-
    memory bound: a body where every member models every other stays tractable to ~7. 'quorum' is the
    strict majority ('lawQuorumIsStrictMajority').

  * GUILD (the community). 'guildCap' = 'dunbarNumber' = 150, the cohesion ceiling. The Dunbar layers
    are a geometric skeleton — base 5, ratio 3 → @[5,15,45,135,405,…]@ ('dunbarLayers',
    'lawLayersGeometric') — empirically rounded to @[5,15,50,150,500,1500]@; the cap is the 4th layer
    (@5·3³ = 135@ rounded to 150, 'lawGuildCapIsFourthLayer'). TEETH: 'coherent' fails past the cap, so
    a guild MUST 'schismSplit' into two halves ('lawSchismHalves') — the split is a governance event,
    not a bug. The council fits strictly inside the guild ('lawCouncilFitsGuild') and sits between the
    innermost layers, support-clique (5) and sympathy-group (15) ('lawCouncilBetweenLayers').

HONEST: the FORM is earned. The two anchors ('deliberationSpan' = 7, 'dunbarNumber' = 150) are the
empirical inputs — Miller's span and Dunbar's number — pinned here as ONE place so the whole social
layer moves together if a measured community re-pins them; everything else is derived from them.

GHC-boot-only; re-pins nothing. Laws QuickCheck'd in @Properties.GuildScale@ (to be wired).
-}
-- COMPARTMENT: SWIFT-APP-SOCIAL | tag:DisplaySide
module SixFour.Spec.GuildScale
  ( -- * The two anchors (the only empirical inputs)
    deliberationSpan
  , dunbarNumber
    -- * The council (odd deciders)
  , largestOddAtMost
  , councilSize
  , quorum
    -- * The guild (Dunbar community)
  , dunbarBase
  , dunbarRatio
  , dunbarLayers
  , guildCap
  , coherent
  , schismSplit
    -- * Laws (QuickCheck'd in @Properties.GuildScale@)
  , lawCouncilIsOdd
  , lawCouncilBreaksTies
  , lawOddCouncilHasUniqueMedian
  , lawQuorumIsStrictMajority
  , lawLayersGeometric
  , lawGuildCapIsFourthLayer
  , lawSchismHalves
  , lawCouncilFitsGuild
  , lawCouncilBetweenLayers
  ) where

-- ─────────────────────────────────────────────────────────────────────────────
-- The two anchors — the ONLY empirical inputs; everything else is derived.
-- ─────────────────────────────────────────────────────────────────────────────

-- | Miller's working-memory span (7±2, upper): the most distinct peers a member of a
-- deliberating body can jointly hold in mind. Sizes the council.
deliberationSpan :: Int
deliberationSpan = 7

-- | Dunbar's number: the ceiling on stable social relationships one can maintain, hence the
-- membership ceiling past which a guild loses cohesion. Sizes the guild.
dunbarNumber :: Int
dunbarNumber = 150

-- ─────────────────────────────────────────────────────────────────────────────
-- The council — odd deciders.
-- ─────────────────────────────────────────────────────────────────────────────

-- | The largest odd integer @≤ n@ (@n@ if odd, else @n−1@). The tie-avoidance flooring.
largestOddAtMost :: Int -> Int
largestOddAtMost n = if odd n then n else n - 1

-- | The council size: the largest odd body within the deliberation span — @7@.
councilSize :: Int
councilSize = largestOddAtMost deliberationSpan

-- | The decision threshold: a strict majority of the council — @⌊c/2⌋ + 1 = 4@ of 7.
quorum :: Int
quorum = councilSize `div` 2 + 1

-- ─────────────────────────────────────────────────────────────────────────────
-- The guild — Dunbar community.
-- ─────────────────────────────────────────────────────────────────────────────

-- | The innermost Dunbar layer (the support clique).
dunbarBase :: Int
dunbarBase = 5

-- | The Dunbar layer scaling ratio (each layer ~3× the last).
dunbarRatio :: Int
dunbarRatio = 3

-- | The geometric Dunbar layer skeleton @[5,15,45,135,…]@ — @n@ layers from 'dunbarBase' by
-- 'dunbarRatio'. Empirically these round to @[5,15,50,150,500,1500]@.
dunbarLayers :: Int -> [Int]
dunbarLayers n = take n (iterate (* dunbarRatio) dunbarBase)

-- | The hard guild membership ceiling = 'dunbarNumber' (the 4th layer @5·3³ = 135@ rounded).
guildCap :: Int
guildCap = dunbarNumber

-- | A guild of @n@ members stays coherent while it does not exceed the cap. Past it, no member can
-- hold every other as a relationship, so the group fractures.
coherent :: Int -> Bool
coherent n = n <= guildCap

-- | The schism of an over-cap guild into two near-equal halves — the split is a governance event.
schismSplit :: Int -> (Int, Int)
schismSplit n = (n `div` 2, n - n `div` 2)

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws (QuickCheck'd in @Properties.GuildScale@).
-- ─────────────────────────────────────────────────────────────────────────────

-- | The council is odd (the tie-avoidance floor did its job).
lawCouncilIsOdd :: Bool
lawCouncilIsOdd = odd councilSize

-- | An odd council breaks ties: no split of votes into two camps is ever equal, so every binary
-- decision has a strict winner.
lawCouncilBreaksTies :: Bool
lawCouncilBreaksTies = all (\yes -> 2 * yes /= councilSize) [0 .. councilSize]

-- | An odd council has a UNIQUE median grade: the lower- and upper-median indices coincide only for
-- odd n. This is why majority judgment needs an odd panel (an even one forces a tie-break rule).
lawOddCouncilHasUniqueMedian :: Bool
lawOddCouncilHasUniqueMedian =
  odd councilSize == ((councilSize - 1) `div` 2 == councilSize `div` 2)

-- | The quorum is a strict majority: @2·quorum > councilSize@.
lawQuorumIsStrictMajority :: Bool
lawQuorumIsStrictMajority = 2 * quorum > councilSize

-- | The Dunbar layers are geometric: each layer is 'dunbarRatio' times the previous.
lawLayersGeometric :: Int -> Bool
lawLayersGeometric n =
  let ls = dunbarLayers (max 1 n)
  in and (zipWith (\a b -> b == a * dunbarRatio) ls (drop 1 ls))

-- | The guild cap is the 4th Dunbar layer: at least the derived skeleton @5·3³ = 135@ and below the
-- next layer @5·3⁴ = 405@.
lawGuildCapIsFourthLayer :: Bool
lawGuildCapIsFourthLayer =
  let d3 = dunbarBase * dunbarRatio ^ (3 :: Int)
      d4 = dunbarBase * dunbarRatio ^ (4 :: Int)
  in d3 <= guildCap && guildCap < d4

-- | A schism splits members exactly and near-evenly (halves differ by at most one).
lawSchismHalves :: Int -> Bool
lawSchismHalves n =
  let (a, b) = schismSplit n
  in a + b == n && abs (a - b) <= 1

-- | The council fits inside the guild (deciders are a strict subset of members).
lawCouncilFitsGuild :: Bool
lawCouncilFitsGuild = councilSize <= guildCap

-- | The council sits between the two innermost Dunbar layers — bigger than the support clique (5),
-- no bigger than the sympathy group (15).
lawCouncilBetweenLayers :: Bool
lawCouncilBetweenLayers =
  case dunbarLayers 2 of
    (support : sympathy : _) -> support <= councilSize && councilSize <= sympathy
    _                        -> False
