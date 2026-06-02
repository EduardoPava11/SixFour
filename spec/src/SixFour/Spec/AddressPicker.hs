{- |
Module      : SixFour.Spec.AddressPicker
Description : Address↔leaf mapping for the iOS picker widget. Radix-r d-digit addresses that select leaves in a collapsed SplitTree.

The Review screen's AddressPickerView is a multi-component iOS picker (N wheels, each base=factor)
that selects a leaf in the current frame's median-cut SplitTree. The picker is the honest UI form
of "a 2⁸ is 8 binary splits": each wheel labelled with the real split (axis@pos) it controls,
derived from the binary tree path at that collapsed level.

This module pins the address↔leaf-index bijection:
- A d-digit address in radix @factor@ (where @factor^d = 256@) is the in-order position
  of a leaf in the collapsed NaryTree tree.
- Each digit D ∈ [0, factor−1] selects one "collapsed binary level" (k = log₂ factor binary levels).
- The binary address is the digit sequence expanded to collapseK bits per digit (big-endian).
- A binary address [b₀, b₁, …, b₇] (8 bits) indexes the leaf path: 0=lo, 1=hi at each step.
- The axis@pos LABEL for digit d is read from the binary tree path at levels [k*d, k*d+k).

Contract-first: these are total functions, verified bit-for-bit against leafPaths + descendants.
-}
module SixFour.Spec.AddressPicker
  ( -- * Digit ↔ binary address conversion
    digitsToBinaryAddress
  , binaryAddressToDigits
    -- * Leaf selection by n-ary address
  , leafIndexOfAddress
  , addressOfLeafIndex
    -- * Split axis/position extraction per digit
  , axisAndPosAtDigit
  , axisAtDigit
  , posAtDigit
    -- * Shape and invariants
  , digitsPerLevel
  , digitCount
    -- * Laws (predicates; QuickCheck'd in Properties.AddressPicker)
    -- (round-trip law is `lawPickerAddressRoundTrip` to avoid colliding with
    --  SplitTree's binary-prefix `lawAddressRoundTrip`.)
  , lawPickerAddressRoundTrip
  , lawAddressInjectivity
  , lawDigitCountEqualsDepth
  , lawAddressArithmeticInvariant
  ) where

import Data.List (foldl')
import SixFour.Spec.SplitTree

-- | Convert an n-ary address (list of digits in base @factor@) to a binary address (list of bits [0,1]).
-- Each digit d is unpacked to collapseK bits in big-endian order.
-- For 4⁴: digits [0, 1, 2, 3] → k=2, digits [0,1,2,3] each expand to 2 bits
--         [0]→[0,0], [1]→[0,1], [2]→[1,0], [3]→[1,1]
--         → binary [0,0, 0,1, 1,0, 1,1]
digitsToBinaryAddress :: Branching -> [Int] -> [Int]
digitsToBinaryAddress b digits = concatMap (\d -> decimalToBits k d) digits
  where k = collapseK b

-- | Convert a binary address (list of bits) to an n-ary address (digits in base @factor@).
-- Group every collapseK bits and interpret each group as a decimal digit.
binaryAddressToDigits :: Branching -> [Int] -> [Int]
binaryAddressToDigits b bits = map (bitsToDecimal . take k) (chunksOf k bits)
  where k = collapseK b

-- | Split a list into chunks of size n (last chunk may be shorter).
chunksOf :: Int -> [a] -> [[a]]
chunksOf _ [] = []
chunksOf n xs = take n xs : chunksOf n (drop n xs)

-- | Convert a decimal number to its binary representation in k bits (big-endian, padded).
decimalToBits :: Int -> Int -> [Int]
decimalToBits k n = reverse [ if testBit n i then 1 else 0 | i <- [0 .. k - 1] ]
  where
    testBit x i = (x `div` (2 ^ i)) `mod` 2 == 1

-- | Convert a list of bits to a decimal number (big-endian).
bitsToDecimal :: [Int] -> Int
bitsToDecimal bits = foldl' (\acc b -> acc * 2 + b) 0 bits

-- | Leaf index (in-order position in the leaves array) for a given n-ary address.
-- The address is a sequence of digits, each selecting one child at its level.
-- We traverse the binary tree using the expanded binary path, then find the resulting leaf
-- in the canonical leaves list.
leafIndexOfAddress :: Branching -> [Int] -> SplitTree -> Maybe Int
leafIndexOfAddress b digits tree
  | length digits /= digitCount b = Nothing
  | otherwise =
      let binAddr = digitsToBinaryAddress b digits
      in case subtreeAt binAddr tree of
        Just (Leaf ic) -> Just (findLeafPos ic (leaves tree))
        _              -> Nothing
  where
    findLeafPos ic ics = go 0 ics
      where
        go _ [] = 0  -- unreachable for valid trees with valid addresses
        go i (x : xs) | icIndex x == icIndex ic = i
                      | otherwise               = go (i + 1) xs

-- | N-ary address (digit sequence) for a leaf at a given index (in-order position in leaves array).
-- Invert the relationship: given the leaf index, find its binary path from leafPaths, 
-- then collapse to digits.
addressOfLeafIndex :: Branching -> Int -> SplitTree -> Maybe [Int]
addressOfLeafIndex b leafIdx tree
  | leafIdx < 0 || leafIdx >= length (leaves tree) = Nothing
  | otherwise =
      let ic = (leaves tree) !! leafIdx
          paths = leafPaths tree
          binAddr = case [ p | (p, ic') <- paths, icIndex ic' == icIndex ic ] of
            (p : _) -> p
            []      -> []
      in Just (binaryAddressToDigits b binAddr)

-- | Extract the (SplitAxis, position) pair that labels a given digit level.
-- Follow the binary tree from the root for collapseK*d levels, reading the FIRST split axis
-- and position encountered in that initial range. This is the axis controlling digit d.
axisAndPosAtDigit :: Branching -> Int -> SplitTree -> Maybe (SplitAxis, Double)
axisAndPosAtDigit b d tree
  | d < 0 || d >= digitCount b = Nothing
  | otherwise =
      let k = collapseK b
          startLvl = k * d
      in readAxisAtLevel startLvl tree
  where
    -- Traverse the tree, counting depth, and return the first split we hit at or after startLvl.
    readAxisAtLevel lvl t = go 0 t
      where
        go depth (Leaf _)
          | depth >= lvl = Nothing  -- ran out of tree before reaching startLvl
          | otherwise    = Nothing
        go depth (Branch ax pos l r)
          | depth == lvl = Just (ax, pos)  -- found the split at the requested level
          | depth < lvl  = 
              -- continue deeper; try left first, then right
              case go (depth + 1) l of
                Just x  -> Just x
                Nothing -> go (depth + 1) r
          | otherwise = Nothing  -- already past the target level

-- | The SplitAxis that labels a digit level.
axisAtDigit :: Branching -> Int -> SplitTree -> Maybe SplitAxis
axisAtDigit b d tree = fst <$> axisAndPosAtDigit b d tree

-- | The split position that labels a digit level.
posAtDigit :: Branching -> Int -> SplitTree -> Maybe Double
posAtDigit b d tree = snd <$> axisAndPosAtDigit b d tree

-- | Digit count for a branching: @branchDepth b@.
digitsPerLevel :: Branching -> Int
digitsPerLevel = branchDepth

-- | Total digit count (same as digitsPerLevel, for semantic clarity).
digitCount :: Branching -> Int
digitCount = branchDepth

--------------------------------------------------------------------------------
-- Laws (predicates; exercised by Properties.AddressPicker)
--------------------------------------------------------------------------------

-- Implication, as in SplitTree.hs.
infix 1 ==>
(==>) :: Bool -> Bool -> Bool
p ==> q = not p || q

-- | Every leaf can be retrieved by its address, and the address round-trips exactly.
lawPickerAddressRoundTrip :: Branching -> SplitTree -> Bool
lawPickerAddressRoundTrip b tree =
  all ok [0 .. length (leaves tree) - 1]
  where
    ok idx =
      case addressOfLeafIndex b idx tree of
        Just addr ->
          case leafIndexOfAddress b addr tree of
            Just idx' -> idx' == idx
            Nothing   -> False
        Nothing -> False

-- | All addresses are distinct: each leaf has a unique address (the mapping is injective).
lawAddressInjectivity :: Branching -> SplitTree -> Bool
lawAddressInjectivity b tree =
  let addrs = [ addressOfLeafIndex b i tree | i <- [0 .. length (leaves tree) - 1] ]
      justAddrs = [ a | Just a <- addrs ]
  in length justAddrs == length (nubAddrs justAddrs)
  where
    nubAddrs [] = []
    nubAddrs (x : xs) = x : nubAddrs (filter (/= x) xs)

-- | Digit count of a valid address always equals @branchDepth b@.
lawDigitCountEqualsDepth :: Branching -> [Int] -> Bool
lawDigitCountEqualsDepth b addr =
  length addr == digitCount b  -- valid addresses have this length

-- | Arithmetic law: @factor^depth = 256@ for all branchings, and address arithmetic is consistent.
lawAddressArithmeticInvariant :: Bool
lawAddressArithmeticInvariant =
  all (\b -> branchFactor b ^ digitCount b == 256) [B16, B4, B2]
