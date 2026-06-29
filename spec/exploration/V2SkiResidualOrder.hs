{- |
Module      : V2SkiResidualOrder
Description : EXPLORATION (NOT WIRED, base-only, runghc). The residual as a REVERSIBLE SKI word,
              and the search family the user nudges. Proves, via discrete geometry + algebraic
              number theory, that 64^3 + (16^3 residual) -> 256^3 is LOSSLESSLY REVERSIBLE for
              EVERY reduction order, while DIFFERENT orders/depths give DIFFERENT 256^3.

  Check:  runghc V2SkiResidualOrder.hs   (needs V2TrainingLattice.hs in the same dir)

  THE IDEA (owner directive 2026-06-29): the residual is a SKI expression -- a WORD of reversible
  byte-exact generators applied to the coarse frame. Reducing the word builds the 256^3.
    * LOSSLESS = REVERSIBLE (not output-confluence): every word is a composition of byte-exact
      BIJECTIONS, so 'applyWord (invWord w)' undoes 'applyWord w' exactly. You can always return
      to the 64^3 + residual. This is the reversibility the owner demands, tested extensively.
    * ORDER MATTERS: the generators do NOT commute, so different orders (and different DEPTHS, where
      PonderNet halts) give DIFFERENT 256^3 -- the search family the user plays with. Neutral (the
      empty word) is the byte-exact floor.
    * THE ANT PROOF OF REVERSIBILITY: a generator is reversible IFF it is a unit / lattice bijection.
      In Z[w] the invertible elements are EXACTLY the norm-1 units; a non-unit (norm > 1) has NO
      inverse, so it could never be undone. But BYTE-EXACTNESS is stricter than reversibility: a unit
      acts on the residue ca+cb mod 3 by its image in Z[w]/(1-w) = F_3 (the ramified prime!). Since
      w == 1 mod (1-w), the units {1, w, w^2} map to +1 and PRESERVE the index-3 residue (byte-exact
      for ALL luma); the units -1, -w, -w^2 map to -1 and FLIP it (byte-exact only when luma==0 mod 3). So
      the universally byte-exact hue rotations are EXACTLY the C3 subgroup u == 1 mod (1-w) -- a
      sharper consequence of 3 ramifying. Luma shifts move by multiples of 3 (stay in Lambda); swaps
      are permutations (bijections by construction).

  HONEST BOUNDARY: SKI's Church-Rosser gives a UNIQUE full normal form (one canonical 256^3); the
  "different 256^3" are PARTIAL reductions at different order/depth, NOT a violation of confluence.
  The word is a B-composition of reversible ops (the order of expression); see V2SkiLevels for the
  B-stack. Base-only, runghc-checkable, NOT in cabal/Map/gate.
-}
module V2SkiResidualOrder where

