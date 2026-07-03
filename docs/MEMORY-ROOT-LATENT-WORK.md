# MEMORY ROOT + LATENT WORK: the per-capture memory ladder is an exact byte COUNT scaling 8x/rung on the index, and each combinator's latent work is the measured erased/synthesized residual, priced in bits, Landauer-scoped

> Status: DESIGN OF RECORD · 2026-07-02 · Owner: SixFour
> Companions: `docs/ENTROPY-INVARIANTS.md`, `docs/DESTRUCTIVE-PYRAMID.md`, `docs/SCALE-TRANSITION-TRAINING.md`, `docs/GENE-COMPUTE-ECONOMY.md`, `docs/DEVICE-MODEL-MAP.md`, `CLAUDE.md`.
> Spec wins on any disagreement. Anchors are `file:line`, grep-confirmed against the substrate maps this session; PROPOSED laws are named as such and are not anchors. Start any spec browse at `SixFour.Spec.Map`.

---

## 1. THESIS + VERDICT

The thesis has two halves that share one substrate. FIRST: quantize the full GIF89a memory at every scale 16/32/64/128/256 as a CONCRETE per-capture COUNT of bytes, read off pinned constants, never an entropy estimate. The raw index memory scales cleanly at exactly 8x per octant rung (`side^3 = (2^p)^3 = 8^p`, forced by the 2x2x2 lift branching), so the whole ladder is `quantum * 8^(p - 6)` and is predictable in advance; the LZW-compressed shipped byte size does NOT scale this way because `lzwEncodeFrame` (`Native/src/kernels.zig:1794`) is variable-length and content-dependent. SECOND: give each combinator a measured latent work. `I` (reversible lift) erases nothing (Bennett: a bijection is measure-preserving), so `work(I) = 0` is a byte-exact theorem; destructive `K` (pool-and-discard) erases the residual it drops; `S` (invent) must re-supply that same residual. Priced in the ONE unit that is exact per capture, the count of erased/synthesized residual bits, this re-teeths the "energy-work" analogy that `docs/ENTROPY-INVARIANTS.md` demoted to INTERPRETATION for lacking an erasure cycle.

**VERDICT: SOUND on the counting core, INTERPRETATION on the thermodynamics, after four fixes the critics forced.** What is PROVABLE and MEASURABLE: (a) the 8x/rung law on the RAW INDEX sub-component is an algebraic identity, not a fitted rate; (b) `work(I) = 0` is byte-exact from the lift bijection; (c) the per-capture erased/synthesized quantity is a deterministic byte/bit COUNT you can put in the ledger. Where the teeth are honestly INFORMATION-not-joules: the Landauer/Szilard "heat/work" naming is an intuition for WHY the I/K/S asymmetry is physical (bijection free, erase priced), NOT a joule meter; `k_B T ln2 = 2.9e-21 J/bit` is ~1e9x below real CMOS and is philosophically contested (Norton). Four corrections are load-bearing and folded below: the clean 8x is INDEX-only (palette scales 2x, header is fixed, so TOTAL bytes are nowhere near 8x at small scale); the per-capture work quantity is `codedResidualBits` (an unconditional COUNT), NOT the corpus conditional `H(detail|coarse)`; the down-then-up conservation law holds only in the REPLAY regime at or below the 64^3 capture, above which `S` invents unbacked bits with no `K`-dual; and the leaf is named `Spec.IndexMemoryLadder`, not `MemoryLadder`, because the clean scaling is on the index alone.

---

## 2. THE MEMORY LADDER

Pinned constants: `K=256`, `SIDE=64`, `FRAME_COUNT=64`, `CHANNELS=3` (`kernels.zig:65-68`); `Q16_ONE = 1<<16` (`kernels.zig:62`). The GIF89a writer `s4_gif_assemble` (`kernels.zig:1861`) emits `"GIF89a"` (`:1884`) and packed byte `0x70` = NO GCT (`:1887`), so every frame carries its own Local Colour Table of `K*CHANNELS = 768` bytes. Raw index stream = one 8-bit palette index per voxel = `side^3` bytes. The base quantum lives at the root rung `p=6` (the captured `64^3`); the whole ladder is `quantum * 8^(p-6)`.

