module Main (main) where

import Test.Tasty

import qualified Properties.GuildScale   as GuildScale
import qualified Properties.Trade        as Trade
import qualified Properties.Governance   as Governance
import qualified Properties.Lineage      as Lineage
import qualified Properties.Affiliation  as Affiliation
import qualified Properties.Role         as Role
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
import qualified Properties.GlobalCollapseQ16 as GlobalCollapseQ16
import qualified Properties.Diversity    as Diversity
import qualified Properties.EncoderModalityLoad as EncoderModalityLoad
import qualified Properties.EncoderWidthAlloc as EncoderWidthAlloc
import qualified Properties.EncoderDepthAlloc as EncoderDepthAlloc
import qualified Properties.EncoderEntropyFloor as EncoderEntropyFloor
import qualified Properties.EncoderCorpus as EncoderCorpus
import qualified Properties.EncoderGrounding as EncoderGrounding
import qualified Properties.SyntheticCorpus as SyntheticCorpus
import qualified Properties.GMM          as GMM
import qualified Properties.Bures        as Bures
import qualified Properties.Sinkhorn     as Sinkhorn
import qualified Properties.Barycenter   as Barycenter
import qualified Properties.Entropy      as Entropy
import qualified Properties.RGBTFeature  as RGBTFeature
import qualified Properties.CubeLadder   as CubeLadder
import qualified Properties.VoxelReduce  as VoxelReduce
import qualified Properties.ABSurface    as ABSurface
import qualified Properties.GenomeCarrier as GenomeCarrier
import qualified Properties.SwapCarrier as SwapCarrier
import qualified Properties.GeneSimilarity as GeneSimilarity
import qualified Properties.CurateRealize as CurateRealize
import qualified Properties.PairTree     as PairTree
import qualified Properties.PairTreeFixed as PairTreeFixed
import qualified Properties.RGBTLift     as RGBTLift
import qualified Properties.OctreeCell   as OctreeCell
import qualified Properties.V21Field     as V21Field
import qualified Properties.V21FieldUI   as V21FieldUI
import qualified Properties.V21Transport as V21Transport
import qualified Properties.V21Pyramid   as V21Pyramid
import qualified Properties.Recursion    as Recursion
import qualified Properties.LadderIdentity as LadderIdentity
import qualified Properties.PerScaleWeights as PerScaleWeights
import qualified Properties.ScalePonder   as ScalePonder
import qualified Properties.XYTLabDuality as XYTLabDuality
import qualified Properties.LargeJepaHead as LargeJepaHead
import qualified Properties.LBalanceOperator as LBalanceOperator
import qualified Properties.OctreeGenome  as OctreeGenome
import qualified Properties.SubstrateDomain as SubstrateDomain
import qualified Properties.SuccessiveRefinement as SuccessiveRefinement
import qualified Properties.SuperResPalette as SuperResPalette
import qualified Properties.SynthesisPolicyValue as SynthesisPolicyValue
import qualified Properties.TwoMoveOctave as TwoMoveOctave
import qualified Properties.MoveSignal as MoveSignal
import qualified Properties.BoundedP6 as BoundedP6
import qualified Properties.Sided as Sided
import qualified Properties.DataParallel as DataParallel
import qualified Properties.JepaMemory as JepaMemory
import qualified Properties.HalfwayLatent as HalfwayLatent
import qualified Properties.JepaData as JepaData
import qualified Properties.RelationalResidual as RelationalResidual
import qualified Properties.RelationalMemory as RelationalMemory
import qualified Properties.RemainderTail as RemainderTail
import qualified Properties.ByteCarrier   as ByteCarrier
import qualified Properties.Q16           as Q16
import qualified Properties.DetailEntropy as DetailEntropy
import qualified Properties.DetailMaskedPrediction as DetailMaskedPrediction
import qualified Properties.MaskedBandPrediction as MaskedBandPrediction
import qualified Properties.MaskedBandTrainer as MaskedBandTrainer
import qualified Properties.DeviceTrainStep as DeviceTrainStep
import qualified Properties.GeneTaxonomy as GeneTaxonomy
import qualified Properties.DetailPredictor as DetailPredictor
import qualified Properties.Dim6          as Dim6
import qualified Properties.ProjectionOrdering as ProjectionOrdering
import qualified Properties.Dimensions    as Dimensions
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
import qualified Properties.ConstructionEncoder as ConstructionEncoder
import qualified Properties.HierarchicalDelta as HierarchicalDelta
import qualified Properties.RootLatticeDetail as RootLatticeDetail
import qualified Properties.GaugeAction as GaugeAction
import qualified Properties.ScaleFiltration as ScaleFiltration
import qualified Properties.RingReduction as RingReduction
import qualified Properties.MetricLattice as MetricLattice
import qualified Properties.RefinementSystem as RefinementSystem
import qualified Properties.RefinementCarriers as RefinementCarriers
import qualified Properties.GaussianChroma as GaussianChroma
import qualified Properties.AnchorDiagnostic as AnchorDiagnostic
import qualified Properties.DualCube as DualCube
import qualified Properties.ChannelProduct as ChannelProduct
import qualified Properties.HeldOutTarget as HeldOutTarget
import qualified Properties.MatrixTarget as MatrixTarget
import qualified Properties.NudgeRankTheorem as NudgeRankTheorem
import qualified Properties.PonderBudget as PonderBudget
import qualified Properties.CellNudge as CellNudge
import qualified Properties.PonderHaltDistribution as PonderHaltDistribution
import qualified Properties.VarianceFloorGuard as VarianceFloorGuard
import qualified Properties.MotionFloorCorpus as MotionFloorCorpus
import qualified Properties.ScaleSpineRungs as ScaleSpineRungs
import qualified Properties.ModelIO as ModelIO
import qualified Properties.Model as Model
import qualified Properties.AboveFloorMargin as AboveFloorMargin
import qualified Properties.ModelForward as ModelForward
import qualified Properties.TransportGroup as TransportGroup
import qualified Properties.TemporalData as TemporalData
import qualified Properties.DeltaSurrogate as DeltaSurrogate
import qualified Properties.LearnabilityTheorem as LearnabilityTheorem
import qualified Properties.Convergence as Convergence
import qualified Properties.HeadConvergence as HeadConvergence
import qualified Properties.TrunkLinearization as TrunkLinearization
import qualified Properties.Generalization as Generalization
import qualified Properties.BlindComplementIsA7 as BlindComplementIsA7
import qualified Properties.IdentifiabilityIsA7Bridge as IdentifiabilityIsA7Bridge
import qualified Properties.CoverageMonotone as CoverageMonotone
import qualified Properties.BlindComplementGeometry as BlindComplementGeometry
import qualified Properties.LatticeRankComputed as LatticeRankComputed
import qualified Properties.ChromaUnitGauge as ChromaUnitGauge
import qualified Properties.ChromaUnitMinimizer as ChromaUnitMinimizer
import qualified Properties.ParadigmSoundness as ParadigmSoundness
import qualified Properties.ParadigmRobustness as ParadigmRobustness
import qualified Properties.ValueWeightThreshold as ValueWeightThreshold
import qualified Properties.GlobalUniqueness as GlobalUniqueness
import qualified Properties.NudgeContamination as NudgeContamination
import qualified Properties.DeltaGesture as DeltaGesture
import qualified Properties.TriScaleBench as TriScaleBench
import qualified Properties.GestureAxis as GestureAxis
import qualified Properties.ScaleSurface as ScaleSurface
import qualified Properties.PerceptualEncoder as PerceptualEncoder
import qualified Properties.GifDualView   as GifDualView
import qualified Properties.CrossEncoderDistance as CrossEncoderDistance
import qualified Properties.CoarseIsPalette as CoarseIsPalette
import qualified Properties.ScaleIndexedCorrespondence as ScaleIndexedCorrespondence
import qualified Properties.DualEncoderJepa as DualEncoderJepa
import qualified Properties.MinimalInstructionSet as MinimalInstructionSet
import qualified Properties.DitherLevel   as DitherLevel
import qualified Properties.MidLatentCrossPrediction as MidLatentCrossPrediction
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
import qualified Properties.PaletteGesture as PaletteGesture
import qualified Properties.GroupRGBT     as GroupRGBT
import qualified Properties.Quad4Fixed   as Quad4Fixed
import qualified Properties.GlobalVolume as GlobalVolume
import qualified Properties.SplitTree    as SplitTree
import qualified Properties.GridAxis     as GridAxis
import qualified Properties.Order        as Order
import qualified Properties.GridScript   as GridScript
import qualified Properties.Export       as Export
import qualified Properties.CaptureFormat as CaptureFormat
import qualified Properties.TemporalLoop as TemporalLoop
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
import qualified Properties.HaarRibbon as HaarRibbon
import qualified Properties.QuartetDelta as QuartetDelta
import qualified Properties.Dither       as Dither
import qualified Properties.SpatialDither as SpatialDither
import qualified Properties.Bottleneck16 as Bottleneck16
import qualified Properties.Loom         as Loom
import qualified Properties.Significance as Significance
import qualified Properties.SignificanceFixed as SignificanceFixed
import qualified Properties.STBN3D       as STBN3D
import qualified Properties.Cyclic       as Cyclic
import qualified Properties.PlaybackClock as PlaybackClock
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
  , GlobalCollapseQ16.tests
  , Diversity.tests
  , EncoderModalityLoad.tests
  , EncoderWidthAlloc.tests
  , EncoderDepthAlloc.tests
  , EncoderEntropyFloor.tests
  , EncoderCorpus.tests
  , EncoderGrounding.tests
  , SyntheticCorpus.tests
  , GMM.tests
  , Bures.tests
  , Sinkhorn.tests
  , Barycenter.tests
  , Entropy.tests
  , RGBTFeature.tests
  , CubeLadder.tests
  , VoxelReduce.tests
  , ABSurface.tests
  , GenomeCarrier.tests
  , SwapCarrier.tests
  , GeneSimilarity.tests
  , CurateRealize.tests
  , PairTree.tests
  , PairTreeFixed.tests
  , RGBTLift.tests
  , OctreeCell.tests
  , Recursion.tests
  , LadderIdentity.tests
  , PerScaleWeights.tests
  , ScalePonder.tests
  , XYTLabDuality.tests
  , LargeJepaHead.tests
  , LBalanceOperator.tests
  , OctreeGenome.tests
  , SubstrateDomain.tests
  , SuccessiveRefinement.tests
  , SuperResPalette.tests
  , SynthesisPolicyValue.tests
  , TwoMoveOctave.tests
  , MoveSignal.tests
  , BoundedP6.tests
  , Sided.tests
  , DataParallel.tests
  , JepaMemory.tests
  , HalfwayLatent.tests
  , JepaData.tests
  , RelationalResidual.tests
  , RelationalMemory.tests
  , RemainderTail.tests
  , ByteCarrier.tests
  , Q16.tests
  , DetailEntropy.tests
  , DetailMaskedPrediction.tests
  , MaskedBandPrediction.tests
  , MaskedBandTrainer.tests
  , DeviceTrainStep.tests
  , GeneTaxonomy.tests
  , DetailPredictor.tests
  , Dim6.tests
  , ProjectionOrdering.tests
  , Dimensions.tests
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
  , ConstructionEncoder.tests
  , HierarchicalDelta.tests
  , RootLatticeDetail.tests
  , GaugeAction.tests
  , ScaleFiltration.tests
  , RingReduction.tests
  , MetricLattice.tests
  , RefinementSystem.tests
  , RefinementCarriers.tests
  , GaussianChroma.tests
  , AnchorDiagnostic.tests
  , DualCube.tests
  , ChannelProduct.tests
  , HeldOutTarget.tests
  , MatrixTarget.tests
  , NudgeRankTheorem.tests
  , PonderBudget.tests
  , CellNudge.tests
  , PonderHaltDistribution.tests
  , VarianceFloorGuard.tests
  , MotionFloorCorpus.tests
  , ScaleSpineRungs.tests
  , ModelIO.tests
  , Model.tests
  , AboveFloorMargin.tests
  , ModelForward.tests
  , TransportGroup.tests
  , TemporalData.tests
  , DeltaSurrogate.tests
  , LearnabilityTheorem.tests
  , Convergence.tests
  , HeadConvergence.tests
  , TrunkLinearization.tests
  , Generalization.tests
  , BlindComplementIsA7.tests
  , IdentifiabilityIsA7Bridge.tests
  , CoverageMonotone.tests
  , BlindComplementGeometry.tests
  , LatticeRankComputed.tests
  , ChromaUnitGauge.tests
  , ChromaUnitMinimizer.tests
  , ParadigmSoundness.tests
  , ParadigmRobustness.tests
  , ValueWeightThreshold.tests
  , GlobalUniqueness.tests
  , NudgeContamination.tests
  , DeltaGesture.tests
  , TriScaleBench.tests
  , GestureAxis.tests
  , ScaleSurface.tests
  , PerceptualEncoder.tests
  , GifDualView.tests
  , CrossEncoderDistance.tests
  , CoarseIsPalette.tests
  , ScaleIndexedCorrespondence.tests
  , DualEncoderJepa.tests
  , MinimalInstructionSet.tests
  , DitherLevel.tests
  , MidLatentCrossPrediction.tests
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
  , PaletteGesture.tests
  , GroupRGBT.tests
  , Quad4Fixed.tests
  , GlobalVolume.tests
  , SplitTree.tests
  , GridAxis.tests
  , Order.tests
  , GridScript.tests
  , Export.tests
  , CaptureFormat.tests
  , TemporalLoop.tests
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
  , HaarRibbon.tests
  , QuartetDelta.tests
  , Dither.tests
  , SpatialDither.tests
  , Bottleneck16.tests
  , Loom.tests
  , Significance.tests
  , SignificanceFixed.tests
  , STBN3D.tests
  , Cyclic.tests
  , PlaybackClock.tests
  , AtlasCascade.tests
  , Upscale256.tests
  , V21Field.tests
  , V21FieldUI.tests
  , V21Transport.tests
  , GuildScale.tests
  , Trade.tests
  , Governance.tests
  , Lineage.tests
  , Affiliation.tests
  , Role.tests
  , V21Pyramid.tests
  ]
