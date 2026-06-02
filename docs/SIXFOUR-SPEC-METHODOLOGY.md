# SixFour — Haskell-as-Spec Methodology (how deep to go)

**Status:** Methodology guide (researched). Picks the right rigor *per design*, instead of defaulting to ADTs+GHCi or over-investing.
**Date:** 2026-06-01.

---

## 0. The decision rule (read first)

> **Escalate rigor only when a violated invariant is "pager-on-fire": data loss, wrong output that ships, cross-language drift, or a correctness bug that's expensive to find. "We currently do it this way" is NOT a reason to add type-level machinery** — it makes the code harder to change for no operational benefit.

SixFour is **Mac-side ML tooling** (the spec is the source of truth that emits Swift/Python/Zig contracts + golden vectors; it is not shipped, not safety-critical, not cryptographic). So the honest landing is: **Layers 0–2 + golden vectors cover ~95% of our failure modes at ~25% spec overhead.** Heavy layers (dependent types, LiquidHaskell/SMT, Agda proofs) are *ceremony* here — skip them until a real pain point earns them.

**Dependency note:** the spec *library* stays GHC-boot-only (base/vector/containers/text/transformers). Everything recommended below lives in the **test-suite / dev tooling** (QuickCheck, quickcheck-state-machine, QuickSpec, refined) — acceptable because the spec is tooling, never the shipped path.

---

## 1. The depth ladder (what we have / adopt / skip)

| Rung | Technique | Buys | Cost | SixFour |
|---|---|---|---|---|
| **0** | ADTs + smart constructors + **QuickCheck** laws | property-checked pure logic + construction-time validation | ~10% | **HAVE — baseline** |
| **1** | `refined`/`validity` predicates + **quickcheck-classes** (auto law-check Monoid/Functor/…) | runtime invariant validation; free typeclass-law checks | ~15% | **ADOPT (selectively)** |
| **2a** | **quickcheck-state-machine** / Hedgehog model-based testing | specifies *stateful* behavior (pre/post-conditions, transitions) | ~20% | **ADOPT — for the search** |
| **2b** | **Denotational design** (Conal Elliott; type-class morphisms) + metamorphic relations | semantics-first laws (e.g. σ-equivariance as a meaning-preserving map) | ~30% design tax | **ADOPT — for the NN** |
| **3a** | **Golden-vector parity** (tasty-golden style) | byte-identical Swift/Python/Zig conformance; catches Codegen drift | ~5% | **HAVE — critical, expand** |
| **3c** | **QuickSpec** (auto-*discovers* equational laws) | finds laws you forgot to write; cheap audit of hand-coded laws | ~10 min/type | **ADOPT — cheap win** |
| 3b | doctest / Haddock property examples | exec spec + docs in sync | ~5% | SKIP (internal tooling, not a public API) |
| 4b | GADTs + phantom indexing (state tags) | compile-time variant refinement | ~25–35% (inference pain) | SKIP (runtime tags + 2a suffice) |
| 5 | DataKinds + singletons (type-level shapes) | tensor dims composed at the type level | VERY HIGH | SKIP unless shape *theorems* are load-bearing |
| 5b | Naperian functors (structural equivariance) | equivariance by construction | EXTREME | SKIP (luxury; metamorphic tests instead) |
| 6 | **LiquidHaskell** + SMT refinement types | compile-time arithmetic/array/law proofs | EXTREME (SMT divergence, slow CI, immature) | SKIP (golden vectors already catch this) |
| 7 | Tagless-final multi-language DSL | N-language codegen from one algebra | VERY HIGH | SKIP unless N≥3 langs *and* specs churn |
| 9 | Program calculation (Bird–Meertens fusion) | provably-correct optimized hot loops | ~20% discipline | CONSIDER for hot data-parallel paths only |
| 10 | Agda + extraction (Cardano/seL4 pattern) | machine-checked proofs | 11+ person-years | NO (not safety-critical) |

---

## 2. By design family (the actual guidance)

