{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE OverloadedStrings #-}
{- |
@spec-gen@ — generate FULL 64³ GIFs that mimic the SixFour app's output, with
__calculated entropy and LAB statistics__, for look-NN design and testing.

Each file is a 64×64, 64-frame GIF89a: one 256-colour Local Color Table per
frame, no transparency, every frame surjective onto all 256 colours
(a 'CompleteVoxelVolume'), bytes written by a faithful port of the app's
@GIFEncoder.swift@ ("SixFour.Gen.GifWire").

Three modes:

  * @--battery@ (default) — the 6 structural fixtures (round-trip checked).
  * @--sweep@ — a seeded corpus spanning the §8 descriptor space
    ("SixFour.Gen.Sweep"); each GIF is realized from a statistically-controlled
    'CyclicStack', measured ("SixFour.Gen.Stats"), and labelled into
    @manifest.json@.
  * @--synth@ — one GIF from explicit knob flags
    (@--clusters --spread --drift --gamut --skew --popdrift@).

Generate-to-test: every GIF is decoded back ("SixFour.Gen.GifDecode"). For the
stat modes the check is a __lossless entropy round-trip__ — decoded indices are
byte-exact, so each frame's pixel histogram (hence its Shannon palette entropy
@H(w_t)@) is provably preserved — plus the 'CompleteVoxelVolume' brand and the
embedded comment. A failure exits non-zero.

Usage: @cabal run spec-gen -- [--battery|--sweep|--synth] [--out DIR] [--seed N]@
-}
module Main (main) where

import           Control.Monad        (forM)
import           System.IO            (hSetBuffering, stdout, BufferMode (LineBuffering))
import           System.Environment   (getArgs)
import           System.Directory     (createDirectoryIfMissing)
import           System.FilePath      ((</>))
import           System.Exit          (exitFailure)
import           Text.Printf          (printf)
import           Data.Maybe           (catMaybes)
import           Data.Word            (Word64)
import qualified Data.Text            as T
import qualified Data.Text.IO         as TIO
import qualified Data.ByteString.Lazy as BL
import qualified Data.Vector          as V
import qualified Data.Vector.Unboxed  as U

import SixFour.Spec.Shape   (T, H, W, K, tVal, hVal, wVal, kVal)
import SixFour.Spec.Palette (Palette, paletteToList)
import SixFour.Spec.Cyclic  ( CyclicStack (..), Weights, SinkhornParams
                            , sharedSinkhornParams, paletteEntropy )
import SixFour.Spec.Indices ( IndexTensor (..), withCompleteVoxelVolume
                            , mkIndexTensor, mkCompleteVoxelVolume )

import SixFour.Gen.GifWire  (encodeVolume, oklabToRGB8, defaultFps)
import SixFour.Gen.GifDecode
import SixFour.Gen.Battery  (Case (..), battery)
import SixFour.Gen.Synth    (SynthParams (..), defaultSynthParams, synthStack)
import SixFour.Gen.Realize  (Realized (..), realize)
import SixFour.Gen.Stats    (CoreStats (..), measure, measureFast, reportJSON, summaryComment)
import SixFour.Gen.Sweep    (SweepCase (..), sweep)

data Mode = Battery | Sweep | Synth deriving (Eq)

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  args <- getArgs
  let mode | "--sweep" `elem` args = Sweep
           | "--synth" `elem` args = Synth
           | otherwise             = Battery
      seed = read (argStr "--seed" "1" args) :: Word64
      out  = argStr "--out" (defaultOut mode) args
      fast = "--fast" `elem` args
  createDirectoryIfMissing True out
  printf "spec-gen → %s  (mode %s, seed %d%s)\n" out (show mode) seed
         (if fast then ", fast: holonomy omitted" else "" :: String)
  printf "shape: T·H·W·K = %d·%d·%d·%d  (per-frame surjective, ≥2 px/slot, no transparency)\n\n"
         tVal hVal wVal kVal
  case mode of
    Battery -> runBattery out seed
    Sweep   -> runStats fast out (sweep seed)
    Synth   -> runStats fast out [synthCaseFromArgs seed args]

instance Show Mode where
  show Battery = "battery"; show Sweep = "sweep"; show Synth = "synth"