RAW INDEX memory (1 byte/voxel), the clean ladder:

| S (rung p) | voxels S^3 | raw index | x/rung | palette 768*S | x/rung |
|---|---|---|---|---|---|
| 16 (4) | 4,096 | 4 KiB | . | 12 KiB | . |
| 32 (5) | 32,768 | 32 KiB | x8 | 24 KiB | x2 |
| **64 (6) = root** | **262,144** | **256 KiB** | x8 | **48 KiB** | x2 |
| 128 (7) | 2,097,152 | 2 MiB | x8 | 96 KiB | x2 |
| 256 (8) | 16,777,216 | 16 MiB | x8 | 192 KiB | x2 |

**The 8x is FORCED, not folklore.** `rawIndexBytes = side^3 = (2^p)^3 = 8^p`, so `succ p` multiplies by `2^3 = 8`. The generator is real: `s4_cube_expand_rung` (`kernels.zig:924`) writes a 2x2x2 lane block per input voxel, and `ScaleFiltration.branching 2 3 = 8` (`ScaleFiltration.hs:45`) with `lawOctantBranchingIs8` (`:31`). Index memory is VOLUMETRIC (x8); palette memory is LINEAR in frame count (x2, per-frame LCT with `K=256` fixed). That asymmetry is a real countable fact.

**Base quantum, two honest readings, pick one for the golden.** Pre-palette 10-bit: capture is 10-bit x420 YCbCr (`CaptureSession.swift`, A1 ledger row `DEVICE-MODEL-MAP.md:38`), so `262,144 voxels x 30 bit = 7,864,320 bit = 960 KiB` at the root. Post-quantize: `s4_quantize_frame` (`kernels.zig:343`) emits maximin-seeded (optional Lloyd) 256 centroids + u8 indices, giving `256 KiB index + 48 KiB palette = 304 KiB` at the root. The SHIPPABLE quantum is the 304 KiB post-palette COUNT; the leaf must not double-define it.

**The LZW caveat (this is why the leaf is INDEX-only).** The x8 law holds on RAW index/voxel memory. The shipped GIF byte size does NOT: `lzwEncodeFrame` (`kernels.zig:1794`) grows codes 9->12 bit and resets the dictionary on full, so a flat frame collapses far below the bound and a noisy frame approaches it. The worst-case bound `s4_gif_encode_burst_bound` (`kernels.zig:74`) at (64,256,256) is ~8.45 MB, matching ledger C8 (`DEVICE-MODEL-MAP.md:54`, `bound ~8.45 MB`). State it as `lawRawMemoryPredictable` (green, provable) versus a deliberately UN-authored `compressedSizeContentDependent` (no anchor predicts it, and none should exist).

**Tie to the DEVICE ledger.** The abstract ladder is anchored to real RSS by golden against `DEVICE-MODEL-MAP.md:34-56`: A6 `v21HistBuffer` = `64*64^2*3*256*4B = 768 MiB` (`:43`, the peak-RSS hotspot, the V2.1 pre-collapse distributional field, `3*256*4 = 3072x` the root index memory), B1 `poolV21Counts` = 12 MiB (`:44`), A5 `OKLabTile` = 4 MiB (`:42`), C7 export replicate = 4 MiB (`:53`), C8 gifAssemble = 8.45 MB (`:54`). Note C7: the shipped `256^2` is a `4x4` index replicate of the `64^2` capture (fake `64^2 x 4`), palette stays 48 KiB, so the shipped raw is ~4.05 MiB, not the cube-ladder `16 MiB`. The cube ladder (this doc) and the shipped GIF (T=64 fixed, only spatial side moves) are two distinct shapes; keep them distinct.

