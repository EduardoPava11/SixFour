export const meta = {
  name: 'unified-feature',
  description: 'Unified SixFour feature pipeline: Haskell spec-map tooling + web prior-art + spec-law drafting + UI implementation, in one workflow. Drives the N×M cell-widget footprint API + the frame-locked-detent QuartetDelta threshold slider. Implements (uncommitted) and adversarially reviews.',
  whenToUse: 'When a SixFour increment spans the spec (Haskell laws/golden), external prior art (web), and the Swift UI at once — and you want one pipeline that grounds, designs, builds, and verifies instead of separate workflows.',
  phases: [
    { title: 'Ground', detail: 'three lenses in parallel: spec-map cartographer (Haddock/Hoogle/import-graph) + web prior-art + UI/Swift-seam tracer' },
    { title: 'Synthesize', detail: 'merge into one change-set + draft the actual Haskell law source + Swift widget skeletons' },
    { title: 'Implement', detail: 'apply spec+codegen+Swift, run the full gate (cabal test + spec-codegen + iOS build-for-testing); leave UNCOMMITTED for review' },
    { title: 'Review', detail: 'adversarial check of the diff vs the laws, cell-field law, and the frame-locked-detent contract' },
  ],
}

const ROOT = '/Users/daniel/SixFour'
const SPEC = `${ROOT}/spec`

// The increment this run targets (parameterizable via args for reuse).
const TARGET = (typeof args === 'string' && args) ? args :
  `The N×M cell-widget footprint language + its first frame-locked-detent widget:
   (1) an explicit N×M (whole-GIF-pixel-cell) footprint API on the chrome widgets (CellActionButton et al.),
       replacing point-authored sizing (e.g. minHeight: 44 → 11×11 cells), per docs/SIXFOUR-CELL-WIDGET-LANGUAGE.md;
   (2) the QuartetDelta core/motion THRESHOLD SLIDER on the Review screen (M×11 cells, knob = 1 lit cell):
       dragging it re-thresholds the motion overlay's core set AND fires one haptic CellTick per cell crossed,
       FRAME-LOCKED to the 20fps cell-field refresh (one cell = one frame = one tick = one repaint);
   (3) the spec backing for the timing: new laws lawTicksFrameMonotone + lawDetentTriadCoincident on
       Spec.CellMechanics (built on cellsCrossed / lawTickConservation + Spec.Display's 20fps clock).`

