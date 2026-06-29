{- |
Module      : V2IndexLzw
Description : EXPLORATION - NOT WIRED. The index map + LZW reading: GIF89a's discrete
              CONTENT head (index map (x,y)->Slot) plus the COMPUTE over it (LZW), read as
              the "latent thinking" layer. Companion to GifSki.hs (the value/content SKI
              reading): there render = palette . index was the B combinator; here we make
              the index/LZW side concrete and prove the one HARD theorem it rests on.

  THREAD B of the SixFour/OneSix two-lens exploration. This module is BASE-ONLY (imports
  only GHC-boot: base + Data.List) and is NOT in any cabal file, Map, or gate. Check with:
  runghc V2IndexLzw.hs

  WHAT IS REAL HERE:

    * A minimal, self-contained, CORRECT LZW over a 4-slot alphabet, with an explicit
      growing dictionary seeded from the singletons. The hard part (and the real theorem)
      is the KwKwK edge case: the encoder can emit a code in the very step it defines that
      code, so the decoder must reconstruct an entry it has not yet been told. A naive
      decoder that only looks codes up FAILS on exactly this case (lawNaiveDecoderFails),
      while the proper one round-trips (lawLzwRoundTrips). LZW is lossless: that is a real,
      non-trivial property and it is the spine of this file.

    * The dictionary genuinely behaves as a structure-capturing latent: a repetitive
      (low-entropy) stream compresses to FEWER codes than a high-entropy stream of the same
      length (lawDictionaryIsLatent), and the compression comes from emitting single codes
      that STAND FOR multi-symbol substrings seen earlier (lawDictRefIsSharing). The
      reuse-count is a real measured number.

  HONEST BOUNDARY (the project rejects forced jargon):

    * LZW "sharing" is DATA-level substring reuse: one code value stands in for a multi-
      symbol substring that occurred before. The S combinator is TERM-level argument
      DUPLICATION (S f g x -> f x (g x), the single x consumed twice). These RHYME (both
      are "use a thing more than once / name it once, reference it many times"), and that
      rhyme is why a shared dictionary entry feels like the S/contraction move from the
      expand/contract SKI reading. But it is a SUGGESTIVE analogy, NOT a theorem: no typed
      homomorphism from "LZW code stream" to "SKI term reduction" is exhibited here. So:
      the REUSE COUNT in lawDictRefIsSharing is REAL data; its "= the S/contraction move"
      gloss is DECORATIVE and is marked <> wherever it appears. The lossless round-trip and
      the entropy/dictionary-size relation are the genuine theorems.
-}
module V2IndexLzw where

import Data.List (tails, isPrefixOf, nub)

-- ===========================================================================
-- (1) Minimal correct LZW over a small slot alphabet
-- ===========================================================================
--
-- An INDEX MAP value is a Slot (a palette index). A frame's index map, flattened in
-- (x,y) raster order, is just a [Slot] stream. LZW is the COMPUTE over that stream: it
-- replaces repeated index substrings by single dictionary codes. We use a 4-slot alphabet
-- (slots 0..3) so the KwKwK edge and dictionary growth are exercised on tiny inputs.

type Slot = Int           -- ^ a palette index, the discrete CONTENT atom
type Code = Int           -- ^ an LZW output code (a dictionary reference)

-- | Size of the slot alphabet. Singleton codes occupy 0 .. alphabetSize-1; the first
--   assignable multi-symbol code is alphabetSize.
alphabetSize :: Int
alphabetSize = 4

-- | Encoder dictionary: substring -> code. Newest entries pushed on the front.
initEncDict :: [([Slot], Code)]
initEncDict = [ ([s], s) | s <- [0 .. alphabetSize - 1] ]

-- | Decoder dictionary: code -> substring. Newest entries pushed on the front.
initDecDict :: [(Code, [Slot])]
initDecDict = [ (s, [s]) | s <- [0 .. alphabetSize - 1] ]

