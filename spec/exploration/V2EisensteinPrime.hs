{- |
Module      : V2EisensteinPrime
Description : EXPLORATION (NOT WIRED, base-only, runghc). Z[w] is a Euclidean domain; the
              rational prime 3 RAMIFIES as 3 = u * (1-w)^2 for a unit u; and the index-3
              sublattice that the byte-exact /3 guard lives on IS the ideal (1-w).

  Check:  cd spec/exploration && runghc V2EisensteinPrime.hs

  THE DEEP ANT (real, not forced): the V2 byte-exactness condition "l == ca + cb (mod 3)"
  is NOT an arbitrary modular hack. It is the shadow of how the rational prime 3 behaves
  in the Eisenstein integers Z[w] (w^2 = -1 - w, the ring of the hexagonal A2 chroma
  lattice). In Z[w] every odd rational prime is one of three things:
      * p == 1 (mod 3)  SPLITS    : p = pi * pi-bar, two NON-ASSOCIATE primes (e.g. 7)
      * p == 2 (mod 3)  is INERT  : (p) stays prime, N((p)) = p^2            (e.g. 2)
      * p == 0 (mod 3)  RAMIFIES  : 3 = unit * (1-w)^2, ONE prime, squared
  The ramified prime is (1-w), with N(1-w) = 3. The quotient Z[w]/(1-w) is the field F_3,
  and the reduction map a + b w |-> a + b (mod 3) IS the /3 guard. So "index-3 sublattice"
  and "the ideal (1-w)" are the SAME object, and "byte-exact mod 3" is "agreeing in F_3".

  This file PROVES (toothed, with boundary witnesses) the chain:
      Euclidean division  ==>  3 ramifies as unit*(1-w)^2  ==>  the ideal (1-w) is exactly
      the congruence a + b == 0 (mod 3)  ==>  the luma guard l == ca+cb (mod 3) is the F_3
      reduction of the chroma.
  Base-only, runghc-checkable, NOT in any cabal file / Map / gate. Mirrors the Eisenstein
  arithmetic of V2RgbEisenstein.hs and V2TrainingLattice.hs.

  HONEST BOUNDARY (anti-vacuous-law): the ramification facts about the GENERATOR (1-w) and
  the SPECIFIC factorizations of 7 and 2 are CLOSED computations (exact, not sampled). The
  IDEAL-membership claims (division-remainder == congruence) are SAMPLE-VERIFIED over a
  finite box of Z[w], not a proved closed theorem; they are marked as such below.
-}
module V2EisensteinPrime where

-- ===========================================================================
-- (1) Eisenstein integers Z[w], w^2 = -1 - w  (matches V2TrainingLattice)
-- ===========================================================================

data Eisen = Eisen Int Int deriving (Eq, Show)

eadd, esub, emul :: Eisen -> Eisen -> Eisen
eadd (Eisen a b) (Eisen c d) = Eisen (a + c) (b + d)
esub (Eisen a b) (Eisen c d) = Eisen (a - c) (b - d)
emul (Eisen a b) (Eisen c d) = Eisen (a * c - b * d) (a * d + b * c - b * d)

-- | The algebraic norm N(a + b w) = a^2 - ab + b^2 = (a + b w)(a + b w-bar).
enorm :: Eisen -> Int
enorm (Eisen a b) = a * a - a * b + b * b

-- | Complex conjugate: conj(a + b w) = a + b w-bar = (a - b) - b w, since w-bar = -1 - w.
--   Satisfies  z * conj z = Eisen (N z) 0  (used to build the rational quotient for ediv).
econj :: Eisen -> Eisen
econj (Eisen a b) = Eisen (a - b) (negate b)

-- | The 6 units = norm-1 elements = the six 60-degree hue rotations (1, w, w^2 and negatives).
units :: [Eisen]
units = [Eisen 1 0, Eisen 0 1, Eisen (-1) (-1), Eisen (-1) 0, Eisen 0 (-1), Eisen 1 1]

-- | The ramified prime above 3:  1 - w  =  Eisen 1 (-1),  with N(1-w) = 3.
oneMinusW :: Eisen
oneMinusW = Eisen 1 (-1)

-- ===========================================================================
-- (2) Euclidean division in Z[w]
-- ===========================================================================

