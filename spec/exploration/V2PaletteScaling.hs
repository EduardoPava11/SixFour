{- |
Module      : V2PaletteScaling
Description : EXPLORATION (NOT WIRED, base-only, runghc). The 16x16 = 256 FACT as the foundation of
              palette scaling, and the S/K/I path the PonderNet searches to climb 16^3 -> 64^3 -> 256^3.

  Check:  runghc V2PaletteScaling.hs

  THE FACT (owner directive 2026-06-29): 16 * 16 == 256. This is THE SixFour identity and it MUST drive
  the model:
    * At scale 16: a frame is 16x16 = 256 pixels, EXACTLY a 256-colour palette. So at the coarsest
      scale each of the 16 frames IS its own palette (a bijection square <-> palette). (lawFrameIsPaletteAt16)
    * The number of palettes = the number of frames = the side: 16^3 needs 16 palettes, 64^3 needs 64,
      256^3 needs 256 -- each still 256 colours (16x16). (lawPaletteCountPerScale)
    * To CLIMB the ladder you INVENT palettes with S (expand, x4 per rung = the twiceness), then pool
      with K and hold with I. The path 16 -> 256 is an S/K/I WORD; reaching 256 needs net 2 expansions.
      (lawSKIRolesInScaling, lawPathReaches256)
    * The SEARCH over S/K/I paths is the PonderNet exploring the H (scale hierarchy) of the JEPA; the
      path length is the ponder/read depth. (lawSearchDepthIsPonder)

  Honest boundary: S/K/I here are the SCALE operations (expand/contract/hold), consistent with the
  expand/contract reading of V2SkiNativeGif and the reversible residual word of V2SkiResidualOrder.
  Base-only, runghc, NOT in cabal/Map/gate.
-}
module V2PaletteScaling where

-- ===========================================================================
-- (1) THE FACT: 16 x 16 = 256, and a frame at scale 16 IS a palette
-- ===========================================================================

paletteSize :: Int
paletteSize = 256

squareSide :: Int
squareSide = 16          -- because 16 * 16 == 256

-- | Chunk a flat list into rows of n (a square layout when length == n*n).
chunkInto :: Int -> [a] -> [[a]]
chunkInto _ [] = []
chunkInto n xs = take n xs : chunkInto n (drop n xs)

-- | Lay a 256-entry palette out as a 16x16 frame (and read it back). At scale 16 this IS the frame.
layoutSquare :: [a] -> [[a]]
layoutSquare = chunkInto squareSide

readSquare :: [[a]] -> [a]
readSquare = concat

-- | A full 256-colour palette stand-in (256 distinct entries).
samplePalette :: [Int]
samplePalette = [0 .. 255]

-- ===========================================================================
-- (2) Palette count per scale: frames = palettes = the side
-- ===========================================================================

scales :: [Int]
scales = [16, 64, 256]                 -- the rung spine (x4 apart = the twiceness)

palettesAt :: Int -> Int               -- number of palettes (= frames = the side)
palettesAt s = s

pixelsPerFrame :: Int -> Int           -- a frame is s x s pixels
pixelsPerFrame s = s * s

pixelsPerPaletteEntry :: Int -> Int    -- (s/16)^2 : how many pixels share one of the 256 entries
pixelsPerPaletteEntry s = (s * s) `div` paletteSize

-- ===========================================================================
-- (3) The S/K/I scale operations and the path
-- ===========================================================================

-- | The scale operations: S expands (x4 = invents the new frames/palettes, one twiceness rung),
--   K contracts (pools 4->1), I holds. This is the expand/contract/hold reading at the SCALE level.
data Op = S | K | I deriving (Eq, Show)

applyOp :: Op -> Int -> Int
applyOp S s = s * 4
applyOp K s = s `div` 4
applyOp I s = s

-- | Run an S/K/I word over a starting side (left fold = the order of expression).
runPath :: [Op] -> Int -> Int
runPath ops start = foldl (flip applyOp) start ops

