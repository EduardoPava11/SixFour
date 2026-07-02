{- |
Module      : SixFour.Spec.CurateRealize
Description : The curated-volume → indexed-GIF realization — slice the interleaved Q16 volume the octant ladder built into per-frame pixel lists (the layout pin) and quantize each frame with the SAME verified per-frame quantizer the shipped renderer uses. Frame-LOCAL by law (slab streaming is licensed), lossless on palettizable frames, and the ladder floor of flatness realizes to one colour.

The LAUNCH curate loop (L1.2 row 4) builds a Q16 OKLab volume by the octant
ladder ("SixFour.Spec.SelfSimilarReconstruct" 'expandRungVolume' — floor or
gene-invented detail) and must ship it as a GIF: per-frame palettes + indices.
This module pins that realization:

  * 'volumeFrames' — the LAYOUT pin: the interleaved device volume
    @((t·side + r)·side + c)·3 + ch@ slices into @side@ frames of @side²@
    row-major @(L,a,b)@ triples ('lawFramesPartitionVolume' proves it on a
    position-coded volume, exact).
  * 'realizeIndexed' — each frame through "SixFour.Spec.QuantFixed"
    'quantizeFrameQ16' (maximin seed + optional Lloyd), the SAME bit-exact
    quantizer the shipped 64³ renderer's Stage 1 runs (Zig
    @s4_quantize_frame@, fixture-gated) — the curated export invents NO new
    quantization machinery, it re-parameterizes the verified one.
  * 'lawRealizeIsFrameLocal' — a frame's (palette, indices) depend ONLY on its
    own pixels, so the 256-frame realization streams frame-by-frame (with the
    ladder's block-locality this licenses end-to-end t-slab processing: the
    ~201 MB volume never has to exist whole).
  * 'lawPalettizableRealizeLossless' — a frame with ≤ k distinct colours
    round-trips EXACTLY (@palette[index[i]] == pixel[i]@).
  * 'lawConstantFloorRealizesToOneColour' — the ladder floor of a flat volume
    realizes losslessly to a single colour: the floor never garbles through
    the quantizer (the zero-gene == floor claim carried to the GIF bytes).

== The Upscale256 fork, resolved honestly