-- | Nearest integer to p/n for n > 0 (round half up). Guarantees |p/n - result| <= 1/2.
roundDivE :: Int -> Int -> Int
roundDivE p n =
  let q = p `div` n          -- floor (Haskell div floors toward -inf)
      r = p - q * n          -- 0 <= r < n
  in if 2 * r >= n then q + 1 else q

-- | Euclidean division: ediv x y = (q, r) with x = q*y + r and N(r) < N(y), for y /= 0.
--   Method: the rational quotient x/y = x * conj(y) / N(y); round each coordinate to the
--   nearest integer to land on the lattice point q; r = x - q*y. Coordinate rounding keeps
--   each component within 1/2, so N(r) = N(x/y - q) * N(y) <= (3/4) N(y) < N(y).
ediv :: Eisen -> Eisen -> (Eisen, Eisen)
ediv x y =
  let n          = enorm y
      Eisen p qn = emul x (econj y)         -- numerator of x/y (before dividing by n)
      qq         = Eisen (roundDivE p n) (roundDivE qn n)
      r          = esub x (emul qq y)
  in (qq, r)

-- | (1-w) | z  decided by the Euclidean remainder (the ground-truth ideal-membership test).
divisibleByOneMinusW :: Eisen -> Bool
divisibleByOneMinusW z = snd (ediv z oneMinusW) == Eisen 0 0

-- | Reduction Z[w] -> F_3 = Z[w]/(1-w).  Since 1 - w == 0 mod (1-w), we have w == 1, so
--   a + b w |-> a + b (mod 3).  This map IS the /3 byte-exact guard.
phiF3 :: Eisen -> Int
phiF3 (Eisen a b) = (a + b) `mod` 3

-- ===========================================================================
-- (3) The V2 sRGB chroma + the byte-exact luma guard (matches V2TrainingLattice)
-- ===========================================================================

type RGB = (Int, Int, Int)

luma :: RGB -> Int
luma (r, g, b) = r + g + b

-- | Chroma via R->1, G->w, B->w^2; gray collapses to the kernel Eisen 0 0.
chroma :: RGB -> Eisen
chroma (r, g, b) = Eisen (r - b) (g - b)

-- | The byte-exact /3 guard:  l == ca + cb (mod 3).
byteExact :: Int -> Eisen -> Bool
byteExact l (Eisen ca cb) = (l - ca - cb) `mod` 3 == 0

-- ===========================================================================
-- (4) Laws
-- ===========================================================================

-- | Z[w] is a EUCLIDEAN DOMAIN: ediv x y = (q,r) reconstructs x = q*y + r exactly AND
--   strictly shrinks the norm, N(r) < N(y), for every y /= 0. (Sample over a finite box.)
lawEuclideanDivision :: Bool
lawEuclideanDivision =
     and [ reconstructs x y && shrinks y (snd (ediv x y)) && tightBound y (snd (ediv x y))
         | x <- box, y <- box, y /= Eisen 0 0 ]
  where
    box = [Eisen a b | a <- [-4 .. 4], b <- [-4 .. 4]]
    reconstructs x y = let (q, r) = ediv x y in eadd (emul q y) r == x
    shrinks y r      = enorm r < enorm y
    -- CLOSEST-POINT TOOTH: nearest-lattice-point rounding forces N(r) <= (3/4)N(y),
    -- i.e. 4*N(r) <= 3*N(y) (integer form, no rationals). A non-nearest rounder (e.g.
    -- floor) could still satisfy the weak N(r) < N(y) yet VIOLATE this tight bound, so
    -- this conjunct is what actually pins ediv to the closest lattice point.
    tightBound y r   = 4 * enorm r <= 3 * enorm y

-- | N(1 - w) = 3: the generator of the prime above 3. (1-w = Eisen 1 (-1), norm 1+1+1.)
lawNormOfOneMinusW :: Bool
lawNormOfOneMinusW =
     enorm oneMinusW == 3
  && oneMinusW == Eisen 1 (-1)
  && enorm (Eisen 1 0) == 1          -- tooth: a unit has norm 1, not 3 (1-w is NOT a unit)

