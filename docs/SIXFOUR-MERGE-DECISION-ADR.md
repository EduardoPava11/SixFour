# ADR: Look-NN + Value-Net Unification (Merge Decision)

Status: ACCEPTED
Date: 2026-06-17
Decider: Chair, with three independent judges + adversarial critics.
Supersedes the open decisions in docs/SIXFOUR-LOOK-VALUE-UNIFICATION.md Section 7.

## 1. Decision in one line

Ship the unified sigma-equivariant net on the as-is lossy palette-collapse substrate, with a frozen Mac-MLX trunk + value and on-device MPSGraph fine-tune of only the genome-enc and value-MLP, spec-first in the full doc P-order, and build the Metal cube-lift parity gate now as an independent hardening win. This is the CORRECTNESS path with the time-to-shippable graft from the INCREMENTAL path.

## 2. Winning path and why it won

Winner: the CORRECTNESS / methodology-first path.

Judge consensus: judge-1 and judge-2 both ranked it first (weighted 8.69 and 8.71); judge-3 ranked the INCREMENTAL path first by a thin margin (8.36 vs 8.27). The two paths share the exact same decision-variable answers on the three soundness-binding variables (DV2-C, DV3-A, DV4-A) and differ only in framing and effort sizing. The Chair adopts the CORRECTNESS spine as the canonical decision because it is the one whose written sequence actually schedules the proof obligations the merge truly has, and it grafts the INCREMENTAL path's two real wins (front-loaded de-risk ordering and an early on-device latency re-measure). On the binding criteria, which are dominated by soundness (0.22), spec+gate hygiene (0.18), and reuse (0.16) totaling 0.56, the CORRECTNESS path scores highest on the top two axes.

Why it survives the constraints (all verified against source this session):

- C9 spec-before-code binds. Spec.AtlasValueHead genuinely does not exist (spec/src/SixFour/Spec/ holds only AtlasBoard, AtlasCascade, AtlasMove, AtlasOracle, AtlasState, Preference, PreferenceUpdate). The neural value head is off-contract until the module plus its laws plus a golden land and cabal test is green. The chosen path lands this as a dedicated step before any Swift change.
- C1 sigma-invariance is achievable with exact ==. inv_proj (trainer/atlas_net_mlx.py:104-113) sums the achromatic halves raw (sigma-fixed, sign +1) and squares the rg and by blocks (mx.sum(rg*rg), mx.sum(by*by)). Negation-then-squaring is bit-identical in IEEE-754 and the achromatic sum is unchanged under a +1 sign, so V(sigma s) == V(s) holds element-wise with no reassociation hazard. The value head reads ONLY inv_proj (line 125), so it is a parallel reader off the pooled context.
- C2 theorem-preserved holds, with one honest caveat the path schedules: the value head adds no operator to the equivariant trunk-to-genome OUTPUT path, so lookNetSigmaTheorem is not re-proven. HOWEVER, the curation-scalar extension phi_ext is an in-series masked operator on the trunk (atlas_net_mlx.py:94, h = base @ w_phi.T + ext @ w_ext.T BEFORE the L4 recursion). Its equivariance is NOT free from the halting-head template and must be proved as lawExtMaskHonoursSigma (the _EXT_MASK zeroes all chromatic contributions). Likewise the genome encoder genome_enc(384->64) with the transposed _GENC_MASK needs lawGenomeEncMaskHonoursSigma. These are genuinely new proofs, not transcription.
- C3 numeric split holds. Trunk + genome + reconstruct stay integer/Q16, golden-gated, byte-exact. The value head is fp32 ordinal-only forever, never quantized, never golden-gated. inv_proj is where the value branch's fp32 begins. The genome branch's fp32-to-Q16 quantization is a DIFFERENT wire (the genome decoder output, where it re-enters the palette pipeline). This ADR keeps the two seams distinct.
- C4/C5 deploy contract holds. MLX is Mac-train-only; on-device is a hand-written Swift/Accelerate or Metal forward loading a plain binary blob, plus MPSGraph (an Apple framework) for the per-user fine-tune. Never mlx-swift, never CoreML, never an opaque ANE runtime.
- C6 floor-div, C7 sim, C8 dormant-flag all verified: @divFloor pervades the Zig lift (kernels.zig:525,563,610,629-650), no Cube.metal or Metal lift kernel exists, the trap is real but latent; MPSGraph cannot run in the simulator but plain compute shaders can; rgbt4dEnabled has zero non-AppSettings callers and the shipped 64->16 is the lossy palette collapse.

