module Main (main) where

import Test.Tasty

import qualified Properties.Color        as Color
import qualified Properties.ColorFixed   as ColorFixed
import qualified Properties.ZoneProfile  as ZoneProfile
import qualified Properties.LookTransfer as LookTransfer
import qualified Properties.RedFrontEnd  as RedFrontEnd
import qualified Properties.CubeLut      as CubeLut
import qualified Properties.Gauge        as Gauge
import qualified Properties.Surjectivity as Surj
import qualified Properties.Wu           as Wu
import qualified Properties.QuantFixed   as QuantFixed
import qualified Properties.Coverage     as Coverage
import qualified Properties.Collapse     as Collapse
import qualified Properties.Diversity    as Diversity
import qualified Properties.GMM          as GMM
import qualified Properties.Bures        as Bures
import qualified Properties.Sinkhorn     as Sinkhorn
import qualified Properties.Barycenter   as Barycenter
import qualified Properties.Entropy      as Entropy
import qualified Properties.RGBTFeature  as RGBTFeature
import qualified Properties.CubeLadder   as CubeLadder
import qualified Properties.VoxelReduce  as VoxelReduce
import qualified Properties.DivergenceSchedule as DivergenceSchedule
import qualified Properties.ABSurface    as ABSurface
import qualified Properties.GenomeCarrier as GenomeCarrier
import qualified Properties.PairTree     as PairTree
import qualified Properties.PairTreeFixed as PairTreeFixed
import qualified Properties.RGBTLift     as RGBTLift
import qualified Properties.OctreeCell   as OctreeCell
import qualified Properties.LadderIdentity as LadderIdentity
import qualified Properties.PerScaleWeights as PerScaleWeights
import qualified Properties.ScalePonder   as ScalePonder
import qualified Properties.XYTLabDuality as XYTLabDuality
import qualified Properties.LBalanceOperator as LBalanceOperator
import qualified Properties.OctreeGenome  as OctreeGenome
import qualified Properties.SubstrateDomain as SubstrateDomain
import qualified Properties.SuccessiveRefinement as SuccessiveRefinement
import qualified Properties.SuperResPalette as SuperResPalette
import qualified Properties.RelationalResidual as RelationalResidual
import qualified Properties.RemainderTail as RemainderTail
import qualified Properties.ByteCarrier   as ByteCarrier
import qualified Properties.DetailEntropy as DetailEntropy
import qualified Properties.DetailMaskedPrediction as DetailMaskedPrediction
import qualified Properties.MaskedBandPrediction as MaskedBandPrediction
import qualified Properties.MaskedBandTrainer as MaskedBandTrainer
import qualified Properties.DetailPredictor as DetailPredictor
import qualified Properties.Dim6          as Dim6
import qualified Properties.ProjectionOrdering as ProjectionOrdering
import qualified Properties.Dimensions    as Dimensions
import qualified Properties.OptionTree    as OptionTree
import qualified Properties.ChromaRotation as ChromaRotation
import qualified Properties.LatentNavigation as LatentNavigation
import qualified Properties.DetentNudge   as DetentNudge
import qualified Properties.NudgeStep      as NudgeStep
import qualified Properties.LatentProjection as LatentProjection
import qualified Properties.OctreeForward  as OctreeForward
import qualified Properties.SelfSimilarReconstruct as SelfSimilarReconstruct
import qualified Properties.DeferredSurfacing as DeferredSurfacing
import qualified Properties.SelfSupervisedRung as SelfSupervisedRung
import qualified Properties.NeuronRedundancy as NeuronRedundancy
import qualified Properties.RungPivot as RungPivot
import qualified Properties.HJepaLevels as HJepaLevels
import qualified Properties.DisplayDecoder as DisplayDecoder
import qualified Properties.EncoderFrozen as EncoderFrozen
import qualified Properties.ContinuousLoop as ContinuousLoop
import qualified Properties.JepaTarget as JepaTarget
import qualified Properties.PerAxisTraining as PerAxisTraining
import qualified Properties.SameObjectInvariance as SameObjectInvariance
import qualified Properties.SameObjectJEPA as SameObjectJEPA
import qualified Properties.CubeTensor     as CubeTensor
import qualified Properties.ProjectionQuery as ProjectionQuery
import qualified Properties.CarrierL      as CarrierL
import qualified Properties.SteeringSpine as SteeringSpine
import qualified Properties.RedownsampleGate as RedownsampleGate
import qualified Properties.PairedResidual as PairedResidual
import qualified Properties.CanonicalPhase as CanonicalPhase
import qualified Properties.SigmaPairFixed as SigmaPairFixed
import qualified Properties.LeafOverride  as LeafOverride
import qualified Properties.LocalPonder   as LocalPonder
import qualified Properties.IsometryMove  as IsometryMove
import qualified Properties.MoveRadiusSchedule as MoveRadiusSchedule
import qualified Properties.GenomePair    as GenomePair
import qualified Properties.Proposer      as Proposer
import qualified Properties.ValueHead     as ValueHead
import qualified Properties.ThetaToDelta  as ThetaToDelta
import qualified Properties.PaletteGesture as PaletteGesture
import qualified Properties.GroupRGBT     as GroupRGBT
import qualified Properties.Quad4Fixed   as Quad4Fixed
import qualified Properties.GlobalVolume as GlobalVolume
import qualified Properties.SplitTree    as SplitTree
import qualified Properties.GridAxis     as GridAxis
import qualified Properties.Order        as Order
import qualified Properties.GridScript   as GridScript
import qualified Properties.Export       as Export
import qualified Properties.Lattice      as Lattice
import qualified Properties.Boundary     as Boundary
import qualified Properties.InfluenceField as InfluenceField
import qualified Properties.CellFiber    as CellFiber
import qualified Properties.CellGrid     as CellGrid
import qualified Properties.GridLayout   as GridLayout
import qualified Properties.MovableLayout as MovableLayout
import qualified Properties.CellMechanics as CellMechanics
import qualified Properties.WidgetDescriptor as WidgetDescriptor
import qualified Properties.Ownership    as Ownership
import qualified Properties.Display      as Display
import qualified Properties.FrontProjection as FrontProjection
import qualified Properties.VoxelFit     as VoxelFit
import qualified Properties.CellShapes   as CellShapes
import qualified Properties.SevenSeg     as SevenSeg
import qualified Properties.CloudProjection as CloudProjection
import qualified Properties.PaletteSearch as PaletteSearch
import qualified Properties.LookCategory as LookCategory
import qualified Properties.HaarRibbon as HaarRibbon
import qualified Properties.QuartetDelta as QuartetDelta
import qualified Properties.LinAlg as LinAlg
import qualified Properties.PaletteOracle as PaletteOracle
import qualified Properties.Dither       as Dither
import qualified Properties.SpatialDither as SpatialDither
import qualified Properties.LookNet      as LookNet
import qualified Properties.LookCore     as LookCore
import qualified Properties.Layer        as Layer
import qualified Properties.Scale        as Scale
import qualified Properties.Preference   as Preference
import qualified Properties.Bottleneck16 as Bottleneck16
import qualified Properties.SigmaDecomp  as SigmaDecomp
import qualified Properties.Quad4        as Quad4
import qualified Properties.SigmaPairHead as SigmaPairHead
import qualified Properties.Pipeline     as Pipeline
import qualified Properties.AxisNet      as AxisNet
import qualified Properties.Obfuscation  as Obfuscation
import qualified Properties.Loom         as Loom
import qualified Properties.Significance as Significance
import qualified Properties.SignificanceFixed as SignificanceFixed
import qualified Properties.STBN3D       as STBN3D
import qualified Properties.Cyclic       as Cyclic
import qualified Properties.PlaybackClock as PlaybackClock
import qualified Properties.Look         as Look
import qualified Properties.Tensor       as Tensor
import qualified Properties.LookNetE     as LookNetE
import qualified Properties.LookNetR     as LookNetR
import qualified Properties.LookNetD     as LookNetD
import qualified Properties.LookNetCompose as LookNetCompose
import qualified Properties.CoreMLContract as CoreMLContract
import qualified Properties.MLXContract  as MLXContract
import qualified Properties.GoldenForward as GoldenForward
import qualified Properties.AtlasNetEval as AtlasNetEval
import qualified Properties.AtlasGame    as AtlasGame
import qualified Properties.BoardQ16     as BoardQ16
import qualified Properties.GLRM         as GLRM
import qualified Properties.GumbelSearch as GumbelSearch
import qualified Properties.Loss         as Loss
import qualified Properties.AtlasBoard   as AtlasBoard
import qualified Properties.AtlasMove    as AtlasMove
import qualified Properties.AtlasState   as AtlasState
import qualified Properties.DeltaCodebook as DeltaCodebook
import qualified Properties.AtlasOracle  as AtlasOracle
import qualified Properties.PreferenceUpdate as PreferenceUpdate
import qualified Properties.PersonalGenome as PersonalGenome
import qualified Properties.GenomeBlend  as GenomeBlend
import qualified Properties.DecisionLog  as DecisionLog
import qualified Properties.AtlasCascade as AtlasCascade
import qualified Properties.Upscale256   as Upscale256