---

## 3. ROOT ANALYSIS

The ladder IS the descending-sublattice chain of `Spec.ScaleFiltration`. Each rung refines by sublattice index `[L_k : L_{k+1}] = 2^3 = 8` (`lawDescendingChainIndex ScaleFiltration.hs:107`), one octant descent = one step of branching 8. The "1 coarse + 7 detail" split is the short exact sequence `0 -> A_{b-1} -> Z^b -> Z -> 0` in `Spec.RootLatticeDetail`: coarse is the rank-1 DC functional `sumFunctional = sum` (`RootLatticeDetail.hs:47`), detail is its mean-free kernel `A_{b-1}`, and `numDetailBands b = b-1` (`:56`) so `b=8` gives `7 = rank A_7` via `lawOctantIsA7` (`:41`).

**Memory = quantum * 8^depth.** The base quantum is literally the root of the geometric series; `rawIndexBytes r = quantum * 8^(p-6)`. The step operator is scale-invariant, which is WHY one octant operator covers every rung: `OctreeCell.levelsBetween 64 16 == levelsBetween 256 64 == 2` (`lawLadderSelfSimilar`, cited from the octree ladder). The octree-ball metric is ultrametric and provably distinct from the archimedean L1/d6 (`lawL1NotUltrametric ScaleFiltration.hs:85`), so the ladder carries a genuine valuation, not just a size.

**The middle-64 up/down symmetry.** The `64^3` capture is the anchor. DOWN = destructive `K` pool `scalarCollapseLossy = ocCoarse . liftOct` (`OctreeCell.hs:235`), lossless iff self-similar; UP = `S` invent, unbacked above capture (`SelfSimilarReconstruct.lawBeyondCaptureInvented`). Memory grows or shrinks by `8^(delta p)` on either side of the root. The two directions are conditional-entropy duals reflected across the capture scale, but only in the replay regime (see section 4).

**Honest correction, keep it flagged.** The MEMORY.md index line "A7 = densest dim-7 packing" is WRONG: E7 is the densest lattice in dimension 7 (Conway and Sloane). Keep A_7 strictly as the STRUCTURE and GAUGE generator (8 sum-zero coordinates, the `S_8` palette-permutation gauge = the octant slots); drop or re-attribute the "densest" superlative. It is irrelevant to every law here.

---

## 4. LATENT WORK OF S/K/I

New additive leaf `Spec.CombinatorWork`, importing `PacketEconomy.Combinator(I|K|S)` (`PacketEconomy.hs:82`) and `DetailEntropy` (`DetailEntropy.hs:112`). Nothing imports it, so it re-pins no golden, the same pattern that introduced `DetailEntropy` and `RemainderTail`. **STATUS: UNBUILT.** The work laws are proposed in `docs/ENTROPY-INVARIANTS.md:130-131,149-175`; grep of `spec/src` finds no thermo/work module. This section is the design to author them.

The primitive is the per-capture COUNT of residual bits on ONE measured residual `r`, called `codedResidualBits(r) = detailEntropyBits(r)` (`DetailEntropy.hs:112`, `shannonBits:83`, non-negative `lawEntropyNonNegative:53`). It is an UNCONDITIONAL per-band coded length, kept STRICTLY distinct from the corpus conditional `H(detail|coarse)` (they differ by the submodularity gap `G >= 0`, `ENTROPY-INVARIANTS.md:149`). The three works:

