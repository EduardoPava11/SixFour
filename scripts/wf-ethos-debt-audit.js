export const meta = {
  name: 'sixfour-ethos-debt-audit',
  description: 'Extract SixFour ethos, audit code against it, adversarially verify each debt finding against current state, synthesize a reconciled cleanup plan',
  phases: [
    { title: 'Ethos', detail: 'parallel readers extract each ethos pillar + its checkable invariants' },
    { title: 'Audit', detail: 'per pillar, grep code/docs for violations of that pillar\'s invariants' },
    { title: 'Verify', detail: 'adversarially verify each finding against the 2026-06-05 current state (skeptical)' },
    { title: 'Synthesize', detail: 'reconcile into a prioritized cleanup ledger, mechanical-safe vs judgment-required' },
  ],
}

// Current-state facts every agent must reason against. Last turn's Explore established these.
const NOW = [
  "Today is 2026-06-05.",
  "Glass was RETIRED app-wide TODAY (total pixelation won). Every Glass* component is now a flat cell-button; GlassControls.swift has no .glassEffect.",
  "GlassOverContent.swift is a now-DEAD component (its L1 glass layer no longer exists).",
  "Spec.Display.hs is UNBUILT (T1-T9 planned, not written).",
  "CONTRADICTION: SIXFOUR-DISPLAY-FSM.md's refined Law #2 still sanctions a glass layer (encode∘glass=encode), but SIXFOUR-DESIGN-LANGUAGE.md says glass is retired everywhere. The docs disagree.",
  "Law #1 = ONE ATOM: gifPx = 6pt. Widgets grow by using MORE cells, never a bigger atom. 'Dual pitch' (an element with its own point size) is the classic violation.",
  "The ContestedCellGridView contested-cell resolution (clean / effect-zone shimmer / loud magenta sentinel, NEVER blend) is PROVEN-GOOD (lawNoSynthesis) and is NOT debt.",
].join(" ")

const ROOT = (args && args.repoRoot) || "/Users/daniel/SixFour"

// The ethos pillars: each is a canonical doc/subsystem that asserts part of the app's soul.
const PILLARS = [
  { key: 'design-language', source: 'docs/SIXFOUR-DESIGN-LANGUAGE.md',
    focus: 'GRID as canonical UI language; Law #1 (one atom = gifPx); Law #2 (no glass on content); total pixelation.' },
  { key: 'vision', source: 'docs/SIXFOUR-VISION.md',
    focus: 'one cube projected honestly; NN proposes, SEARCH generates options, user picks, spec proves each projection.' },
  { key: 'spec-methodology', source: 'docs/SIXFOUR-SPEC-METHODOLOGY.md',
    focus: 'Haskell-as-spec depth ladder; escalate only on pager-on-fire invariants; golden vectors; codegen-pinned contracts.' },
  { key: 'architecture-boundary', source: 'docs/SIXFOUR-ARCHITECTURE-MAP.md',
    focus: 'Swift/Zig/Metal/Haskell boundary rule; Zig = byte-exact integer source of truth; caller-owns-memory C-ABI; determinism + SHA-256.' },
  { key: 'display-fsm', source: 'docs/SIXFOUR-DISPLAY-FSM.md',
    focus: 'display = FSM; single 20fps clock; three projections cannot drift; every cell is I/O at 20fps; T1-T9 theorems; kill cellPt.' },
  { key: 'representation-unification', source: 'docs/SIXFOUR-REPRESENTATION-UNIFICATION.md',
    focus: 'one (x,y,t) index cube projected to 2D + palette factor; single source of truth; no parallel reconstruction paths.' },
]

const ETHOS_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['pillar', 'canonicalSource', 'assertions', 'invariants'],
  properties: {
    pillar: { type: 'string' },
    canonicalSource: { type: 'string' },
    assertions: { type: 'array', items: { type: 'string' }, description: 'core principles this pillar asserts' },
    invariants: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['id', 'statement', 'howToCheck'],
        properties: {
          id: { type: 'string' },
          statement: { type: 'string', description: 'a concrete, checkable property the code/docs must satisfy' },
          howToCheck: { type: 'string', description: 'grep/inspection recipe to detect a violation' },
        },
      },
    },
  },
}

