{- |
Module      : V2TrainingLattice
Description : EXPLORATION (NOT WIRED, base-only, runghc). Discrete geometry + algebraic
              number theory IN THE TRAINING of the V2 model. The training loss, target
              quantization, and inductive bias are grounded in the Eisenstein integers
              Z[w] (the hexagonal A2 lattice), NOT in Euclidean RGB or Lab.

  Check:  runghc V2TrainingLattice.hs

  THE POINT (owner directive 2026-06-29): "Discrete geometry + algebraic number theory in
  the training of the model." V2 is raw sRGB 8-bit (Lab DROPPED). The colour structure that
  drives training is the A2 lattice:
    * LOSS = L1 on the (1,1,1) luma axis + the Eisenstein NORM a^2-ab+b^2 of the chroma
      residual (the genuine hexagonal distance, sheared away from Euclidean).
    * TARGET is snapped to the index-3 sublattice L = {l == ca+cb (mod 3)} so the
      data-manufactured target is BYTE-EXACT invertible (the /3 guard; collapse-safe).
    * INDUCTIVE BIAS: the 6 units of Z[w] are 60-degree hue rotations that act as
      ISOMETRIES of the loss (a global hue spin cannot lower the loss).

  Mirrors the Eisenstein arithmetic of spec/exploration/V2RgbEisenstein.hs and the index-3
  sublattice from V2-SKI-PONDER-DIGEST.md. Base-only, runghc-checkable, NOT wired.
-}
module V2TrainingLattice where

-- ===========================================================================
-- (1) Eisenstein integers Z[w], w^2 = -1 - w  (the A2 chroma lattice)
-- ===========================================================================

data Eisen = Eisen Int Int deriving (Eq, Show)

eadd, esub, emul :: Eisen -> Eisen -> Eisen
eadd (Eisen a b) (Eisen c d) = Eisen (a + c) (b + d)
esub (Eisen a b) (Eisen c d) = Eisen (a - c) (b - d)
emul (Eisen a b) (Eisen c d) = Eisen (a * c - b * d) (a * d + b * c - b * d)

-- | The algebraic norm = the squared hexagonal (A2) chroma length.
enorm :: Eisen -> Int
enorm (Eisen a b) = a * a - a * b + b * b

-- | The 6 units = norm-1 elements = the six 60-degree hue rotations.
units :: [Eisen]
units = [Eisen 1 0, Eisen 0 1, Eisen (-1) (-1), Eisen (-1) 0, Eisen 0 (-1), Eisen 1 1]

-- ===========================================================================
-- (2) sRGB 8-bit <-> (luma, Eisenstein chroma), and the index-3 sublattice L
-- ===========================================================================

type RGB = (Int, Int, Int)

-- | Luma on the (1,1,1) balance axis.
luma :: RGB -> Int
luma (r, g, b) = r + g + b

-- | Chroma via R->1, G->w, B->w^2; gray collapses to the kernel Eisen 0 0.
chroma :: RGB -> Eisen
chroma (r, g, b) = Eisen (r - b) (g - b)

-- | Invert (luma, chroma) back to RGB. Integer ONLY on the index-3 sublattice
--   L = {l == ca + cb (mod 3)}. An invert-OR-REFUSE total function (the /3 byte-exactness guard).
lumaChromaToRgb :: Int -> Eisen -> Maybe RGB
lumaChromaToRgb l (Eisen ca cb)
  | (l - ca - cb) `mod` 3 == 0 = let bb = (l - ca - cb) `div` 3 in Just (bb + ca, bb + cb, bb)
  | otherwise                  = Nothing

-- | Snap LUMA into the congruence class so the inverse is byte-exact. Snaps luma (minimal
--   displacement <= 2), NOT a true nearest-lattice point (honest naming, per the digest).
snapToLambda :: Int -> Eisen -> (Int, Eisen)
snapToLambda l c@(Eisen ca cb) = (l - ((l - ca - cb) `mod` 3), c)

