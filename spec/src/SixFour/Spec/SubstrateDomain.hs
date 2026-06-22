{- |
Module      : SixFour.Spec.SubstrateDomain
Description : The invertible-DOMAIN contract of the reversible integer substrate — the @|v| <= B = 2^29-1@ bound that keeps every lift intermediate inside i32, matching the owned Zig kernel's total-function guard (@RC_OUT_OF_RANGE@).

The reversible lift ("SixFour.Spec.RGBTLift" 'liftQuad', and the multi-level Haar /
temporal split built from it) is byte-exact reversible for ALL integers in 64-bit
Haskell. The SHIPPED substrate, however, stores values in i32 (the owned Zig core,
chosen for portability BEYOND the Apple ecosystem), so it is only TOTAL on the finite
domain where every lift intermediate fits i32. This module pins that domain so the
Haskell oracle and the Zig kernel agree on the SAME contract instead of one side
silently exceeding it.

The binding case is the 2x2 'liftQuad': it lifts twice, so the second-level high band
@HH@ reaches @4*B@. With @B = 2^29 - 1@, @4B = 2^31 - 4 <= i32Max@ (fits); one tick
past, @B + 1@, gives @4(B+1) = 2^31 > i32Max@ (overflows). So B is the TIGHT bound
('lawBoundIsTight'). The multi-level Haar / temporal split only reach @2B@ per level
(each per-level detail is @x - y@ over bounded lifted parents), so they inherit the
same domain with margin ('lawDetailWithinTwoB').

CROSS-LANGUAGE CONTRACT: the Zig kernel (@Native\/src\/kernels.zig@: @SUBSTRATE_BOUND@ =
@2^29-1@, @liftChecked@) REFUSES out-of-domain input with @RC_OUT_OF_RANGE@ rather than
wrapping silently; 64-bit Haskell @Int@ is unbounded and does NOT refuse, so the
cross-language golden compares IN-DOMAIN only. Within the domain, both round-trip
identically. Real OKLab Q16 is ~@2^17@, so B leaves >4096x headroom and changes NO
in-domain output.

GHC-boot-only (base). Laws are exported predicates, QuickCheck'd in
"Properties.SubstrateDomain".
-}
module SixFour.Spec.SubstrateDomain
  ( -- * The domain bound (mirrors Zig @SUBSTRATE_BOUND@ / @DETAIL_BOUND@)
    substrateBound
  , detailBound
  , i32Max
  , i32Min
    -- * Domain / storage predicates
  , inDomain
  , quadInDomain
  , fitsI32
    -- * Laws (QuickCheck'd in @Properties.SubstrateDomain@)
  , lawDomainRoundTrips
  , lawDomainFitsI32
  , lawBoundIsTight
  , lawDetailWithinTwoB
  ) where

import SixFour.Spec.RGBTLift (Quad, liftQuad, unliftQuad)

-- | The invertible-domain bound @B = 2^29 - 1@: every input leaf\/generator must
-- satisfy @|v| <= B@. Mirrors the Zig @SUBSTRATE_BOUND@.
substrateBound :: Int
substrateBound = (2 ^ (29 :: Int)) - 1

-- | The max legal single-level detail @2B@ (a per-level @x - y@ over bounded lifted
-- parents). Mirrors the Zig @DETAIL_BOUND@.
detailBound :: Int
detailBound = 2 * substrateBound

-- | The signed-32-bit storage range of the shipped (Zig) substrate.
i32Max, i32Min :: Int
i32Max = (2 ^ (31 :: Int)) - 1
i32Min = negate (2 ^ (31 :: Int))

-- | A scalar is in the invertible domain iff @|v| <= B@.
inDomain :: Int -> Bool
inDomain v = abs v <= substrateBound

-- | A 2x2 block is in domain iff all four cells are.
quadInDomain :: Quad -> Bool
quadInDomain (a, b, c, d) = all inDomain [a, b, c, d]

-- | Does a value fit the signed-32-bit storage the shipped substrate uses?
fitsI32 :: Int -> Bool
fitsI32 v = v >= i32Min && v <= i32Max

-- | Within the domain, the lift round-trips exactly (delegates "SixFour.Spec.RGBTLift"
-- @lawLiftUnliftExact@, scoped to the domain the shipped substrate actually supports).
lawDomainRoundTrips :: Quad -> Bool
lawDomainRoundTrips q = not (quadInDomain q) || unliftQuad (liftQuad q) == q

-- | THE total-function safety law: within the domain @|v| <= B@, EVERY band 'liftQuad'
-- produces fits i32 — so the Zig i32 substrate never overflows and never has to refuse a
-- legitimate input. Teeth: a domain bound chosen too large would push the @4B@ HH band
-- past @i32Max@ and fail this. This is the proof the Zig @liftChecked@ guard is sound
-- (refusal happens exactly when, and only when, a value would not fit i32).
lawDomainFitsI32 :: Quad -> Bool
lawDomainFitsI32 q =
  not (quadInDomain q) ||
    let (ll, lh, hl, hh) = liftQuad q
    in all fitsI32 [ll, lh, hl, hh]

-- | The bound is TIGHT: the extremal in-domain quad's HH band fits i32, but the same
-- quad one tick OUT of domain (@B + 1@) overflows i32. So B cannot be raised without
-- breaking i32 totality. The alternating-sign quad @(m, -m, -m, m)@ has @HH = 4m@, so
-- @4B = 2^31 - 4@ fits and @4(B+1) = 2^31@ does not. Closed witnesses, @once@-tested.
lawBoundIsTight :: Bool
lawBoundIsTight =
  let b      = substrateBound
      hhOf m = let (_, _, _, hh) = liftQuad (m, negate m, negate m, m) in hh
  in fitsI32 (hhOf b)                 -- at B: HH = 4B = 2^31 - 4 fits i32
     && not (fitsI32 (hhOf (b + 1)))  -- at B+1: HH = 2^31 overflows i32

-- | A single-level detail of two in-domain values stays within @2B@ — so the
-- multi-level Haar / temporal split (whose per-level detail is @x - y@ over bounded
-- parents) inherit the domain with margin. Teeth: a 'detailBound' smaller than @2B@
-- would fail at the antipodal pair.
lawDetailWithinTwoB :: Int -> Int -> Bool
lawDetailWithinTwoB x y =
  not (inDomain x && inDomain y) || abs (x - y) <= detailBound
