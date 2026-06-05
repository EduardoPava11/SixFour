{- |
Module      : SixFour.Spec.PairTreeFixed
Description : The OWNED integer (Q16) Haar palette tree — reversible lifting.

Where 'SixFour.Spec.PairTree' is the @Double@ Haar (perceptual reference; its
round-trip holds only to a TOLERANCE because @x+y@ then @/2@ loses the LSB in
float), THIS module is the integer contract: a **reversible integer Haar**
(the lifting-scheme S-transform, JPEG2000-lossless lineage) over Q16 OKLab
triples. Every step is expressible identically in Zig (i32 add/sub,
@\@divFloor@ by 2), so the Haskell golden and the @s4_haar_*@ kernel agree
BYTE-FOR-BYTE, and:

  * @reconstructFixed . analyzeFixed = id@ is EXACT (no tolerance) for any
    power-of-two leaf count — see 'lawReconstructAnalyzeRoundTripExact';
  * a 'MoveI' composed with its inverse is EXACTLY the identity (integer add then
    subtract) — 'lawMoveRoundTripExact'; the float version needed @haarClose@.

This is the owned integer substrate of "the way we turn GIFA→GIFB": the palette's
dimensional space (root + 8 levels of offsets) and the reversible moves that walk
it, as exact integer math. The float 'PairTree' and the aesthetic value head map
onto this as greater abstractions.

== The reversible lifting

For an adjacent pair @(x, y)@ (per channel):

> d      = x - y                 -- the full detail (NOT (x-y)/2)
> parent = y + floorDiv d 2      -- a lifted floor-average

Inverse (exact for all integers, floorDiv consistent):

> y = parent - floorDiv d 2
> x = y + d

So a node stores the integer detail @d@ and a lifted parent; the tree is the
recursive application, identical in shape to 'PairTree' (level @i@ has @2^i@
offsets, @2^D@ leaves).
-}
module SixFour.Spec.PairTreeFixed
  ( -- * The integer Haar palette
    OKLabI
  , HaarPaletteI(..)
  , wellFormedI
  , treeDepthI
    -- * Reversible integer lifting (palette ↔ tree)
  , analyzeFixed
  , reconstructFixed
    -- * Coarse-level node colours (byte-exact to Zig @s4_haar_level_nodes@)
  , levelNodesFixed
  , lawLevelNodesFixedCount
  , lawLevelNodesFixedFull
    -- * Reversible integer moves (the path through LAB)
  , MoveI(..)
  , applyMoveI
  , invertMoveI
    -- * Laws (QuickCheck'd in Properties.PairTreeFixed)
  , lawReconstructAnalyzeRoundTripExact
  , lawAnalyzeReconstructStructure
  , lawMoveRoundTripExact
  , lawMovePreservesWellFormed
  , lawLiftPairInvertsExactly
  ) where

-- | A Q16 OKLab triple (scale @2^16@), the integer substrate of
-- 'SixFour.Spec.ColorFixed' and the Zig core.
type OKLabI = (Int, Int, Int)

-- | A palette as an integer Haar pyramid: a @root@ (the lifted DC node) plus, for
-- each of @D@ levels, the integer detail vectors at that split. Level @i@ carries
-- @2^i@ offsets, so the tree has @2^D@ leaves.
data HaarPaletteI = HaarPaletteI
  { rootI   :: OKLabI
  , levelsI :: [[OKLabI]]   -- ^ top-down; @levelsI !! i@ has @2^i@ offsets
  } deriving (Eq, Show)

treeDepthI :: HaarPaletteI -> Int
treeDepthI = length . levelsI

-- | Level @i@ has exactly @2^i@ offsets.
wellFormedI :: HaarPaletteI -> Bool
wellFormedI (HaarPaletteI _ lvls) =
  and [ length (lvls !! i) == 2 ^ i | i <- [0 .. length lvls - 1] ]

-- ---------------------------------------------------------------------------
-- Reversible integer lifting (per channel)
-- ---------------------------------------------------------------------------

-- | Floor division by 2 (arithmetic shift semantics) — Haskell 'div' floors;
-- the Zig port uses @\@divFloor(d, 2)@. The /same/ rounding on both sides is what
-- makes the lift exactly reversible AND byte-identical.
floorHalf :: Int -> Int
floorHalf d = d `div` 2

-- | Forward lift of one pair @(x, y)@ → @(parent, detail)@, per channel.
liftPair :: OKLabI -> OKLabI -> (OKLabI, OKLabI)
liftPair (x1, x2, x3) (y1, y2, y3) =
  let f x y = let d = x - y in (y + floorHalf d, d)   -- (parent, detail)
      (p1, d1) = f x1 y1
      (p2, d2) = f x2 y2
      (p3, d3) = f x3 y3
  in ((p1, p2, p3), (d1, d2, d3))

-- | Inverse lift @(parent, detail)@ → @(x, y)@, per channel. Exact inverse of
-- 'liftPair' for all integers.
unliftPair :: OKLabI -> OKLabI -> (OKLabI, OKLabI)
unliftPair (p1, p2, p3) (d1, d2, d3) =
  let g p d = let y = p - floorHalf d in (y + d, y)    -- (x, y)
      (x1, y1) = g p1 d1
      (x2, y2) = g p2 d2
      (x3, y3) = g p3 d3
  in ((x1, x2, x3), (y1, y2, y3))

-- | Forward integer Haar: collapse @2^D@ leaves into the tree (offsets
-- coarsest-first, like 'SixFour.Spec.PairTree.analyze'). A trailing odd element is
-- dropped (the palette is always a power of two).
analyzeFixed :: [OKLabI] -> HaarPaletteI
analyzeFixed leaves0 = go leaves0 []
  where
    go cur acc
      | length cur <= 1 = HaarPaletteI (headOr0 cur) acc
      | otherwise =
          let reduced = pairReduce cur
          in go (map fst reduced) (map snd reduced : acc)
    pairReduce (x : y : rest) = liftPair x y : pairReduce rest
    pairReduce _              = []
    headOr0 (x : _) = x
    headOr0 []      = (0, 0, 0)

-- | Inverse integer Haar: expand the tree into its @2^D@ leaves. At each level a
-- node @n@ with detail @d@ yields @[x, y] = unliftPair n d@. Exact inverse of
-- 'analyzeFixed'.
reconstructFixed :: HaarPaletteI -> [OKLabI]
reconstructFixed (HaarPaletteI rt lvls) = foldl step [rt] lvls
  where step nodes offs = concat [ let (x, y) = unliftPair n d in [x, y]
                                  | (n, d) <- zip nodes offs ]

-- | The integer node colours at a given pairing @level@ — the **abstraction
-- cascade**, Q16. @level 0 = [rootI]@; @level i@ has @2^i@ nodes; @level treeDepthI@
-- is the full leaf palette. This is 'reconstructFixed' stopped after @level@
-- inverse-lift expansions, so it is byte-identical to the Zig
-- @s4_haar_level_nodes(level, …)@ kernel (same @divFloor@ rounding). SixFour
-- surfaces @levelNodesFixed 4@ (16 colours) as the capture shutter.
levelNodesFixed :: Int -> HaarPaletteI -> [OKLabI]
levelNodesFixed level (HaarPaletteI rt lvls) = foldl step [rt] (take (max 0 level) lvls)
  where step nodes offs = concat [ let (x, y) = unliftPair n d in [x, y]
                                  | (n, d) <- zip nodes offs ]

-- ---------------------------------------------------------------------------
-- Reversible integer moves (the path through LAB)
-- ---------------------------------------------------------------------------

-- | A move perturbs the detail at @(mvLevelI, mvIndexI)@ by an integer Q16
-- @mvDeltaI@. Exactly reversible (integer add then subtract — no float tolerance),
-- lossless, and structure-preserving. Out-of-range targets act as the identity.
data MoveI = MoveI
  { mvLevelI :: Int
  , mvIndexI :: Int
  , mvDeltaI :: OKLabI
  } deriving (Eq, Show)

addI :: OKLabI -> OKLabI -> OKLabI
addI (a, b, c) (d, e, f) = (a + d, b + e, c + f)

negI :: OKLabI -> OKLabI
negI (a, b, c) = (negate a, negate b, negate c)

modifyAt :: Int -> (a -> a) -> [a] -> [a]
modifyAt i f xs
  | i < 0 || i >= length xs = xs
  | otherwise = [ if j == i then f x else x | (j, x) <- zip [0 ..] xs ]

applyMoveI :: MoveI -> HaarPaletteI -> HaarPaletteI
applyMoveI (MoveI lv ix d) (HaarPaletteI rt lvls) =
  HaarPaletteI rt (modifyAt lv (modifyAt ix (addI d)) lvls)

invertMoveI :: MoveI -> MoveI
invertMoveI m = m { mvDeltaI = negI (mvDeltaI m) }

-- ---------------------------------------------------------------------------
-- Laws (predicates; exercised by Properties.PairTreeFixed)
-- ---------------------------------------------------------------------------

-- | EXACT round-trip (no tolerance): re-analysing a palette and reconstructing it
-- returns the identical integer leaves, for any power-of-two leaf count.
lawReconstructAnalyzeRoundTripExact :: [OKLabI] -> Bool
lawReconstructAnalyzeRoundTripExact leaves =
  let n = length leaves
  in not (isPow2 n) || reconstructFixed (analyzeFixed leaves) == leaves
  where isPow2 m = m > 0 && (m == 2 ^ (floor (logBase 2 (fromIntegral m :: Double)) :: Int))

-- | A well-formed tree of depth @D@ reconstructs to exactly @2^D@ leaves, and
-- re-analysing them gives a well-formed tree of the same depth.
lawAnalyzeReconstructStructure :: HaarPaletteI -> Bool
lawAnalyzeReconstructStructure hp =
  not (wellFormedI hp) ||
  let leaves = reconstructFixed hp
  in length leaves == 2 ^ treeDepthI hp
     && treeDepthI (analyzeFixed leaves) == treeDepthI hp

-- | 'levelNodesFixed' has @2^level@ nodes at every level @0..treeDepthI@ (for a
-- well-formed tree) — the cascade shape 256→…→16→…→4→…→1.
lawLevelNodesFixedCount :: HaarPaletteI -> Bool
lawLevelNodesFixedCount hp =
  not (wellFormedI hp) ||
  and [ length (levelNodesFixed l hp) == 2 ^ l | l <- [0 .. treeDepthI hp] ]

-- | The deepest level is the full palette: @levelNodesFixed (treeDepthI) ==
-- reconstructFixed@ (exact, integer).
lawLevelNodesFixedFull :: HaarPaletteI -> Bool
lawLevelNodesFixedFull hp = levelNodesFixed (treeDepthI hp) hp == reconstructFixed hp

-- | A move composed with its inverse is EXACTLY the identity (integer reversibility).
lawMoveRoundTripExact :: MoveI -> HaarPaletteI -> Bool
lawMoveRoundTripExact m s = applyMoveI (invertMoveI m) (applyMoveI m s) == s

-- | A move preserves well-formedness (it changes a value, never the structure).
lawMovePreservesWellFormed :: MoveI -> HaarPaletteI -> Bool
lawMovePreservesWellFormed m s = wellFormedI s == wellFormedI (applyMoveI m s)

-- | The atomic lift inverts exactly for any integer pair (the basis of the whole
-- transform's exactness).
lawLiftPairInvertsExactly :: OKLabI -> OKLabI -> Bool
lawLiftPairInvertsExactly x y =
  let (p, d)        = liftPair x y
      (x', y')      = unliftPair p d
  in x' == x && y' == y