-- | 3 RAMIFIES:  3 = u * (1-w)^2  for the unit u = -w^2 = Eisen 1 1.
--   (1-w)^2 = -3w = Eisen 0 (-3); u * (-3w) = 3 w^3 = 3 = Eisen 3 0. TEETH: any OTHER unit
--   (and the squared generator alone) fails to equal Eisen 3 0.
lawThreeRamifies :: Bool
lawThreeRamifies =
     emul oneMinusW oneMinusW == Eisen 0 (-3)               -- (1-w)^2 = -3w
  && u `elem` units                                          -- the corrector is a genuine unit
  && emul u (emul oneMinusW oneMinusW) == Eisen 3 0          -- u * (1-w)^2 = 3
  && emul oneMinusW oneMinusW /= Eisen 3 0                   -- tooth: bare (1-w)^2 is not 3
  && and [ emul w2 (emul oneMinusW oneMinusW) /= Eisen 3 0   -- tooth: every WRONG unit fails
         | w2 <- units, w2 /= u ]
  where
    u = Eisen 1 1   -- = -w^2

-- | The index-3 sublattice IS the ideal (1-w):  Euclidean-divisibility by (1-w) equals the
--   simple congruence a + b == 0 (mod 3), DERIVED (w == 1 mod (1-w) so a+b w |-> a+b).
--   SAMPLE-VERIFIED over a finite box (not a closed theorem). TEETH: a representative NOT in
--   the ideal has a nonzero remainder; a representative IN it has remainder zero.
lawIndexThreeSublatticeIsIdealOneMinusW :: Bool
lawIndexThreeSublatticeIsIdealOneMinusW =
     and [ divisibleByOneMinusW z == (phiF3 z == 0) | z <- box ]   -- division == congruence
  && divisibleByOneMinusW (Eisen 3 0)                              -- tooth: 3 in (since 3=(1-w)^2 up to unit)
  && divisibleByOneMinusW (Eisen 1 (-1))                           -- tooth: the generator is in its own ideal
  && not (divisibleByOneMinusW (Eisen 1 0))                        -- tooth: 1 NOT in (a+b=1 /= 0 mod 3)
  && snd (ediv (Eisen 1 0) oneMinusW) /= Eisen 0 0                 -- tooth: nonzero remainder for a non-member
  && enorm (snd (ediv (Eisen 1 0) oneMinusW)) == 1                 -- tooth: that remainder is a UNIT (N=1):
                                                                   --   N(r) < N(1-w)=3 and no norm-2 element exists,
                                                                   --   so the only non-zero residues are units (F_3*)
  where
    box = [Eisen a b | a <- [-5 .. 5], b <- [-5 .. 5]]

-- | CONNECTION: the byte-exact luma guard l == ca+cb (mod 3) IS the F_3 reduction of the
--   chroma through the ramified prime (1-w):  byteExact l c  <=>  l mod 3 == phiF3 c.
--   And GENUINE RGB ALWAYS satisfies it (l - ca - cb = 3b), so the guard only bites when
--   luma and chroma are set as INDEPENDENT lattice points (a snapped training target).
--   TEETH: an independent (l, chroma) off the sublattice fails; real RGB never does.
lawByteExactCongruenceIsF3Reduction :: Bool
lawByteExactCongruenceIsF3Reduction =
     and [ byteExact l c == (l `mod` 3 == phiF3 c)                 -- guard == F_3 agreement
         | l <- [-6 .. 6], c <- box ]
  && and [ byteExact (luma rgb) (chroma rgb)                       -- real RGB ALWAYS passes
         | r <- [0 .. 4], g <- [0 .. 4], b <- [0 .. 4], let rgb = (r, g, b) ]
  && not (byteExact 1 (Eisen 0 0))                                 -- tooth: l=1, gray chroma -> 1 /= 0 mod 3
  && byteExact 0 (Eisen 0 0)                                       -- tooth: l=0, gray chroma -> passes
  where
    box = [Eisen a b | a <- [-4 .. 4], b <- [-4 .. 4]]

