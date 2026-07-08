export const meta = {
  name: 'cut-export-contract',
  description: 'DESIGN-ONLY workflow: scope extending the byte-exact GIFB genome contract (BranchedPalette.projectQ16, owned 3× Haskell≡Swift≡Zig) so the 2⁸ cut depth threads into export. Grounds the contract, designs the extension, drafts the Haskell spec, adversarially checks byte-exactness preservation. Writes a design doc + feasibility verdict. Mutates NO byte-exact code.',
  whenToUse: 'Before touching a byte-exact, golden-pinned, multi-language contract — produce a verified design + feasibility verdict first, so implementation is a separate, greenlit step.',
  phases: [
    { title: 'Ground', detail: 'byte-exact-contract cartographer + export/cut Swift-seam + prior-art on hierarchical/sub-256 palette quantization' },
    { title: 'Design', detail: 'design the contract extension preserving byte-exactness; draft the Haskell spec + Zig/golden plan' },
    { title: 'Review', detail: 'adversarial: does it preserve the b16/b4/b2 goldens? is the 256-leaf requirement actually removable? blast radius?' },
  ],
}

const ROOT = '/Users/daniel/SixFour'
const SPEC = `${ROOT}/spec`

// ── Phase 1: GROUND ─────────────────────────────────────────────────────────
phase('Ground')
const lenses = [
  {
    label: 'ground:byte-exact-contract',
    prompt: `You are the BYTE-EXACT CONTRACT cartographer. Working dir: ${SPEC} (and ${ROOT}). The spec is a browsable map (CLAUDE.md).
    TARGET: scope extending the GIFB global-palette genome so an arbitrary CUT DEPTH (palette-story 2⁸, 0…8 Haar levels, or equivalently a sub-256 colour count) can drive the EXPORT, not just the 3 fixed branching presets (b16/b4/b2).
    1. Regenerate + read the spec map: \`bash ${SPEC}/scripts/spec-docs.sh 2>&1 | tail -20\`; read src/SixFour/Spec/Map.hs categories for the collapse/genome modules.
    2. Map the byte-exact genome contract END TO END across all three owners:
       - Haskell: Spec.Collapse (globalCollapseQ16 / farthestPointSeedsQ16), Spec.Quad4 / Spec.SigmaPairFixed / Spec.PairTreeFixed (the b4/b2 genomes), and any Codegen that emits their goldens.
       - Swift: SixFour/Palette/BranchedPalette.swift (projectQ16), PaletteCollapse.swift (FarthestPointCollapse), SplitTree.swift.
       - Swift kernels: SixFour/Kernels/*.swift — the s4_* kernels for collapse/genome/haar (grep s4_global_collapse, s4_haar, s4_quantize, projectQ16 equivalents).
       - Goldens: SixFour/Generated/{CollapseGolden,GenomeGolden,GenomeFixedGolden,PairTreeGolden}.swift and the Zig fixture tests that pin them.
    3. Pin down the CORE QUESTION: WHY does projectQ16 (b4/b2) require exactly 256 leaves? Is the 256-leaf structure intrinsic to the genome (Quad4 = 4⁴ = 256, σ-pair = 2⁸ = 256), or could the genome be evaluated at a shallower depth (fewer leaves)? Quote the code that assumes 256.
    Return a precise contract map: the 3-owner surface for the genome, the exact files/functions/goldens that would change, and a crisp answer to whether sub-256 / arbitrary-depth is INTRINSICALLY blocked or merely unimplemented.`,
  },
  {
    label: 'ground:export-cut-seam',
    prompt: `You are the EXPORT / CUT Swift-seam tracer. Working dir: ${ROOT}.
    Read: SixFour/Encoder/LadderExport.swift (makeURL — the export entry; flatGlobalLeaves), SixFour/Encoder/LadderGIF.swift (encodeGlobalGIF, globalRemap), SixFour/Palette/BranchedPalette.swift (projectQ16), and the CUT tool in SixFour/UI/Surface/ReviewPhaseField.swift (cutDepth/cutGlobal/recomputeCutGlobal/openCutLever — currently PREVIEW-ONLY via SplitTree.descendants, which DIVERGES from the export's maximin→projectQ16 path).
    Determine: (a) exactly where a cut-depth (or color-count k) parameter would thread into makeURL → the collapse → projectQ16; (b) the discrepancy between the cut preview's algorithm (SplitTree median-sort) and the export's (maximin + projectQ16) — what would it take to make preview ≡ export at a given cut; (c) which Rungs (16³/64³/256³) are affected; (d) whether a color-count cut (maximin to k<256) is cleanly in-contract for b16 (flat identity) even if b4/b2 need the genome.
    Return the Swift-side change surface + the preview≡export reconciliation options, with file:line.`,
  },
  {
    label: 'ground:priorart',
    prompt: `You are the PRIOR-ART researcher. Use WebSearch/WebFetch (load via ToolSearch if needed).
    Research how palette/color quantizers expose a CONTINUOUS or MULTI-LEVEL "how many colors / how deep" control while keeping a HIERARCHICAL structure: wavelet-packet / Haar palette pyramids, octree color quantization depth pruning, median-cut depth, and (key) any technique for evaluating a fixed-depth color tree at a SHALLOWER depth to yield fewer colors without rebuilding. Also: GIF global color table sizes < 256 (2^n tables) and their encoder support.
    Return 5-8 load-bearing facts with URLs that inform whether "collapse a 256-leaf genome to 2^k colors" is a standard, sound operation (and how others keep it deterministic/exact).`,
  },
]
const grounding = await parallel(lenses.map(l => () => agent(l.prompt, { label: l.label, phase: 'Ground' }))).then(r => r.filter(Boolean))
const BRIEF = `CONTRACT MAP:\n${grounding[0] ?? ''}\n\nEXPORT/CUT SEAM:\n${grounding[1] ?? ''}\n\nPRIOR ART:\n${grounding[2] ?? ''}`
log('Contract grounded; designing the extension (design-only, no code mutation).')

