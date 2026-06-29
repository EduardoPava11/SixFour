# V2 GIF89a Latent-Thinking Substrate: Three-File Synthesis

## 1. Header

These are **base-only exploration notes**, NOT wired into `cabal` / `Map` / `gate`. They connect three runghc-checkable Haskell files under `spec/exploration/`, each of which mirrors `GifSki.hs`'s `laws :: [(String,Bool)]` + `main` PASS/FAIL + `SUMMARY: n/m laws PASS (all green)` skeleton and imports only GHC-boot (`base`, `Data.List`). No em-dashes anywhere in source or prose.

| File | Module | Laws | Status |
|---|---|---|---|
| `spec/exploration/V2Gif89aAxes.hs` | `V2Gif89aAxes` | 5/5 | all green (runghc), `-Wall` clean |
| `spec/exploration/V2IndexLzw.hs` | `V2IndexLzw` | 5/5 | all green (runghc) |
| `spec/exploration/V2SkiLevels.hs` | `V2SkiLevels` | 7/7 | all green (runghc) |

The three together tell one story: **(R,G,B,x,y,t) is exactly GIF89a; per-frame palette + index map + LZW are the latent-thinking substrate; and the SKI nested stack is what "exploring by levels" means.** None of these is a Tier-0 promotion candidate yet (see Section 6); they are exploration that earns specific, narrow promotions.

---

## 2. The mapping: (R,G,B,x,y,t) == GIF89a, typed

The owner's first ask, made type-precise in `V2Gif89aAxes.hs`:

- **Palette** `palette_t : Slot -> (R,G,B)` is the colour **VALUE** head. In the real wire (`GifDecode.dfPalette`) this is the 256-entry Local Color Table written **per frame** (no Global Color Table).
- **Index map** `index_t : (x,y) -> Slot` is the discrete **CONTENT** head (`GifDecode.dfIndices`, row-major `w*h`).
- **t** indexes the **FRAME**: each frame carries its own palette/LCT, so `t` is literally the per-frame-palette axis.

The render law:

```
render(x,y,t) = palette_t (index_t (x,y))   =   palette . index   =   B palette index
```

This is `B` (the composition combinator `B f g x = f (g x)`, realized in `GifSki.hs` as `b = S # (K # S) # K`). `lawRenderIsBComposition` proves three things with teeth: (a) the typed `render (pal,idx) p == pal (idx p)` on a real frame (a definitional tautology, honestly flagged); (b) the actual `Comb` reduction `b f g x -> f (g x)`; (c) **non-commutativity** (a witness separates `f(g x)` from `g(f x)`), so "palette AFTER index" is a real ordered fact, not a coincidence of symmetry.

Two structural companions seat the mapping:

- **`lawSixAxesFactor`** (value DOF ⊥ index DOF): off-diagonal blindness (slot choice is palette-blind, a slot's colour is position-blind) is **definitional** by typed disjointness and is labelled so; the load-bearing tooth is the **slot-permutation gauge** `render (pal0∘σ⁻¹, σ∘idx0) == render (pal0, idx0)` (the same `σ_t` that `Upscale256.alignSlots` realizes), which needs `σ∘σ⁻¹ = id` and so cannot pass vacuously, plus `or [...]` teeth proving both heads actually move.
- **`lawValueArgumentAsymmetry`** (the faithful re-base of `RelationalMemory.lawPositionDistinguishesSameColour`): two `(x,y)` cells routed through the **same slot** share one RGB value yet are distinct content. Colour-only `dColour` collapses every such pair to 0 while full `d6 > 0`. This is *why* `(x,y)` is the discrete latent and palette is merely the value: position carries distinguishing information colour alone cannot.

Underpinning the colour axis, **`lawGrayIsEisensteinKernel`** re-grounds V2's substrate: under `R->1, G->w, B->w^2` with syzygy `1+w+w^2=0`, every gray `(k,k,k)` maps to `Eisen 0 0` (the chroma kernel), and one-step-off-gray witnesses (`(k,k,k±1)` -> specific nonzero Eisenstein integers) prove the kernel is **exactly** the gray/luma `(1,1,1)` axis. This is the carrier (I) axis; no role is ever seated on a raw R/G/B channel.

---

## 3. Latent thinking = palette + index + LZW

The owner's second ask: latent thinking happens in per-frame palettes, index maps, and LZW. The typing:

- **The index map is the discrete latent.** It is the `(x,y) -> Slot` content head, the thing `lawValueArgumentAsymmetry` shows carries information beyond colour. Position is the latent; palette is the readout value.
- **LZW is the compute over that latent.** `V2IndexLzw.hs` hand-writes a base-only LZW encode/decode (with the KwKwK special case) and proves it is a genuine lossless inverse.
- **The dictionary is the latent that grows with structure.** `lawDictionaryIsLatent` measures it: a flat 16-slot stream compresses to 6 codes, while a high-entropy de Bruijn 16-slot stream compresses to 16 codes (zero compression). Same raw length, opposite structure: the dictionary size *is* a structure meter.

### The LZW-sharing = S-contraction bridge: honest status

This is the single most important honesty boundary across the three files. The owner framed an LZW dictionary reference (reusing a repeated index substring) as **explicit sharing = the S/contraction structural move**. The files keep that reading at arm's length:

- **REAL (theorem, gated):** the lossless round-trip `decode . encode == id` including KwKwK (`lawLzwRoundTrips`); the **reuse COUNT** as measured data (`[0,1]` recurs 6x in `[0,1]×6`, emitted as a single back-reference, savings 6, `lawDictRefIsSharing`); and the **sharing ⇔ compression** invariant (code stream shorter than input iff `reuseCount > 0`).
- **SUGGESTIVE (not asserted as a theorem):** the reading of dictionary reuse AS the SKI `S` rule. LZW sharing is **DATA-level substring reuse**; `S f g x -> f x (g x)` is **TERM-level argument duplication**. They rhyme structurally, but **no typed homomorphism from LZW-stream to SKI-reduction is exhibited**, so the bridge is marked DECORATIVE `<>` in code and in the printed note. Only `reuseCount` and the round-trip are load-bearing.

The teeth that keep this from being a lying-green decoration:

- **`lawNaiveDecoderFails` / KwKwK boundary:** a naive look-up-only decoder is shown to succeed on non-KwKwK streams (including one that compresses 10->8) and fail on exactly the KwKwK streams. This is two-sided: if KwKwK were fake the first conjunct fails; if the naive decoder were simply broken everywhere the second conjunct fails. KwKwK ("a code used as it is born") is pinned as the *specific* hard case, not "naive fails whenever LZW compresses."
- **`lawCodesNeverExceed`:** `#codes <= #slots` (phrases partition the stream), with both the strict (flat) and tight-equality (incompressible `[0,1,2,3]`) boundaries asserted.
- **The `[3,3]` discriminating tooth** (surfaced in both `V2IndexLzw` and `V2SkiLevels`): a repeated SYMBOL with `reuseCount == 0`, because its 2-symbol phrase is built but never reused. A naive "has-duplicate" metric returns 1 here and would break the law. This proves the count measures phrase **sharing**, not symbol repetition.

---

## 4. SKI by levels

The owner's third ask: SKI stacks have nested functions; explore by LEVELS. `V2SkiLevels.hs` models a render at octree depth `d` as a **stack of `d` levels**. Each `Level` carries a role tag and a `(palette, index)` pair; its contribution is the per-level B-composition `levelFn = palette . index`. The whole stack renders by `renderStack = foldr (.) id (map levelFn levels)` (a chain of B-compositions).

- **Peel = one reduction.** `lawPeelOneLevelIsOneStep`: peeling the innermost-applied level is one step; a `d`-stack reaches normal form in exactly `d` peels (= ponder/read depth); the resolved+remaining invariant holds at every `k`; stopping one peel short gives the wrong residual (tooth).
- **I/S/K level roles** (`lawLevelRolesMatchExpandContract`, the strongest law) match the blessed `V2-SKI-EXPAND-CONTRACT.md` assignment:
  - **I** = the held/reversible rung: `heldIndex = id`, a bijection (value + length preserved). Seated on the luma/(1,1,1) carrier, per the Eisenstein kernel; never on Red.
  - **K** = pool/contract DOWN = weakening: `poolDown` keeps coarse, drops detail, non-injective, with an exhibited collision witness (`[1,2,3,4]` and `[1,9,3,8]` collapse to one output). Mirrors `scalarCollapseLossy = ocCoarse . liftOct`.
  - **S** = expand/INVENT UP = contraction: `expandUp` duplicates each coarse cell into `(coarse, inventFrom coarse)`, **coarse used twice** (the `liftKeyed`-style duplication, NOT a linear two-input `octantLift`, which would be BCI not S). The unique cardinality-increasing move; the mislabel tooth `S /= I` (invention is not reversible) actually fails if you swap roles.
- **Twiceness = 2 levels per rung.** `lawTwicenessIsTwoLevels`: one rung `== level . level`, band scales x4 (`levelsPerStep = 2`, covering 16:64 :: 64:256); a rung (4n) differs from a single level (2n) (tooth).
- **`lawBChainIsNesting`** gives the calculus content behind the fold: `B f (B g h) x` reduces to `f (g (h x))`, with a non-commutativity order tooth at `(I,K,S,I)` (the B-chain equals the correct nesting but differs from the swapped nesting). **`lawConfluence`** mirrors GifSki (two reduction orders, one normal form).

The substructural grading is the real spine: **BCI** (linear, every variable used once) = the reversible byte-exact floor (I); **BCK** (adds K = weakening, may discard) = pool-down; **full SKI** (adds S = contraction, may duplicate) = invented super-res surplus. "S is barred on the floor" is *derived* from "the floor is a bijection," not asserted. Tagging a level "K" or "S" does not make the octree a term-rewrite system; the names are kept only where a level genuinely is a bijection, a discard, or a duplication.

---

## 5. Honest verdict table

| File | Law | Verdict |
|---|---|---|
| **V2Gif89aAxes** | `lawRenderIsBComposition` | **REAL.** Part (a) definitional (flagged); teeth = real `B = S(KS)K` reduction + non-commutativity witness. |
| | `lawSixAxesFactor` | **REAL.** Off-diagonals definitional (flagged); load-bearing tooth = slot-permutation gauge (`σ∘σ⁻¹=id`) + non-triviality. |
| | `lawValueArgumentAsymmetry` | **REAL.** Faithful re-base of `lawPositionDistinguishesSameColour`; `dColour==0 && d6>0` over a proven-nonempty same-slot set + a `dColour>0` witness. |
| | `lawGrayIsEisensteinKernel` | **REAL.** Rests on verified `1+w+w²=0`; one-step-off boundary witnesses show kernel = exactly the gray axis. |
| | `lawLzwReuseIsSharing` | **REAL data / SUGGESTIVE gloss.** Round-trip + reuse count + KwKwK with naive counter-witness; combinator reading marked SUGGESTIVE. |
| **V2IndexLzw** | `lawLzwRoundTrips` | **REAL.** Losslessness over a corpus incl. 5 KwKwK streams + period-2 alternation. |
| | `lawNaiveDecoderFails` | **REAL.** Two-sided: naive == proper on non-KwKwK (incl. a compressing stream), naive != proper on KwKwK. Pins the exact failure boundary. |
| | `lawCodesNeverExceed` | **REAL.** Both strict (flat) and equality (incompressible) boundaries asserted. |
| | `lawDictRefIsSharing` | **REAL data / SUGGESTIVE gloss.** Reuse count (savings 6, `maxReuse>=2`) real; S-contraction reading explicitly DECORATIVE `<>`. |
| | `lawDictionaryIsLatent` | **REAL.** Both spectrum endpoints measured: zero compression (noisy 16->16) and real compression (flat 16->6). |
| **V2SkiLevels** | `lawNestedRenderIsBStack` | **REAL (via tooth) / fold-identity SUGGESTIVE.** Fold equality near-definitional (marked `<>`); teeth = order-reversal + `lawBChainIsNesting`. |
| | `lawPeelOneLevelIsOneStep` | **REAL.** Exact depth count + resolved/remaining invariant + wrong-residual tooth at d−1. |
| | `lawLevelRolesMatchExpandContract` | **REAL (strongest).** I=bijection, K=non-injective w/ exhibited collision, S=unique cardinality-increasing move, mislabel tooth S≠I. |
| | `lawTwicenessIsTwoLevels` | **REAL.** Concrete ×4 arithmetic + `rung ≠ single level` tooth. |
| | `lawBChainIsNesting` | **REAL.** B-chain reduction with non-commutativity order tooth. |
| | `lawConfluence` | **REAL.** Two reducers, one NF; mirrors GifSki. |
| | `lawLzwReuseIsSharingCount` | **REAL count / SUGGESTIVE combinator.** Round-trip + live KwKwK edge + sharing⇔compression + `[3,3]` tooth + monotone growth. |

**VACUOUS-IF-ANY:** none remain vacuous. Two residual near-definitional tautologies are honestly flagged in-code, not claimed as hard theorems: `lawRenderIsBComposition` part (a) (`render` is *defined* as `pal . idx`) and `lawSixAxesFactor`'s two off-diagonal equalities (typed disjointness). In both cases the non-vacuity is carried by other conjuncts. The only genuinely suggestive structural claim (LZW reuse ≡ SKI `S`) is deliberately **not** asserted as a law in any file; it is marked a suggestion in three places per file, with only the measurable `reuseCount` gated.

---

## 6. Build plan: promote vs stay exploration

**Promotion candidates (narrow, only the hard floor):**

1. **LZW lossless round-trip (`decode . encode == id`, KwKwK included).** This is the strongest Tier-0 candidate. It is a real, mechanism-bearing theorem that the *generated* wire already depends on (`GifDecode.lzwDecode` / `GifWire.lzwEncode`). Path to promotion: re-state the round-trip not over the toy alphabet but as a property the generated codec must satisfy, with the KwKwK and clear/EOI edges as named goldens. NOTE the growth-trigger asymmetry between the real impls (decoder grows on `next' == (1<<size)`, encoder on `nextCode > (1<<codeSize)`): a promoted law must target the GIF-byte-matching pair, not the toy's single-rule pair. This is the one place where the exploration's invariant is load-bearing for shipped bytes.

2. **`render = palette . index = B` (value/content factorization).** A candidate, but lighter. The pointwise `render = pal . idx` is definitional; what is worth promoting is the **slot-permutation gauge** (`lawSixAxesFactor`'s real tooth), because that is exactly the `Upscale256.alignSlots` invariant and a gauge violation would be a real cross-frame bug. Promote the gauge law, not the tautology.

**Stay exploration (do NOT promote):**

- All SKI/combinator content (`V2SkiLevels`, the `Comb` reducer, peel/twiceness, role tags). These are genuine and well-toothed *as readings*, but they are bookkeeping over the octree's substructural grading, not term-rewrite mechanism in the shipped pipeline. Promoting them would re-introduce forced jargon.
- `lawGrayIsEisensteinKernel` is already a theorem living in `V2RgbEisenstein.hs`; the axes file re-states it. No new promotion needed; keep the dependency one-directional.
- Every LZW-sharing = S-contraction claim. Suggestive by construction; nothing to gate.

**Next file / law to write:**

- **`V2AlignSlotsGauge.hs`** (or fold into the axes file): lift `lawSixAxesFactor`'s slot-permutation gauge to a standalone law that mirrors `Upscale256.alignSlots`'s actual matching rule (slot `j` of `P_t` to lowest `j'` of `P_{t+1}` sharing the same global-slot image, unmatched -> `nearestQ16`). This is the honest bridge from the exploration gauge to a shippable invariant, and it is the one place where the value/content split touches real cross-frame code.
- After that, a single **promotion-staging note** that takes ONLY the LZW round-trip toward a generated-code golden, with the encoder/decoder width-growth asymmetry made explicit.

---

## 7. Open questions for the owner

1. **Carrier axis under V2 re-base.** `phi6` pairs `L<->t` and pins `{L,t}` as the universal/carrier set, but V2 says luma lives on the `(1,1,1)` balance axis (the Eisenstein kernel), NOT a raw R/G/B channel. Should the P6 re-base store **raw (R,G,B)** or **(luma, chroma1, chroma2)** so `isUniversal` keeps pointing at the genuine DC carrier? The axes file currently stores raw RGB and computes chroma via `chroma (r,g,b) = Eisen (r-b) (g-b)`; confirm this is the intended basis.

2. **`phi6` survival as automorphism vs label-only.** Under V2 Eisenstein the square `Z[i]` symmetry (D4, order 8) becomes hexagonal A2 (D6, order 12), not isometric. Confirm `phi6` survives **only as a bookkeeping set-involution**, NOT as a render automorphism, and that the per-axis colour<->position pairing (`a<->x, b<->y, L<->t`) is honest on the Lab/chroma basis but **decorative** on raw R,G,B.

3. **Canonical K.** Is `scalarCollapseLossy` "THE" K (true weakening, `K x y = x`) and `octantDistill` "K-with-a-receipt" (affine made reversible by a `[[Detail]]` side channel)? The level file uses the weakening reading; confirm before any promotion mentions K.

4. **Which S.** Three candidates exist (`Haar sLift` [BCI], `unliftOct` [1->8 linear], `liftKeyed` + Invented arm [contraction]). The files commit to **S = `liftKeyed`/`expandUp` contraction (coarse used twice)**, explicitly NOT `octantLift`. Confirm this is the blessed S, and whether the `S_dup` vs `S_inv` split (Open Q2/Q3 in `V2-SKI-EXPAND-CONTRACT.md`) needs surfacing in a law.

5. **LZW-as-S, named law or permanently suggestive?** All three files keep "dictionary reuse = S-contraction" as DECORATIVE, gating only `reuseCount` and the round-trip. Does the owner want this bridge **ever** promoted to a named law (which would require exhibiting a typed homomorphism LZW-stream -> SKI-reduction, currently absent), or is it permanently a suggestive data-vs-term rhyme?

6. **LZW promotion target.** For the one real promotion (round-trip), should the Tier-0 law target the **toy self-consistent codec** (internal inverse-ness only) or be rewritten against the **generated `GifWire`/`GifDecode`** with GIF-byte-matching width growth and the clear/EOI/KwKwK edges as goldens? The latter is more valuable but couples the exploration to generated code.