import Data.List (foldl', nub)
import V2TrainingLattice
  ( Eisen(..), emul, enorm, units, luma, chroma, lumaChromaToRgb )

-- ===========================================================================
-- (1) The byte-exact frame and the reversible generators (the residual alphabet)
-- ===========================================================================

type RGB = (Int, Int, Int)

-- | A tiny frame of byte-exact points (the 256^3 shadow we reduce the residual over).
type Frame = [RGB]

-- | The C3 subgroup of units that are == 1 mod the ramified prime (1-w): {1, w, w^2}. These map to
--   +1 in Z[w]/(1-w) = F_3, so they PRESERVE the index-3 residue ca+cb mod 3 and are byte-exact hue
--   rotations for EVERY luma. The other 3 units flip the residue (byte-exact only when luma == 0 mod 3).
latticeUnits :: [Eisen]
latticeUnits = [Eisen 1 0, Eisen 0 1, Eisen (-1) (-1)]   -- 1, w, w^2

-- | The inverse of a unit, found WITHIN the 6-element unit group (closed under inverse; the C3
--   subgroup is closed too, so a latticeUnit's inverse is a latticeUnit).
invUnit :: Eisen -> Eisen
invUnit u = head [ v | v <- units, emul u v == Eisen 1 0 ]

-- | Hue-rotate one colour by a unit. Rotation PRESERVES Lambda (l unchanged; ca'+cb' == ca+cb mod 3),
--   so for an integer-RGB input it is always byte-exact (Just). Returns Nothing only off-lattice.
rotHueMaybe :: Eisen -> RGB -> Maybe RGB
rotHueMaybe u rgb = lumaChromaToRgb (luma rgb) (emul u (chroma rgb))

rotHue :: Eisen -> RGB -> RGB
rotHue u rgb = maybe rgb id (rotHueMaybe u rgb)   -- total; the fallback is DEAD (lawEveryRotByteExact)

-- | A reversible byte-exact generator = one step of the SKI residual word.
data Gen
  = Rot   Int Eisen   -- ^ rotate point i's hue by a UNIT u (a norm-1 element of Z[w])
  | Shift Int Int     -- ^ add n to ALL channels of point i (luma += 3n, chroma fixed: stays in Lambda)
  | Swap  Int Int     -- ^ swap points i and j (a permutation)
  deriving (Eq, Show)

atIdx :: Int -> (a -> a) -> [a] -> [a]
atIdx i f xs = [ if k == i then f x else x | (k, x) <- zip [0 ..] xs ]

swapAt :: Int -> Int -> [a] -> [a]
swapAt i j xs = [ pick k | (k, _) <- zip [0 ..] xs ]
  where pick k | k == i    = xs !! j
               | k == j    = xs !! i
               | otherwise = xs !! k

applyGen :: Gen -> Frame -> Frame
applyGen (Rot i u)   = atIdx i (rotHue u)
applyGen (Shift i n) = atIdx i (\(r, g, b) -> (r + n, g + n, b + n))
applyGen (Swap i j)  = swapAt i j

-- | The inverse generator (Rot by the inverse unit; Shift by the negation; Swap is self-inverse).
invGen :: Gen -> Gen
invGen (Rot i u)   = Rot i (invUnit u)
invGen (Shift i n) = Shift i (negate n)
invGen (Swap i j)  = Swap i j

-- | Reduce the residual word over a frame, in order (a left fold = a B-composition chain).
applyWord :: [Gen] -> Frame -> Frame
applyWord w fr = foldl' (flip applyGen) fr w

-- | The inverse word: invert each generator and reverse the order (so it undoes 'applyWord').
invWord :: [Gen] -> [Gen]
invWord = map invGen . reverse

-- ===========================================================================
-- (2) Sample frames, generators, and words (broad, for extensive testing)
-- ===========================================================================

-- | A starting frame: integer RGB, hence already on Lambda (lawMathBackbone: integer RGB is always in Lambda).
state0 :: Frame
state0 = [(255, 0, 0), (0, 255, 0), (0, 0, 255), (40, 40, 40)]

-- | Every generator over the 4-point frame (all units, luma shifts, swaps).
gens :: [Gen]
gens =  [ Rot i u   | i <- [0 .. 3], u <- latticeUnits ]   -- byte-exact hue rotations only (C3)
     ++ [ Shift i n | i <- [0 .. 3], n <- [-3 .. 3] ]
     ++ [ Swap i j  | i <- [0 .. 3], j <- [0 .. 3], i < j ]

-- | A small generator set whose words we enumerate exhaustively (1- to 3-letter = 156 words).
smallGens :: [Gen]
smallGens = [ Rot 0 (Eisen 0 1), Rot 1 (Eisen (-1) (-1)), Shift 2 3, Swap 0 3, Swap 1 2 ]

-- | Many words (the empty word + all 1, 2, 3-letter words over smallGens). The search space.
manyWords :: [[Gen]]
manyWords =  [[]]
          ++ [ [a]       | a <- smallGens ]
          ++ [ [a, b]    | a <- smallGens, b <- smallGens ]
          ++ [ [a, b, c] | a <- smallGens, b <- smallGens, c <- smallGens ]

states :: [Frame]
states = [ state0, map (rotHue (Eisen 1 1)) state0, reverse state0 ]

-- ===========================================================================
-- (3) Laws (the reversibility proof, extensively tested)
-- ===========================================================================

-- | Each generator is byte-exactly reversible: @applyGen (invGen g) . applyGen g == id@, over all gens.
lawGenReversible :: Bool
lawGenReversible = and [ applyGen (invGen g) (applyGen g s) == s | g <- gens, s <- states ]

-- | THE REVERSIBILITY THEOREM: for EVERY word (order) and frame, the inverse word undoes it EXACTLY.
--   This is 64^3 + (16^3 residual word) -> 256^3 -> back, byte-for-byte, for every reduction order.
--   156 words x 3 frames = 468 orderings checked; teeth: the word set includes non-commuting pairs.
lawWordReversible :: Bool
lawWordReversible = and [ applyWord (invWord w) (applyWord w s) == s | w <- manyWords, s <- states ]

-- | Every rotation by a C3 byte-exact unit stays in Lambda (the 'rotHue' fallback is DEAD). TWO teeth
--   prove the guard is real: (1) an image-(-1) unit (-w^2 = Eisen 1 1) rotating a luma /= 0 mod 3 point
--   LEAVES Lambda (so the C3 restriction is necessary, not decorative); (2) a luma move by a NON-multiple
--   of 3 leaves Lambda (so Shift moves all channels = luma by 3).
lawEveryRotByteExact :: Bool
lawEveryRotByteExact =
     and [ rotHueMaybe u rgb /= Nothing | u <- latticeUnits, rgb <- broad ]
  && rotHueMaybe (Eisen 1 1) (1, 0, 0) == Nothing                            -- tooth: image(-1) unit, luma=1, breaks Lambda
  && lumaChromaToRgb (luma (255, 0, 0) + 1) (chroma (255, 0, 0)) == Nothing  -- tooth: luma+1 breaks Lambda
  where broad = [ (r, g, b) | r <- [0, 40, 128, 255], g <- [0, 90, 255], b <- [0, 200] ]

-- | ORDER MATTERS (the search family is real): two words that are REORDERINGS of the same generators
--   give DIFFERENT 256^3, yet EACH is reversible. Non-commutativity is what gives the user choice.
lawOrderMatters :: Bool
lawOrderMatters =
     applyWord wa state0 /= applyWord wb state0                          -- different output
  && applyWord (invWord wa) (applyWord wa state0) == state0              -- but wa reversible
  && applyWord (invWord wb) (applyWord wb state0) == state0              -- and wb reversible
  where
    wa = [Rot 0 (Eisen 0 1), Swap 0 1]
    wb = [Swap 0 1, Rot 0 (Eisen 0 1)]

-- | The empty word is the byte-exact FLOOR (no residual reduced = the unchanged coarse frame). This is
--   the neutral nudge. TOOTH: a non-empty word actually moves the frame (the floor is not everything).
lawEmptyWordIsFloor :: Bool
lawEmptyWordIsFloor =
     applyWord [] state0 == state0
  && applyWord [Rot 0 (Eisen 0 1)] state0 /= state0

-- | DEPTH = the PonderNet halt step: the prefixes of a word are the search family by reduction depth.
--   Depth 0 = the floor; full depth = the canonical reduction; intermediate depths DIFFER (a real
--   family); and EVERY depth is reversible (you can always undo or continue). Reuses lawWordReversible's
--   guarantee at each prefix length.
lawDepthIsPonderHalt :: Bool
lawDepthIsPonderHalt =
     head prefs == state0                                               -- depth 0 = floor
  && last prefs == applyWord w state0                                   -- full depth = canonical 256^3
  && length (nub prefs) > 1                                             -- the family is non-trivial
  && and [ applyWord (invWord (take k w)) (prefs !! k) == state0 | k <- [0 .. length w] ]  -- each depth reversible
  where
    w     = [Rot 0 (Eisen 0 1), Shift 1 3, Swap 2 3, Rot 0 (Eisen (-1) (-1))]
    prefs = [ applyWord (take k w) state0 | k <- [0 .. length w] ]

-- | THE ANT PROOF OF REVERSIBILITY: reversibility holds BECAUSE every generator is a byte-exact lattice
--   BIJECTION grounded in algebraic number theory.
--     * Rot uses a UNIT: norm-1 elements are EXACTLY the invertibles of Z[w], and the inverse is another
--       unit ('invUnit'). A non-unit (norm > 1) has NO inverse in Z[w] (tooth) -- it could never be undone.
--     * Shift moves luma by a multiple of 3 -> stays in the index-3 sublattice Lambda (byte-exact).
--     * Swap is a permutation (a bijection by construction).
--   So "every order is reversible" is a THEOREM about the unit group, not an assumption.
lawReversibleBecauseANT :: Bool
lawReversibleBecauseANT =
     -- reversibility <=> unit: norm-1 units are invertible; a non-unit (norm 4) has NO inverse in Z[w]
     all (\u -> enorm u == 1 && emul u (invUnit u) == Eisen 1 0) units
  && enorm (Eisen 2 0) > 1
  && null [ v | v <- intSample, emul (Eisen 2 0) v == Eisen 1 0 ]                 -- non-unit: no inverse (tooth)
     -- byte-exact <=> C3: the latticeUnits PRESERVE the index-3 residue ca+cb mod 3 (the ramified prime)
  && and [ residue (emul u c) == residue c | u <- latticeUnits, c <- chromas ]
     -- ... while the image(-1) unit -w^2 FLIPS it, so the C3 restriction is FORCED, not decorative (tooth)
  && or  [ residue (emul (Eisen 1 1) c) /= residue c | c <- chromas ]
  && and [ applyGen (invGen g) (applyGen g state0) == state0 | g <- gens ]        -- => every generator reverses
  where
    intSample = [ Eisen a b | a <- [-9 .. 9], b <- [-9 .. 9] ]
    chromas   = [ Eisen a b | a <- [-4 .. 4], b <- [-4 .. 4] ]
    residue (Eisen a b) = (a + b) `mod` 3

-- ===========================================================================
-- (4) Runner (mirrors GifSki.hs)
-- ===========================================================================

laws :: [(String, Bool)]
laws =
  [ ("lawGenReversible        (each generator byte-exactly reverses)",          lawGenReversible)
  , ("lawWordReversible       (EVERY order reverses: 468 orderings)",           lawWordReversible)
  , ("lawEveryRotByteExact    (hue rotation never leaves Lambda; luma+1 does)", lawEveryRotByteExact)
  , ("lawOrderMatters         (reorderings give different 256^3, each reversible)", lawOrderMatters)
  , ("lawEmptyWordIsFloor     (empty residual = the byte-exact floor)",         lawEmptyWordIsFloor)
  , ("lawDepthIsPonderHalt    (prefixes = search family by depth, each reversible)", lawDepthIsPonderHalt)
  , ("lawReversibleBecauseANT (reversible <=> unit; non-unit has no inverse)",  lawReversibleBecauseANT)
  ]

main :: IO ()
main = do
  putStrLn "V2SkiResidualOrder.hs  -- EXPLORATION (NOT WIRED): the residual as a reversible SKI word"
  putStrLn (replicate 72 '-')
  mapM_ (\(n, ok) -> putStrLn (verdict ok ++ "  " ++ n)) laws
  putStrLn (replicate 72 '-')
  let passed = length (filter snd laws)
      total  = length laws
  putStrLn ("SUMMARY: " ++ show passed ++ "/" ++ show total ++ " laws PASS"
            ++ if passed == total then "  (all green)" else "  (FAILURES present)")
  putStrLn ""
  let wa = [Rot 0 (Eisen 0 1), Swap 0 1]
      wb = [Swap 0 1, Rot 0 (Eisen 0 1)]
  putStrLn ("order A (rot,swap) state0 = " ++ show (applyWord wa state0))
  putStrLn ("order B (swap,rot) state0 = " ++ show (applyWord wb state0)
            ++ "   (different 256^3: " ++ show (applyWord wa state0 /= applyWord wb state0) ++ ")")
  putStrLn ("A reverses: " ++ show (applyWord (invWord wa) (applyWord wa state0) == state0)
            ++ "   B reverses: " ++ show (applyWord (invWord wb) (applyWord wb state0) == state0))
  putStrLn ""
  putStrLn "HONEST NOTE: lossless = REVERSIBILITY (every order undoes byte-exactly), proven via ANT"
  putStrLn "(reversible <=> norm-1 unit of Z[w]; a non-unit has no inverse). DIFFERENT 256^3 come from"
  putStrLn "different ORDER and DEPTH (PonderNet halt) of the SKI residual word, NOT from breaking SKI"
  putStrLn "confluence (the full normal form stays the one canonical 256^3). The empty word is the floor."
  where
    verdict True  = "PASS"
    verdict False = "FAIL"
