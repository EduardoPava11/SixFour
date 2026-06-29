{- |
Module      : V2A2ClosestPoint
Description : EXPLORATION (NOT WIRED, base-only, runghc). The TRUE A2 closest-point onto
              the index-3 sublattice Lambda, fixing V2TrainingLattice.snapToLambda.

  Check:  runghc V2A2ClosestPoint.hs
  (fallback: cd ../ && cabal exec -- runghc exploration/V2A2ClosestPoint.hs)

  THE GAP (owner directive 2026-06-29): V2TrainingLattice.snapToLambda only moves LUMA DOWN by
  the residual r to enter the congruence class Lambda = {(l,ca,cb) : l == ca+cb (mod 3)}. That
  is NOT the nearest lattice point under the training metric
        cost (l0,c0) (l1,c1) = |l1 - l0|  +  N(c1 - c0)        -- lumaL1 + Eisenstein (A2) norm
  (the very metric of V2TrainingLattice.trainLoss). This module builds the genuine closest point.

  WHAT IS REAL (no forced jargon): the metric, the candidate moves and the argmin are honest.
  Because a single luma step (+-1) ALWAYS re-enters Lambda when r/=0, the global minimum cost is
  provably <= 1, and we enumerate EVERY cost-<=1 move (luma +-1 with no chroma move, plus the 6
  unit chroma shifts with no luma move, plus the identity). So the argmin over this finite
  candidate set is the GLOBAL minimum, not merely a local one (proven below, and independently
  cross-checked by brute force over a radius-3 neighbourhood).

  HONEST BOUNDARY (stated, not overclaimed): under THIS metric a unit luma step and a minimal
  unit chroma shift BOTH cost exactly 1, so a chroma move never costs strictly LESS than the
  best luma step (they tie). The genuine fix over snapToLambda is therefore (a) choosing the
  cheaper luma DIRECTION (up vs down) and (b) recognising the equal-cost chroma alternatives.
  A chroma move IS strictly cheaper than snapToLambda's SUBOPTIMAL down-by-2 move (cost 1 < 2),
  which is the witness the strictly-better law exhibits.

  Base-only, runghc-checkable, NOT in any cabal file, Map, or gate. Reuses V2TrainingLattice.
-}
module V2A2ClosestPoint where

import Data.List (minimumBy)
import Data.Ord (comparing)
import V2TrainingLattice
  ( Eisen(..)
  , enorm
  , esub
  , eadd
  , emul
  , units
  , luma
  , chroma
  , lumaChromaToRgb
  , snapToLambda
  )

-- ===========================================================================
-- (1) The training metric on (luma, Eisenstein chroma) coordinates
-- ===========================================================================

-- | A lattice point in the (luma, chroma) coordinate system the trainer snaps in.
type Pt = (Int, Eisen)

-- | The training metric cost of moving from @p0@ to @p1@: L1 on the (1,1,1) luma axis PLUS the
--   Eisenstein (hexagonal A2) norm of the chroma residual. This mirrors V2TrainingLattice.trainLoss
--   exactly (|luma delta| + enorm (chroma delta)), but in (luma,chroma) coordinates.
metricCost :: Pt -> Pt -> Int
metricCost (l0, c0) (l1, c1) = abs (l1 - l0) + enorm (esub c1 c0)

-- | Is a (luma, chroma) point ON the index-3 sublattice Lambda (i.e. does it invert to integer sRGB)?
inLambda :: Pt -> Bool
inLambda (l, c) = case lumaChromaToRgb l c of
  Just _  -> True
  Nothing -> False

-- ===========================================================================
-- (2) The candidate moves and the true closest point
-- ===========================================================================

-- | All candidate destinations: luma-only moves (|dl| <= 2, which also covers snapToLambda's
--   down-by-2) and chroma-only unit shifts (the 6 norm-1 hue steps). This finite set provably
--   CONTAINS the global minimum: the true minimal cost is <= 1, and every cost-<=1 lattice move
--   appears here (luma +-1 with no chroma move, the 6 unit chroma shifts with no luma move, and
--   the identity). The luma +-2 entries are kept only so the snapToLambda move is a candidate too.
candidatesFor :: Pt -> [Pt]
candidatesFor (l, c) =
     [ (l + dl, c)    | dl <- [-2 .. 2] ]
  ++ [ (l, eadd c u)  | u  <- units ]

