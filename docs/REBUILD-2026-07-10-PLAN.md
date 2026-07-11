# THE REBUILD — 64³ color-time, simpler and robust (2026-07-10)

Daniel's directive (verbatim intent): take the app apart and restructure it so it is
simpler and robust. The 64×64×64 tensor is the canonical substrate — each cell a
small tensor of information. The app keeps making the GIF with classical
algorithms; the 64³ records train a model that should eventually beat the
classical pipeline. Probe the camera hardware up the ladder
16³/32³/64³/128³/256³/… (training-data generation), always collapsing to the
64³ reality. The app must PROVE with a device log that it takes the three
resolutions; the {16,32,64} ladder must be MATHEMATICALLY PROVEN to train the
model on color time. Ladder symmetries via fold algebra (foldr/foldl); 16 and
256 are each two octaves from the 64 reality.

Ground rules inherited from the 2026-07-10 sunset (SESSION-2026-07-10-NOTES.md):
device-fit and debt-budget are gates now. One unit, landed small,
device-verified, THEN deepen. Nothing below is exempt.

---

## 1. What the research established (three agents, 2026-07-10)

### 1.1 NN literature (why this design is right, and what the model should be)

- **GIFnets** (Google, CVPR 2020, arXiv:2006.13434): PaletteNet + DitherNet +
  BandingNet beat median-cut + Floyd–Steinberg while emitting standard GIF89a.
  Existence proof for "model beats the classical pipeline". Not temporal —
  color-TIME is open ground and is our edge.
- **FSQ** (ICLR 2024, arXiv:2309.15505): a product lattice of quantization
  levels IS an implicit codebook (no learned VQ tables, no collapse). Our 64³
  bin lattice = FSQ with levels {64,64,64}. The classical pipeline and the
  learned model share one discrete space by construction.
- **Multigrid video training** (Wu et al., CVPR 2020, arXiv:1912.00998; theory
  arXiv:2501.12739): variable spacetime-resolution schedules train faster AND
  generalize across grids; coarse grids buy gradient-variance reduction
  cheaply. Our {16,32,64} ladder is the exact-integer version (their grids are
  lossy bilinear; ours are exact u64 folds).
- **V-JEPA 2 / VideoMAE** (arXiv:2506.09985 / 2203.12602): mask spacetime
  tubes, predict representations. For us the target representation is GIVEN
  and EXACT — the integer pooled cell tensors — so there is no collapse
  problem and no EMA target encoder ("Moment-JEPA").
- **Time-varying palette geometry** (SIGGRAPH 2021 skew polytopes): the most
  literal published "color time" — palette as trajectory. Cheap fallback head.

**Ranked model direction (the review Daniel asked for):**
1. **Temporal PaletteNet by distillation** — small net reads the 64³
   cell-tensor cube, emits the 256-entry palette (+ soft index logits);
   trained in MLX with the classical pipeline's own output as the initial
   target, then surpasses it with a temporal-flicker + banding loss.
   Hand-writable forward pass (convs/MLP) — inside the zero-dependency rule.
2. **FSQ framing** on the existing bin lattice + tiny masked cell-code
   predictor (MAGVIT-v2's lesson: the tokenizer is the bottleneck — ours is
   exact and free).
3. **One weight-shared fully-convolutional net trained multigrid** on
   {16,32,64} with the EXACT cross-scale constraint pool(f(64)) == f(pool(64))
   as a consistency loss; 128/256 probes are the generalization test.
4. **Moment-JEPA pretraining** (mask late t-slices, predict exact cell
   tensors) as the Mac-side MLX recipe feeding 1–3.
This replaces the never-trained full-matrix H-JEPA as the working model plan;
SIXFOUR-MODEL.md remains the north-star document for the invention-above-floor
idea, but the reachability gap (contractDescentOnRealDataUnproven) is attacked
with direction 1 on REAL .s4cr corpora — per the floored-is-data-not-architecture
lesson.

### 1.2 Model audit (what exists)

Three learned-object lineages, one live: θ_up (21 params, per-capture, plain
Metal, decorative-safe: zero-gene == floor). θ_B band head dormant. LookNet
deleted. H-JEPA full-matrix: spec-complete, no trainer, never reached the
floor on held-out loss. The color-time spec spine (ColorTime, GaussianLadder,
EventEncoding, TriScaleTraining, FidelityLadder, LadderIdentity) is tight,
mutually referencing, and ~80% of the theorem Daniel wants. The .s4cr v2
record already carries c64/c32/c16 u64 sum cubes (independent mode) or the
c16-only derived signature. No 128/256 captured tier exists anywhere (256³ is
synthesis-only, Upscale256/CubeLadder).

### 1.3 Hardware feasibility (iPhone 17 Pro, iOS 26)

- Cost scales with CROP pixels, not bins ⇒ 128² is free at today's crop 512;
  256² needs GPU pooling and/or crop 1024 (1080p-class x420).
