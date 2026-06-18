# SixFour — Gate-Coverage Table (canonical)

> **Scope.** This is the canonical, file-cited answer to one question: *what is
> verification-gated in SixFour TODAY, and what is not.* It is subordinate to
> `docs/STATUS.md` (the single status ledger) and refines its verification claims.
> If a verification claim here disagrees with STATUS.md, STATUS.md wins on
> *project state* and this doc wins on *which gate covers which kernel*.
> Companion: `docs/SIXFOUR-BACKEND-TENSOR-STACK-MAP.md` (§5 SIMT bit-agreement,
> §7 prioritized build sequence). Last written 2026-06-17.

## 0. The three tiers and the one unifying mechanism

SixFour has three tiers (per `CLAUDE.md`): **Tier 0** = Haskell spec (`spec/`,
source of truth, **834 tests green**); **Tier 1** = Mac trainer (`trainer/`,
Python/MLX, NOT shipped); **Tier 2** = iOS app (`SixFour/` + `Native/`,
hand-written Swift/Metal/Zig, zero third-party deps).

There is **no shared IR** between tiers. The ONLY mechanism that unifies them is
**golden vectors**: `spec/app/Fixtures.hs` emits `*_golden.json` from the same
spec modules that drive `Generated/*.swift`; Zig `*_fixture_test.zig` load that
JSON and assert byte-equality; Swift tests assert against the same data. A claim
of "Zig ≡ Swift ≡ Haskell" is only true where a golden gate enforces it.

The gate sequence (`scripts/gate-order.txt`) is
`codegen → doc → verify → native → lint → gen → build`. The load-bearing facts
in STATUS.md are asserted by `scripts/verify-doc-claims.sh` (grep/test/find only;
no shared IR). `verify` = `cabal test`; `native` = `zig build test`.

## 1. GOLDEN-GATED TODAY (Q16 integer, byte-for-byte, CPU tier: Zig ≡ Swift ≡ Haskell)

These kernels are exact (no tolerance). Proven on real hardware for the Zig
fixtures; Swift tests assert against the same JSON. This is the verified surface.

| kernel(s) | golden | Zig fixture | Swift test |
|---|---|---|---|
| `s4_global_collapse` (maximin, Gonzalez 1985 + Lloyd) | `collapse_golden.json` (`Spec.Collapse`) | `collapse_fixture_test.zig` | `CollapseGoldenTests` / `ZigCollapseGoldenTests` |
| `s4_haar_analyze`/`reconstruct`/`level_nodes` | `haar_golden.json` (`Spec.PairTreeFixed`) | yes | — |
| `s4_linear_to_oklab_q16`, `s4_palette_oklab_to_srgb8` | `color_golden.json` (`Spec.ColorFixed`) | yes | — |
| `s4_rgbt_lift`/`unlift_quad`, `s4_cube_lift`/`unlift_level` | `rgbt4d_golden.json` (`Spec.RGBTLift`/`CubeLadder`) | `rgbt4d_fixture_test.zig` (now LIT) | `RGBT4DGoldenTests` |
| `s4_quantize_frame`, `s4_dither_frame`, `s4_significance_fill` | per-stage goldens | `fixture_test.zig` | partial (see §4 holes) |
| `s4_gif_assemble`, `s4_gif_encode_burst` (+bound/scratch) | `golden.gif` from composed fold | `gif_fixture_test.zig` | — |
| LUT grading: `s4_zone_profile_q16`, `s4_look_transfer_q16`, `s4_build_cube_q16` | `lut_golden.json` (`Spec.{ZoneProfile,LookTransfer,CubeLut}`) | `lut_fixture_test.zig` | yes |
| `s4_board_mass_q16`, `s4_board_counts_to_mass_q16` (Atlas board mass) | inline golden (`Spec.BoardQ16`, cabal-confirmed) | `kernels.zig` unit test | `BoardQ16GoldenTests` |
| `s4_leaf_override` (σ-pair taste tint, n=0) | inline golden (`Spec.LeafOverride` laws) | `kernels.zig` unit test | `LeafOverrideGoldenTests` |

