{- |
spec-codegen driver. Writes the four target files:

  * @SixFour/Generated/StageContract.swift@
  * @SixFour/Generated/NetContract.swift@
  * @trainer/generated/stages.py@
  * @trainer/generated/net_shape.py@

Defaults to writing relative to the cabal CWD (@~/SixFour/spec@), so
the Swift output lands at @../SixFour/Generated@ and the Python
output at @../trainer/generated@. Override with @--swift-out DIR@ or
@--mlx-out DIR@.
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
  ( emitStageContract, emitNetContract, emitHybridContract )
import SixFour.Codegen.MLX   (emitStagesPy,      emitNetShapePy)
import SixFour.Spec.Hybrid.STBN3D (Mask3D(..), generateSTBN3D)

main :: IO ()
main = do
  args <- getArgs
  let opts          = parseArgs args
      swiftOutDir   = fromMaybe "../SixFour/Generated"  (lookup "--swift-out" opts)
      mlxOutDir     = fromMaybe "../trainer/generated"  (lookup "--mlx-out"   opts)
      resourceOutDir = fromMaybe "../SixFour/Resources" (lookup "--res-out"   opts)

  writeUtf8 (swiftOutDir   </> "StageContract.swift")  emitStageContract
  writeUtf8 (swiftOutDir   </> "NetContract.swift")    emitNetContract
  writeUtf8 (swiftOutDir   </> "HybridContract.swift") emitHybridContract
  writeUtf8 (mlxOutDir     </> "stages.py")            emitStagesPy
  writeUtf8 (mlxOutDir     </> "net_shape.py")         emitNetShapePy

  -- Drop a Python __init__.py so `from generated import …` works.
  writeUtf8 (mlxOutDir </> "__init__.py") T.empty

  -- 8³ scalar STBN3D mask, written as a raw binary the Swift loader
  -- tiles 8×8×8 → 64×64×64 at runtime. Bit-exact ground truth:
  -- SixFour.Spec.Hybrid.STBN3D.generateSTBN3D @8 @8 @8. The tile is
  -- toroidally distanced, so tiling is mathematically clean (no edge
  -- discontinuities); periodicity at the 8-voxel boundary is the
  -- only spectral loss vs a true 64³ mask. Upgrading to a true 64³
  -- requires an FFT-based void filter (O(n log n) per swap) and is
  -- tracked as TR-1 in the plan.
  let Mask3D maskBytes = generateSTBN3D @8 @8 @8
  writeBinary (resourceOutDir </> "stbn3d-8.bin") maskBytes

  putStrLn "spec-codegen: wrote 6 files + 1 resource."
  putStrLn $ "  swift   : " <> swiftOutDir
  putStrLn $ "  mlx     : " <> mlxOutDir
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
