{- |
Module      : SixFour.Spec.Layer
Description : The look-NN's layers as a typeclass — type-checked composition + bound laws.

This is the design surface for the look-NN (the tool that replaces the prose
@spec/NN_DESIGN_MATRIX.md@ A/B matrix): each layer of the dataflow is a
'Layer' **typeclass instance** whose @In@/@Out@ associated types /are/ its
dimensional contract, and whose semantic obligations are law predicates bound
to it. Two things follow that the value-level @LookNet.lookNetLayers@ table
could not give:

  1. **Composition is checked by the compiler.** The 'Pipe' GADT's @(':>>')@
     constructor demands @Pipe (Out l) b@, so a layer whose output type does not
     match the next layer's input type /does not compile/. (Compare
     @Properties.LookNet.chainComposes@, which checks @lsOutDim == lsInDim@ at
     /runtime/ over @[LayerSpec]@ — this lifts that check to the type level.)
  2. **Verification is bound to the layer.** Each layer's laws are predicates
     here, QuickCheck'd uniformly in @Properties.Layer@.

The substrate is the continuous OKLab Gaussian mixture ("SixFour.Spec.GMM").
The deterministic layers wrap the existing total reference functions from
"SixFour.Spec.LookNet" / "SixFour.Spec.PairTree". The learnable region L3–L5 is
the committed **Path-B core** ("SixFour.Spec.LookCore"): @reconstruct(floor ⊕
s·tanh(residual))@. Its /reference inhabitant/ is the zero-residual case — the
Wasserstein-2 / k-means floor ('SixFour.Spec.LookNet.baselinePalette'), a total
function (no stubs). The Phase-C trainer supplies the bounded residual; the laws
in "SixFour.Spec.LookCore" already prove that it cannot break the contract.