defaultOut :: Mode -> String
defaultOut Battery = "/tmp/sixfour-gifs-full"
defaultOut _       = "/tmp/sixfour-stats"

-- ===========================================================================
-- Stat modes (sweep / synth): synth → realize → encode → decode → label
-- ===========================================================================

runStats :: Bool -> FilePath -> [SweepCase] -> IO ()
runStats fast out cases = do
  results <- forM cases (processStat fast out sharedSinkhornParams)
  let oks     = map fst results
      records = catMaybes (map snd results)
  TIO.writeFile (out </> "manifest.json") (manifest records)
  printf "\nwrote %d/%d labelled GIFs + manifest.json\n" (length records) (length cases)
  if and oks
    then putStrLn "all GIFs round-trip cleanly (H(w) entropy exactly preserved)."
    else putStrLn "FAILURES above." >> exitFailure

-- | Realize one controlled stack, write+verify its GIF, return (pass, record).
-- The record 'Text' is forced to normal form before returning so each case's
-- working set (stack, matrices) is GC'd rather than retained as a thunk.
processStat :: Bool -> FilePath -> SinkhornParams -> SweepCase -> IO (Bool, Maybe T.Text)
processStat fast out params (SweepCase name stack mparams) =
  case realize @T @H @W @K stack of
    Nothing -> printf "  [FAIL] %-18s realize failed\n" name >> pure (False, Nothing)
    Just rz -> do
      let srcStack = rzStack rz                         -- weights = integer counts
          core     = (if fast then measureFast else measure) params srcStack
          comment  = summaryComment name core
          palettes = map fst (V.toList (unStack srcStack)) :: [Palette K]
          path     = out </> (name ++ ".gif")
      case encodeVolume defaultFps (Just comment) (rzVolume rz) palettes of
        Left e -> printf "  [FAIL] %-18s encode: %s\n" name e >> pure (False, Nothing)
        Right bytes -> do
          BL.writeFile path bytes
          let (ok, msg) = checkStat rz core comment bytes
              record    = reportJSON name mparams core
          printf "  [%s] %-18s %6d B  H(w)~%.2f H_g~%.2f cov=%.2f holo=%.3f trans=%.2f  %s\n"
                 (if ok then "PASS" else "FAIL" :: String) name (BL.length bytes)
                 (meanList (csPerFrameHW core)) (meanList (csPerFrameHG core))
                 (csCoverage core) (atOr 11 (csDescriptor core)) (atOr 4 (csDescriptor core)) msg
          T.length record `seq` pure (ok, Just record)   -- force, then drop core/stack

-- | Lossless entropy round-trip: indices byte-exact ⇒ histograms identical ⇒
-- the H(w_t) trajectory is preserved; plus brand + comment.
checkStat :: Realized T H W K -> CoreStats -> T.Text -> BL.ByteString -> (Bool, String)
checkStat rz core comment bytes =
  case decodeGif bytes of
    Left e   -> (False, "decode: " ++ e)
    Right dg
      | length (dgFrames dg) /= tVal              -> (False, "frame count")
      | dgWidth dg /= wVal || dgHeight dg /= hVal -> (False, "canvas")
      | decodedIndices dg /= realizedIdx          -> (False, "indices differ")
      | not (brandHolds dg)                       -> (False, "not a complete voxel volume")
      | dgComment dg /= Just comment              -> (False, "comment lost")
      | hwDecoded dg /= csPerFrameHW core         -> (False, "H(w) trajectory changed")
      | otherwise                                 -> (True, "ok; H(w) exact + complete")
  where
    realizedIdx = withCompleteVoxelVolume (rzVolume rz) (\(IndexTensor v) -> U.toList v)
    brandHolds dg = case mkIndexTensor @T @H @W @K (decodedIndices dg) of
                      Nothing -> False
                      Just it -> maybe False (const True) (mkCompleteVoxelVolume it)
    hwDecoded dg = [ paletteEntropy (histWeights (dfIndices f)) | f <- dgFrames dg ]

-- | Per-frame index histogram → 'Weights' over the K slots.
histWeights :: [Int] -> Weights
histWeights idx = V.accum (+) (V.replicate kVal 0) [ (i, 1) | i <- idx ]