// ── Phase 1: GROUND — three unified lenses on the target ────────────────────
phase('Ground')
const lenses = [
  {
    label: 'ground:spec-map',
    prompt: `You are the HASKELL SPEC-MAP cartographer (the spec is a browsable map of the app — CLAUDE.md). Working dir: ${SPEC}.
    TARGET:\n${TARGET}\n
    1. Regenerate the browsable spec map: \`bash ${SPEC}/scripts/spec-docs.sh 2>&1 | tail -30\` (Map lint + Properties-claim lint + Haddock + Hoogle + graphviz import graph). Report lint status + the import-graph + Haddock paths it printed.
    2. Read \`src/SixFour/Spec/Map.hs\` and report the categories + import-graph neighbours of Spec.CellMechanics and Spec.Display (and PlaybackClock if present). Read the CellMechanics module header + its detent section (cellsCrossed, CellTick, lawTickConservation, the reactive pulse tokens, lawDropColorMatchesMove) and Spec.Display's 20fps event model.
    3. Determine, from the spec, the EXACT seam where the two NEW laws attach: where do CellTick tokens get emitted? what is the frame/clock representation in Spec.Display? Is there a frame-index type to quantise ticks against? Report the concrete types/functions (with file:line) that lawTicksFrameMonotone (≤1 tick per frame slot, monotone in frame index) and lawDetentTriadCoincident (haptic+pulse+repaint share a frame index) must be written in terms of.
    Return a precise spec-side briefing: the attach points, the existing helpers to reuse, and whether any new type (a FrameIndex) is needed.`,
  },
  {
    label: 'ground:web-priorart',
    prompt: `You are the WEB PRIOR-ART researcher for an iOS implementation detail. Use WebSearch/WebFetch (load via ToolSearch if needed).
    TARGET:\n${TARGET}\n
    Research the IMPLEMENTATION prior art for two specific things, and report concrete, citable findings (with URLs):
    1. Frame-locking haptics to the display refresh on iOS: how to fire UIImpactFeedbackGenerator / CoreHaptics events in lockstep with a CADisplayLink callback; the right generator for a crisp detent "tick"; prepare()/impactOccurred(intensity:) timing; whether coalescing multiple ticks into one frame is the accepted pattern; any pitfalls (haptic latency, main-thread, 120Hz ProMotion vs a fixed 20fps app clock). Apple HIG on haptics + detents.
    2. N×M cell/tile footprint APIs in real UI toolkits (how grid systems express a widget's row/col span + minimum cell footprint) — to inform an idiomatic Swift API shape for "this widget is W×H cells".
    Return a tight findings brief with the 5-8 most load-bearing facts + URLs. Flag anything that would change the design (e.g. if firing one haptic per CADisplayLink tick is discouraged).`,
  },
  {
    label: 'ground:ui-seam',
    prompt: `You are the UI / SWIFT-SEAM tracer. Working dir: ${ROOT}.
    TARGET:\n${TARGET}\n
    1. Read SixFour/UI/GlobalLattice.swift (the gifPx=4pt atom + the cell-count constants: touch floor 11, secondary 12, etc.). Read SixFour/UI/Components/CellChrome.swift (CellActionButton + CellSlider — the existing slider primitive!) and report CellSlider's current API + how it renders/handles drag.
    2. Read the SHIPPED motion overlay seam: SixFour/UI/Surface/ReviewPhaseField.swift — the actionRow (the Motion toggle), motionCoreSet, paletteStrip. Determine exactly where a THRESHOLD SLIDER plugs in (a @State threshold; motionCoreSet currently uses medianDisplacementThreshold — the slider would override it with a draggable value feeding QuartetDelta.coreColors(thr,slots)).
    3. Find the 20fps clock leaf in Swift (PlaybackClock / a CADisplayLink driver — grep) and how existing haptics fire today (grep UIImpactFeedbackGenerator / CellMechanics token consumers). Report the call-site where a frame-locked CellTick would be flushed.
    4. Report what an explicit N×M footprint API on CellActionButton would replace (the point-based minHeight:44 / GlobalLattice.pt(...) sizing) and how CellSlider should express M×11.
    Return a concrete Swift-side briefing with file:line anchors for: the footprint-API change, the slider widget, the threshold wiring into motionCoreSet, and the frame-locked haptic flush point.`,
  },
]
const grounding = await parallel(lenses.map(l => () =>
  agent(l.prompt, { label: l.label, phase: 'Ground' })
)).then(rs => rs.filter(Boolean))
const BRIEF = `SPEC-MAP LENS:\n${grounding[0] ?? '(none)'}\n\nWEB PRIOR-ART LENS:\n${grounding[1] ?? '(none)'}\n\nUI-SEAM LENS:\n${grounding[2] ?? '(none)'}`
log('Three lenses merged; synthesizing the change-set + drafting spec laws.')

