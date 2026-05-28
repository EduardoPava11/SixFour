{-# LANGUAGE ScopedTypeVariables #-}
{- |
Module      : SixFour.Gen.GifWire
Description : Byte-faithful Haskell port of the app's @GIFEncoder.swift@.

This is the on-the-wire GIF89a writer that produces files structurally
indistinguishable from a real SixFour capture:

  * fixed 64×64, 64 frames (any @(t,h,w)@ at the type level, but @K@ must be 256);
  * __no__ Global Color Table — every frame carries its own 256-entry
    Local Color Table (@0x87@ image-descriptor packed byte);
  * NETSCAPE2.0 infinite-loop block;
  * disposal method 1 (do not dispose), transparency flag __off__ — every
    frame fully overwrites the canvas, so there is no transparent index;
  * LZW with @minCodeSize = 8@ (raw 8-bit indices), variable code size,
    clear/reset on dictionary overflow — the same state machine, byte for
    byte, as @GIFEncoder.lzwEncode@;
  * an optional GIF89a Comment Extension (@0x21 0xFE@) for metadata.

The encoder consumes a 'CompleteVoxelVolume' — the type itself is the proof
that there are exactly @T@ frames, each @H*W@ indices long, each frame
surjective onto all 256 colours. "No missing pixel colours" is therefore a
precondition the caller cannot dodge: an incomplete volume is unconstructible.

This module depends only on @bytestring@/@vector@/@containers@ + the spec
library — never JuicyPixels. It is the inverse of "SixFour.Gen.GifDecode".

Cross-reference: @SixFour/Encoder/GIFEncoder.swift@ (the source of truth).
-}
module SixFour.Gen.GifWire
  ( -- * Encoding
    encodeVolume
  , defaultFps
  , delayCentiseconds
    -- * Palette → bytes (exposed for the decoder's round-trip test)
  , oklabToRGB8
  ) where

import           Data.Word               (Word8, Word32)
import           Data.Bits               (shiftL, shiftR, (.|.), (.&.))
import           Data.Proxy              (Proxy (..))
import           GHC.TypeLits            (KnownNat, natVal)
import qualified Data.Text               as T
import qualified Data.Text.Encoding      as TE
import qualified Data.ByteString         as BS
import qualified Data.ByteString.Lazy    as BL
import           Data.ByteString.Builder
import qualified Data.Map.Strict         as M
import qualified Data.Vector.Unboxed     as U

import SixFour.Spec.Color   (OKLab, SRGB (..), okLabToSRGB)
import SixFour.Spec.Palette (Palette, paletteToList)
import SixFour.Spec.Indices ( CompleteVoxelVolume, IndexTensor (..)
                            , withCompleteVoxelVolume )

-- | The app captures at 20 fps.
defaultFps :: Int
defaultFps = 20

-- | GIF frame delay is in centiseconds; @GIFEncoder.init@ uses
-- @max(1, 100 / fps)@. At 20 fps that is 5 cs.
delayCentiseconds :: Int -> Int
delayCentiseconds fps = max 1 (100 `div` fps)

-- | Encode a complete voxel volume to GIF89a bytes, byte-faithfully matching
-- @GIFEncoder.encode(volume:perFramePalettes:to:comment:)@.
--
-- @palettes@ must have exactly @T@ entries (one Local Color Table per frame);
-- each 'Palette' already has 256 OKLab colours by its type. @comment@, if
-- present and non-empty, is embedded as a Comment Extension after the loop
-- block. Returns 'Left' only on the caller-side mismatches the Swift encoder
-- also rejects (palette count ≠ frame count, or @K ≠ 256@).
encodeVolume
  :: forall t h w k. (KnownNat t, KnownNat h, KnownNat w, KnownNat k)
  => Int                                  -- ^ fps (delay derived)
  -> Maybe T.Text                         -- ^ optional comment
  -> CompleteVoxelVolume t h w k
  -> [Palette k]
  -> Either String BL.ByteString
encodeVolume fps comment vol palettes =
  let nt = nat (Proxy :: Proxy t)
      nh = nat (Proxy :: Proxy h)
      nw = nat (Proxy :: Proxy w)
      nk = nat (Proxy :: Proxy k)
  in withCompleteVoxelVolume vol $ \(IndexTensor flat) ->
     if nk /= 256
       then Left ("GifWire supports only K=256 (the app shape); got " ++ show nk)
     else if length palettes /= nt
       then Left ( "mismatched frame/palette count: " ++ show nt
                   ++ " frames vs " ++ show (length palettes) ++ " palettes" )
     else
       let perFrame  = nh * nw
           frameIdx f = U.slice (f * perFrame) perFrame flat
           frames     = [ frameIdx f | f <- [0 .. nt - 1] ]
           delay      = delayCentiseconds fps
           body       = mconcat
             [ graphicsControl delay
               <> imageDescriptorWithLCT nw nh
               <> localColorTable pal
               <> lzwEncode 8 idx
             | (idx, pal) <- zip frames palettes ]
           doc =
                byteString (BS.pack [0x47,0x49,0x46,0x38,0x39,0x61]) -- "GIF89a"
             <> logicalScreenDescriptor nw nh
             <> netscapeLoop 0
             <> maybe mempty commentExtension
                  (comment >>= \c -> if T.null c then Nothing else Just c)
             <> body
             <> word8 0x3B                                          -- trailer
       in Right (toLazyByteString doc)
  where
    nat :: KnownNat n => Proxy n -> Int
    nat = fromIntegral . natVal

-- ---------------------------------------------------------------------------
-- Block builders (mirror GIFEncoder.swift's private helpers)
-- ---------------------------------------------------------------------------

-- | 16-bit little-endian, matching @GIFEncoder.u16@.
u16 :: Int -> Builder
u16 v = word8 (fromIntegral (v .&. 0xFF)) <> word8 (fromIntegral ((v `shiftR` 8) .&. 0xFF))

-- | Logical screen descriptor with the GCT flag off. Packed byte @0x70@:
-- bit7 GCT=0, bits4-6 colour-resolution=7, bit3 sort=0, bits0-2 ignored.
logicalScreenDescriptor :: Int -> Int -> Builder
logicalScreenDescriptor w h =
  u16 w <> u16 h <> word8 0x70 <> word8 0x00 <> word8 0x00

-- | NETSCAPE2.0 application extension; @count = 0@ ⇒ loop forever.
netscapeLoop :: Int -> Builder
netscapeLoop count =
  byteString (BS.pack
    [ 0x21, 0xFF, 0x0B
    , 0x4E,0x45,0x54,0x53,0x43,0x41,0x50,0x45        -- "NETSCAPE"
    , 0x32,0x2E,0x30                                  -- "2.0"
    , 0x03, 0x01
    , fromIntegral (count .&. 0xFF)
    , fromIntegral ((count `shiftR` 8) .&. 0xFF)
    , 0x00 ])

-- | Graphic Control Extension. Packed @0x04@: disposal=001 (do not dispose),
-- user-input=0, transparent=0 — no transparency, ever.
graphicsControl :: Int -> Builder
graphicsControl delay =
  byteString (BS.pack [0x21, 0xF9, 0x04, 0x04])
  <> u16 delay
  <> word8 0x00 <> word8 0x00

-- | Image descriptor with the LCT flag set. Packed @0x87@: LCT=1, interlace=0,
-- sort=0, size=7 (2^(7+1)=256 entries).
imageDescriptorWithLCT :: Int -> Int -> Builder
imageDescriptorWithLCT w h =
  word8 0x2C
  <> u16 0 <> u16 0                 -- left, top
  <> u16 w <> u16 h
  <> word8 0x87

-- | 768-byte Local Color Table: 256 × RGB, OKLab gamma-encoded to 8-bit sRGB.
-- A @Palette 256@ has exactly 256 entries by construction, so this is total.
localColorTable :: Palette k -> Builder
localColorTable pal =
  mconcat [ let (r,g,b) = oklabToRGB8 c in word8 r <> word8 g <> word8 b
          | c <- paletteToList pal ]

-- | GIF89a Comment Extension: @0x21 0xFE@, UTF-8 text in ≤255-byte sub-blocks,
-- @0x00@ terminator. Readable by @exiftool@ / @strings@.
commentExtension :: T.Text -> Builder
commentExtension t =
  word8 0x21 <> word8 0xFE <> subBlocks (TE.encodeUtf8 t) <> word8 0x00
  where
    subBlocks bs
      | BS.null bs = mempty
      | otherwise  =
          let (chunk, rest) = BS.splitAt 255 bs
          in word8 (fromIntegral (BS.length chunk)) <> byteString chunk <> subBlocks rest

-- | OKLab → 8-bit sRGB triple, matching the Swift quantiser
-- (@round(x*255)@ clamped to @[0,255]@).
oklabToRGB8 :: OKLab -> (Word8, Word8, Word8)
oklabToRGB8 lab =
  let SRGB r g b = okLabToSRGB lab in (q r, q g, q b)
  where q x = fromIntegral (max 0 (min 255 (round (x * 255) :: Int))) :: Word8

-- ---------------------------------------------------------------------------
-- LZW — a line-by-line port of GIFEncoder.lzwEncode
-- ---------------------------------------------------------------------------

-- | Mutable-feel LZW state, threaded purely.
data LZW = LZW
  { dict     :: !(M.Map BS.ByteString Int)  -- ^ string → code
  , codeSize :: !Int                        -- ^ current code width in bits
  , nextCode :: !Int                        -- ^ next code to assign
  , buf      :: !Word32                      -- ^ bit accumulator (LSB-first)
  , bits     :: !Int                        -- ^ valid bits in 'buf'
  , subRev   :: ![Word8]                    -- ^ current ≤255-byte sub-block, reversed
  , subLen   :: !Int                        -- ^ length of 'subRev'
  , done     :: !Builder                    -- ^ flushed sub-blocks
  }

-- | LZW-compress one frame's indices, returning the GIF image-data stream:
-- the @minCodeSize@ byte, then length-prefixed sub-blocks, then a @0x00@
-- block terminator.
lzwEncode :: Int -> U.Vector Int -> Builder
lzwEncode minCodeSize pixels =
  word8 (fromIntegral minCodeSize) <> stream
  where
    clearCode = 1 `shiftL` minCodeSize
    endCode   = clearCode + 1
    maxCode   = 4095

    initDict :: M.Map BS.ByteString Int
    initDict = M.fromList [ (BS.singleton (fromIntegral i), i) | i <- [0 .. clearCode - 1] ]

    fresh :: LZW -> LZW
    fresh s = s { dict = initDict, nextCode = endCode + 1, codeSize = minCodeSize + 1 }

    -- push one byte into the current sub-block, flushing at 255
    pushByte :: Word8 -> LZW -> LZW
    pushByte b s =
      let s' = s { subRev = b : subRev s, subLen = subLen s + 1 }
      in if subLen s' == 255 then flush s' else s'

    flush :: LZW -> LZW
    flush s
      | subLen s == 0 = s
      | otherwise =
          s { done   = done s
                     <> word8 (fromIntegral (subLen s))
                     <> byteString (BS.pack (reverse (subRev s)))
            , subRev = [], subLen = 0 }

    -- emit a code at the current code size, LSB-first
    outputCode :: Int -> LZW -> LZW
    outputCode code s0 =
      let s1 = s0 { buf  = buf s0 .|. (fromIntegral code `shiftL` bits s0)
                  , bits = bits s0 + codeSize s0 }
      in drain s1
      where
        drain s
          | bits s >= 8 =
              let byte = fromIntegral (buf s .&. 0xFF) :: Word8
              in drain (pushByte byte (s { buf = buf s `shiftR` 8, bits = bits s - 8 }))
          | otherwise = s

    -- the main scan: returns the final state after consuming all pixels
    run :: LZW
    run =
      let s0      = outputCode clearCode (fresh emptyState)
          (sN, cur) = U.foldl' step (s0, BS.empty) pixels
          -- flush the trailing string + end code
          sFlush  = if BS.null cur then sN
                                   else outputCode (lookupCode cur sN) sN
          sEnd    = outputCode endCode sFlush
          sBits   = if bits sEnd > 0
                      then sEnd { subRev = fromIntegral (buf sEnd .&. 0xFF) : subRev sEnd
                                , subLen = subLen sEnd + 1 }
                      else sEnd
      in flush sBits

    emptyState = LZW M.empty (minCodeSize + 1) (endCode + 1) 0 0 [] 0 mempty

    lookupCode :: BS.ByteString -> LZW -> Int
    lookupCode key s = M.findWithDefault clearCode key (dict s)

    -- one pixel: extend current string, emit + grow dict on a miss
    step :: (LZW, BS.ByteString) -> Int -> (LZW, BS.ByteString)
    step (s, cur) px =
      let pb   = fromIntegral px :: Word8
          next = cur `BS.snoc` pb
      in if M.member next (dict s)
           then (s, next)
           else
             let s1 = outputCode (lookupCode cur s) s
                 s2 = if nextCode s1 <= maxCode
                        then let nc = nextCode s1
                                 d' = M.insert next nc (dict s1)
                                 s' = s1 { dict = d', nextCode = nc + 1 }
                             in if nextCode s' > (1 `shiftL` codeSize s') && codeSize s' < 12
                                  then s' { codeSize = codeSize s' + 1 }
                                  else s'
                        else fresh (outputCode clearCode s1)
             in (s2, BS.singleton pb)

    stream = done run <> word8 0x00
