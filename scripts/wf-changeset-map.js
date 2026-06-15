export const meta = {
  name: 'changeset-map',
  description: 'Use the Haskell spec-as-map tooling (Spec.Map, Haddock/Hoogle, import graph) to produce a precise "what to change and where" implementation map for the QuartetDelta Review overlay + the Dither/Scale verification gates. Design only — writes one doc, no code.',
  whenToUse: 'Before implementing a feature that threads the spec→codegen→Swift→view seam, when you want the change-set derived from the spec map rather than from blind grep.',
  phases: [
    { title: 'Browse', detail: 'regenerate the browsable spec (Haddock + Hoogle + import graph) and locate the targets on the map' },
    { title: 'Trace', detail: 'one tracer per area: QuartetDelta spec-side, the Review Swift seam, the Dither+Scale gates' },
    { title: 'Synthesize', detail: 'merge into one ordered change-set doc with exact files/anchors/data-paths + verification recipe' },
  ],
}

const ROOT = '/Users/daniel/SixFour'
const SPEC = `${ROOT}/spec`

const CHANGESET_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['area', 'specMapLocation', 'files', 'dataPath', 'reuse', 'verification', 'risks'],
  properties: {
    area: { type: 'string', description: 'which target this change-set covers' },
    specMapLocation: { type: 'string', description: 'where the target sits on the spec map: its SixFour.Spec.Map category, its import-graph neighbours (who it imports / could import it), and the Hoogle/Haddock types+functions involved' },
    files: {
      type: 'array',
      description: 'every file to touch, in apply order',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['path', 'anchor', 'change'],
        properties: {
          path: { type: 'string', description: 'repo-relative path' },
          anchor: { type: 'string', description: 'exact function/struct/line anchor to edit near (e.g. "ReviewPhaseField.body, after paletteStrip ~L103")' },
          change: { type: 'string', description: 'precise edit: what to add/modify and how it connects' },
          isNew: { type: 'boolean', description: 'true if a new file' },
        },
      },
    },
    dataPath: { type: 'string', description: 'the end-to-end data flow, e.g. "surface.palettesPerFrame → pick frames 0/21/42/63 → QuartetDelta.toSlots → coreColors(thr) → render outlined cells"' },
    reuse: { type: 'string', description: 'existing helpers/views/golden patterns to reuse instead of writing new (cite file:line)' },
    verification: { type: 'string', description: 'how to prove it: cabal test / spec-codegen regen / xcodebuild build-for-testing / the relevant golden' },
    risks: { type: 'string', description: 'collisions, open design questions, cell-field-law conformance, anything to decide before coding' },
  },
}

// ── Phase 1: regenerate + read the spec map ─────────────────────────────────
phase('Browse')
const mapFacts = await agent(
  `You are a SPEC-MAP CARTOGRAPHER for the SixFour repo (a Haskell-verified iOS app; the spec is a browsable MAP of the app — see CLAUDE.md "The spec is browsable"). Working dir: ${SPEC}.

  GOAL: regenerate the browsable spec and report WHERE on the map our three targets live, so downstream tracers navigate the map instead of grepping blind.

  1. Run the spec-as-map driver and capture its output (it lints Spec.Map coverage + Properties claims, builds Haddock with hyperlinked source + quickjump, a Hoogle DB, and a graphviz module import graph):
       bash ${SPEC}/scripts/spec-docs.sh   2>&1 | tail -40
     Report: did the Map lint and Properties-claim lint pass? Where did the Haddock index.html and the import-graph file land (give the paths it printed)?
  2. Read the categorised index module \`src/SixFour/Spec/Map.hs\` and report the CATEGORY + neighbours of: QuartetDelta, Dither, Scale (and note Collapse/PairTree/HaarRibbon since QuartetDelta feeds Act III).
  3. Inspect the generated import graph (the .dot/.png/.svg the script produced — read the .dot text) and report QuartetDelta's in/out edges: what it imports (e.g. Spec.Color) and what imports it. Same for Dither (note its Scale + spec-gif coupling) and Scale.
  4. Use Hoogle to list the exported symbols of the three modules, e.g.:
       cd ${SPEC} && hoogle --database=spec.hoo "QuartetDelta" 2>/dev/null | head -30   (and "Dither", "Scale"; if spec.hoo missing, read the module export lists directly)
     Report the key functions a consumer would call (e.g. QuartetDelta.toSlots/coreColors/quartetCore/slotDisplacement; Dither.goldenThresholds/realize/temporalMean; Scale.layerLawReport/allLayersHold).

  Return a tight factual briefing (map categories + import-graph neighbours + key exported symbols + the artifact paths). This is shared context for the tracers — be concrete, cite real paths.`,
  { label: 'browse:spec-map', phase: 'Browse' }
)
log('Spec map regenerated and read; tracing the three change-sets.')

