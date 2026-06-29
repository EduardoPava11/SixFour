{- |
Module      : V2SkiHomomorphism
Description : EXPLORATION (NOT WIRED, base-only, runghc). Closes the OPEN item from
              V2SkiNativeGif: a typed HOMOMORPHISM h : Comb -> Op from GifSki's abstract
              SKI reducer into the native GIF89a operation algebra, such that NATIVE
              INVENTION is exactly the image of the S-term under reduction. This is the
              precondition the owner named before SKI may be USED in training.

  Check:  runghc V2SkiHomomorphism.hs
     (needs GifSki.hs and V2SkiNativeGif.hs in the same directory)

  THE CONSTRUCTION: Op is the standard universal domain for untyped combinators
  (a frame, or a function on the domain). h maps S,K,I to their domain realizations and
  preserves application by construction (h (App a b) = app (h a) (h b)), so it preserves
  the SKI reduction rules. Native frame operations (coarse, invent, anchorBlend from
  V2SkiNativeGif) inject as Op atoms; the theorem 'lawSIsNativeInvention' then shows the
  abstract S-term, interpreted, equals the native invented frame.

  REAL (axioms hold, toothed): h realizes the S/K/I rules over GIF frames; native invention
  IS h applied to the S-term; h commutes with GifSki.nf (reduce-then-interpret ==
  interpret-then-reduce) on terms that genuinely reduce; SKK = I lands as native identity.
  SUGGESTIVE: nothing new is asserted here beyond the homomorphism on the S/K/I fragment;
  the codec as a WHOLE is still not claimed to be an SKI program.
-}
module V2SkiHomomorphism where

import qualified GifSki as G
import V2SkiNativeGif
  ( Frame, frameEq, coarse, invent, anchorBlend, inventedFrame )

-- ===========================================================================
-- (1) The universal domain and the homomorphism
-- ===========================================================================

-- | The universal domain for untyped combinators over GIF89a frames:
--   either a frame (a GIF89a object) or a function on the domain.
data Op = OpFrame Frame | OpFun (Op -> Op)

-- | Application in the domain. A frame ignores further arguments (kept total).
app :: Op -> Op -> Op
app (OpFun f)    x = f x
app (OpFrame fr) _ = OpFrame fr     -- kept-total dead branch: no well-formed term applies a frame

-- | THE HOMOMORPHISM h : Comb -> Op. Preserves application by construction
--   (@h (App a b) = app (h a) (h b)@) and realizes the S/K/I reduction rules in the domain,
--   so reducing a Comb term and interpreting it agree.
h :: G.Comb -> Op
h G.S         = OpFun (\f -> OpFun (\g -> OpFun (\x -> app (app f x) (app g x))))
h G.K         = OpFun (\x -> OpFun (\_ -> x))
h G.I         = OpFun (\x -> x)
h (G.App a b) = app (h a) (h b)

-- Inject native GIF89a frame operations as domain atoms.
opF :: Frame -> Op
opF = OpFrame

op1 :: (Frame -> Frame) -> Op
op1 f = OpFun (\x -> case x of OpFrame fr -> OpFrame (f fr); _ -> x)

op2 :: (Frame -> Frame -> Frame) -> Op
op2 f = OpFun (\x -> OpFun (\y -> case (x, y) of
                                    (OpFrame a, OpFrame b) -> OpFrame (f a b)
                                    _                      -> x))

asFrame :: Op -> Maybe Frame
asFrame (OpFrame fr) = Just fr
asFrame _            = Nothing

-- | Compare two domain values that have reduced to frames.
opFrameEq :: Op -> Op -> Bool
opFrameEq a b = case (asFrame a, asFrame b) of
                  (Just x, Just y) -> frameEq x y
                  _                -> False

-- ===========================================================================
-- (2) Laws
-- ===========================================================================

-- | h realizes the I rule natively: @app (h I) a == a@.
lawHomI :: Bool
lawHomI = opFrameEq (app (h G.I) (opF inventedFrame)) (opF inventedFrame)

-- | h realizes the K rule natively (weakening): @app (app (h K) a) b == a@, the second
--   argument discarded. Tooth: two different second arguments give the same result, and they
--   really differ, so information was genuinely thrown away.
lawHomK :: Bool
lawHomK =
     opFrameEq (app (app (h G.K) (opF coarse)) (opF inventedFrame)) (opF coarse)
  && opFrameEq (app (app (h G.K) (opF coarse)) (opF inventedFrame))
               (app (app (h G.K) (opF coarse)) (opF (invent coarse)))
  && not (frameEq coarse inventedFrame)

