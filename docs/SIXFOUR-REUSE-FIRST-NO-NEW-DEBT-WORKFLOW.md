# SixFour — Reuse-First / No-New-Debt Workflow

> **Status:** PROCESS (2026-06-18). A standing gate for every phase of every migration. The rule:
> **before you write a new symbol, prove the behaviour isn't already owned somewhere you could
> reuse, port, or extend.** New code is the last resort, not the first. When you find duplication
> on the way, *consolidate it* — leave the tree with less debt than you found, never more.

This exists because SixFour already owns most of its math three times over (Haskell spec ≡ Zig ≡
Swift/Metal, golden-gated). That is a *strength* — but only if new work **composes** the owned
primitives. The failure mode is a fresh monolithic kernel that silently re-implements a lift, a
floor-div, or a Haar that already ships and is already proven. That fork is pure debt: two copies
to keep bit-exact, two places to break.

---

## 1. The principle

1. **The math is ported once.** If a behaviour exists in the Haskell spec, it has (or will have) a
   golden-gated Zig/Swift twin. Reuse the twin; do not write a second implementation of the same
   equation.
2. **Compose, don't re-derive.** A new operator is almost always a *composition* of owned
   primitives (the Haskell `VoxelReduce` owns no lift — it composes `CubeLadder` ∘ `TemporalLoop`).
   The port should compose the same owned kernels.
3. **Consolidate on contact.** If the audit finds the same equation inlined in N places, factor it
   into ONE named helper and route all N through it — in the *same* change. That is the cleanup.
4. **New code earns its keep.** Genuinely new behaviour is fine — but it gets the full ceremony
   (spec module → law → golden → twin → `Spec.Map` entry), so it becomes a reusable asset, not the
   next inline copy.

---

## 2. The Reuse Audit (run BEFORE writing any new symbol)

Five checks. Paste the filled template (§5) into the phase's section of its workflow doc.

### 2.1 Does the Haskell spec already own it?
- Browse, don't grep first: start at `SixFour.Spec.Map` (the categorised index) — CLAUDE.md says so.
- `Hoogle` by type/name: `spec/scripts/spec-docs.sh --serve` → search the signature you're about
  to write. A hit means it exists.
- `grep -rn "<conceptName>" spec/src/SixFour/Spec/` for the operator and its inverse.

### 2.2 Is there already a Zig/Swift/Metal twin?
- `grep -n "pub export fn s4_" Native/src/kernels.zig` — the whole kernel surface on one screen.
- `grep -rn "<helper>" Native/src/` for internal (non-exported) helpers — the math you need may be
  *inlined* in a neighbouring kernel (then §2.4 applies: factor it out).
- Check `SixFour/Native/SixFourNative.swift` for the FFI wrapper and `SixFour/Metal/*.metal` for a
  GPU twin.

### 2.3 Is it already gated by a golden?
- `grep -rln "<symbol>" Native/src/*fixture_test.zig spec/app/Fixtures.hs SixFourTests/` — if a
  golden already pins it, reuse is *free and safe*; you inherit the proof.

### 2.4 Is the math INLINED where it should be a shared helper?
- The smell: the same arithmetic (an S-transform `y + floor((x−y)/2)`, a `floorDiv`, a nearest-
  centroid argmin, a CRC) appears verbatim in more than one function.
- The fix (do it now, not later): extract ONE helper, route every copy through it, keep the goldens
  green. Log the consolidation in the tech-debt ledger as *closed*.

### 2.5 Would the new symbol be a MONOLITH that hides a composition?
- If the thing you're about to write is "do A then B" and A and B are both owned, **do not** write
  a combined `do_A_and_B` kernel. Orchestrate the two owned calls (in Swift, or a thin Zig wrapper
  that calls the existing internal fns). The composition's *spec* is the golden; the port composes.

---

## 3. Decision tree

```
Need behaviour X.
│
├─ Spec owns X?                     ── reuse it. (port the twin if missing; §2.2)
│
├─ Twin owns X (exported or inlined)?
│     ├─ exported  ── CALL it. zero new code.
│     └─ inlined   ── FACTOR it into a shared helper, route all callers, then call. (cleanup)
│
├─ X = compose(owned A, owned B)?   ── ORCHESTRATE A,B. no monolith. spec-of-composition = golden.
│
└─ X genuinely new?                 ── full ceremony: Spec module → law → golden → twin → Map entry.
                                       (now X is reusable; it will pass THIS audit next time.)
```

---

## 4. Anti-patterns (each is debt the audit must catch)

- **Parallel math.** A second implementation of an equation the spec already owns. (Two copies to
  keep bit-exact forever.)
- **Monolithic kernel.** `s4_do_everything` that inlines lifts/argmins instead of calling the owned
  primitives. Impossible to gate against the composable goldens; §5.1 of the AlphaZero doc warns of
  exactly this ("do NOT write a separate null-flag kernel").
