{- |
Module      : V2SkiNativeGif
Description : EXPLORATION (NOT WIRED, base-only, runghc). SKI made NATIVE to GIF89a in
              8-bit sRGB. The S, K, I reduction equations hold with actual GIF89a objects
              (a per-frame sRGB888 palette + an index map) as the reduced VALUES, not an
              abstract Comb bolted on "by argument". V2 substrate: raw sRGB 8-bit RGB,
              Lab DROPPED, no stored luma/chroma (chroma is a derived view only).

  Check:  runghc V2SkiNativeGif.hs
     or:  cd spec && cabal exec -- runghc exploration/V2SkiNativeGif.hs

  THE POINT (owner directive 2026-06-29): "SKI is powerful and can be used, but first we
  must make it native to the GIF89a." GifSki.hs reduces an ABSTRACT Comb (S|K|I|App) that
  is tied to the codec only by argument. Here the SAME three reduction equations are
  realized DIRECTLY on GIF89a Frames in sRGB888, and the substructural grading
  (I = bijection, K = weakening, S = contraction) is checked against the native operations.

  REAL (axioms hold, toothed):
    * K = weakening: @gK f _ = f@ natively DISCARDS the second frame (its information is lost).
    * I = the reversible held rung: @shiftFrame@ is a genuine RGB888 bijection with a
      witnessed inverse (round-trips), and is non-trivial (a non-zero shift changes render).
    * S = contraction: @gS f g x = f x (g x)@ feeds the coarse frame x TWICE; the native
      invention INCREASES the distinct-colour count (super-res) where I preserves it and K
      discards it (checked over I/K/S, not a global uniqueness claim).
    * render = palette . index = B (the composition combinator), native sRGB888.
    * sRGB-8-bit closure: every operation stays in 0..255 (Lab dropped, nothing float/Lab stored).

  SUGGESTIVE (scoped, NOT claimed as a theorem):
    * That the GIF codec AS A WHOLE is an SKI program. We exhibit agreement only on the
      B / composition fragment ('lawAbstractBMatchesNativeCompose', reusing
      'GifSki.lawComposition'); a full typed homomorphism Comb -> GIF-operations for S is
      left OPEN (see the HONEST NOTE).
-}
module V2SkiNativeGif where

import Data.List (nub)
import qualified GifSki as G

-- ===========================================================================
-- (1) The native sRGB 8-bit GIF89a substrate (Lab DROPPED)
-- ===========================================================================

-- | A colour channel: 8-bit sRGB, the ONLY colour domain in V2 (0..255).
type Chan = Int

-- | A native sRGB888 colour. No Lab, no float, no stored luma/chroma.
type RGB = (Chan, Chan, Chan)

-- | A palette slot index (0..255 in a real GIF; small here for checking).
type Slot = Int

-- | A pixel position (x, y).
type Pos = (Int, Int)

-- | Clamp to the 8-bit sRGB domain. The native domain is CLOSED under this.
clamp8 :: Int -> Int
clamp8 = max 0 . min 255

-- | Is a colour inside the native 8-bit sRGB box?
inSrgb8 :: RGB -> Bool
inSrgb8 (r, g, b) = all (\c -> c >= 0 && c <= 255) [r, g, b]

-- | A GIF89a frame: a per-frame palette (the colour VALUE head, Slot -> sRGB888) and
--   an index map (the discrete CONTENT head, Pos -> Slot). This IS the V2 object.
data Frame = Frame { fPal :: Slot -> RGB, fIdx :: Pos -> Slot }

-- | Render one pixel NATIVELY: colour = palette (index pos) = (fPal . fIdx) pos = B fPal fIdx pos.
renderAt :: Frame -> Pos -> RGB
renderAt f p = fPal f (fIdx f p)

-- Sample domain for extensional equality (a Frame holds functions, not data).
sampleGrid :: [Pos]
sampleGrid = [(x, y) | y <- [0 .. 3], x <- [0 .. 3]]

renderSample :: Frame -> [RGB]
renderSample f = map (renderAt f) sampleGrid

-- | Extensional frame equality on the sample grid.
frameEq :: Frame -> Frame -> Bool
frameEq a b = renderSample a == renderSample b

-- | Distinct colours a frame actually produces (the "cardinality" S can raise and K cannot).
distinctColours :: Frame -> Int
distinctColours = length . nub . renderSample

-- | Build a Frame from a pixel-colour function by giving each sample position its own slot.
--   Lets us materialize blended / invented frames as genuine (palette, index) pairs.
--   On the sample grid, @renderAt (materialize h) p == h p@.
materialize :: (Pos -> RGB) -> Frame
materialize h = Frame pal idx
  where
    assoc    = zip sampleGrid [0 ..]              -- pos -> slot (bijective on the grid)
    idx p    = maybe 0 id (lookup p assoc)
    palAssoc = [ (s, h p) | (p, s) <- assoc ]     -- slot -> colour
    pal s    = maybe (0, 0, 0) id (lookup s palAssoc)

