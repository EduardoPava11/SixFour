# SIXFOUR — Cut → Export Contract

**Status: GREENLIGHT ARTIFACT — design + feasibility verdict only. This workflow implemented NOTHING.**
Date: 2026-06-15 · Subject: threading the 2⁸ cut depth into GIF export by extending the byte-exact GIFB genome contract.

---

## Verdict

**Feasibility: IN-CONTRACT (math) — but the published plan needs rework before it is a safe greenlight.**

| Axis | Verdict |
|---|---|
| Cut **math** (sub-256 evaluation of collapse + genome) | **SOUND.** The substrate is already a depth-parameterized recursive tree in every owner; nothing in the transform math hard-codes 256. |
| Golden-preservation strategy (append-only) | **SOUND**, *conditional* on Codegen.GenomeFixed re-emitting the existing 256 arrays from the unchanged `gen 0x5eed1234` 256-prefix in unchanged order. |
| The published **Zig plan + cross-owner byte-exact risk model** | **WRONG — REWORK REQUIRED.** The plan to edit `s4_gif_assemble` and pin a "k=64 GIF golden in BOTH Swift and Zig" rests on a Swift↔Zig parity that does not exist. The global-GCT GIF is produced by **Swift only**. The correct Zig scope is **ZERO changes**; the named edit would corrupt the unrelated GIFA path. |
| Net | **Reviewer verdict: `needs-rework`.** Do the cut — but as **all-Swift**, with **zero Zig edits**, and re-aim the byte-exact test effort at the two Swift 256-literals, not at a non-existent cross-owner GCT. |

The cut is worth doing. The design's *recommendation* (color-count cut, k = 2^level, b16-first) is correct. What must be corrected before code lands is the **model of where GIF bytes are produced** — and therefore the entire Zig section and the #1 byte-exact risk.

---

## The byte-exact contract today (3-owner map)

The cut rides on an existing tri-owner byte-exact stack. Verified against source (2026-06-15):

### Owner 1 — Haskell (source of truth)
- `Spec.Collapse.globalCollapseQ16 :: Int -> [[PxQ16]] -> [PxQ16]` — **already k-parametric**, golden-pinned at k=16 (`CollapseGolden`).
- Genome radices via `PaletteBranching` + `projectFixed` per radix (`Spec.{Flat,SigmaPair,Quad4}Fixed`), all integer/exact, the recursive analyzers depth-generic.
- `Codegen.GenomeFixed` emits `genomeFixedLeaves = take 256 (gen 0x5eed1234 …)` → the 256-entry golden arrays consumed by Swift.

### Owner 2 — Zig (`Native/src/kernels.zig`)
- `s4_haar_analyze` / `s4_haar_reconstruct` / `s4_haar_level_nodes` (≈:497-613): fully `n`-generic, gated only by `isPow2(n)`. `s4_haar_level_nodes` already emits exactly `2^level` nodes byte-exact — **it IS a depth operator**.
- `s4_global_collapse` (≈:459): delegates with a `k_out` parameter — accepts any k ≤ 256.
- `s4_quantize_frame` (≈:705): guards `k>0 && k<=256` — accepts any cut k.
- **`s4_gif_assemble` / `s4_gif_encode_burst` (≈:1172+): the per-frame-LCT GIF*A* encoder.** Confirmed at **`kernels.zig:1184`: `w.byte(0x70); // packed: no GCT, colour-res 7`.** This path writes **per-frame Local Color Tables, NO Global Color Table.** There is **no `0xF7` and no global-GCT writer anywhere in `Native/src`.** It is used only by `DeterministicRenderer` (the K=256 GIFA hero path), which the cut declares out of scope.

