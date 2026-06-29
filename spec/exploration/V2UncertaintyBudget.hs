{- |
Module      : V2UncertaintyBudget
Description : EXPLORATION (NOT WIRED, base-only, runghc). The FOUNDATION for the nudge: the
              conserved uncertainty budget of the coarse-vs-residual deconstruction, in V2
              byte-exact integer form (the reversible octree Haar lift, NOT floating-point entropy).

  Check:  runghc V2UncertaintyBudget.hs

  THE FUNCTION (owner directive 2026-06-29): the user nudges HOW the 64^3 deconstructs into
  coarse + residual. The web-searched math (Heisenberg/Gabor/entropic uncertainty) says space and
  scale are conjugate: you cannot sharpen both. The V2 FORM of that conservation is the reversible
  octree Haar lift over integers:
    * 8 voxels  <->  1 coarse (DC) + 7 detail (the residual).  Reversible = a BIJECTION = lossless
      (the real conserved quantity: information, not a slogan).
    * The coarse is RANK ONE (one DC value); so all spatial STRUCTURE is FORCED into the residual:
      detailSupport == 0 IFF the signal is flat. Structure <=> residual. (lawStructureRequiresResidual)
    * The nudge REALLOCATES content between coarse and residual; the coarse (global summary) is the
      INVARIANT, the residual is what moves. (lawResidualEditPreservesCoarse) Neutral = zero residual
      = the byte-exact floor. (lawZeroResidualIsFloor)

  HONEST NEGATIVE (anti-forced-jargon): the Haar is the multiresolution GOOD COMPROMISE, so it does
  NOT obey a strong support-Heisenberg bound -- a basis-aligned delta maps to a SINGLE coefficient
  (suppSpace == 1 AND suppScale == 1, product 1). We prove this (lawHaarHasNoStrongHeisenberg) rather
  than claim an uncertainty the transform lacks. The genuine conservation is the BIJECTION + the 1+7
  dimension split, which IS what the nudge trades against.

  Ties: the residual is the reversible SKI word of V2SkiResidualOrder; the lift is the octree spine.
  Base-only, runghc-checkable, NOT in cabal/Map/gate.
-}
module V2UncertaintyBudget where

-- ===========================================================================
-- (1) The reversible integer Haar lift (the V2 byte-exact transform)
-- ===========================================================================

-- | One lifting step on a pair: detail = b - a, coarse = a + floor(detail/2). Reversible over Z.
haarStep :: (Int, Int) -> (Int, Int)
haarStep (a, b) = let d = b - a; s = a + (d `div` 2) in (s, d)

unHaarStep :: (Int, Int) -> (Int, Int)
unHaarStep (s, d) = let a = s - (d `div` 2); b = a + d in (a, b)

pairUp :: [Int] -> [(Int, Int)]
pairUp (a : b : rest) = (a, b) : pairUp rest
pairUp _              = []

unpair :: [(Int, Int)] -> [Int]
unpair ((a, b) : rest) = a : b : unpair rest
unpair _               = []

-- | One Haar level over an even-length list: returns (coarses, details).
levelF :: [Int] -> ([Int], [Int])
levelF xs = let sds = map haarStep (pairUp xs) in (map fst sds, map snd sds)

-- | Inverse of one level: coarses + details -> the original list.
levelB :: [Int] -> [Int] -> [Int]
levelB ss ds = unpair (map unHaarStep (zip ss ds))

-- | The full 8-point octant Haar: 8 voxels -> [coarse(DC), 7 detail]. This is the octree octant.
haar8 :: [Int] -> [Int]
haar8 xs0 =
  let (s0, d0) = levelF xs0      -- 4 coarse, 4 detail
      (s1, d1) = levelF s0       -- 2 coarse, 2 detail
      (s2, d2) = levelF s1       -- 1 coarse, 1 detail
  in s2 ++ d2 ++ d1 ++ d0        -- 1 + 1 + 2 + 4 = 8

-- | The inverse: [coarse, 7 detail] -> 8 voxels.
unhaar8 :: [Int] -> [Int]
unhaar8 cs =
  let s2 = take 1 cs
      d2 = take 1 (drop 1 cs)
      d1 = take 2 (drop 2 cs)
      d0 = take 4 (drop 4 cs)
      s1 = levelB s2 d2
      s0 = levelB s1 d1
  in levelB s0 d0