-- ===========================================================================
-- (2) The three combinators, NATIVE (their values are GIF89a Frames / Frame-ops)
-- ===========================================================================

-- | I, native: identity on a frame. The reversible HELD rung. A non-trivial witness of
--   the I-CLASS is 'shiftFrame' below (a real RGB888 bijection), of which I is @shiftFrame 0@.
gI :: Frame -> Frame
gI = id

-- | K, native: @K f _ = f@. Keeps the first frame, DISCARDS the second (weakening).
gK :: Frame -> Frame -> Frame
gK f _ = f

-- | S, native: @S f g x = f x (g x)@. The coarse frame x is fed to BOTH g and f (used twice =
--   the contraction structural rule). On the GIF object this is invention: g manufactures
--   detail FROM the coarse, f anchors the coarse against that detail.
gS :: (Frame -> Frame -> Frame) -> (Frame -> Frame) -> Frame -> Frame
gS f g x = f x (g x)

-- | A genuine sRGB888 bijection: add k to every channel mod 256. Inverse is @shift (256-k)@.
--   This is the I-class witness (reversible), the native slot/colour gauge.
shift :: Int -> RGB -> RGB
shift k (r, g, b) = ((r + k) `mod` 256, (g + k) `mod` 256, (b + k) `mod` 256)

shiftFrame :: Int -> Frame -> Frame
shiftFrame k (Frame pal idx) = Frame (shift k . pal) idx

-- ===========================================================================
-- (3) Concrete native witnesses: coarse, invention, anchor-blend
-- ===========================================================================

-- | A demo frame with real structure (several distinct colours), for the B / sRGB laws.
demoFrame :: Frame
demoFrame = materialize (\(x, y) -> (clamp8 (x * 60), clamp8 (y * 60), 30))

-- | The COARSE input x: one flat colour everywhere (1 distinct colour). The base of invention.
coarse :: Frame
coarse = materialize (const (8, 8, 8))

-- | g (invent): manufacture detail FROM the coarse frame. Reads coarse's base colour (uses x),
--   then varies it by position parity, surfacing NEW colours not present in the flat coarse.
invent :: Frame -> Frame
invent x = materialize $ \(px, py) ->
  let (r, g, b) = renderAt x (0, 0)          -- reads the coarse base (this is one use of x)
      k         = (px + py) `mod` 4
  in (clamp8 (r + 30 * k), clamp8 (g + 10 * k), clamp8 b)

-- | f (anchor-blend): combine the coarse anchor x with invented detail d, per pixel.
--   Uses x AGAIN (the second use that makes gS a real contraction).
anchorBlend :: Frame -> Frame -> Frame
anchorBlend x d = materialize $ \p ->
  let (r1, g1, b1) = renderAt x p             -- coarse anchor (second use of x)
      (r2, g2, b2) = renderAt d p             -- invented detail
  in ((r1 + r2) `div` 2, (g1 + g2) `div` 2, (b1 + b2) `div` 2)

-- | The invented frame: S anchorBlend invent coarse. The super-res surplus, native.
inventedFrame :: Frame
inventedFrame = gS anchorBlend invent coarse

-- ===========================================================================
-- (4) Laws (each a Bool, toothed)
-- ===========================================================================

-- | I is the reversible held rung: shiftFrame round-trips (bijection with a witnessed
--   inverse), AND it is NON-trivial (a non-zero shift genuinely changes render). The pairing
--   of "invertible" with "non-trivial" is the tooth: it is a real bijection, not a hidden id.
lawNativeIReversible :: Bool
lawNativeIReversible =
     and [ frameEq (shiftFrame ((256 - k) `mod` 256) (shiftFrame k demoFrame)) demoFrame
         | k <- [0, 1, 7, 200] ]                          -- round-trips for every shift
  && not (frameEq (shiftFrame 7 demoFrame) demoFrame)      -- tooth: shift 7 is NOT the identity
  && frameEq (gI demoFrame) demoFrame                      -- gI is the k=0 case

-- | K is weakening: @gK f _ = f@ keeps the first frame and DISCARDS the second. The tooth:
--   two DIFFERENT second arguments give the SAME result (information was discarded), and the
--   two second arguments really differ (so something was actually thrown away).
lawNativeKDiscards :: Bool
lawNativeKDiscards =
     frameEq (gK demoFrame coarse) demoFrame                          -- K f _ = f
  && frameEq (gK demoFrame coarse) (gK demoFrame inventedFrame)       -- 2nd arg discarded
  && not (frameEq coarse inventedFrame)                               -- tooth: the discarded args differ

-- | S is contraction = invention: @gS f g x@ uses the coarse x TWICE and RAISES the distinct-colour
--   count where I and K do NOT. Teeth: the invented surplus is real (g genuinely creates colours),
--   K discards exactly that surplus, and I preserves the count, so S is the move that raises it.
lawNativeSInvents :: Bool
lawNativeSInvents =
     distinctColours inventedFrame > distinctColours coarse           -- S raised cardinality (invention)
  && distinctColours (invent coarse) > distinctColours coarse         -- the surplus is real (g creates it)
  && distinctColours (gK coarse (invent coarse)) == distinctColours coarse  -- K discards that surplus
  && distinctColours (gI coarse) == distinctColours coarse            -- I preserves the count (neither raises)

