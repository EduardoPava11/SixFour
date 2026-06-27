{- |
spec-codegen driver. Writes 28 Swift/golden files + the Python trainer contracts + 1 binary resource:

  * @SixFour/Generated/*.swift@ — the Swift contracts and byte-exact goldens the hand-written
    Swift/Metal port is verified against (StageContract, NetContract, STBN3DContract,
    SignificanceContract, CollapseGolden, PairTreeGolden, PaletteValueGolden, MaskedBandGolden, …).
  * @SixFour/Resources/stbn3d-8.bin@ — 8³ STBN3D scalar mask
  * @trainer/generated/stages.py@ — NumPy shape/significance constants the trainer imports
  * @trainer/generated/{jepa_data,jepa_head,temporal_data}_golden.json@ — the H-JEPA data-engine,
    head-trajectory, and inter-frame @(t,t+1)@ goldens the @trainer/mlx/@ loaders reproduce byte-exact
  * @studio/look-nn-baseline/src/generated/contract.rs@ — Rust @burn@ contract + golden vectors

Defaults to writing relative to the cabal CWD (@~/SixFour/spec@), so
the Swift output lands at @../SixFour/Generated@ and the Python
output at @../trainer/generated@. Override with @--swift-out DIR@,
@--mlx-out DIR@ (the @trainer/generated@ Python dir), @--res-out DIR@,
or @--burn-out DIR@.
-}
module Main (main) where

import qualified Data.ByteString  as BS
import qualified Data.Text        as T
import qualified Data.Text.IO     as TIO
import qualified Data.Vector.Unboxed as U
import           Data.Text        (Text)
import           Data.Word        (Word8)
import           System.Directory   (createDirectoryIfMissing)
import           System.FilePath    ((</>), takeDirectory)
import           System.Environment (getArgs)
import           Data.Maybe (fromMaybe)

import SixFour.Codegen.Swift
  ( emitStageContract, emitSTBN3DContract, emitSignificanceContract
  , emitGlobalVolumeContract, emitLatticeContract, emitBoundaryContract
  , emitFieldTuningContract, emitFieldTuningMetalHeader, emitInfluenceFieldGolden
  , emitCellShapesContract
  , emitSevenSegContract, emitPlaybackClockContract, emitCellContract
  , emitDisplayContract, emitABSurfaceContract, emitFrontProjectionGolden, emitVoxelFitContract, emitOrderContract, emitExportContract
  , emitGridLayoutContract, emitMoveContract, emitCellMechanicsContract, emitOwnershipContract )
import SixFour.Codegen.Shapes (emitStagesPy)
import SixFour.Codegen.JepaData (emitJepaDataGolden)
import SixFour.Codegen.JepaHead (emitJepaHeadGolden)
import SixFour.Codegen.LearnabilityTheorem (emitLearnabilityGolden)
import SixFour.Codegen.TemporalData (emitTemporalDataGolden)
import SixFour.Codegen.Collapse (emitCollapseGolden)
import SixFour.Codegen.RGBT4D (emitRGBT4DGolden)
import SixFour.Codegen.VoxelReduce (emitVoxelReduceGolden)
import SixFour.Codegen.GenomeCarrier (emitGenomeCarrierGolden)
import SixFour.Codegen.MaskedBand (emitMaskedBandGolden)
import SixFour.Codegen.PairTree (emitPairTreeGolden)
import SixFour.Codegen.QuartetDelta (emitQuartetDeltaGolden)
import SixFour.Codegen.GenomeFixed (emitGenomeFixedGolden)
import SixFour.Codegen.GridAxis (emitGridAxisGolden)
import SixFour.Codegen.ModelIO (emitModelIOContract)
import SixFour.Spec.STBN3D    (Mask3D(..), generateSTBN3D)

main :: IO ()
main = do
  args <- getArgs
  let opts          = parseArgs args
      swiftOutDir   = fromMaybe "../SixFour/Generated"  (lookup "--swift-out" opts)
      mlxOutDir     = fromMaybe "../trainer/generated"  (lookup "--mlx-out"   opts)
      resourceOutDir = fromMaybe "../SixFour/Resources" (lookup "--res-out"   opts)
      burnOutDir    = fromMaybe "../studio/look-nn-baseline/src/generated" (lookup "--burn-out" opts)

  writeUtf8 (swiftOutDir   </> "StageContract.swift")  emitStageContract
  writeUtf8 (swiftOutDir   </> "STBN3DContract.swift") emitSTBN3DContract
  writeUtf8 (swiftOutDir   </> "SignificanceContract.swift") emitSignificanceContract
  writeUtf8 (swiftOutDir   </> "GlobalVolumeContract.swift") emitGlobalVolumeContract
  writeUtf8 (swiftOutDir   </> "LatticeContract.swift")      emitLatticeContract
  writeUtf8 (swiftOutDir   </> "BoundaryContract.swift")     emitBoundaryContract
  writeUtf8 (swiftOutDir   </> "FieldTuningContract.swift")  emitFieldTuningContract
  writeUtf8 (swiftOutDir   </> "FieldTuning.metal.h")        emitFieldTuningMetalHeader
  writeUtf8 (swiftOutDir   </> "InfluenceFieldGolden.swift") emitInfluenceFieldGolden
  writeUtf8 (swiftOutDir   </> "CellShapesContract.swift")   emitCellShapesContract
  writeUtf8 (swiftOutDir   </> "SevenSegContract.swift")     emitSevenSegContract
  writeUtf8 (swiftOutDir   </> "PlaybackClockContract.swift") emitPlaybackClockContract
  writeUtf8 (swiftOutDir   </> "CellContract.swift")          emitCellContract
  writeUtf8 (swiftOutDir   </> "DisplayContract.swift")       emitDisplayContract
  writeUtf8 (swiftOutDir   </> "ABSurfaceContract.swift")    emitABSurfaceContract
  writeUtf8 (swiftOutDir   </> "FrontProjectionGolden.swift") emitFrontProjectionGolden
  writeUtf8 (swiftOutDir   </> "VoxelFitContract.swift")     emitVoxelFitContract
  writeUtf8 (swiftOutDir   </> "OrderContract.swift")         emitOrderContract
  writeUtf8 (swiftOutDir   </> "ExportContract.swift")        emitExportContract
  writeUtf8 (swiftOutDir   </> "GridLayoutContract.swift")    emitGridLayoutContract
  writeUtf8 (swiftOutDir   </> "MoveContract.swift")          emitMoveContract
  writeUtf8 (swiftOutDir   </> "CellMechanicsContract.swift") emitCellMechanicsContract
  writeUtf8 (swiftOutDir   </> "OwnershipContract.swift")     emitOwnershipContract
  writeUtf8 (swiftOutDir   </> "CollapseGolden.swift")       emitCollapseGolden
  writeUtf8 (swiftOutDir   </> "RGBT4DGolden.swift")         emitRGBT4DGolden
  writeUtf8 (swiftOutDir   </> "VoxelReduceGolden.swift")    emitVoxelReduceGolden
  writeUtf8 (swiftOutDir   </> "GenomeCarrierGolden.swift")  emitGenomeCarrierGolden
  writeUtf8 (swiftOutDir   </> "PairTreeGolden.swift")       emitPairTreeGolden
  writeUtf8 (swiftOutDir   </> "MaskedBandGolden.swift")     emitMaskedBandGolden
  writeUtf8 (swiftOutDir   </> "QuartetDeltaGolden.swift")   emitQuartetDeltaGolden
  writeUtf8 (swiftOutDir   </> "GenomeFixedGolden.swift")    emitGenomeFixedGolden
  writeUtf8 (swiftOutDir   </> "GridAxisGolden.swift")        emitGridAxisGolden
  writeUtf8 (swiftOutDir   </> "SixFourModelIO.swift")        emitModelIOContract
  writeUtf8 (mlxOutDir     </> "stages.py")            emitStagesPy
  writeUtf8 (mlxOutDir     </> "jepa_data_golden.json") emitJepaDataGolden
  writeUtf8 (mlxOutDir     </> "jepa_head_golden.json") emitJepaHeadGolden
  writeUtf8 (mlxOutDir     </> "learnability_golden.json") emitLearnabilityGolden
  writeUtf8 (mlxOutDir     </> "temporal_data_golden.json") emitTemporalDataGolden

  -- Drop a Python __init__.py so `from generated import …` works.
  writeUtf8 (mlxOutDir </> "__init__.py") T.empty

  -- 8³ scalar STBN3D mask, written as a raw binary the Swift loader
  -- tiles 8×8×8 → 64×64×64 at runtime. Bit-exact ground truth:
  -- SixFour.Spec.STBN3D.generateSTBN3D @8 @8 @8. The tile is
  -- toroidally distanced, so tiling is mathematically clean (no edge
  -- discontinuities); periodicity at the 8-voxel boundary is the
  -- only spectral loss vs a true 64³ mask. Upgrading to a true 64³
  -- requires an FFT-based void filter (O(n log n) per swap) and is
  -- tracked as TR-1 in the plan.
  let Mask3D maskBytes = generateSTBN3D @8 @8 @8
  writeBinary (resourceOutDir </> "stbn3d-8.bin") maskBytes

  putStrLn "spec-codegen: wrote 29 files + 1 resource."
  putStrLn $ "  swift   : " <> swiftOutDir
  putStrLn $ "  mlx     : " <> mlxOutDir
  putStrLn $ "  burn    : " <> burnOutDir
  putStrLn $ "  resource: " <> resourceOutDir
  putStrLn $ "  stbn3d-8.bin size: " <> show (U.length maskBytes) <> " bytes"

writeUtf8 :: FilePath -> Text -> IO ()
writeUtf8 path content = do
  createDirectoryIfMissing True (takeDirectory path)
  TIO.writeFile path content

writeBinary :: FilePath -> U.Vector Word8 -> IO ()
writeBinary path bytes = do
  createDirectoryIfMissing True (takeDirectory path)
  BS.writeFile path (BS.pack (U.toList bytes))

-- | Trivial @--key value@ parser. Accepts both @--key value@ and @--key=value@.
parseArgs :: [String] -> [(String, String)]
parseArgs [] = []
parseArgs (kv:rest)
  | take 2 kv == "--"
  , '=' `elem` kv =
      let (k, v) = break (== '=') kv
      in (k, drop 1 v) : parseArgs rest
parseArgs (k:v:rest)
  | take 2 k == "--" = (k, v) : parseArgs rest
parseArgs (_:rest) = parseArgs rest