// ── Phase 2: trace each area (parallel) ─────────────────────────────────────
phase('Trace')
const SHARED = `\n\nSHARED SPEC-MAP BRIEFING (from the cartographer — use it, don't re-derive):\n${mapFacts}\n`

const tracers = [
  {
    label: 'trace:quartet-spec',
    prompt: `You are tracing the SPEC + CODEGEN side of activating a Review motion overlay for Act II QuartetDelta. Working dir: ${ROOT}.
    QuartetDelta is already a golden-gated contract (commit on branch cleanup/haskell-bloat): Codegen.QuartetDelta → SixFour/Generated/QuartetDeltaGolden.swift, Swift port SixFour/Palette/QuartetDelta.swift, test QuartetDeltaGoldenTests. Read those three files + spec/src/SixFour/Spec/QuartetDelta.hs.
    QUESTION: does a fixed-quartet Review MOTION OUTLINE overlay need ANY new spec/codegen, or is the existing Swift port (toSlots/slotDisplacement/coreColors/quartetCore/corenessRanked) already sufficient? The overlay: pick 4 frames (default 0/21/42/63 of the 64), build slots, outline the low-displacement "core" slots and dim/annotate the high-displacement ones in the 16-colour palette widget.
    Determine: (a) is corenessRanked exposed in the Swift port? (b) is any threshold/normalisation needed that should be spec'd (e.g. a relative threshold = median, which the GOLDEN already pins) vs. computed in Swift? (c) should the overlay's threshold come from the golden's coreThreshold or be recomputed per-run? Decide and justify against the no-stubs / spec-is-source-of-truth rule.
    Return a CHANGESET for the spec/codegen side (likely SMALL or NONE — say so clearly if the port already suffices, and name any one helper to add to the Swift port like exposing corenessRanked).`,
  },
  {
    label: 'trace:review-seam',
    prompt: `You are tracing the SWIFT VIEW SEAM for a QuartetDelta motion-outline overlay on the Review screen. Working dir: ${ROOT}.
    Read SixFour/UI/Surface/ReviewPhaseField.swift IN FULL: the body (~L77), gifaHero (~L138), paletteStrip (~L153), and the helpers meanColour (~L364) / darkenCell (~L373) / the group-pick + cell-render machinery. Also read how a palette cell is rendered (CellSprite / CellField / the 16-colour widget) and the cell-field/pixelation law (memory: whole screen = one data-coloured 4pt cell field; Zig owns GIF math, Swift owns UI; no SwiftUI Text/SF-Symbols on the field).
    Determine EXACTLY where and how a motion overlay plugs in:
    - the data path: surface.palettesPerFrame → pick 4 frames (default 0/21/42/63) → QuartetDelta.toSlots → coreColors / slotDisplacements → render. Confirm palettesPerFrame is populated on Review (it is read at ReviewPhaseField:128/155).
    - the rendering: how to visually mark "core" vs "motion" slots within the existing paletteStrip/16-colour widget WITHOUT violating the cell-field law (e.g. brightness/outline via cell colour, not Text). Reuse darkenCell/meanColour.
    - whether it's a NEW private var (like paletteStrip) toggled by a control, or an annotation layered on the existing paletteStrip.
    - the frame-pick: fixed 0/21/42/63 first slice (no browse phase exists).
    Return a CHANGESET for the Swift view side with exact file:line anchors (ReviewPhaseField additions, any new small view, the toggle/control), the data path, reuse, and risks (cell-field-law conformance, where the toggle lives).`,
  },
  {
    label: 'trace:dither-scale-gates',
    prompt: `You are tracing the change-set for TWO verification-gate activations (priority 2, after the overlay). Working dir: ${ROOT}.
    Mirror the established golden pattern: read spec/src/SixFour/Codegen/PairTree.hs + the just-added spec/src/SixFour/Codegen/QuartetDelta.hs (both emitters), how app/Spec.hs wires them, spec.cabal exposed-modules, and an existing golden test (SixFourTests/PairTreeGoldenTests.swift).
    TARGET A — Spec.Dither gate: read spec/src/SixFour/Spec/Dither.hs (goldenThresholds/realize/temporalMean/binomialVariance, lawDitherMeanRecoversP). Plan a new Codegen.DitherGolden → SixFour/Generated/DitherGolden.swift pinning the golden-ordered threshold sequence + a small mean-recovery case table (p∈{0.25,0.382,0.5,0.75}, recoveredMean≈p, tol 0.05), consumed by a new SixFourTests/DitherGoldenTests.swift. Note it is the TEMPORAL dither model — SEPARATE from the shipped spatial dither (Spec.SpatialDither / SixFour/Palette/Dither.swift); do NOT conflate.
    TARGET B — Spec.Scale gate: read spec/src/SixFour/Spec/Scale.hs + spec/test/Properties/Scale.hs. The cheap high-value activation is to GUARANTEE Properties.Scale hard-asserts Scale.allLayersHold / layerLawReport at the real 64³ (scaleT/H/W/K) over ≥3 seeds, so the 64³ proof is a standing cabal-test gate rather than only asserted inside the spec-gif exe's render guard. Determine whether Properties.Scale ALREADY does this (read it) — if yes, the activation is a no-op/confirm; if no, specify the exact test additions.
    Keep spec-gif green: both modules stay imported by app/Gif.hs; you only ADD consumers.
    Return TWO change-sets (one per target) with exact files/anchors, the wiring lines (cabal exposed-modules + app/Spec.hs writeUtf8 + Spec.Map index for DitherGolden), verification, and risks.`,
  },
]