-- | THE HEADLINE: native invention IS the image of the S-term under reduction.
--   @app^3 (h S) anchorBlend invent coarse == native inventedFrame@.
lawSIsNativeInvention :: Bool
lawSIsNativeInvention =
  opFrameEq (app (app (app (h G.S) (op2 anchorBlend)) (op1 invent)) (opF coarse))
            (opF inventedFrame)

-- | SKK reduces to I (GifSki.lawIisSKK); through h it acts as the native identity on a frame.
lawSKKIsIdentity :: Bool
lawSKKIsIdentity =
     G.lawIisSKK
  && opFrameEq (app (h skk) (opF inventedFrame)) (opF inventedFrame)
  where skk = G.App (G.App G.S G.K) G.K

-- | h COMMUTES WITH REDUCTION (on terms NORMALIZING TO I): interpreting nf(t) equals interpreting
--   t, applied to a frame. All test terms here normalize to I (a pure Comb term cannot embed a Frame
--   atom, so closed combinator terms that reduce to a frame are not expressible; SKK is the
--   load-bearing reducing case). Tooth: at least one term genuinely reduces (t /= nf t), not vacuous.
lawHomCommutesWithReduction :: Bool
lawHomCommutesWithReduction =
     and [ opFrameEq (app (h t) a) (app (h (G.nf t)) a) | t <- terms ]
  && any (\t -> t /= G.nf t) terms
  where
    a     = opF inventedFrame
    terms = [ G.I
            , G.App (G.App G.S G.K) G.K          -- SKK -> I
            , G.App (G.App G.K G.I) G.S          -- KIS -> I
            ]

-- | Consolidation: the combinator images h I / h K / h S, applied to native frame atoms, act as
--   the native operators gI / gK / gS (identity / discard / invent).
lawCombinatorImagesActNatively :: Bool
lawCombinatorImagesActNatively =
     opFrameEq (app (h G.I) (opF coarse)) (opF coarse)
  && opFrameEq (app (app (h G.K) (opF coarse)) (opF inventedFrame)) (opF coarse)
  && opFrameEq (app (app (app (h G.S) (op2 anchorBlend)) (op1 invent)) (opF coarse))
               (opF inventedFrame)

-- ===========================================================================
-- (3) Runner
-- ===========================================================================

laws :: [(String, Bool)]
laws =
  [ ("lawHomI                     (app (h I) a = a)",                       lawHomI)
  , ("lawHomK                     (h K = weakening, 2nd arg discarded)",    lawHomK)
  , ("lawSIsNativeInvention       (native invention = image of S)",         lawSIsNativeInvention)
  , ("lawSKKIsIdentity            (SKK = I, native identity)",              lawSKKIsIdentity)
  , ("lawHomCommutesWithReduction (reduce-then-interp = interp-then-reduce)", lawHomCommutesWithReduction)
  , ("lawCombinatorImagesActNatively (h I/K/S act as gI/gK/gS on frames)",  lawCombinatorImagesActNatively)
  ]

main :: IO ()
main = do
  putStrLn "V2SkiHomomorphism.hs  -- EXPLORATION (NOT WIRED): Comb -> GIF homomorphism, S closed"
  putStrLn (replicate 72 '-')
  mapM_ (\(n, ok) -> putStrLn (verdict ok ++ "  " ++ n)) laws
  putStrLn (replicate 72 '-')
  let passed = length (filter snd laws)
      total  = length laws
  putStrLn ("SUMMARY: " ++ show passed ++ "/" ++ show total ++ " laws PASS"
            ++ if passed == total then "  (all green)" else "  (FAILURES present)")
  putStrLn ""
  putStrLn "HONEST NOTE: h is the standard interpretation of untyped combinators into a"
  putStrLn "universal domain; it is a homomorphism (preserves application) by construction and"
  putStrLn "so preserves the S/K/I reduction rules. The content is that native GIF89a invention"
  putStrLn "is EXACTLY h applied to the S-term. This CLOSES the open homomorphism for S, the"
  putStrLn "precondition for using SKI in training. Still NOT claimed: that the whole codec is an"
  putStrLn "SKI program (only the S/K/I fragment is realized natively here)."
  where
    verdict True  = "PASS"
    verdict False = "FAIL"