-- | Build a single-case sweep from @--synth@ knob flags.
synthCaseFromArgs :: Word64 -> [String] -> SweepCase
synthCaseFromArgs seed args =
  let p = defaultSynthParams
        { seed      = seed
        , nClusters = round (argDbl "--clusters" (fromIntegral (nClusters defaultSynthParams)) args)
        , spread    = argDbl "--spread"   (spread   defaultSynthParams) args
        , drift     = argDbl "--drift"    (drift    defaultSynthParams) args
        , gamut     = argDbl "--gamut"    (gamut    defaultSynthParams) args
        , concSkew  = argDbl "--skew"     (concSkew defaultSynthParams) args
        , popDrift  = argDbl "--popdrift" (popDrift defaultSynthParams) args
        }
  in SweepCase "synth" (synthStack @T @K p) (Just p)

manifest :: [T.Text] -> T.Text
manifest rs = "[\n" <> T.intercalate ",\n" rs <> "\n]\n"

-- ===========================================================================
-- Battery mode (unchanged: structural round-trip, no stats/manifest)
-- ===========================================================================

runBattery :: FilePath -> Word64 -> IO ()
runBattery out seed = do
  results <- mapM (emitCase out seed) (battery seed)
  putStrLn ""
  if and results
    then printf "all %d GIFs are complete 64^3 voxel volumes and round-trip cleanly.\n"
                (length results)
    else putStrLn "FAILURES above." >> exitFailure

emitCase :: FilePath -> Word64 -> Case -> IO Bool
emitCase out seed c = do
  let path    = out </> (caseName c ++ ".gif")
      comment = T.pack (printf "SixFour spec-gen | %s | %s | %dx%dx%d K=%d | seed %d"
                          (caseName c) (caseNote c) tVal hVal wVal kVal seed)
  case encodeVolume defaultFps (Just comment) (caseVolume c) (casePalettes c) of
    Left err -> printf "  [FAIL] %-18s encode error: %s\n" (caseName c) err >> pure False
    Right bytes -> do
      BL.writeFile path bytes
      let verdict = verifyBattery c comment bytes
      printf "  [%s] %-18s %6d bytes  %s\n"
             (if vrOK verdict then "PASS" else "FAIL" :: String)
             (caseName c) (BL.length bytes) (vrMsg verdict)
      pure (vrOK verdict)

data Verify = Verify { vrOK :: Bool, vrMsg :: String }

verifyBattery :: Case -> T.Text -> BL.ByteString -> Verify
verifyBattery c comment bytes =
  case decodeGif bytes of
    Left e   -> Verify False ("decode failed: " ++ e)
    Right dg -> check dg
  where
    original     = withCompleteVoxelVolume (caseVolume c) (\(IndexTensor v) -> U.toList v)
    expectedPals = [ map oklabToRGB8 (paletteToList p) | p <- casePalettes c ]
    check dg
      | dgWidth dg /= wVal || dgHeight dg /= hVal = fail' "wrong canvas"
      | length (dgFrames dg) /= tVal              = fail' "wrong frame count"
      | decodedIndices dg /= original             = fail' "indices differ after round-trip"
      | map dfPalette (dgFrames dg) /= expectedPals = fail' "palette RGB differ"
      | not brandHolds                            = fail' "not a complete voxel volume"
      | dgComment dg /= Just comment              = fail' "comment did not survive"
      | otherwise = Verify True (printf "round-trip ok; complete (T=%d, K=%d)" tVal kVal)
      where brandHolds = case mkIndexTensor @T @H @W @K (decodedIndices dg) of
                           Nothing -> False
                           Just it -> maybe False (const True) (mkCompleteVoxelVolume it)
    fail' = Verify False

-- ===========================================================================
-- arg helpers
-- ===========================================================================

argStr :: String -> String -> [String] -> String
argStr flag def as = case dropWhile (/= flag) as of
  (_ : v : _) -> v
  _           -> def

argDbl :: String -> Double -> [String] -> Double
argDbl flag def as = case dropWhile (/= flag) as of
  (_ : v : _) -> maybe def id (readMaybe v)
  _           -> def
  where readMaybe s = case reads s of [(x, "")] -> Just x; _ -> Nothing

meanList :: [Double] -> Double
meanList [] = 0
meanList xs = sum xs / fromIntegral (length xs)

atOr :: Int -> [Double] -> Double
atOr i xs = if i < length xs then xs !! i else 0