- **Stateful search — `PaletteSearch` (MCTS).** Layer 0 ✓ (have it) **+ Layer 2a: model-based / state-machine testing.** A search is the one genuinely *stateful* thing we have; pre/post-condition + transition models (oracle correctness, tree-grows-monotonically, backup conservation, determinism) are exactly where `quickcheck-state-machine`/Hedgehog earn their keep. Skip type-level state tagging.
- **Numeric NN — look-NN (tensors, σ-equivariance).** Layer 0 + **2b denotational design** (σ-equivariance as a type-class morphism / meaning-preserving law) + **4a metamorphic relations** (`f(σ·x) = σ·f(x)`). **Do NOT** reach for DataKinds/singletons/Naperian — golden vectors already catch shape mismatches post-hoc; type-level shape proofs are ceremony unless a *shape-composition theorem* becomes load-bearing.
- **Data-structure invariants — HaarPalette / SplitTree (wellFormed, 256-leaf completeness).** Layer 0 + **Layer 1: smart constructors + `refined`/`validity` + quickcheck-classes.** A runtime `Validity`/refinement predicate for `wellFormed` is the right tool; **do NOT** encode 256-leaf completeness at the type level (cost ≫ benefit). LiquidHaskell measures only if a tree-balance bug ever proves costly *and* untestable.
- **Cross-language contracts — Swift/Python/Zig.** **Layer 3a golden vectors are mandatory and sufficient** for our 2–3 targets (have it). Tagless-final (Layer 7) only if we hit ≥3 churning targets. Never type-level-index spec outputs → codegen inputs (kills iteration speed).

---

## 3. Concrete next adoptions (small, high-leverage)

1. **`PaletteSearch` → state-machine tests (Layer 2a).** Model the search as a state machine: commands = `mctsStep`; postconditions = visits conserved, tree grows, determinism by seed, gallery ⊆ evaluated. Catches transition bugs our current per-property tests can miss. (Our prior hand-rolled draft failed *exactly* on state-transition/tree-growth bugs — this is the technique that would have caught them earlier.)
2. **QuickSpec on new ADTs (Layer 3c).** Run it on `Move`/`SplitTree`/`HaarPalette` ops to *discover* equational laws (e.g. `applyMove (invertMove m) = id`), then confirm our hand-written laws aren't missing any. ~10 min per type.
3. **`refined` predicates at the cross-language boundary (Layer 1).** Tag contract inputs/outputs with validity predicates so a malformed Swift/Zig payload is rejected at the boundary, not deep in the pipeline.
4. **Keep doing:** golden-vector parity (3a) + smart constructors + QuickCheck laws (0). Expand golden coverage as new specs land.

---

## 4. Open questions (decide before escalating)
- Is any **tensor-shape composition** in look-NN load-bearing enough to justify DataKinds, or do golden vectors catch every mismatch? (Default: golden vectors — skip DataKinds.)
- Have **tree-balance / completeness** bugs ever been costly *and* missed by tests? If never, runtime `Validity` is enough (skip LiquidHaskell).
- Will codegen ever target **≥3 churning languages**? If not, golden vectors beat a tagless-final DSL.

> **The smell to watch:** adopting a heavy layer because it's elegant, not because it catches a real, costly failure. Per the research consensus (Mercury, Cardano, practitioner write-ups): type-level rigor is justified for financial/regulatory/cryptographic correctness — *not* ML tooling. We default to Layers 0–2b + golden vectors and escalate only on evidence.

## 5. References
- QuickCheck — https://hackage.haskell.org/package/QuickCheck · QuickSpec (law discovery) — https://smallbone.se/papers/quickspec.pdf
- quickcheck-state-machine (model-based) — https://github.com/advancedtelematic/quickcheck-state-machine · quickcheck-classes — https://hackage.haskell.org/package/quickcheck-classes
- refined — https://hackage.haskell.org/package/refined · validity/genvalidity — https://cs-syd.eu/posts/2021-11-26-genvalidity
- Denotational design (Conal Elliott) — http://conal.net/blog/posts/denotational-design-with-type-class-morphisms · Theorems for Free — https://reasonablypolymorphic.com/blog/theorems-for-free/
- tasty-golden — https://hackage.haskell.org/package/tasty-golden · LiquidHaskell (when justified) — https://ucsd-progsys.github.io/liquidhaskell-tutorial/
- Cardano formal ledger spec (Agda+Haskell, the heavy end) — https://drops.dagstuhl.de/storage/01oasics/oasics-vol129-fmbc2025/OASIcs.FMBC.2025.6/OASIcs.FMBC.2025.6.pdf
- "What FP gets wrong about systems" (the pager-on-fire rule) — https://www.iankduncan.com/engineering/2026-02-09-what-functional-programmers-get-wrong-about-systems/
