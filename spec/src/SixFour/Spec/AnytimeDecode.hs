{- |
Module      : SixFour.Spec.AnytimeDecode
Description : Partial decode NEVER fails. Reading k detail bands is a strict PREFIX of the full decode over the additive prefix-difference lift (a successive-refinement code), and depth-0 (the coarse floor = Showcase = FloorExact) is ALWAYS available at zero cost via the zero-detail octant expand. This is the graceful-degradation guarantee that makes an advisory decode budget safe.

Encoding is cheap; decoding spends packets up the rung ladder (see
"SixFour.Spec.PacketEconomy"). For an advisory budget to be safe, a decode halted at
any rung must be a VALID coarser result rather than a failure. This module names that
contract.

The keystone is stated on the REAL additive inverse @unliftVec@ (the prefix-difference
lift, @coarse = x0@, @detail_i = x_{i+1} − x_i@, inverse = prefix-sum), which is a
successive-refinement code: a k-band prefix of the reconstruction equals the full
decode truncated to depth k. It is DELIBERATELY not stated on the shipped averaging
octant inverse @unliftOct@: that Haar-averaging inverse is non-additive, so a k-band
prefix is NOT a prefix of its full decode (a verification probe found the octant
prefix property false for k=0..6). The octant decode's anytime guarantee is stated
SEPARATELY as floor totality: the zero-detail (@Nothing@) expand is total and never
faults for every input ('lawFloorAlwaysDecodable'), so the coarse floor is always
reachable.

== S, K, I: the floor read is the free I packet

In the S\/K\/I reading (@I@ = reversible coarse floor read, @K@ = pool, @S@ = weighted
invent), the zero-detail expand is the pure @I@ read: no gene, no packet, always
available. Halting the @S@-climb at any rung leaves a valid @I@-floor image
underneath, which is exactly why "spending less never breaks the picture".

== Discrete geometry + algebraic number theory

  * The prefix-difference lift is a SUCCESSIVE-REFINEMENT code (Equitz-Cover): every
    prefix is itself optimal at its rate, so "partial decode must not fail" is the
    named property that each prefix is valid, guaranteed because the coarse layer is a
    degraded function of the fine one. 'lawDecodeIsAnytime' pins the prefix identity.
  * Non-vacuity: a TAIL-DEPENDENT decoder (a global renormalisation that subtracts the
    last prefix sum, reading the whole tail before emitting the coarse sample) FAILS
    the prefix property at some k ('anytimeUnder' 'badRenorm' is false), so the
    keystone genuinely forbids the non-additive class it claims to.
  * The floor decode is the nearest-neighbour octant expand: @length (expandRungVolume
    s vol Nothing) = 8·s³@ for every input, an integer totality fact on the ℤ voxel
    cube.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.AnytimeDecode
  ( -- * Prefix reads over the additive lift
    takeBands
  , dropDetailBeyond
  , badRenorm
    -- * Keystone (scheme-1 prefix) and its non-vacuity probe
  , lawDecodeIsAnytime
  , anytimeUnder
    -- * Floor totality (the octant decode's anytime guarantee)
  , lawFloorAlwaysDecodable
  , lawFloorNonNegOnNonNeg
  ) where

import SixFour.Spec.RefinementSystem      (unliftVec)
import SixFour.Spec.SelfSimilarReconstruct (expandRungVolume)

-- | Read the first @n@ reconstructed samples of the decode (over the REAL 'unliftVec').
takeBands :: Int -> (Integer, [Integer]) -> [Integer]
takeBands n pr = take n (unliftVec pr)

-- | Keep the coarse value and the first @k@ detail differences (drop the tail). Total.
dropDetailBeyond :: Int -> (Integer, [Integer]) -> (Integer, [Integer])
dropDetailBeyond k (c, ds) = (c, take k ds)

-- | The DELIBERATELY-WRONG tail-dependent decoder the keystone must reject: a global
-- renormalisation subtracting the LAST prefix sum (it reads the whole tail before
-- emitting even the coarse sample), so its k-prefix differs from its full-prefix.
badRenorm :: (Integer, [Integer]) -> [Integer]
badRenorm (c, ds) = let xs = scanl (+) c ds in map (subtract (last xs)) xs

-- | ★ KEYSTONE (scheme-1 prefix): reading @k+1@ bands equals the full decode truncated
-- to depth @k@, over the additive prefix-difference inverse 'unliftVec'. A non-additive
-- carrier fails this.
lawDecodeIsAnytime :: (Integer, [Integer]) -> Int -> Bool
lawDecodeIsAnytime (c, ds) k0 =
  let k = abs k0 `mod` (length ds + 2)
  in  takeBands (k + 1) (c, ds) == unliftVec (dropDetailBeyond k (c, ds))

-- | The prefix property with an ARBITRARY decoder substituted, so a wrong (tail-dependent)
-- decoder is provably falsified ('badRenorm' fails this at some k).
anytimeUnder :: ((Integer,[Integer]) -> [Integer]) -> (Integer,[Integer]) -> Int -> Bool
anytimeUnder dec (c, ds) k = take (k + 1) (dec (c, ds)) == dec (c, take k ds)

-- | Floor is ALWAYS defined and never faults: the zero-detail (@Nothing@) octant expand
-- is total with the correct length @8·s³@ for EVERY input.
lawFloorAlwaysDecodable :: Int -> [Int] -> Bool
lawFloorAlwaysDecodable side vol =
  let s = max 1 side
  in  length (expandRungVolume s vol Nothing) == 8 * s * s * s

-- | On a non-negative coarse cube the floor expand stays non-negative (domain-scoped).
lawFloorNonNegOnNonNeg :: Int -> [Int] -> Bool
lawFloorNonNegOnNonNeg side vol =
  let s = max 1 side
  in  all (>= 0) (expandRungVolume s (map abs vol) Nothing)