// ── Phase 2: DESIGN ─────────────────────────────────────────────────────────
phase('Design')
const DESIGN_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['feasibility', 'approach', 'haskellDraft', 'zigPlan', 'goldenPlan', 'swiftPlan', 'byteExactRisk', 'blastRadius', 'recommendation'],
  properties: {
    feasibility: { type: 'string', enum: ['in-contract', 'needs-extension', 'blocked'], description: 'is the cut→export achievable, and at what cost' },
    approach: { type: 'string', description: 'the chosen design: cut as color-count k (maximin to 2^level) vs depth-pruned genome, and why' },
    haskellDraft: { type: 'string', description: 'the actual drafted Spec.* change (function signatures / law sketches) to extend the contract' },
    zigPlan: { type: 'string', description: 'which s4_* kernels change and how, to stay byte-exact with Haskell' },
    goldenPlan: { type: 'string', description: 'which goldens change/get added; how the existing b16/b4/b2 goldens stay green' },
    swiftPlan: { type: 'string', description: 'BranchedPalette/makeURL/cut-tool changes to consume the extended contract + make preview ≡ export' },
    byteExactRisk: { type: 'string', description: 'the specific places byte-exactness could break across Haskell≡Swift≡Zig' },
    blastRadius: { type: 'string' },
    recommendation: { type: 'string', description: 'do it / defer / do a smaller in-contract subset (e.g. b16-only color-count) — with the rationale' },
  },
}
const design = await agent(
  `You are the CONTRACT DESIGNER. Working dir: ${ROOT}. Design (DO NOT implement) the extension that lets the 2⁸ cut depth drive EXPORT, preserving the byte-exact GIFB genome contract (Haskell≡Swift≡Zig, golden-pinned).
   GROUNDED BRIEF:\n${BRIEF}\n
   Decide the cleanest approach (likely: cut depth → color-count k = 2^(level), maximin to k, then the genome evaluated at the matching depth; or a b16-only in-contract subset if b4/b2 are intrinsically 256). Draft the Haskell spec change, the Zig kernel plan, the golden plan (existing b16/b4/b2 MUST stay byte-identical), the Swift consumption + the preview≡export reconciliation, the byte-exact risk points, and a clear recommendation (do it / defer / smaller subset). Be honest if it is not worth it.`,
  { label: 'design:contract', phase: 'Design', schema: DESIGN_SCHEMA }
)

// ── Phase 3: REVIEW (adversarial, byte-exactness) ───────────────────────────
phase('Review')
const review = await agent(
  `You are an ADVERSARIAL reviewer of a DESIGN for extending a byte-exact, golden-pinned, 3-language contract. Working dir: ${ROOT}. You may read any code to verify.
   DESIGN:\n${JSON.stringify(design, null, 2)}\n
   Attack it HARD: (1) Does the design ACTUALLY keep the existing b16/b4/b2 goldens byte-identical, or would the refactor perturb them? Read the goldens + projectQ16 to check. (2) Is the "256-leaf requirement" claim in the design correct — is sub-256 genome evaluation mathematically sound (Quad4=4⁴, σ-pair=2⁸ are intrinsically 256-leaf), or is the design hand-waving? (3) Where EXACTLY could Haskell≡Swift≡Zig diverge under the new code path (rounding, summation order, Q16 truncation)? (4) Is the recommendation honest about cost vs value? Return the concrete failure modes and a verdict (sound / needs-rework / not-worth-it). Be skeptical; default to "the byte-exact contract is fragile, prove the design preserves it."`,
  { label: 'review:byte-exact', phase: 'Review', schema: {
      type: 'object', additionalProperties: false,
      required: ['goldensPreserved', 'mathSound', 'divergenceRisks', 'verdict', 'problems'],
      properties: {
        goldensPreserved: { type: 'boolean' },
        mathSound: { type: 'boolean' },
        divergenceRisks: { type: 'array', items: { type: 'string' } },
        verdict: { type: 'string', enum: ['sound', 'needs-rework', 'not-worth-it'] },
        problems: { type: 'array', items: { type: 'string' } },
      } } }
)

// ── Write the design doc ────────────────────────────────────────────────────
phase('Design')
const doc = await agent(
  `Write ${ROOT}/docs/SIXFOUR-CUT-EXPORT-CONTRACT.md — the design + feasibility verdict for threading the 2⁸ cut into export by extending the byte-exact GIFB genome contract.
   DESIGN:\n${JSON.stringify(design, null, 2)}\n
   ADVERSARIAL REVIEW:\n${JSON.stringify(review, null, 2)}\n
   Sections: ## Verdict (feasibility + the reviewer's verdict, up top), ## The byte-exact contract today (3-owner map), ## Why the cut doesn't thread today (the 256-leaf / preview-vs-export gap), ## Proposed extension (approach + drafted Haskell + Zig/golden/Swift plan), ## Byte-exactness preservation (how b16/b4/b2 stay green + the divergence risks), ## Recommendation (do it / defer / smaller subset, with cost). End with an executive summary. This doc is the greenlight artifact — be precise and honest; this workflow implemented NOTHING.`,
  { label: 'design:doc', phase: 'Design' }
)
return { doc: 'docs/SIXFOUR-CUT-EXPORT-CONTRACT.md', feasibility: design?.feasibility, verdict: review?.verdict, recommendation: design?.recommendation, summary: doc }