-- | The TRUE nearest Lambda point under the training metric: the argmin over the candidate set,
--   restricted to candidates that actually land in Lambda. Deterministic tie-break = prefer
--   smaller luma displacement, then smaller chroma displacement (so equal-cost chroma moves are
--   preferred over a same-cost luma move). Always defined: a luma-only candidate is always valid.
closestLambda :: Pt -> Pt
closestLambda tgt = minimumBy (comparing rank) valid
  where
    valid = filter inLambda (candidatesFor tgt)
    rank cand = (metricCost tgt cand, abs (fst cand - fst tgt), normL1 (snd cand))
    normL1 (Eisen a b) = abs a + abs b

-- | snapToLambda as a point-to-point move, for cost comparison (it only shifts luma).
snapPt :: Pt -> Pt
snapPt (l, c) = snapToLambda l c

-- ===========================================================================
-- (3) Sampling
-- ===========================================================================

-- | A spread of training targets, including all three residue classes r in {0,1,2} and both
--   chroma signs (so the chroma-shift branch is genuinely exercised, not just luma).
sampleTargets :: [Pt]
sampleTargets = [ (l, Eisen a b) | l <- [-3 .. 6], a <- [-3 .. 3], b <- [-3 .. 3] ]

-- ===========================================================================
-- (4) Laws
-- ===========================================================================

-- | The result ALWAYS lies in Lambda (inverts to integer sRGB). TEETH: the closest point is a
--   genuine selection, not "everything is already in Lambda" -- there exist sampled targets whose
--   own identity is NOT in Lambda, yet the result is.
lawClosestIsInLambda :: Bool
lawClosestIsInLambda =
     all (inLambda . closestLambda) sampleTargets
  && any (\t -> not (inLambda t)) sampleTargets        -- tooth: off-Lambda targets exist
  && not (inLambda (2, Eisen 0 0))                     -- tooth witness: r = 2 is off Lambda ...
  && inLambda (closestLambda (2, Eisen 0 0))           -- ... but its closest point is on Lambda

-- | A point already in Lambda is returned UNCHANGED (cost-0 identity wins). TEETH: closestLambda
--   is NOT the identity function -- there exist off-Lambda targets whose result differs from input.
lawClosestIdempotent :: Bool
lawClosestIdempotent =
     all (\t -> closestLambda t == t) [ t | t <- sampleTargets, inLambda t ]
  && any (\t -> closestLambda t /= t) sampleTargets    -- tooth: it actually moves some targets

-- | closestLambda is NEVER worse than snapToLambda, and is STRICTLY better on some target.
--   TEETH (the whole point): the strict witness must exist. At target (2, Eisen 0 0) the residual
--   is r = 2, so snapToLambda moves luma DOWN by 2 (cost 2), while the closest point costs 1
--   (a unit chroma shift OR a single luma step up). We also exhibit the parenthetical case
--   literally: a chroma move (cost 1) is cheaper than snapToLambda's luma move (cost 2).
lawClosestNoWorseThanSnapLuma :: Bool
lawClosestNoWorseThanSnapLuma =
     all (\t -> metricCost t (closestLambda t) <= metricCost t (snapPt t)) sampleTargets
  && any (\t -> metricCost t (closestLambda t) <  metricCost t (snapPt t)) sampleTargets   -- strict witness
  && metricCost wt (closestLambda wt) == 1
  && metricCost wt (snapPt wt)        == 2
  && inLambda (wt_luma) && metricCost wt wt_luma  == 1   -- a luma step up: cost 1
  && inLambda (wt_chr)  && metricCost wt wt_chr   == 1   -- a chroma unit shift: cost 1 < 2 (cheaper than snap)
  where
    wt      = (2, Eisen 0 0)          -- r = 2
    wt_luma = (3, Eisen 0 0)          -- luma up 1
    wt_chr  = (2, Eisen 1 1)          -- chroma shift, sum 2 == r, norm 1