>  CyclicStack t k ──[Pool]──▶ GMM                         (L1–L2, det)
>  CyclicStack t k ──[LookCore]──▶ HaarPalette             (L3–L5, learn; ref = floor)
>  HaarPalette     ──[Reconstruct]──▶ [OKLab] (256 leaves) (L6, det)
>  LookInput t h w k ──[WholeLookNet]──▶ LookOutput t h w k (the whole GIF)
-}
module SixFour.Spec.Layer
  ( -- * The layer typeclass
    Layer(..)
    -- * Type-checked composition
  , Pipe(..)
  , runPipe
  , pipeSpec
    -- * The look-NN's layers (typed instances)
  , Pool(..)
  , LookCore(..)
  , Reconstruct(..)
  , WholeLookNet(..)
    -- * Ready-made pipelines
  , palettePipe
  , runWholeLookNet
    -- * Laws (predicates; QuickCheck'd in Properties.Layer)
  , lawPipeMatchesManual
  , lawPaletteHasKLeaves
  , lawFloorBalanced
  , lawPoolWeightNormalised
  , lawLayerNeutralResidualIsFloor
  ) where

import Data.Kind    (Type)
import Data.Proxy   (Proxy(..))
import GHC.TypeLits (Nat, KnownNat, natVal)

import SixFour.Spec.Color    (OKLab(..))
import SixFour.Spec.Cyclic   (CyclicStack)
import SixFour.Spec.GMM      (GMM, totalWeight)
import SixFour.Spec.PairTree (HaarPalette, reconstruct, lawBalancedMean)
import SixFour.Spec.LookCore (lookFloor, applyLookCore, lookCoreScale, zeroResidualLike)
import SixFour.Spec.LookNet
  ( LayerKind(..)
  , LookInput(..), LookOutput(..)
  , runLookNet, baselinePalette, poolToGMM
  )

-- ----------------------------------------------------------------------------
-- The typeclass
-- ----------------------------------------------------------------------------

-- | A layer of the look-NN dataflow: a typed transform with a kind tag. The
-- associated @In@/@Out@ types are the layer's dimensional contract — making
-- them type families is what lets 'Pipe' reject mismatched compositions at
-- compile time.
class Layer l where
  -- | The input type the layer consumes.
  type In  l :: Type
  -- | The output type the layer produces.
  type Out l :: Type
  -- | Run the layer. For deterministic layers this is the total reference
  -- function; for the learnable region it is the verified floor inhabitant.
  runLayer  :: l -> In l -> Out l
  -- | A human-readable name (mirrors @LookNet.lsName@).
  layerName :: l -> String
  -- | Deterministic reference vs. learnable block (mirrors @LookNet.lsKind@).
  layerKind :: l -> LayerKind

-- ----------------------------------------------------------------------------
-- Type-checked composition
-- ----------------------------------------------------------------------------

-- | A pipeline from @a@ to @b@, built from 'Layer's. @(':>>')@ can only attach a
-- layer @l@ whose @Out l@ matches the rest of the pipe's input — so an
-- ill-typed composition is a /type error/, not a runtime failure. This is the
-- type-level form of @LookNet.paletteChain@ \/ @indexChain@.
data Pipe (a :: Type) (b :: Type) where
  Done  :: Pipe a a
  (:>>) :: Layer l => l -> Pipe (Out l) b -> Pipe (In l) b

infixr 5 :>>

-- | Execute a pipeline left-to-right.
runPipe :: Pipe a b -> a -> b
runPipe Done          = id
runPipe (l :>> rest)  = runPipe rest . runLayer l

-- | The ordered @(name, kind)@ of every layer in a pipeline — the typed
-- composition surfaced as an inspectable artifact (cf. the value-level
-- @LookNet.lookNetLayers@ table). The layer types are existential inside the
-- GADT, but the 'Layer' dictionary travels with each one.
pipeSpec :: Pipe a b -> [(String, LayerKind)]
pipeSpec Done         = []
pipeSpec (l :>> rest) = (layerName l, layerKind l) : pipeSpec rest

-- ----------------------------------------------------------------------------
-- The look-NN's layers, as typed instances
-- ----------------------------------------------------------------------------

-- | L1–L2: pool the @T@ per-frame palettes into one renormalised OKLab Gaussian
-- mixture — the continuous, category-free substrate the set encoder consumes.
data Pool (t :: Nat) (k :: Nat) = Pool

instance Layer (Pool t k) where
  type In  (Pool t k) = CyclicStack t k
  type Out (Pool t k) = GMM
  runLayer _  = poolToGMM
  layerName _ = "L1-L2 Pool -> GMM"
  layerKind _ = Deterministic

-- | L3–L5: the learnable core ("SixFour.Spec.LookCore", Path B). It carries the
-- look residual the trainer produces: @output = floor ⊕ s·tanh(residual)@. The
-- residual is a Haar-shaped delta on the floor; @LookCore Nothing@ is the
-- neutral / reference inhabitant = the Wasserstein-2 \/ k-means floor
-- ('lookFloor'), a total function (no stub). Because the residual is a /field/,
-- the /trained/ net composes through this same typeclass — and the @LookCore@
-- laws prove it stays neutral-reset, bounded, and σ-equivariant for any residual.
newtype LookCore (t :: Nat) (k :: Nat) = LookCore (Maybe HaarPalette)

instance KnownNat k => Layer (LookCore t k) where
  type In  (LookCore t k) = CyclicStack t k
  type Out (LookCore t k) = HaarPalette
  runLayer (LookCore mResidual) stk =
    let fl = lookFloor stk
    in maybe fl (applyLookCore lookCoreScale fl) mResidual
  layerName _ = "L3-L5 LookCore (floor + s.tanh residual)"
  layerKind _ = Learnable

-- | L6: inverse Haar transform — expand the tree into its @2^depth@ OKLab leaves
-- (the global palette). For a depth-8 tree this is the 256-colour palette.
data Reconstruct = Reconstruct

instance Layer Reconstruct where
  type In  Reconstruct = HaarPalette
  type Out Reconstruct = [OKLab]
  runLayer _  = reconstruct
  layerName _ = "L6 Reconstruct (inverse Haar -> leaves)"
  layerKind _ = Deterministic

-- | The whole net as a single 'Layer': @LookInput → LookOutput@ — the headline
-- "64 palettes + 64 index maps → global palette + global index map." Its
-- reference inhabitant builds the palette from the floor ('baselinePalette') and
-- runs the deterministic L6–L8 scaffold ('runLookNet'); the global-surjectivity
-- witness rides along in the output.
data WholeLookNet (t :: Nat) (h :: Nat) (w :: Nat) (k :: Nat) = WholeLookNet

instance (KnownNat t, KnownNat h, KnownNat w, KnownNat k)
      => Layer (WholeLookNet t h w k) where
  type In  (WholeLookNet t h w k) = LookInput  t h w k
  type Out (WholeLookNet t h w k) = LookOutput t h w k
  runLayer _ inp = runLookNet (baselinePalette (liStack inp)) inp
  layerName _ = "look-NN (LookInput -> LookOutput)"
  layerKind _ = Learnable

-- ----------------------------------------------------------------------------
-- Ready-made pipelines
-- ----------------------------------------------------------------------------

-- | The palette path as a compile-time-checked pipeline:
-- @CyclicStack t k → HaarPalette → [OKLab]@. The @In@/@Out@ types line up by
-- construction; swapping a stage whose types do not match will not compile.
-- (Type-family non-injectivity means the nullary layers need their @t k@
-- pinned by annotation.)
palettePipe :: forall t k. KnownNat k => Pipe (CyclicStack t k) [OKLab]
palettePipe = (LookCore Nothing :: LookCore t k) :>> Reconstruct :>> Done

-- | Run the whole look-NN via its 'Layer' instance.
runWholeLookNet
  :: forall t h w k. (KnownNat t, KnownNat h, KnownNat w, KnownNat k)
  => LookInput t h w k -> LookOutput t h w k
runWholeLookNet = runLayer (WholeLookNet :: WholeLookNet t h w k)

-- ----------------------------------------------------------------------------
-- Laws (predicates; QuickCheck'd in Properties.Layer)
-- ----------------------------------------------------------------------------

-- | The typed pipeline computes exactly the hand-written composition — i.e.
-- 'runPipe' faithfully threads the layers (no reordering, no dropped stage).
lawPipeMatchesManual :: forall t k. KnownNat k => CyclicStack t k -> Bool
lawPipeMatchesManual stk =
  runPipe (palettePipe @t @k) stk == (reconstruct . lookFloor) stk

-- | The palette path yields exactly @K@ leaves (the floor collapses to @K@
-- colours and the depth-@log₂K@ tree reconstructs to @2^depth = K@).
lawPaletteHasKLeaves :: forall t k. KnownNat k => CyclicStack t k -> Bool
lawPaletteHasKLeaves stk =
  let kk = fromIntegral (natVal (Proxy :: Proxy k)) :: Int
  in length (runPipe (palettePipe @t @k) stk) == kk

-- | The floor palette is balanced: the mean of its leaves equals the root (the
-- σ-mirror offsets cancel). Reuses 'SixFour.Spec.PairTree.lawBalancedMean'.
lawFloorBalanced :: forall t k. KnownNat k => Double -> CyclicStack t k -> Bool
lawFloorBalanced tol stk = lawBalancedMean tol (lookFloor stk)

-- | L1–L2 renormalises the pooled mixture to total weight 1 (when the input
-- carries positive weight) — the pooled measure is a probability measure.
lawPoolWeightNormalised :: forall t k. Double -> CyclicStack t k -> Bool
lawPoolWeightNormalised tol stk =
  let gmm = runLayer (Pool :: Pool t k) stk
      w   = totalWeight gmm
  in w <= 0 || abs (w - 1) <= tol

-- | Neutral reset through the typed layer: a zero residual (@Just 0@) produces
-- exactly the floor (@Nothing@). This lifts 'SixFour.Spec.LookCore.lawNeutralIsFloor'
-- onto the 'LookCore' 'Layer' instance — the "no look" code is the floor.
lawLayerNeutralResidualIsFloor :: forall t k. KnownNat k => CyclicStack t k -> Bool
lawLayerNeutralResidualIsFloor stk =
  let fl   = lookFloor stk
      zero = LookCore (Just (zeroResidualLike fl)) :: LookCore t k
  in runLayer zero stk == runLayer (LookCore Nothing :: LookCore t k) stk
