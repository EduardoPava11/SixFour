{- |
Module      : V2DualityTest
Description : EXPLORATION - NOT WIRED, NOT THE PRODUCTION SPEC. Makes the THREAD A verdict
              CHECKABLE: does the V1 phi6 Balance/Search duality survive the V2 move from
              OKLab/Gaussian colour to RGB/Eisenstein colour?

  VERDICT (checked by the laws below): SURVIVES-WEAKENED.
    * SURVIVES (colour-AGNOSTIC, integer Haar): the Balance/Search split and its exact
      reversible round-trip port to RGB UNCHANGED (lawBalanceSearchSplitPortsToRGB).
    * BREAKS (colour-SPECIFIC, the ring iso): phi6 cannot be a LATTICE isomorphism between
      the space search plane (Z[i], square, 4 units, the pixel raster) and the colour
      search plane (Z[w], hexagonal, 6 units, RGB's 120-degree primaries). The unit groups
      have different orders (4 vs 6) so there is no ring iso, and the natural rotations
      have different orders (mult-by-i has order 4; the 60-degree Eisenstein unit has
      order 6) so no equivariant bijection of the planes exists. phi6 stays a LABEL-only
      Z-module permutation, not a lattice iso (lawPhi6IsLabelOnlyNotLatticeIso).

  BASE-ONLY. NOT in any cabal/Map/gate. Check with:  runghc V2DualityTest.hs
-}
module V2DualityTest where

-- ===========================================================================
-- (1) The two rings: Z[i] (Gaussian, space) and Z[w] (Eisenstein, RGB colour)
-- ===========================================================================

-- | A Gaussian integer @a + b*i@, i^2 = -1.  The SQUARE pixel-raster lattice.
data Gauss = Gauss Int Int deriving (Eq, Show)

gmul :: Gauss -> Gauss -> Gauss
gmul (Gauss a b) (Gauss c d) = Gauss (a*c - b*d) (a*d + b*c)

gone :: Gauss
gone = Gauss 1 0

-- | Gaussian norm @a^2 + b^2@ (multiplicative).
gnorm :: Gauss -> Int
gnorm (Gauss a b) = a*a + b*b

-- | The four Gaussian units {+-1, +-i} (norm 1), 90 degrees apart.
gaussUnits :: [Gauss]
gaussUnits = [Gauss 1 0, Gauss 0 1, Gauss (-1) 0, Gauss 0 (-1)]

-- | An Eisenstein integer @a + b*w@, w^2 = -1 - w (so 1 + w + w^2 = 0). HEXAGONAL lattice.
data Eisen = Eisen Int Int deriving (Eq, Show)

emul :: Eisen -> Eisen -> Eisen
emul (Eisen a b) (Eisen c d) = Eisen (a*c - b*d) (a*d + b*c - b*d)

eone :: Eisen
eone = Eisen 1 0

-- | Eisenstein norm @a^2 - a*b + b^2@ (multiplicative).
enorm :: Eisen -> Int
enorm (Eisen a b) = a*a - a*b + b*b

-- | The six Eisenstein units {+-1, +-w, +-w^2} (norm 1), 60 degrees apart.
eisenUnits :: [Eisen]
eisenUnits = [Eisen 1 0, Eisen 0 1, Eisen (-1) (-1), Eisen (-1) 0, Eisen 0 (-1), Eisen 1 1]

-- | The 60-degree generator @-w^2 = 1 + w@ of the Eisenstein unit group (order 6).
u60 :: Eisen
u60 = Eisen 1 1

-- | The 90-degree generator @i@ of the Gaussian unit group (order 4).
u90 :: Gauss
u90 = Gauss 0 1

-- ===========================================================================
-- (2) The wedge: no ring iso, because the unit groups differ in size
-- ===========================================================================

-- | Multiplicative order of a unit: how many times you multiply by it to return to 1.
gOrder :: Gauss -> Int
gOrder u = go 1 (gmul u gone)
  where go n x | x == gone = n
               | n > 64    = -1            -- guard (never hit for true units)
               | otherwise = go (n+1) (gmul x u)

eOrder :: Eisen -> Int
eOrder u = go 1 (emul u eone)
  where go n x | x == eone = n
               | n > 64    = -1
               | otherwise = go (n+1) (emul x u)

lawGaussUnitsFour :: Bool
lawGaussUnitsFour =
  length gaussUnits == 4 && all (\u -> gnorm u == 1) gaussUnits

lawEisenUnitsSix :: Bool
lawEisenUnitsSix =
  length eisenUnits == 6 && all (\u -> enorm u == 1) eisenUnits

-- | No RING isomorphism Z[i] ~ Z[w]: a ring iso restricts to a unit-group iso, but
--   |units(Z[i])| = 4 /= 6 = |units(Z[w])|. (Independently: discriminants -4 /= -3.)
lawNoRingIsoGaussEisen :: Bool
lawNoRingIsoGaussEisen = length gaussUnits /= length eisenUnits

-- ===========================================================================
-- (3) What SURVIVES: the colour-AGNOSTIC integer Haar split (ported verbatim)
-- ===========================================================================

-- | The 1-D reversible S-transform (the Balance/Search atom). @div@ floors toward -inf,
--   which is exactly what makes it a bijection on Int. Ported verbatim from RGBTLift.hs.
sLift :: Int -> Int -> (Int, Int)
sLift x y = let d = x - y in (y + (d `div` 2), d)

-- | Exact inverse.
sUnlift :: Int -> Int -> (Int, Int)
sUnlift lo hi = let y = lo - (hi `div` 2) in (y + hi, y)

-- | BALANCE = the coarse/DC sub-band (left adjoint); SEARCH = the detail (right adjoint).
balance :: Int -> Int -> Int
balance x y = fst (sLift x y)

search :: Int -> Int -> Int
search x y = snd (sLift x y)

-- | The split ports to RGB UNCHANGED: lifting then unlifting each of R,G,B round-trips
--   exactly. This is the colour-agnostic core that survives V1->V2 (operates on Ints, so
--   it never sees whether the scalars came from OKLab or raw RGB).
lawBalanceSearchSplitPortsToRGB :: Bool
lawBalanceSearchSplitPortsToRGB =
  and [ sUnlift (balance r g) (search r g) == (r, g)
      | r <- [0,1,17,128,200,255,-3,-50], g <- [0,5,128,255,-7,200] ]

-- ===========================================================================
-- (4) What BREAKS: phi6 is a LABEL-only Z-module map, not a LATTICE iso
-- ===========================================================================
--
-- V1 lived as  Z (+) Z[i]  on BOTH cubes, so phi6 swapping
--   (L,a,b,t,x,y) <-> (t,x,y,L,a,b)  exchanged two IDENTICAL Gaussian planes.
-- In V2 the colour search plane is Z[w] and the space search plane is Z[i]; phi6 still
-- TYPE-CHECKS as a permutation of a free Z^6, but it can no longer be a lattice iso of
-- the search planes, because mult-by-i (order 4) and the 60-degree Eisenstein unit
-- (order 6) cannot be matched by any equivariant bijection.

-- | The V1-style phi6 LABEL involution on a 6-tuple (it still type-checks; it is a
--   Z-module automorphism of Z^6 = an involutive coordinate swap).
phi6 :: (Int,Int,Int,Int,Int,Int) -> (Int,Int,Int,Int,Int,Int)
phi6 (l,a,b,t,x,y) = (t,x,y,l,a,b)

-- | phi6 is genuinely involutive at the LABEL level (it survives THIS much).
lawPhi6IsInvolution :: Bool
lawPhi6IsInvolution =
  and [ phi6 (phi6 v) == v | v <- samples ]
  where samples = [ (l,a,b,t,x,y) | l<-[0,7], a<-[1,-2], b<-[3], t<-[5], x<-[2,9], y<-[-1] ]

-- | phi6 is a Z-module automorphism at the LABEL level: it commutes with addition.
lawPhi6IsModuleAutomorphism :: Bool
lawPhi6IsModuleAutomorphism =
  and [ phi6 (add6 p q) == add6 (phi6 p) (phi6 q) | p <- samples, q <- samples ]
  where add6 (a,b,c,d,e,f) (g,h,i,j,k,l) = (a+g,b+h,c+i,d+j,e+k,f+l)
        samples = [ (1,2,3,4,5,6), (-1,0,2,7,-3,4), (10,-5,1,0,8,-2) ]

-- | THE BREAK: phi6 wants to identify the space search plane (Z[i]) with the colour
--   search plane (Z[w]) and carry one's natural rotation to the other. It CANNOT: the
--   square 90-degree generator i has multiplicative order 4, while the hexagonal
--   60-degree generator -w^2 has order 6. An equivariant bijection would force these
--   orders equal. So phi6 is LABEL-only, NOT a lattice iso of the search planes.
lawPhi6IsLabelOnlyNotLatticeIso :: Bool
lawPhi6IsLabelOnlyNotLatticeIso =
  gOrder u90 == 4 && eOrder u60 == 6 && gOrder u90 /= eOrder u60

-- | Sanity: the two norms genuinely differ on a shared coordinate pair, so "preserves the
--   norm" is not even well-typed across the swap (a^2+b^2 vs a^2-ab+b^2).
lawNormsDifferAcrossSwap :: Bool
lawNormsDifferAcrossSwap =
  any (\(a,b) -> gnorm (Gauss a b) /= enorm (Eisen a b)) [(a,b) | a<-[1,2,3], b<-[1,2,3]]

-- ===========================================================================
-- (5) Runner
-- ===========================================================================

laws :: [(String, Bool)]
laws =
  [ ("lawGaussUnitsFour          (|units Z[i]| = 4)",          lawGaussUnitsFour)
  , ("lawEisenUnitsSix           (|units Z[w]| = 6)",          lawEisenUnitsSix)
  , ("lawNoRingIsoGaussEisen     (4 /= 6 => no ring iso)",     lawNoRingIsoGaussEisen)
  , ("lawBalanceSearchSplitPorts (Haar round-trips on RGB)",   lawBalanceSearchSplitPortsToRGB)
  , ("lawPhi6IsInvolution        (label swap, involutive)",    lawPhi6IsInvolution)
  , ("lawPhi6IsModuleAutomorph   (label-level Z-module aut)",  lawPhi6IsModuleAutomorphism)
  , ("lawPhi6IsLabelOnlyNotIso   (ord i =4 /= 6= ord -w^2)",   lawPhi6IsLabelOnlyNotLatticeIso)
  , ("lawNormsDifferAcrossSwap   (a^2+b^2 /= a^2-ab+b^2)",      lawNormsDifferAcrossSwap)
  ]

main :: IO ()
main = do
  putStrLn "V2DualityTest.hs  -- EXPLORATION (NOT WIRED): does phi6 survive V1->V2 (RGB)?"
  putStrLn (replicate 74 '-')
  mapM_ (\(n,ok) -> putStrLn (verdict ok ++ "  " ++ n)) laws
  putStrLn (replicate 74 '-')
  let passed = length (filter snd laws)
      total  = length laws
  putStrLn ("SUMMARY: " ++ show passed ++ "/" ++ show total ++ " laws PASS"
            ++ if passed == total then "  (all green)" else "  (FAILURES present)")
  putStrLn ""
  putStrLn ("order(i)    in Z[i] = " ++ show (gOrder u90) ++ "   (square, 90-degree)")
  putStrLn ("order(-w^2) in Z[w] = " ++ show (eOrder u60) ++ "   (hexagonal, 60-degree)")
  putStrLn ""
  putStrLn "VERDICT: SURVIVES-WEAKENED. The colour-agnostic Haar Balance/Search split and"
  putStrLn "its exact round-trip port to RGB unchanged; phi6 keeps only its label-level"
  putStrLn "Z-module involution and LOSES the search-plane lattice iso (Z[i] is not Z[w])."
  where verdict True  = "PASS"
        verdict False = "FAIL"