### Owner 3 — Swift (`SixFour/Encoder/`) — **sole owner of the global-GCT GIF**
- `GIFEncoder.encodeGlobal` (`GIFEncoder.swift:136`) — the **only** producer of a global-color-table GIF. Confirmed literals:
  - `:142  guard globalPalette.count == 256 else { … }` — hard 256 gate.
  - `:160  data.append(0xF7)` — hard packed LSD byte (GCT=1, colorRes=7, **GCT size field = 7 ⇒ 256 entries**).
  - `:163  data.append(contentsOf: colorTable(globalPalette))` — the 768-byte GCT.
  - `:198-200  colorTable(_:)` → `var table = [UInt8](repeating: 0, count: 256*3)` then `for i in 0..<256 { … }` — **hard 768-byte loop.**
- `LadderGIF.paletteToSRGB8` (`LadderGIF.swift:87-95`) — **pads the GCT to 256** (`out.append(Array(repeating: black, count: 256 - out.count)); return out.prefix(256)`).
- `LadderExport.makeURL` (`LadderExport.swift:54-57`) — `FarthestPointCollapse.collapse(… , k: SixFourShape.K).leaves` → `BranchedPalette.projectQ16(leaves, branching:, override:)` → `encodeGlobal`. **k is hard-pinned to `SixFourShape.K = 256`.**

**Byte-exact seam:** the GIFB global table is a **pure-Swift artifact**. Zig participates in the *collapse/Haar* math but **not** in writing the GCT GIF. This is the single fact that invalidates the published Zig/cross-owner plan.

---

## Why the cut doesn't thread today (the 256-leaf / preview-vs-export gap)

Two independent gaps, both real:

1. **Export is hard-pinned to 256 leaves at three Swift interface points** — `makeURL` feeds `SixFourShape.K`, `encodeGlobal` *requires* `== 256` and emits `0xF7`/768, and `paletteToSRGB8` pads to 256. Nothing downstream of the collapse believes in a smaller table. The cut depth the UI already computes (`cutDepth`, `cutBranching.depth`) **never reaches the encoder.**

2. **The preview is a second, unowned, divergent reduction operator.** `ReviewPhaseField.recomputeCutGlobal` (`ReviewPhaseField.swift:545+`, doc-comment at :67-86) reduces via **`SplitTree.build` median-sort + `SplitTree.collapse` painting each group with its first leaf**, on the **no-mask** `flatGlobalLeaves` (`:531`), while export honors `selectedGroups`. Its own doc-comment admits it is **not byte-identical** to ship — different operator (median-cut vs maximin), different index order, different mask, **and no Haskell owner.** The moment the cut becomes a real export lever, this is latent byte-divergence debt.

---

## Proposed extension

### Approach (CHOSEN): color-count cut, k = 2^level

A new `cutLevel ∈ 0..8` ⇒ **`kOut = 2^cutLevel`**, threaded as a count **distinct from the per-frame `SixFourShape.K`**, into the **existing** `FarthestPointCollapse.collapse(k:)` (already k-parametric, golden-proven at k=16) → `BranchedPalette.projectQ16` evaluated on the k leaves → a GIF with a **computed** (not hard-7) GCT size field and a **k×3** (not 768) GCT.

**Rationale.** The collapse is already k-parametric; the integer Haar / level-nodes kernels are already the depth operator and already byte-exact; GIF natively wants 2^k tables (octree prune-to-K, median-cut depth-k — 2^k is the canonical encoder-aligned target with a real LZW min-code-size payoff). The cut is hard-coded out at exactly three Swift interface points and nowhere in the math.

**Radix honesty (the one intrinsic constraint).**

| Radix | Admissible cut levels | Why |
|---|---|---|
| **b16** (Flat = identity) | **all 0..8** | `projectQ16(maximin k) = maximin k` for any power-of-two k ≤ 256. Zero genome involvement. |
| **b2** (σ-pair) | **1..8** | needs `evens.count = k/2` a power of two ⇒ k ∈ {2,4,…,256} = exactly 2^level for level ≥ 1. **Level 0 (k=1 ⇒ evens=0) trips `!evens.isEmpty` (fail-loud) — floor b2 at level 1.** |
| **b4** (Quad4) | **even only {0,2,4,6,8}** | the ÷4 reduce needs k a power of FOUR ⇒ k ∈ {1,4,16,64,256}. Odd levels {1,3,5,7} **silently drop a tail** (`while i+3<count`, no trap) → must be gated off at the UI. |