-- | Encode an index stream to codes, AND return the substring each code stands for (in
--   lock-step). Standard greedy LZW: grow the current phrase @w@ while @w++[c]@ is known;
--   on a miss, emit the code for @w@, learn @w++[c]@ at the next code, restart at @[c]@.
encodeWith :: [Slot] -> ([Code], [[Slot]])
encodeWith []       = ([], [])
encodeWith (x : xs) = go initEncDict alphabetSize [x] xs
  where
    go dict _next w [] = ([codeOf dict w], [w])         -- flush the final phrase
    go dict next w (c : cs) =
      let wc = w ++ [c] in
      case lookup wc dict of
        Just _  -> go dict next wc cs                    -- phrase still known: extend it
        Nothing ->
          let (ks, ss) = go ((wc, next) : dict) (next + 1) [c] cs
          in (codeOf dict w : ks, w : ss)                -- emit w, learn wc, restart at c
    codeOf d w = maybe (error "encode: missing code") id (lookup w d)

-- | The code stream.
encode :: [Slot] -> [Code]
encode = fst . encodeWith

-- | The substrings the codes stand for (length == number of emitted codes).
encodeSubstrings :: [Slot] -> [[Slot]]
encodeSubstrings = snd . encodeWith

-- | Decode a code stream back to the index stream. The KwKwK case: when a code @k@ is the
--   next-not-yet-defined code, its entry is @prev ++ [head prev]@ (reconstructed, since the
--   encoder used it in the same step it defined it). This is the part that makes LZW hard.
decode :: [Code] -> [Slot]
decode []         = []
decode (k0 : ks)  =
  let w0 = maybe (error "decode: bad first code") id (lookup k0 initDecDict)
  in w0 ++ go initDecDict alphabetSize w0 ks
  where
    go _dict _next _prev []          = []
    go dict next prev (k : rest) =
      let entry = case lookup k dict of
                    Just e  -> e
                    Nothing -> prev ++ [head prev]       -- <-- the KwKwK reconstruction
          dict' = (next, prev ++ [head entry]) : dict
      in entry ++ go dict' (next + 1) entry rest

