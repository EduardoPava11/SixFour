{-# LANGUAGE ScopedTypeVariables #-}

module Properties.AtlasNetEval (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import qualified Data.Vector.Unboxed as U

import SixFour.Spec.Tensor       (gmmTokenSigmaMask)
import SixFour.Spec.LookNetD     (sigmaDecoderMask)
import SixFour.Spec.AtlasNetEval

-- The concrete Atlas-head forward ('atlasForward', ported from atlas_net_mlx.py)
-- is the ordinal golden oracle for the hand-written Metal forward. These laws pin
-- its self-consistency AND the AlphaZero symmetry split (invariant value /
-- equivariant policy), so the emitted golden is trustworthy. The σ laws hold
-- structurally (mask construction), so a mask error here FAILS the gate.

w :: AtlasNetWeights
w = deterministicAtlasWeights

finite :: Double -> Bool
finite x = not (isNaN x) && not (isInfinite x)

-- | A random Atlas input: (tokens 13-D, pooling weights Σ=1, genome 384-D).
genInput :: Gen ([U.Vector Double], [Double], U.Vector Double)
genInput = do
  n  <- choose (1, 8)
  ts <- vectorOf n (U.fromList <$> vectorOf atlasTokenDim (choose (-1, 1)))
  ws <- vectorOf n (choose (0.01, 1) :: Gen Double)
  let s = sum ws
  g  <- U.fromList <$> vectorOf 384 (choose (-1, 1))
  pure (ts, map (/ s) ws, g)

-- | σ on a 13-D token: negate the 10 base dims where 'gmmTokenSigmaMask' is True;
-- the 3 σ-invariant curation scalars (dims 10..12) are left unchanged.
sigmaTok :: U.Vector Double -> U.Vector Double
sigmaTok t =
  let base = U.imap (\i x -> if gmmTokenSigmaMask !! i then negate x else x) (U.take 10 t)
  in base U.++ U.drop 10 t

-- | σ₃₈₄ on the 384-D genome: negate channels where 'sigmaDecoderMask' is True.
sigmaGenome :: U.Vector Double -> U.Vector Double
sigmaGenome = U.imap (\i x -> if sigmaDecoderMask !! i then negate x else x)

sigmaInput :: ([U.Vector Double], [Double], U.Vector Double)
           -> ([U.Vector Double], [Double], U.Vector Double)
sigmaInput (ts, ws, g) = (map sigmaTok ts, ws, sigmaGenome g)

tol :: Double
tol = 1e-9

tests :: TestTree
tests = testGroup "AtlasNetEval (the Atlas policy/value head forward — the ordinal oracle)"

  [ testProperty "policy is exactly 1524-D and context is 128-D" $
      forAll genInput $ \inp ->
        let t = atlasForward w inp
        in length (atfPolicy t) == nVocab && length (atfContext t) == ctxDim

  , testProperty "context + policy + value are all finite (no NaN/Inf — JSON-safe)" $
      forAll genInput $ \inp ->
        let t = atlasForward w inp
        in all finite (atfContext t) && all finite (atfPolicy t) && finite (atfValue t)

  , testProperty "value is σ-INVARIANT: V(σ·s) ≈ V(s) (inv-proj squares the chroma flip)" $
      forAll genInput $ \inp ->
        let va = atfValue (atlasForward w (sigmaInput inp))
            vb = atfValue (atlasForward w inp)
        in abs (va - vb) <= tol

  , testProperty "policy is σ-EQUIVARIANT via the delta row-swap: p(σ·s)[slot,2i] ≈ p(s)[slot,2i+1]" $
      forAll genInput $ \inp ->
        let pa = atfPolicy (atlasForward w (sigmaInput inp))
            pb = atfPolicy (atlasForward w inp)
            idx slot d = slot * nDeltas + d
            ok slot i = abs (pa !! idx slot (2*i) - pb !! idx slot (2*i+1)) <= tol
        in and [ ok slot i | slot <- [0 .. nSlots - 1], i <- [0 .. nDeltas `div` 2 - 1] ]

  , testProperty "deterministic Atlas weights are all finite" $
      once $
        let bits = U.toList (aPhiExt w) ++ U.toList (aGenomeEnc w) ++ U.toList (aNodeHead w)
                ++ U.toList (aDeltaHalf w) ++ U.toList (aV1 w) ++ U.toList (aV1b w)
                ++ U.toList (aV2 w) ++ [aV2b w]
        in all finite bits
  ]
