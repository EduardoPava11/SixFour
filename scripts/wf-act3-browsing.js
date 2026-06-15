export const meta = {
  name: 'act3-browsing',
  description: 'Implement Act III — the Browse & Pick-Four FSM phase. The missing lifecycle act that lets the user scrub the 64-frame burst and pick 4 anchor frames feeding the 4⁴ quartet. New Surface phase + events + Σ field + BrowsingPhaseField, spec-first (Spec.Display FSM). Implements uncommitted + adversarially reviews.',
  whenToUse: 'Building a new FSM phase + its phase-field, where the state machine is the byte-exact spec source of truth and the new phase must preserve totality/no-orphan laws.',
  phases: [
    { title: 'Ground', detail: 'FSM spec-map (Spec.Display + Surface) + UI-seam (PhaseField routing, scrub/filmstrip widgets) + the Act III design' },
    { title: 'Synthesize', detail: 'draft the FSM additions (phase/events/Σ field) + BrowsingPhaseField change-set, keeping the FSM total' },
    { title: 'Implement', detail: 'apply spec+codegen+Swift, gate (cabal test + spec-codegen + iOS build-for-testing); leave UNCOMMITTED' },
    { title: 'Review', detail: 'adversarial: FSM totality/no-orphan/review-explicit laws hold; the new phase is wired; widgets match the Act III matrix' },
  ],
}

const ROOT = '/Users/daniel/SixFour'
const SPEC = `${ROOT}/spec`

// ── Ground ──────────────────────────────────────────────────────────────────
phase('Ground')
const lenses = [
  {
    label: 'ground:fsm-spec-map',
    prompt: `You are the FSM SPEC-MAP cartographer. Working dir: ${SPEC} (and ${ROOT}). The spec is the byte-exact source of truth for the surface FSM (CLAUDE.md).
    TARGET: add Act III = a new \`browsing\` phase between \`capturing\` and \`rendering\` — the user scrubs the 64-frame burst and PICKS 4 anchor frames (\`picks:[Int]\`, the quad anchors that feed the 4⁴ quartet). Today \`.burstComplete\` wires straight to \`.rendering(.quantize)\`.
    1. Regenerate + read the map: \`bash ${SPEC}/scripts/spec-docs.sh 2>&1 | tail -20\`; read Spec.Map for Display/the FSM.
    2. Read Spec.Display (the phase/event model, the FSM laws — totality, no-orphan, review-explicit; the golden happy-path trace) and how it codegens to SixFour/Generated/DisplayContract.swift.
    3. Read SixFour/UI/Surface/Surface.swift: the SurfacePhase enum, the events, surfaceStep(phase,event) (the Swift mirror), the Σ fields (palettesPerFrame, indexCube, cursor, picks?), and Surface.assertSpecParity.
    Report EXACTLY: where the new \`browsing\` phase + \`selectFrame\`/\`picked4\` events + \`picks:[Int]\` Σ field attach in BOTH the Haskell spec AND the Swift mirror; which FSM laws must be re-proven; whether the edge is capturing→browsing→rendering; and the golden-trace change. Cite file:line.`,
  },
  {
    label: 'ground:ui-seam',
    prompt: `You are the UI-seam tracer for a new phase field. Working dir: ${ROOT}.
    TARGET: a BrowsingPhaseField (does not exist) for Act III. Read SixFour/UI/Surface/PhaseField.swift (the field(for:phase) router), an existing phase field as a template (CapturingPhaseField.swift + ReviewPhaseField.swift), the widget registry (docs/SIXFOUR-CELL-WIDGET-LANGUAGE.md) and the Act III row in docs/SIXFOUR-ACTS-AND-WIDGETS.md.
    Determine the widgets Act III shows (per the matrix): Field64 scrubber, a scrub rail (a CellSlider over the 64 frames — REUSE CellSlider + the frame-locked .cellDetent), a 4-pick filmstrip, Palette16 (inert), DiversityRing (coverage), a continue gate (CellActionButton). Report: where BrowsingPhaseField plugs into the router, what data it reads (surface.indexCube/palettesPerFrame/cursor/picks), how the scrub rail drives surface.cursor, how a tap adds/removes a pick, and how the continue gate fires \`.picked4\` → rendering. Cite file:line + reuse points (cellDetent, CellSprite, the gifaHero pattern).`,
  },
]
const grounding = await parallel(lenses.map(l => () => agent(l.prompt, { label: l.label, phase: 'Ground' }))).then(r => r.filter(Boolean))
const BRIEF = `FSM SPEC-MAP:\n${grounding[0] ?? ''}\n\nUI-SEAM:\n${grounding[1] ?? ''}`
log('FSM + UI grounded; synthesizing the Act III change-set.')

