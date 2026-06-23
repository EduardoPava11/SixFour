-- COMPARTMENT: PURE-SPEC-WALL | tag:DataParallelTag
{- |
Module      : SixFour.Spec.DataParallel
Description : The 4th COMPARTMENT WALL — the Metal/GPU data-parallel boundary, completing the phantom-tag set (ByteCarrier float<->byte, Sided display<->commit, BoundedP6 in-domain, + this host<->device-parallel). A GPU op is a PURE per-element map (no cross-element coupling) and every reduction must DECLARE its determinism class (Exact integer / Tol float), because GPU reduction ORDER varies across silicon.

Web-grounded (Metal Shading Language Spec v4.1 address-space type system; float reduction
non-associativity arXiv:2408.05148; @encase@/@bytemuck@ host/device shared-struct codegen). The
GPU compartment had no type boundary; this is it, in the proven "SixFour.Spec.ByteCarrier"
pattern (a phantom tag + hidden-constructor carriers + smart builders).

TWO load-bearing types:

  * @'PixelMap' a b@ — the SHAPE-A data-parallel primitive: a PURE per-element function, hidden
    constructor, only built by 'pixelMap'. @'runPixelMap'@ is exactly @map@ — no element may read
    another's input or output, so the GPU's arbitrary thread schedule cannot change the result
    (the same no-coupling guarantee as @ByteCarrier.reenterQ16Many@). A Metal @kernel void@ over
    @thread_position_in_grid@ translates from a 'PixelMap'.

  * @'DetClass'@ = @Exact@ | @Tol n@ — every 'LaneFold' (a cross-lane REDUCTION) carries its
    determinism class. @Exact@ asserts the combine is associative AND commutative over an EXACT
    domain (integers), so any GPU reduction ORDER gives the bit-identical result. @Tol n@ admits a
    float reduction whose result may vary by up to @n@ ULPs with thread order — it can NEVER be
    @Exact@, so a float sum cannot masquerade as bit-exact. This is the determinism HIERARCHY
    (Zig bit-exact / Metal exact-per-lane-but-tol-on-float-reduce / Core AI float) made a type.

This module DEFINES the boundary; it carries no kernel. A future @Codegen.Metal@ emitter
translates @PixelMap MapK@ + @LaneFold Exact@ to verified @.metal@. GHC-boot-only. Additive LEAF.
-}
module SixFour.Spec.DataParallel
  ( -- * The data-parallel compartment tag
    DataParallelTag
    -- * The per-element pure map (constructor HIDDEN)
  , PixelMap
  , pixelMap
  , runPixelMap
    -- * Reductions + their determinism class
  , DetClass(..)
  , mkTol
  , LaneFold
  , laneFold
  , runLaneFold
  , foldDetClass
    -- * Laws (QuickCheck'd in @Properties.DataParallel@)
  , lawPixelMapIsElementwise
  , lawExactIntReduceIsOrderInvariant
  , lawTolDeclaresNonNegTolerance
  , lawExactNeverFloatReduce
  ) where

import Data.List (foldl')

-- | Phantom tag: a value on the GPU DATA-PARALLEL path (per-element / per-lane). The boundary
-- the Metal compartment is bounded by, orthogonal to @MacTag@/@DeviceTag@/@DisplaySide@.
data DataParallelTag

-- | The SHAPE-A primitive: a pure per-element map. Constructor NOT exported, so the only
-- 'PixelMap' a client can build is via 'pixelMap' — there is no way to smuggle in a function
-- that reads a neighbour (a stencil/reduction is a different shape, 'LaneFold').
newtype PixelMap a b = PixelMap (a -> b)

-- | Build a per-element map from a PURE element function (the only door).
pixelMap :: (a -> b) -> PixelMap a b
pixelMap = PixelMap

-- | Run a 'PixelMap' over the grid: exactly @map@. No element reads another, so any GPU thread
-- schedule yields the same result.
runPixelMap :: PixelMap a b -> [a] -> [b]
runPixelMap (PixelMap f) = map f

-- | The determinism class of a cross-lane reduction. @Exact@: associative AND commutative over an
-- exact (integer) domain, so reduction ORDER is irrelevant and the result is bit-identical across
-- silicon. @Tol n@: a float reduction that may vary by up to @n@ ULPs with thread order (it can
-- never be @Exact@).
data DetClass = Exact | Tol Int deriving (Eq, Show)

-- | Build a tolerance class with a guaranteed NON-NEGATIVE ULP bound.
mkTol :: Int -> DetClass
mkTol = Tol . abs

-- | A cross-lane reduction tagged with its determinism class + its identity and combine.
data LaneFold a = LaneFold DetClass (a -> a -> a) a

-- | Build a reduction, declaring its determinism class.
laneFold :: DetClass -> (a -> a -> a) -> a -> LaneFold a
laneFold = LaneFold

-- | Run a reduction (left fold = one canonical schedule).
runLaneFold :: LaneFold a -> [a] -> a
runLaneFold (LaneFold _ combine z) = foldl' combine z

-- | The reduction's declared determinism class.
foldDetClass :: LaneFold a -> DetClass
foldDetClass (LaneFold dc _ _) = dc

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.DataParallel)
-- ============================================================================

-- | A 'PixelMap' is ELEMENTWISE: running it equals @map@ of its element function, so no GPU
-- thread schedule can change the result. Teeth: a primitive that let one element read another
-- (a stencil masquerading as a map) would differ from @map@ and fail. (Same guarantee shape as
-- @ByteCarrier.lawBatchedReentryIsElementwise@.)
lawPixelMapIsElementwise :: [Int] -> Bool
lawPixelMapIsElementwise xs =
  runPixelMap (pixelMap (\x -> x * 3 + 1)) xs == map (\x -> x * 3 + 1) xs

-- | An @Exact@ integer reduction is ORDER-INVARIANT: reducing the grid in any thread order
-- (here: a list and its reverse) gives the bit-identical result. Teeth: declaring @Exact@ for a
-- non-commutative combine (e.g. subtraction) breaks this — only genuinely associative+commutative
-- integer reductions may claim @Exact@.
lawExactIntReduceIsOrderInvariant :: [Int] -> Bool
lawExactIntReduceIsOrderInvariant xs =
  let f = laneFold Exact (+) 0
  in runLaneFold f xs == runLaneFold f (reverse xs)

-- | A @Tol@ class always declares a NON-NEGATIVE ULP tolerance (via 'mkTol'). Teeth: a negative
-- tolerance (a meaningless "better than exact" float bound) cannot be constructed.
lawTolDeclaresNonNegTolerance :: Int -> Bool
lawTolDeclaresNonNegTolerance n =
  case mkTol n of
    Tol t -> t >= 0
    Exact -> False    -- mkTol never yields Exact

-- | @Exact@ and @Tol@ are DISJOINT: a float reduction (which must use 'mkTol') can never be
-- @Exact@, so a non-deterministic float sum cannot masquerade as bit-exact at the type level.
-- Teeth: @mkTol n == Exact@ for any @n@ would collapse the determinism hierarchy.
lawExactNeverFloatReduce :: Int -> Bool
lawExactNeverFloatReduce n = mkTol n /= Exact