Why the runner-up (INCREMENTAL) did not win the chair, despite judge-3's pick: it is functionally the same plan. The Chair selected CORRECTNESS as the named winner because INCREMENTAL sizes the law step "M" and calls codegen "mechanical", both of which the critics showed are understated (phi_ext makes the keystone law L-sized proof-design; Codegen.MLX must emit the fusion and mask glue). CORRECTNESS budgets these honestly. The two are otherwise interchangeable.

Why VISION placed third on all three judges: it is sound and aligned but loses on time-to-shippable (0.14) and on-device risk (0.13). Its DV1-C parallel Haar track is off-seam (the net never consumes the spatial Haar substrate), and its step that wires rgbt4dEnabled was oversold as "enabling reversible 256^3" when the genome rides the lossy palette axis and Spec.Upscale256 is itself lossy and unported, so the bijective end-state is not delivered. It also back-loaded the single binding device-latency unknown behind five steps of spend.

## 3. Grafts from runner-up proposals into the winning path

- From INCREMENTAL: front-load the de-risk. Keep the Metal parity gate first (it is independent and CI-runnable in-sim) and add an EARLY shared-trunk on-device latency probe so the merge's one hardware unknown is retired before the deeper spec/codegen/MLX-train spend, not after. This is grafted as an explicit hardware re-measure inside the deploy-refactor step rather than at the very end.
- From INCREMENTAL: the honest reframing that freezing the trunk shrinks only the optimizer variable set, NOT the L4 x8-recursion forward and backprop cost. The latency budget treats the shared-trunk graph as a genuine open hardware unknown.
- From VISION: keep the spatial Haar ladder as a strictly parallel, non-blocking, OPTIONAL future rung, explicitly DECOUPLED from any reversibility claim. We do not wire it for v1, but we do not foreclose it; the two decompositions are orthogonal.
- From VISION and the critics: pin the label-free statement in the spec (per-frame = NN input, global = NN output = learned replacement for s4_global_collapse), because the codebase has a live A/B label collision (Upscale256.hs calls global "cube A"; LadderExport.swift treats per-frame as A/GIFA). The merge must not inherit the wrong label.

## 4. Resolved decision variables

- DV1-scope: A. Ship the merge against the as-is per-frame/global stack; the learned genome head IS the replacement for s4_global_collapse (lossy collapse); rgbt4dEnabled stays OFF. Justification: the merge seam (pooled L4 context) is substrate-agnostic and the net rides the palette axis only, so wiring the dormant Haar ladder first is off-seam churn that blocks nothing it needs. (Graft: keep the Haar ladder as an optional decoupled future rung per the VISION lens, with no reversibility overclaim.)

- DV2-valuehead-training: C. MLX-Mac frozen v1 for the trunk + value, with on-device MPSGraph fine-tuning ONLY genome-enc + value-MLP (trunk frozen). Justification: freezing the Mac-verified trunk pins C2 and C3 by construction (no on-device fp32 drift can fork the Q16-golden genome path) while preserving the per-user adaptation that is the north star, and it shrinks the on-device optimizer surface.

- DV3-metal-parity-timing: A. Build the P0 Metal cube-lift parity gate now, standalone, independent of the merge: integer cubeLiftLevel/rgbtLiftQuad in a new Cube.metal with explicit floor-div, golden-gate Metal == Zig == Haskell. Justification: it is the cheapest closure of the only unguarded silent-divergence (the @divFloor-vs-truncation trap), CI-runnable in-sim today, and it lights the integer path the net's deterministic stages and the future Haar track both reuse.

- DV4-spec-first-ordering: A. Full doc P-order: P0 Metal gate, P1 Spec.AtlasValueHead (the laws + golden), P2 codegen atlas_net_mlx.py from spec, P3 MPSGraph deploy refactor, P4 wire the Q16 boundary. Justification: C9 forces P1 before any Swift; P2 codegen is retained (not skipped) because the golden pins vectors, not architecture, and the hand-written prototype already deviates from the halting template (raw achro passthrough), so only spec-emission stops drift. The DV4-C debt-first detour is rejected as already-solved: Zig is 29/29 (golden present, no skip), the doc gate exits 0, and the header drift is reconciled.