-- | render = palette . index = B (the composition combinator), native sRGB888.
--   Near-definitional pointwise (flagged); the bite is carried by the abstract-agreement law.
lawNativeRenderIsB :: Bool
lawNativeRenderIsB =
     all (\p -> renderAt demoFrame p == (fPal demoFrame . fIdx demoFrame) p) sampleGrid
  && distinctColours demoFrame > 1                                    -- non-vacuous: real structure

-- | sRGB 8-bit closure: every native operation stays in 0..255. Lab is DROPPED: there is no
--   float / no Lab coordinate anywhere; out-of-range integers are clamped back into the box.
lawSrgb8NativeNoLab :: Bool
lawSrgb8NativeNoLab =
     all inSrgb8 (concatMap renderSample [coarse, inventedFrame, demoFrame, shiftFrame 200 demoFrame])
  && not (inSrgb8 (300, -5, 128))                                     -- tooth: this colour is OUT of the box
  && inSrgb8 (clamp8 300, clamp8 (-5), clamp8 128)                    -- clamp genuinely brings it back in
  && clamp8 300 == 255 && clamp8 (-5) == 0                            -- the domain is closed under clamp8

-- | Two facts that hold INDEPENDENTLY (this is a conjunction, NOT a cross-check): GifSki's abstract
--   B law is green (nf (b f g x) == nf (f (g x))), and the native render is B-shaped (palette . index).
--   The genuine native <-> abstract BRIDGE is V2SkiHomomorphism.lawSIsNativeInvention; this law only
--   records that both calculi realize the same composition equation, not that one verifies the other.
lawBLawGreenAndRenderBShaped :: Bool
lawBLawGreenAndRenderBShaped =
     G.lawComposition                                                 -- abstract: B f g x reduces to f (g x)
  && all (\p -> renderAt demoFrame p == (fPal demoFrame . fIdx demoFrame) p) sampleGrid  -- native: same shape

-- ===========================================================================
-- (5) Runner (mirrors GifSki.hs)
-- ===========================================================================

laws :: [(String, Bool)]
laws =
  [ ("lawNativeIReversible        (I = sRGB888 bijection, witnessed inverse)", lawNativeIReversible)
  , ("lawNativeKDiscards          (K f _ = f : weakening, 2nd arg lost)",       lawNativeKDiscards)
  , ("lawNativeSInvents           (S raises colour count where I/K do not)",    lawNativeSInvents)
  , ("lawNativeRenderIsB          (render = palette . index = B)",              lawNativeRenderIsB)
  , ("lawSrgb8NativeNoLab         (8-bit sRGB closed, Lab dropped)",            lawSrgb8NativeNoLab)
  , ("lawBLawGreenAndRenderBShaped(GifSki B green + native render B-shaped)",   lawBLawGreenAndRenderBShaped)
  ]

main :: IO ()
main = do
  putStrLn "V2SkiNativeGif.hs  -- EXPLORATION (NOT WIRED): SKI made NATIVE to GIF89a in 8-bit sRGB"
  putStrLn (replicate 72 '-')
  mapM_ (\(n, ok) -> putStrLn (verdict ok ++ "  " ++ n)) laws
  putStrLn (replicate 72 '-')
  let passed = length (filter snd laws)
      total  = length laws
  putStrLn ("SUMMARY: " ++ show passed ++ "/" ++ show total ++ " laws PASS"
            ++ if passed == total then "  (all green)" else "  (FAILURES present)")
  putStrLn ""
  putStrLn ("coarse distinct colours    = " ++ show (distinctColours coarse))
  putStrLn ("invented distinct colours  = " ++ show (distinctColours inventedFrame)
            ++ "   (S raised it: " ++ show (distinctColours inventedFrame > distinctColours coarse) ++ ")")
  putStrLn ("shiftFrame 7 round-trips   = "
            ++ show (frameEq (shiftFrame (256 - 7) (shiftFrame 7 demoFrame)) demoFrame))
  putStrLn ""
  putStrLn "HONEST NOTE: the S/K/I reduction equations hold with GIF89a Frames as the reduced"
  putStrLn "values, in 8-bit sRGB (Lab dropped). I = a witnessed RGB888 bijection, K = genuine"
  putStrLn "weakening, S = the colour-count-raising contraction where I/K do not (invention)."
  putStrLn "What stays SUGGESTIVE: reading the GIF codec AS A WHOLE as an SKI program. We show only"
  putStrLn "fragment agreement with the abstract reducer (B / composition, via GifSki.lawComposition);"
  putStrLn "a full typed homomorphism Comb -> GIF-operations for S is OPEN, the next honest step."
  where
    verdict True  = "PASS"
    verdict False = "FAIL"