-- | The TRICHOTOMY of rational primes in Z[w], on the canonical small witnesses:
--     7 == 1 (mod 3)  SPLITS  : 7 = (3+w)(2-w), two NON-ASSOCIATE primes, each of norm 7.
--     2 == 2 (mod 3)  INERT   : no element has norm 2, so (2) is prime with N((2)) = 4 = 2^2.
--     3 == 0 (mod 3)  RAMIFIES: handled by lawThreeRamifies above.
--   Split/inert verified by NORMS (honest: we exhibit the factor pair and the norm gap, we
--   do not run a general primality routine).
lawSplitInertTrichotomy :: Bool
lawSplitInertTrichotomy =
     -- SPLIT: 7 = (3+w)(2-w)
     enorm pi7 == 7 && enorm pi7' == 7
  && emul pi7 pi7' == Eisen 7 0
  && all (\u -> emul u pi7' /= pi7) units                          -- non-associate: no unit maps one to the other
  -- INERT: 2 has no Eisenstein factor of norm 2; (2) has norm 4 = 2^2
  && not (any (\z -> enorm z == 2) box)
  && enorm (Eisen 2 0) == 4
  where
    pi7  = Eisen 3 1
    pi7' = Eisen 2 (-1)
    box  = [Eisen a b | a <- [-5 .. 5], b <- [-5 .. 5]]

-- ===========================================================================
-- (5) Runner
-- ===========================================================================

laws :: [(String, Bool)]
laws =
  [ ("lawEuclideanDivision        (x=qy+r, N(r)<N(y) : Z[w] Euclidean)",      lawEuclideanDivision)
  , ("lawNormOfOneMinusW          (N(1-w) = 3 : the prime above 3)",          lawNormOfOneMinusW)
  , ("lawThreeRamifies            (3 = u*(1-w)^2, u a unit)",                  lawThreeRamifies)
  , ("lawIndexThreeIsIdeal1mW     ((1-w)|z  <=>  a+b==0 mod 3)",               lawIndexThreeSublatticeIsIdealOneMinusW)
  , ("lawByteExactIsF3Reduction   (luma guard = F_3 reduction of chroma)",     lawByteExactCongruenceIsF3Reduction)
  , ("lawSplitInertTrichotomy     (7 splits, 2 inert : 3 ramifies)",          lawSplitInertTrichotomy)
  ]

main :: IO ()
main = do
  putStrLn "V2EisensteinPrime.hs  -- EXPLORATION (NOT WIRED): 3 ramifies in Z[w]; (1-w) IS the index-3 sublattice"
  putStrLn (replicate 72 '-')
  mapM_ (\(n, ok) -> putStrLn (verdict ok ++ "  " ++ n)) laws
  putStrLn (replicate 72 '-')
  let passed = length (filter snd laws)
      total  = length laws
  putStrLn ("SUMMARY: " ++ show passed ++ "/" ++ show total ++ " laws PASS"
            ++ if passed == total then "  (all green)" else "  (FAILURES present)")
  putStrLn ""
  putStrLn ("(1-w)         = " ++ show oneMinusW ++ "   N(1-w) = " ++ show (enorm oneMinusW))
  putStrLn ("(1-w)^2       = " ++ show (emul oneMinusW oneMinusW) ++ "   (= -3w)")
  putStrLn ("(-w^2)*(1-w)^2 = " ++ show (emul (Eisen 1 1) (emul oneMinusW oneMinusW))
            ++ "   (= 3 : 3 ramifies)")
  putStrLn ("ediv (Eisen 5 2) (1-w) = " ++ show (ediv (Eisen 5 2) oneMinusW)
            ++ "   (q*y + r reconstructs: "
            ++ show (let (q, r) = ediv (Eisen 5 2) oneMinusW in eadd (emul q oneMinusW) r == Eisen 5 2) ++ ")")
  putStrLn ("7 = (3+w)(2-w) = " ++ show (emul (Eisen 3 1) (Eisen 2 (-1))) ++ "   (split)")
  putStrLn ""
  putStrLn "HONEST NOTE: the ramification of 3 (3 = -w^2 * (1-w)^2, N(1-w)=3) and the"
  putStrLn "factorizations 7 = (3+w)(2-w) (split) / 2 inert are CLOSED computations. The claim"
  putStrLn "'(1-w)|z  <=>  a+b == 0 mod 3' is SAMPLE-VERIFIED over a finite box, not a proved"
  putStrLn "closed theorem. The /3 byte-exact guard is the F_3 = Z[w]/(1-w) reduction of chroma:"
  putStrLn "discrete geometry's prime-splitting IS the byte-exactness condition, not a coincidence."
  where
    verdict True  = "PASS"
    verdict False = "FAIL"