// ── Phase 2: SYNTHESIZE — one change-set + drafted law source ────────────────
phase('Synthesize')
const PLAN_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['summary', 'specChanges', 'swiftChanges', 'gateRecipe', 'decisions', 'risks'],
  properties: {
    summary: { type: 'string' },
    specChanges: { type: 'array', items: { type: 'object', additionalProperties: false,
      required: ['file', 'change'], properties: {
        file: { type: 'string' },
        change: { type: 'string', description: 'precise edit' },
        draftSource: { type: 'string', description: 'the actual Haskell (or codegen) source to add, ready to paste — for the new laws/functions' },
      } } },
    swiftChanges: { type: 'array', items: { type: 'object', additionalProperties: false,
      required: ['file', 'change'], properties: {
        file: { type: 'string' },
        change: { type: 'string' },
        anchor: { type: 'string', description: 'function/struct/line to edit near' },
      } } },
    gateRecipe: { type: 'string', description: 'exact commands to verify, in order' },
    decisions: { type: 'array', items: { type: 'string' }, description: 'design decisions taken (with the chosen default)' },
    risks: { type: 'string' },
  },
}
const plan = await agent(
  `You are the SYNTHESIZER. Working dir: ${ROOT}. Merge the three grounded lenses into ONE implementation-ready change-set for the target, drafting the ACTUAL new Haskell law source so the implementer pastes, not invents.
   TARGET:\n${TARGET}\n
   GROUNDED BRIEF:\n${BRIEF}\n
   Produce: (a) specChanges — for Spec.CellMechanics add lawTicksFrameMonotone + lawDetentTriadCoincident (draft the Haskell, in terms of the real types the spec-map lens found; if a FrameIndex type is needed, draft it), wire into Properties.CellMechanics + any golden/codegen; (b) swiftChanges — the N×M footprint API on CellActionButton (cells not points), reuse/extend the existing CellSlider for the M×11 threshold slider, wire the slider's value into ReviewPhaseField.motionCoreSet (override medianDisplacementThreshold), and flush ONE frame-locked CellTick haptic per crossed cell at the 20fps clock leaf; (c) gateRecipe (cabal build all && cabal test; cabal run spec-codegen + confirm relevant golden; xcodegen generate; xcodebuild build-for-testing); (d) decisions taken with defaults; (e) risks. Keep it conservative + reuse-first (CellSlider already exists — extend, don't replace). Respect: cell-field law (no Text/strokes on the field), compile-check-only for the camera app, no-stubs.`,
  { label: 'synthesize:plan', phase: 'Synthesize', schema: PLAN_SCHEMA }
)
log(`Change-set ready: ${plan?.specChanges?.length ?? 0} spec edits, ${plan?.swiftChanges?.length ?? 0} Swift edits. Implementing in an isolated worktree.`)

// ── Phase 3: IMPLEMENT — apply + gate, in an isolated worktree (uncommitted) ─
phase('Implement')
const IMPL_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['applied', 'buildOk', 'testsOk', 'iosBuildOk', 'goldenUnchangedOrExpected', 'gateOutput', 'diffSummary', 'issues'],
  properties: {
    applied: { type: 'boolean', description: 'were all planned edits applied' },
    buildOk: { type: 'boolean' },
    testsOk: { type: 'boolean' },
    iosBuildOk: { type: 'boolean' },
    goldenUnchangedOrExpected: { type: 'boolean', description: 'any golden change was expected + explained' },
    gateOutput: { type: 'string', description: 'the tail of cabal test + xcodebuild results (test counts, BUILD SUCCEEDED/FAILED)' },
    diffSummary: { type: 'string', description: 'git diff --stat + a per-file note of what changed' },
    issues: { type: 'string', description: 'anything that did not apply cleanly, was deferred, or needs a human decision' },
  },
}
const impl = await agent(
  `You are the IMPLEMENTER. Work in the MAIN working tree at ${ROOT} on the current branch (cleanup/haskell-bloat). Apply the change-set EXACTLY; draft Haskell law source is provided — paste + adapt it, do not redesign.
   CHANGE-SET (JSON):\n${JSON.stringify(plan, null, 2)}\n
   Rules:
   - Apply spec edits first; \`cd spec && cabal build all && cabal test\` must stay green (report the test count). If a new law fails, FIX the law/source until green — that is the point of spec-first.
   - If any Codegen changed: \`cabal run spec-codegen\` and check \`git diff\` on the affected SixFour/Generated/*.swift — a golden change must be EXPECTED + explained, never silent.
   - Then the Swift: the N×M footprint API + the CellSlider-based threshold slider + the ReviewPhaseField wiring + the frame-locked haptic flush. \`cd ${ROOT} && xcodegen generate && xcodebuild build-for-testing -scheme SixFour -destination 'platform=iOS Simulator,name=iPhone 17 Pro'\` must end in TEST BUILD SUCCEEDED (camera app = compile-check only; never run).
   - DO NOT git commit and DO NOT git restore/checkout — leave every change in the working tree exactly as built so the main loop can review the real diff and commit. (If a step cannot be made green, leave the partial work in place and report it; do not revert.)
   - Report exact gate results (test counts, BUILD line), \`git -C ${ROOT} diff --stat\`, and any issue.
   Be honest: if something cannot be made green, report buildOk/testsOk/iosBuildOk=false with the error — do not claim success.`,
  { label: 'implement:apply+gate', phase: 'Implement', schema: IMPL_SCHEMA }
)

