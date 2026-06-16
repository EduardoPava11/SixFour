export const meta = {
  name: 'act-decisions',
  description: 'Implement the FIRST SLICE of the layered spec (docs/SIXFOUR-LAYERED-ACTS-AND-SCREEN-MAP.md): extend Spec.Display with the decision events, land Spec.ActDecisions (Act→few Decisions→Surface→one Completion) with the keystone maxDecisionsPerAct=3 law + 8 laws + codegen to ActDecisionsContract.swift, so a control past the cap is UNREPRESENTABLE. Cap=3, Browse=real Display phase. Implements uncommitted + adversarially reviews the laws for VACUITY.',
  whenToUse: 'Building a gate-enforced cardinality law where vacuous laws are the risk — the adversarial phase must prove each law actually constrains.',
  phases: [
    { title: 'Ground', detail: 'read the drafted ActDecisions + the branch Display alphabet (Browsing phase + events) + the codegen/Swift-mirror pattern' },
    { title: 'Synthesize', detail: 'the exact change-set: Display event extension + Spec.ActDecisions + 8 laws + codegen + Surface.swift mirror' },
    { title: 'Implement', detail: 'apply, gate (cabal test: Display laws + ActDecisions laws green; spec-codegen; iOS build-for-testing); leave UNCOMMITTED' },
    { title: 'Review', detail: 'adversarial: is EVERY law non-vacuous (a 4th decision MUST fail lawDecisionBudget)? Display still total? cap genuinely enforced? parity holds?' },
  ],
}

const ROOT = '/Users/daniel/SixFour'
const SPEC = `${ROOT}/spec`
const DECISIONS = `cap = 3 (maxDecisionsPerAct); Browse = a REAL Display phase (Browsing already exists on this branch).`

// ── Ground ──────────────────────────────────────────────────────────────────
phase('Ground')
const lenses = [
  {
    label: 'ground:spec',
    prompt: `You are grounding the ActDecisions spec build. Working dir: ${SPEC}. Decisions: ${DECISIONS}
    1. Read docs/SIXFOUR-LAYERED-ACTS-AND-SCREEN-MAP.md — the DRAFTED \`Spec.ActDecisions\` module (the Act/Surface/Target/Decision algebra, decisionsFor, the 8 laws, goldenDecisionTable) and the "First implementation slice" section. This draft is the spec to build (adapt to the real Display alphabet).
    2. Read spec/src/SixFour/Spec/Display.hs: the Phase + Event data decls, allEvents/allPhases, step, eventName/phaseName, the golden happy-path trace, and the FSM laws (lawPhaseTotal, lawNoOrphanPhase, lawPhaseIsCellGrid, lawReviewExplicit). Confirm Browsing phase + SelectFrame/Picked4 exist.
    3. Reconcile the decision table's events with the real alphabet: which of {LookSwipe, ScrubTick, CutLever, ExportLut, OpenSettings, ShutterTap, Retake, Committed, SelectFrame, Picked4} EXIST vs must be ADDED. The new ones (LookSwipe/ScrubTick/CutLever/ExportLut) are DECISION-LEVEL affordances that mutate Σ, NOT the phase — so they get NO new step transition (default no-op), keeping totality. pick-four = SelectFrame, Browse commit = Picked4.
    4. Read a codegen exemplar (spec/src/SixFour/Codegen/Swift.hs emitting a contract + Surface.swift's assertSpecParity / event-token mirror) so the ActDecisionsContract.swift emit + the Display-event mirror follow the established pattern.
    Return: the exact events to add, the adapted decisionsFor (each act ≤3, real events), and the codegen + Swift-mirror touch points (file:line).`,
  },
]
const grounding = await parallel(lenses.map(l => () => agent(l.prompt, { label: l.label, phase: 'Ground' }))).then(r => r.filter(Boolean))
const BRIEF = grounding[0] ?? ''
log('Grounded; synthesizing the ActDecisions change-set.')

// ── Synthesize ──────────────────────────────────────────────────────────────
phase('Synthesize')
const PLAN_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['summary', 'specChanges', 'codegenChanges', 'swiftChanges', 'vacuityNotes', 'gateRecipe', 'risks'],
  properties: {
    summary: { type: 'string' },
    specChanges: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['file', 'change'],
      properties: { file: { type: 'string' }, change: { type: 'string' }, draftSource: { type: 'string', description: 'ready-to-paste Haskell (the ActDecisions module + the Display event additions + the 8 laws)' } } } },
    codegenChanges: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['file', 'change'], properties: { file: { type: 'string' }, change: { type: 'string' } } } },
    swiftChanges: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['file', 'change'], properties: { file: { type: 'string' }, change: { type: 'string' }, anchor: { type: 'string' } } } },
    vacuityNotes: { type: 'string', description: 'for EACH of the 8 laws, why it is non-vacuous — what input would FALSIFY it (esp. lawDecisionBudget: a 4th decision row must fail). If a law is structurally tautological, say so and strengthen it.' },
    gateRecipe: { type: 'string' },
    risks: { type: 'string' },
  },
}
const plan = await agent(
  `You are the SYNTHESIZER. Working dir: ${ROOT}. Produce the implementation-ready change-set for the ActDecisions first slice. Decisions: ${DECISIONS}
   GROUNDED BRIEF:\n${BRIEF}\n
   Produce: specChanges (the Display event additions — LookSwipe/ScrubTick/CutLever/ExportLut + eventName + allEvents, NO new step transitions; the full Spec.ActDecisions module with each act ≤3 real-event decisions; Properties.ActDecisions with the 8 laws; spec.cabal wiring); codegenChanges (emit Generated/ActDecisionsContract.swift via Codegen.Swift + app/Spec.hs + Map.hs); swiftChanges (Surface.swift mirror for the 4 new Display event tokens so assertSpecParity holds — NO UI router yet, that is the next slice); vacuityNotes (CRITICAL: for each law, what falsifies it — make lawDecisionBudget genuinely fail on a 4th row, don't let any law be tautological); gateRecipe; risks. Conservative, spec-first. The Swift UI router is DEFERRED — this slice lands the spec + the cap law + the codegen contract only.`,
  { label: 'synthesize:plan', phase: 'Synthesize', schema: PLAN_SCHEMA }
)
log(`Change-set: ${plan?.specChanges?.length ?? 0} spec edits. Implementing.`)

