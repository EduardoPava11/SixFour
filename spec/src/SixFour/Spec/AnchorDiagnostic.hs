{- |
Module      : SixFour.Spec.AnchorDiagnostic
Description : Experiment #1 of the L-anchor model review, made a THEOREM: per-channel detail-signal measured through the TWO mathematical lenses the owner asked for, each as a typeclass instance. 'ChannelDetail' is one interface, @channelEnergy@, with two instances: the L channel is scored by DISCRETE GEOMETRY (the @d6@\/@ℓ¹@ lattice norm of "SixFour.Spec.MetricLattice", the model's own taxicab metric) and the chroma channel by ALGEBRAIC NUMBER THEORY (the @ℤ[i]@ Gaussian field norm of "SixFour.Spec.GaussianChroma"). A channel's energy is @0@ exactly when its octant detail sits at the root-lattice floor (no learnable detail; the detail kernel is the constants, "SixFour.Spec.RootLatticeDetail" @lawDetailKernelIsConstants@).

THE QUESTION under review: does anchoring the JEPA target on L (the trainer feeds only L, with a=b=0,
@train_loop.palette_target@) discard real signal? THE ANSWER, as a constructed witness: YES, for
ISO-LUMINANT CHROMATIC scenes. 'lawIsoLuminantSignalIsInChromaRingNotL' exhibits a constant-L,
varying-chroma octant whose entire detail signal lives in the @ℤ[i]@ chroma ring while the L channel
(all the trainer ever sees) is at the lattice floor. So an L-only target is provably BLIND to such a
scene. The contrast laws pin the other regimes: a luma ramp is L-signal (L-anchoring is right there),
a flat scene floors every channel (then the data engine, not the anchor, is the problem).

HONEST BOUNDARY (doc, not law): this PROVES the failure mode EXISTS as a witness scene-kind; it does
NOT measure how common iso-luminant chromatic octants are in the shipped synthetic corpus
(@trainer/mlx/synth_capture.py@). That frequency is the empirical follow-up. What is settled here:
IF such a scene occurs, L-anchoring sees the floor and the signal is in the chroma ring the head
never emits. Pure-spec, emits no golden.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.AnchorDiagnostic
  ( -- * The two-lens channel-energy interface
    ChannelDetail(..)
  , LDetail(..)
  , ChromaDetail(..)
    -- * Octant detail of a channel (via the frozen liftOct)
  , octDetailL
  , octDetailChroma
    -- * Witness scenes
  , SceneKind(..)
  , scene
  , lEnergyOf
  , chromaEnergyOf
    -- * Laws
  , lawIsoLuminantSignalIsInChromaRingNotL
  , lawLumaRampSignalIsInL
  , lawFlatSceneFloorsAllChannels
  , lawHighFreqLightsAllChannels
  , lawConstantChannelIsLatticeFloor
  ) where

import SixFour.Spec.OctreeCell      (V8(..), liftOct, OctBand(..), detailToList)
import SixFour.Spec.MetricLattice   (NormP(..), norm)
import SixFour.Spec.RefinementSystem (Gaussian(..))
import SixFour.Spec.GaussianChroma  (gaussNorm)

-- | ONE interface, the per-channel detail ENERGY, with a DIFFERENT mathematical lens per channel.
-- @channelEnergy x == 0@ means the channel's octant detail is at the root-lattice floor: nothing for
-- a masked-band predictor to learn (the zero floor already fits). The two instances are the two
-- lenses of the review: a lattice (discrete geometry) and a ring of integers (algebraic number theory).
class ChannelDetail c where
  channelEnergy :: c -> Integer

-- | The L (lightness) channel's seven detail bands, scored by DISCRETE GEOMETRY: the @ℓ¹@ / taxicab
-- @d6@ lattice norm ("SixFour.Spec.MetricLattice"), the metric the model actually runs (@p = 1@).
newtype LDetail = LDetail [Integer] deriving (Eq, Show)

instance ChannelDetail LDetail where
  channelEnergy (LDetail ds) = norm L1 ds

-- | The chroma channel's seven detail bands as GAUSSIAN INTEGERS @a + b·i@, scored by ALGEBRAIC
-- NUMBER THEORY: the sum of @ℤ[i]@ field norms @a² + b²@ ("SixFour.Spec.GaussianChroma" @gaussNorm@).
-- One band contributes zero iff BOTH its a- and b-detail vanish, so chroma energy sees signal in
-- either chroma axis (the hue plane), which an L-only target cannot.
newtype ChromaDetail = ChromaDetail [Gaussian] deriving (Eq, Show)

instance ChannelDetail ChromaDetail where
  channelEnergy (ChromaDetail gs) = sum (map gaussNorm gs)

-- | The L detail of a channel's eight octant voxels: lift, take the seven detail bands. Reuses the
-- frozen byte-exact 'liftOct' unchanged.
octDetailL :: V8 Int -> LDetail
octDetailL v = LDetail (map fromIntegral (detailToList (ocDetail (liftOct v))))

-- | The chroma detail of an octant from its a- and b-channel voxels: lift each, pair the per-band
-- details into Gaussian integers @(a_k, b_k)@.
octDetailChroma :: V8 Int -> V8 Int -> ChromaDetail
octDetailChroma av bv =
  let da = detailToList (ocDetail (liftOct av))
      db = detailToList (ocDetail (liftOct bv))
  in ChromaDetail (zipWith (\a b -> Gaussian (fromIntegral a, fromIntegral b)) da db)

-- ---------------------------------------------------------------------------
-- Witness scenes (one octant per kind): (L voxels, a voxels, b voxels).
-- ---------------------------------------------------------------------------

-- | The scene regimes the diagnostic separates.
data SceneKind = Flat | LumaRamp | IsoLuminantChroma | HighFreq
  deriving (Eq, Show, Enum, Bounded)

-- | An octant's three channels for a scene kind.
scene :: SceneKind -> (V8 Int, V8 Int, V8 Int)
scene Flat              = (constV8 50, constV8 5, constV8 5)
scene LumaRamp          = (listV8 [0, 16, 32, 48, 64, 80, 96, 112], constV8 10, constV8 10)
scene IsoLuminantChroma = (constV8 50,
                           listV8 [0, 30, 0, 30, 0, 30, 0, 30],
                           listV8 [20, 0, 20, 0, 20, 0, 20, 0])
scene HighFreq          = (listV8 [10, 40, 12, 38, 8, 44, 6, 46],
                           listV8 [5, 25, 7, 23, 9, 21, 3, 27],
                           listV8 [15, 2, 17, 4, 13, 6, 19, 1])

-- | The L-channel detail energy of a scene (discrete-geometry lattice norm).
lEnergyOf :: SceneKind -> Integer
lEnergyOf k = let (lv, _, _) = scene k in channelEnergy (octDetailL lv)

-- | The chroma-channel detail energy of a scene (algebraic-number-theory Gaussian norm).
chromaEnergyOf :: SceneKind -> Integer
chromaEnergyOf k = let (_, av, bv) = scene k in channelEnergy (octDetailChroma av bv)

constV8 :: Int -> V8 Int
constV8 c = V8 c c c c c c c c

listV8 :: [Int] -> V8 Int
listV8 xs = case take 8 (xs ++ repeat 0) of
  (a : b : c : d : e : f : g : h : _) -> V8 a b c d e f g h
  _                                    -> V8 0 0 0 0 0 0 0 0

-- ---------------------------------------------------------------------------
-- Laws (the diagnostic verdict, made non-vacuous by the witness scenes).
-- ---------------------------------------------------------------------------

-- | THE KEYSTONE: an ISO-LUMINANT CHROMATIC octant (constant L, varying a\/b) has its entire detail
-- signal in the @ℤ[i]@ chroma ring while the L channel sits at the lattice floor. So the L-only
-- training target ("anchor on L", @palette_target@ with a=b=0) is provably BLIND to this scene's
-- signal. This is the structural reason the masked-band head can sit at the zero floor: the channel
-- it anchors on is the empty one. Teeth: a non-trivial L energy here, or zero chroma energy, fails.
lawIsoLuminantSignalIsInChromaRingNotL :: Bool
lawIsoLuminantSignalIsInChromaRingNotL =
  lEnergyOf IsoLuminantChroma == 0 && chromaEnergyOf IsoLuminantChroma > 0

-- | The regime L-anchoring gets RIGHT: a luma ramp (varying L, constant chroma) carries its signal
-- in L, with chroma at the floor. So L-anchoring is not always wrong; it is right exactly when the
-- structure is luminance, which is the steelman's natural-image case.
lawLumaRampSignalIsInL :: Bool
lawLumaRampSignalIsInL =
  lEnergyOf LumaRamp > 0 && chromaEnergyOf LumaRamp == 0

-- | The DATA-ENGINE-is-the-problem regime: a flat octant floors EVERY channel, so no choice of
-- anchor helps. Distinguishes "anchor is mis-targeted" from "the scene has no signal at all".
lawFlatSceneFloorsAllChannels :: Bool
lawFlatSceneFloorsAllChannels =
  lEnergyOf Flat == 0 && chromaEnergyOf Flat == 0

-- | A high-frequency octant lights BOTH lenses: real L energy and real chroma energy. The healthy
-- regime where a symmetric (per-channel) target would have signal in every channel.
lawHighFreqLightsAllChannels :: Bool
lawHighFreqLightsAllChannels =
  lEnergyOf HighFreq > 0 && chromaEnergyOf HighFreq > 0

-- | Why "L at floor" is FORCED on any iso-luminant scene: a constant channel lifts to zero detail
-- (its detail is the kernel of the lift, the constants, "SixFour.Spec.RootLatticeDetail"
-- @lawDetailKernelIsConstants@). So whenever L is constant, the L anchor sees the floor by theorem,
-- not by accident. Quantified over every constant value.
lawConstantChannelIsLatticeFloor :: Int -> Bool
lawConstantChannelIsLatticeFloor c = channelEnergy (octDetailL (constV8 c)) == 0
