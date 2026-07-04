{- |
Module      : SixFour.Spec.OctantViews
Description : The 2×2×2 ↔ 1 + 7-latents abstraction, graded by AXIS SUBSETS. The truth being gated: a 2×2×2 spacetime block is two 2×2 xy-quads at the ORDERED pair (t, t+1); the three UNORDERED axis pairs x:y, x:t, y:t are the block's isometric views; and the 7 detail latents are compressions in different ORDERS — the linear octant skeleton is the 3-bit Walsh–Hadamard transform (the characters of (ℤ/2)³), graded by Hamming weight into 1 coarse + 3 single-axis + 3 pair + 1 triple bands (1+3+3+1 = binomial row 3, detail total 7 = rank A₇, tying "SixFour.Spec.RootLatticeDetail").

The keystone ('lawLatentIsViewDetail'): every order-k latent is computable from its
k-dimensional VIEW ALONE — pool the complementary axes first, then take the view's own
top detail; the answer is byte-identical to the 3D band. The three pair latents ARE the
isometric faces' details (x:y the frame plane, x:t and y:t the slit-scan planes), and
the views + coarse reconstruct the block exactly ('lawViewsDetermineBlock',
@8·v = Σ_S sign_S · band_S@ — division only by 8 = 2³, so reconstruction lives in ℤ[1/2],
never divides by a non-unit).

TIME'S ARROW is in the grading: swapping the unordered x:y permutes the latents by the
S₂ action ('lawXYSwapPermutesLatents'); reversing the ORDERED t,t+1 negates exactly the
four t-containing bands and fixes the rest ('lawTimeReversalFlipsTBands') — the order of
the pair (t, t+1) lives ONLY in the t-bands. Pooling an axis kills exactly the bands
containing it ('lawAxisPoolingKillsItsBands') — the latent-level refinement of the
SpineRing t-collapse (the collapse kernel, on latents, is the span of the t-bands).

COLOR IS A DIFFERENT DIMENSIONAL SPACE: the block is a fiber bundle (spacetime base) ×
(color fiber); the lift acts per channel and commutes with every linear color map — the
opponent transform (L, a, b) mixes fibers, never the base grading
('lawColorFiberCommutes', the V2.1 "opp is linear so opp(delta) = delta(opp)" fact,
extended to all 8 bands). The GIF extraction mixes both: the Global Color Table is the
color fiber realized at the 16×16 rung (one bin per palette slot, @Native/palette16.zig@)
and the LZW index stream is the base; the inference/training LAYERS 16×16, 32×32, 64×64
are the rungs of this one graded morphism, with scale-transition supervision (coarse =
pooled fine) per rung ("SixFour.Spec.SelfSupervisedRung").

HONEST BOUNDARY (same as RootLatticeDetail): this module gates the IDEALIZED LINEAR
Walsh–Hadamard skeleton — the grading, the view-sufficiency, the arrow, the fiber
structure. The SHIPPED reversible lift (@kernels.zig s4_octant_lift@, floored) is a
set-bijection, not this linear map; the two agree on which bands exist, not on
per-element additivity.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.OctantViews
  ( -- * The block: 8 corners, t ordered
    Axis (..)
  , Corner
  , corners
  , Block
  , blockFromList
    -- * The graded bands (Walsh–Hadamard characters, indexed by axis subsets)
  , axisSubsets
  , bandOf
  , bandOrder
    -- * Views (pool the complement, then the view's own detail)
  , viewDetail
    -- * Color fiber
  , RGB
  , opponent
    -- * Laws
  , lawBandCountIsBinomial
  , lawLatentIsViewDetail
  , lawViewsDetermineBlock
  , lawXYSwapPermutesLatents
  , lawTimeReversalFlipsTBands
  , lawAxisPoolingKillsItsBands
  , lawColorFiberCommutes
  ) where

import SixFour.Spec.RootLatticeDetail (numDetailBands)

-- | The three spacetime axes. x and y are the UNORDERED spatial pair; t is ORDERED
-- (corner coordinate 0 = time t, 1 = time t+1 — the arrow).
data Axis = AxX | AxY | AxT
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | A corner of the 2×2×2 block: each coordinate 0 or 1, as (x, y, t).
type Corner = (Int, Int, Int)

-- | All 8 corners, the two xy-quads at t = 0 and t = 1 interleaved.
corners :: [Corner]
corners = [ (x, y, t) | x <- [0, 1], y <- [0, 1], t <- [0, 1] ]

-- | A block assigns a value to each corner (per color channel, or per fiber point).
type Block a = Corner -> a

-- | Build a block from an 8-list in 'corners' order (short lists pad with 0) —
-- the QuickCheck-friendly constructor used by the property tests.
blockFromList :: [Integer] -> Block Integer
blockFromList xs (x, y, t) = padded !! (x * 4 + y * 2 + t)
  where padded = take 8 (xs ++ repeat 0)

axisBit :: Axis -> Corner -> Int
axisBit AxX (x, _, _) = x
axisBit AxY (_, y, _) = y
axisBit AxT (_, _, t) = t

-- | The 8 axis subsets in a fixed order: the DUAL GROUP of (ℤ/2)³. The subset is the
-- band's index; its SIZE is the band's ORDER (the grading 1+3+3+1).
axisSubsets :: [[Axis]]
axisSubsets =
  [ [], [AxX], [AxY], [AxT], [AxX, AxY], [AxX, AxT], [AxY, AxT], [AxX, AxY, AxT] ]

-- | The character sign of subset s at a corner: −1 for each s-axis sitting at 1.
signAt :: [Axis] -> Corner -> Integer
signAt s c = product [ if axisBit a c == 0 then 1 else -1 | a <- s ]

-- | The band (Walsh–Hadamard coefficient) of a block at subset s: the signed corner
-- sum. @[]@ is the coarse (DC) band; the 7 nonempty subsets are the detail latents.
bandOf :: Block Integer -> [Axis] -> Integer
bandOf v s = sum [ signAt s c * v c | c <- corners ]

-- | The order of a latent = how many axes it mixes (the grading degree).
bandOrder :: [Axis] -> Int
bandOrder = length

-- Assignments of 0/1 to a list of axes (the corners of a sub-cube on those axes).
assignments :: [Axis] -> [[(Axis, Int)]]
assignments = foldr (\a acc -> [ (a, b) : r | b <- [0, 1], r <- acc ]) [[]]

complementOf :: [Axis] -> [Axis]
complementOf s = [ a | a <- [AxX, AxY, AxT], a `notElem` s ]

mkCorner :: [(Axis, Int)] -> Corner
mkCorner kv = (get AxX, get AxY, get AxT)
  where get a = maybe 0 id (lookup a kv)

-- | The view detail of subset s, computed FROM THE VIEW ALONE: first pool (sum) the
-- block over the axes NOT in s — the k-dimensional isometric view — then take the
-- view's own all-axes signed detail. 'lawLatentIsViewDetail' proves this equals
-- 'bandOf': the latents are compressions in different orders.
viewDetail :: [Axis] -> Block Integer -> Integer
viewDetail s v =
  sum [ signOf cS * pooled cS | cS <- assignments s ]
  where
    signOf cS = product [ if b == 0 then 1 else -1 | (_, b) <- cS ]
    pooled cS = sum [ v (mkCorner (cS ++ cC)) | cC <- assignments (complementOf s) ]

-- | A color fiber point: (R, G, B) per corner — a different dimensional space from
-- the spacetime base.
type RGB = (Integer, Integer, Integer)

-- | The linear opponent color map (L, a, b) = (R+G+B, R−G, R+G−2B) — the V2.1 stored
-- latent axes. Linear over ℤ, which is exactly why it commutes with the lift.
opponent :: RGB -> RGB
opponent (r, g, b) = (r + g + b, r - g, r + g - 2 * b)

bandRGB :: Block RGB -> [Axis] -> RGB
bandRGB v s = ( bandOf (fst3 . v) s, bandOf (snd3 . v) s, bandOf (thd3 . v) s )
  where
    fst3 (a, _, _) = a
    snd3 (_, b, _) = b
    thd3 (_, _, c) = c

-- | LAW (the grading): band counts per order are the binomial row 1,3,3,1, and the
-- detail total is 7 = rank A₇ = 'numDetailBands' 8 — the octant band count and the
-- axis-subset grading are the same theorem seen twice.
lawBandCountIsBinomial :: Bool
lawBandCountIsBinomial =
  [ length [ s | s <- axisSubsets, bandOrder s == k ] | k <- [0 .. 3] ] == [1, 3, 3, 1]
    && length (filter (not . null) axisSubsets) == numDetailBands 8

-- | LAW (keystone — latents are compressions in different orders): every band equals
-- the detail of its OWN view: pool the complementary axes, then the k-dimensional
-- signed sum. Order-2 latents are exactly the isometric faces x:y, x:t, y:t.
lawLatentIsViewDetail :: [Integer] -> Bool
lawLatentIsViewDetail xs =
  and [ viewDetail s v == bandOf v s | s <- axisSubsets ]
  where v = blockFromList xs

-- | LAW (views determine the block, in ℤ[1/2]): @8·v(c) = Σ_S sign_S(c) · band_S@ —
-- character orthogonality of (ℤ/2)³; reconstruction divides only by 8 = 2³.
lawViewsDetermineBlock :: [Integer] -> Bool
lawViewsDetermineBlock xs =
  and [ 8 * v c == sum [ signAt s c * bandOf v s | s <- axisSubsets ] | c <- corners ]
  where v = blockFromList xs

-- | LAW (the unordered spatial pair): swapping x ↔ y permutes the latents by
-- relabeling subsets — {x}↔{y}, {x,t}↔{y,t} — and fixes coarse, {t}, {x,y}, {x,y,t}.
lawXYSwapPermutesLatents :: [Integer] -> Bool
lawXYSwapPermutesLatents xs =
  and [ bandOf vSwap s == bandOf v (map rel s) | s <- axisSubsets ]
  where
    v = blockFromList xs
    vSwap (x, y, t) = v (y, x, t)
    rel AxX = AxY
    rel AxY = AxX
    rel AxT = AxT

-- | LAW (time's arrow lives only in the t-bands): reversing the ordered pair
-- (t, t+1) negates exactly the four bands containing t and fixes the other four.
lawTimeReversalFlipsTBands :: [Integer] -> Bool
lawTimeReversalFlipsTBands xs =
  and [ bandOf vRev s == flipT s (bandOf v s) | s <- axisSubsets ]
  where
    v = blockFromList xs
    vRev (x, y, t) = v (x, y, 1 - t)
    flipT s = if AxT `elem` s then negate else id

-- | LAW (pooling kills its bands — the latent-level t-collapse): replacing both time
-- slices by their sum zeroes exactly the t-containing bands and doubles the rest;
-- on latents, the SpineRing t-collapse kernel is the span of the t-bands.
lawAxisPoolingKillsItsBands :: [Integer] -> Bool
lawAxisPoolingKillsItsBands xs =
  and [ bandOf vPool s == expected s | s <- axisSubsets ]
  where
    v = blockFromList xs
    vPool (x, y, _) = v (x, y, 0) + v (x, y, 1)
    expected s = if AxT `elem` s then 0 else 2 * bandOf v s

-- | LAW (color is a fiber): the lift acts per channel, so every linear color map —
-- the opponent (L, a, b) here — commutes with every band: mixing color axes never
-- touches the base grading. @opp(band) == band(opp)@ on all 8 subsets.
lawColorFiberCommutes :: [Integer] -> Bool
lawColorFiberCommutes xs =
  and [ bandRGB (opponent . v) s == opponent (bandRGB v s) | s <- axisSubsets ]
  where
    padded = take 24 (xs ++ repeat 0)
    v (x, y, t) = ( padded !! (i * 3), padded !! (i * 3 + 1), padded !! (i * 3 + 2) )
      where i = x * 4 + y * 2 + t