This is a respected intrinsic constraint, not new work. The UI gates odd levels off (or snaps to the nearest even) when b4 is selected.

**REJECTED alternative — the depth-pruned-genome / SplitTree-merge the preview uses today.** Keeps 256 entries, merges tree levels by painting each group with its first leaf. Rejected: (1) a *second, unreconciled* reduction operator (median-cut, widest-axis sort) diverging from export's maximin+genome path in both operator and index order; (2) keeps 256 GCT entries ⇒ no LZW/min-code-size benefit, not a real "fewer colors" cut; (3) no Haskell owner. **Recommendation: RETIRE it** and make the preview compute the *same* color-count collapse as export (preview ≡ export by construction).

### Drafted Haskell (additive, small)

The substrate is already depth-generic; the spec change pins the cut as a first-class operator + a sub-256 golden.

**1) `Spec.Collapse` — no new function.** `globalCollapseQ16` already takes k. Add one law:
```haskell
-- for level ∈ [0..8], maximin emits exactly 2^level when the cloud is large enough
lawCutLevelK :: Int -> [[PxQ16]] -> Bool
lawCutLevelK level pxs =
  length (globalCollapseQ16 (2 ^ clampLevel level) pxs)
    == min (2 ^ clampLevel level) (length (pooledCandidatesQ16 pxs))
```

**2) NEW module `Spec.CutDepth`** (one Map entry, genome/collapse category) — the cut→k→leaf contract + radix legality, one source of truth for Swift:
```haskell
cutK :: Int -> Int
cutK level = 2 ^ max 0 (min 8 level)

radixAdmitsCut :: PaletteBranching -> Int -> Bool   -- k = cutK level
radixAdmitsCut B16 k = isPow2 k                      -- all levels
radixAdmitsCut B2  k = isPow2 k && k >= 2            -- floor level 1
radixAdmitsCut B4  k = isPow4 k                      -- k ∈ {1,4,16,64,256}

cutLeaves :: PaletteBranching -> Int -> [OKLabI] -> [OKLabI]
cutLeaves br level = projectFixed br . take (cutK level)   -- precond: radixAdmitsCut br (cutK level)
```
Laws: `lawCutB16Identity` (b16 cut = take-k of leaves, exact) · `lawCutB2SigmaSymmetric` (b2 cut σ-symmetric for every admissible level) · `lawCutB4PowerOfFour` (b4 admissible ⇒ leaf count is a power of four) · **`lawCutFullDepthIsShipped`** (level 8 ⇒ EXACTLY today's 256-leaf `projectFixed` — the byte-exact regression pin that keeps existing goldens green).

**3) `Codegen.GenomeFixed` — APPEND-ONLY.** Keep `leaves`/`flat`/`quad4`/`sigmaPair` (all 256) **byte-identical** (same seed, same 256-prefix, **unchanged emission order**). ADD `quad4_64`, `sigmaPair_64`, `sigmaPair_32` from `take 64`/`take 32` of the **same** `gen 0x5eed1234` stream. (Note: `quad4ProjectFixed (take 64 leaves)` is a *new independent vector*, not a prefix of the 256 array — that is fine, it is purely additive and perturbs no existing byte.)

### Zig plan — **CORRECTED: ZERO Zig changes**

