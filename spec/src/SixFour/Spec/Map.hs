{- |
Module      : SixFour.Spec.Map
Description : The browsable, categorised index of the SixFour spec — START HERE.

This is the spec's landing page: a categorised map of every module, so the spec is *browsable* (open
the Haddock HTML and click through) and *navigable* as the app changes. It defines nothing — it only links.

Regenerate the browsable HTML + search with @spec/scripts/spec-docs.sh@ (Haddock + Hoogle). The categories
below mirror @docs/SIXFOUR-SPEC-BROWSABLE-WORKFLOW.md@; keep them in sync when adding a module.

== ★ The core: the NN design
The look-NN is the heart everything orbits. It takes the per-frame palettes (cat. 2), sees them collapsed
(cat. 3), and emits a genome in the palette-tree space (cat. 4), scored by a value oracle and searched.
The verdict (see @docs/SIXFOUR-256-SUPERRES-WORKFLOW.md@): __no JEPA core__ — the net is a __gated, gap-only
residual head__ on a deterministic statistical base; every cell still emits an exact 1-byte index.

  * "SixFour.Spec.Net"            — pinned NN shapes (io dims, MoR depth) → @NetContract@
  * "SixFour.Spec.LookNet"        — the look-NN top-level
  * "SixFour.Spec.LookNetE"       — Encoder (set → σ-equivariant context, L3)
  * "SixFour.Spec.LookNetR"       — Recursion / core (Mixture-of-Recursions, L4)
  * "SixFour.Spec.LookNetD"       — Decoder (state → 384-DOF σ-pair genome, L5)
  * "SixFour.Spec.LookNetCompose" — the σ-equivariance theorem (E∘R∘D)
  * "SixFour.Spec.LookNetEval"    — forward-pass evaluation
  * "SixFour.Spec.LookCore", "SixFour.Spec.Layer", "SixFour.Spec.Scale", "SixFour.Spec.AxisNet" — primitives
  * "SixFour.Spec.Loss"           — training loss (OT/reconstruction; GAN dropped)
  * "SixFour.Spec.PaletteOracle"  — the deterministic value head (Ou-Luo beauty + entropy)
  * "SixFour.Spec.PaletteSearch"  — MCTS over scored candidates
  * "SixFour.Spec.Preference", "SixFour.Spec.Look", "SixFour.Spec.Loom" — preference / authoring surface
  * "SixFour.Spec.LookCategory" — ★ north-star: named look taxonomy + on-device Bradley–Terry push-pull learning

