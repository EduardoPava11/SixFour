# SixFour — Global Palette → V2 Deferral Workflow (DEEP, reachability-complete)

> **Mandate (2026-06-18, Daniel):** **No deletion.** Map the full global-palette path to **V2** so
> **MVP1 ships per-frame only**. The global code stays compiled and recoverable behind ONE V2 flag
> that is OFF in MVP1. "Retirement" = retired *from MVP1*, not removed.
>
> **This is the HARD re-map.** It is grounded in a reachability call-graph: the global path has
> **FIVE entry points**, and MVP1 is per-frame-only ONLY when ALL five are guarded plus a settings
> sanitizer. Gating just the capture router LEAKS global through the Review screen.
>
> Supersedes the "flip + tag" sketch in `docs/SIXFOUR-PER-FRAME-GENOME-AB-MIGRATION-WORKFLOW.md` §5.

---

## 0. The mechanism + the principle

**One gate constant** (new file `SixFour/Settings/Feature.swift`):
```swift
enum Feature {
    /// The global (single) colour palette = the GIFB collapse path. DEFERRED TO V2.
    /// MVP1 ships per-frame only; flip to true to re-enable global in V2.
    static let globalPaletteV2 = false
}
```

**The reachability principle (why this is HARD):** "MVP1 is per-frame only" is true iff **every**
path from a user action to a global *leaf* passes through a `Feature.globalPaletteV2` guard. The
leaves are: `renderGlobalPalette`, `renderDeterministicGlobal`, `globalCollapse`/`s4_global_collapse`,
`encodeGlobal`/`encodeGlobalGIF`, `reindexCubeToGlobal`/`globalRemap`, `LadderExport.flatGlobalLeaves`,
`LadderExport.makeURL(.global64/.working16)`, `AtlasCollapse.collapse`. There are FIVE distinct user
entry points reaching them — §1.

Nothing is deleted: Zig exports, header count (33), spec tests, and goldens are **untouched**.

---

## 1. The reachability call-graph (FIVE entry points)

```
USER ACTION                                   → … → GLOBAL LEAF                         GUARD
─────────────────────────────────────────────────────────────────────────────────────────────
[1] Capture button
    SurfaceView capture → CaptureViewModel.renderOnce → renderDeterministic
      └ if paletteScope == .global → renderDeterministicGlobal
          └ DeterministicRenderer.renderGlobalPalette → SixFourNative.globalCollapse
              → Zig s4_global_collapse                                                  GS1

[2] Review › Ship / Export rung button        ⚠ BYPASSES paletteScope ENTIRELY
    ReviewPhaseField.exportRung → LadderExport.makeURL(.global64 | .working16)
      └ FarthestPointCollapse.collapse → LadderGIF.encodeGlobalGIF
          → reindexCubeToGlobal → globalRemap → GIFEncoder.encodeGlobal                 GS2

[3] Review › Group-pick tool                    ⚠ BYPASSES paletteScope
    ReviewPhaseField.openGroupPick → recomputeGroupGlobal
      └ LadderExport.flatGlobalLeaves(selectedGroups:)                                  GS3

[4] Review › Cut-lever tool                     ⚠ BYPASSES paletteScope
    ReviewPhaseField.openCutLever → LadderExport.flatGlobalLeaves(palettesPerFrame:)    GS4

[5] Review › Color Atlas curation               ⚠ PERSISTS into the NEXT capture
    ReviewPhaseField (atlasOpen) → AtlasCuration → AtlasPaletteStore.curatedLeavesQ16
      └ read at CaptureViewModel.renderDeterministicGlobal (curatedLeavesQ16 → render)  GS5
```

> The capture path [1] is the obvious one. Paths [2]–[5] live entirely in the **Review** screen and
> never consult `paletteScope` — they are the leak surface a naive gate misses.

---

## 2. THE GUARD-SITE TABLE (the heart of this workflow)

Insert `Feature.globalPaletteV2` at EACH site. With the flag false, every global leaf is unreachable.

| ID | File · function | Guard | Per-frame fallback (flag OFF) |
|----|----------------|-------|-------------------------------|
| **GS1** | `CaptureViewModel.renderDeterministic` · the `paletteScope == .global` branch | `if Feature.globalPaletteV2 && settings.paletteScope == .global { … }` | falls through to per-frame `render()` (the standard 64-frame LCT path) |
| **GS2** | `ReviewPhaseField.exportRung` (the Ship/Export rung action) | `guard Feature.globalPaletteV2 else { return }` **inside** `exportRung` (not just hiding the button) | rung export inert; user shares the committed per-frame GIF via the main Share button |
| **GS3** | `ReviewPhaseField.recomputeGroupGlobal` (group-pick) | `guard Feature.globalPaletteV2 else { return }` before `flatGlobalLeaves` | group-pick preview no-ops; `groupGlobal` stays empty |
| **GS4** | `ReviewPhaseField.openCutLever` (cut-lever) | `guard Feature.globalPaletteV2 else { return }` before `flatGlobalLeaves` | cut-lever preview no-ops; `cutFlatLeaves` empty |
| **GS5** | `ReviewPhaseField` Atlas-open action **and** the curated-leaves read in `renderDeterministicGlobal` | gate `atlasOpen = true` with the flag; AND `let curated = (settings.colorAtlasEnabled && Feature.globalPaletteV2) ? AtlasPaletteStore.shared.curatedLeavesQ16 : nil` | Atlas curation dormant; curated leaves never injected |
| **SAN** | `AppSettings.paletteScope` getter **or** GS1 read | `let scope = Feature.globalPaletteV2 ? settings.paletteScope : .perFrame` (sanitize a stale persisted `.global`) | a previously-saved `.global` preference is coerced to `.perFrame` |