- 512² gated on one empirical unknown: does ANY 4K-class format deliver
  x420 through AVCaptureVideoDataOutput on this phone (the btp2 trap)?
  1024²+ is jetsam territory. Predicted ceiling: 256² sustained.
- Sensor fact for the theorem doc: all video formats are quad-binned in
  silicon (48MP→12MP) — the first 2×2 fold happens in hardware
  (isVideoBinned is the API witness; PERF-MAP §4.5 purity order).
- Existing proof-log machinery: [perf] tick lines, BurstTiming drop counts,
  per-rung [perf] rung N² lines, systemPressureState telemetry. The ONE
  missing baseline number: device-measured tick CPU at crop 512 — no real
  run was ever logged.
- EV-ladder settle latency scales ~3–4× exposure duration (Apple forums
  751112) — log realized settle, don't assume settleFrames=2 holds at the
  coarse rung's long exposures.

---

## 2. The target architecture (simpler and robust)

ONE spine, four boxes, everything else deleted or quarantined:

```
CAMERA (AVFoundation, re-authored small)
  └─ 64-frame burst @20fps, 10-bit x420, crop 512 (probe may raise to 1024)
POOL (Kernels/ + Metal twins — KEPT, golden-gated)
  └─ exact u64 sums at every ladder rung; canonical 64³ cell-tensor record
      cell tensor v1 = (ΣR,ΣG,ΣB) u64 linear flux  [moments/χ² later, additive]
GIF (classical, KEPT: DeterministicRenderer + Encoder/ + palette16 floor)
  └─ app-export GIF == encoder input; byte-exact; the model's supervision target
RECORD + TRAIN (.s4cr v2 cubes → Mac MLX corpus; θ_up stays on device)
  └─ phone generates training data; Temporal PaletteNet trains on the Mac
```

KEEP (moves into the rebuilt target unchanged): Kernels/ (all 12 files),
Metal/ twins, ColorHead.swift + MultiScaleLadder.swift + RungReads/Telemetry +
CaptureRecord.swift (all AVFoundation-free), Encoder/, Train/ (θ_up spine),
Generated/ (regenerated anyway), the whole Haskell spec, VoxelReduce.

RE-AUTHOR small: CaptureSession (87KB → target <1/3 of it), the UI (one Live
surface + one Decide surface, form-follows-function charter, device-fit gate
BEFORE any composition lands).

DELETE (Stage 2, only after Daniel approves the list + probe verdict):
Merge/ + v3 decision-word writers (spec modules stay — true math), Tube/
(TubeGenerator has 0 refs) + THE SCROLL UI, Organs/, GeneLibrary/ (quarantine:
orthogonal to color-time; S4GX genes still cross via files), RGBT4DLift (keep
VoxelReduce), all Feature-off paths (globalPaletteV2, lutExport, opticalEV,
multiScaleRender, metaInitW0), UI scenes beyond Live/Decide. Rough cut:
~15–17k LOC of the ~37k goes.

Wire contracts that SURVIVE regardless (sunset notes): .s4cr v1/v2 bytes
pinned; the capture-format contract (app-export GIF == encoder input,
replicate2D ≠ upscale256); the GIF89a delay law 64@20/32@10/16@5.

"Bigger square GIF": display-size decouples from data-size. The GIF stays
64×64×64-frames canonical; export offers an integer-replicated bigger raster
(replicate2D, palette/index untouched) so the file views larger with ZERO new
information — the 64³ record remains the truth the model trains on. True
higher-res capture beyond that is a post-probe decision (needs the 256²
verdict + a new delay-law rung, side | 320).

---

## 3. The stages (each ends at a device gate)

**Stage 0 — PROVE (this session, additive only, no deletions).**
- S0a `Spec.LadderColorTime` — the consolidating theorem module (§4).
  Gate: cabal test green; theorem doc section in this file.
- S0b The LADDER PROBE (`Feature.ladderProbe`, default false) — per burst,
  pool the SAME crop at {16,32,64,128,256} independently, then verify the
  fold algebra on real photons and emit the proof log (§5). Includes the
  format census (log every x420 candidate incl. 4K verdict + isVideoBinned).
  Gate: BUILD SUCCEEDED (compile-only rule) → Daniel runs on the phone →
  the log IS the deliverable.
- S0c This plan doc.

**Stage 1 — REBUILD the target (after probe verdict).** New minimal app
target (project.yml second target) assembling KEEP-list sources + the small
re-authored CaptureSession + minimal Live/Decide UI. Old target stays
buildable throughout (the escape hatch). Device gate: parity capture — same
scene, old vs new target, byte-identical GIF + .s4cr.

**Stage 2 — DELETE (Daniel approves the list explicitly).** Execute the
delete list; old target removed; docs pruned to match. Gate: full suite green
+ one device capture session.

**Stage 3 — CORPUS + MODEL.** .s4cr export ergonomics (AirDrop batch), Mac
ingest, MLX Temporal PaletteNet v0 distilled from the classical pipeline;
multigrid schedule over {16,32,64}; cross-scale exact consistency loss.
Gate: v0 matches classical output (distillation floor) before any
"beat it" claim; then flicker/banding loss ablation.

