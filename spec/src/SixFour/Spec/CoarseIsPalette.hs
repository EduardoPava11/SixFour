{- |
Module      : SixFour.Spec.CoarseIsPalette
Description : The 16²=256 bridge as a COMPILE-TIME theorem — at the coarse 16³ scale a frame has exactly 256 cells, which is exactly a palette, so the construction encoder A and the perceptual encoder B COINCIDE there. This is the Analysis-rung fixed point where the two semantics' distance is structurally zero, and the unique side at which palette-size equals frame-pixel-count.

The user's keystone insight: "@16x16=256@ which is also already a colour palette; having 16
of these is yet another layer of semantics". This module makes it a TYPE-LEVEL identity and
hangs the dual-encoder coincidence on it.

  * 'PaletteCells' @= 16 * 16@, and 'coarseEqPalette' @:: PaletteCells :~: 256@ is 'Refl' —
    GHC itself proves @16*16 == 256@ at compile time (the escalation the plan asked for).
  * A frame at side @s@ has @s²@ pixels; a palette has 256 slots. They are EQUAL iff
    @s == 16@. So the coarse 16³ tier is the unique scale where the per-frame palette is not
    a compression at all but an IDENTITY — which is why Encoder A and B coincide there.
  * 'coarseToPaletteStack' — a coarse 16³ cube (@8^4 = 4096 = 16 * 256@ voxels) reshapes
    losslessly into 16 typed palettes 'QPalette' @PaletteCells@ ("having 16 of these").
  * 'lawCoarseFrameSizeIsPaletteSize' — the @Refl@ witness plus its value-level consequence,
    with teeth (side 64 and 256 are NOT the fixed point).
  * 'lawCoarseIsStackOfPalettes' — the reshape is a bijection: 16 palettes of 256 that
    concatenate back to the cube.
  * 'lawCoarsePaletteComparesToPerFrame' — each coarse-derived palette EQUALS that frame's
    perceptual colours: at 16³ the construction palette and the perceptual cloud are the same
    256 colours (cross-encoder distance zero), the Analysis-rung coincidence
    "SixFour.Spec.ScaleIndexedCorrespondence" delegates.

Additive: reuses "SixFour.Spec.ConstructionEncoder" @QColour@,
"SixFour.Spec.PerceptualEncoder", "SixFour.Spec.SameObjectInvariance" @Cube@,
"SixFour.Spec.OctreeGenome" @octreeLeafCount@. GHC-boot-only (@base@: GHC.TypeLits,
Data.Type.Equality). Laws QuickCheck'd in "Properties.CoarseIsPalette".
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.CoarseIsPalette
  ( -- * The 16²=256 identity as a type
    PaletteCells
  , QPalette(..)
  , mkQPalette
  , paletteCells
  , coarseSide
  , coarseDepth
  , framePixels
  , coarseFrameCount
  , coarseEqPalette
    -- * The depth-5 midpoint (32^3, the never-surfaced organisable level)
  , intermediateDepth
  , intermediateSide
    -- * The coarse cube reshaped into a stack of palettes, and the index-free decode
  , coarseToPaletteStack
  , decodeAPalettesOnly
  , paletteStackComplete256
    -- * Laws (QuickCheck'd in @Properties.CoarseIsPalette@)
  , lawCoarseFrameSizeIsPaletteSize
  , lawCoarseIsStackOfPalettes
  , lawCoarsePaletteComparesToPerFrame
  , lawSixteenPalettesReconstructCube
  , lawMidpointIsPaletteStack
  ) where

import Data.List          (nub)
import Data.Proxy          (Proxy(..))
import Data.Type.Equality  ((:~:)(Refl))
import GHC.TypeLits        (Nat, KnownNat, natVal)
import qualified GHC.TypeNats as TN   -- the type-level multiplication (bare @*@ means @Type@)

import SixFour.Spec.SameObjectInvariance (Cube(..), validCube)
import SixFour.Spec.ConstructionEncoder  (QColour)
import SixFour.Spec.PerceptualEncoder    (perceptualEmbed)
import SixFour.Spec.RelationalResidual   (P6(..))
import SixFour.Spec.OctreeGenome         (octreeLeafCount)

-- | The number of cells in a coarse 16³ frame, AS A TYPE: @16 * 16@. GHC reduces it to
-- @256@, which is exactly a palette's size.
type PaletteCells = 16 TN.* 16

-- | A palette of @k@ Q16 colours (type-level cardinality). The integer twin of a
-- "SixFour.Spec.Palette" @Palette k@; a coarse frame is a @QPalette PaletteCells@.
newtype QPalette (k :: Nat) = QPalette { unQPalette :: [QColour] }
  deriving (Eq, Show)

-- | Build a 'QPalette' @k@ if the list has exactly @k@ colours (the checked path; the
-- reshape below uses the raw constructor on already-256-long chunks).
mkQPalette :: forall k. KnownNat k => [QColour] -> Maybe (QPalette k)
mkQPalette xs
  | length xs == fromIntegral (natVal (Proxy :: Proxy k)) = Just (QPalette xs)
  | otherwise                                             = Nothing

-- | The palette size at runtime, read off the TYPE @PaletteCells@ (@= 256@).
paletteCells :: Int
paletteCells = fromIntegral (natVal (Proxy :: Proxy PaletteCells))

-- | The coarse Analysis-tier side (@16@).
coarseSide :: Int
coarseSide = 16

-- | The octant depth of the coarse tier: @16³ ⇒ d = 4@ (@8^4 = 4096@ voxels).
coarseDepth :: Int
coarseDepth = 4

-- | Pixels in a frame of side @s@ (@s²@). Equals 'paletteCells' iff @s == 16@.
framePixels :: Int -> Int
framePixels s = s * s

-- | How many palette-sized frames a coarse cube holds: @8^4 / 256 = 16@ ("having 16 of
-- these"). Equals 'coarseSide'.
coarseFrameCount :: Int
coarseFrameCount = octreeLeafCount coarseDepth `div` paletteCells

-- | THE compile-time theorem: @16 * 16 == 256@. 'Refl' typechecks only because GHC's own
-- type-literal normaliser reduces the product — the @16²=256@ identity is checked by the
-- compiler, not asserted at runtime.
coarseEqPalette :: PaletteCells :~: 256
coarseEqPalette = Refl

-- | Split a list into @n@-length chunks (total).
chunksOf :: Int -> [a] -> [[a]]
chunksOf n = go
  where
    go [] = []
    go xs = take n xs : go (drop n xs)

-- | Reshape a coarse 16³ cube into its 16 palettes of 256 colours — "having 16 of these is
-- yet another layer of semantics". Each chunk is a @QPalette PaletteCells@.
coarseToPaletteStack :: Cube -> [QPalette PaletteCells]
coarseToPaletteStack (Cube cl ca cb) =
  map QPalette (chunksOf paletteCells (zip3 cl ca cb))

-- | The A-form DECODE: reconstruct a coarse cube from ONLY its stack of palettes, with NO
-- index map. Concatenate the palettes' colours in their canonical (Morton) order and split
-- into the three channels. The exact inverse of 'coarseToPaletteStack': the position of a
-- colour in its palette IS its cell, so 16 ordered palettes suffice.
decodeAPalettesOnly :: [QPalette PaletteCells] -> Cube
decodeAPalettesOnly pals =
  let cols = concatMap unQPalette pals
  in Cube [ l | (l,_,_) <- cols ] [ a | (_,a,_) <- cols ] [ b | (_,_,b) <- cols ]

-- | Is every palette in the stack COMPLETE-256 (exactly 256 entries, all DISTINCT)? This is
-- the precondition under which the dropped index is genuinely the identity (a complete-256
-- frame in canonical order, "SixFour.Spec.ConstructionEncoder" @identityIndex@). Absent it,
-- the colours-in-order still reconstruct correctly but are no longer a deduplicated palette.
-- The typed-cube counterpart is the "SixFour.Spec.Indices" @CompleteVoxelVolume@ brand.
paletteStackComplete256 :: [QPalette PaletteCells] -> Bool
paletteStackComplete256 =
  all (\(QPalette xs) -> length xs == 256 && length (nub xs) == 256)

-- | The octant depth of the never-surfaced midpoint between 64³ and 16³: @32³ ⇒ d = 5@ (one
-- octant level above the coarse 16³ tier).
intermediateDepth :: Int
intermediateDepth = 5

-- | The midpoint side (@32@). A @32³@ frame has @32·32 = 1024 = 4·256@ cells: FOUR palettes,
-- not one, so the midpoint is richer than a single palette (the organisable level the net
-- fills, "SixFour.Spec.RungPivot").
intermediateSide :: Int
intermediateSide = 32

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.CoarseIsPalette)
-- ============================================================================

-- | The @16²=256@ fixed point, witnessed by the compile-time 'coarseEqPalette' and its
-- value-level consequence: a coarse frame has 256 pixels = a palette, the cube holds 16 such
-- frames. TEETH: side 64 (4096 pixels) and side 256 (65536) are NOT palette-sized, so 16 is
-- the UNIQUE side where the per-frame palette is an identity rather than a compression —
-- exactly why the two encoders coincide only at the coarse tier.
lawCoarseFrameSizeIsPaletteSize :: Bool
lawCoarseFrameSizeIsPaletteSize =
  case coarseEqPalette of
    Refl ->
         paletteCells == 256
      && framePixels coarseSide == paletteCells   -- 16*16 == 256 (the fixed point)
      && framePixels 64  /= paletteCells          -- teeth: pivot frame over-budget
      && framePixels 256 /= paletteCells          -- teeth: synthesis frame far over-budget
      && coarseFrameCount == coarseSide            -- 4096 / 256 == 16 frames

-- | The reshape is a BIJECTION: a coarse cube becomes exactly 16 palettes of 256 colours
-- that concatenate back to the cube's colour stream. Teeth: a lossy reshape (wrong chunk
-- size, dropped frame) would change the count, a length, or the concatenation.
lawCoarseIsStackOfPalettes :: Cube -> Bool
lawCoarseIsStackOfPalettes cube
  | not (validCube coarseDepth cube) = True
  | otherwise =
      let stack         = coarseToPaletteStack cube
          Cube cl ca cb = cube
      in length stack == coarseFrameCount
         && all ((== paletteCells) . length . unQPalette) stack
         && concatMap unQPalette stack == zip3 cl ca cb

-- | THE coincidence: each coarse-derived palette EQUALS that frame's perceptual colours. At
-- 16³ the construction encoder's per-frame palette (256 colours) and the perceptual
-- encoder's per-frame colour cloud are the SAME 256 colours — the cross-encoder distance is
-- structurally zero. This is the Analysis-rung exactness
-- "SixFour.Spec.ScaleIndexedCorrespondence" rides. Teeth: requires each frame to be exactly
-- 256 colours (the @16²=256@ identity); at any other side the per-frame palette would not be
-- an identity and the equality would not hold cell-for-cell.
lawCoarsePaletteComparesToPerFrame :: Cube -> Bool
lawCoarsePaletteComparesToPerFrame cube
  | not (validCube coarseDepth cube) = True
  | otherwise =
      let stack     = coarseToPaletteStack cube
          cloud     = perceptualEmbed coarseDepth cube
          cloudCols = [ (p6L p, p6A p, p6B p) | p <- cloud ]
          frameCols = chunksOf paletteCells cloudCols
      in map unQPalette stack == frameCols
         && all ((== paletteCells) . length) frameCols

-- | THE A-form "no index map" theorem: 16 ordered palettes reconstruct the coarse cube
-- EXACTLY, with no index field transmitted. @decodeAPalettesOnly . coarseToPaletteStack == id@
-- on a well-formed 16³ cube: the position of a colour in its palette IS its cell. Teeth: a
-- lossy reshape (wrong chunk size, dropped palette, reordered colours) changes a colour or the
-- count and fails the round-trip on any well-formed cube.
lawSixteenPalettesReconstructCube :: Cube -> Bool
lawSixteenPalettesReconstructCube cube
  | not (validCube coarseDepth cube) = True
  | otherwise = decodeAPalettesOnly (coarseToPaletteStack cube) == cube

-- | The 32³ midpoint is a STACK OF 4 PALETTES per frame, not one: @framePixels 32 = 1024 =
-- 4·256@. Unlike the 16³ identity scale (where a frame IS exactly one palette), the midpoint
-- has spare capacity, which is why it is the organisable level. Teeth: @framePixels 32 /=
-- paletteCells@ (NOT the identity scale) and @intermediateDepth == coarseDepth + 1@ (one octant
-- level above 16³), mirroring 'lawCoarseFrameSizeIsPaletteSize' at 64.
lawMidpointIsPaletteStack :: Bool
lawMidpointIsPaletteStack =
     framePixels intermediateSide == 4 * paletteCells   -- 1024 = 4·256
  && framePixels intermediateSide /= paletteCells        -- NOT the identity scale
  && intermediateDepth == coarseDepth + 1                -- 32³ is one octant level above 16³