Notes:
- **`PersonalTaste` (on-device θ taste vector, n=0 loop) is golden-gated Swift ≡ Haskell** —
  `btUpdate` mirrors `Spec.PreferenceUpdate` (cabal-captured goldens in `PersonalTasteTests`:
  θ=0,w=[1,0…]→0.025→0.0496862…). The embedding + leaf-tint are float, single-impl (per-device).
  Wired live into `AtlasState.choose` (freeze embeddings → btUpdate → persist → tint → log
  `category=atlas.taste`), surfaced in `AtlasGalleryView`.
- **`Spec.DecisionLog` CMPE chunk (DECN v2 = embeddings) is property-gated** (`Properties.DecisionLog`,
  10 tests incl. round-trip + CMPE round-trip + v1 backward-compat). Device twin = optional embedding
  fields on the Codable `AtlasDecisionRecord` (`DecisionLogV2Tests`); the full Swift SF64 binary codec
  is still spec-only (JSON on device today).
- **`ThetaToDelta` (θ→δ n=0 taste map) is golden-gated Swift ≡ Haskell** (no Zig kernel — θ
  is per-device float, so float-tier, not cross-device-exact; the integer δ it emits then feeds
  the exact Zig `s4_leaf_override`). `ThetaToDeltaGoldenTests` pins the cabal-captured goldens
  incl. a `.5` tie that catches round-half-to-even vs away-from-zero.
- **`GLRM` (preference kill-switch) is golden-gated Swift ≡ Haskell** (no Zig kernel —
  it is a Mac/device-CPU preflight, not a render kernel). `GLRM.swift` mirrors
  `Spec.GLRM` with matched summation order, so the `Double` OLS is bit-identical;
  `GLRMGoldenTests` pins the cabal-captured coefficients + R². Wired into
  `AtlasTrainingSession` (blocks real-data training on no-signal picks).
- **Maximin IS the collapse canon.** The historical "maximin ≠ Wu bug" is
  disproven; `s4_quantize_frame` matches `Spec.QuantFixed`/`Spec.Collapse`
  byte-for-byte. Do not re-flag.
- The deterministic **look-grading** subsystem (zone-profile → look-transfer →
  `.cube`) is a shipped, three-language, user-reachable *heuristic* (NOT neural)
  pillar. It reaches Review's Export-LUT button
  (`UI/Surface/ReviewPhaseField.swift`). See STATUS.md "Swipe-to-LOOK" entry.

## 2. FLOAT-TOLERANCE-GATED TODAY (ordinal-only, NOT byte-exact)

| artifact | what it gates | mechanism | exactness |
|---|---|---|---|
| `SixFour/Metal/field.metal` | GPU capture-field shader | compared against a Haskell/Swift **CPU** reference | **float tolerance only** |
| `NearestCentroidTests.swift` | SIMD8 nearest-centroid GPU↔CPU | within tolerance | float tolerance only |

`FieldTuning.metal.h` (a tuning-constant header from `Codegen.Swift`) is the only
Metal artifact codegen emits. **No fixture asserts any Metal output against a Zig
byte-exact golden.**

## 3. NOT GATED — the open HOLES

Each hole is also a STATUS.md "Open debt" row and/or a
`SIXFOUR-BACKEND-TENSOR-STACK-MAP.md §7` build step. Severity in brackets.

1. **[blocker] No GPU byte-exact golden gate.** Every proven byte-exact gate is
   CPU-tier (Zig/Swift/Haskell). `field.metal` gates within float tolerance vs a
   CPU reference, not a Zig golden. The integer cube-lift kernel exists in Zig
   (`Native/src/kernels.zig:684` `s4_cube_lift_level`, inverse `:712`) but has
   **no Metal port**. *Fix (§7 step 5):* stand up the first Zig→Metal golden gate
   by porting `s4_cube_lift_level` to Metal using `floorDiv` + fixed-order
   reductions (hazards in `BACKEND-TENSOR-STACK-MAP §5`), gated against
   `rgbt4d_golden.json`. This becomes the precedent every later GPU kernel follows.