const changesets = await parallel(tracers.map(t => () =>
  agent(t.prompt + SHARED, { label: t.label, phase: 'Trace', schema: CHANGESET_SCHEMA })
)).then(rs => rs.filter(Boolean))

// ── Phase 3: synthesize one ordered change-set map ──────────────────────────
phase('Synthesize')
const plan = await agent(
  `You are writing the implementation change-set map for the SixFour repo. Working dir: ${ROOT}.
   Inputs — the spec-map briefing and the three traced change-sets:
   SPEC-MAP BRIEFING:
   ${mapFacts}

   TRACED CHANGE-SETS (JSON):
   ${JSON.stringify(changesets, null, 2)}

   Write ${ROOT}/docs/QUARTETDELTA-OVERLAY-CHANGESET.md — a precise "what to change and where" map:
   1. ## Map orientation — where these targets sit on the spec map (Spec.Map categories + import-graph neighbours), and a one-line statement of how the spec acts as the app map here.
   2. ## Part 1 — QuartetDelta Review motion overlay (PRIORITY 1): the merged spec-side + Swift-seam change-set as an ORDERED file-by-file checklist (path → anchor → exact change), the data path (frames 0/21/42/63 → toSlots → coreColors → cells), helpers to reuse, and the cell-field-law constraints. Call out any decision the user must make (e.g. toggle placement, recompute-threshold-vs-golden).
   3. ## Part 2 — Dither gate (PRIORITY 2a) and ## Part 3 — Scale gate (PRIORITY 2b): each as its own ordered checklist, noting if Scale is already-asserted (no-op).
   4. ## Verification recipe — per part: cabal build all && cabal test (+ spec-codegen regen where a golden changes) and iOS xcodebuild build-for-testing; the exact golden each part is pinned by.
   5. ## Open decisions — the short list the user should confirm before coding.
   Be concrete and conservative; prefer reuse over new files. After writing, return a ~12-line executive summary: the ordered file list for Part 1, whether the Scale gate is a no-op, and the open decisions.`,
  { label: 'synthesize:changeset', phase: 'Synthesize' }
)

return { doc: 'docs/QUARTETDELTA-OVERLAY-CHANGESET.md', areas: changesets.map(c => c.area), summary: plan }
