{- |
Module      : SixFour.Spec.V21Transport
Description : The V2.1 TIME axis, recovered: a byte-exact 1-D optimal-transport displacement flow. The pooled field ("SixFour.Spec.V21Field") marginalises the burst over time; this module restores the 64 per-frame slices as an anchor histogram plus per-frame monotone transport maps @T = F⁻¹∘F@, so the time↔value coupling survives at monotone-map cost, not full-tensor cost.

The field in "SixFour.Spec.V21Field" is the burst POOLED over time (@accumulateHist@ decimates the
@t@ axis, @poolV21Counts@ sums it): per bin it keeps the full VALUE distribution but destroys the
FRAME axis. The shipped GIF keeps the 64 frames but crushes each bin's value distribution to one
palette byte. They are the two MARGINALS of the per-bin joint density @f(t, value)@ — and, like a
signal's time and frequency views, neither can be sharp in both. What both discard is the same thing:
the COUPLING, how a bin's value MOVES over the burst.

This module stores that coupling directly. Because the ground space is 1-D (a value level in
@0..nLevels-1@) and every per-frame histogram carries the SAME mass (the soft-splat deposits @box*w@
per bin per frame, a partition of unity — "SixFour.Spec.V21Field" 'SixFour.Spec.V21Field.splatContribAt'),
the optimal transport between two frames' histograms has a CLOSED FORM: expand each histogram to its
sorted quantile list (the sampled inverse-CDF @F⁻¹@, one entry per unit mass) and match rank-for-rank.
The transport MAP carrying frame @s@ to frame @t@ is then the per-rank integer displacement
@d[k] = q_t[k] - q_s[k]@ — exactly @F_t⁻¹ ∘ F_s@ read on the mass line. No Sinkhorn, no LP, no float,
no non-unit division: it lives on the byte-exact ring ℤ, so Metal == Zig == Haskell (the new Zig seam
is @s4_v21_transport@).

== What this buys (the laws in @Properties.V21Transport@)

  * 'quantiles' \/ 'histOf' are inverse (the inverse-CDF representation is a bijection on equal-mass
    histograms) — 'lawQuantileRoundTrip'.
  * 'pushforward' of the source under 'transportDisp' reproduces the target EXACTLY, and the negated
    displacement inverts it — 'lawTransportReconstructs', 'lawTransportReversible'. No frame is
    approximated: the 64 slices come back byte-for-byte.
  * The transport's total displacement EQUALS the CDF-L1 Wasserstein-1 cost ('SixFour.Spec.V21Field.paletteW1'
    is the same quantity for palettes) — 'lawTransportCostIsW1' — so this is the OPTIMAL map, not an
    arbitrary rearrangement.
  * A RIGID value drift (the whole distribution shifted by @c@, i.e. motion) transports at a CONSTANT
    displacement @c@ at every rank — 'lawTranslateIsConstantShift'. That is the compression: a moving
    bin costs ONE scalar per frame, not a whole histogram.
  * Composition along ranks is ADDITIVE, so the burst is a geodesic — 'lawFlowAdditiveInRank' — and an
    anchor plus the per-frame displacements reconstructs ALL 64 slices — 'lawFlowRecoversAllSlices'.
    This is the headline: TIME is recovered.
  * The 1-D W₂ barycenter is the per-rank MEAN of the quantiles ('barycenter'), and the barycenter of
    translates is a single translate — 'lawBarycenterIsRankMean', 'lawBarycenterOfTranslatesIsTranslate'.
    So the "'SixFour.Spec.V21Field.collapseQ16' of a smarter consensus" (the better GIF byte) is just a
    readout of this same flow at its Fréchet mean.

== Scope

