# SixFour AlphaZero Collapse Design

Synthesis lead doc. Supersedes the supervised MLX look-net core. Status: design, spec-first build sequence below. All claims cite `file:line` verified against source 2026-06-17. PLAIN punctuation only.

---

## 1. The reframe in one paragraph

The supervised MLX look-net regressed a 384-DOF genome and did not train well. We abandon its trained weights and port the IDEAS into an AlphaZero-shaped core: a POLICY net plus a VALUE net over a turn-based state machine whose moves are reversible edits in OKLab space, with the cube ladder `16^3 <-> 64^3 <-> 256^3` as the abstraction hierarchy and Bradley-Terry A/B preference as the reward signal. Everything deterministic is engineered bare metal: the game state and the reversible integer Haar lift are integer/Q16 byte-exact (Zig == Swift == Haskell == Metal), the policy/value net is fp32 ordinal-only (MPSGraph trains it on device, hand-written Metal compute runs its forward in the simulator), and no mlx-swift or CoreML black box ever ships. CRITICAL HONESTY: the codebase is already MCTS-search-over-a-value-heuristic shaped, but it is NOT a closed AlphaZero loop today. The value half is proven on device (12.4 ms/step, AtlasTrainer.swift); the policy half has no trainer, no target, and no on-device path (AtlasTrainer.swift:33 calls policy heads "follow-up work"). This doc resolves the four cross-facet contradictions the critique found and sequences the build so each phase closes one honest gap.

---

## 2. THE GAME

The game is a single-player search MDP per capture episode, plus a between-episode preference channel. It is NOT two-player Go: there is no adversary, no alternating plies, no value-sign-flip. Calling it "AlphaZero" means we borrow the (policy, value) plus MCTS plus expert-iteration TEMPLATE, applied to a 1-player MDP whose reward model is fit from pairwise A/B preference (this is preference-based RL / RLHF-reward-model plus planning). mctsStep backs up `oValue` with no minimax (PaletteSearch.hs:200).

### 2.1 State

`S = (rung, tree, board, ply)`:
- `rung in {16^3, 64^3, 256^3}` the cube-ladder abstraction level (CubeLadder.hs).
- `tree :: SigmaSearchState` a COMPLETE depth-7 sigma-pair tree, ALWAYS 256 leaves. There are no partial trees (PaletteSearch.hs:18; atlasLeaves = reconstructPaired, AtlasState.hs:103-104). The directive's "partial-collapse position" does not exist: a position is a COEFFICIENT configuration on a fixed-depth tree, not a half-built tree. This reinterpretation is canon.
- `board :: Board16` the 16^3 x 6 curation tensor, the AlphaGo board (AtlasMove.hs:20, ch0-2 recomputed, ch3-5 curated).
- `ply :: Int` move counter, drives the terminal predicate.

### 2.2 Moves (the unified Move ADT, OWNED here, not deferred)

Today three disjoint move systems exist and the critique's contradiction #3 is real:
- GenomeMove = `PaletteSearch.Move {mvLevel, mvIndex, mvDelta :: OKLab}` (PaletteSearch.hs:117-123): perturb one Haar coefficient. Reversible (`invertMove`, PaletteSearch.hs:133).
- CurationMove = `AtlasMove.CurationMove` (AtlasMove.hs:76-80): ToggleBin (ch4) / WeightRegion (ch3) / PinAnchor (ch5) / `Compare GenomeHash GenomeHash` (the A/B outcome, mutates nothing, lawCompareIdentity AtlasMove.hs:17).
- RungMove (proposed): Ascend/Descend via distill/synthesize.