// ── Synthesize ──────────────────────────────────────────────────────────────
phase('Synthesize')
const PLAN_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['summary', 'specChanges', 'swiftChanges', 'fsmLaws', 'gateRecipe', 'decisions', 'risks'],
  properties: {
    summary: { type: 'string' },
    specChanges: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['file', 'change'],
      properties: { file: { type: 'string' }, change: { type: 'string' }, draftSource: { type: 'string', description: 'drafted Haskell for the phase/event/law additions' } } } },
    swiftChanges: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['file', 'change'],
      properties: { file: { type: 'string' }, change: { type: 'string' }, anchor: { type: 'string' } } } },
    fsmLaws: { type: 'string', description: 'how totality / no-orphan / review-explicit stay proven with the new phase + events' },
    gateRecipe: { type: 'string' },
    decisions: { type: 'array', items: { type: 'string' } },
    risks: { type: 'string' },
  },
}
const plan = await agent(
  `You are the SYNTHESIZER. Working dir: ${ROOT}. Merge the grounded lenses into ONE implementation-ready change-set for Act III (the browsing phase), drafting the actual Haskell FSM additions.
   TARGET: new \`browsing\` phase (capturing→browsing→rendering), \`selectFrame Int\`/\`picked4\` events, \`picks:[Int]\` Σ field; a BrowsingPhaseField (Field64 scrubber + scrub-rail CellSlider w/ .cellDetent + 4-pick filmstrip + continue gate). Keep the FSM TOTAL and the laws proven; the golden happy-path trace gains the browsing hop.
   GROUNDED BRIEF:\n${BRIEF}\n
   Produce: specChanges (draft the Spec.Display phase/event/Σ additions + law updates + the codegen to DisplayContract.swift), swiftChanges (Surface.swift mirror + PhaseField router + new BrowsingPhaseField + the capturing→browsing edge + the rendering input = picks), fsmLaws (how totality/no-orphan/review-explicit hold), gateRecipe, decisions (e.g. exactly-4 vs ≤4 picks; default picks; can you skip browsing?), risks. Conservative, reuse-first (CellSlider/.cellDetent/CellSprite/gifaHero). Respect: spec-first (Haskell drives, codegen, Swift mirrors bit-exact via assertSpecParity), cell-field law, compile-check-only.`,
  { label: 'synthesize:plan', phase: 'Synthesize', schema: PLAN_SCHEMA }
)
log(`Change-set: ${plan?.specChanges?.length ?? 0} spec + ${plan?.swiftChanges?.length ?? 0} Swift edits. Implementing.`)