2. **[blocker] Float-determinism hole in the policy-net input.**
   `Spec.AtlasBoard.histogram :: [OKLab] -> V.Vector Double`
   (`spec/src/SixFour/Spec/AtlasBoard.hs:170`) accumulates board mass in
   **Double**, in input order — permutation-dependent, so a 1-ULP nudge can flip
   a bin boundary. The integer replacement **`Spec.BoardQ16`**
   (`countsQ16`/`massQ16`/`boardMassQ16`, law `lawCountsOrderIndependent`,
   `spec/src/SixFour/Spec/BoardQ16.hs`) is **spec-only**: grep finds **no
   `s4_board_q16` / `countsQ16` port in `Native/` or `SixFour/`**.
   *Nuance:* the Swift bin-index arithmetic is already Q16-integer
   (`SixFour/Atlas/AtlasBoard.swift` `AtlasBinIdx.bin(ofQ16:)`); the un-ported
   piece is the **mass accumulation** (counts → Q16 normalised mass) that the
   policy/value board channels read. *Fix (§7 step 2):* port `BoardQ16` to
   Zig + Swift, replace the float mass path, gate with `lawCountsOrderIndependent`.
   Determinism prerequisite for any on-device policy/value selection.

3. **[blocker] No trained Look-NN weights; supervised path ABANDONED (2026-06-17).**
   The grayscale-L supervised MLX run **did not converge to a usable look**; the
   trained outputs (`look_net_trained.s4ln`, `atlas_net_trained.npz`,
   `synth_looknet_grayscale.gif`) were **DELETED**. The only `.s4ln` on disk is the
   **regenerable GOLDEN fixture** `trainer/out/look_net.s4ln` (not a trained
   artifact). `s4_load_look_net` loader CODE is kept and fixture-verified against
   that golden; `SixFourNative.swift:82` `loadLookNet` has **zero production
   callers**. There is therefore **no trained-weight gate** and the
   `CLAUDE.md` "turn the trained base net into a palette source" spine has nothing
   to load. *Fix (§7 step 3):* decide the genome source — EITHER retrain a
   converging full-colour Look-NN and re-export a real `.s4ln`, OR commit to the
   AlphaZero collapse path as the genome generator and retire the abandoned
   trainer. Honest sequencing required before any on-device learned-genome work.

4. **[high] Atlas nets have NO spec-pinned `NetIOSpec`.** Only `METRIC` (in=6,
   out=0) and `LOOK` (in=10, out=384) are pinned via `Net.hs → net_shape.py →
   Generated/NetContract.swift`. The entire Atlas roster (policy + value) lives
   only in un-codegenned trainer Python (`atlas_net_mlx.py`:
   `ATLAS_TOKEN_DIM=13`, `N_VOCAB=1524`) and Swift literals; there is no
   `Codegen.AtlasPolicy`/`AtlasValue`. Atlas is **not contract-protected**.
   *Fix:* write `Spec.AtlasPolicy` (13-D tokens + 384 genome → 1524 logits) and
   `Spec.AtlasValue` (board + genome → 1) with pinned `NetIOSpec`, emit
   `atlas_net_mlx.py` + `AtlasContract.swift`, gate byte-exact (offline).
   Prerequisite for closing the AlphaZero loop (§7 step 7).

5. **[high] A/B device path uses a `perturb()` stub, not the spec'd proposer.**
   `SixFour/Atlas/AtlasState.swift:96` sets `candidateB = Self.perturb(candidateA)`
   — a fixed ±0.04 OKLab (Q16 2621) chroma kick on the `a` axis with alternating
   sign (`:172-178`), a placeholder. The real proposer
   `Spec.GenomePair.sampleOrthogonalPair` (`:270`, Haar-space disjoint-band,
   exact-0-inner-product) is **spec-only, unwired**. *Fix (§7 step 4):* replace
   `perturb()` with `sampleOrthogonalPair`, extend the DECN decision-log wire
   format to store full 770-D `(w,l)` embeddings (today hash-only), gate with
   GenomePair laws.

6. **[high] On-device θ training (Bradley-Terry) is spec-only.**
   `Spec.PreferenceUpdate.btUpdate` (770-D θ, BT-logloss + L2 SGD) has **zero
   Swift consumer**; `AtlasState.swift` logs Compares as hash, not full
   embedding; `AppSettings.swift` has no `PersonalGenomeStore`. The MPSGraph
   **value** spike (`AtlasTrainer.swift`, 29,249 params, 12.4 ms/step, train-only)
   is the only on-device training that runs, and it never selects a palette.
   *Fix (§7 step 4):* extend DECN to carry embeddings, implement the `btUpdate`
   fold in Swift, wire the 10-Compare promotion gate, gate with a Preference
   golden.