DECISION (resolves #3): a new `Spec.AtlasGame` module defines ONE game ADT that WRAPS the existing ADTs without editing PaletteSearch/AtlasMove (preserve the verbatim-search contract):

```
data GameMove
  = Edit   PaletteSearch.Move        -- agent ply: perturb a Haar coefficient
  | Curate AtlasMove.CurationMove    -- board edit (ToggleBin/WeightRegion/PinAnchor)
  | Rung   RungDir                   -- Ascend/Descend the ladder (Descend always legal; Ascend only within capture)
  -- Compare is NOT a GameMove. It is the meta-level OUTCOME emitter (see 2.5).
```

The POLICY net emits only over `Edit` moves (the 127 x 12 DeltaCodebook vocabulary, DeltaCodebook.hs:19-21, lawVocab1524). `Curate` moves are human/board plies that gate legality. `Rung` is the abstraction operator. `Compare` is the reward, lifted out of the move algebra entirely. This is the single owner for the unified move space the critique demanded.

### 2.3 Transition

`Edit` -> applyMove (PaletteSearch.hs:127, preserves depth/256 leaves, lawSearchPreservesDepth AtlasState.hs). `Curate` -> applyCuration (AtlasMove.hs:89). `Rung Descend` -> distill (lossless within capture). `Rung Ascend` within capture -> synthesize (lossless); above capture -> synthBeyond (one-way, see section 3). All total; out-of-range is identity.

### 2.4 Legality and terminal

- Legality: `atlasWellFormed` plus the oracle top-k=8 generator (policyWidth=8, AtlasOracle.hs:92-93) with kill-bin pruning and forced-anchor moves (atlasPolicy AtlasOracle.hs:179-191). Ascend-beyond-capture is FORBIDDEN as a reversible move (it is non-invertible synthesis).
- Terminal (new, OWNED in AtlasGame as an enforced predicate, resolves part of #5): `terminal s = ply s >= plyBudget && allAnchorsMet (board s) && noKilledLeaves s`. The terminal state's leaves are the candidate genome submitted to the A/B gallery. Today the search halts on a visit/value BUDGET (HaltOnVisits/HaltOnValue, PaletteSearch.hs:50), which is search budget, not game terminal; the predicate above is the missing piece.

### 2.5 Reward (Bradley-Terry A/B, the twist)

A capture episode ends when two candidate terminal genomes A and B are surfaced and a judge picks one. That pick is `Compare wHash lHash` (AtlasMove.hs:80), scored by Bradley-Terry `P(A>B) = sigma(u(A) - u(B))` (Preference.btProbability). Two judges, one wire format:
- SELF-PLAY (T2, no humans): judge = shapedReward (AtlasState.hs:115). `z = [shapedReward(A) > shapedReward(B)]`. Bootstrap only; it can only teach the net to imitate shapedReward, so beta MUST be gated to human Compares (section 5.4).
- HUMAN (T3, federated): judge = the user's Review-screen pick. `z` = the human pick.

The reward channel is a contextual-bandit pairwise label, structurally separate from the sequential MCTS return. Do NOT fuse them. See section 5.4 for credit assignment.

---

## 3. LAB reversibility and the 16^3 -> 256^3 abstraction

NOTE: SixFour uses OKLab end-to-end, not CIELAB. "LAB" below means OKLab.

### 3.1 Why the 2x2;2x2 -> 1 map is reversible

The integer S-transform (lifting scheme, JPEG2000-lossless lineage): `sLift x y = (y + floor((x-y)/2), x-y)`, inverted by `sUnlift lo hi = let y = lo - floor(hi/2) in (y+hi, y)` (RGBTLift.hs). Reversible on Z because the high band `hi = x-y` is stored EXACTLY and the inverse subtracts the SAME `floor(hi/2)` it added, so the floor error cancels identically forward and back. `liftQuad`/`unliftQuad` apply it separably to make `(R,G,B,T) = (LL, LH, HL, HH)`. lawLiftUnliftExact and lawLadderBijective (CubeLadder.hs:122) pin the bijection.

### 3.2 The lossless / invented boundary (the honest reward frontier)

- Lossless region: anything at or below captured `64^3` WITH its detail planes retained. `64^3 <-> 16^3` is a closed bijection (lawLadderBijective, CubeLadder.hs:122). `16^3` is the abstraction node: from it you go DOWN losslessly (it carries detail) and UP to `64^3` losslessly (replay stored detail).
- Invented region: STRICTLY ABOVE captured resolution. `synthBeyond` unlifts with detail = (0,0,0) (CubeLadder.hs:92), which is nearest-neighbour replication, exact only where detail was genuinely zero. Everywhere else the zero-detail tensor is WRONG and must be invented (NN super-res). This is the ONE non-invertible step.

CRITIQUE-CORRECTION (the directive overclaims): "abstract UP to 256^3 reversibly" is FALSE above captured resolution. Reframe: `256^3` from captured detail is one-shot terminal synthesis OUTSIDE the reversible MDP. The value net is credited ONLY for detail invented strictly above capture, never for re-deriving what the bijection already preserves (otherwise the game is trivially gameable). This requires a spatial-tier reward term that is structurally zero below `64^3`; today shapedReward has no spatial term (it scores color-value leaves only, AtlasState.hs:115), so this is a build item, not an existing asset.

### 3.3 Two distinct 16^3 lattices (do not conflate)

- SPATIAL 16^3: grid-resolution distill of OKLab pixel planes (the ladder; the directive's "abstract up to 256^3").
- COLOR-VALUE 16^3: OKLab-value binning of the curation board (AtlasMove.hs; okLabBin floor binning).

Both are 16-per-axis over OKLab but along different axes (space vs color value). Type them apart with distinct newtypes (`SpatialBin` vs `ColorBin`) so the type system forbids conflation. Pin ONE a,b working range: use `[-0.5, 0.5]` (what okLabBin actually computes) and amend Color.hs's `[-0.4, 0.4]` to match, or add a law that FAILS on out-of-range a,b instead of clamping silently.

### 3.4 The float/integer split inside the game (resolves contradiction #2)

There are TWO unrelated reversible-Haar systems and four facets conflated them:
- The SPATIAL ladder (`CubeLadder.liftLevel :: Int -> [Int]`, integer, @divFloor, byte-exact). This is `Rung`.
- The SEARCH substrate (`Move.mvDelta :: OKLab` Double; `reconstructPaired` = float PT.reconstruct + sigmaReflect, SigmaPairHead.hs:118; round-trip only `haarClose 1e-9`). This is `Edit`. It is FLOAT, epsilon-reversible, NOT cross-device bit-exact.

So the directive's "reversible 2x2 LAB map" is the integer ladder (Rung), but the move the policy actually plays (Edit) is float. The determinism boundary is therefore the TERMINAL: define the canonical terminal as the Q16/u32 genome hash (GenomeHash, AtlasMove.hs:68), require DecisionLog to store the terminal genome's INTEGER (Q16) leaves, and reconstruct via the integer synthesize so a replayed episode is bit-exact across devices. Float Edit moves may drift in low bits as SEARCH GUIDANCE only. We do NOT claim per-Edit-move bit-exact reversibility; we claim float-reversible in-search, integer-exact at terminal. Add `lawTerminalQuantizationIdempotent`.

RECOMMENDED HARDENING (optional, makes the directive literally true): quantize the Edit substrate to Q16 integer deltas drawn from the DeltaCodebook (the policy is already discrete over it). Then `invertMove . applyMove = id` is EXACT, GenomeHash is over a reproducible integer genome, and replay is bit-exact end-to-end. This is a real port (PairTreeFixed/SigmaPairFixed exist) and is the cleanest resolution; defer it past v1 unless cross-device search replay is required.

---

## 4. Policy and value architecture (ideas ported, not weights)

Shared trunk, two heads: `f_theta(s) = (p, v)`. Ideas ported from the sigma-equivariant trunk; ALL weights re-initialized (the MLX weights are abandoned).

### 4.1 ONE state space for the value head (resolves contradiction #1)

Three incompatible "V" inputs exist in source: spec value is linear `theta` over 770-D atlasEmbedding (AtlasState.hs:120; AtlasOracle.hs:75 awTheta is 770-D); the only PROVEN trainer is a nonlinear MLP over the 384-D genome alone (AtlasTrainer.swift:199 wGenome 384->64, board fused separately, 770 never an input); the heads facet proposed a third (pooled leaves through sigmaInvariantFeatures).

DECISION (v1): the value head is a LINEAR utility over the 770-D atlasEmbedding. Then it IS literally `btUpdate` (PreferenceUpdate.hs:12, eta=0.05, lambda=1e-3, dims=770) and all three spec laws (lawGradientFiniteDiff, lawThetaBounded, lawStepDecreasesLoss) transfer for free. Rewrite AtlasTrainer's value graph to a single linear layer over a 770-D feed and DELETE the 384-genome MLP path. The "proven 12.4 ms/step" number is for the MLP and must be RE-MEASURED for the linear-770 head (it will be cheaper). This is the cheapest path to "proven == spec". A nonlinear MLP-over-770 is a v2 option that requires NEW bounding laws.

### 4.2 Trunk (port LookNetR Mixture-of-Recursions idea)

ONE weight-shared sigma-block-diagonal block applied coreDepth=8 times (LookNetR.hs:9-11), static unroll (control-flow-free, Metal-friendly, LookNetR.hs:70). W masked to a 22x22 achromatic block (484 free) + a 42x42 chromatic block (1764 free) = 2248 free of 4096 (LookNetR.hs:32). On Metal emit TWO dense sub-matmuls (22-wide, 42-wide), not a masked 64x64: exact and halves FLOPs. sigma-equivariance is STRUCTURAL, not trained (this is what the supervised net only got "within tolerance").

### 4.3 Policy head (sigma-equivariant, over Edit moves)

Factored logits: `nodeLogits[127]` (which Haar slot, DeltaCodebook nodeAddressing) and `deltaLogits[12]` (which codebook delta). `p(a|s) = softmax(nodeLogit[lv,ix] + deltaLogit[k])` over LEGAL moves, then routed through the EXISTING atlasPolicy seam (zero priors into killed ch4 bins, exp(weightField) on ch3, forced anchor moves on ch5, top-k=8 renorm, AtlasOracle.hs:179-191). The net REPLACES codebookPolicy's hand-coded coarse-to-fine prior; lawPriorsSumOne / lawWidthLeqEight stay as laws on the seam.

sigma-equivariance CORRECTION: the codebook is sigma-paired as a SET (lawSigmaClosed), but the involution is NOT uniform `k XOR 1`. The L-pair (rows 0,1 = +-L) is sigma-FIXED POINTWISE; only the a- and b-pairs swap. The deltaLogit head must tie rows accordingly: identity on the L-pair, swap on chroma pairs. This needs a NEW law analogous to lawHaltingSigmaInvariance, and a separate law that sigma acts on node addressing as claimed (sigma reflects chroma, not tree topology, but this must be PROVEN, not asserted).

### 4.4 Value head (sigma-invariant scalar = expected A/B win prob)

For the v1 linear-770 head (4.1) the input is atlasEmbedding directly. For a v2 nonlinear head, project the trunk context onto sigmaInvariantFeatures `(||achromatic||^2, ||chromatic||^2)` (LookNetR.hs:62), sigma-invariant EXACTLY because `(-x)^2 = x^2` (bit-identical even in fp32). Train with the Bradley-Terry softplus margin loss `mean softplus(-(V_w - V_l))` (the proven AtlasTrainer loss). BT gives only a RELATIVE utility (margin), so the value is identified only up to an additive constant: frame as an ELO-style ladder vs a previous checkpoint, NOT an absolute win-prob vs a "neutral baseline" (that baseline does not exist in spec).

### 4.5 Equivariant policy / invariant value split

Policy is sigma-EQUIVARIANT: `p(sigma . s) = sigma-permute(p(s))` (chroma reflection permutes the chroma deltaLogits, fixes the L logits, fixes node addressing). Value is sigma-INVARIANT: `V(sigma . s) = V(s)`. This is the clean AlphaZero symmetry split and it is a CONSTRUCTION theorem (the supervised net's failure was getting equivariance only "within tolerance"; here it is structural).

---

## 5. Bare-metal SIMT + Metal engineering

Numeric law spanning all kernels: INTEGER/Q16 byte-exact where state lives and replays; fp32 ordinal-only where the net guides. The @divFloor-vs-Metal-truncation trap bites every signed integer division: Metal int `/` and `>>` truncate toward zero, Zig `@divFloor` and Haskell `div` floor toward -inf. Disagree by 1 LSB on negatives, which breaks the lift's floor-cancellation. Every Metal integer-division site MUST use an explicit `floorHalf`/`floorDiv` helper (port RGBT4DLift.floorDiv).

### 5.1 Collapse kernels (the Rung ladder, integer, byte-exact)

`SixFour/Metal/Cube.metal`: `cubeLiftLevelKernel`, `cubeUnliftLevelKernel`, plus synthBeyond via unlift + a host zero-detail buffer (single code path, do NOT write a separate null-flag kernel). One SIMT thread per 2x2 BLOCK (not per pixel), `bi = by*h + bx` linearization matching the Zig by-outer/bx-inner loop. Disjoint writes (bi is a bijection block->slot) so NO barriers, NO atomics; pure deterministic function of input.
- Numeric contract: `==`, zero tolerance, i32 only (never short/half; overflow headroom for T=hh ~2x range). Floor-div via floorHalf.
- Parity gate: this is the FIRST byte-exact integer-Metal-vs-Haskell golden in the repo (do not oversell it as extending field.metal, whose "verified" comment is currently unbacked). Three-way fan against the EXISTING RGBT4DGolden: Metal == golden, Metal == Zig (s4_cube_lift_level), Metal == Swift. Keystone test: a NEGATIVE-heavy fixture (e.g. (-7,3,-128,65) plus -128/+127 boundary quads) round-trips `unlift(lift(g)) == g`. This MUST pass on real A19/M-series hardware, not just the simulator (the MSL int-div semantic is the actual risk).
- This kernel implements the cube-ladder ABSTRACTION transition only. It is NOT an AtlasMove ply; do not pin it against a move-result.

### 5.2 Net forward (fp32, hand-written Metal, sim-runnable)

Plain Metal compute (runs in the simulator, unlike MPSGraph) loading the fp32 blob. This is the search-time evaluator. For v1 linear-770 value head: a 770-D dot + sigmoid, trivial. For the policy head: board encoder (6->64 per-bin linear + pool), 8-step unrolled trunk (two dense sub-matmuls per step), factored 127 + 12 logits.
- Numeric contract: fp32 ORDINAL-only. The boundary that must agree cross-device is the ARGMAX (selected node, delta) with a documented lowest-index tie-break (mirroring nearestCentroidQ16 strict-<), and `sign(V_w - V_l)`, NOT the float logits. Use a FIXED-order tree reduction (no atomic float adds; the cited kmeans precedent uses atomic_fetch_add and is a determinism ANTI-pattern here) so per-device run-to-run value is stable.
- Input-side determinism gap (must close): the board's 6 float channels accumulate `1/n` (non-dyadic, order-dependent) via AtlasBoard.histogram and bin via float okLabBin (boundary-flip on 1 ULP). Pin the board-from-Q16-histogram derivation with its own golden vector (Zig == Swift == Haskell) before trusting argmax stability. Float leaks at the FIRST matmul otherwise.
- Parity gate: ordinal/argmax agreement against a Haskell reference. That reference is `Spec.AtlasNetEval` (section 8, must be written BEFORE deleting the MLX file, since atlas_net_mlx.py is the only existing forward definition of these heads; LookNetEval.hs is the ABANDONED trunk, LookNetEval.hs:5).

### 5.3 Search (Gumbel-AlphaZero, CPU tree + GPU batched value)

DO NOT port classic sequential PUCT to Metal. Use Gumbel-AlphaZero (Danihelka et al. 2022): branching is capped at 8 (policyWidth, AtlasOracle.hs:93), so root action selection is Sequential Halving over ALL 8 children with no sampling loss, removing PUCT's c, P, sqrt(N) tuning and the Dirichlet noise we already wanted off-device. It gives a provable policy-improvement guarantee at tiny simulation counts, which IS the interactive on-device budget, and the search output is then a valid policy-training target.
- Tier A (CPU/Swift): rose tree, Gumbel/Sequential-Halving selection, expand, backup, seeded tie-break (argmaxWithSeed). Pointer-chasing, integer; does NOT belong on GPU.
- Tier B (Metal): a batched value oracle. CPU collects a FRONTIER of M=64..128 expanded states, one dispatch evaluates all, reads back M scalars, backs them up. Dynamics are KNOWN and reversible, so the GPU NEVER simulates dynamics (no MuZero latent model, which would also break the determinism contract) -- it only evaluates value.
- COST CORRECTION: beautyLossLeaves is O(256) ADJACENT pairs (128 pairs), NOT O(256^2). Drop the threadgroup-tiling-of-a-256x256-matrix design; one thread per leaf, one threadgroup per candidate suffices. Latency is dominated by dispatch/readback, so frontier batching is the real lever. Whole search budget is low-single-digit ms at gallery-generation time (Review screen, not the 20fps capture loop).
- Numeric contract: the SEARCH (transition, reconstruct, value) is float in spec, so it is a RANKING tier. To match the proven-deterministic Haskell tree EXACTLY (lawDeterministic relies on EXACT Double-equality tie detection in argmaxWithSeed, PaletteSearch.hs:218): quantize the GPU value to a fixed Q16 comparison KEY on a fixed-order reduction, so CPU and GPU agree on the integer tie key. Do NOT rely on an epsilon bound that "never flips a decision" while the live invariant is bit-equality of the tie set.
- Gallery extraction stays CPU (extractGallery DPP). Tension to rule (taste call): more exploration gives a more DIVERSE gallery (good for swipe options) but less policy-improvement optimality. Possibly keep a small exploration term specifically for gallery diversity.

### 5.4 On-device training (MPSGraph, the sanctioned framework)

DECISION: MPSGraph custom loop for BOTH Mac cold-start and device fine-tune, NOT hand-written Metal backprop. Reasons: backward is proven correct and fast on target silicon (AtlasTrainer.swift, value path), MPSGraph is an OS framework so Tier-2 zero-dep holds, the model is ~16K-115K params so latency/power are negligible, and a hand-rolled autodiff is a large new golden surface for no win. Hand-written Metal is reserved for the FORWARD pass only (5.2, which must run in the sim).
- Stage 0 (Mac cold-start): expert iteration. Run Gumbel-search with the zero-weights oracle (zeroAtlasWeights, AtlasOracle.hs:80) as teacher; regress policy to MCTS VISIT-COUNT distribution (cross-entropy) and value to the backed-up returns. NOTE: today train_atlas_mlx.py regresses policy to the oracle's TOP-8 one-ply lookahead, NOT visit counts; the true visit-count target is UNBUILT. Re-host on Mac MPSGraph (kills the last shipped MLX usage); MLX may remain a Tier-1 Mac TOOL per CLAUDE.md (rule it explicitly), but the shipped blob is plain fp32 s4 format, never an MLX/CoreML artifact.
- Stage 1 (deploy): ship the fp32 blob in the bundle; the hand-Metal forward (5.2) loads it.
- Stage 2 (on-device fine-tune): the VALUE head fine-tunes from real Compares via btUpdate (linear-770, so the spec laws hold). The beta = n/(n+50) ramp (AtlasOracle.hs:85) hands from shipped shapedReward to learned BT utility. CRITICAL: gate beta on the count of HUMAN Compares (`awHumanCompares`), NOT synthetic-judge Compares, or the net provably collapses onto shapedReward. The POLICY head stays FROZEN on device for v1 (on-device expert iteration needs MCTS + forward in the train loop + visit-count storage; deferred). Add the `-eta*lambda*theta` L2 decay term to the MPSGraph update (it omits it today) or lawThetaBounded does not hold.
- Credit assignment (resolves #5, OWNED here as an enforced law): exploit the GenomeHash join. `Compare wHash lHash` carries both; VDST visit-distributions are keyed by GenomeHash. RULE: the WINNER's generating-search root visit distribution is reinforced (positive KL target, full weight); the loser's is down-weighted behavior-clone at 0.3 or dropped (matching COLOR-ATLAS T3). Gate informative pairs at the SOURCE: extractGallery must reject a pair whose `||embedding(A) - embedding(B)||^2 < threshold` (else lawStepDecreasesLoss's informativeness precondition is vacuous and the BT gradient is ~0). Law: `lawGalleryPairInformative`.
- Kill-switch (epistemic hygiene, must exist before any preference NN training): port QUAD fitOLS into a real `Spec.GLRM` module; regress logged BT outcomes on [coverage, beauty, ||chroma||^2]; if no stable beta-hat / R^2, the preference data is noise -> STOP. It is referenced as shipped in COLOR-ATLAS but does NOT exist in the repo; build it or strike the claim.

### 5.5 SIMT / Metal verified facts (web-researched 2026-06-17)

The "Zig + Metal SIMT" agreement was grounded against current sources, not assumed. Three load-bearing facts:

1. Zig does NOT compile to Metal. Zig's self-hosted GPU backend (0.15.x) emits SPIR-V / PTX / AMDGCN for Vulkan / OpenCL / CUDA, and is ~50 percent through its own behavior tests on Vulkan. Metal Shading Language consumes none of these; bridging SPIR-V to MSL means MoltenVK / SPIRV-Cross, which are third-party dependencies and violate the Tier-2 zero-dep rule. CONCLUSION: Zig is the CPU integer REFERENCE (`s4_*`), MSL is the GPU SIMT kernel, and the two agree ONLY through golden vectors. There is no single "Zig-to-Metal" compiler; the parity gate (S4) is the agreement.

2. MSL signed integer division and shift truncate toward zero (C++14 semantics), not floor. Zig `@divFloor` and Haskell `div` floor toward negative infinity. They disagree by 1 LSB on negative operands, which breaks the lift's floor-cancellation. EVERY signed-integer division in a Metal port MUST use an explicit floor helper (port `RGBT4DLift.floorDiv`); never the bare MSL `/` or `>>`.

3. Metal `simd_sum` and threadgroup reductions have UNSPECIFIED lane order, so float reductions reassociate and are not bit-reproducible across dispatches or devices. CONCLUSION: any value the CPU tree must agree with cannot come from a raw `simd_sum`. The GPU evaluates the batched frontier with a FIXED-order reduction and quantizes to the Q16 integer comparison key (`Spec.GumbelSearch.q16Key`); the integer key, not the float, is the cross-tier contract (`lawArgmaxKeyDependsOnlyOnKeys`: a sub-key float wobble cannot flip a move).

Sources: Apple, Metal Shading Language Specification v4 (developer.apple.com/metal/Metal-Shading-Language-Specification.pdf); alichraghi.github.io/blog/zig-gpu (Zig GPU / SPIR-V status); kieber-emmons, "Optimizing Parallel Reduction in Metal for Apple M1".

---

## 6. Chosen algorithm and why

Gumbel-AlphaZero (Danihelka, Guo, Schrittwieser, Silver, ICLR 2022) for the shipped search; classic persistent-tree PUCT (PaletteSearch.mctsStep, kept verbatim) for the Mac expert-iteration harness where budget is free.

Rationale, grounded:
- Branching is capped at 8 (policyWidth, AtlasOracle.hs:93). Sequential Halving over <=8 actions is near-exhaustive and provably non-regressive; full PUCT exploration is overkill.
- The reward is smooth/deterministic (shapedReward), not sparse win/loss, so one-ply value estimates are informative and deep lookahead is not needed.
- Gumbel-AZ is the principled "PUCT without Dirichlet" we already wanted for determinism, and it gives a policy-improvement THEOREM at tiny fixed simulation count, which makes the search output a sound policy-training target (the expert-iteration flywheel).

Ports from prior art (ideas, with the highest-leverage first):
1. KataGo (Wu 2019) AUXILIARY TARGETS: add cheap heads predicting stateCoverage / stateBeauty / gamutCoverageFraction (all golden-computable, zero labeling cost). This DENSIFIES a sparse-preference signal and is the single best mitigation for "the supervised net did not train well." Plus gated promotion (a new net ships only if it beats the incumbent on held-out BT log-loss AND maintains per-class coverage >= maximin baseline).
2. RLHF reward-model hygiene (Christiano 2017, Ouyang 2022): anchor the learned reward to the deterministic shapedReward (the 0.3*MSE anchor, make it a LAW not a curriculum note); the beta ramp is the KL-to-prior analog; the GLRM kill-switch is the reward-model-calibration discipline.

REJECT MuZero / Stochastic-MuZero: learned latent dynamics solve a problem we do not have (unknown dynamics) and would break the byte-exact reversible-lift determinism contract. The true model is a 4-int SIMD stencil.

---

## 7. Cross-facet conflicts resolved

- #1 state space: value head is LINEAR over 770-D atlasEmbedding (5.4, 4.1). Delete the 384-genome MLP; re-measure latency. Owner: Phase M2.
- #2 determinism boundary: two Haar systems are typed apart (Rung integer ladder vs Edit float substrate). Determinism boundary is the Q16 TERMINAL hash, not per-move (section 3.4). Owner: Spec.AtlasGame + lawTerminalQuantizationIdempotent.
- #3 unified move ADT: `GameMove = Edit | Curate | Rung`; Compare lifted out as the reward (section 2.2). Owner: Spec.AtlasGame.
- #4 policy half not closed: stated honestly throughout. v1 ships value-only on device + frozen pretrained policy; policy training is a v2 deliverable with the visit-count cross-entropy bridge spec'd (5.3, 5.4). Reframe headline from "AlphaZero closed loop" to "Gumbel-search over a learnable BT value with an offline-pretrained policy."
- #5 credit assignment: OWNED as lawGalleryPairInformative + the winner-VDST-reinforce / loser-BC-0.3 rule + the GLRM gate (5.4).
- #6 golden source of truth: write `Spec.AtlasNetEval` (the AtlasNet head forward in Haskell) BEFORE deleting atlas_net_mlx.py; it is the only existing forward definition. Owner: Phase M1, gated before teardown step 3 touches MLX (note: teardown does NOT delete atlas_net_mlx.py, only the trained .npz, so the reference survives; still write the Haskell oracle).
- #7 false premise: the trained artifacts are STILL ON DISK (verified: look_net_trained.s4ln 133923 B, atlas_net_trained.npz 257218 B, synth_looknet_grayscale.gif). The teardown below actually deletes them; the reframe's "port ideas not weights" is ENFORCED by the checklist, not assumed.

---

## 8. DEAD-MLX TEARDOWN PLAN (ordered checklist)

Execute in order. The gate edit MUST precede the file deletion or the gate goes red the instant the artifact is gone.

1. EDIT THE GATE FIRST. In `scripts/verify-doc-claims.sh`, DELETE the entire check at lines 86-87 ("trained deploy blob exists (133923 bytes)..." / `test "$(stat -f%z trainer/out/look_net_trained.s4ln ...)" = "133923"`). This is the ONLY gate pinning the dead MLX blob. Do NOT repoint it at look_net.s4ln (TRAP: that re-introduces a brittle byte pin and conflates the surviving regenerable golden fixture with the dead trained blob). Loader-code coverage already lives at lines 88-89.
2. KEEP UNCHANGED lines 88-89 ("Zig blob loader verified by fixture test" / `grep -q 's4_load_look_net' Native/src/fixture_test.zig`). Asserts the loader CODE/test exists (an idea kept), references no trained artifact.
3. Run `scripts/verify-doc-claims.sh`; confirm GREEN with the trained blob still on disk (proves only 86-87 depended on it).
4. DELETE the dead trained outputs: `trainer/out/look_net_trained.s4ln`, `trainer/out/atlas_net_trained.npz`, `trainer/out/synth_looknet_grayscale.gif`. (gitignore line 20 ignores trainer/out/; repo is not git-tracked here, so non-destructive to VCS. All are regenerable.)
5. (Recommended) run `python trainer/export_look_net_blob.py` to (re)assert `look_net.s4ln` + `look_net.spot.json` are present so the Zig fixture test actively PASSES rather than skips. Skipping is also safe (the test skips-if-absent).
6. Build/run the Zig suite (`zig build test`); confirm `fixture_test.zig` passes-or-skips, never reds, without the trained blob (it reads the GOLDEN-derived look_net.s4ln, not the trained one; cmp confirms they differ).
7. Re-run `scripts/verify-doc-claims.sh`; confirm still GREEN after deletion.
8. NO CODE CHANGE to `Native/src/fixture_test.zig` (loads the regenerable golden fixture, skips-if-absent). Do NOT delete it or look_net.s4ln / look_net.spot.json (loader-code verification, an idea kept).
9. KEEP (do not delete): `trainer/out/look_net.s4ln` (golden fixture, not trained), `look_net.spot.json`, `trainer/generated/look_net_golden.json`, `Native/src/kernels.zig` lift + `s4_load_look_net` loader, `SixFour/Atlas/AtlasTrainer.swift` (sanctioned MPSGraph trainer for the new value head), `trainer/export_look_net_blob.py` (fixture producer), the spec modules (RGBTLift, CubeLadder, Atlas*, Preference*, DecisionLog, SigmaPairHead, LookNetE/R/D). Flag `regimen.py / train_look_net_mlx.py / train_atlas_mlx.py / atlas_net_mlx.py / eval_l_quality.py` as needing REFRAME toward policy/value (they will error at runtime reading deleted outputs; Mac-side Tier-1, not on any gate; out of scope for the purge). IMPORTANT: capture atlas_net_mlx.py's head algebra into `Spec.AtlasNetEval` before any later reframe edits it (the only forward definition of the AtlasNet heads, finding #6).
10. LAST, update docs (prose edits cannot red a gate; the only gated anchor is the deleted line 86-87):
    - `docs/STATUS.md:185` (canonical ledger, edit FIRST): remove the claim that look_net_trained.s4ln (133,923 B) exists; replace with a note that supervised MLX look-net is abandoned (output deleted) and the core is reframed AlphaZero-shaped (policy+value over the Atlas state machine, Bradley-Terry A/B reward).
    - `docs/SIXFOUR-ARCHITECTURE-MAP.md:104,190,261-262`: drop the four claims that the trained blobs are on disk / "the trainer produced a deploy blob". Reframe: forward path + Zig loader CODE kept (loads the golden fixture); supervised trained weights abandoned; sigma-pair/sigma-equivariant trunk ported as IDEAS.
    - `docs/APP-MAP.md:305`: remove the look_net_trained.s4ln parenthetical; note the MLX deploy blob is abandoned, loader code retained.
    - `docs/HANDOFF-LNN-app-io-and-ui.md:20,150`: remove "Weights ship as a blob: look_net_trained.s4ln" and the train step; mark the supervised L-NN deploy path abandoned for the AlphaZero reframe.
    - `docs/SIXFOUR-STATE-INSPECTION-2026-06-17.md:39`: keep "s4_load_look_net fixture-verified" (true via golden fixture); strike the trained-blob row; status -> "trained blob ABANDONED/DELETED; loader code retained, 0 callers".
    - `docs/ON-DEVICE-TRAINING.md`: do not imply a usable supervised trained blob exists; KEEP the MPSGraph on-device-training section (it is the sanctioned trainer for the new value head).
    - `docs/COLOR-ATLAS.md:83,260,308,435`: leave the .s4ln v2 FORMAT + export_look_net_blob.py + atlas-trainer DESIGN text (ideas); add a note that atlas_net_trained.npz (the trained instance) was deleted and is regenerable.

---

## 9. Phased, spec-first build sequence

Each phase: edit Haskell spec -> `cabal test` (laws) -> `cabal run spec-codegen` (regen goldens) -> Swift/Zig/Metal port -> golden gate green.

S (small, the honest purge + foundations):
- S1: execute the teardown (section 8). Gate: verify-doc-claims.sh green + Zig suite green.
- S2: write `Spec.AtlasNetEval` (AtlasNet head forward in Haskell) from atlas_net_mlx.py before any reframe edits. Gate: golden vectors for (board, embedding) -> (policy logits, value) emitted; this becomes THE ordinal source of truth (#6).
- S3: `Spec.AtlasGame` wrapper: `GameMove = Edit | Curate | Rung`, terminal predicate, RungMove legality (Ascend-beyond-capture forbidden). Gate: lawTerminal well-defined, lawRungLegalityForbidsSynthBeyond, no edit to PaletteSearch/AtlasMove (#3).
- S4: Cube.metal collapse kernels + the first byte-exact integer-Metal golden (5.1), negative-fixture round-trip on real hardware. Gate: Metal == Zig == Swift == golden, `==`.

M (medium, the value loop closes honestly):
- M1: rewrite AtlasTrainer value graph to linear-770 over atlasEmbedding; add L2 decay; re-measure ms/step. Gate: device BT step == btUpdate, lawThetaBounded/lawGradientFiniteDiff hold; sim-gated.
- M2: board-from-Q16-histogram golden (Zig == Swift == Haskell) to pin input determinism (5.2). Gate: byte-exact board float derivation.
- M3: hand-Metal value forward (sim-runnable) + ordinal gate vs Spec.AtlasNetEval. Gate: sign(V_w - V_l) agreement on golden fixtures.
- M4: `Spec.GLRM` kill-switch + lawGalleryPairInformative + winner-VDST/loser-BC credit rule (5.4). Gate: preference NN training BLOCKS when R^2 unstable; degenerate pairs produce zero weight.
- M5: Gumbel-AlphaZero search, CPU tree + GPU batched value (5.3), Q16 comparison-key tie-break. Gate: lawDeterministic preserved; GPU value tie-key == CPU.

L (large, the policy half + abstraction):
- L1: policy head (factored 127 x 12, sigma-equivariant) + the corrected sigma involution law (L-pair fixed, chroma swap, 4.3). Gate: lawPolicySigmaEquivariant.
- L2: KataGo auxiliary heads (coverage/beauty) + gated promotion (section 6). Gate: held-out BT log-loss + coverage >= maximin.
- L3: Mac MPSGraph expert iteration with TRUE visit-count policy targets; on-device policy fine-tune (un-freeze). Gate: visit-count cross-entropy loss; promotion gate.
- L4 (optional): Q16 Edit substrate (3.4 hardening) for bit-exact cross-device search replay. Gate: invertMove . applyMove == id exactly; end-to-end replay bit-exact.

---

## 10. Honest risks and residual product/taste calls

Risks:
- The policy half is genuinely unbuilt. v1 ships value-only-on-device + frozen pretrained policy. If the pretrained policy is weak, the gallery quality rests entirely on Gumbel-search + shapedReward + the value re-ranker. The KataGo auxiliary heads (L2) are the main hedge against the same "did not train well" failure recurring.
- Argmax stability under fp32 reassociation is asserted, not measured. The discrete golden gate is only achievable if the top-1 policy margin and sign(V_w - V_l) exceed the cross-device fp32 error on real hardware. Must be measured on A19/M-series, not assumed.
- Self-play (T2) can only imitate shapedReward; the twist's real content is at T3 (human z). If users do not generate enough Compares, beta never ramps and the "learned" core is just the deterministic oracle.
- BT is margin-only (relative). Choose the checkpoint-ladder framing or the value is unidentifiable.
- The Q16 Edit-substrate port (L4) is real work; until then "byte-exact game replay" holds only at the terminal, not per-move.

Residual product/taste calls only the user can make:
- The pick-four / A/B surfacing UX: are A and B two independent searches, two DPP-gallery picks from one search, or one search plus a perturbation? This sets how correlated (and how informative) the BT pairs are.
- Gallery diversity vs policy-improvement optimality (5.3): how much exploration to keep purely for swipe-option variety.
- Is the baseline a previous checkpoint (ELO ladder, relative) or a fixed reference palette (absolute)? Recommend checkpoint ladder.
- Whether MLX stays as a Tier-1 Mac TOOL (CLAUDE.md still permits it) or is purged entirely from tooling. The reframe abandons the OUTPUT; the trainer-as-tool decision is yours.
- Whether to fund L4 (full cross-device bit-exact search replay) or accept terminal-only determinism for v1.
