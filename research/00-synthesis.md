# 00 — Synthesis: One Append-Only Graph

*How the four research briefs compose into a single design thread for SixFour's transferable-gene system.*

**Thesis.** The four topics the user asked for — transferable genes with genealogy, expressiveness, distributed-biological models, and the swap-economy — are not four systems. They are **four folds over one object**: a content-addressed, append-only, monotone log of events. Genealogy is a fold that yields a provenance DAG. Governance is a fold that yields reputation and council decisions. Coherence is the algebraic fact that the log is a CRDT. Selection is what happens when that log is read as a population of alleles. Expressiveness is the only concern that lives *inside* the gene rather than *over the log* — and even it is disciplined by the same content-address that makes the log work. This synthesis names the shared spine, the reinforcing couplings between briefs, the one genuine tension, and a staged build order.

Read the briefs for depth: [[01-transferable-genes-genealogy]] · [[02-gene-expressiveness]] · [[03-distributed-biological-models]] · [[04-swap-economy-governance]].

---

## 1. The shared spine: everything is a fold over a content-addressed append-only log

SixFour already committed to the load-bearing decision before any of this research: a gene is `hash(canonical bytes)`, and `Spec.Trade` is an append-only ledger whose holdings are monotone. Each brief, independently, discovered that this one decision is what makes its topic tractable:

- **[03] Distributed biology** found the tightest fit in the whole review: an append-only, grant-only, holdings-only-grow ledger **is a Grow-Only-Set CRDT**. By Shapiro et al. (2011), a monotone join-semilattice earns **Strong Eventual Consistency** — any two devices that have seen the same trades agree, regardless of gossip order — and that is *provable in Haskell* as ordinary algebraic laws. Convergence is not a hope to be engineered; it is a theorem the existing design already earns.
- **[01] Genealogy** found that a **Merkle-DAG is a logical clock** (Sanjuán et al. 2020): because a gene's hash commits to its parents' hashes, "derived-after" is encoded structurally, with no vector-clock bookkeeping. Lineage computed as a fold over an append-only derivation log converges under concurrent creation for the *same* reason the trade ledger does.
- **[04] Governance** found that reputation (`demand`, `reliability`), council decisions (majority judgment), and schism are all **pure folds** over the ledger — and that the money-free, grant semantics *dissolve* the classical exchange impossibilities (TTC, Myerson–Satterthwaite, VCG) because there is nothing rivalrous to allocate.
- **[02] Expressiveness** is the outlier — it lives inside the gene — but it is governed by the same content-address: a gene's identity is the hash of its canonical Q16 bytes, so any expressiveness upgrade (a richer generator, a gene algebra) must produce **byte-exact** output or it changes the gene's identity. The bijective octree guarantees nothing is representationally unreachable; the golden gate guarantees nothing is unverifiable.

**The unifying claim:** SixFour should not build a provenance system *and* a governance system *and* a replication system. It should build **one append-only event log** (with two event kinds — trades and derivations — over one content-addressed gene space) and then express genealogy, reputation, convergence, and selection as **distinct folds** over it. This is already the project's native idiom ("governance as folds of a trade ledger"); the research says that idiom generalizes to all four concerns.

---

## 2. The reinforcing couplings (where the briefs need each other)

The four topics are inter-related exactly where the user suspected. The couplings are not thematic hand-waving — they are specific, and each is a design obligation.

### 2.1 Genealogy ⨯ Governance — *creators must be rewarded up the DAG*
[04] identifies the incentive gap: in a gift economy the creator's return is reputation for generosity (`demand`), but a naive `demand` count rewards only *direct* takes — so the author of a foundational gene that everyone *derives from* goes unpaid. The fix requires [01]'s provenance DAG: **propagate `demand` along genealogy**, awarding a discounted share up the ancestry when a descendant is taken up. This is incentive-compatible precisely because ancestry is content-addressed and unforgeable ([01] D1) — you cannot claim to be upstream of a popular gene without having actually produced its verifiable ancestor. The propagation must be **concave with genealogical distance** ([04], per the "Concave is the New Linear" impossibility) so a single genesis gene doesn't become a reputation monopoly.

