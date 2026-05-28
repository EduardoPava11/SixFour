{-# LANGUAGE AllowAmbiguousTypes        #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE TypeOperators              #-}
{-# LANGUAGE UndecidableInstances       #-}

{- |
Module      : SixFour.Spec.Pipeline
Description : Type-class framework for the look-NN pipeline + per-option type aliases.

The look-NN's algebraic structure expressed in Haskell. A 'Stage' is a typed
transformation @In tag -> Out tag@; 'SigmaEquivariant' upgrades a stage to one
that commutes with the chroma involution σ; 'SigmaSymmetricRange' upgrades it
further to one whose image lies in the σ-symmetric eigenspace.

Composition @g :> f@ ("f then g") DERIVES the constraints from its parts:

    instance (SigmaEquivariant f, SigmaEquivariant g, In g ~ Out f)
          => SigmaEquivariant (g :> f)

So a pipeline is @SigmaEquivariant@ iff every stage in the composition is. This
is the mechanical version of the markdown claim in the plan's §A.2: it is the
type-checker, not the human, that certifies "Option 4 is σ-equivariant end-to-end".

== What's encoded here

* The committed deterministic stages (Bin16, SymSelect, Quad4ReconAchroma) are
  classified — each carries the highest class instance that its math permits.
* PairTreeRecon and Quad4Recon are 'Stage' only — they do NOT derive
  'SigmaEquivariant' in general (would require a specific input structure).
* 'AchromaticQuad4' is the @Quad4Palette@ subtype with @root.a = root.b = 0@;
  'Quad4ReconAchroma' acts on it and IS 'SigmaEquivariant' by construction
  (the achromatic root is σ-fixed; chromatic offsets carry σ-equivariance).
* Each of the five unification options of the plan (§A.2) is given a type alias
  parameterised over its learned middle @m@.
* The composition theorem ('option4Theorem') is the central artefact: it
  type-checks iff Option 4's pipeline is 'SigmaEquivariant' (under the
  hypothesis that the learned middle @m@ is also σ-equivariant — a training
  obligation, not an algebraic one).

== What's NOT encoded

The learned stages (Encoder, Core, Decoder) are not given a runtime
implementation — they are postulated. Their σ-equivariance is a training
target the gradient loop must enforce; here we only express the conditional
("IF training succeeds, THEN the whole pipeline is σ-equivariant").

Laws (see @Properties.Pipeline@):
  * 'lawSigmaEquivariant' holds for Bin16, SymSelect, Quad4ReconAchroma.
  * 'lawSigmaSymmetricRange' holds for SymSelect.
  * @once@ property: 'option4Theorem' compiles ⇒ Pipeline4Boundary is σ-eq.
-}
module SixFour.Spec.Pipeline
  ( -- * The classes
    Stage(..)
  , SigmaEquivariant(..)
  , SigmaSymmetricRange
  , Lipschitz(..)
    -- * Composition
  , (:>)
    -- * Concrete stages (classified)
  , Bin16
  , SymSelect
  , PairTreeRecon
  , Quad4Recon
  , Quad4ReconAchroma
    -- * The σ action on histogram vectors (exported for friend modules)
  , sigmaApplyVec
    -- * The achromatic-root subtype
  , AchromaticQuad4(..)
  , mkAchromaticQuad4
  , projectAchromaticQuad4
    -- * Per-option pipeline type aliases
  , Pipeline1
  , Pipeline2
  , Pipeline3
  , Pipeline4
  , Pipeline4Boundary
    -- * Mechanical proofs
  , option4Theorem
  , SigmaEquivariantDict(..)
  , SigmaSymmetricRangeDict(..)
    -- * Law predicates (run by QuickCheck in Properties.Pipeline)
  , lawSigmaEquivariant
  , lawSigmaSymmetricRange
  ) where

import           Data.Kind             (Type)
import           Data.Proxy            (Proxy(..))
import qualified Data.Vector.Unboxed   as U

import SixFour.Spec.Bottleneck16  ( Histogram4096(..)
                                  , histogramFromOKLabs )
import SixFour.Spec.Color         (OKLab(..))
import SixFour.Spec.PairTree      ( HaarPalette
                                  , sigmaReflect )
import qualified SixFour.Spec.PairTree as PT
import qualified SixFour.Spec.Quad4    as Q4
import SixFour.Spec.Quad4         (Quad4Palette(..))
import SixFour.Spec.SigmaDecomp   (sigmaBinPerm, symPart)

-- =============================================================================
-- The classes
-- =============================================================================

-- | A pipeline stage. Tagged at the type level; the value-level transformation
-- is @step \@tag :: In tag -> Out tag@.
class Stage tag where
  type In  tag :: Type
  type Out tag :: Type
  step :: In tag -> Out tag

-- | A stage that commutes with the σ involution on its input and output types.
--
-- Law @lawSigmaEquivariant@: @step \@tag . sigmaIn \@tag === sigmaOut \@tag . step \@tag@.
class Stage tag => SigmaEquivariant tag where
  sigmaIn  :: In  tag -> In  tag
  sigmaOut :: Out tag -> Out tag

-- | A stage whose output lies in the σ-symmetric eigenspace.
--
-- Law @lawSigmaSymmetricRange@: @sigmaOut \@tag (step \@tag x) === step \@tag x@.
class SigmaEquivariant tag => SigmaSymmetricRange tag

-- | Stage with a known Lipschitz constant — the bounded-effect law L2
-- (@LookNet.hs@) encoded in the type system.
class Stage tag => Lipschitz tag where
  lipConstant :: Double

-- =============================================================================
-- Composition: "g :> f" means "f, then g"
-- =============================================================================

-- | Type-level composition. There are no values of this type — it is a tag
-- whose instances are derived from the instances of its parts.
data g :> f
infixr 5 :>

instance (Stage f, Stage g, In g ~ Out f) => Stage (g :> f) where
  type In  (g :> f) = In  f
  type Out (g :> f) = Out g
  step x = step @g (step @f x)

instance ( SigmaEquivariant f
         , SigmaEquivariant g
         , In g ~ Out f
         )
      => SigmaEquivariant (g :> f) where
  sigmaIn  = sigmaIn  @f
  sigmaOut = sigmaOut @g

-- The σ-symmetric-range property at the *output* of the composition follows
-- from the σ-symmetric-range property at the *output stage* (g), provided f
-- preserves the σ-action so the law can travel through it.
instance ( SigmaEquivariant f
         , SigmaSymmetricRange g
         , In g ~ Out f
         )
      => SigmaSymmetricRange (g :> f)

-- =============================================================================
-- Concrete stages — each tagged by an empty data type
-- =============================================================================

-- | The σ involution applied to a histogram vector, by index permutation.
-- Public because the SigmaEquivariant instances of 'Bin16' and 'SymSelect'
-- both need it, and it is exact (a permutation, not floating arithmetic).
sigmaApplyVec :: U.Vector Double -> U.Vector Double
sigmaApplyVec v = U.generate (U.length v) (\i -> v U.! sigmaBinPerm i)

-- | Bin a list of OKLab samples into a 4096-bin probability simplex. Commits
-- to the same @okLabBin@ that 'SixFour.Spec.Coverage' scores against.
data Bin16

instance Stage Bin16 where
  type In  Bin16 = [OKLab]
  type Out Bin16 = Histogram4096
  step = histogramFromOKLabs

-- σ on the input is element-wise 'sigmaReflect'; σ on the output is the bin
-- permutation 'sigmaApplyVec'. The equivariance follows from the
-- quantisation-commutativity law of 'SixFour.Spec.Bottleneck16'.
instance SigmaEquivariant Bin16 where
  sigmaIn  = map sigmaReflect
  sigmaOut (Histogram4096 v) = Histogram4096 (sigmaApplyVec v)

-- | Project a histogram onto its σ-symmetric eigenspace.
data SymSelect

instance Stage SymSelect where
  type In  SymSelect = Histogram4096
  type Out SymSelect = Histogram4096
  step = symPart

-- σ acts as the bin permutation on both sides. The law holds because @symPart@
-- is the @½(H + σH)@ averaging — it commutes with σ exactly.
instance SigmaEquivariant SymSelect where
  sigmaIn  (Histogram4096 v) = Histogram4096 (sigmaApplyVec v)
  sigmaOut (Histogram4096 v) = Histogram4096 (sigmaApplyVec v)

-- The whole point of 'symPart': its image is fixed by σ.
instance SigmaSymmetricRange SymSelect

-- | Binary Haar PairTree reconstruction. NOT 'SigmaEquivariant' in general —
-- the σ-equivariance of the palette set requires an achromatic root + the
-- offsets to be chromatic-pure, neither of which the 'HaarPalette' type
-- enforces. We intentionally do not provide an instance here.
data PairTreeRecon

instance Stage PairTreeRecon where
  type In  PairTreeRecon = HaarPalette
  type Out PairTreeRecon = [OKLab]
  step = PT.reconstruct

-- | 4-ary 'Quad4Palette' reconstruction. Same caveat as 'PairTreeRecon': not
-- σ-equivariant on the full Quad4Palette type. The σ-equivariance instance
-- lives on the 'AchromaticQuad4' subtype below.
data Quad4Recon

instance Stage Quad4Recon where
  type In  Quad4Recon = Quad4Palette
  type Out Quad4Recon = [OKLab]
  step = Q4.reconstruct

-- =============================================================================
-- AchromaticQuad4 — the subtype that makes σ-equivariance algebraic
-- =============================================================================

-- | A 'Quad4Palette' whose root lies on the achromatic L-axis (root.a =
-- root.b = 0). For such trees, σ acts on the root as the identity (σ-fixed),
-- so the σ-action on children reduces to the σ-action on the offsets — and
-- 'Quad4ReconAchroma' becomes algebraically σ-equivariant. The smart
-- constructor enforces the constraint; the projecting constructor zeroes the
-- chromatic root components.
newtype AchromaticQuad4 = AchromaticQuad4 { unAchromaticQuad4 :: Quad4Palette }
  deriving (Eq, Show)

-- | Promote a 'Quad4Palette' to 'AchromaticQuad4' if its root is achromatic
-- (root.a = root.b = 0 exactly). Returns 'Nothing' otherwise.
mkAchromaticQuad4 :: Quad4Palette -> Maybe AchromaticQuad4
mkAchromaticQuad4 qp@(Quad4Palette (OKLab _ a b) _)
  | a == 0 && b == 0 = Just (AchromaticQuad4 qp)
  | otherwise        = Nothing

-- | Project any 'Quad4Palette' into 'AchromaticQuad4' by zeroing the chromatic
-- root components. Always succeeds; useful for testing and for the v1 ES
-- search that wants to operate inside the achromatic-root constraint.
projectAchromaticQuad4 :: Quad4Palette -> AchromaticQuad4
projectAchromaticQuad4 (Quad4Palette (OKLab l _ _) lvls) =
  AchromaticQuad4 (Quad4Palette (OKLab l 0 0) lvls)

-- | 'Quad4Recon' on 'AchromaticQuad4'. Universally σ-equivariant.
data Quad4ReconAchroma

instance Stage Quad4ReconAchroma where
  type In  Quad4ReconAchroma = AchromaticQuad4
  type Out Quad4ReconAchroma = [OKLab]
  step (AchromaticQuad4 qp) = Q4.reconstruct qp

-- σ on the AchromaticQuad4 input: leave the (achromatic, σ-fixed) root alone,
-- and reflect every offset. σ on the output: per-leaf reflection. The law
-- @lawSigmaEquivariance@ already proves this for 'Q4.reconstruct' on a
-- transformed Quad4Palette where the root is σ-fixed (which the achromatic
-- subtype guarantees algebraically — see @Properties.Pipeline@).
instance SigmaEquivariant Quad4ReconAchroma where
  sigmaIn (AchromaticQuad4 (Quad4Palette rt lvls)) =
    AchromaticQuad4 (Quad4Palette rt
      [ [ (sigmaReflect d1, sigmaReflect d2) | (d1, d2) <- lvl ] | lvl <- lvls ])
  sigmaOut = map sigmaReflect

-- =============================================================================
-- Per-option pipeline type aliases (the 5 unification options from §A.2)
-- =============================================================================
--
-- Each pipeline is parameterised over its learned middle @m@. The learned
-- stages (Encoder, Core, Decoder) carry no algebraic σ-structure — they are
-- training-time obligations. Each alias names the type, and a comment near
-- its definition records the *highest* class instance the type derives,
-- given an appropriately-typed @m@.

-- | Option 1 — Loss-only. Forward path is identical to the existing pipeline;
-- σ-awareness lives entirely in the loss head (not modelled at this type
-- level). Even with @SigmaEquivariant m@, the final 'PairTreeRecon' kills the
-- end-to-end equivariance, so:
--   highest derivable class on the boundary: 'Stage'.
type Pipeline1 m = PairTreeRecon :> m

-- | Option 2 — Input-only. The encoder sees only @H_sym@; the decoder is the
-- binary PairTree (no algebraic σ-output). 'SymSelect' supplies the input-side
-- σ-symmetric guarantee but it does not propagate through 'PairTreeRecon'.
--   highest derivable class on the boundary: 'Stage'.
type Pipeline2 m = PairTreeRecon :> m :> SymSelect :> Bin16

-- | Option 3 — Output-only. The encoder sees the raw GMM tokens (modelled as
-- the learned @m@'s input); the decoder is 'Quad4ReconAchroma'. The output is
-- σ-symmetric by construction; the input is not σ-projected, so the
-- composition is 'SigmaSymmetricRange' iff @m@'s output is, but not
-- necessarily 'SigmaEquivariant' (no σ-projection on input).
type Pipeline3 m = Quad4ReconAchroma :> m

-- | Option 4 — Full σ-equivariant. Both ends are σ-equivariant; if @m@ is
-- 'SigmaEquivariant' (its σ commutes with σ on Histogram4096 and on
-- AchromaticQuad4), the WHOLE composition derives 'SigmaEquivariant' AND
-- 'SigmaSymmetricRange'. This is the unique option where the unification of
-- the three primitives is algebraic, not learned.
type Pipeline4 m = Quad4ReconAchroma :> m :> SymSelect :> Bin16

-- | The /deterministic boundary/ of Option 4 — the pipeline with the learned
-- middle removed, used to demonstrate that the boundary alone composes its
-- σ-classes mechanically. (Composing 'Bin16' :> 'SymSelect' shows σ-action
-- carries from samples through the histogram into the σ-symmetric subspace;
-- 'Quad4ReconAchroma' on its own shows the output boundary; the learned
-- middle 'm' is what glues them.)
type Pipeline4Boundary = SymSelect :> Bin16

-- =============================================================================
-- The Option 4 composition theorem — a type-level proof
-- =============================================================================

-- | The Option 4 composition theorem.
--
-- @
-- Given a learned middle @m@ that is 'SigmaEquivariant' on the boundary
-- types — @In m ~ Histogram4096@, @Out m ~ AchromaticQuad4@ — the full
-- Option 4 pipeline is 'SigmaEquivariant'.
-- @
--
-- The proof is the type signature: if GHC accepts it, the instance composes.
-- The body is @()@ — the theorem is purely about typeability.
--
-- == Why not 'SigmaSymmetricRange' for 'Pipeline4'
--
-- The output type of 'Pipeline4' is @[OKLab]@ — a *list* representation of
-- the palette. The σ-action on this list is pointwise reflection
-- @map sigmaReflect@, and a σ-pair palette's leaves are NOT individually
-- σ-fixed (they pair up under σ rather than being fixed by it). So the
-- output, while it is the σ-image of itself under a leaf permutation, is
-- NOT in the σ-symmetric eigenspace of the pointwise action — the
-- 'SigmaSymmetricRange' law @sigmaOut (step x) ≡ step x@ does not hold.
--
-- The 'SigmaSymmetricRange' guarantee lives at 'Pipeline4Boundary' instead,
-- whose output type is 'Histogram4096' and whose image is exactly the
-- σ-symmetric histogram subspace by construction.
option4Theorem
  :: forall m
   . ( SigmaEquivariant m
     , In  m ~ Histogram4096
     , Out m ~ AchromaticQuad4
     )
  => Proxy (Pipeline4 m)
  -> SigmaEquivariantDict (Pipeline4 m)
option4Theorem _ = SigmaEquivariantDict

-- | Zero-information runtime witness that 'SigmaEquivariant tag' holds.
data SigmaEquivariantDict tag where
  SigmaEquivariantDict :: SigmaEquivariant tag => SigmaEquivariantDict tag

-- | Zero-information runtime witness that 'SigmaSymmetricRange tag' holds.
data SigmaSymmetricRangeDict tag where
  SigmaSymmetricRangeDict :: SigmaSymmetricRange tag => SigmaSymmetricRangeDict tag

-- =============================================================================
-- Law predicates (run by QuickCheck in @Properties.Pipeline@)
-- =============================================================================

-- | @lawSigmaEquivariant \@tag@: σ-equivariance of @tag@ at sample point @x@.
-- The instance is parameterised over an @Eq (Out tag)@ context — for OKLab
-- and float-valued outputs the test must use @okClose@ etc.
lawSigmaEquivariant
  :: forall tag
   . (SigmaEquivariant tag, Eq (Out tag))
  => In tag -> Bool
lawSigmaEquivariant x =
  step @tag (sigmaIn @tag x) == sigmaOut @tag (step @tag x)

-- | @lawSigmaSymmetricRange \@tag@: σ-symmetric-range of @tag@ at sample @x@.
lawSigmaSymmetricRange
  :: forall tag
   . (SigmaSymmetricRange tag, Eq (Out tag))
  => In tag -> Bool
lawSigmaSymmetricRange x = sigmaOut @tag (step @tag x) == step @tag x