-- ===========================================================================
-- (3) The training loss in discrete geometry
-- ===========================================================================

-- | TRAINING LOSS = L1 on luma + the Eisenstein (hexagonal A2) norm of the chroma residual.
--   NOT Euclidean RGB, NOT Lab.
trainLoss :: RGB -> RGB -> Int
trainLoss p t = abs (luma p - luma t) + enorm (esub (chroma p) (chroma t))

-- ===========================================================================
-- (4) Laws
-- ===========================================================================

-- | N(xy) = N(x)N(y): the multiplicative norm, the ANT backbone of the metric.
lawNormMultiplicative :: Bool
lawNormMultiplicative =
  and [ enorm (emul x y) == enorm x * enorm y | x <- sample, y <- sample ]
  where sample = [Eisen a b | a <- [-3 .. 3], b <- [-3 .. 3]]

-- | N >= 0 and N = 0 IFF gray (the chroma kernel). The loss is a genuine non-negative metric
--   that vanishes exactly on the luma axis.
lawNormPositiveDefinite :: Bool
lawNormPositiveDefinite =
     all (\x -> enorm x >= 0) sample
  && all (\x -> (enorm x == 0) == (x == Eisen 0 0)) sample
  && chroma (7, 7, 7) == Eisen 0 0          -- gray -> kernel
  && enorm (chroma (7, 7, 8)) > 0           -- one step off gray has positive chroma (tooth)
  where sample = [Eisen a b | a <- [-4 .. 4], b <- [-4 .. 4]]

-- | The 6 units have norm 1 and act as 60-degree HUE ROTATIONS preserving chroma length
--   (isometries of the A2 metric). A non-unit scales the length (tooth).
lawUnitsAreSixHueRotations :: Bool
lawUnitsAreSixHueRotations =
     length units == 6
  && all (\u -> enorm u == 1) units
  && and [ enorm (emul u x) == enorm x | u <- units, x <- sample ]
  && enorm (emul (Eisen 2 0) (Eisen 1 1)) /= enorm (Eisen 1 1)    -- tooth: non-unit (norm 4) scales
  where sample = [Eisen a b | a <- [-3 .. 3], b <- [-3 .. 3]]