// ── Phase 4: REVIEW — adversarial check of the implemented diff ──────────────
phase('Review')
const REVIEW_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['soundness', 'lawsHonest', 'cellFieldLawOk', 'frameLockOk', 'problems', 'verdict'],
  properties: {
    soundness: { type: 'string', description: 'does the implementation actually do what the target asked' },
    lawsHonest: { type: 'boolean', description: 'do lawTicksFrameMonotone/lawDetentTriadCoincident genuinely constrain, not vacuously pass' },
    cellFieldLawOk: { type: 'boolean', description: 'no Text/strokes/SF-Symbols on the cell field; widget authored in cells' },
    frameLockOk: { type: 'boolean', description: 'haptic+pulse+repaint genuinely share the 20fps frame index (not async per-touch)' },
    problems: { type: 'array', items: { type: 'string' } },
    verdict: { type: 'string', enum: ['ship', 'fix-then-ship', 'rework'] },
  },
}
const review = await agent(
  `You are an ADVERSARIAL reviewer. The implementation is UNCOMMITTED in the main tree — READ THE REAL DIFF: \`git -C ${ROOT} diff\` (and \`git -C ${ROOT} status\`), plus the changed source files directly. Do not trust the implementer's self-report; verify against the actual code. Working dir: ${ROOT}.
   CHANGE-SET:\n${JSON.stringify(plan, null, 2)}\n
   IMPLEMENTER SELF-REPORT (verify, don't trust):\n${JSON.stringify(impl, null, 2)}\n
   Check HARD against the actual diff: (1) Are the two new laws non-vacuous — read the predicates in Spec.CellMechanics + Properties.CellMechanics; do they actually forbid a bad state (a tick in the wrong frame, a haptic without its repaint), or trivially hold? (2) Cell-field-law: read the slider source — authored in cells (M×11, knob=1 lit cell), NO Text/stroke/SF-Symbol on the field? (3) Frame-lock: read the haptic flush site — is it genuinely in the same CADisplayLink/20fps callback as the repaint, or an async per-touch UIImpactFeedbackGenerator call that only LOOKS frame-locked? (4) \`git diff SixFour/Generated/\` — did any golden change, and is it explained? (5) Is the N×M footprint API a real cell count or a renamed point literal? List concrete problems (with file:line) and a verdict.`,
  { label: 'review:adversarial', phase: 'Review', schema: REVIEW_SCHEMA }
)

return {
  target: TARGET,
  planSummary: plan?.summary,
  implemented: { build: impl?.buildOk, tests: impl?.testsOk, ios: impl?.iosBuildOk, diff: impl?.diffSummary, issues: impl?.issues },
  review,
  note: 'Implemented in an isolated worktree, UNCOMMITTED. Review the verdict before merging into cleanup/haskell-bloat.',
}