-- ===========================================================================
-- (2) Coarse / residual / supports
-- ===========================================================================

coarseDC :: [Int] -> Int
coarseDC = head . haar8

residual :: [Int] -> [Int]            -- the 7 detail bands (the SKI residual word's content)
residual = drop 1 . haar8

detailSupport :: [Int] -> Int         -- how many residual bands are active (structure richness)
detailSupport = length . filter (/= 0) . residual

suppSpace :: [Int] -> Int             -- active voxels (spatial occupancy)
suppSpace = length . filter (/= 0)

suppScale :: [Int] -> Int             -- active Haar coefficients (coarse + detail)
suppScale = length . filter (/= 0) . haar8

isFlat :: [Int] -> Bool
isFlat xs = all (== head xs) xs

-- The signal space we enumerate over (3^8 = 6561 integer octants in {-1,0,1}).
box :: [[Int]]
box = sequence (replicate 8 [-1, 0, 1])

nonflat :: [[Int]]
nonflat = filter (not . isFlat) box

-- ===========================================================================
-- (3) Laws
-- ===========================================================================

-- | THE CONSERVATION SUBSTRATE: the lift is a BIJECTION over the whole box (lossless byte-exact).
--   Information is conserved; the nudge can only MOVE it, never create or destroy it.
lawHaarReversible :: Bool
lawHaarReversible = all (\x -> unhaar8 (haar8 x) == x) box

-- | THE 1+7 DIMENSION SPLIT: the octant is 1 coarse (DC) + 7 residual. Structural, exact.
lawDimensionSplit :: Bool
lawDimensionSplit =
     all (\x -> length (haar8 x) == 8) box
  && all (\x -> length (residual x) == 7) box
  && all (\x -> coarseDC x : residual x == haar8 x) box

-- | STRUCTURE <=> RESIDUAL (the core conservation): the coarse is rank-1 (a single DC value), so the
--   residual is zero IFF the signal is flat. ANY spatial structure is FORCED into the residual.
--   TEETH: both directions over 6561 signals (a non-flat signal always spends residual; a flat one never).
lawStructureRequiresResidual :: Bool
lawStructureRequiresResidual =
     all (\x -> (detailSupport x == 0) == isFlat x) box
  && any (\x -> detailSupport x > 0) box                  -- tooth: structure exists and costs residual
  && detailSupport [0,0,0,0,0,0,0,0] == 0                 -- tooth: the flat floor spends nothing

-- | NEUTRAL = FLOOR: zeroing the residual (the empty SKI word) reconstructs a FLAT signal = the
--   byte-exact deterministic coarse upsample. The neutral nudge is the lossless floor.
lawZeroResidualIsFloor :: Bool
lawZeroResidualIsFloor =
  all (\x -> let floored = unhaar8 (coarseDC x : replicate 7 0)
             in isFlat floored && detailSupport floored == 0) box

-- | THE NUDGE REALLOCATES, THE COARSE IS INVARIANT: edit the residual (any new 7 bands), and the
--   coarse (DC global summary) is preserved while the spatial content changes. The bijection makes
--   the reallocation lossless. TEETH: a residual edit that genuinely changes the signal, yet the
--   coarse is byte-identical and the edit round-trips.
lawResidualEditPreservesCoarse :: Bool
lawResidualEditPreservesCoarse =
  all check sampleEdits
  where
    sampleEdits = [ (x, ed) | x <- take 200 nonflat, ed <- [ replicate 7 0, [1,0,0,0,0,0,0], reverse (residual x) ] ]
    check (x, ed) =
      let c  = coarseDC x
          x' = unhaar8 (c : ed)
      in coarseDC x' == c                       -- coarse conserved under residual reallocation
         && haar8 x' == c : ed                  -- the edit round-trips (lossless reallocation)

-- | THE HONEST TRADEOFF: lowering the residual smooths the signal. Concretely, the ONLY signals with
--   detailSupport 0 are flat (max spatial uniformity); and zeroing residual bands strictly reduces the
--   number of distinct voxel values (it cannot add structure). TEETH: a witness where dropping the
--   residual collapses a structured signal to a flat one.
lawLessResidualMeansSmoother :: Bool
lawLessResidualMeansSmoother =
     all (\x -> distinctVals (unhaar8 (coarseDC x : replicate 7 0)) <= distinctVals x) box
  && distinctVals witness > 1
  && distinctVals (unhaar8 (coarseDC witness : replicate 7 0)) == 1   -- residual removed -> flat
  where
    witness = [3, 3, 3, 3, 9, 9, 1, 1]
    distinctVals = length . dedup
    dedup = foldr (\v acc -> if v `elem` acc then acc else v : acc) []

-- | HONEST NEGATIVE (anti-forced-jargon): the octree Haar does NOT obey a strong support-Heisenberg
--   bound -- it is the multiresolution GOOD COMPROMISE. A basis-aligned delta maps to a SINGLE
--   coefficient, so suppSpace == 1 AND suppScale == 1 (product 1) is REACHABLE. We assert this so the
--   foundation never overclaims an uncertainty the transform lacks; the real conservation is the
--   bijection + the 1+7 split above.
lawHaarHasNoStrongHeisenberg :: Bool
lawHaarHasNoStrongHeisenberg =
     suppSpace delta == 1 && suppScale delta == 1          -- a delta localized in BOTH space and scale
  && minimum [ suppSpace x * suppScale x | x <- nonzero ] == 1   -- the support-product floor is 1, not n
  where
    delta   = [1, 0, 0, 0, 0, 0, 0, 0]
    nonzero = filter (any (/= 0)) box

-- ===========================================================================
-- (4) Runner
-- ===========================================================================

laws :: [(String, Bool)]
laws =
  [ ("lawHaarReversible            (the lift is a bijection: lossless conservation)", lawHaarReversible)
  , ("lawDimensionSplit            (octant = 1 coarse + 7 residual, exact)",          lawDimensionSplit)
  , ("lawStructureRequiresResidual (detail=0 IFF flat: structure <=> residual)",      lawStructureRequiresResidual)
  , ("lawZeroResidualIsFloor       (neutral nudge = flat byte-exact floor)",          lawZeroResidualIsFloor)
  , ("lawResidualEditPreservesCoarse (nudge reallocates; coarse invariant, lossless)", lawResidualEditPreservesCoarse)
  , ("lawLessResidualMeansSmoother (the honest space<->residual tradeoff)",           lawLessResidualMeansSmoother)
  , ("lawHaarHasNoStrongHeisenberg (HONEST NEGATIVE: Haar = good compromise, floor 1)", lawHaarHasNoStrongHeisenberg)
  ]

main :: IO ()
main = do
  putStrLn "V2UncertaintyBudget.hs  -- EXPLORATION (NOT WIRED): the conserved coarse/residual budget"
  putStrLn (replicate 72 '-')
  mapM_ (\(n, ok) -> putStrLn (verdict ok ++ "  " ++ n)) laws
  putStrLn (replicate 72 '-')
  let passed = length (filter snd laws)
      total  = length laws
  putStrLn ("SUMMARY: " ++ show passed ++ "/" ++ show total ++ " laws PASS"
            ++ if passed == total then "  (all green)" else "  (FAILURES present)")
  putStrLn ""
  let s = [3, 3, 3, 3, 9, 9, 1, 1]
  putStrLn ("signal           = " ++ show s)
  putStrLn ("haar8 (1+7)      = " ++ show (haar8 s) ++ "   coarse=" ++ show (coarseDC s)
            ++ " detailSupport=" ++ show (detailSupport s))
  putStrLn ("residual zeroed  = " ++ show (unhaar8 (coarseDC s : replicate 7 0)) ++ "   (flat = the floor)")
  putStrLn ""
  putStrLn "HONEST NOTE: the conserved quantity is the BIJECTION (lossless) + the 1 coarse + 7 residual"
  putStrLn "dimension split; structure is FORCED into the residual (coarse is rank-1 DC). The nudge"
  putStrLn "reallocates content into/out of the residual; the coarse summary is the invariant. The Haar"
  putStrLn "is the multiresolution compromise, so there is NO strong support-Heisenberg bound (proven)."
  where
    verdict True  = "PASS"
    verdict False = "FAIL"