**Stage 4 — CLOSE THE LOOP.** Hand-written Swift/Metal forward pass for the
trained palette head (zero-dependency rule), golden-gated against MLX,
behind a flag, decorative-safe (zero-model == classical floor), A/B on
device.

---

## 4. The mathematical proof (S0a: Spec.LadderColorTime)

THEOREM (color-time ladder). Training on the {16³,32³,64³} ladder is training
on color time, because:

1. **Pooling is a commutative-monoid fold.** A cell's tensor is the u64
   coordinatewise sum of its children — the fold of (ℕ³,+,0) over the block.
   Commutativity + associativity ⇒ foldl = foldr = any traversal order
   (Daniel's symmetry). Law: `lawFoldOrderInvariant`.
2. **The ladder is transitive (associativity, spatially).**
   pool64→16 = pool32→16 ∘ pool64→32 exactly (already teeth-tested in
   palette16; restated at cube level). Law: `lawPoolTransitive`.
3. **64 is a retract of every finer rung.** expand64→128 (replication) then
   pool128→64 is the identity; dually pooling is a projection. The chain
   16 ⇇ 32 ⇇ 64 ⇄ 128 ⇄ 256 makes 64³ the fixed point every rung maps onto;
   |log₂(side/64)| = 2,1,0,1,2 — 16 and 256 equidistant from the 64 reality.
   Laws: `lawPoolExpandIdentity`, `lawLadderSymmetricAboutSixtyFour`.
4. **The fold index IS color-time.** One integer k simultaneously = spatial
   coarsening, temporal pool depth, optical stops (ColorTime:
   lawColorTimeQuartic, τ_c = 4^k·Δ₀) and the ℤ[i] ideal norm
   (GaussianLadder: lawNormIsColorTime). Coarser rung ⇔ MORE color-time ⇔
   √τ_c better chroma SNR (lawSnrSqrtPowerLaw). So a model shown the three
   rungs is shown the SAME scene at three color-time exposures — the ladder
   axis is literally the color-time axis. Restated: `lawRungIsColorTimeStop`.
5. **The rungs carry disjoint training signal at invariant density.**
   Transitions 16→32 and 32→64 train DISJOINT bits; info-per-compute is
   rung-invariant; all three rungs cost 9/8 of the finest alone
   (TriScaleTraining). Refinement is monotone to zero error over ℚ
   (FidelityLadder: lawDeeperIsCloser). Temporal dither decode has zero
   irreducible loss given (signal, phase) (EventEncoding: lawHermiteDither).

1–3 are the fold-algebra half (new laws, this module). 4–5 are the
color-time half (proved in existing modules; this module re-states the
composite and pins the numeric identities across k ∈ {-2,…,2} rungs).
The DEVICE half of the proof is §5's transitivity check on real photons.

---

## 5. The proof log (S0b: what Daniel reads on the phone)

Once per probe burst, subsystem com.sixfour.SixFour, search `[proof]`:

```
[proof] format: 1920×1080 x420 20fps binned=true (4K x420: ACCEPTED|btp2-EXCLUDED)
[proof] rung 256²: 64/64 frames, pool crop512→2×2px bins, tick mean/max A/B ms
[proof] rung 128²: 64/64 frames, …
[proof] rung  64²: 64/64 frames, …            ← the canonical cube
[proof] rung  32²: 64/64 frames, …
[proof] rung  16²: 64/64 frames, …
[proof] fold: pool(256→64) == direct64  BYTE-IDENTICAL (lawPoolTransitive on-device)
[proof] fold: pool(128→64) == direct64  BYTE-IDENTICAL
[proof] fold: pool(64→32→16) == pool(64→16)  BYTE-IDENTICAL
[proof] foldl==foldr: forward/reverse accumulation identical (commutative monoid)
[proof] collapse: canonical 64³ cell-tensor record N MiB, 64 slices × 64·64·3 u64
[proof] budget: dropped=0, worstΔ=… ms, pressure=nominal, 5-burst drift=…
```

The three-resolutions proof Daniel asked for = rung 16/32/64 lines with
64/64 frames + the two BYTE-IDENTICAL fold lines: the phone itself verifies
the theorem's laws 1–3 on real photons every probe burst. 128/256 lines are
the training-data capability census; their pass criteria: dropped=0, tick max
under budget, stable across 5 bursts, pressure logged.

---

## 6. Open questions (parked, not blocking Stage 0)

- 512² verdict awaits the 4K-x420 census line.
- Cell tensor v2 (add Σv², χ², class — the .bvox v3 idea) after corpus v0.
- True >64 GIF rungs (128@40fps impossible at 20fps hardware; a 128-side
  GIF would need delay 2.5cs — violates s4_ladder_delay_cs integrality;
  export replication sidesteps this, canon unchanged).
- GeneLibrary quarantine vs delete: Daniel's call at Stage 2.