-- | closestLambda attains the GLOBAL minimum cost over a brute-forced radius-3 neighbourhood of
--   Lambda points. The claim is EQUALITY, not merely "<=": the achieved cost EQUALS the brute min.
--   (Soundness "<=" is the substantive direction; ">=" holds because closestLambda's result is
--   itself one of the radius-3 Lambda points, so it cannot beat their minimum. Asserting "==" makes
--   attainment explicit instead of resting that ">=" step on the reader.) TEETH: the neighbourhood
--   genuinely contains higher-cost near-miss Lambda points (max cost > the achieved min), so the law
--   is not vacuously comparing a degenerate singleton neighbourhood against itself.
lawClosestIsMinimal :: Bool
lawClosestIsMinimal =
     all (\t -> metricCost t (closestLambda t) == bruteMin t) sampleTargets
  && any (\t -> bruteMax t > metricCost t (closestLambda t)) sampleTargets   -- tooth: near-misses cost more
  where
    nbhd (l, Eisen ca cb) =
      [ p | l' <- [l - 3 .. l + 3]
          , a  <- [ca - 3 .. ca + 3]
          , b  <- [cb - 3 .. cb + 3]
          , let p = (l', Eisen a b)
          , inLambda p ]
    bruteMin t = minimum [ metricCost t p | p <- nbhd t ]
    bruteMax t = maximum [ metricCost t p | p <- nbhd t ]

-- | MATH BACKBONE: an INDEPENDENT ANT cross-check of the three facts the closest-point
--   construction silently rests on (no closestLambda logic appears here, so this cannot be
--   tautological with the laws above).
--   (a) RAMIFICATION  3 = (1+w)(1-w)^2, the prime (1-w) ramified with NORM 3. In Eisen coords
--       1-w = Eisen 1 (-1); (1-w)^2 = Eisen 0 (-3) = -3w; (1+w)(1-w)^2 = Eisen 3 0 = 3. This is
--       WHY the sublattice index is exactly 3 (the residue is read mod 3).
--   (b) IDEAL MEMBERSHIP / index-3 congruence: Lambda IS exactly the image of integer sRGB. For
--       every integer RGB, luma - ca - cb = 3*b, an exact multiple of 3, so it ALWAYS lands in
--       Lambda. TOOTH: the index is genuinely 3, exactly ONE of three consecutive luma values at
--       fixed chroma is in Lambda (the other two refuse), so membership is non-trivial.
--   (c) EUCLIDEAN DIVISION: Z[w] is norm-Euclidean. For every x and nonzero y a quotient q exists
--       with N(x - q y) < N(y) (the remainder strictly shrinks). q is found by rounding x*conj(y)/N(y)
--       to lattice coords and searching its 3x3 neighbourhood (the hexagonal fundamental domain is
--       not a coordinate box, so the neighbour search is required, not decorative).
lawMathBackbone :: Bool
lawMathBackbone =
  -- (a) ramification 3 = (1+w)(1-w)^2, prime (1-w) ramified with norm 3
     enorm wm == 3
  && emul wm wm == Eisen 0 (-3)                                   -- (1-w)^2 = -3w
  && emul uw (emul wm wm) == Eisen 3 0                            -- (1+w)(1-w)^2 = 3
  && enorm uw == 1                                                -- tooth: the cofactor (1+w) really is a unit
  -- (b) ideal-membership congruence: every integer sRGB lands in Lambda, with residue = 3*blue
  && all (\rgb -> luma rgb - reA (chroma rgb) - imA (chroma rgb) == 3 * blue rgb) rgbs
  && all (\rgb -> inLambda (luma rgb, chroma rgb)) rgbs
  && length [ l | l <- [0, 1, 2], inLambda (l, Eisen 0 0) ] == 1 -- tooth: index exactly 3, not 1
  -- (c) Euclidean division: the remainder norm strictly drops for every nonzero divisor
  && and [ euclideanShrinks x y | x <- esample, y <- esample, y /= Eisen 0 0 ]
  where
    wm = Eisen 1 (-1)                    -- 1 - w  (the ramified prime over 3)
    uw = Eisen 1 1                       -- 1 + w  (a unit, the ramification cofactor)
    reA (Eisen a _) = a
    imA (Eisen _ b) = b
    blue (_, _, b)  = b
    rgbs    = [ (r, g, b) | r <- [0 .. 4], g <- [0 .. 4], b <- [0 .. 4] ]
    esample = [ Eisen a b | a <- [-3 .. 3], b <- [-3 .. 3] ]
    conjE (Eisen a b) = Eisen (a - b) (negate b)                 -- complex conjugate in Z[w]
    nearest n d = (2 * n + d) `div` (2 * d)                      -- round n/d to nearest integer (d > 0)
    euclideanShrinks x y =
      let ny = enorm y
          Eisen p q = emul x (conjE y)                           -- x * conj(y); exact quotient = this / ny
          q0a = nearest p ny
          q0b = nearest q ny
      in any (\qq -> enorm (esub x (emul qq y)) < ny)
             [ Eisen (q0a + da) (q0b + db) | da <- [-1 .. 1], db <- [-1 .. 1] ]

-- ===========================================================================
-- (5) Runner
-- ===========================================================================

laws :: [(String, Bool)]
laws =
  [ ("lawClosestIsInLambda          (result inverts to integer sRGB, selection not trivial)", lawClosestIsInLambda)
  , ("lawClosestIdempotent          (on-Lambda fixed, off-Lambda actually moved)",            lawClosestIdempotent)
  , ("lawClosestNoWorseThanSnapLuma (<= snap always, STRICT witness exists)",                 lawClosestNoWorseThanSnapLuma)
  , ("lawClosestIsMinimal           (global min over radius-3 nbhd, near-misses cost more)",  lawClosestIsMinimal)
  , ("lawMathBackbone               (ramification 3=u(1-w)^2, index-3 congruence, Euclidean)", lawMathBackbone)
  ]

main :: IO ()
main = do
  putStrLn "V2A2ClosestPoint.hs  -- EXPLORATION (NOT WIRED): true A2 closest-point onto Lambda"
  putStrLn (replicate 72 '-')
  mapM_ (\(n, ok) -> putStrLn (verdict ok ++ "  " ++ n)) laws
  putStrLn (replicate 72 '-')
  let passed = length (filter snd laws)
      total  = length laws
  putStrLn ("SUMMARY: " ++ show passed ++ "/" ++ show total ++ " laws PASS"
            ++ if passed == total then "  (all green)" else "  (FAILURES present)")
  putStrLn ""
  let wt = (2, Eisen 0 0) :: Pt
  putStrLn ("witness target          = " ++ show wt ++ "   (residual r = 2)")
  putStrLn ("snapToLambda gives      = " ++ show (snapPt wt)
            ++ "   cost " ++ show (metricCost wt (snapPt wt)) ++ " (luma down 2)")
  putStrLn ("closestLambda gives     = " ++ show (closestLambda wt)
            ++ "   cost " ++ show (metricCost wt (closestLambda wt)) ++ " (chroma unit shift)")
  putStrLn ""
  putStrLn "HONEST BOUNDARY: the candidate set is PROVABLY exhaustive for the GLOBAL minimum,"
  putStrLn "not merely local: a single luma +-1 step always re-enters Lambda when r /= 0, so the"
  putStrLn "true min cost is <= 1, and every cost-<=1 move is enumerated (luma +-1, the 6 unit"
  putStrLn "chroma shifts, identity). Under this metric a luma step and a minimal chroma shift"
  putStrLn "BOTH cost 1, so chroma never STRICTLY beats the best luma step (they tie); chroma is"
  putStrLn "strictly cheaper only than snapToLambda's suboptimal down-by-2 move. The brute-force"
  putStrLn "radius-3 check independently confirms global optimality on every sampled target."
  where
    verdict True  = "PASS"
    verdict False = "FAIL"