### 2.2 Governance ⨯ Distributed biology — *reputation is an eigenvector, which is a gossip computation*
[04] recommends making `demand` a **flow anchored in a pre-trusted seed set** (EigenTrust) rather than a self-referential count, to kill collusion rings. But an eigenvector is a global fixed point, and [03] supplies the decentralized machinery to compute it without a coordinator: **Push-Sum / gossip aggregation** computes network-wide averages in O(log N) rounds, and power iteration is a fold over iteration count. The open question both briefs raise — "can eigenvector reputation be a *pure fold* under the append-only contract?" — is the single most important governance research task, and it sits exactly at the [03]/[04] seam.

### 2.3 Distributed biology ⨯ Genealogy — *genes are alleles; guilds are demes; the DAG is the pedigree*
[03] reads the network as population genetics: genes are alleles, guilds are Wright/island demes, inter-guild trades are gene flow, and schism-at-150 is deme fission. [01]'s genealogy DAG *is the pedigree* of that population — the record of which allele descended from which. Evolutionary graph theory ([03]) then predicts which guild topologies **amplify** good genes vs. drift; and the provenance DAG is what lets you measure, after the fact, whether amplification actually happened (did widely-derived genes originate in amplifier guilds?). Selection and genealogy are the forward and backward views of the same flow.

### 2.4 Expressiveness ⨯ everything — *a gene worth tracking, trading, and selecting must first be worth having*
[02] is upstream of the other three: genealogy, governance, and selection are only interesting if genes are **expressive enough** to differ meaningfully and **evolvable enough** to recombine. Two couplings are concrete:
- **Gene algebra ↔ genealogy.** [02]'s byte-exact blend/graft/crossover operators each produce a *new* gene with *new* parents — i.e. every composition is a first-class derivation event in [01]'s DAG. The briefs jointly raise the **blend-explosion** worry: if every experimental blend is recorded, the DAG explodes. The resolution is shared: only genes that are *kept or traded* become derivation events (a governance/[04] threshold gates a genealogy/[01] write).
- **Neutrality ↔ selection.** [02]'s most elegant finding is that the octree bijection, which seems to *forbid* neutrality, actually lets you *define* neutrality exactly (two genes are neutral-equivalent iff their synthesized palettes are byte-identical). [03]'s population genetics says neutrality is the fuel of evolvability — a large neutral set makes a gene a robust trade good that survives recombination. So the verifiability constraint that looked like a cost becomes the mechanism that makes the swap economy's population evolvable.

---

## 3. The one genuine tension: expressiveness vs. verifiability

Three of the four concerns are *reinforced* by the content-addressed-log spine — they get convergence, unforgeable lineage, and dissolved impossibilities essentially for free. Only **[02] expressiveness** is in genuine tension with the rest, and it is the tension the project has always lived with: **the field's most compressive encodings (CPPN/HyperNEAT, GRNs, L-systems) buy their power by being opaque developmental simulations, which the golden gate forbids.**

The research resolves this without compromise. [02]'s verdict:
- Keep the **bijective octree as the substrate** (the "frozen reversible lift stays the tokenizer" architecture the project already committed to).
- Push expressiveness up through the **generator layer**, where a **feed-forward, hand-writable CPPN-style generator** — inputs are the existing 6-axis `(L,a,b,x,y,t)` alphabet, coefficients are the σ-pairs — is the *one* developmental encoding compatible with byte-exact verification. L-systems and GRNs are ruled out.
- Decide "is 384 DOF enough?" by an **MDL codelength sweep** on real captures, not by assertion.
- Get a **closed gene algebra** by doing all composition in the Q16 generator domain, then synthesizing once — never in float leaf space.

So the tension does not require choosing between expressive and verifiable. It requires locating expressiveness in the *generator coefficients* (free to be rich) rather than the *genotype→phenotype map* (which must stay a fixed, inspectable, golden-gated function).