-- | A NAIVE decoder that does NOT handle KwKwK: it only ever looks codes up, and gives up
--   (Nothing) the moment it meets the not-yet-defined code. Used only to give
--   'lawLzwRoundTrips' teeth: the round-trip is non-trivial precisely because THIS fails.
decodeNaive :: [Code] -> Maybe [Slot]
decodeNaive []        = Just []
decodeNaive (k0 : ks) =
  case lookup k0 initDecDict of
    Nothing -> Nothing
    Just w0 -> fmap (w0 ++) (go initDecDict alphabetSize w0 ks)
  where
    go _ _ _ []                = Just []
    go dict next prev (k : rest) =
      case lookup k dict of
        Nothing    -> Nothing                            -- naive: cannot reconstruct KwKwK
        Just entry ->
          let dict' = (next, prev ++ [head entry]) : dict
          in fmap (entry ++) (go dict' (next + 1) entry rest)

-- ===========================================================================
-- (2) Sample index streams
-- ===========================================================================

-- | KwKwK-triggering streams: a slot run / period-2 alternation makes the encoder emit a
--   code in the same step it defines it. A naive decoder breaks on each of these.
kwkwkStreams :: [[Slot]]
kwkwkStreams =
  [ [0,0,0,0,0]
  , [1,1,1,1,1,1]
  , [0,1,0,1,0,1,0]
  , [2,3,2,3,2,3,2,3]
  , [3,3,3,0,0,0,3,3,3,0,0,0]
  ]

-- | Streams that do NOT trigger KwKwK: the encoder never emits a code in the same step it
--   defines it, so a naive look-up-only decoder reconstructs them CORRECTLY. Crucially this
--   includes streams that DO compress (e.g. [0,1,1,0,2,2,0,1,1,0], 10 slots -> 8 codes): so
--   "naive fails" is NOT "naive fails whenever LZW compresses" -- it fails on KwKwK ALONE.
--   (Verified by construction: see lawNaiveDecoderFailsKwKwK, which asserts naive == proper
--   on exactly these.)
nonKwkwkStreams :: [[Slot]]
nonKwkwkStreams =
  [ [0,1,2,3]              -- incompressible: 4 codes == 4 slots
  , [0,1,1,0,2,2,0,1,1,0]  -- COMPRESSES 10 -> 8, yet naive still succeeds (no KwKwK)
  , take 17 (cycle [0,1,2,3])
  , take 23 (cycle [0,1,2,0,3])
  ]

-- | A broad sample set for the round-trip law (edge cases + KwKwK + mixed structure).
sampleStreams :: [[Slot]]
sampleStreams =
  [ []
  , [0]
  , [3]
  , take 20 (cycle [0,1])
  ] ++ nonKwkwkStreams ++ kwkwkStreams

-- | How many times @sub@ occurs (overlapping) inside @xs@.
occurrences :: Eq a => [a] -> [a] -> Int
occurrences sub xs = length [ () | t <- tails xs, sub `isPrefixOf` t ]

-- ===========================================================================
-- (3) The laws
-- ===========================================================================

-- | THE HARD THEOREM: LZW is lossless. @decode . encode == id@ on every sample, crucially
--   including the KwKwK streams where the decoder must rebuild an entry before it is told.
lawLzwRoundTrips :: Bool
lawLzwRoundTrips = and [ decode (encode xs) == xs | xs <- sampleStreams ]

-- | TEETH for the above, BOTH ways: the naive (look-up-only) decoder FAILS on exactly the
--   KwKwK streams AND SUCCEEDS on the non-KwKwK streams (where it equals the proper decoder).
--   This pins KwKwK as the EXACT failure boundary: naive is a perfectly correct decoder
--   EVERYWHERE EXCEPT the KwKwK case, so the round-trip's difficulty is genuinely KwKwK and
--   nothing else. The non-KwKwK side includes a COMPRESSING stream (10 -> 8), so this is not
--   "naive fails iff LZW compresses" -- it is "naive fails iff a code is used as it is born".
--   If KwKwK were not real, the kwkwk conjunct would go False (naive would match) and the law
--   would break; if naive were simply broken, the nonKwkwk conjunct would go False.
lawNaiveDecoderFailsKwKwK :: Bool
lawNaiveDecoderFailsKwKwK =
  and [ decode (encode xs) == xs                -- proper one is correct ...
        && decodeNaive (encode xs) /= Just xs   -- ... and naive one is NOT (KwKwK breaks it)
      | xs <- kwkwkStreams ]
  &&
  and [ decode (encode xs) == xs                -- proper one is correct ...
        && decodeNaive (encode xs) == Just xs   -- ... and naive one ALSO succeeds here
      | xs <- nonKwkwkStreams ]

-- | LZW never EXPANDS here: each emitted code is one phrase covering >= 1 input slot, so the
--   stream is partitioned into phrases and #codes <= #slots, always. Teeth: equality at the
--   incompressible/short end, strict inequality once a substring repeats.
lawCodesNeverExceedSlots :: Bool
lawCodesNeverExceedSlots =
  and [ length (encode xs) <= length xs | xs <- sampleStreams ]
  && length (encode flatStream) < length flatStream    -- strict where structure exists
  && length (encode [0,1,2,3]) == length [0,1,2,3]      -- equality at the incompressible end

-- | DICTIONARY REFERENCE IS SHARING (the reuse count is REAL; the S/contraction gloss is
--   DECORATIVE <>). On a repetitive stream the encoder emits single codes that STAND FOR
--   multi-symbol substrings which occur again in the raw stream: one code, many raw symbols,
--   referenced because the substring was seen before. We require strict compression AND at
--   least one emitted multi-symbol substring that genuinely recurs (>= 2 times) in the input.
lawDictionaryReferenceIsSharing :: Bool
lawDictionaryReferenceIsSharing =
  comp < raw            -- strict compression: codes < slots
  && not (null reused)  -- caused by real reuse of a previously-seen multi-symbol substring
  && maxReuse >= 2       -- and that substring recurs at least twice in the raw stream
  where
    xs      = take 12 (cycle [0,1])          -- [0,1] six times
    raw     = length xs
    comp    = length (encode xs)
    emitted = encodeSubstrings xs
    multi   = nub [ s | s <- emitted, length s >= 2 ]      -- codes standing for >1 symbol
    reused  = [ s | s <- multi, occurrences s xs >= 2 ]    -- ... that recur in the input
    maxReuse = maximum (0 : [ occurrences s xs | s <- reused ])

-- | THE DICTIONARY IS THE LATENT: a low-entropy (repetitive) stream compresses to strictly
--   FEWER codes than a high-entropy stream of the SAME length, because the dictionary
--   captures the structure. Teeth: two same-length streams, opposite structure, measured.
lawDictionaryIsLatent :: Bool
lawDictionaryIsLatent =
  length (encode flatStream) < length (encode noisyStream)
  && length flatStream == length noisyStream             -- same raw length: fair comparison
  && length (encode noisyStream) == length noisyStream   -- high-entropy end: ZERO compression
  && length (encode flatStream)  <  length flatStream    -- low-entropy end: real compression

-- | A maximally repetitive stream (all one slot): the dictionary learns long phrases fast.
flatStream :: [Slot]
flatStream = replicate 16 0

-- | A high-entropy stream: a de Bruijn-style sequence over {0,1,2,3} in which every adjacent
--   PAIR is distinct, so almost no substring recurs and the dictionary cannot compress it.
noisyStream :: [Slot]
noisyStream = [0,0,1,0,2,0,3,1,1,2,1,3,2,2,3,3]

-- ===========================================================================
-- (4) Runner  (mirrors GifSki.hs: PASS/FAIL per law + all-green summary)
-- ===========================================================================

laws :: [(String, Bool)]
laws =
  [ ("lawLzwRoundTrips        (decode . encode = id, incl KwKwK)",  lawLzwRoundTrips)
  , ("lawNaiveDecoderFails    (naive decode breaks on KwKwK)",      lawNaiveDecoderFailsKwKwK)
  , ("lawCodesNeverExceed     (#codes <= #slots: phrases partition)", lawCodesNeverExceedSlots)
  , ("lawDictRefIsSharing     (one code stands for a reused run)",  lawDictionaryReferenceIsSharing)
  , ("lawDictionaryIsLatent   (structure -> strictly fewer codes)", lawDictionaryIsLatent)
  ]

main :: IO ()
main = do
  putStrLn "V2IndexLzw.hs  -- EXPLORATION (NOT WIRED): index map + LZW as the compute/latent layer"
  putStrLn (replicate 72 '-')
  mapM_ (\(n, ok) -> putStrLn (verdict ok ++ "  " ++ n)) laws
  putStrLn (replicate 72 '-')
  let passed = length (filter snd laws)
      total  = length laws
  putStrLn ("SUMMARY: " ++ show passed ++ "/" ++ show total ++ " laws PASS"
            ++ if passed == total then "  (all green)" else "  (FAILURES present)")
  putStrLn ""
  -- A concrete witness of the KwKwK hardness:
  let w = [0,0,0,0,0]
  putStrLn ("KwKwK witness " ++ show w ++ " -> codes " ++ show (encode w))
  putStrLn ("   proper decode = " ++ show (decode (encode w))
            ++ "   naive decode = " ++ show (decodeNaive (encode w)))
  -- Sharing / latent numbers, named:
  let xs = take 12 (cycle [0,1])
  putStrLn ("sharing: " ++ show xs ++ "  raw=" ++ show (length xs)
            ++ " codes=" ++ show (length (encode xs))
            ++ " savings=" ++ show (length xs - length (encode xs)))
  putStrLn ("   [0,1] recurs " ++ show (occurrences [0,1] xs)
            ++ "x in raw; emitted as a single code (a back-reference).")
  putStrLn ("latent: flat  " ++ show flatStream ++ " -> " ++ show (length (encode flatStream)) ++ " codes")
  putStrLn ("        noisy " ++ show noisyStream ++ " -> " ++ show (length (encode noisyStream)) ++ " codes")
  putStrLn ""
  putStrLn "HONEST NOTE: the lossless round-trip (KwKwK and all) and the entropy/dictionary-size"
  putStrLn "relation are REAL theorems. The reuse COUNT in lawDictRefIsSharing is real data; its"
  putStrLn "reading as the S/contraction move is SUGGESTIVE (a data-vs-term rhyme), not a theorem:"
  putStrLn "no typed homomorphism LZW-stream -> SKI-reduction is exhibited. Sharing here is"
  putStrLn "DATA-level substring reuse; S is TERM-level argument duplication."
  where verdict True  = "PASS"
        verdict False = "FAIL"