- **`work(I) = 0`.** Reversible lift/unlift is a set-bijection, measure-preserving, so it erases nothing (Bennett). Byte-exact THEOREM, witness `OctreeCell.lawOctReversible:202` and whole-tree `lawCubeBijective`; kernels `s4_octant_lift`/`s4_octant_unlift` (`kernels.zig:857/887`). The packet ledger already charges `I` zero: `packets = length . filter (/= I)` (`PacketEconomy.hs:115`).
- **`work(K-destructive) = codedResidualBits(r)` ERASED (Landauer).** Only DISCARD costs. The non-destructive pool that KEEPS the held remainder costs 0: `SuccessiveRefinement.split` with `lawRefineRoundTrip` (`SuccessiveRefinement.hs:78`) proves `refine . split = id`, so `K` is free until the held `remainderRate = sum 7*|held bands|` (`:75`) is dropped. Dropping it is strictly worse than eps (`RemainderTail.lawLosslessNeedsRemainder`), which is exactly what makes the erasure real.
- **`work(S) = codedResidualBits(r)` SYNTHESIZED, opposite sign, in the replay regime only.** `S` re-supplies the residual `K` would erase: witness `DetailPredictor.predictDetail` (theta head) and the Just-detail branch of `s4_cube_expand_rung` (`kernels.zig:945`, the S-site fork). ABOVE the capture there is no ground-truth residual (`SelfSimilarReconstruct.lawBeyondCaptureInvented`); `S` there synthesizes the entropy of theta's OUTPUT distribution (unbacked new bits) with NO `K`-dual. That case is UNBACKED DEBT, explicitly not equal-magnitude.

Laws for the leaf:

- `lawIWorkIsZero` (T0, byte-exact): `work I = 0`, delegates `lawOctReversible:202`. The one law where the bijection earns its keep.
- `lawLosslessKWorkIsZero` (T0): pool-and-KEEP costs 0, delegates `lawRefineRoundTrip:78`. This is the load-bearing distinction that makes the sign meaningful: only `K`-with-dropped-remainder charges.
- `lawKDestructiveWorkIsCodedResidual` (T0 on a pinned micro-corpus): `work K = codedResidualBits(r)`, computed by counting the dropped bands, never by `H(fine) - H(coarse)` subtraction.
- `lawSWorkEqualsKWorkInReplay` (T0, keystone, RESTRICTED): for a measured residual `r` at scale `<= 64^3`, "K discards exactly the `codedResidualBits(r)` that S must re-supply byte-for-byte," provable from the round-trip `refine . split = id`, NOT from a `negate` sign convention. Above `64^3` it does not apply; emit a distinct `lawBeyondCaptureInvented`-tagged clause (S-work = generator-prior entropy, no dual).

The **CombinatorWork typeclass** is a thin refinement of the existing packet economy: `PacketEconomy.packets` (`:115`) counts THAT a combinator acts (compute packets); `CombinatorWork.work` prices HOW MANY residual bits it moves (bit work). `I=0`, `K/S = codedResidualBits`.

**Honest Landauer scope (module header requirement).** This is INFORMATION work, in bits, kT-proportional, NOT literal device joules. Landauer/Szilard justify the ASYMMETRY only (bijection free, erase priced `>= k_B T ln2`, information-to-work exchange verified to single-electron scale, PNAS 1406966111), not an energy budget: real CMOS spends ~1e9x the bound and the derivation is contested (Norton: logical irreversibility does not entail thermodynamic irreversibility). Carry NO temperature `T`, NO bath; tag every "heat/work" NAME as INTERPRETATION.

**How this re-teeths the demoted analogy.** `ENTROPY-INVARIANTS.md` demoted energy-work because it had a chain-rule invariant but no erasure cycle. CombinatorWork supplies the cycle in the one exact unit: `I` is the reversible branch (0 dissipation), destructive `K` is the erasure (the `7/8` residual block of the A_7 detail siblings, priced in `codedResidualBits`), `S` re-synthesizes it. The destructive-pyramid descent's total cost is `sum_rungs work(K)` at each rung's residual (`DESTRUCTIVE-PYRAMID.md`), and gene competition for `S`-packets (`GENE-COMPUTE-ECONOMY.md`) is competition to do the synthesis work `codedResidualBits`. The analogy stops being metaphor because the conservation is a theorem on a real down-then-up loop, restricted to where a measured residual exists.