> The published plan to edit `s4_gif_assemble`'s packed byte and pin a "k=64 GIF golden in BOTH owners" is **withdrawn.** `s4_gif_assemble` / `s4_gif_encode_burst` write `0x70` (no GCT) + per-frame LCTs — they are the **GIFA** per-frame encoder used by `DeterministicRenderer`, which the cut declares out of scope. There is no Zig global-GCT writer to keep in lockstep, and editing the LCT-size field there would **corrupt the unrelated GIFA path.**

Confirmed: `kernels.zig:1184` = `w.byte(0x70)`; `grep` finds **zero** `0xF7`/global-GCT code in `Native/src`. The Haar / collapse / quantize kernels are already depth-generic and stay **untouched**. **Correct Zig scope = no edits.** (Quad4 has no Zig owner regardless — it is a pure-Swift port.)

### Golden plan — **CORRECTED: Swift-only k<256 pin**

INVARIANT: every existing golden (`GenomeFixedGolden` 256-leaf arrays, `CollapseGolden` k=16, `PairTreeGolden`, the `GenomeGolden` float twin, the existing 256-entry GIF goldens) stays **byte-identical**. Guaranteed by being append-only.

1. **`GenomeFixedGolden.swift`** — keep `leaves`/`flat`/`quad4`/`sigmaPair` exactly (regen from the unchanged 256-prefix). ADD `quad4_64`, `sigmaPair_64`, `sigmaPair_32` from `take 64`/`take 32` of the same stream. New `projectQ16` calls on the 64/32 leaves must `==` these.
2. **`CollapseGolden.swift`** — already proves sub-256 (k=16). Optionally add level-keyed k=2^level vectors; not required. Existing bytes untouched.
3. **NEW Swift-only k<256 GIF-bytes golden** (e.g. k=64): GCT header byte `0x70 | (log2 64 − 1) = 0x70 | 5 = 0x75`, GCT = 64×3 = 192 bytes. **This lives in the Swift encoder only** — there is no Zig GCT GIF to mirror. Verify the computed-size path yields `0xF7` for k=256 (the existing 256 GIF golden must encode byte-identically).
4. **`lawCutFullDepthIsShipped` golden** — `cutLeaves br 8 leaves == projectFixed br leaves` for all three radices. The explicit "level-8 ≡ today's ship" pin.

### Swift plan

**EXPORT (`LadderExport.swift`)**
- `makeURL` (:38): add `cutLevel: Int = 8` — **default 8 ⇒ k=256 ⇒ byte-identical to today**, so every existing caller compiles unchanged.
- :54-57: `let k = CutDepth.cutK(cutLevel)`; `.collapse(…, k: k).leaves`; `BranchedPalette.projectQ16(leaves, branching:, override:)` on the k leaves. b16/b2 are power-of-two-generic; for b4 gate via `CutDepth.radixAdmitsCut` (snap odd levels even).
- `flatGlobalLeaves` (both overloads, :84-100): add `k:` so the preview's cached leaves are the **same k** as export.

**GIF ENCODER (`GIFEncoder.swift`) — the REAL byte hazard, all Swift-internal**
- :142 — relax `guard globalPalette.count == 256` → `guard count is a power of two && count <= 256`.
- :160 — compute the packed LSD byte as `0x70 | UInt8(log2(count) − 1)` (256 → `0xF7` unchanged).
- :198-200 — `colorTable(_:)` must emit **`count × 3`** bytes, not the hard `0..<256` / 768-byte loop.
- `LadderGIF.paletteToSRGB8` (:87-95) — must emit **exactly `count`** entries, not pad-to-256. **Both this pad and the `colorTable` loop must change in lockstep**; if one pads and the other doesn't, the GIF byte stream diverges and the background-index / color-resolution semantics shift.

