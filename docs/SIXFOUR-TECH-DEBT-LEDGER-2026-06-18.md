# SixFour — Consolidated Tech-Debt Ledger (NN / Atlas / Gate-Coverage cleanup)

> **This is the GATE DOC for the 2026-06-18 docs-consolidation pass.** It says which
> doc-fixes are DONE in this change-set and which code-fixes those doc-fixes now UNBLOCK.
> Status authority remains `docs/STATUS.md` (gated by `scripts/verify-doc-claims.sh`); this
> ledger is the per-item detail the STATUS "Open debt" rows point to. Spec authority is the
> Haskell `spec/` modules. It consolidates the debt from three drafts —
> `SIXFOUR-NETWORKS-CANONICAL-ROSTER.md` (per-net inventory),
> `SIXFOUR-NN-DESIGN-CANON.md` (NN design canon), and
> `SIXFOUR-GATE-COVERAGE-TABLE.md` (what is verification-gated). Last reconciled 2026-06-18.
>
> **Reading rule.** A "doc-fix DONE" item is a line-level correction landed in a still-live
> doc by this pass (no code touched). A "code-fix DEFERRED/UNBLOCKED" item is the real
> engineering work the corrected docs now describe honestly; it is NOT done here. Every row
> maps to exactly one `docs/STATUS.md` "Open debt" id (dedup across the three drafts).

## A. Doc-fixes DONE in this pass (no code change; honesty corrections in live docs)

| id | doc-fix landed | file |
|----|----------------|------|
| D-glrm-claim | Struck the false "Spec.GLRM does NOT exist in the repo" claim; GLRM.hs EXISTS, only WIRING is outstanding | `docs/SIXFOUR-ALPHAZERO-COLLAPSE-DESIGN.md` ~:161 |
| D-abandon-banner | Added ABANDONED-PATH note: `look_net_trained.s4ln`/`atlas_net_trained.npz` were DELETED; references are design/regenerable, not reachable files | `docs/COLOR-ATLAS.md` (~:83,143,156,226) |
| D-oracle-note | Marked `LookNetEval` as forward-oracle-with-abandoned-weights (oracle preserved, zero callers) | `spec/src/SixFour/Spec/LookNetEval.hs` docstring |
| D-map-designonly | Tagged `BoardQ16`/`GenomePair`/`GenomeBlend`/`GenomeCarrier`/`ExportFamily` bullets DESIGN-ONLY (no device reachability) | `spec/src/SixFour/Spec/Map.hs` §★★/§4 |
| D-value-net-sot | Pinned the two-value-head distinction (linear-770 spec v1 vs 29,249-param device MLP spike) as a single source of truth in STATUS | `docs/STATUS.md` "VALUE NET" block |
| D-bit-identity | Softened "bit-identical Mac↔iPhone" to "cross-language bit-identity UNPROVEN" everywhere (C11) | `docs/STATUS.md:62-63` + new gate-coverage doc §5 |

## B. Doc-conflicts resolved (the three drafts disagreed; resolution is canon)

| id | conflict | resolution |
|----|----------|-----------|
| C-bit-identity | Roster + NN-Canon repeat "bit-identical Mac↔iPhone" as fact; Gate-Coverage says UNPROVEN | **Gate-Coverage wins.** On-device value-training run is real; cross-language bit-identity is unproven (no parity harness). STATUS line softened. |
| C-value-input | Roster: "board[128]‖genome[384]"; NN-Canon: "4096×6 board+384 genome"; Gate: "board+genome" | **Roster wins** (most precise): device spike = nonlinear MLP, genome 384→64 + board→128 context → 128→32→1, 29,249 params pinned at `AtlasTrainingSession.swift:76`. |
| C-glrm-exists | ALPHAZERO doc + COLOR-ATLAS said GLRM doesn't exist; all 3 new docs say it EXISTS unwired | **New docs win.** `Spec.GLRM.hs` exists; debt is wiring only → `glrm-wired-but-unused` (med). |
| C-gan | Roster/Gate frame GAN as "vestigial in regimen.py, strike it"; NN-Canon says "stale dead-MLX text, leave Map.hs" | **Unified:** `Spec.Loss`/`Map.hs:25` "GAN dropped" is CANON (no Map.hs edit). The contradiction lives ONLY in `trainer/regimen.py` (Tier-1, no gate). Strike is a DEFERRED code-fix, not part of this docs pass. Severity med (Gate) not high (Roster). |
| C-archive-luv | Roster: do NOT archive LOOK-VALUE-UNIFICATION (add pointer); NN-Canon: ARCHIVE it | **Keep in place + historical banner (no archive this pass).** Archiving breaks the live xref at MERGE-DECISION-ADR.md:6 and would drop load-bearing design text; instead a top-of-file banner marks it superseded by ALPHAZERO (linear-770) + the new canon doc. |
| C-archive-stateinspect | NN-Canon: archive STATE-INSPECTION as dated snapshot; Gate-Coverage cites it live for C11 | **Keep in place (no archive this pass).** Its bit-identity-unproven verdict is folded into STATUS + the gate-coverage doc (the live citation); kept on disk so the STATUS header + ALPHAZERO + 4 other referrers stay valid. |