const FINDINGS_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['findings', 'truncated'],
  properties: {
    truncated: { type: 'boolean', description: 'true if more findings existed than were reported' },
    findings: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['id', 'pillar', 'invariantViolated', 'location', 'evidence', 'proposedFix', 'severity', 'confidence'],
        properties: {
          id: { type: 'string' },
          pillar: { type: 'string' },
          invariantViolated: { type: 'string' },
          location: { type: 'string', description: 'file:line (relative to repo root)' },
          evidence: { type: 'string', description: 'quoted code/doc proving the violation' },
          proposedFix: { type: 'string' },
          severity: { type: 'string', enum: ['critical', 'high', 'medium', 'low'] },
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
        },
      },
    },
  },
}

const VERDICT_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['id', 'isReal', 'status', 'reason', 'correctedSeverity', 'fixClass'],
  properties: {
    id: { type: 'string' },
    isReal: { type: 'boolean', description: 'true only if this is a LIVE debt against current state' },
    status: { type: 'string', enum: ['live', 'moot', 'already-fixed', 'stale-doc', 'false-positive'] },
    reason: { type: 'string' },
    correctedSeverity: { type: 'string', enum: ['critical', 'high', 'medium', 'low', 'none'] },
    fixClass: { type: 'string', enum: ['mechanical-safe', 'judgment-required', 'spec-work', 'none'] },
  },
}

phase('Ethos')
log(`Auditing SixFour at ${ROOT} across ${PILLARS.length} ethos pillars`)

// Phase 1 -> 2 pipeline: each pillar's invariants are extracted, then its code is audited.
// No barrier between extract and audit per pillar — a pillar starts auditing as soon as its
// ethos is distilled, while other pillars are still reading.
const auditResults = await pipeline(
  PILLARS,
  // Stage 1: distill the ethos pillar into checkable invariants
  (p) => agent(
    `You are reading the SixFour iOS app to distill its ETHOS. ${NOW}\n\n` +
    `Read ${ROOT}/${p.source} (and skim closely-related docs it references). ` +
    `Pillar focus: ${p.focus}\n\n` +
    `Extract: (a) the core ASSERTIONS/principles this pillar makes about how the app must be built, and ` +
    `(b) for each, a concrete CHECKABLE INVARIANT about the code or docs, with a grep/inspection recipe to detect a violation. ` +
    `Be specific to SixFour (cite token names, law numbers, theorem ids, file conventions). Return structured data only.`,
    { label: `ethos:${p.key}`, phase: 'Ethos', schema: ETHOS_SCHEMA, agentType: 'Explore' }
  ),
  // Stage 2: audit the codebase for violations of THIS pillar's invariants
  (ethos, p) => agent(
    `You are auditing the SixFour codebase for TECHNICAL DEBT — violations of one ethos pillar's invariants. ${NOW}\n\n` +
    `Repo root: ${ROOT}\n` +
    `Pillar: ${p.key} (canonical: ${p.source})\n` +
    `Invariants to check:\n${JSON.stringify(ethos.invariants, null, 2)}\n\n` +
    `Search Swift (SixFour/ incl. Kernels/), Haskell (spec/), and docs/ for concrete violations. ` +
    `Also cross-reference ${ROOT}/docs/TECH-DEBT-LEDGER.md and ${ROOT}/NOTES.md for already-logged debt under this pillar. ` +
    `For each violation give file:line evidence (quote it), a proposed fix, severity, and your confidence. ` +
    `CRITICAL: many old glass-related ledger entries may now be MOOT (glass retired today) — still surface them, but you may mark low confidence. ` +
    `Report the highest-value findings; if you cap the list, set truncated=true. Return structured data only.`,
    { label: `audit:${p.key}`, phase: 'Audit', schema: FINDINGS_SCHEMA, agentType: 'Explore' }
  )
)