## 5. Committed ordered build sequence

Each step states the gate it must pass. No Swift change ships before its governing Haskell law and golden are green.

- Step 1 (M): P0 Metal cube-lift parity gate. New SixFour/Metal/Cube.metal with integer cubeLiftLevel and rgbtLiftQuad kernels and an explicit idivFloor helper reproducing @divFloor for negative Q16. Emit a Haskell golden into Generated/ (reuse the GenomeFixedGolden no-tolerance pattern plus a NEGATIVE-bearing Q16 batch from the RGBTLift pattern). Add MetalCubeLiftParityTests.swift dispatching the shader in-sim and asserting exact Int32 equality against the golden AND against SixFourNative.s4_cube_lift_level.
  Gate: in-sim Swift test asserts Metal == Zig == Haskell with exact == on a negative-bearing batch; zig and cabal gates stay green.

- Step 2 (S): Housekeeping. Reconcile any stale STATUS.md test-count text to the verified reality (834 Haskell / 29 Zig, both gates green; rgbt4d_fixture_test live). Edit STATUS.md only; no new ledger.
  Gate: scripts/verify-doc-claims.sh exits 0.

- Step 3 (L): P1 Spec.AtlasValueHead. New module with FOUR laws: lawValueSigmaInvariance (exact ==, split into a sigma-fixed achromatic-passthrough sub-lemma and a squared-chroma-norm sub-lemma); lawValuePreservesLookNetTheorem (value head adds no operator to the equivariant genome OUTPUT path); lawExtMaskHonoursSigma (curation phi_ext feeds ONLY the 22 achromatic dims so the EXTENDED trunk stays equivariant); lawGenomeEncMaskHonoursSigma (the 384->64 transposed-mask encoder is equivariant). Plus a value-forward golden. Wire into spec.cabal exposed-modules, add a SixFour.Spec.Map entry, keep cabal haddock warning-clean. Pin the label-free per-frame=input / global=output statement here.
  Gate: cabal test green with all four laws; haddock warning-clean; Map entry present.

- Step 4 (M): P2 codegen. Emit atlas_net_mlx.py from the spec, retiring the hand-written prototype. If the spec-emitted mask structure (notably _GENC_MASK row ordering and the achro-passthrough-vs-square split) disagrees with the prototype, the SPEC is ground truth: fix the prototype, do not assert fidelity to it.
  Gate: emitted module byte-faithful to the spec; a generated-vs-spec consistency check passes; cabal test stays green.

- Step 5 (L): P3 MPSGraph deploy refactor in AtlasTrainer.swift. Retire wBoard (the standalone per-bin Linear(6->64) + mean-pool, currently feeding raw concat([boardCtx, enc]) into w1 at line 236). Route board tokens through the L3 phi / phi_ext masked path into the L4 recursion; feed the value MLP the 24-D inv_proj instead of raw 128-D ctx; share trunk variables (FROZEN) with the look-NN forward; fine-tune only genome-enc and value-MLP. Guard all MPSGraph execution with #if targetEnvironment(simulator). EARLY on-device latency probe: re-measure shared-trunk forward + backprop on real iPhone 17 Pro and set a budget (the proven 12.4 ms/step was the separate-board spike, not this graph). Keep the old non-invariant spike behind a flag until the merged path re-passes its loss-halving test on device.
  Gate: on-device run shows V(sigma s) == V(s) to fp32 tolerance on the deployed path (spec-only exact ==; device is approximately invariant by design and never bit-asserted); latency within the recorded budget; loss-halving non-regression vs the spike.

- Step 6 (M): Train and export frozen v1. Train trunk + value + genome-enc on Mac with MLX (frozen trunk), export to a plain binary blob via the s4_load_look_net pattern. Add the hand-written Swift forward for trunk + inv_proj + value MLP. Byte-exact-gate the GENOME half of the blob against the Haskell genome golden; tolerance-gate (1e-9 hexDouble transport pin) the float trunk; the value scalar is ordinal-only, never byte-gated.
  Gate: genome half byte-exact vs GenomeFixedGolden (no tolerance); float trunk transport within 1e-9; value head ordinal ranking-consistency check on a held-out preference set passes.