== ★★ The Color Atlas — on-device personalization (north-star training surface)
The first spec footprint of the north-star: the user curates a 16³ board, picks become Bradley–Terry
comparisons, and a small per-user delta head is updated on device (proven on hardware, see
@docs/COLOR-ATLAS.md@ + the UPDATE block in @docs/STATUS.md@).

  * "SixFour.Spec.AtlasBoard"      — the 16³ curation board state
  * "SixFour.Spec.AtlasState"      — the Atlas session state
  * "SixFour.Spec.AtlasMove"       — the Move ADT (the user's curation actions)
  * "SixFour.Spec.AtlasOracle"     — the value oracle scoring board candidates
  * "SixFour.Spec.AtlasCascade"    — the multi-stage proposal cascade
  * "SixFour.Spec.DecisionLog"     — the replay-record wire format of picks
  * "SixFour.Spec.DeltaCodebook"   — the per-user delta-head codebook
  * "SixFour.Spec.PreferenceUpdate" — the on-device preference-update (gradient/weight) rule

== 1. Numeric & colour core
"SixFour.Spec.Shape", "SixFour.Spec.Color", "SixFour.Spec.ColorFixed", "SixFour.Spec.LinAlg",
"SixFour.Spec.Tensor", "SixFour.Spec.Gauge", "SixFour.Spec.Sinkhorn" (entropic OT + the
debiased Sinkhorn divergence — the discrete-measure fidelity that tightens the Bures
Gaussian-summary; shared by "SixFour.Spec.Loss" and "SixFour.Spec.Barycenter").

== 2. Per-frame palette — the NN INPUT
"SixFour.Spec.StageA", "SixFour.Spec.Palette", "SixFour.Spec.QuantFixed", "SixFour.Spec.GMM",
"SixFour.Spec.Bures", "SixFour.Spec.Diversity", "SixFour.Spec.Coverage", "SixFour.Spec.Significance",
"SixFour.Spec.SignificanceFixed".

== 3. Collapse → the global palette
"SixFour.Spec.Collapse", "SixFour.Spec.GlobalVolume", "SixFour.Spec.Cyclic",
"SixFour.Spec.Barycenter", "SixFour.Spec.Entropy". (Baseline = maximin pick;
"SixFour.Spec.Barycenter" is the free-support W₂ /particle-flow/ move — the next rung of the
GIFA→GIFB redesign — that lets atoms transport, not merely select; "SixFour.Spec.Entropy" is the
capture information analysis — RGBT pool weights + the per-frame↔global scope cost — that DECIDES
where global vs per-frame is justified, see @docs/SIXFOUR-CUBE-LADDER-GAP-ANALYSIS.md@. The NN
learns this barycenter.)

== 4. Palette structure / genome — the NN OUTPUT space (16² / 4⁴ / 2⁸)
"SixFour.Spec.SplitTree", "SixFour.Spec.PairTree", "SixFour.Spec.PairTreeFixed",
"SixFour.Spec.RGBTLift" (the @2×2 ↔ RGBT@ reversible integer lifting — the spatial sibling of the
1-D PairTreeFixed S-transform; the @(2×2)<->1@ bijection that makes the cube ladder lossless, see
@docs/SIXFOUR-RGBT4D-BUFFER-HARDENING-WORKFLOW.md@), "SixFour.Spec.CanonicalPhase" (the loop
gauge-fix — the rotation-invariant necklace canonical form that gives the semantic RGBT lanes a
reproducible phase on the C₆₄-symmetric GIF loop),
"SixFour.Spec.RGBTFeature" (the 1b feature layer — entropy-weighted temporal coherence over the
circular buffer, the substrate every tier reads), "SixFour.Spec.CubeLadder" (the 16³/64³/256³ tiers
as reversible 2D-Haar views on that substrate — lossless within capture via "SixFour.Spec.RGBTLift",
predictive only beyond),
"SixFour.Spec.SigmaPairFixed", "SixFour.Spec.SigmaPairHead", "SixFour.Spec.SigmaDecomp",
"SixFour.Spec.Quad4", "SixFour.Spec.Quad4Fixed", "SixFour.Spec.Bottleneck16",
"SixFour.Spec.LeafOverride", "SixFour.Spec.PaletteGesture", "SixFour.Spec.GroupRGBT".

== 5. The authoring STORY (Acts I–IV) — the user-facing pipeline the NN lives in
"SixFour.Spec.StageA" (Act I, @16²@ per-frame) · "SixFour.Spec.QuartetDelta" (Act II, @4⁴@ quartet core) ·
"SixFour.Spec.HaarRibbon" (Act III, @2⁸@ Haar abstraction) · "SixFour.Spec.Export" (Act IV, the global pack
@{16³,64³,256³}@) · "SixFour.Spec.Upscale256" (Act IV, the residual-seeded @256³@ super-res of the export pack) ·
"SixFour.Spec.ActDecisions" (the per-act decision table, each act <= 3 real Display events).
See @docs/SIXFOUR-PALETTE-STORY-WORKFLOW.md@.

== 6. Dither & index encoding
"SixFour.Spec.Dither", "SixFour.Spec.SpatialDither", "SixFour.Spec.STBN3D", "SixFour.Spec.Indices",
"SixFour.Spec.FrontProjection", "SixFour.Spec.VoxelFit".

== 7. UI — the cell-field / display / grid
"SixFour.Spec.Display", "SixFour.Spec.PlaybackClock", "SixFour.Spec.Lattice", "SixFour.Spec.Boundary", "SixFour.Spec.InfluenceField", "SixFour.Spec.CellFiber",
"SixFour.Spec.CellGrid", "SixFour.Spec.CellShapes", "SixFour.Spec.CellMechanics", "SixFour.Spec.GridLayout",
"SixFour.Spec.GridAxis",
"SixFour.Spec.GridScript", "SixFour.Spec.MovableLayout", "SixFour.Spec.WidgetDescriptor", "SixFour.Spec.Ownership", "SixFour.Spec.Order",
"SixFour.Spec.CloudProjection", "SixFour.Spec.SevenSeg", "SixFour.Spec.Pipeline", "SixFour.Spec.Obfuscation".

== 8. Cross-cutting
"SixFour.Spec.Laws" — shared law combinators.

== 9. Codegen — emitters to the app (Swift / Zig / Python), golden-pinned
@SixFour.Codegen.Swift@, @.Shapes@, @.Golden@, @.Collapse@, @.RGBT4D@, @.PairTree@, @.QuartetDelta@, @.Genome@,
@.GenomeFixed@, @.PaletteValue@, @.MLX@, @.CoreML@, @.Burn@.

== 10. Look transfer / LUT extraction (R3D .cube)
The on-screen "look" and the exported 3D LUT are two projections of ONE OKLab palette→palette
transform derived from the captured palette's luminance-zone chroma profile (a port of
@~/lut-generator/src/python/gif_palette_lut.py@). See @docs/SIXFOUR-LOOK-LUT-WORKFLOW.md@.

  * "SixFour.Spec.ZoneProfile"  — luminance-zone mean a/b/chroma profile of a palette
  * "SixFour.Spec.LookTransfer" — the chrominance-only transfer (preview ≡ cube core)
  * "SixFour.Spec.RedFrontEnd"  — Log3G10 decode + RWG→Rec.709 + filmic tonemap (LUT-driven, Q16)
  * "SixFour.Spec.CubeLut"      — the 65³ .cube grid builder
-}
module SixFour.Spec.Map () where
