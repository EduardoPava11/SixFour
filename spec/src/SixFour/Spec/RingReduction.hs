{- |
Module      : SixFour.Spec.RingReduction
Description : The single float→device crossing (@reenterQ16@) as a RING REDUCTION between a fine "big" grid (the Mac/MLX float twin) and the coarse "small" Q16 device grid: an @embed@ (the small grid sits inside the big one) with a @reduce@ (round the extra fractional bits, half-to-even). The structural facts are that @reduce@ is a RETRACTION onto the grid (@reduce ∘ embed = id@, grid points are fixpoints), it is IDEMPOTENT (the terminal quantization), and it is ELEMENTWISE (batched = per-element, no cross-band coupling) — these are exactly the @reenterQ16@ contract generalized to any (big, small) dyadic-grid pair.

HONEST BOUNDARY (the analysis flagged "reduce labelled a ring HOMOMORPHISM" as an overclaim, so it
is a LAW here, not a silent assumption): rounding from the fine grid is NOT additive off the coarse
grid — @reduce@ is a retraction/quantizer, NOT a ring homomorphism. 'lawReduceIsNotAdditive' exhibits
@reduce (x+y) ≠ reduce x + reduce y@ (two 0.5s). What IS exact: the grid fixpoints, idempotence, and
the half-to-even tie rule. Generalizes @q16.quantize_q16@ / @reenterQ16@; see "SixFour.Spec.ScaleFiltration"
(the dyadic scale these grids sit on).
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.RingReduction
  ( -- * The two dyadic grids
    Q16(..)
  , Big(..)
  , gap
  , addQ16
    -- * The crossing
  , embed
  , reduce
  , reduceBatch
  , roundHalfEven
    -- * Laws
  , lawReduceEmbedId
  , lawReduceIdempotent
  , lawReduceHalfToEven
  , lawReduceIsNotAdditive
  , lawReduceBatchedIsElementwise
  ) where

-- | A value on the COARSE (device) grid: the integer @value · 2^16@ (Q16 fixed point).
newtype Q16 = Q16 Integer deriving (Eq, Show)

-- | A value on the FINE (Mac/MLX float twin) grid: the integer @value · 2^32@. The coarse grid
-- embeds into this one; @reduce@ rounds back.
newtype Big = Big Integer deriving (Eq, Show)

-- | Fine units per coarse quantum: @2^(32-16) = 2^16@ (the 16 fractional bits @reduce@ collapses).
gap :: Integer
gap = 2 ^ (16 :: Int)

-- | Coarse-grid addition (the small ring's @+@).
addQ16 :: Q16 -> Q16 -> Q16
addQ16 (Q16 a) (Q16 b) = Q16 (a + b)

-- | Round @b / k@ to the nearest integer, ties to EVEN (banker's / half-to-even). Works for
-- negatives via floor-division with non-negative remainder.
roundHalfEven :: Integer -> Integer -> Integer
roundHalfEven b k =
  let (q, r) = b `divMod` k        -- r ∈ [0,k), q = floor(b/k)
  in case compare (2 * r) k of
       LT -> q
       GT -> q + 1
       EQ -> if even q then q else q + 1

-- | The section: a coarse grid value sits exactly inside the fine grid (multiply by 'gap').
embed :: Q16 -> Big
embed (Q16 q) = Big (q * gap)

-- | The reduction / device crossing: round the fine value onto the coarse grid, half-to-even.
reduce :: Big -> Q16
reduce (Big b) = Q16 (roundHalfEven b gap)

-- | Batched reduction is exactly per-element (no cross-band coupling).
reduceBatch :: [Big] -> [Q16]
reduceBatch = map reduce

-- ---------------------------------------------------------------------------
-- Laws.
-- ---------------------------------------------------------------------------

-- | RETRACTION: grid points are fixpoints — @reduce ∘ embed = id@. (A coarse value lifted into the
-- fine grid and rounded back is unchanged.)
lawReduceEmbedId :: Integer -> Bool
lawReduceEmbedId n = reduce (embed (Q16 n)) == Q16 n

-- | IDEMPOTENT terminal quantization: rounding an already-rounded value changes nothing —
-- @reduce ∘ embed ∘ reduce = reduce@.
lawReduceIdempotent :: Integer -> Bool
lawReduceIdempotent b = reduce (embed (reduce (Big b))) == reduce (Big b)

-- | The half-to-even tie rule (the byte-exact commit): @0.5 → 0@, @1.5 → 2@, @2.5 → 2@, @-0.5 → 0@.
lawReduceHalfToEven :: Bool
lawReduceHalfToEven =
     reduce (Big (0 * gap + h)) == Q16 0      -- 0.5 → 0 (even)
  && reduce (Big (1 * gap + h)) == Q16 2      -- 1.5 → 2 (even)
  && reduce (Big (2 * gap + h)) == Q16 2      -- 2.5 → 2 (even)
  && reduce (Big (negate h))    == Q16 0      -- -0.5 → 0 (even)
  where h = gap `div` 2

-- | THE honest boundary: @reduce@ is a quantizer, NOT a ring homomorphism. Two half-quanta each
-- round DOWN to 0, but their sum is a full quantum that rounds to 1: @reduce (x+y) ≠ reduce x + reduce y@.
lawReduceIsNotAdditive :: Bool
lawReduceIsNotAdditive =
  let h = gap `div` 2
      x = Big h            -- 0.5
      y = Big h            -- 0.5
      Big bx = x
      Big by = y
  in reduce (Big (bx + by)) /= addQ16 (reduce x) (reduce y)   -- reduce(1.0)=1  ≠  0 + 0

-- | ELEMENTWISE: batched reduction distributes over concatenation (no element couples to another).
lawReduceBatchedIsElementwise :: [Integer] -> [Integer] -> Bool
lawReduceBatchedIsElementwise xs ys =
  reduceBatch (map Big (xs ++ ys)) == reduceBatch (map Big xs) ++ reduceBatch (map Big ys)