Additive and byte-exact: it introduces no colour-ring choice and reuses the value alphabet of
"SixFour.Spec.V21Field". Equal per-frame mass is a PRECONDITION (guaranteed on the soft-splat field);
the laws construct equal-mass inputs from equal-length sample lists, mirroring how the device produces
them. The probability\/geodesic-interpolation view for a continuous @t@ is a training diagnostic that
would live in an exploration module, not here.
-}
-- COMPARTMENT: ZIG-FLOOR | tag:DeviceTag
module SixFour.Spec.V21Transport
  ( -- * Histograms as sorted quantiles (the sampled inverse-CDF)
    Hist
  , Disp
  , quantiles
  , histOf
  , cdf
  , mass
    -- * The monotone 1-D transport map T = F⁻¹∘F
  , transportDisp
  , pushforward
  , w1CDF
  , shiftHist
    -- * The temporal displacement flow (anchor + per-frame maps -> the 64 slices)
  , Flow
  , flowFrom
  , reconstructFlow
    -- * The 1-D Wasserstein barycenter (per-rank mean; the consensus anchor)
  , barycenter
    -- * The barycenter-anchored flow + RLE map compression (the airdrop format)
  , flowVsAnchor
  , reconstructVsAnchor
  , Run
  , rleEncode
  , rleDecode
    -- * The GIF derived from the data (the inference surface is a projection of training data)
  , gifByteOf
  , gifFromFlow
    -- * Laws (QuickCheck'd in @Properties.V21Transport@)
  , lawQuantileRoundTrip
  , lawTransportReconstructs
  , lawTransportReversible
  , lawTransportCostIsW1
  , lawTranslateIsConstantShift
  , lawFlowAdditiveInRank
  , lawFlowRecoversAllSlices
  , lawBarycenterIsRankMean
  , lawBarycenterOfTranslatesIsTranslate
  , lawGifDerivesFromFlow
  , lawFlowIsFullTrainingSet
  , lawBarycenterFlowRecovers
  , lawRleRoundTrip
  , lawRigidDriftIsOneRun
  ) where

import SixFour.Spec.V21Field (modeOfCounts)

-- | An integer COUNT histogram over the value levels @0..levels-1@ (the same fibre payload a
--   "SixFour.Spec.V21Field" curve counts, before the energy recode). Its 'mass' is the number of
--   observations; for the soft-splat field every per-frame bin has the same mass @box*w@.
type Hist = [Int]

-- | A per-RANK integer displacement: the transport map in quantile (mass-line) coordinates. Entry @k@
--   is how far the @k@-th unit of mass moves along the value axis. Length equals the 'mass'.
type Disp = [Int]

-- | THE SAMPLED INVERSE-CDF: expand a count histogram to its non-decreasing list of value levels, one
--   entry per unit of mass (level @l@ repeated @count l@ times). @quantiles [2,0,3] == [0,0,2,2,2]@.
--   This is @F⁻¹@ read on the discrete mass line; it is the canonical form 1-D optimal transport acts
--   on (matching rank-for-rank).
quantiles :: Hist -> [Int]
quantiles h = concat (zipWith replicate h [0 ..])

-- | Bin a list of value levels back into a length-@levels@ count histogram (the left inverse of
--   'quantiles' when @levels@ covers the alphabet). Out-of-range samples are dropped, matching the
--   crop-margin discipline of "SixFour.Spec.V21Field".
histOf :: Int -> [Int] -> Hist
histOf levels xs = [ length (filter (== l) xs) | l <- [0 .. levels - 1] ]

-- | The cumulative distribution (running count sum) of a histogram: @cdf [2,0,3] == [2,2,5]@. Its L1
--   difference is the 1-D Wasserstein-1 ground cost ('w1CDF'), the same quantity
--   "SixFour.Spec.V21Field" 'SixFour.Spec.V21Field.paletteW1' computes for palettes.
cdf :: Hist -> [Int]
cdf = scanl1 (+)

-- | The total observation count (mass) of a histogram.
mass :: Hist -> Int
mass = sum

-- | THE MONOTONE TRANSPORT MAP @T = F⁻¹∘F@, in quantile coordinates: the per-rank displacement
--   @d[k] = q_t[k] - q_s[k]@ carrying source histogram @s@ to target @t@. For 1-D distributions of
--   EQUAL MASS the rank-for-rank (sorted) matching is the optimal coupling for every convex ground
--   cost, so this displacement IS the optimal transport map. Requires @mass s == mass t@ (the
--   soft-splat field guarantees it); on unequal mass the shorter rank list truncates.
transportDisp :: Hist -> Hist -> Disp
transportDisp s t = zipWith (-) (quantiles t) (quantiles s)

-- | PUSH THE SOURCE FORWARD along a displacement and re-bin: @histOf levels (q_s + d)@. With
--   @d = transportDisp s t@ this reproduces @t@ exactly ('lawTransportReconstructs'); with @-d@ it
--   inverts back to @s@. This is how a stored anchor + map yields a frame slice.
pushforward :: Int -> Hist -> Disp -> Hist
pushforward levels s d = histOf levels (zipWith (+) (quantiles s) d)

-- | The 1-D Wasserstein-1 transport cost as the L1 distance between CDFs, @Σ_v |CDF_s(v) - CDF_t(v)|@.
--   Equals the total absolute rank displacement @Σ_k |d[k]|@ ('lawTransportCostIsW1'), the witness that
--   'transportDisp' is the optimal (not merely a valid) map. Pads the shorter CDF with its final value
--   so equal-mass histograms of the same alphabet compare exactly.
w1CDF :: Hist -> Hist -> Int
w1CDF s t =
  let cs = cdf s; ct = cdf t
      n  = max (length cs) (length ct)
      pad xs = xs ++ replicate (n - length xs) (if null xs then 0 else last xs)
  in sum (map abs (zipWith (-) (pad cs) (pad ct)))

-- | Rigidly shift a histogram by @c@ along the value axis (every sample moves by @c@), re-binned into
--   @levels@. The witness for 'lawTranslateIsConstantShift': a rigid drift is what a moving bin looks
--   like, and it transports at a constant displacement.
shiftHist :: Int -> Int -> Hist -> Hist
shiftHist levels c h = histOf levels (map (+ c) (quantiles h))

-- | A TEMPORAL DISPLACEMENT FLOW: an anchor histogram plus, for each remaining frame, the transport
--   map ('Disp') carrying the anchor to that frame. This is the restructured capture — the field's
--   value distribution PLUS the coupling that reinstates time.
type Flow = (Hist, [Disp])

-- | Encode a burst (the per-frame histograms, in frame order) as a 'Flow' anchored at the FIRST frame:
--   @(H₀, [transportDisp H₀ H_t | t = 1..])@. Every frame is equal mass (the soft-splat guarantee), so
--   every displacement is well-defined. Anchoring at 'barycenter' instead is a drop-in alternative (the
--   consensus anchor); the reconstruction law holds for any equal-mass anchor.
flowFrom :: [Hist] -> Flow
flowFrom []             = ([], [])
flowFrom (h0 : rest)    = (h0, [ transportDisp h0 h | h <- rest ])

-- | Decode a 'Flow' back to the per-frame histograms: the anchor, then each frame pushed forward along
--   its stored map. Exact inverse of 'flowFrom' ('lawFlowRecoversAllSlices'): the 64 slices return
--   byte-for-byte, so TIME is recovered from field + maps.
reconstructFlow :: Int -> Flow -> [Hist]
reconstructFlow _      ([],     _)    = []
reconstructFlow levels (anchor, maps) = anchor : [ pushforward levels anchor d | d <- maps ]

-- | THE 1-D WASSERSTEIN-2 BARYCENTER of equal-mass histograms: the per-rank MEAN of their quantiles,
--   re-binned. Unlike the arithmetic mean of the histograms (which blurs and splits modes — the naive
--   @Σ_t H_t@ pooling), this is the geometrically correct average: the barycenter of shifted copies is
--   a single shifted copy ('lawBarycenterOfTranslatesIsTranslate'). Integer per-rank mean uses
--   truncating division (the deterministic floor, like the collapse tie-break); exact when the mean is
--   integral. The natural consensus ANCHOR for a 'Flow', and the better GIF-byte consensus is its
--   'SixFour.Spec.V21Field.collapseQ16'.
barycenter :: Int -> [Hist] -> Hist
barycenter levels [] = replicate levels 0
barycenter levels hs =
  let qs = map quantiles hs
      n  = length hs
  in histOf levels [ sum col `div` n | col <- transposeEq qs ]

-- Transpose a list of equal-length rows (the quantile lists of equal-mass histograms). Defined locally
-- to keep the module dependency-free; equal length is the equal-mass precondition.
transposeEq :: [[Int]] -> [[Int]]
transposeEq xss
  | any null xss = []
  | otherwise    = map head xss : transposeEq (map tail xss)

-- ---------------------------------------------------------------------------
-- The airdrop FORMAT: a barycenter-anchored flow with RLE-compressed maps. The
-- anchor is the 1-D barycenter (the consensus, so displacements are centred and
-- small); each of the 64 frames stores its map FROM the anchor (random access,
-- no chaining). Raw maps are per-rank (length = mass), so they are NOT smaller
-- than the frames by themselves; the size win is run-length encoding, which
-- collapses a rigid drift (a constant displacement) to a SINGLE run
-- (lawRigidDriftIsOneRun) and is exact (lawRleRoundTrip). Lossy low-rank/velocity
-- models are a later modelling rung, off this byte-exact format.
-- ---------------------------------------------------------------------------

-- | The per-frame transport maps FROM a given anchor (need not be a frame): @[anchor -> slice_t]@.
--   With the 'barycenter' as anchor this is the consensus-centred flow; every map is well-defined
--   because the barycenter shares the slices' mass.
flowVsAnchor :: Hist -> [Hist] -> [Disp]
flowVsAnchor anchor slices = [ transportDisp anchor h | h <- slices ]

-- | Reconstruct the per-frame slices from an anchor and its 'flowVsAnchor' maps: push the anchor
--   forward along each map. Exact inverse ('lawBarycenterFlowRecovers'), so no frame is lost.
reconstructVsAnchor :: Int -> Hist -> [Disp] -> [Hist]
reconstructVsAnchor levels anchor maps = [ pushforward levels anchor d | d <- maps ]

-- | A run-length pair @(value, length)@ of a displacement map. A rigid drift is one run; piecewise-
--   rigid motion is a few runs. This is where the flow gets SMALLER than storing raw frames.
type Run = (Int, Int)

-- | Run-length ENCODE a displacement (or any int list): consecutive equal values become one @(value,
--   run-length)@ pair. Exact and reversible ('rleDecode').
rleEncode :: [Int] -> [Run]
rleEncode []       = []
rleEncode (x : xs) = go x 1 xs
  where
    go v n []       = [(v, n)]
    go v n (y : ys)
      | y == v    = go v (n + 1) ys
      | otherwise = (v, n) : go y 1 ys

-- | Run-length DECODE: expand each @(value, run-length)@ pair back to the value repeated. Left inverse
--   of 'rleEncode'.
rleDecode :: [Run] -> [Int]
rleDecode = concatMap (\(v, n) -> replicate n v)

-- ---------------------------------------------------------------------------
-- The GIF derived from the data. The deployed model's surface is GIF in / GIF
-- out; the field + transport flow are TRAINING-ONLY context. For that to be
-- self-consistent the GIF must be a deterministic PROJECTION of the training
-- data, not an independent artifact -- so the GIF byte of a bin is the COLLAPSE
-- (the mode) of its value histogram, and a frame's GIF is the collapse of the
-- flow-reconstructed slice. This is the byte SixFour.Spec.V21Field.collapseQ16
-- produces on the energy face; reused here, not re-derived.
-- ---------------------------------------------------------------------------

-- | THE GIF BYTE of one value histogram: the collapse = the MODE (argmax count, lowest index winning
--   ties), exactly "SixFour.Spec.V21Field" 'SixFour.Spec.V21Field.modeOfCounts'. A GIF pixel is a
--   per-channel mode, so a bin's colour is @(mode R, mode G, mode B)@.
gifByteOf :: Hist -> Int
gifByteOf = modeOfCounts

-- | THE GIF DERIVED FROM THE FLOW: reconstruct every frame from the anchor + per-frame maps, then
--   collapse each slice to its GIF byte. The GIF is therefore a PURE FUNCTION of the stored transport
--   data — the inference surface (GIF in, GIF out) is a projection of exactly what the model trained
--   on, never a separately-produced image.
gifFromFlow :: Int -> Flow -> [Int]
gifFromFlow levels flow = map gifByteOf (reconstructFlow levels flow)

-- ---------------------------------------------------------------------------
-- Laws (predicates; QuickCheck'd in Properties.V21Transport). Equal-mass inputs
-- are built from equal-LENGTH sample lists coerced into the value alphabet, which
-- is exactly how the device produces per-frame bins (box*w samples each).
-- ---------------------------------------------------------------------------

-- Coerce raw ints to valid value levels in @0..levels-1@.
sampl :: Int -> [Int] -> [Int]
sampl levels = map (\x -> abs x `mod` max 1 levels)

-- Build an equal-mass pair of histograms from two raw lists (truncated to a common length).
pairHist :: Int -> [Int] -> [Int] -> (Hist, Hist)
pairHist levels a b =
  let n  = min (length a) (length b)
      h1 = histOf levels (take n (sampl levels a))
      h2 = histOf levels (take n (sampl levels b))
  in (h1, h2)

-- | THE INVERSE-CDF REPRESENTATION IS A BIJECTION: re-binning a histogram's quantiles restores it
--   exactly. The foundation the whole flow stands on.
lawQuantileRoundTrip :: Int -> [Int] -> Bool
lawQuantileRoundTrip lraw s =
  let levels = 1 + abs lraw `mod` 16
      h      = histOf levels (sampl levels s)
  in histOf levels (quantiles h) == h

-- | RECONSTRUCTION: pushing the source forward along its transport map reproduces the target byte-for-
--   byte. Field + map = the exact frame slice. (Equal mass by construction.)
lawTransportReconstructs :: Int -> [Int] -> [Int] -> Bool
lawTransportReconstructs lraw a b =
  let levels   = 1 + abs lraw `mod` 16
      (h1, h2) = pairHist levels a b
  in pushforward levels h1 (transportDisp h1 h2) == h2

-- | REVERSIBILITY: the negated displacement is the reverse transport, and it inverts the map — no
--   information is lost restructuring the capture. @transportDisp t s == map negate (transportDisp s t)@.
lawTransportReversible :: Int -> [Int] -> [Int] -> Bool
lawTransportReversible lraw a b =
  let levels   = 1 + abs lraw `mod` 16
      (h1, h2) = pairHist levels a b
      d        = transportDisp h1 h2
  in transportDisp h2 h1 == map negate d
     && pushforward levels h2 (map negate d) == h1

-- | OPTIMALITY: the transport's total rank displacement equals the CDF-L1 Wasserstein-1 cost, so the
--   monotone rank matching is the OPTIMAL coupling, not just a valid one.
lawTransportCostIsW1 :: Int -> [Int] -> [Int] -> Bool
lawTransportCostIsW1 lraw a b =
  let levels   = 1 + abs lraw `mod` 16
      (h1, h2) = pairHist levels a b
  in sum (map abs (transportDisp h1 h2)) == w1CDF h1 h2

-- | THE COMPRESSION THEOREM: a rigid value drift (motion) transports at a CONSTANT displacement at
--   every rank. A moving bin costs ONE scalar per frame, not a whole histogram — why the flow beats the
--   full [t x value] tensor. The shift is kept in the interior so no mass leaves the alphabet.
lawTranslateIsConstantShift :: Int -> [Int] -> Int -> Bool
lawTranslateIsConstantShift lraw s craw =
  let levels = 8 + abs lraw `mod` 24            -- headroom so the shift stays in range
      c      = 1 + abs craw `mod` 3             -- a small positive drift
      -- keep samples in the lower interior so +c never clips
      h      = histOf levels (map (\x -> abs x `mod` (levels - c)) s)
      hShift = shiftHist levels c h
  in null s || transportDisp h hShift == replicate (mass h) c

-- | GEODESIC / CHEAP COMPOSITION: transport composes ADDITIVELY along ranks, so a chain of frame-to-
--   frame maps equals the direct anchor-to-frame map. @disp H0 H2 == disp H0 H1 + disp H1 H2@.
lawFlowAdditiveInRank :: Int -> [Int] -> [Int] -> [Int] -> Bool
lawFlowAdditiveInRank lraw a b c =
  let levels = 1 + abs lraw `mod` 16
      n      = minimum [length a, length b, length c]
      h k    = histOf levels (take n (sampl levels k))
      (h0, h1, h2) = (h a, h b, h c)
  in transportDisp h0 h2 == zipWith (+) (transportDisp h0 h1) (transportDisp h1 h2)

-- | THE HEADLINE — TIME IS RECOVERED: encoding a burst as an anchor + per-frame maps and decoding it
--   returns every one of the frames byte-for-byte. The restructured capture loses nothing the pooled
--   field + GIF pair discarded; it reinstates the whole [t x value] joint.
lawFlowRecoversAllSlices :: Int -> [[Int]] -> Bool
lawFlowRecoversAllSlices lraw raws =
  let levels = 1 + abs lraw `mod` 16
      rows   = filter (not . null) raws
      n      = if null rows then 0 else minimum (map length rows)
      slices = [ histOf levels (take n (sampl levels r)) | r <- rows ]
  in null slices || reconstructFlow levels (flowFrom slices) == slices

-- | THE BARYCENTER IS THE PER-RANK MEAN: the 1-D W₂ barycenter equals binning the rank-wise average of
--   the inputs' quantiles (the closed form), so no solver is needed for the consensus anchor.
lawBarycenterIsRankMean :: Int -> [[Int]] -> Bool
lawBarycenterIsRankMean lraw raws =
  let levels = 1 + abs lraw `mod` 16
      rows   = filter (not . null) raws
      n      = if null rows then 0 else minimum (map length rows)
      slices = [ histOf levels (take n (sampl levels r)) | r <- rows ]
      qs     = map quantiles slices
      k      = length slices
      manual = histOf levels [ sum col `div` k | col <- transposeEq qs ]
  in null slices || barycenter levels slices == manual

-- | THE DEFINING SYMMETRY (why the barycenter is the RIGHT average, not the blurring arithmetic mean):
--   the barycenter of a histogram and its rigid shifts is that histogram shifted by the MEAN shift — a
--   single sharp mode, never a multi-modal smear. Uses shifts whose mean is integral so the integer
--   per-rank mean is exact.
lawBarycenterOfTranslatesIsTranslate :: Int -> [Int] -> Bool
lawBarycenterOfTranslatesIsTranslate lraw s =
  let levels  = 12 + abs lraw `mod` 20
      base    = histOf levels (map (\x -> 2 + abs x `mod` (levels - 6)) s)   -- interior, room for +/-2
      shifts  = [0, 2, 4]                                                    -- mean shift = 2 (integral)
      copies  = [ shiftHist levels c base | c <- shifts ]
      meanSh  = sum shifts `div` length shifts
  in null s || barycenter levels copies == shiftHist levels meanSh base

-- | GIF DERIVES FROM DATA (the deploy contract, as a theorem): the GIF bytes computed from the stored
--   flow equal the GIF bytes of the original per-frame slices. Because the flow reconstructs the slices
--   exactly, the GIF is a deterministic function of the training data — so the inference surface (GIF
--   in / GIF out) consumes a projection of what the model trained on, and the manifest's "the GIF is the
--   collapse" is TRUE by construction, not by coincidence.
lawGifDerivesFromFlow :: Int -> [[Int]] -> Bool
lawGifDerivesFromFlow lraw raws =
  let levels = 1 + abs lraw `mod` 16
      rows   = filter (not . null) raws
      n      = if null rows then 0 else minimum (map length rows)
      slices = [ histOf levels (take n (sampl levels r)) | r <- rows ]
  in null slices || gifFromFlow levels (flowFrom slices) == map gifByteOf slices

-- | THE BARYCENTER-ANCHORED FLOW RECOVERS EVERY SLICE: anchoring at the consensus barycenter (not a
--   frame) and storing one map per frame still reconstructs all 64 slices byte-for-byte. So the
--   airdrop format (barycenter + per-frame maps) is lossless for any equal-mass burst.
lawBarycenterFlowRecovers :: Int -> [[Int]] -> Bool
lawBarycenterFlowRecovers lraw raws =
  let levels = 1 + abs lraw `mod` 16
      rows   = filter (not . null) raws
      n      = if null rows then 0 else minimum (map length rows)
      slices = [ histOf levels (take n (sampl levels r)) | r <- rows ]
      anchor = barycenter levels slices
  in null slices || reconstructVsAnchor levels anchor (flowVsAnchor anchor slices) == slices

-- | RLE IS EXACT: run-length decode inverts run-length encode on any displacement, so compressing the
--   maps loses nothing (the format stays byte-exact).
lawRleRoundTrip :: [Int] -> Bool
lawRleRoundTrip xs = rleDecode (rleEncode xs) == xs

-- | THE COMPRESSION, CONCRETELY: a rigid value drift (motion) has a CONSTANT displacement, so its map
--   RLE-encodes to a SINGLE run — one @(shift, mass)@ pair for the whole frame, instead of @mass@
--   numbers. This is why the flow beats storing raw per-frame histograms: coherent motion is nearly
--   free. Pairs with 'lawTranslateIsConstantShift' (the displacement is constant) to show the win.
lawRigidDriftIsOneRun :: Int -> [Int] -> Int -> Bool
lawRigidDriftIsOneRun lraw s craw =
  let levels = 8 + abs lraw `mod` 24
      c      = 1 + abs craw `mod` 3
      h      = histOf levels (map (\x -> abs x `mod` (levels - c)) s)
      hShift = shiftHist levels c h
      disp   = transportDisp h hShift
  in null s || rleEncode disp == [(c, mass h)]

-- | THE DATA IS A FULL TRAINING SET: the stored flow reconstructs every per-frame slice byte-for-byte
--   (the same guarantee as 'lawFlowRecoversAllSlices', stated as the training-completeness contract).
--   Nothing about the burst is lost, so the model can train on the whole @[t × value]@ joint and the
--   GIF is a strict projection of it ('lawGifDerivesFromFlow').
lawFlowIsFullTrainingSet :: Int -> [[Int]] -> Bool
lawFlowIsFullTrainingSet lraw raws =
  let levels = 1 + abs lraw `mod` 16
      rows   = filter (not . null) raws
      n      = if null rows then 0 else minimum (map length rows)
      slices = [ histOf levels (take n (sampl levels r)) | r <- rows ]
  in null slices || reconstructFlow levels (flowFrom slices) == slices