**PREVIEW RECONCILIATION (`ReviewPhaseField.swift`) — highest value, lowest risk, land first**
- RETIRE `recomputeCutGlobal`'s SplitTree median-cut body (:545+). Replace with: paint the preview directly from `BranchedPalette.projectQ16(FarthestPointCollapse().collapse(k: CutDepth.cutK(cutDepth)).leaves, branching:)` — the **exact bytes `makeURL` will encode**. Preview becomes export's GCT swatch by construction.
- Pass `selectedGroups` into the preview's `flatGlobalLeaves` (today preview is no-mask at :531 while export honors the mask).
- `exportRung` (:477-492): capture `cutDepth` + `selectedGroups`, pass `cutLevel:` into `makeURL`.
- Cut UI: when `cutBranching == .b4`, disable/snap odd levels (only {0,2,4,6,8}); b16/b2 allow all 9 (b2 floored at 1). Drive from `CutDepth.radixAdmitsCut`.

---

## Byte-exactness preservation

**How b16 / b4 / b2 stay green.** The whole change is **append-only on goldens** + a **defaulted `cutLevel = 8`** that reproduces today's exact 256-leaf GIF bytes (k=256, `0xF7`, 768-byte GCT). The `lawCutFullDepthIsShipped` law is the explicit guard. Existing 256 arrays, `CollapseGolden` k=16, `PairTreeGolden`, and the float twin are all untouched.

**Divergence risks (corrected ranking):**

1. **(REAL #1) Two Swift 256-literals must change in lockstep.** `LadderGIF.paletteToSRGB8` pad-to-256 (**:87-95**) **AND** `GIFEncoder.colorTable` 768-byte `0..<256` loop (**:198-200**), plus the `encodeGlobal` `== 256` guard (:142) and the `0xF7` packed byte (:160). **All Swift-internal.** This is the real highest-risk point — *not* a cross-language one. Pin with the Swift-only k=64 GIF golden.
2. **(WITHDRAWN) The published "Swift↔Zig GCT-size parity" risk is misdiagnosed** — there is no Zig GCT writer. Redirect all test effort from a non-existent cross-owner golden to risk #1.
3. **Quad4 silent power-of-four drop.** `quad4AnalyzeFixed` halts at `length cur <= 1`; `quadReduce` returns `[]` on a <4 tail (Swift mirrors `while i+3<count`). A count like 32 silently collapses toward root `(0,0,0)` with **no trap**. Contained ONLY by gating b4 to even levels; assert `radixAdmitsCut` before `projectQ16` so a bypassed UI gate still fails loud in the spec layer.
4. **b2 level-0 (k=1).** Trips `sigmaPairProjectQ16`'s `!evens.isEmpty` (fail-loud); the Haskell twin has no fallback. **Floor b2 genome cut at level ≥ 1.** (Swift's `else { return leaves }` branch is a Swift-only divergence if the precondition is ever relaxed — don't.)
5. **Maximin tie-break.** Reuse the shipped Q16 INTEGER `farthestPointSeedsQ16` (strict `<` ⇒ lowest-index ties, already golden at k=16) for the new k. Risk only if anyone reintroduces a Double maximin for the smaller k.
6. **Float-twin drift.** `GenomeGolden` (Double, tolerance-gated) and `GenomeFixedGolden` (integer, exact) must gain the sub-256 vectors from the **same seed prefix**; a different fixture would let the tolerance gate pass while masking an integer divergence.
7. **Procedural golden risk.** Append-only safety holds ONLY if `Codegen.GenomeFixed` re-emits the existing 256 arrays from the **unchanged** `gen 0x5eed1234` 256-prefix in **unchanged emission order**. Any re-threading of the generator to parameterize n could shift existing bytes.
8. **Level-8 ≡ ship.** The `cutLevel = 8` default MUST reproduce today's exact 256-leaf GIF bytes. `lawCutFullDepthIsShipped` is the guard; without it the encoder refactor could perturb the shipped GIFB.

---

## Recommendation

**DO IT — corrected scope: all-Swift color-count cut (k = 2^level), ZERO Zig edits, b4 gated to even levels, b2 floored at level 1.** The cut math is genuinely in-contract: the collapse is already k-parametric and golden-proven at k=16, and GIF natively wants 2^k tables. The work is bounded and append-only on goldens, guarded by `lawCutFullDepthIsShipped`.

**Smallest shippable first step (recommended): b16-only.** Flat = identity ⇒ `projectQ16(maximin k) = maximin k`, zero genome involvement, zero Quad4/σ-pair edge cases. This de-risks the **one real byte hazard** (the two Swift GCT-size literals) behind the simplest radix. Then extend to b2 (k = 2^level ≥ 2) and b4 (even levels) once the Swift k<256 GIF golden is green.

**Land FIRST regardless of scope: RETIRE the SplitTree preview reduction** (`recomputeCutGlobal`, `ReviewPhaseField.swift:545+`) and make the preview compute export's exact bytes. It is a second, unowned, doc-admittedly-non-byte-identical operator — latent debt the moment the cut becomes a real export lever. Reconciling onto one operator (preview = export's GCT swatch) is the highest-value, lowest-risk part of the whole change.