## C. Code-fixes now UNBLOCKED (described honestly by the corrected docs; NOT done here)

Ordered by the honest dependency sequence (matches `SIXFOUR-ALPHAZERO-COLLAPSE-DESIGN.md` §8–§9).

| id | STATUS debt row | code-fix unblocked | sev | blocker? |
|----|-----------------|--------------------|-----|----------|
| glrm-wired-but-unused | new | Wire `Spec.GLRM` OLS kill-switch into `AtlasTrainer` before any value-net preference training | med | no (do first) |
| board-q16-unported | **DONE 2026-06-18** (commit 14478c1) | Ported `Spec.BoardQ16` → Zig `s4_board_mass_q16`/`s4_board_counts_to_mass_q16`; `AtlasBoard16.base` uses it; golden-gated Haskell≡Zig≡Swift (`BoardQ16GoldenTests`, `kernels.zig` unit test). Float leak at the policy/value board input CLOSED. | high | done |
| (genome-source) | empty-training-data + looknet-load-unused | Decide genome source: retrain converging full-colour Look-NN (re-export real `.s4ln`) OR commit to AlphaZero collapse path | high | **yes** |
| ab-perturb-stub | new | Replace `AtlasState.perturb()` fixed-±0.04 stub with `Spec.GenomePair.sampleOrthogonalPair`; extend DecisionLog to 770-D embeddings; wire `btUpdate` | high | no |
| no-metal-golden-gate | new | Stand up first byte-exact Zig→Metal golden: Metal port of `s4_cube_lift_level` via `floorDiv` + fixed-order reductions, gated vs `rgbt4d_golden.json` | high | **yes** (GPU precedent) |
| (gpu-value-oracle) | palette-search-design-only | Build Gumbel-search GPU value oracle on that gate (batched frontier, Q16 keys) | med | no |
| atlas-nets-unpinned | new | Add `Spec.AtlasPolicy`/`AtlasValue` with pinned `NetIOSpec` (13-D tokens+384 genome→1524 logits; board+genome→1); emit `net_shape.py`+`AtlasContract.swift`; OR retire Atlas nets to trainer-only research with no cross-tier contract claim | high | **yes** (loop) |
| atlas-value-spec-drift | new | Rewrite `AtlasTrainer` value graph from 384-genome MLP to spec-v1 linear-770 head over `atlasEmbedding`; add `-η·λ·θ` L2 decay; re-measure latency (expected cheaper) | high | no |
| gan-framing-contradiction | new | Strike vestigial GAN framing from `trainer/regimen.py:14,54` + dead `lam_adv`/`dlr`/`eps_*` knobs so code matches `Spec.Loss` | med | no |
| no-ondevice-trainer-spec | existing (re-pointed) | Spec+Swift the on-device `btUpdate` θ fold + `PersonalGenomeStore` + 10-Compare promotion gate | high | no |
| genome-blend-carrier-export-design-only | new | `GenomeBlend`/`GenomeCarrier`/`ExportFamily` device consumers (federated import, v2+) | low | no (layers last) |
| looknet-param-count-est | new | Measure Look-NN params (`count_params()`/`Spec.LookNet` law) to replace the unsourced ~115K estimate | low | no |

## D. Pinning truth table (closes the param-count confusion across all three drafts)

Only **METRIC=6**, **θ=770**, and the **device value spike=29,249** are PINNED (a literal in
source/STATUS/`net_shape.py`). `~115K` (Look-NN), `~6K` (Atlas policy), `~1K` (Atlas value-Mac)
are **design estimates** with no repo literal — do not cite as contracts. Only METRIC (in=6,out=0)
and LOOK (in=10,out=384) carry a spec-pinned `NetIOSpec`; the **entire Atlas roster is
NOT contract-protected** (dims are uncodegenned trainer literals `ATLAS_TOKEN_DIM=13`,
`N_VOCAB=1524`). The COLOR-ATLAS "≈64K total" is design arithmetic, not a measured contract.

## E. Verified-surface honesty (Gate-Coverage §5, canon)

- **Verified surface = CPU tier only.** Zig≡Swift≡Haskell is golden-pinned on the integer
  `s4_*` kernels. **No Metal/GPU output is gated against a byte-exact golden** (`field.metal`
  is float-tolerance vs a CPU reference). The GPU side of the SIMT determinism contract is
  aspirational today.
- **The learned half is spec-complete and unwired**; no trained weights exist; no on-device
  forward pass runs. On-device training runs only the MPSGraph value spike (train-only,
  never selects a palette).
- **"bit-identical Mac↔iPhone" is overstated** → treat as: on-device training real,
  cross-language bit-identity UNPROVEN.

> Note: `verify-doc-claims.sh` already asserts the header declares **28** distinct `s4_*`
> symbols (25 shipped + 3 tooling), so any new doc prose that says "24"/"21+3" is stale —
> the three drafts' export-count asides were corrected to match the gate in the new docs.