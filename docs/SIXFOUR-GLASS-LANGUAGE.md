# SixFour Liquid Glass Design Language — "GLASS"

**Status:** Companion constitution to `docs/SIXFOUR-DESIGN-LANGUAGE.md` ("GRID"), v1.0 (2026-06-01.)
**Scope:** the *material* layer — Apple **Liquid Glass** (iOS 26) — on the surfaces where SixFour uses chrome-over-content: **Review, Settings, and the state/fallback screens.** This document is the detailed definition of GRID's one-line `EXEMPT-GLASS-REVIEW` exemption.
**Hard boundary (read first):** **Glass is RETIRED on the capture HUD.** The HUD is governed by GRID's flat 2 pt cell-grid (the cube *is* the content). Glass governs only the surfaces that float chrome *over* content. Where this document and GRID overlap, **GRID wins**; this document only fills the surface GRID leaves to "glass MATERIAL, retained for Review/Settings, its documented use."
**Maturity flag:** the *rules* here are authoritative; some describe the **target**, and the **current code has three known seams** (a legacy `.ultraThinMaterial` footer, a stray glass chip on the capture HUD, an unrationalised corner scale) tracked in §7. Those are migration debt, not counter-examples.

---

## 0. Why glass exists here — and nowhere else

GRID's Cardinal Law is that the 64×64 cube is the UI's *law*: the capture HUD is **content**, drawn as flat indexed cells, no opacity, no material, no rounding. Liquid Glass is the opposite treatment — a translucent **material** that samples and refracts what is *behind* it. The two are not competing styles; they describe two different relationships to content:

| | Capture HUD | Review / Settings / State |
|---|---|---|
| Relationship to content | the UI **is** the content (the cube) | chrome floats **over** content (GIF, palette, form) |
| Treatment | flat 2 pt cells, indexed colour | Liquid Glass material |
| Governed by | **GRID** | **GLASS** (this doc) |
| Pitch | 2 pt cell lattice | 6 pt Review family (`EXEMPT-REVIEW-PITCH`) |