"SixFour.Spec.Upscale256" is the OLD deterministic endgame: it blends
per-frame palettes across time and consumes cube A = the GLOBAL-palette
indices — machinery behind @Feature.globalPaletteV2 = false@, unreachable in
MVP1. The LIVE curate floor is therefore the octant ladder's zero-detail
expand realized by THIS module, not @upscale256@; the V3 doc's "zero paint =
the deterministic Upscale256 floor" reads as "the deterministic floor", which
this pipeline realizes. @upscale256@ stays the V2 global-palette endgame.
GHC-boot-only. Laws QuickCheck'd in @Properties.CurateRealize@.
-}
-- COMPARTMENT: ZIG-FLOOR | tag:DeviceTag
module SixFour.Spec.CurateRealize
  ( -- * The layout pin (volume → frames)
    Voxel
  , volumeFrames
  , interleaveChannels
    -- * The realization (frames → per-frame palettes + indices)
  , realizeIndexed
    -- * Laws (QuickCheck'd in @Properties.CurateRealize@)
  , lawFramesPartitionVolume
  , lawRealizeIsFrameLocal
  , lawPalettizableRealizeLossless
  , lawConstantFloorRealizesToOneColour
  ) where

import SixFour.Spec.QuantFixed             (quantizeFrameQ16)
import SixFour.Spec.SelfSimilarReconstruct (expandRungVolume)

-- | One OKLab Q16 voxel\/pixel\/palette entry — @(L, a, b)@ integers (the
-- structural type "SixFour.Spec.QuantFixed" quantizes).
type Voxel = (Int, Int, Int)

-- | The LAYOUT pin: slice an interleaved device volume
-- @((t·side + r)·side + c)·3 + ch@ into @side@ frames, each @side²@ row-major
-- @(L,a,b)@ pixels. Total (missing entries read 0), so a short buffer cannot
-- crash the realization — it degrades to zeros, never garbage reads.
volumeFrames :: Int -> [Int] -> [[Voxel]]
volumeFrames side flat =
  [ [ px ((t * side + r) * side + c)
    | r <- [0 .. side - 1], c <- [0 .. side - 1] ]
  | t <- [0 .. side - 1] ]
  where
    px i = (at (3 * i), at (3 * i + 1), at (3 * i + 2))
    at j = if j >= 0 && j < length flat then flat !! j else 0

-- | Interleave three per-channel scalar volumes (the 'expandRungVolume' output
-- shape, one per L\/a\/b) into the device's channel-interleaved flat volume.
interleaveChannels :: [Int] -> [Int] -> [Int] -> [Int]
interleaveChannels ls as bs =
  concat (zipWith3 (\l a b -> [l, a, b]) ls as bs)

-- | THE REALIZATION: every frame of the volume through the verified per-frame
-- quantizer — @(k, iters)@ exactly as the shipped renderer's Stage 1. Returns
-- per-frame @(palette, index plane)@, the GIF89a content 'SixFour.Gen.GifWire'
-- \/ @s4_gif_assemble@ consume.
realizeIndexed :: Int -> Int -> Int -> [Int] -> [([Voxel], [Int])]
realizeIndexed k iters side = map (quantizeFrameQ16 k iters) . volumeFrames side

-- ---------------------------------------------------------------------------
-- Laws (QuickCheck'd in Properties.CurateRealize)
-- ---------------------------------------------------------------------------

-- | The layout pin, exact: on a POSITION-CODED volume (channel @ch@ of flat
-- voxel @i@ carries the value @3·i + ch@), frame @t@'s pixel @(r,c)@ is
-- exactly the triple of its own coordinates — any axis swap, stride slip, or
-- channel de-interleave error fails.
lawFramesPartitionVolume :: Bool
lawFramesPartitionVolume =
  let side = 3
      n    = side * side * side
      flat = [ v | i <- [0 .. n - 1], v <- [3 * i, 3 * i + 1, 3 * i + 2] ]
      fs   = volumeFrames side flat
  in and
       [ fs !! t !! (r * side + c) == (3 * i, 3 * i + 1, 3 * i + 2)
       | t <- [0 .. side - 1], r <- [0 .. side - 1], c <- [0 .. side - 1]
       , let i = (t * side + r) * side + c ]

-- | Realization is FRAME-LOCAL: perturbing one voxel changes at most its own
-- frame's (palette, indices) — the law that licenses streaming the 256-frame
-- export frame-by-frame (and, with the ladder's block-locality, whole t-slabs).
lawRealizeIsFrameLocal :: [Int] -> Int -> Bool
lawRealizeIsFrameLocal vals kIdx =
  let side = 2
      n3   = side * side * side * 3
      volA = [ if i < length vals then vals !! i else 0 | i <- [0 .. n3 - 1] ]
      j    = ((kIdx `mod` n3) + n3) `mod` n3
      volB = [ if i == j then v + 7 else v | (i, v) <- zip [0 ..] volA ]
      jFrame = (j `div` 3) `div` (side * side)
      ra = realizeIndexed 4 1 side volA
      rb = realizeIndexed 4 1 side volB
  in and [ a == b | (t, (a, b)) <- zip [0 ..] (zip ra rb), t /= jFrame ]

-- | A frame with ≤ k distinct colours realizes LOSSLESSLY:
-- @palette[index[i]] == pixel[i]@ for every pixel — the maximin seeder covers
-- every distinct colour before k runs out, and Lloyd over exact clusters is a
-- fixed point.
lawPalettizableRealizeLossless :: [Int] -> Int -> Bool
lawPalettizableRealizeLossless picks iters =
  let side    = 2
      palette = [(0, 0, 0), (6553, -300, 42), (-1200, 6553, 6553), (65536, 0, -65536)]
      n       = side * side * side
      choose i = palette !! (((pick i `mod` 4) + 4) `mod` 4)
      pick i   = if i < length picks then picks !! i else i
      flat     = concat [ [l, a, b] | i <- [0 .. n - 1], let (l, a, b) = choose i ]
      its      = ((iters `mod` 3) + 3) `mod` 3
      realized = realizeIndexed 4 its side flat
      frames   = volumeFrames side flat
  in and
       [ pal !! ix == p
       | (f, (pal, ixs)) <- zip frames realized
       , (p, ix) <- zip f ixs ]

-- | The ladder floor of FLATNESS realizes to one colour, losslessly: floor-expand
-- a constant volume per channel ('expandRungVolume' with no detail), interleave,
-- realize — every pixel of every frame reproduces the constant exactly. The
-- zero-gene floor survives the quantizer untouched, all the way to GIF content.
lawConstantFloorRealizesToOneColour :: Int -> Int -> Int -> Bool
lawConstantFloorRealizesToOneColour l0 a0 b0 =
  let side  = 2
      n     = side * side * side
      wrap v = v `mod` 60000
      (l, a, b) = (wrap l0, wrap a0, wrap b0)
      grow ch = expandRungVolume side (replicate n ch) Nothing
      flat  = interleaveChannels (grow l) (grow a) (grow b)
      fine  = 2 * side
      realized = realizeIndexed 4 1 fine flat
  in and
       [ pal !! ix == (l, a, b)
       | (pal, ixs) <- realized, ix <- ixs ]