// Barrier is now correct: dedup across ALL pillars' findings before the expensive verify fan-out.
const raw = auditResults.filter(Boolean).flatMap((r) => (r.findings || []).map((f) => ({ ...f, _pillar: f.pillar })))
const seen = new Set()
const deduped = []
for (const f of raw) {
  const k = `${f.location}::${f.invariantViolated}`.toLowerCase()
  if (seen.has(k)) continue
  seen.add(k)
  deduped.push(f)
}
const truncatedAny = auditResults.filter(Boolean).some((r) => r.truncated)
log(`Collected ${raw.length} findings -> ${deduped.length} after dedup${truncatedAny ? ' (some audits truncated their lists)' : ''}. Verifying each adversarially.`)

// Phase 3: adversarial verification — skeptic opens the cited file and rules on current-state reality.
phase('Verify')
const verdicts = await parallel(deduped.map((f) => () =>
  agent(
    `You are an ADVERSARIAL verifier ruling on a claimed technical-debt finding in SixFour. Default to skeptical. ${NOW}\n\n` +
    `Repo root: ${ROOT}\nClaimed finding:\n${JSON.stringify(f, null, 2)}\n\n` +
    `OPEN the cited file at the cited location and inspect the surrounding code/doc. Then rule: is this a LIVE debt right now, ` +
    `or is it moot (made irrelevant by total pixelation / a retired feature), already-fixed, a stale-doc contradiction, or a false-positive? ` +
    `Give the corrected severity (or 'none' if not real) and classify the fix as mechanical-safe (unambiguous, low-risk edit), ` +
    `judgment-required (needs a design call), spec-work (needs Haskell/codegen), or none. Return structured data only.`,
    { label: `verify:${(f.location || f.id).slice(0, 40)}`, phase: 'Verify', schema: VERDICT_SCHEMA, agentType: 'Explore' }
  ).then((v) => ({ finding: f, verdict: v }))
))

const ruled = verdicts.filter(Boolean)
const live = ruled.filter((r) => r.verdict.isReal)
const dismissed = ruled.filter((r) => !r.verdict.isReal)
log(`Verified: ${live.length} LIVE debts, ${dismissed.length} dismissed (moot/stale/already-fixed/false-positive).`)

// Phase 4: synthesize the reconciled, prioritized cleanup ledger.
phase('Synthesize')
const synthesisMd = await agent(
  `You are the lead engineer synthesizing a RECONCILED TECHNICAL-DEBT CLEANUP PLAN for the SixFour app. ${NOW}\n\n` +
  `Below are the VERIFIED-LIVE debt findings (each already adversarially confirmed against current state), ` +
  `and the DISMISSED ones (kept for the record so the team knows they were checked and why they're not debt).\n\n` +
  `LIVE:\n${JSON.stringify(live.map((r) => ({ ...r.finding, verdict: r.verdict })), null, 2)}\n\n` +
  `DISMISSED:\n${JSON.stringify(dismissed.map((r) => ({ id: r.finding.id, location: r.finding.location, status: r.verdict.status, reason: r.verdict.reason })), null, 2)}\n\n` +
  `Produce a clear Markdown document titled "SixFour — Ethos & Technical-Debt Reconciliation". Structure it: ` +
  `(1) a short ETHOS RESTATEMENT (the app's soul in ~6 bullets, drawn from the pillars); ` +
  `(2) the LIVE debt grouped by ethos pillar, each item with location, the invariant it violates, the exact fix, severity, and fixClass; ` +
  `(3) a PRIORITIZED EXECUTION ORDER separating 'mechanical-safe' (can batch-apply) from 'judgment-required' (needs a design call) from 'spec-work' (Haskell); ` +
  `(4) a DISMISSED appendix (one line each: what was checked, why it's not debt). ` +
  `Be concrete and cite file:line. Output ONLY the Markdown document body.`,
  { label: 'synthesize:reconciliation', phase: 'Synthesize' }
)

return {
  counts: { raw: raw.length, deduped: deduped.length, live: live.length, dismissed: dismissed.length, truncatedAny },
  live: live.map((r) => ({ ...r.finding, verdict: r.verdict })),
  dismissed: dismissed.map((r) => ({ id: r.finding.id, location: r.finding.location, status: r.verdict.status, reason: r.verdict.reason })),
  reconciliationMarkdown: synthesisMd,
}