**DEFER:** the depth-pruned-genome / keep-256-entries variant — second reduction semantics, no GIF payoff, no Haskell owner.

**Cost.** Spec: +1 module (`Spec.CutDepth`, ~4 laws) + 1 Collapse law + an append-only `Codegen.GenomeFixed` edit + 1 Map entry. **Zig: none.** Swift: `makeURL` +1 defaulted param (all callers compile), the ~3-line collapse block in `LadderExport`, the `encodeGlobal` guard + packed byte + `colorTable` + `paletteToSRGB8` GCT-size changes (the real hazard), the preview body retirement in `ReviewPhaseField`, and a b4 odd-level UI gate. Goldens: append-only + one new Swift-only k<256 GIF golden. No build-system change, no new dependency; satisfies the zero-dep Tier-2 contract. Per-frame K (DeterministicRenderer, CaptureViewModel, PaletteCloudView) stays 256 — the cut is **global-table only**, inserted at the `encodeGlobal`/global-collapse seam where "frames may use any subset, no completeness brand" already holds. The per-frame completeness brands (`GlobalVolumeContract`, `SignificanceContract`, `StageContract == K`) are **not** touched and the sub-256 table must NOT flow back through them.

---

## Executive summary

Threading the 2⁸ cut into GIF export is **mathematically in-contract**: the collapse is already k-parametric (golden at k=16), the genome analyzers are depth-generic, and GIF natively wants 2^k color tables — so a `cutLevel → k = 2^level` color-count cut is the canonical, encoder-aligned target. b16 admits all levels, b2 levels ≥ 1, b4 even levels only (the ÷4 reduce silently drops non-power-of-four tails — UI must gate). The golden strategy is append-only and guarded by a `lawCutFullDepthIsShipped` "level-8 ≡ today's ship" pin, so existing byte-exactness cannot regress.

**The published plan needs one correction before greenlight:** its Zig section and its #1 byte-exact risk assume a Swift↔Zig parity for the global color table that **does not exist**. The GIFB global-GCT GIF is produced by **Swift alone** (`GIFEncoder.encodeGlobal`, `0xF7` at :160, 768-byte `colorTable` at :198, pad-to-256 in `paletteToSRGB8`); Zig's `s4_gif_assemble` is the per-frame-LCT GIF**A** encoder (`0x70` at `kernels.zig:1184`, no GCT) and must **not** be edited. **Correct scope = zero Zig changes**; redirect all byte-exact test effort to the **two Swift 256-literals** that must shrink to k×3 in lockstep.

**Verdict: do the cut, all-Swift, b16-first; retire the unowned SplitTree preview reduction first** (highest value, lowest risk) so preview ≡ export by construction. With the Zig misdiagnosis corrected, the change is contained, append-only, and zero-dep. **Greenlight conditional on the corrected (zero-Zig, two-Swift-literal) scope.** This document is design-only — nothing was implemented.