7. **[high] No Gumbel-search GPU value oracle.** `Spec.GumbelSearch` is
   CPU/Sequential-Halving only (`q16Key` `:50`, `lawArgmaxKeyDependsOnlyOnKeys`
   `:31`); there is no Metal kernel for batched frontier evaluation or Q16-key
   quantization. *Fix (§7 step 6):* after the first Zig→Metal golden gate (hole 1),
   build the batched-frontier value oracle emitting Q16 keys via fixed-order
   reduction; gate `lawArgmaxKeyDependsOnlyOnKeys` on real hardware.

8. **[medium] GAN framing is internally contested.** `Spec.Map` lists
   `Spec.Loss` as "OT/reconstruction; **GAN dropped**" (`Map.hs:25`), but the
   trainer code (`regimen.py`, `look_net_loss_mlx.py`, and the
   `train_look_net_mlx.py` docstring) describes an ε-annealed GAN discriminator.
   Since the trainer is abandoned, this is **design clarity, not a build blocker**.
   *Fix:* reconcile to ONE canonical loss module when the genome source is decided.

9. **[high] No full-colour training data.** `trainer/data/captured_frames` and
   `trainer/data/reference_gifs` are empty/absent (gitignored; gated by
   `verify-doc-claims.sh:72-75`). The trainer is synthetic-only
   (`synth_classes.py`); "beats baseline 5/6 / ~3×" is **unpinned synthetic
   runtime output, not a contract**. Deferred until the genome source is decided.

10. **[medium] Param counts mostly unpinned.** Only `METRIC=6`, `θ=770`, and the
    device value spike `=29,249` are grounded in source/STATUS. `~115K`
    (Look-NN), `~6K` (Atlas policy), `~1K` (Atlas value-Mac) are **estimates** —
    no param-count literal exists in `atlas_net_mlx.py`/`look_net_mlx.py`/
    `net_shape.py`. Low priority (doc only).

11. **[low] Federation is spec-only.** `Spec.GenomeBlend`/`GenomeCarrier` and
    three-rung `ExportFamily` have no on-device consumer; `fed_sim.py` is pure
    simulation. Layers on last (§7 step 8).

## 4. CPU-tier golden gaps (Swift side of an already-Zig-gated kernel)

These are NOT GPU/Metal holes; they are missing **Swift** golden assertions for
kernels already Zig-gated against Haskell (tracked in STATUS.md "Open debt"):

- `s4_dither_frame` lacks a Swift golden (`missing-dither-golden`).
- `s4_palette_oklab_to_srgb8` lacks a Swift golden (`missing-palette-srgb8-golden`).
- `s4_srgb8_to_oklab_q16` lacks a dedicated golden (`missing-srgb8-oklab-golden`).
- No direct `s4_gif_assemble ≡ GIFEncoder.swift` LZW parity gate
  (`gifencoder-lzw-parity`).

## 5. Honest summary

- **Verified surface = CPU tier only.** Zig ≡ Swift ≡ Haskell is rigorously
  golden-pinned on ~16 integer `s4_*` kernels. **Metal/GPU output is unverified
  against any byte-exact golden** — the GPU side of the SIMT determinism contract
  is aspirational today.
- **The learned half is spec-complete and unwired.** Look-NN forward is proven in
  Haskell only; no trained weights exist; no on-device forward pass runs.
- **On-device training runs, but for telemetry.** The MPSGraph value net trains
  (train-only) and never selects a palette; the look-NN genome that would colour
  output does not run on device.
- **"bit-identical Mac ↔ iPhone" is overstated.** The on-device value-training run
  is real, but no test asserts the headline numbers and no cross-language parity
  harness exists; the Swift spike and Mac MLX architectures differ. Treat as:
  on-device training real; **cross-language bit-identity unproven**
  (`SIXFOUR-STATE-INSPECTION-2026-06-17.md §2 C11`).

Build the missing gates in the order of `SIXFOUR-BACKEND-TENSOR-STACK-MAP.md §7`
(steps 1–3 first: GLRM wire, BoardQ16 port, genome-source decision).
