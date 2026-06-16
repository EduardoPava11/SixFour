export const meta = {
  name: 'holistic-form-follows-function',
  description: 'DESIGN-ONLY: web-search "form follows function" UI/UX, ground it against SixFour\'s FORM (the tight cell grid) and FUNCTION (GIF sizes + the search+modification of the colour palette), and synthesize ONE holistic, decluttered, act-by-act design where the cell-grid form is DERIVED from the function. Writes a design doc. No code.',
  whenToUse: 'When the UI has accumulated co-equal controls and needs a holistic re-derivation from first principles (form = the established design language; function = what the app actually does), grounded in real prior art.',
  phases: [
    { title: 'Ground', detail: 'web prior-art (form-follows-function + search/modify UX) + FORM cartographer (cell grid) + FUNCTION cartographer (GIF sizes + palette search/modify)' },
    { title: 'Design', detail: 'synthesize one holistic design: the cell-grid form derived from the GIF + palette-search/modify function, as a clear act-by-act flow' },
    { title: 'Review', detail: 'adversarial: is the form genuinely FOLLOWING function (no ornament)? is it clearer (one act at a time, clear completion)? does it honour the cell grid?' },
  ],
}

const ROOT = '/Users/daniel/SixFour'
const SPEC = `${ROOT}/spec`

// ── Phase 1: GROUND ─────────────────────────────────────────────────────────
phase('Ground')
const lenses = [
  {
    label: 'ground:web-form-function',
    prompt: `You are the WEB PRIOR-ART researcher on "FORM FOLLOWS FUNCTION" applied to UI/UX. Use WebSearch/WebFetch (load via ToolSearch with select:WebSearch,WebFetch if needed). End with sources (URLs).
    Research, with concrete citable findings:
    1. The PRINCIPLE: Louis Sullivan's "form follows function" + its modern UI/UX interpretation (Dieter Rams' principles, Bauhaus functionalism, content-first / function-first design). What does it concretely PRESCRIBE for an interface — how is form DERIVED from function rather than decorated onto it?
    2. DECLUTTER / sequence patterns: progressive disclosure, wizards / stepped flows, "one primary action per screen", modal-vs-flat tool exposure, the cost of co-equal toolbars. How do well-regarded designs make a multi-step task read as act → act with a clear "what completes this step"?
    3. SEARCH + MODIFY interfaces (the app's core function): faceted / parametric search UX, slider/lens-based exploration of a structured space, and COLOUR PALETTE editor / generator UX (how pro tools let you explore a palette's structure at multiple granularities AND modify it without a wall of controls).
    Return 8-12 load-bearing, citable facts grouped by (principle / sequence-declutter / search-modify), each usable to DERIVE a UI from function. Flag any anti-patterns to avoid.`,
  },
  {
    label: 'ground:form-cartographer',
    prompt: `You are the FORM cartographer. Working dir: ${ROOT}. The established FORM is the TIGHT CELL GRID. Read and report its rules precisely:
    - docs/SIXFOUR-CELL-WIDGET-LANGUAGE.md (the N×M cell-widget language + the widget REGISTRY + the frame-locked detent), SixFour/UI/GlobalLattice.swift (the 4pt atom + cell-count constants), docs/SIXFOUR-ACTS-AND-WIDGETS.md (the Act×Widget matrix).
    - The cell-field / total-pixelation law (whole screen = one data-coloured cell field; cells only, no Text/glass/SF-Symbol on the field; CellActionButton/CellSlider/CellSprite/CellSelector primitives).
    Report: the atom (4pt), the canonical footprints (touch floor 11², shutter 16², hero 64², slider M×11), the placement rules (View.place / movable / disjoint), and the HARD constraints any new design MUST obey. This is the vocabulary the holistic design must be built FROM.`,
  },
  {
    label: 'ground:function-cartographer',
    prompt: `You are the FUNCTION cartographer. Working dir: ${ROOT}. The FUNCTION has two parts the user named: (A) the GIF SIZES, and (B) the "search + modification of the colour palette". Read and report:
    - GIF sizes: the output rungs 16³/64³/256³ (LadderExport.Rung), the 64×64 frame / 64³ cube, the palette radixes 16²/4⁴/2⁸ (PaletteBranching depth 2/4/8). What each size MEANS functionally (preview vs hero vs export; per-frame vs quartet vs Haar).
    - Palette SEARCH: how the user EXPLORES the palette's structure — the 16²/4⁴/2⁸ radix tree, the collapse depth (SplitTree.collapse), the cut lever, the motion/core split (QuartetDelta), the group-pick (GroupRGBT). Which of these is "navigating/searching the palette space" vs a fixed view.
    - Palette MODIFICATION: how the user CHANGES the palette — collapse to a depth, recolour by look (LookTransfer), pick groups, pick-four anchors, the leaf override. Which ops MODIFY the exported palette vs only preview.
    - The acts/lifecycle (Live→Capture→Browse→Render→Review) and the current Review CLUTTER (the 7-button action row: Share/Save/LUT/Motion/Cut/Retake/Atlas/Groups) — read SixFour/UI/Surface/ReviewPhaseField.swift.
    Report the FUNCTION as two clean axes (SEARCH the palette / MODIFY the palette) + the GIF-size outputs + the act flow, with each control mapped to search-vs-modify. This is WHAT the form must follow.`,
  },
]
const grounding = await parallel(lenses.map(l => () => agent(l.prompt, { label: l.label, phase: 'Ground' }))).then(r => r.filter(Boolean))
const BRIEF = `WEB PRIOR-ART (form-follows-function):\n${grounding[0] ?? ''}\n\nFORM (the cell grid):\n${grounding[1] ?? ''}\n\nFUNCTION (GIF sizes + palette search/modify):\n${grounding[2] ?? ''}`
log('Form + function + prior-art grounded; synthesizing the holistic design.')

