{-# LANGUAGE DataKinds #-}
{-# LANGUAGE ScopedTypeVariables #-}
{- |
@spec-gif@ — render the look-NN's problem and proofs as GIF files. The GIF is the medium;
there is no HTML. Verdicts print to stdout, the GIFs are the artifacts (open with Quick Look).

Usage: @cabal run spec-gif -- [--out DIR] [--seed N] [--scale S]@

Generate-to-test: 'SixFour.Spec.Scale.layerLawReport' verifies every layer at the real 64³
first; a failing contract @error@s out before anything is drawn. JuicyPixels lives only
here, never in the @sixfour-spec@ library.
-}
module Main (main) where

import           System.Environment   (getArgs)
import           System.Directory     (createDirectoryIfMissing)
import           System.FilePath      ((</>))
import           Text.Printf          (printf)
import           Data.Maybe           (fromJust)
import           Data.Word            (Word64)
import qualified Data.Set             as Set
import qualified Data.Vector          as V
import qualified Data.Vector.Unboxed  as U

import Codec.Picture (Image, PixelRGB8(..))

import SixFour.Spec.Color    (OKLab(..))
import SixFour.Spec.Palette  (mkPalette, paletteToList)
import SixFour.Spec.Cyclic   (CyclicStack(..))
import SixFour.Spec.PairTree (reconstruct, sigmaReflect, phi)
import SixFour.Spec.LookCore (applyLookCore, lookCoreScale, zeroResidualLike)
import SixFour.Spec.Indices  (IndexTensor(..))
import SixFour.Spec.LookNet  (LookInput(..), LookOutput(..), runLookNet, baselinePalette)
import SixFour.Spec.Coverage (gamutCoverageFraction)
import SixFour.Spec.Dither   (binomialVariance, realize)
import SixFour.Spec.Scale    ( synthLookInput, randomResidual, layerLawReport
                             , scaleT, scaleH, scaleW, scaleK )

import SixFour.Viz.Gif

main :: IO ()
main = do
  args <- getArgs
  let out   = argStr "--out"   "/tmp/sixfour-gifs" args
      seed  = read (argStr "--seed"  "1" args) :: Word64
      scale = read (argStr "--scale" "5" args) :: Int
      gap   = PixelRGB8 40 40 40
      w = scaleW; h = scaleH
  createDirectoryIfMissing True out
  putStrLn ("spec-gif → " ++ out ++ "  (seed " ++ show seed ++ ", scale " ++ show scale ++ ")")

  -- GENERATE-TO-TEST: the spec must hold for ALL layers at the real 64³. Run the single
  -- source-of-truth report; refuse to render anything if any layer's contract fails.
  putStrLn "verifying the spec at 64^3 (T·H·W·K = 64·64·64·256):"
  let report = layerLawReport seed
  mapM_ (\(n, ok) -> putStrLn ("  [" ++ (if ok then "PASS" else "FAIL") ++ "] " ++ n)) report
  if all snd report
    then putStrLn "  → all layers hold; rendering the gallery."
    else error ("spec FAILED at 64^3 (layers: "
                ++ show [ n | (n, ok) <- report, not ok ] ++ ") — refusing to render")

  -- THE PROBLEM: 64 per-frame palettes + index maps  →  one global palette + index map.
  let input          = synthLookInput seed
      stack          = liStack input
      floor'         = baselinePalette stack
      output         = runLookNet floor' input
      global         = reconstruct (loPalette output)               -- 256 global OKLab
      localPals      = [ paletteToList p | (p, _) <- V.toList (unStack stack) ]
      localIdxFrames = sliceFrames (liLocalIndices input)
      globalFrames   = sliceFrames (loIndices output)

  writeGif (out </> "input.gif")  (gifPerFramePalette scale w h 5 (zip localPals localIdxFrames))
  writeGif (out </> "output.gif") (gifGlobalPalette  scale w h 5 global globalFrames)

  let beforeAfter =
        [ hcatRGB 8 gap (upscaleNN scale a) (upscaleNN scale b)
        | (a, b) <- zip [ frameToRGB pal w h idx | (pal, idx) <- zip localPals localIdxFrames ]
                        [ frameToRGB global w h idx | idx <- globalFrames ] ]
  writeGif (out </> "problem.gif") (gifFromRGBFrames 5 beforeAfter)

  -- LAW: σ-equivariance — global palette vs its σ-reflection (the complement flip).
  writeGif (out </> "proof_sigma.gif")
    (gifFromRGBFrames 60 [ hcatRGB 12 gap (swatchRGB 16 18 global)
                                          (swatchRGB 16 18 (map sigmaReflect global)) ])

  -- LAW: neutral residual = floor (reset) — the diff renders pure black.
  let zeroOut  = applyLookCore lookCoreScale floor' (zeroResidualLike floor')
      sFloor   = swatchRGB 16 18 (reconstruct floor')
      sZero    = swatchRGB 16 18 (reconstruct zeroOut)
  writeGif (out </> "proof_neutral.gif")
    (gifFromRGBFrames 60 [ hcatRGB 12 gap sFloor (hcatRGB 12 gap sZero (diffRGB sFloor sZero)) ])

  -- LAW: global-surjective yet per-frame-incomplete (the L8 contract), shown frame by frame.
  let usedSwatch idx =
        let used = Set.fromList idx
        in swatchRGB 16 18 [ if i `Set.member` used then global !! i else OKLab 0.07 0 0
                           | i <- [0 .. scaleK - 1] ]
  writeGif (out </> "proof_surjective.gif")
    (gifFromRGBFrames 5 [ upscaleNN 2 (usedSwatch idx) | idx <- globalFrames ])

  -- QUALITY HARDENED across ENGINEERED VARIANCE: sweep 64 distinct look-residuals (= 64
  -- different users/apps). Each yields a DIFFERENT global palette (variance, allowed), yet
  -- the quality contract — bounded leaf displacement AND σ-equivariance — holds for EVERY
  -- one. (These laws are ∀-residual by construction; the gate exhibits it over the sample.)
  let looks     = [ randomResidual (seed * 1000 + fromIntegral i) floor' | i <- [0 .. scaleT - 1] ]
      envFrames = [ upscaleNN 2 (swatchRGB 16 18 (reconstruct (applyLookCore lookCoreScale floor' r)))
                  | r <- looks ]
  writeGif (out </> "proof_envelope.gif") (gifFromRGBFrames 6 envFrames)

  -- VARIANCE (engineered & allowed): two valid dither splits side by side. NOT a contest —
  -- both are legitimate settings; the hardened part is the temporal mean recovering the tone.
  let pHalf  = 0.5
      pPhi    = 2 - phi                              -- 0.381966… (the φ split)
      flick p = [ flickerPatch p t | t <- [0 .. scaleT - 1] ]
  writeGif (out </> "proof_flicker.gif")
    (gifFromRGBFrames 4 [ hcatRGB 8 gap (upscaleNN 3 a) (upscaleNN 3 b)
                        | (a, b) <- zip (flick pHalf) (flick pPhi) ])

  -- DECISION: coverage — the global palette's OKLab-gamut occupancy.
  let cov = gamutCoverageFraction [fromJust (mkPalette @256 global)]
  writeGif (out </> "proof_coverage.gif")
    (gifFromRGBFrames 60 [ upscaleNN 2 (swatchRGB 16 18 global) ])

  -- No HTML: the GIF is the medium. Verdicts went to stdout above (the report); the GIFs
  -- are the artifacts — view them directly.
  putStrLn ""
  putStrLn (printf "coverage %.1f%%  ·  dither variance: p=0.5 %.2f, φ-split %.2f"
              (cov * 100) (binomialVariance scaleT pHalf) (binomialVariance scaleT pPhi))
  putStrLn ("rendered the GIFs in " ++ out
            ++ " — view with Quick Look (select all, press space), or `open " ++ out ++ "`")

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------

-- | Split a @T·H·W@ index tensor into @T@ row-major frames of @H·W@ indices.
sliceFrames :: IndexTensor t h w k -> [[Int]]
sliceFrames (IndexTensor v) =
  let per = scaleH * scaleW
  in [ U.toList (U.slice (t * per) per v) | t <- [0 .. scaleT - 1] ]

-- | A 64×64 two-colour dither patch at split @p@, frame @t@: each pixel shows the partner
-- iff @realize p threshold@, the threshold sweeping via the golden ratio over time. The
-- p=0.5 patch flickers maximally; the φ-split is calmer (lower binomial variance).
flickerPatch :: Double -> Int -> Image PixelRGB8
flickerPatch p t = frameToRGB [anchor, partner] scaleW scaleH
  [ let ph = frac (fromIntegral (x * 7 + y * 13) * phi)
        th = frac (ph + fromIntegral t * phi)
    in if realize p th then 1 else 0
  | y <- [0 .. scaleH - 1], x <- [0 .. scaleW - 1] ]
  where anchor  = OKLab 0.20 0 0
        partner = OKLab 0.85 0 0

frac :: Double -> Double
frac x = x - fromIntegral (floor x :: Int)

argStr :: String -> String -> [String] -> String
argStr flag def args = case dropWhile (/= flag) args of
  (_ : v : _) -> v
  _           -> def