-- | Any training target snapped to L inverts to INTEGER sRGB (byte-exact, collapse-safe),
--   preserving its chroma and snapped luma. A non-L target REFUSES (the /3 guard, tooth).
lawSnapToLambdaByteExact :: Bool
lawSnapToLambdaByteExact =
     all ok [ (l, Eisen a b) | l <- [-5 .. 10], a <- [-4 .. 4], b <- [-4 .. 4] ]
  && lumaChromaToRgb 1 (Eisen 0 0) == Nothing                      -- tooth: 1 /= 0 (mod 3), refuses
  where
    ok (l, c) =
      let (l', _) = snapToLambda l c
      in case lumaChromaToRgb l' c of
           Just rgb -> chroma rgb == c && luma rgb == l'            -- integer RGB, chroma + luma exact
           Nothing  -> False

-- | The loss IS lumaL1 + the hexagonal A2 norm, and that metric is genuinely SHEARED (not
--   Euclidean): chroma deltas (2,1) and (2,-1) have EQUAL Euclidean length but DIFFERENT A2 norm.
--   So the discrete geometry does real work in the loss.
lawTrainingLossIsLatticeNorm :: Bool
lawTrainingLossIsLatticeNorm =
     trainLoss c c == 0                                                       -- zero on equality
  && all (\(p, t) -> trainLoss p t >= 0) pairs                               -- non-negative
  && trainLoss (3, 1, 0) (0, 0, 0) == abs (luma (3, 1, 0)) + enorm (chroma (3, 1, 0))
  && enorm (Eisen 2 1) == 3 && enorm (Eisen 2 (-1)) == 7                     -- hexagonal: sheared
  && ((2 * 2 + 1 * 1) :: Int) == (2 * 2 + (-1) * (-1))                       -- Euclidean: equal (tooth)
  where
    c     = (4, 2, 1)
    pairs = [((r, g, b), (0, 0, 0)) | r <- [0 .. 3], g <- [0 .. 3], b <- [0 .. 3]]

-- | Simultaneously HUE-ROTATING prediction and target (multiply both chroma by a unit) leaves
--   the chroma loss INVARIANT: the units are isometries, a real inductive bias for training
--   (no global hue spin can lower the loss). Tooth: a non-unit scales the loss.
lawHueRotationInvariantLoss :: Bool
lawHueRotationInvariantLoss =
     and [ enorm (esub (emul u cp) (emul u ct)) == enorm (esub cp ct)
         | u <- units, cp <- sample, ct <- sample ]
  && enorm (esub (emul (Eisen 2 0) cp0) (emul (Eisen 2 0) ct0)) /= enorm (esub cp0 ct0)
  where
    sample = [Eisen a b | a <- [-2 .. 2], b <- [-2 .. 2]]
    cp0    = Eisen 1 0
    ct0    = Eisen 0 1

-- ===========================================================================
-- (5) Runner
-- ===========================================================================

laws :: [(String, Bool)]
laws =
  [ ("lawNormMultiplicative       (N(xy) = N(x)N(y) : ANT backbone)",          lawNormMultiplicative)
  , ("lawNormPositiveDefinite     (N>=0, =0 iff gray : loss vanishes on luma)", lawNormPositiveDefinite)
  , ("lawUnitsAreSixHueRotations  (6 units = 60deg isometries)",               lawUnitsAreSixHueRotations)
  , ("lawSnapToLambdaByteExact    (L target inverts to integer sRGB)",         lawSnapToLambdaByteExact)
  , ("lawTrainingLossIsLatticeNorm(lumaL1 + hexnorm, sheared /= Euclidean)",   lawTrainingLossIsLatticeNorm)
  , ("lawHueRotationInvariantLoss (units are loss isometries : bias)",         lawHueRotationInvariantLoss)
  ]

main :: IO ()
main = do
  putStrLn "V2TrainingLattice.hs  -- EXPLORATION (NOT WIRED): discrete geometry + ANT in training"
  putStrLn (replicate 72 '-')
  mapM_ (\(n, ok) -> putStrLn (verdict ok ++ "  " ++ n)) laws
  putStrLn (replicate 72 '-')
  let passed = length (filter snd laws)
      total  = length laws
  putStrLn ("SUMMARY: " ++ show passed ++ "/" ++ show total ++ " laws PASS"
            ++ if passed == total then "  (all green)" else "  (FAILURES present)")
  putStrLn ""
  putStrLn ("hex norm  (2, 1) = " ++ show (enorm (Eisen 2 1))
            ++ "   hex norm (2,-1) = " ++ show (enorm (Eisen 2 (-1)))
            ++ "   (Euclidean of both = 5: the A2 metric is sheared)")
  putStrLn ("snapToLambda 7 (Eisen 1 1) = " ++ show (snapToLambda 7 (Eisen 1 1))
            ++ "   inverts to " ++ show (uncurry lumaChromaToRgb (snapToLambda 7 (Eisen 1 1))))
  putStrLn ""
  putStrLn "HONEST NOTE: training in discrete geometry = the loss is the A2 hexagonal norm"
  putStrLn "(sheared away from Euclidean, proven), the target snaps to the index-3 sublattice L"
  putStrLn "so it stays byte-exact (the /3 guard), and the 6 units are hue-rotation isometries"
  putStrLn "of the loss. snapToLambda snaps LUMA (minimal displacement), not a true nearest"
  putStrLn "lattice point; a real closest-point routine is the next refinement."
  where
    verdict True  = "PASS"
    verdict False = "FAIL"