---

## 5. THE CRITIC VERDICTS (folded)

- **8x-law caveats.** The x8 is real on the INDEX sub-component only. It BREAKS on TOTAL bytes at small scale because palette (x2) dominates: `total(32)/total(16) = (32+24)/(4+12) = 3.5x`, not 8x; add the fixed 32-byte file header (`"GIF89a"` + screen descriptor + NETSCAPE loop) and per-frame 8-byte GCE + 10-byte image descriptor and the small-scale ratio degrades further. So the leaf is `Spec.IndexMemoryLadder` and the quantum is defined index-only. The 10->8 reduction does NOT change the count (1 index byte/voxel at any depth; it is maximin+Lloyd quantization, not truncation). Pick ONE quantum (304 KiB post-palette) or the golden is ambiguous.
- **Landauer teeth, honest scope.** Correctly disclaimed: no `T`, no joules, ~1e9x gap conceded, Norton cited. The teeth are exactly as strong as bit-accounting and no stronger. Renaming a byte ledger "heat" adds no physical teeth; the GPU erases nothing at kT. Keep the bit COUNT honest and the "work/heat" name tagged INTERPRETATION.
- **Invented-above-64 work is UNDEFINED.** Above the captured scale there is no ground-truth residual, so `work(K)` does not exist there and `work(S)` is the entropy of theta's output distribution, not a measured conditional. The keystone's "adjoints reflected across s0" is vacuous exactly where `S` invents; scope the equal-magnitude duality to `<= 64^3` and mark the invented case UNBACKED DEBT.
- **Circularity/hygiene.** Do NOT define `work` by `H(fine) - H(coarse)` subtraction (that reads `a == a`); compute the count independently by counting dropped bands. Do NOT name the per-capture count `H(detail|coarse)` (a corpus conditional needing a distribution over (detail,coarse) pairs; one capture is one sample). Keep `codedResidualBits` (per-capture, unconditional, byte-exact) and `H(detail|coarse)` + the gap `G` (corpus-level, bias-corrected, Miller-Madow/NSB) STRICTLY separated; `G > 0` is never a per-capture boolean.
- **E7 not A7.** Keep A_7 as the structural/gauge generator, drop "densest."

---

## 6. NEW LAWS + BUILD PLAN

Two new leaves, dependency-ordered. All Tier-0 laws are pure integer/Shannon arithmetic on pinned constants, constructible via `runghc -isrc` today; wire each into `spec/gate.sh` as a cabal test once green. UNBUILT flags are explicit.

`Spec.IndexMemoryLadder` (no deps, pure arithmetic):

| Law (PROPOSED) | Tier | Algebraic witness | Constructible today | Flag |
|---|---|---|---|---|
| `lawMemoryScalesAsOctantCube` | T0 | `8^(p+1) = 8 * 8^p`; branching `lawOctantBranchingIs8 ScaleFiltration.hs:31` | YES, Integer eval | UNBUILT |
| `lawIndexIsQuantumTimesCube` | T0 | `rawIndexBytes r = quantum * 8^(p-6)`, geometric series root | YES | UNBUILT |
| `lawPaletteScalesLinear` | T0 | `768 * 2^(p+1) = 2 * 768 * 2^p`, per-frame LCT `kernels.zig:1887` | YES | UNBUILT |
| `lawRawMemoryPredictable` | T0 | index ladder is content-independent; contrast the un-authored `compressedSizeContentDependent` | YES | UNBUILT |
| ladder == DEVICE ledger golden | T1 | counts match A6/B1/C7/C8 `DEVICE-MODEL-MAP.md:43,44,53,54` | needs a golden fixture | UNBUILT |

`Spec.CombinatorWork` (imports `PacketEconomy`, `DetailEntropy`, `OctreeCell`, `SuccessiveRefinement`):