**Total new code: ~5 guards + 1 sanitizer + 1 null-check ≈ 8 lines. Zero architectural change.**

> Best practice: also expose `Feature.globalPaletteV2` to SwiftUI so the Review buttons (Ship rung,
> group-pick, cut-lever, Atlas) are *hidden/disabled* when off — but the function-internal guards
> (GS2–GS5) are the load-bearing correctness; hiding the button alone is insufficient (the function
> must reject the call).

---

## 3. Leak register (paths that bypass the obvious gate)

| Leak | Path | Severity | Closed by |
|------|------|----------|-----------|
| **L1** | Ship/Export rung always collapses to global, no `paletteScope` check | **CRITICAL** | GS2 (guard the function, not the button) |
| **L2** | Group-pick + cut-lever run `flatGlobalLeaves` in Review (preview, but executes the global kernel) | HIGH | GS3, GS4 |
| **L3** | Atlas curated palette persists in `AtlasPaletteStore`, injected into the next capture | MEDIUM | GS5 (gate the read with the flag) |
| **L4** | Stale `paletteScope == .global` in UserDefaults re-routes on next launch | LOW | SAN (sanitizer) |
| **L5** | Tests call global leaves directly (not flag-guarded) | LOW (tests only) | none needed — tests gate the V2 code's correctness; they stay green (§6) |
| **L6** | `previewSamplerNote` "global on export" HUD string | TRIVIAL | guard the string with the flag (it is currently never bound to UI anyway) |

---

## 4. Shared-surface independence — VERIFIED (gating global cannot break per-frame)

The deep trace confirmed the per-frame path (`DeterministicRenderer.render` → `GIFEncoder.encode` →
shipped bytes) **never transits a global-only function**:
- `render()` calls `oklabToQ16`, `quantizeFrame`, `ditherFrame`, `significanceFill`, `paletteToSRGB8`,
  `gifAssemble` — all **pure Zig kernels**, each invoked with **per-frame** args. They are also called
  by the global path with *global* args, but the calls are independent (no shared state).
- `render()` never calls `globalCollapse`, never constructs `GlobalResult`, never reads
  `paletteScope`.
- The per-frame brands `CompleteVoxelVolume`/`SignificantVoxelVolume` are orthogonal to the global
  brands `GlobalCompleteVolume`/`GlobalSignificantVolume`.

**Conclusion:** turning `Feature.globalPaletteV2` off removes global reachability with **zero**
effect on the per-frame pipeline. Risk to MVP1 rendering: none.

---

## 5. Settings / UI surface — already minimal

- `ScopeSelector` (the global/per-frame toggle View) is **defined but NEVER instantiated** in any
  view body. So MVP1 already shows **no** global option. Keep the struct for V2; no removal.
- `AppSettings.paletteScope` defaults to `.perFrame` (safe). Persisted under
  `sixfour.paletteScope.v1`. Keep the property + key for V2; the SAN guard neutralises a stale
  `.global`.
- `enum PaletteScope { perFrame, global }` — keep both cases (V2 needs `.global`).

So the only UI-surface action is optional: hide the Review Ship-rung / group-pick / cut-lever /
Atlas buttons when the flag is off (cosmetic; GS2–GS5 are the correctness).

---

## 6. Gates — nothing deleted, so they stay green; ADD the flag invariant

`scripts/verify-doc-claims.sh`:
- **KEEP** the ANCHOR-1 checks that assert the global code is *present* (renderGlobalPalette exists,
  globalCollapse wraps `s4_global_collapse`, header = 33 symbols, header≡export set). Under deferral
  the code is kept, so these stay true. (Update their *descriptions* to "V2-gated".)
- **ADD** the MVP1 invariant:
  `check "MVP1 ships global OFF" grep -q 'static let globalPaletteV2 = false' SixFour/Settings/Feature.swift`
- **ADD** `check "live router is flag-guarded" grep -q 'Feature.globalPaletteV2 && settings.paletteScope == .global' …CaptureViewModel.swift`

`scripts/lint-no-global-palette.sh`:
- **STAYS A FREEZE** (block NEW global callers — exactly right for deferral). Add `Feature.swift`
  and the new guard sites' file (`ReviewPhaseField.swift` already allowlisted for some symbols;
  confirm) to the allowlists so the guards themselves don't trip the lint. Do NOT flip to forbid.