// ── Phase 2: DESIGN ─────────────────────────────────────────────────────────
phase('Design')
const DESIGN_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['thesis', 'searchAxis', 'modifyAxis', 'actFlow', 'reviewReshape', 'formMapping', 'whatGoesAway', 'decisions'],
  properties: {
    thesis: { type: 'string', description: 'the one-sentence form-follows-function thesis: how the cell grid expresses GIF + palette-search/modify' },
    searchAxis: { type: 'string', description: 'how SEARCHING the palette (16²/4⁴/2⁸ radix, collapse depth) is expressed as ONE coherent grid control (not scattered toggles)' },
    modifyAxis: { type: 'string', description: 'how MODIFYING the palette (collapse/motion/groups/look/picks) is expressed, derived from function' },
    actFlow: { type: 'string', description: 'the act-by-act flow with EACH act\'s completion criterion (the single forward action) — Live→Capture→Browse→Render→Review' },
    reviewReshape: { type: 'string', description: 'concretely how Review goes from the 7-button pile to a clear form-follows-function layout (GIF + ship/refine, refine = the search/modify axes one step at a time)' },
    formMapping: { type: 'string', description: 'which cell-grid primitives (CellSlider/CellSelector/CellSprite/CellActionButton, footprints) express which function — form derived from function, in N×M cells' },
    whatGoesAway: { type: 'string', description: 'which current controls merge / collapse / disappear, and WHY (function says they are the same axis)' },
    decisions: { type: 'array', items: { type: 'string' }, description: 'open design decisions for the user' },
  },
}
const design = await agent(
  `You are the HOLISTIC DESIGNER. Working dir: ${ROOT}. Synthesize ONE design where the cell-grid FORM is DERIVED FROM the FUNCTION (GIF sizes + the search+modification of the colour palette). The goal: declutter Review (today a 7-button pile) into a clear act-by-act flow where each step says how it completes — by making the form follow the two functional axes (SEARCH the palette / MODIFY the palette), not by rearranging buttons.
   GROUNDED BRIEF:\n${BRIEF}\n
   Produce: the thesis; the SEARCH axis as one coherent grid control (the 16²/4⁴/2⁸ radix + collapse depth is ONE search of the palette space, not separate Motion/Cut toggles); the MODIFY axis; the act flow with per-act completion criteria; the concrete Review reshape (GIF + ship/refine, refine walks the search→modify axes one at a time); the form→function mapping in real cell primitives + N×M footprints; what current controls MERGE or disappear and why; open decisions. Be ruthless about "form follows function" — if a control exists for no function, cut it; if two controls serve one function, merge them. Honour the cell-field law + the completion-criterion principle. DESIGN ONLY — implement nothing.`,
  { label: 'design:holistic', phase: 'Design', schema: DESIGN_SCHEMA }
)

// ── Phase 3: REVIEW (adversarial) ───────────────────────────────────────────
phase('Review')
const review = await agent(
  `You are an ADVERSARIAL design reviewer. Working dir: ${ROOT}. Attack this "form follows function" holistic design.
   DESIGN:\n${JSON.stringify(design, null, 2)}\n
   Check HARD: (1) Does the form genuinely FOLLOW function, or did it just rename the button pile / add a new abstraction (a "lens") that is ornament? Name any control that survives without a function. (2) Is it actually CLEARER — can a first-time user read it as act → act with an obvious "what completes this step", or is the search/modify split itself confusing? (3) Does it honour the cell-field law + the real cell primitives/footprints (not invent un-cell-able UI)? (4) Does merging controls LOSE any real capability (e.g. Groups ≠ Cut ≠ Motion functionally)? (5) Is the Review reshape implementable against the actual ReviewPhaseField, or hand-wavy? List concrete problems + a verdict (sound / needs-rework / over-simplified).`,
  { label: 'review:adversarial', phase: 'Review', schema: {
      type: 'object', additionalProperties: false,
      required: ['formFollowsFunction', 'clearer', 'cellLawOk', 'losesNoCapability', 'verdict', 'problems'],
      properties: {
        formFollowsFunction: { type: 'boolean' }, clearer: { type: 'boolean' },
        cellLawOk: { type: 'boolean' }, losesNoCapability: { type: 'boolean' },
        verdict: { type: 'string', enum: ['sound', 'needs-rework', 'over-simplified'] },
        problems: { type: 'array', items: { type: 'string' } },
      } } }
)

// ── Write the holistic design doc ───────────────────────────────────────────
phase('Design')
const doc = await agent(
  `Write ${ROOT}/docs/SIXFOUR-HOLISTIC-FORM-FUNCTION.md — the holistic form-follows-function design for SixFour's UI/UX.
   DESIGN:\n${JSON.stringify(design, null, 2)}\n
   ADVERSARIAL REVIEW:\n${JSON.stringify(review, null, 2)}\n
   Sections: ## Thesis (form follows function, one line), ## Prior art (the form-follows-function principle + the search/modify + sequence patterns, with citations from the web lens), ## The function (GIF sizes + the two axes: SEARCH the palette / MODIFY the palette), ## The form (the cell grid vocabulary it's built from), ## The holistic design (act-by-act flow + per-act completion + the Review reshape, with the form→function mapping in cell primitives), ## What merges / goes away (and why function says so), ## Adversarial review + resolutions, ## Open decisions, ## First implementation slice. Keep the cell-field law + completion-criterion principle central. End with an executive summary. This workflow implemented NOTHING.`,
  { label: 'design:doc', phase: 'Design' }
)
return { doc: 'docs/SIXFOUR-HOLISTIC-FORM-FUNCTION.md', thesis: design?.thesis, verdict: review?.verdict, summary: doc }