- Step 7 (M): P4 wire the Q16 boundary and ship the user-reachable output. Quantize the fp32 GENOME-HEAD output (NOT the inv_proj value-branch wire) to Q16 exactly where the genome re-enters the palette pipeline; golden-gate that boundary with no tolerance. Wire the genome as the learned replacement for s4_global_collapse on the .global paletteScope seam, behind a flag, exposed as the Review/export hero. The value head stays fp32 ordinal-only.
  Gate: GenomeFixedGolden no-tolerance at the boundary; cross-device GIF determinism check; flag-gated so the deterministic spine is unaffected when off.

Optional future rung (NOT in v1, no ordering dependency): wire an rgbt4dEnabled consumer plus golden regen so the lossless SPATIAL Haar ladder is available. This is the bijective spatial substrate only; it does NOT by itself deliver reversible 256^3 (that additionally needs Spec.Upscale256 ported and de-lossified). Spec-first per rung; reuses the Step 1 Metal lift parity.

## 6. Explicit tradeoffs the user is accepting

- v1 ships on a LOSSY substrate. The learned genome replaces the lossy maximin collapse; A+B do not reconstruct 64^3 losslessly. Reversible 256^3 stays blocked (it needs the dormant Haar ladder wired AND Spec.Upscale256 ported, neither in v1). If the product later demands a bijective substrate, the net was trained against a non-bijective one and may need retraining.
- The shared-trunk on-device latency and backprop are a genuine hardware unknown until Step 5 measures them. The 12.4 ms/step number does not transfer (it was the separate-board spike). Freezing the trunk does not bound forward cost; the L4 x8 recursion runs every step and gradients backprop through the frozen trunk.
- The value head is fp32 ordinal-only and NEVER golden-gated (Bradley-Terry compares V_w - V_l, so absolute scale and bit-exactness are meaningless). A subtle export bug in the value branch would pass tolerance gates and surface only as a wrong V-ranking; the Step 6 ranking-consistency check is the only guard, and it is weaker than a byte-exact gate. This is inherent to C3 and accepted.
- The keystone law lawValueSigmaInvariance is a SPEC-ONLY exact-== guarantee (Haskell Double). The deployed fp32 path is approximately invariant by design and must never be asserted bit-exact.
- The merge retires the only currently-working on-device NN training path (the spike). The spike stays behind a flag until the merged path re-passes its loss-halving test on device, accepting that the previously-shipping capability is at risk during the transition.

## 7. Residual open questions only the user can settle (taste / product)

- North-star ordering: is the product learned-genome-first (this ADR's bet) or reversibility-first? If reversibility-first, the optional Haar rung and Spec.Upscale256 porting should be promoted ahead of, or alongside, the merge, which would change DV1.
- Full-colour training data: the trainer is grayscale-L-only (a=b=0 nucleus) and trainer/data is empty. v1's learned genome will only "beat baseline" on synthetic data and may look unconvincing in colour until real or curated L*a*b* preference data is captured. The user must decide whether to ship the learned hero behind a flag at grayscale fidelity now, or hold the user-facing hero (Step 7 exposure) until a full-colour trainer and data exist while still landing Steps 1 through 6 as the de-risking spine. RECOMMENDATION: land Steps 1 through 6, gate Step 7's hero exposure on full-colour data.
- How much per-user adaptation the frozen-trunk fine-tune can express: if perceived look quality demands trunk adaptation, DV2-C's freeze is too conservative and would need revisiting (at the cost of re-opening C2/C3 protection).

## 8. Dissent

The judges were not unanimous on the top pick. judge-1 and judge-2 chose CORRECTNESS; judge-3 chose INCREMENTAL by a thin margin (8.36 vs 8.27), valuing time-to-shippable and reuse over the marginally cleaner spec-hygiene framing. The dissent is immaterial to the build plan: the two paths share identical answers on DV2, DV3, and DV4 and differ only on DV1 framing (both choose ship-on-lossy) and on effort sizing. This ADR adopts the CORRECTNESS spine and grafts INCREMENTAL's early-de-risk ordering, which is the union of both top picks. All three judges agreed VISION ranks third and that no proposal carries a fatal or unfixable constraint violation.