---

## 4. What is provable vs. what is bounded vs. what is heuristic

A cross-cutting result the SixFour ethos demands: the research separates cleanly into three verification tiers.

| Tier | Claims | Source briefs |
|---|---|---|
| **Fully Haskell-provable** (QuickCheck/algebraic laws, golden vectors) | Ledger forms a join-semilattice ⇒ Strong Eventual Consistency; genealogy DAG is acyclic + ancestor-closure is monotone; council-7 / schism-150 are monotone stable threshold predicates; octree round-trip `synthesize ∘ distill = id`; gene-algebra operators are byte-exact; neutral-equivalence is a decidable relation | [03] §4.5, [01] D3, [02] §4.3–4.4, [04] §4f |
| **Bounded / specify-and-simulate** (probabilistic guarantees, encode preconditions) | Epidemic convergence time; Push-Sum error; evolutionary-graph fixation probabilities; EigenTrust convergence tolerance; MDL intrinsic-dimension estimate | [03] §4.5, [04] Q1, [02] §4.1 |
| **Design-stance / heuristic** (keep outside the verified core) | Stigmergic reinforcement/evaporation for "hot gene" surfacing; Turing-style guild differentiation; migration-rate tuning; where to sit on the concave/linear frontier | [03] §4.3–4.4, [04] Q2 |

The discipline: let the **provable tier carry the safety guarantees** (the ledger converges no matter what the heuristics do), and let the heuristic tier be freely tunable *because* the provable layer contains it. This is the same containment the project already uses with the Zig Q16 floor.

---

## 5. Staged build order (a recommendation, not a mandate)

The couplings imply a dependency order. Nothing here is committed work — it is the sequence the research implies if the user pursues the design.

1. **Content-address the ancestry ([01] D1).** Extend the gene's canonical bytes with `parents[]` + `derivation`. This is the keystone: it makes lineage immutable and unlocks 2.1's creator rewards, 2.3's pedigree, and 2.4's gene-algebra provenance. Small, local, high-leverage.
2. **Prove the ledger is a CRDT ([03] §4.5).** Exhibit the join-semilattice laws for `Spec.Trade`. This certifies convergence *before* building any propagation, and it is pure spec work in the existing golden-law style.
3. **Add the derivation event kind + provenance fold ([01] D3).** A second append-only log (or event variant) folded into a `GeneGraph`. Now genealogy queries are pure folds with QuickCheck laws.
4. **Make reputation a seed-anchored flow ([04] §4c + [03] Push-Sum).** Replace self-referential `demand` counts with an EigenTrust-style eigenvector, computed by gossip aggregation, propagated concavely up the genealogy DAG. This is the hardest and most valuable governance change; it depends on 1–3.
5. **Gossip propagation stack ([03] §4.1).** Demers rumor-mongering + anti-entropy backstop + Plumtree cross-guild + SWIM membership, scoped by guild. The CRDT proof from step 2 is what makes redundant anti-entropy safe.
6. **Expressiveness track, in parallel ([02] §4).** Run the MDL sweep to size the genome; prototype a hand-written CPPN-style generator against golden vectors; define the byte-exact gene algebra and the neutral-equivalence relation. Independent of 1–5 except that gene-algebra outputs feed step 3's derivation log.

Steps 1–3 are the spine. Step 4 is the research frontier (the eigenvector-as-fold open question). Steps 5–6 are parallelizable once the spine exists.

---

## 6. The one-sentence version

**Build one content-addressed append-only event log; fold it four ways — into a Merkle-DAG pedigree (genealogy), a monotone semilattice (convergence), a seed-anchored reputation eigenvector propagated up that pedigree (governance), and an island-model allele population (selection) — while keeping the gene itself as expressive as a feed-forward generator can be under a byte-exact golden gate.**

---

*Index:* [[README]] · *Briefs:* [[01-transferable-genes-genealogy]] · [[02-gene-expressiveness]] · [[03-distributed-biological-models]] · [[04-swap-economy-governance]]