> **THE GLASS BOUNDARY LAW.** Glass is *material for chrome floating over content*. It may never be applied to a **data cell** — never the camera preview, the GIF hero, a palette swatch, a treemap leaf, or a 64×64 tile. Content is never rendered *on* glass; glass is never a fill *for* content. (This is the material-side mirror of GRID Law #2 "the grid is the render surface.")

---

## 1. Principles (strictly ordered G1 > G2 > G3 > G4 > G5)

### G1 — Glass is chrome, never content.
Floating controls, badges, selectors, action bars, sheets. The thing *behind* the glass is the content; the glass is the affordance. If an element carries data the user reads as the product (a colour, a frame, a pixel), it is content and gets a cell, not glass.

### G2 — One material family: Liquid Glass `.regular`.
Every glass surface uses Apple's iOS-26 `.glassEffect`/`.buttonStyle(.glass)` family. The legacy `.ultraThinMaterial`/`.regularMaterial` blurs are **retired** (one migration target remains: the stats footer, §7). `.clear` glass is reserved for the single documented case in §3.2; default is `.regular`.

### G3 — Glass never samples glass.
Any group of sibling glass shapes **must** share one `GlassEffectContainer`, so they sample a single backdrop region (no glass-on-glass artifacts) and can morph between one another. A lone glass shape may stand alone; two or more in proximity must be contained.

### G4 — Colour is informed by the content behind it.
Tint defaults to white. Where the chrome should reflect what the camera/scene shows, it takes the clamped scene accent (`SFTheme.accent`), echoing Apple's "colour informed by surrounding content." **Selection** is expressed as a *defined* glass `.tint`, not an ad-hoc opacity wash.

### G5 — Accessibility is structural (inherited from GRID P5).
Reduce Transparency degrades glass to a solid, contrast-passing fill; symbols/text on glass hold WCAG thresholds over the *brightest* content they may float over; every glass control is a real labelled control with a ≥ 44 pt hit target; one value, one owner.

---

## 2. Foundations — the Apple API surface SixFour uses

These are the iOS 26 Liquid Glass primitives the language is built from (Apple frameworks only; zero deps, per CLAUDE.md):

| API | Use in SixFour |
|---|---|
| `.glassEffect(_ glass:in:)` | apply glass to a view in a given shape |
| `Glass.regular` / `Glass.clear` | the material variant (default `.regular`) |
| `.interactive()` | live press/scale response — every *tappable* glass surface |
| `.tint(_ color:)` | selection / emphasis tint (G4) |
| `GlassEffectContainer(spacing:)` | the shared sampling region (G3); `spacing` ≈ the morph radius |
| `.glassEffectID(_:in:)` + `@Namespace` | morph identity for controls that appear/disappear (target; not yet used) |
| `.buttonStyle(.glass)` | secondary glass action button |
| `.buttonStyle(.glassProminent)` | primary / emphasised glass action button |

**Shape vocabulary:** `Circle` (icon buttons), `RoundedRectangle(cornerRadius:)` (chips, badges, selectors), `Capsule` (pill controls). No bespoke shapes.

---

## 3. Tokens

Glass tokens live in `SFTheme` (`SixFour/UI/Theme.swift`). They are the **KEEP-for-Review** tokens that GRID §9.8 explicitly exempts from the capture-HUD single-pitch lint — they are legal here precisely because this surface is `EXEMPT-REVIEW-PITCH`.

### 3.1 The token table

| Token | Value | Meaning |
|---|---|---|
| `glassIconButtonSize` | 48 pt | circular icon-button diameter (≥ 44 pt HIG floor ✓) |
| `glassClusterSpacing` | 12 pt | `GlassEffectContainer` spacing = morph radius between clustered controls |
| **`cardCorner`** | 10 pt | **chip / badge** corner (read-only glass containers) |
| **`controlCorner`** | 0 pt | **selector segment** corner (square glass — the segmented look) |
| **`pillCorner`** | 14 pt | **pill** corner (form pills / large rounded controls) |
| `pillVerticalPad` / `pillHorizontalPad` | 7 / 14 pt | pill padding |
| `accent(_:towardWhite:)` | clamped srgb | content-informed tint (G4) |
| `hairline` | white @0.18 | selected-segment glass `.tint` and strip strokes |

### 3.2 The corner scale (rationalised)

The three corner radii are **not** redundant — they encode a deliberate hierarchy. Use exactly one per role; do not introduce a fourth literal:

| Corner | Radius | Role | Why |
|---|---|---|---|
| `controlCorner` | **0 pt** | selector **segments** | a row of square glass reads as one segmented control, edges flush in the container |
| `cardCorner` | **10 pt** | **chips & badges** (status, determinism seal, info) | a self-contained floating object reads as a rounded card |
| `pillCorner` | **14 pt** | **pills** (large standalone controls, form rows) | the most rounded; a single emphasised affordance |

> A bare numeric corner radius on a glass surface (e.g. the current `cornerRadius: 6` at `CaptureView.swift:106`) is a token violation — see §7.

### 3.3 The `.clear` carve-out
`.regular` is the default everywhere. `.clear` glass is permitted **only** when the glass floats directly over the **GIF hero or palette content** and must not tint it (maximal legibility of the colour beneath) — e.g. a future overlay control on the playing GIF. Read-only chips and selectors always use `.regular`.

---

## 4. Components

> Same seven-section template as GRID §6 — **Anatomy → Sizing → States → Behavior → Do/Don't → Accessibility → Code API.** A glass widget that omits a section is not done. Every glass control grows by adding cells/segments, never by inventing a new material treatment.

### 4.1 GlassIconButton — circular icon control
*(`SixFour/UI/Components/GlassControls.swift:26`)*

- **Anatomy** — a single SF Symbol centred in a circular `.regular` glass disc.
- **Sizing** — `glassIconButtonSize` = 48 pt (≥ 44 pt floor). Grow by raising the token, never by scaling a glyph past its frame.
- **States** — idle · pressed (via `.interactive()` scale) · the symbol morphs with `.symbolEffect(.replace)` when `systemImage` changes inside `withAnimation`.
- **Behavior** — `Button` + `.buttonStyle(.plain)` + `.glassEffect(.regular.interactive(), in: Circle())`.
- **Do / Don't** — DO pass the scene accent as `tint` when the chrome should reflect the scene; DON'T place it on the capture HUD (that is GRID's `CellButton`).
- **Accessibility** — required `accessibilityLabel`; optional hint via `OptionalAccessibilityHint`.
- **Code API** — `GlassIconButton(systemImage:accessibilityLabel:tint:action:)`.

### 4.2 GlassToolbarCluster — the shared sampling container
*(`GlassControls.swift:59`)*

- **Anatomy** — an `HStack` of glass children inside one `GlassEffectContainer` (G3).
- **Sizing** — `spacing` = `glassClusterSpacing` (12 pt); also the morph radius.
- **States** — none itself; hosts children's states.
- **Behavior** — the *only* sanctioned way to place ≥ 2 sibling glass controls. Enables future morphing between members.
- **Do / Don't** — DO wrap every multi-control glass row in it; DON'T nest a container in a container, and DON'T let two bare `.glassEffect` siblings sit outside one.
- **Accessibility** — transparent to a11y; children own their labels.
- **Code API** — `GlassToolbarCluster(spacing:) { … }`. *(In use: `GlobalPaletteEditorView.swift:87`.)*

### 4.3 GlassInfoChip — read-only status chip
*(`GlassControls.swift:72`)*

- **Anatomy** — content padded inside a `.regular` glass `RoundedRectangle(cornerRadius: cardCorner)`. Non-interactive (no `.interactive()`).
- **Sizing** — padding 12 h / 8 v; corner = `cardCorner` (10 pt) — never overridden with a literal.
- **States** — static; re-renders on content change.
- **Behavior** — ephemeral status: timing summaries, the determinism badge, phase notes.
- **Do / Don't** — DO use for read-only overlays on Review; DON'T use it as a button (no glass press affordance on a non-control); DON'T ship it on the capture HUD (§7 debt).
- **Accessibility** — the content's own labels; combine where it reads as one phrase.
- **Code API** — `GlassInfoChip(cornerRadius:) { … }` *(default corner = `cardCorner`; do not pass a literal)*.

### 4.4 GlassSelector — segmented glass *(named here; currently inline)*
*(pattern duplicated in `PaletteGridView.swift:76/88` and `PaletteTreeView.swift:93/105/136`)*

- **Anatomy** — a row of glass segments in one `GlassEffectContainer`; each segment a `RoundedRectangle(cornerRadius: controlCorner = 0)`; exactly one selected.
- **Sizing** — segments ≥ 44 pt hit; container spacing = `glassClusterSpacing`.
- **States** — idle = `.regular.interactive()`; **selected = `.regular.tint(.white.opacity(0.18)).interactive()`** (the one sanctioned selection tint, G4); disabled = dimmed.
- **Behavior** — tap selects; haptic on change; exactly one active.
- **Do / Don't** — DO express selection as the defined glass `.tint`; DON'T draw a filled highlight rectangle behind a segment; DON'T let a segment fall below the 44 pt floor.
- **Accessibility** — row `accessibilityElement(children: .contain)`; each segment a `Button` with `.isSelected`; one spoken value.
- **Code API (target)** — extract the inline pattern into `GlassSelector(options:selection:)` so `RepresentationSelector` / `ScopeSelector` / `BranchingSelector` / `GridAxisSelector` share one implementation instead of duplicating the modifier.

### 4.5 Glass action buttons — primary vs secondary
*(`GIFReviewView.swift:170/177/181`, `StateScreens.swift:27`)*

- **Anatomy** — a labelled `Button` with a system glass button style.
- **Sizing** — system metrics; ≥ 44 pt hit.
- **States** — system-managed (idle/pressed/disabled).
- **Behavior** — **`.glassProminent`** = the one primary/affirmative action per surface (Save/Share on Review; Retry on the failure screen). **`.glass`** = secondary actions. At most one `.glassProminent` per surface.
- **Do / Don't** — DO reserve `.glassProminent` for the single primary action; DON'T stack two prominent buttons; DON'T hand-roll a glass fill when a button style exists.
- **Accessibility** — the button's label is the action; destructive actions get a role/confirmation.
- **Code API** — `.buttonStyle(.glassProminent)` / `.buttonStyle(.glass)`.

---

## 5. Patterns

### 5.1 PATTERN-GLASS-LAYERING — glass floats, content sits
Z-order is fixed: **content (GIF hero, palette grid, treemap) at the base; glass chrome above it.** Glass never sits *under* content and content never composites *onto* glass. The backdrop a glass shape samples is always content or field — never another glass surface (G3).

### 5.2 PATTERN-GLASS-CONTAINER — one region per cluster
Every set of ≥ 2 sibling glass controls is wrapped in exactly one `GlassEffectContainer(spacing: glassClusterSpacing)`. Members may later morph into one another via `.glassEffectID(_:in:)` with a shared `@Namespace` (e.g. a selector that grows a segment, a control that appears on play). Single isolated chips need no container.

### 5.3 PATTERN-GLASS-TINT — content-informed colour
Default tint white. When chrome should reflect the scene, pass `SFTheme.accent(sceneTint)` (clamped for legibility, G5). Selection uses the fixed `hairline` tint (`white @0.18`). No other ad-hoc opacities on glass.

### 5.4 PATTERN-GLASS-WHENTOUSE — the decision rule
```
Is the element DATA the user reads as the product (a colour / frame / pixel)?
   → YES: it is content. Use a GRID cell. NO glass.
Is it chrome floating OVER content on Review/Settings/State?
   → YES: use glass (this doc).
Is it on the capture HUD?
   → ALWAYS a GRID cell. NO glass. (Boundary Law.)
```

---

## 6. Accessibility & legibility

- **RULE-GLASS-REDUCE-TRANSPARENCY:** under Reduce Transparency / Increase Contrast, every glass surface degrades to a solid, contrast-passing fill (no blur/refraction). A tested path, mirroring GRID §8.6.
- **RULE-GLASS-CONTRAST:** a symbol/text on glass must hold ≥ 4.5:1 (text) / ≥ 3:1 (non-text) against the **brightest content it can float over** — the worst-case GIF frame or palette swatch, not the average. White-on-`.regular`-glass is the safe default; tinted glass is contrast-checked.
- **RULE-GLASS-TOUCH:** every interactive glass control ≥ 44 pt; `glassIconButtonSize` = 48 ✓.
- **RULE-GLASS-SINGLEOWNER:** one value, one owner (inherited from GRID); a chip that merely *displays* a value the control already speaks is `accessibilityHidden`.
- **RULE-GLASS-MOTION:** glass press/morph animations are fine, but any *looping* motion respects Reduce Motion (snap, don't pulse).

---

## 7. Governance & current-state honesty

Same governance spine as GRID §9: the design language is enforced, drift is tracked openly. Three **known seams** between this language and the code today (migration debt, not counter-rules):

| # | Seam | Location | Resolution |
|---|---|---|---|
| 1 | **Legacy material**, not Liquid Glass | `StatsFooterView.swift:36` uses `.background(.ultraThinMaterial, in: Capsule())` | migrate to `.glassEffect(.regular, in: Capsule())` (G2) |
| 2 | **Glass on the capture HUD** (boundary violation) | `CaptureView.swift:106` puts a `GlassInfoChip` phase banner on the HUD | the HUD phase banner becomes a GRID cell-grid element; glass leaves the HUD (GRID §6.10 retirement) |
| 3 | **Off-token corner** | `CaptureView.swift:106` passes `cornerRadius: 6` | resolved with #2 (the chip leaves the HUD); elsewhere use the §3.2 corner scale only |
| 4 | **Duplicated selector pattern** | `PaletteGridView` + `PaletteTreeView` repeat the selected-tint glass modifier inline | extract `GlassSelector` (§4.4) so the four selectors share one implementation |

### Lints (analogous to GRID §9.3)
- **LINT-GLASS-FAMILY:** flag `.ultraThinMaterial`/`.regularMaterial`/`.thinMaterial` in app chrome (seam #1).
- **LINT-GLASS-HUD:** flag any `glassEffect`/`buttonStyle(.glass*)`/`Glass*` in capture-HUD files (Boundary Law; seam #2). This is the material-side twin of GRID's `gifCellPt`-on-HUD guard.
- **LINT-GLASS-CORNER:** flag a bare numeric `cornerRadius:` on a glass shape; require `controlCorner`/`cardCorner`/`pillCorner` (§3.2; seam #3).
- **LINT-GLASS-CONTAINER:** flag ≥ 2 sibling `.glassEffect` views not inside a `GlassEffectContainer` (G3).

### Governance rules
- **RULE-GLASS-SSOT:** glass sizes/corners/tints live only in `SFTheme`; no widget hardcodes them.
- **RULE-GLASS-DECISIONS:** changing where glass appears (adding glass to a new surface, or removing it) is a GRID `GATE-DECISIONS` item — signed off before code, never per-widget drift.
- **RULE-GLASS-LIFECYCLE:** a new glass control is composed from §4 components; adding a new glass component updates §4, never ad hoc inline `.glassEffect`.

---

## 8. References
- **Apple HIG — Materials / Liquid Glass.** https://developer.apple.com/design/human-interface-guidelines/materials
- **Apple Developer — Applying Liquid Glass to custom views** (`glassEffect`, `GlassEffectContainer`, `glassEffectID`, `.interactive`, `.tint`). https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- **Apple Developer — `buttonStyle(.glass)` / `.glassProminent`.** https://developer.apple.com/documentation/swiftui/primitivebuttonstyle
- **GRID constitution** — `docs/SIXFOUR-DESIGN-LANGUAGE.md` (§9.7 `EXEMPT-GLASS-REVIEW`, §6.10 HUD glass retirement, §7.2 `EXEMPT-REVIEW-PITCH`).
- **As-built source** — `SixFour/UI/Components/GlassControls.swift`, `…/PaletteGridView.swift`, `…/PaletteTreeView.swift`, `…/StatsFooterView.swift`, `…/Screens/Review/GIFReviewView.swift`, `…/Screens/State/StateScreens.swift`, `…/UI/Theme.swift`.
- **App map** — `docs/APP-MAP.md` (where each glass surface lives).
