{- |
Module      : SixFour.Spec.HaarRibbon
Description : Act III — the 2⁸ Haar abstraction ribbon: scroll → abstraction level, protect → keep distinct.

The authoring story's third act (`docs/SIXFOUR-PALETTE-STORY-WORKFLOW.md`). @2⁸@ is the *abstraction* lens:
a scrollable σ-pair ribbon over the depth-8 binary Haar 'SixFour.Spec.SplitTree'. The user travels DOWN the
ribbon to abstract GIFA's 256 colours toward the one global palette they commit.

  * __scroll = Haar level__ @L ∈ [0 .. 8]@. @L = 8@ (top) = all 256 leaves distinct (no abstraction);
    @L = 0@ (bottom) = one group = the global core. Pulling the ribbon down lowers @L@ → fewer, coarser
    groups (σ-pairs merge into their Haar parent).
  * __tap = protect__. A protected leaf (typically a *core colour* from Act II,
    'SixFour.Spec.QuartetDelta.coreColors') is pulled OUT as its own singleton and __never merges__, however
    deep the scroll goes. So the user's sense of "what's important" survives the abstraction.

Output: the surviving groups at @(L, protect)@ — each a merged representative colour — ARE the global
palette the user is organising. Where they stop scrolling (+ what they protected) is what Act IV exports.

This is the @2⁸@ specialisation of the collapse lever, made a *gesture* (scroll) rather than a slider, with
the protect-refinement on top. Refines "SixFour.Spec.SplitTree"; consumes Act II's protect-set. Self-
contained (imports only 'SplitTree' + 'Color'). Laws are the parity gate (Properties.HaarRibbon).
-}
-- COMPARTMENT: SWIFT-COREAI | tag:DisplaySide
module SixFour.Spec.HaarRibbon
  ( RibbonGroup(..)
  , ribbonLevels
  , ribbonGroups
  , ribbonPalette
  , ribbonGroupCount
  , globalCore
    -- * Laws (predicates; QuickCheck'd in Properties.HaarRibbon)
  , lawRibbonMonotone
  , lawRibbonTopIsFull
  , lawRibbonBottomIsCore
  , lawProtectedNeverMerge
  , lawRibbonPartitionTotal
  , lawProtectRefines
  ) where

import Data.List (foldl', sort)

import SixFour.Spec.Color     (OKLab(..))
import SixFour.Spec.SplitTree
  ( SplitTree, IndexedColor(..), buildSplitTree
  , leaves, descendantsAt, paletteDepth, numLeaves )

-- | A surviving group on the ribbon: its leaf slot indices, whether it is a protected singleton, and the
-- merged representative colour the cell renders.
data RibbonGroup = RibbonGroup
  { rgIndices   :: [Int]
  , rgProtected :: Bool
  , rgColor     :: OKLab
  } deriving (Eq, Show)

-- | Number of scroll stops: @L = 0 .. paletteDepth@ → 9 levels (0 = core, 8 = full 256).
ribbonLevels :: Int
ribbonLevels = paletteDepth + 1

-- | The ribbon's surviving groups at Haar level @L@ with a protect-set (leaf slot indices). The base @2^L@
-- groups (Haar subtrees at binary depth @L@) are refined: any protected leaf is split out as its own
-- singleton; the remaining unprotected leaves of a subtree stay one merged group.
ribbonGroups :: Int -> [Int] -> SplitTree -> [RibbonGroup]
ribbonGroups l protect t =
  concatMap (splitProtected protect) (descendantsAt (clamp l) t)
  where clamp x = max 0 (min paletteDepth x)

-- | Within one Haar subtree: emit the unprotected leaves as a single merged group (if any), then each
-- protected leaf as its own untouched singleton (canonical leaf order).
splitProtected :: [Int] -> SplitTree -> [RibbonGroup]
splitProtected protect g =
  let (prot, rest) = foldr step ([], []) (leaves g)
      step ic (ps, rs) | icIndex ic `elem` protect = (ic : ps, rs)
                       | otherwise                 = (ps, ic : rs)
      restGroup = [ RibbonGroup (map icIndex rest) False (meanColor rest) | not (null rest) ]
      protGroups = [ RibbonGroup [icIndex ic] True (icColor ic) | ic <- prot ]
  in restGroup ++ protGroups

-- | The ribbon's surviving palette: one representative colour per group.
ribbonPalette :: Int -> [Int] -> SplitTree -> [OKLab]
ribbonPalette l p = map rgColor . ribbonGroups l p

-- | Number of surviving colours at @(L, protect)@.
ribbonGroupCount :: Int -> [Int] -> SplitTree -> Int
ribbonGroupCount l p = length . ribbonGroups l p

-- | The global core — the single colour at the very bottom of the scroll (@L = 0@, the root mean).
globalCore :: SplitTree -> OKLab
globalCore = meanColor . leaves

--------------------------------------------------------------------------------
-- internal
--------------------------------------------------------------------------------

meanColor :: [IndexedColor] -> OKLab
meanColor [] = OKLab 0 0 0
meanColor ics =
  let n = fromIntegral (length ics)
  in scaleOK (1 / n) (foldl' addOK (OKLab 0 0 0) (map icColor ics))

addOK :: OKLab -> OKLab -> OKLab
addOK (OKLab l a b) (OKLab l' a' b') = OKLab (l + l') (a + a') (b + b')

scaleOK :: Double -> OKLab -> OKLab
scaleOK s (OKLab l a b) = OKLab (s * l) (s * a) (s * b)

--------------------------------------------------------------------------------
-- Laws (predicates; exercised by Properties.HaarRibbon)
--------------------------------------------------------------------------------

-- | Scrolling toward the top (higher @L@, less abstraction) never reduces the colour count — abstraction is
-- monotone in scroll. (No protects; perfect 256-leaf tree.)
lawRibbonMonotone :: Bool
lawRibbonMonotone =
  let t = buildSplitTree (sampleLeaves numLeaves)
  in all (\l -> ribbonGroupCount (l + 1) [] t >= ribbonGroupCount l [] t)
         [0 .. paletteDepth - 1]

-- | The top of the ribbon (@L = 8@) shows all 256 leaves, distinct.
lawRibbonTopIsFull :: Bool
lawRibbonTopIsFull =
  let t = buildSplitTree (sampleLeaves numLeaves)
  in ribbonGroupCount paletteDepth [] t == numLeaves

-- | The bottom (@L = 0@, no protects) collapses to the single global core.
lawRibbonBottomIsCore :: Bool
lawRibbonBottomIsCore =
  let t = buildSplitTree (sampleLeaves numLeaves)
  in ribbonGroupCount 0 [] t == 1

-- | A protected leaf appears as its own untouched singleton at EVERY level — it never merges.
lawProtectedNeverMerge :: Bool
lawProtectedNeverMerge =
  let t = buildSplitTree (sampleLeaves numLeaves)
      k = 0  -- protect leaf slot 0
  in all (\l -> RibbonGroup [k] True (leafColor t k) `elem` ribbonGroups l [k] t)
         [0 .. paletteDepth]

-- | The groups always partition all 256 leaf slots: every slot in exactly one group, none lost or doubled.
lawRibbonPartitionTotal :: Bool
lawRibbonPartitionTotal =
  let t  = buildSplitTree (sampleLeaves numLeaves)
      gs = ribbonGroups 4 [0, 5, 10] t
      ix = sort (concatMap rgIndices gs)
  in ix == [0 .. numLeaves - 1]

-- | Protecting only ever SPLITS: every protected-ribbon group's indices are a subset of some base
-- (no-protect) group's indices at the same level. (Protects refine; never merge across base groups.)
lawProtectRefines :: Bool
lawProtectRefines =
  let t     = buildSplitTree (sampleLeaves numLeaves)
      base  = map rgIndices (ribbonGroups 4 [] t)
      prot  = map rgIndices (ribbonGroups 4 [0, 5, 10] t)
  in all (\g -> any (\b -> all (`elem` b) g) base) prot

--------------------------------------------------------------------------------
-- internal: deterministic distinct sample + a leaf-colour lookup (for the `once` laws)
--------------------------------------------------------------------------------

leafColor :: SplitTree -> Int -> OKLab
leafColor t k =
  head ([ icColor ic | ic <- leaves t, icIndex ic == k ] ++ [OKLab 0 0 0])

sampleLeaves :: Int -> [IndexedColor]
sampleLeaves n =
  [ IndexedColor i (OKLab (frac (fromIntegral i * 0.6180339887498949))
                          (0.4 * (frac (fromIntegral i * 0.3819660112501051) * 2 - 1))
                          (0.4 * (frac (fromIntegral i * 0.2360679774997897) * 2 - 1)))
  | i <- [0 .. n - 1] ]
  where frac x = x - fromIntegral (floor x :: Int)