- **Copy-paste lift / floor-div.** The MSL-truncation trap (`SIXFOUR-ALPHAZERO-COLLAPSE-DESIGN.md`
  §5) bites every *copy* of a signed division. One helper, many callers — never the reverse.
- **Orphan twin.** Porting a kernel with no Haskell golden behind it (nothing pins it; it WILL
  drift). New ports require their golden in the same change.
- **Silent fork of a retired path.** Reviving deprecated code (e.g. global-palette collapse) by
  copying it under a new name. The Phase-0 lint (`scripts/lint-no-global-palette.sh`) is the guard.

---

## 5. The Reuse Audit template (paste into each phase)

```
### Reuse Audit — <phase / symbol>
- Spec owns it?         <module:fn  | NO>
- Twin (exported)?      <s4_*       | inlined in <fn> | NO>
- Golden gate?          <fixture    | NO>
- Inlined-duplication?  <where, and the helper to factor | none>
- Verdict:              REUSE | FACTOR+REUSE | COMPOSE | NEW(ceremony)
- New code introduced:  <none | the minimal delta, justified>
```

### 5.1 Worked example — Phase 1b (`VoxelReduce` on device)

```
### Reuse Audit — Phase 1b: on-device 64³→16³ VoxelReduce
- Spec owns it?         SixFour.Spec.VoxelReduce (composition; owns no lift) — DONE, gated.
- Spatial half twin?    s4_cube_lift_level / s4_cube_unlift_level (Native/src/kernels.zig:688,716)
                        — EXACT twin of CubeLadder.liftLevel (calls rgbtLiftQuad). EXPORTED.
- Spatial golden?       haar_fixture_test.zig + rgbt4d_fixture_test.zig + spec/app/Fixtures.hs. YES.
- Temporal half twin?   NONE exported. BUT the S-transform pair-lift it needs is INLINED in
                        rgbtLiftQuad (kernels.zig:633-636: `q[1] + @divFloor(q[0]-q[1],2)`),
                        identical to TemporalLoop.liftPairT.
- Inlined-duplication?  YES — the S-transform appears 4× inline in rgbtLiftQuad/rgbtUnliftQuad.
- Verdict:              COMPOSE + FACTOR. No monolithic s4_voxel_reduce.
- Plan (no new lift math):
    1. CLEANUP: factor the inlined S-transform into `sLift`/`sUnlift` helpers; route the 4 copies
       in rgbtLiftQuad/rgbtUnliftQuad through them. Goldens stay green (byte-identical). Debt down.
    2. REUSE: spatial half calls s4_cube_lift_level per channel, per frame — zero new code.
    3. MINIMAL NEW: a temporal one-level sequence split that REUSES `sLift` (the only genuinely
       new surface — a loop, not an equation), with its own Haskell golden from TemporalLoop.
    4. ORCHESTRATE: VoxelReduce on device = Swift composing (2)+(3), mirroring the Haskell spec.
       The composition's golden is Spec.VoxelReduce; no s4_voxel_reduce monolith.
- New code introduced:  one temporal-split loop reusing sLift; one helper extraction (net debt ↓).
```

This is the difference the audit makes: the naïve Phase 1b ("write `s4_voxel_reduce`") would have
re-implemented a lift that ships and is proven. The audited Phase 1b writes **one loop**, reuses two
owned kernels, and *removes* four inline copies of the S-transform on the way through.

---

## 6. Integration with the gate

- **Per phase:** the filled §5 template lives in that phase's workflow section. A phase that adds a
  new `s4_*` export without a Reuse-Audit verdict of `NEW(ceremony)` is a review failure.
- **Mechanical guard (optional, cheap):** a grep lint that flags a likely duplicate of a known
  primitive — e.g. a *new* occurrence of the S-transform literal `+ @divFloor(` pattern or a
  hand-rolled `floorDiv`/argmin outside the blessed helper files. Mirror
  `scripts/lint-no-global-palette.sh`'s freeze-the-set approach.
- **Ledger:** every consolidation (§2.4) is logged as a *closed* row in the tech-debt ledger, so the
  cleanup is visible, not silent.

---

## 7. Cross-references
- `docs/SIXFOUR-PER-FRAME-GENOME-AB-MIGRATION-WORKFLOW.md` — the migration this gates (Phase 1b uses
  §5.1 above).
- `CLAUDE.md` — "The spec is browsable — use it" (start at `Spec.Map`, Hoogle before grep) and the
  golden-vector discipline this workflow extends.
- `docs/SIXFOUR-ALPHAZERO-COLLAPSE-DESIGN.md` §5 — the monolith / copy-paste-floor-div anti-patterns
  in their original context.
```