| Law (PROPOSED) | Tier | Algebraic witness | Constructible today | Flag |
|---|---|---|---|---|
| `lawIWorkIsZero` | T0 | lift bijection `lawOctReversible OctreeCell.hs:202` (measure-preserving) | YES, pure | UNBUILT |
| `lawLosslessKWorkIsZero` | T0 | `refine . split = id`, `lawRefineRoundTrip SuccessiveRefinement.hs:78` | YES, pure | UNBUILT |
| `lawKDestructiveWorkIsCodedResidual` | T0 | dropped-band count = `detailEntropyBits:112`; computed independently | YES on a pinned micro-corpus | UNBUILT |
| `lawSWorkEqualsKWorkInReplay` | T0 keystone | round-trip on measured `r` at `<= 64^3`; NOT `negate` | YES once the above lands | UNBUILT |
| S-work above capture | INTERP | `lawBeyondCaptureInvented`; generator-prior entropy, no K-dual | YES as bit accounting | UNBUILT, tagged DEBT |
| `lawWorkNameIsInterpretation` | INTERP | no `T`, no bath; Norton caveat inline | YES as label | UNBUILT |
| corpus `G = codedResidualBits - H(detail|coarse) >= 0` | T2 | submodularity (Miller); bias-corrected over a corpus | NO, needs corpus + estimator | UNBUILT |

Dependency order: (1) `IndexMemoryLadder` four arithmetic laws, add the x8 count to `gate.sh`; (2) the DEVICE-ledger golden; (3) `lawIWorkIsZero` + `lawLosslessKWorkIsZero` (pure, land first); (4) `lawKDestructiveWorkIsCodedResidual` on a pinned 2-witness micro-corpus (mirror `EncoderGrounding` floors `[242,39,231]`/`[171,171,170]`), computed independently, never by subtraction; (5) `lawSWorkEqualsKWorkInReplay` keystone; (6) the INTERP name layer and the DEBT clause; (7) corpus `G` gate left explicitly UNBUILT.

---

## 7. OPEN DECISIONS FOR THE OWNER

1. **Which quantum does the golden pin, 304 KiB post-palette or 960 KiB pre-palette 10-bit?** RECOMMENDED DEFAULT: 304 KiB post-palette (256 KiB index + 48 KiB palette). It is the shippable byte count and it keeps the index-only x8 clean; carry the 960 KiB pre-palette figure only as a documented derivation, never as the leaf constant.
2. **Name the leaf `Spec.IndexMemoryLadder` or `Spec.MemoryLadder`?** RECOMMENDED DEFAULT: `IndexMemoryLadder`. The clean x8 is on the index alone; naming it `MemoryLadder` over-claims because total bytes are 3.5x, not 8x, at 32/16.
3. **Ship the arithmetic ladder laws Tier-0-only first, or wait for the DEVICE-ledger golden?** RECOMMENDED DEFAULT: ship the four arithmetic laws now (pure, gate-ready), land the ledger golden as a fast follow, and keep `compressedSizeContentDependent` explicitly un-authored so no one reads a raw count as a compressed prediction.
4. **Keep the CombinatorWork "heat/work" names, or cut to a pure bit ledger?** RECOMMENDED DEFAULT: keep them, tagged INTERPRETATION with the "no T" caveat inline. The bit accounting (`work I = 0`, `K/S = codedResidualBits`) is a genuine and clarifying decomposition and `lawIWorkIsZero` is a real byte-exact theorem; only the joule/energy-budget framing is cut.
5. **Scope the conservation keystone to `<= 64^3`, or attempt an above-capture version?** RECOMMENDED DEFAULT: scope it to the replay regime `<= 64^3` where a measured residual exists, and mark above-capture `S`-work UNBACKED DEBT (generator-prior entropy, no K-dual). Never list S-work = K-work as equal-magnitude above the capture.