`Native` Zig + spec tests + goldens: **unchanged** (the V2 code is still gated by them).

---

## 7. Docs rewording (claim → V2 framing)

Pattern: every "the app emits a global palette today / global is the path" → **"MVP1 emits per-frame
palettes; the global/GIFB path is implemented + golden-gated but DEFERRED TO V2 behind
`Feature.globalPaletteV2 = false`."**

| File | Site | Change |
|------|------|--------|
| `CLAUDE.md` | §"Palette: global vs per-frame" | MVP1 per-frame; global genome design exists but V2-deferred |
| `STATUS.md` | intro ("global palette the app emits today…") | MVP1 per-frame; GIFB implemented, V2-gated |
| `STATUS.md` | BUILT ledger "GIFA→GIFB global collapse is WIRED" | reword to "implemented + golden-gated, V2-deferred (flag OFF in MVP1)" |
| `STATUS.md` | "Global-palette BACKEND" built row | "backend exists, V2-deferred" |
| `README.md` | GIFA/GIFB lines + "global palette the app emits" (≈ ll. 43-45, 93-94, 109, 194-198) | per-frame is MVP1; GIFB V2-gated |
| `docs/SIXFOUR-COLLAPSE-LEVER-UIUX.md` | top banner + §2.5 scope toggle | add "DEFERRED TO V2" banner; the lever/scope-toggle design is V2, do not wire in MVP1 |
| `NOTES.md` | 2026-06-17 "shipped global palette is…" | mark historical; append the 2026-06-18 V2-deferral note |

Tests' docstrings (`CollapseGoldenTests`, `ZigCollapseGoldenTests`, `Properties/Collapse.hs`,
`Properties/GroupRGBT.hs` backward-compat law, `collapse_fixture_test.zig`): add "regression
reference — gates the V2-gated global code's correctness; stays green." No test logic changes.

---

## 8. The deep workflow (phased; each leaves `s4 all` green)

- **V0 — Add the gate.** Create `SixFour/Settings/Feature.swift` with `globalPaletteV2 = false`.
  `xcodegen generate` (new file). Gate: build green.
- **V1 — Guard ALL FIVE entry points + sanitizer (GS1–GS5 + SAN).** This is the load-bearing phase:
  insert the guards per §2. Compile-check (arm64). Gate: build green; capture produces a per-frame
  GIF; (manually) no Review action reaches a global leaf. *This is the behavioural retirement.*
- **V2t — Retag.** Flip the inline tags `⚠️ DEPRECATED-GLOBAL-PALETTE` → `⚠️ V2-DEFERRED-GLOBAL-PALETTE`
  at the global definitions. Update the freeze-lint banner + allowlist (`Feature.swift`,
  guard-site files). Gate: `s4 lint` green.
- **V3 — Gates.** Add the two `verify-doc-claims.sh` checks (§6). Update ANCHOR-1 descriptions to
  "V2-gated". Gate: `s4 doc` green.
- **V4 — Docs.** Apply §7. STATUS records "global = V2-deferred". Gate: `s4 doc` green.
- **V5 — (optional) UI hide.** Hide/disable the Review Ship-rung / group-pick / cut-lever / Atlas
  buttons when the flag is off (cosmetic polish over the GS guards). Gate: build green.
- **V6 — Verify end-to-end.** `scripts/s4.sh all` green; confirm the shipped GIF is per-frame LCT;
  confirm the global code still compiles (kept). Update memory + migration §5.

> No git checkpoint required for safety (nothing removed), but commit one as normal hygiene.

---

## 9. Protected list — always live in MVP1 (never behind the flag)

- **Per-frame path:** `render()`, `encode()`, the pure Zig helpers, `CompleteVoxelVolume`/
  `SignificantVoxelVolume`.
- **Independent math:** `Spec.Barycenter`, `Spec.Bures`, `Spec.GroupRGBT` geometry,
  `Spec.RGBTFeature`, `Collapse.hs` `farthestPointCollapse`/`pooledCandidates` (the maximin floor the
  NN baseline + barycenter seed from — the `Collapse.hs` math/path split).
- **Future direction:** `AtlasBoard`/`AtlasTrainer`/`Spec.Atlas*`, the genome modules,
  `Spec.VoxelReduce`, `Spec.GenomePair`, `Spec.CubeLadder`, `Spec.TemporalLoop`.
- **Review-only utility:** `FarthestPointCollapse` (Swift) is used by the gated Review tools; it
  stays compiled (only its *callers* GS2–GS4 are gated).

---

## 10. Cross-references
- `docs/SIXFOUR-PER-FRAME-GENOME-AB-MIGRATION-WORKFLOW.md` §5 → here.
- `docs/SIXFOUR-REUSE-FIRST-NO-NEW-DEBT-WORKFLOW.md` — compose owned primitives.
- `scripts/lint-no-global-palette.sh` — stays a freeze.
- `sixfour-per-frame-genome-ab-pivot` (memory) — the standing direction.