// ── Implement (uncommitted, main tree) ──────────────────────────────────────
phase('Implement')
const IMPL_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['applied', 'buildOk', 'testsOk', 'iosBuildOk', 'parityOk', 'gateOutput', 'diffSummary', 'issues'],
  properties: {
    applied: { type: 'boolean' }, buildOk: { type: 'boolean' }, testsOk: { type: 'boolean' },
    iosBuildOk: { type: 'boolean' },
    parityOk: { type: 'boolean', description: 'Surface.assertSpecParity still holds (Swift FSM ≡ Haskell golden trace)' },
    gateOutput: { type: 'string' }, diffSummary: { type: 'string' }, issues: { type: 'string' },
  },
}
const impl = await agent(
  `You are the IMPLEMENTER. Work in the MAIN working tree at ${ROOT} on the current branch. Apply the change-set EXACTLY; drafted Haskell is provided — paste + adapt, don't redesign.
   CHANGE-SET:\n${JSON.stringify(plan, null, 2)}\n
   Rules:
   - Spec FIRST: add the browsing phase/events/Σ field + law updates to Spec.Display; \`cd spec && cabal build all && cabal test\` green (report count). If a totality/no-orphan law fails, FIX until green — spec-first.
   - \`cabal run spec-codegen\` → DisplayContract.swift regenerates: a golden-trace change here is EXPECTED (the new browsing hop) and must be explained, not silent.
   - Swift: mirror the FSM in Surface.swift (surfaceStep + the new phase/events/picks), add BrowsingPhaseField, wire the PhaseField router + the capturing→browsing→rendering edges, feed picks to rendering. Surface.assertSpecParity (DEBUG) must still pass.
   - \`cd ${ROOT} && xcodegen generate && xcodebuild build-for-testing -scheme SixFour -destination 'platform=iOS Simulator,name=iPhone 17 Pro'\` → TEST BUILD SUCCEEDED. Compile-check only; never run (camera app).
   - DO NOT git commit and DO NOT git restore — leave all changes in the working tree for the main loop to review/commit. Report gate results (test counts, BUILD line, parity), git diff --stat, and any issue.
   Be honest: report false with the error if any gate can't be made green.`,
  { label: 'implement:apply+gate', phase: 'Implement', schema: IMPL_SCHEMA }
)

// ── Review (adversarial) ────────────────────────────────────────────────────
phase('Review')
const review = await agent(
  `You are an ADVERSARIAL reviewer. The implementation is UNCOMMITTED in the main tree — READ THE REAL DIFF (\`git -C ${ROOT} diff\`, \`git -C ${ROOT} status\`) and the changed files. Do not trust the implementer's self-report.
   CHANGE-SET:\n${JSON.stringify(plan, null, 2)}\n
   IMPLEMENTER SELF-REPORT (verify, don't trust):\n${JSON.stringify(impl, null, 2)}\n
   Check HARD against the diff: (1) Is the FSM still TOTAL — read surfaceStep + the Haskell δ: does every (phase,event) resolve, is browsing reachable (no-orphan), is review still entered ONLY via the committed path (review-explicit law intact)? (2) Did DisplayContract.swift's golden trace change, and is the change EXACTLY the browsing hop (not a silent perturbation of other transitions)? (3) Is the capturing→browsing→rendering edge correct, and can the user actually reach rendering with picks? (4) Does BrowsingPhaseField honour the cell-field law + reuse .cellDetent for the scrub rail (not a fresh per-touch haptic — LINT-DETENT)? (5) Is picks:[Int] validated (exactly 4? bounds)? List concrete problems (file:line) + a verdict (ship / fix-then-ship / rework).`,
  { label: 'review:adversarial', phase: 'Review', schema: {
      type: 'object', additionalProperties: false,
      required: ['fsmTotal', 'reviewExplicitIntact', 'goldenChangeExpected', 'cellFieldLawOk', 'detentOk', 'verdict', 'problems'],
      properties: {
        fsmTotal: { type: 'boolean' }, reviewExplicitIntact: { type: 'boolean' },
        goldenChangeExpected: { type: 'boolean' }, cellFieldLawOk: { type: 'boolean' }, detentOk: { type: 'boolean' },
        verdict: { type: 'string', enum: ['ship', 'fix-then-ship', 'rework'] },
        problems: { type: 'array', items: { type: 'string' } },
      } } }
)
return { planSummary: plan?.summary, implemented: { build: impl?.buildOk, tests: impl?.testsOk, ios: impl?.iosBuildOk, parity: impl?.parityOk, diff: impl?.diffSummary, issues: impl?.issues }, review, note: 'UNCOMMITTED in main tree — review the verdict before committing.' }