-- | Net expansions = (#S - #K). Reaching 256 from 16 (= x16 = 4^2) needs net 2.
netExpansions :: [Op] -> Int
netExpansions ops = length (filter (== S) ops) - length (filter (== K) ops)

-- | A spread of paths from 16^3 to 256^3 (the search space the PonderNet explores).
searchFamily :: [[Op]]
searchFamily = [ [S, S], [S, I, S], [I, S, S], [S, S, I], [S, K, S, S], [S, S, K, S] ]

-- ===========================================================================
-- (4) Laws
-- ===========================================================================

-- | THE FACT: 16 * 16 == 256, and 16 is the UNIQUE positive side whose square is a 256 palette.
lawSixteenSquaredIs256 :: Bool
lawSixteenSquaredIs256 =
     squareSide * squareSide == paletteSize
  && squareSide == 16 && paletteSize == 256
  && and [ k * k /= 256 | k <- [1 .. 40 :: Int], k /= 16 ]   -- tooth: 16 is the unique side, not 15/17/...

-- | A frame at scale 16 IS a palette: the 256 colours lay out bijectively as a 16x16 grid (16 rows of
--   16), round-tripping byte-exactly. TEETH: 16 rows, each length 16, full 256, exact inverse.
lawFrameIsPaletteAt16 :: Bool
lawFrameIsPaletteAt16 =
     readSquare (layoutSquare samplePalette) == samplePalette        -- round-trip exact
  && length (layoutSquare samplePalette) == 16                       -- 16 rows
  && all ((== 16) . length) (layoutSquare samplePalette)             -- each row 16
  && length samplePalette == 256                                     -- a full palette

-- | The number of palettes is the number of frames is the side: 16/64/256. Each palette is still 256
--   colours (16x16). At scale 16 the pixels-per-entry ratio is 1 (frame == palette, THE FACT); at 64 it
--   is 16, at 256 it is 256.
lawPaletteCountPerScale :: Bool
lawPaletteCountPerScale =
     map palettesAt scales == [16, 64, 256]
  && all (\s -> pixelsPerFrame s `mod` paletteSize == 0) scales       -- pixels partition into 256-palettes
  && map pixelsPerPaletteEntry scales == [1, 16, 256]
  && pixelsPerPaletteEntry 16 == 1                                    -- tooth: at 16 the frame IS the palette

-- | The ladder is the twiceness: each rung is x4 (16 -> 64 -> 256), two octave levels per rung.
lawScalingTwiceness :: Bool
lawScalingTwiceness =
     (64 :: Int) == 16 * 4 && (256 :: Int) == 64 * 4 && (256 :: Int) == 16 * 4 * 4
  && applyOp S 16 == 64 && applyOp S 64 == 256

-- | S expands (invents palettes), K contracts (pools), I holds -- the roles, over the spine. TEETH:
--   S strictly grows, K strictly shrinks, I fixes, at every sampled scale.
lawSKIRolesInScaling :: Bool
lawSKIRolesInScaling =
     applyOp S 16 == 64 && applyOp S 64 == 256                        -- S invents the up-rung palettes
  && applyOp K 256 == 64 && applyOp K 64 == 16                        -- K pools down
  && applyOp I 64 == 64                                               -- I holds
  && and [ applyOp S s > s && applyOp K s < s && applyOp I s == s | s <- [4, 16, 64, 256] ]

-- | The path 16^3 -> 256^3 is an S/K/I WORD. The direct route is [S, S]; detours with I (hold) and
--   K (pool) also reach 256 -- the search FAMILY. Reaching 256 requires net 2 expansions. TEETH:
--   every family path reaches 256 with netExpansions == 2; a single S does NOT reach 256.
lawPathReaches256 :: Bool
lawPathReaches256 =
     runPath [S, S] 16 == 256                                         -- the direct path
  && all (\p -> runPath p 16 == 256) searchFamily                     -- the whole family reaches 256
  && all (\p -> netExpansions p == 2) searchFamily                    -- ... each by net 2 expansions
  && runPath [S] 16 /= 256                                            -- tooth: net 1 does not reach 256
  && runPath [S, K] 16 /= 256                                         -- tooth: net 0 does not reach 256

-- | The SEARCH over paths is the PonderNet exploring the H (scale hierarchy) of the JEPA: the path
--   LENGTH is the ponder/read depth. The minimal-depth route is [S, S] (depth 2); detours cost more
--   ponder depth but reach the same 256^3 (the space PonderNet searches for the ideal path).
lawSearchDepthIsPonder :: Bool
lawSearchDepthIsPonder =
     minimum [ length p | p <- searchFamily, runPath p 16 == 256 ] == 2   -- minimal depth = 2 (S, S)
  && maximum [ length p | p <- searchFamily ] > 2                          -- detours cost ponder depth
  && length (nubInts (map length searchFamily)) > 1                        -- varied depths = a real search space
  where
    nubInts = foldr (\x acc -> if x `elem` acc then acc else x : acc) []

-- ===========================================================================
-- (5) Runner
-- ===========================================================================

laws :: [(String, Bool)]
laws =
  [ ("lawSixteenSquaredIs256   (16*16==256, the unique side: THE FACT)",        lawSixteenSquaredIs256)
  , ("lawFrameIsPaletteAt16    (a 16x16 frame IS a 256-palette, bijective)",    lawFrameIsPaletteAt16)
  , ("lawPaletteCountPerScale  (palettes = frames = side: 16/64/256)",          lawPaletteCountPerScale)
  , ("lawScalingTwiceness      (x4 per rung: 16->64->256)",                     lawScalingTwiceness)
  , ("lawSKIRolesInScaling     (S expands, K pools, I holds)",                  lawSKIRolesInScaling)
  , ("lawPathReaches256        (16->256 is an S/K/I word; net 2 expansions)",   lawPathReaches256)
  , ("lawSearchDepthIsPonder   (path length = PonderNet depth in the JEPA H)",  lawSearchDepthIsPonder)
  ]

main :: IO ()
main = do
  putStrLn "V2PaletteScaling.hs  -- EXPLORATION (NOT WIRED): the 16x16=256 fact + the S/K/I scaling path"
  putStrLn (replicate 72 '-')
  mapM_ (\(n, ok) -> putStrLn (verdict ok ++ "  " ++ n)) laws
  putStrLn (replicate 72 '-')
  let passed = length (filter snd laws)
      total  = length laws
  putStrLn ("SUMMARY: " ++ show passed ++ "/" ++ show total ++ " laws PASS"
            ++ if passed == total then "  (all green)" else "  (FAILURES present)")
  putStrLn ""
  putStrLn ("16 * 16 = " ++ show (squareSide * squareSide) ++ "   (== paletteSize: "
            ++ show (squareSide * squareSide == paletteSize) ++ ")")
  putStrLn ("palettes at 16/64/256 = " ++ show (map palettesAt scales))
  putStrLn ("pixels per palette entry = " ++ show (map pixelsPerPaletteEntry scales)
            ++ "   (1 at scale 16: the frame IS the palette)")
  putStrLn ("path [S,S]   16 -> " ++ show (runPath [S, S] 16)
            ++ "   detour [S,K,S,S] 16 -> " ++ show (runPath [S, K, S, S] 16))
  putStrLn ""
  putStrLn "HONEST NOTE: 16*16=256 is THE fact. At scale 16 a frame IS a palette (256 pixels = 256"
  putStrLn "colours). Climbing to 64/256 palettes INVENTS them with S (x4 per rung), pools with K,"
  putStrLn "holds with I. The path 16->256 is an S/K/I word (net 2 expansions); PonderNet searches that"
  putStrLn "space (the H of the JEPA), path length = ponder depth, for the ideal 256^3."
  where
    verdict True  = "PASS"
    verdict False = "FAIL"
