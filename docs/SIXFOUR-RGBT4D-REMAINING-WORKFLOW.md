> **Status: REMAINING-WORK WORKFLOW + DEBT REGISTER (2026-06-16).** Complements
> [SIXFOUR-RGBT4D-BUFFER-HARDENING-WORKFLOW.md](SIXFOUR-RGBT4D-BUFFER-HARDENING-WORKFLOW.md)
> (Phases 0–5-Swift ✅, on `master`). This is what's left and the debt the build incurred.

# RGBT-4D — remaining work + debt cleanup

## Where we are

Built, proven, golden-pinned, pushed: the lossless `(2×2)↔1` lift (`RGBTLift`), the loop gauge-fix
(`CanonicalPhase`), the SIMT circular buffer (`GroupRGBT.circularWindows`), the 1b feature layer
(`RGBTFeature`), the reversible cube-ladder tiers (`CubeLadder`), Q16 golden pins, and the
flag-gated Swift port (`RGBT4DLift.swift` + `RGBT4DGoldenTests`). 834 spec tests; Swift port
standalone-verified + compiles in-target.

## Remaining steps (in dependency order)

1. **Cross-language golden via codegen** *(this session — verifiable, closes debt D1).* Emit
   `RGBT4DGolden.swift` from `SixFour.Codegen.RGBT4D` (mirroring `Codegen.Collapse`) so the Swift
   port rides the `spec-codegen` drift gate instead of hardcoding values. **Done when** `cabal run
   spec-codegen` writes it and `RGBT4DGoldenTests` consumes it.
2. **End-to-end spec pipeline** *(verifiable, spec-side).* A `Spec.RGBT4D` (or extend an existing
   module) composing `circularWindows → RGBTFeature → CubeLadder` with an end-to-end law
   (capture → tiers, completeness + gauge preserved through the chain). **Done when** the
   composition law is QuickCheck'd.
3. **Phase 5b — the Metal `simd_shuffle` kernel** *(needs device/GPU — NOT verifiable in a headless
   env).* Hand-write the circular-stencil kernel as an optimisation of `RGBT4DLift`, verified
   bit-for-bit against `RGBT4DGolden` on an arm64 simulator/iPhone. **Done when** the on-device
   golden test passes on real hardware. Hand to a session with device access.
4. **Wire a consumer behind the flag** *(product step).* Connect the cube-ladder tiers to an actual
   export path under `rgbt4dEnabled`, producing the three GIF89a products. Co-design with the UI.
5. **Phase 6 — statistical validation at scale** *(spec-side).* Extend the entropy-grid sweep
   ([CubeLadderEntropyExperiments](../spec/experiments/CubeLadderEntropyExperiments.hs)) over the
   full pipeline with CIs + pre-registered criteria.

## Cross-port alignment (Metal ⟂ Zig) — the contract

Going past the spec means two ports; they align ONLY by both gating on the **one spec golden**,
never on each other. As of 2026-06-16:
- **Spec emits the golden from one source, two ways:** `RGBT4DGolden.swift` (codegen, for
  Swift/Metal) and `rgbt4d_golden.json` (`spec-fixtures`, for Zig).
- **Zig port ✅** — `Native/src/kernels.zig` (`s4_rgbt_lift_quad`, `s4_cube_lift_level` + inverses)
  verified bit-for-bit against `rgbt4d_golden.json` by `rgbt4d_fixture_test.zig`
  (`zig build test`: 28/29 pass, 1 unrelated skip).
- **Metal port (pending, device)** — must verify against the SAME golden. The arithmetic is shared
  (`@divFloor` = Haskell `div` = Swift `floorDiv`); the real divergence risk is the 2×2 **tiling
  layout**, which the level golden (`level_coarse` / `level_details`) pins exactly.

## Debt register (incurred building Phases 0–5)

| # | Debt | Severity | Plan |
|---|---|---|---|
| **D1** | Swift golden values were hardcoded in `RGBT4DGoldenTests`, not codegen-emitted — drift risk vs the spec. | medium | **Fix now** (step 1: `Codegen.RGBT4D` + generated `RGBT4DGolden.swift`). |
| **D2** | `CubeLadder`/`RGBTFeature` use list `!!` indexing — O(n²)–O(n⁴) on the reference. | low | Acceptable: these are *spec references*, not the perf path (the Swift/Metal port is). Documented in the modules; no action. |
| **D3** | `experiments/CubeLadderEntropyExperiments.hs` is a standalone repl script, not wired into cabal. | low | Intentional exploratory artifact (has a run header); leave. Promote to a test only if it becomes load-bearing. |
| **D4** | The spec FNV golden hashes Haskell `show` output (spec-internal), distinct from the cross-language integer golden. | low | D1's codegen golden is the cross-language contract; the FNV pin stays as the spec's own determinism guard. |

No `error`/`undefined` stubs, no missing Map entries, no Haddock warnings, no codegen drift were
introduced — those gates stayed green throughout.