main :: IO ()
main = defaultMain $ testGroup "sixfour-spec"
  [ Color.tests
  , ColorFixed.tests
  , ZoneProfile.tests
  , LookTransfer.tests
  , RedFrontEnd.tests
  , CubeLut.tests
  , Gauge.tests
  , Surj.tests
  , Wu.tests
  , QuantFixed.tests
  , Coverage.tests
  , Collapse.tests
  , Diversity.tests
  , GMM.tests
  , Bures.tests
  , Sinkhorn.tests
  , Barycenter.tests
  , Entropy.tests
  , RGBTFeature.tests
  , CubeLadder.tests
  , VoxelReduce.tests
  , DivergenceSchedule.tests
  , ABSurface.tests
  , GenomeCarrier.tests
  , PairTree.tests
  , PairTreeFixed.tests
  , RGBTLift.tests
  , OctreeCell.tests
  , LadderIdentity.tests
  , PerScaleWeights.tests
  , ScalePonder.tests
  , XYTLabDuality.tests
  , LBalanceOperator.tests
  , OctreeGenome.tests
  , SubstrateDomain.tests
  , SuccessiveRefinement.tests
  , SuperResPalette.tests
  , RelationalResidual.tests
  , RemainderTail.tests
  , ByteCarrier.tests
  , DetailEntropy.tests
  , DetailMaskedPrediction.tests
  , MaskedBandPrediction.tests
  , MaskedBandTrainer.tests
  , DetailPredictor.tests
  , Dim6.tests
  , ProjectionOrdering.tests
  , Dimensions.tests
  , OptionTree.tests
  , ChromaRotation.tests
  , LatentNavigation.tests
  , DetentNudge.tests
  , NudgeStep.tests
  , LatentProjection.tests
  , OctreeForward.tests
  , SelfSimilarReconstruct.tests
  , DeferredSurfacing.tests
  , SelfSupervisedRung.tests
  , NeuronRedundancy.tests
  , RungPivot.tests
  , HJepaLevels.tests
  , DisplayDecoder.tests
  , EncoderFrozen.tests
  , ContinuousLoop.tests
  , JepaTarget.tests
  , PerAxisTraining.tests
  , SameObjectInvariance.tests
  , SameObjectJEPA.tests
  , CubeTensor.tests
  , ProjectionQuery.tests
  , CarrierL.tests
  , SteeringSpine.tests
  , RedownsampleGate.tests
  , PairedResidual.tests
  , CanonicalPhase.tests
  , SigmaPairFixed.tests
  , LeafOverride.tests
  , LocalPonder.tests
  , IsometryMove.tests
  , MoveRadiusSchedule.tests
  , GenomePair.tests
  , Proposer.tests
  , ValueHead.tests
  , ThetaToDelta.tests
  , PaletteGesture.tests
  , GroupRGBT.tests
  , Quad4Fixed.tests
  , GlobalVolume.tests
  , SplitTree.tests
  , GridAxis.tests
  , Order.tests
  , GridScript.tests
  , Export.tests
  , Lattice.tests
  , Boundary.tests
  , InfluenceField.tests
  , CellFiber.tests
  , CellGrid.tests
  , GridLayout.tests
  , MovableLayout.tests
  , CellMechanics.tests
  , WidgetDescriptor.tests
  , Ownership.tests
  , Display.tests
  , FrontProjection.tests
  , VoxelFit.tests
  , CellShapes.tests
  , SevenSeg.tests
  , CloudProjection.tests
  , PaletteSearch.tests
  , PaletteOracle.tests
  , LookCategory.tests
  , HaarRibbon.tests
  , QuartetDelta.tests
  , LinAlg.tests
  , Dither.tests
  , SpatialDither.tests
  , LookNet.tests
  , LookCore.tests
  , Layer.tests
  , Preference.tests
  , Bottleneck16.tests
  , SigmaDecomp.tests
  , Quad4.tests
  , SigmaPairHead.tests
  , Pipeline.tests
  , AxisNet.tests
  , Obfuscation.tests
  , Loom.tests
  , Significance.tests
  , SignificanceFixed.tests
  , STBN3D.tests
  , Cyclic.tests
  , PlaybackClock.tests
  , Look.tests
  , Scale.tests
  , Tensor.tests
  , LookNetE.tests
  , LookNetR.tests
  , LookNetD.tests
  , LookNetCompose.tests
  , CoreMLContract.tests
  , MLXContract.tests
  , GoldenForward.tests
  , AtlasNetEval.tests
  , AtlasGame.tests
  , BoardQ16.tests
  , GLRM.tests
  , GumbelSearch.tests
  , Loss.tests
  , AtlasBoard.tests
  , AtlasMove.tests
  , AtlasState.tests
  , DeltaCodebook.tests
  , AtlasOracle.tests
  , PreferenceUpdate.tests
  , PersonalGenome.tests
  , GenomeBlend.tests
  , DecisionLog.tests
  , AtlasCascade.tests
  , Upscale256.tests
  ]