// ── Implement ───────────────────────────────────────────────────────────────
phase('Implement')
const IMPL_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['applied', 'buildOk', 'testsOk', 'capEnforced', 'iosBuildOk', 'parityOk', 'gateOutput', 'diffSummary', 'issues'],
  properties: {
    applied: { type: 'boolean' }, buildOk: { type: 'boolean' }, testsOk: { type: 'boolean' },
    capEnforced: { type: 'boolean', description: 'VERIFIED by temporarily adding a 4th decision to one act → lawDecisionBudget FAILS cabal test → then reverted. Report the observed failure.' },
    iosBuildOk: { type: 'boolean' }, parityOk: { type: 'boolean' },
    gateOutput: { type: 'string' }, diffSummary: { type: 'string' }, issues: { type: 'string' },
  },
}
const impl = await agent(
  `You are the IMPLEMENTER. Work in the MAIN tree at ${ROOT} on the current branch (feat/act3-browsing). Apply the change-set EXACTLY; drafted Haskell is provided — paste + adapt.
   CHANGE-SET:\n${JSON.stringify(plan, null, 2)}\n
   Rules:
   - Spec FIRST: extend Display.Event (4 new events, no new step cases), land Spec.ActDecisions + Properties.ActDecisions, wire spec.cabal. \`cd spec && cabal build all && cabal test\` green; Display's existing laws (totality/reachability/golden) MUST stay green with the larger alphabet.
   - PROVE THE CAP IS REAL: temporarily add a 4th decision to decisionsFor Review → \`cabal test\` must FAIL on lawDecisionBudget → REVERT it → green again. Report the observed failure text (this is capEnforced).
   - Codegen: emit Generated/ActDecisionsContract.swift; \`cabal run spec-codegen\`; the spec-codegen drift gate must accept it (it is a NEW contract). Mirror the 4 new Display events in Surface.swift so assertSpecParity holds.
   - \`cd ${ROOT} && xcodegen generate && xcodebuild build-for-testing -scheme SixFour -destination 'platform=iOS Simulator,name=iPhone 17 Pro'\` → TEST BUILD SUCCEEDED. (NO UI router this slice.)
   - DO NOT git commit / git restore — leave changes in the tree for review. Report gate results, capEnforced (with the observed failure), git diff --stat, issues.`,
  { label: 'implement:apply+gate', phase: 'Implement', schema: IMPL_SCHEMA }
)

// ── Review ──────────────────────────────────────────────────────────────────
phase('Review')
const review = await agent(
  `You are an ADVERSARIAL reviewer. UNCOMMITTED changes in the main tree — READ THE REAL DIFF (\`git -C ${ROOT} diff\`) + the changed files. Do not trust the self-report.
   CHANGE-SET:\n${JSON.stringify(plan, null, 2)}\n
   IMPLEMENTER SELF-REPORT (verify):\n${JSON.stringify(impl, null, 2)}\n
   Check HARD: (1) Is EVERY one of the 8 laws NON-VACUOUS — read each predicate; does it actually forbid a bad state, or trivially hold? Especially: does lawDecisionBudget genuinely fail on a 4th row (the implementer must have demonstrated it), and is lawNoButtons/lawEventCoversDecisions/lawGestureBacksDrag real or a tautology over an empty/total set? Name any vacuous law. (2) Did extending Display.Event keep lawPhaseTotal/lawNoOrphanPhase/the golden trace green (read the diff to DisplayContract.swift — expected = 4 new event tokens, nothing else perturbed)? (3) Is each act genuinely ≤3 with one completion? (4) Does assertSpecParity still hold (Swift mirror complete)? (5) Did anything beyond the spec+codegen+mirror change (no premature UI)? List concrete problems (file:line) + verdict (ship / fix-then-ship / rework).`,
  { label: 'review:adversarial', phase: 'Review', schema: {
      type: 'object', additionalProperties: false,
      required: ['allLawsNonVacuous', 'capGenuinelyEnforced', 'displayStillTotal', 'parityOk', 'verdict', 'problems'],
      properties: {
        allLawsNonVacuous: { type: 'boolean' }, capGenuinelyEnforced: { type: 'boolean' },
        displayStillTotal: { type: 'boolean' }, parityOk: { type: 'boolean' },
        verdict: { type: 'string', enum: ['ship', 'fix-then-ship', 'rework'] },
        problems: { type: 'array', items: { type: 'string' } },
      } } }
)
return { planSummary: plan?.summary, vacuityNotes: plan?.vacuityNotes,
  implemented: { build: impl?.buildOk, tests: impl?.testsOk, capEnforced: impl?.capEnforced, ios: impl?.iosBuildOk, parity: impl?.parityOk, diff: impl?.diffSummary, issues: impl?.issues },
  review, note: 'UNCOMMITTED on feat/act3-browsing — review the verdict before committing.' }
