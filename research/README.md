# SixFour — Research Index

PhD-level literature reviews + design briefs commissioned to inform the **transferable-gene** direction: genes that carry verifiable genealogy back to their creator, are expressive enough to matter, propagate through a distributed biological substrate, and change hands in a money-free swap-economy.

Every brief is grounded in the actual spec (`Spec.Trade`, `Spec.GuildScale`, `Spec.GeneTaxonomy`, `Spec.OctreeGenome`, …), cites only sources that were actually fetched or verified during research, and ends with **concrete, dependency-free, Haskell-verifiable design recommendations**. Browse this index first — like `SixFour.Spec.Map` for the spec.

## Start here

- **[00 — Synthesis: One Append-Only Graph](00-synthesis.md)** — the connecting thread. Argues the four topics are four *folds over one content-addressed append-only log*; names the couplings, the single expressiveness-vs-verifiability tension, the provable/bounded/heuristic tiers, and a staged build order. **Read this to see how the pieces compose.**

## The four briefs

### ★ [01 — Transferable Genes + Verifiable Genealogy](01-transferable-genes-genealogy.md)
The central gap: genes are content-addressed, but lineage-to-creator lives in a mutable tag, not the ledger. Surveys Merkle DAGs (Git/IPFS-IPLD), W3C PROV, C2PA content credentials, vector clocks & **Merkle-CRDTs** (a Merkle-DAG *is* a logical clock), Nix/Guix reproducible derivations, and Keybase sigchains. **Recommends:** commit ancestry into the gene's content hash (`parents[]` + `derivation`), model records on a minimal PROV quad, compute lineage as a second append-only fold beside `Spec.Trade`, bind creators with a hand-written Ed25519 sigchain in the GIF89a block.

### [02 — Expressiveness of the Gene / Genome](02-gene-expressiveness.md)
How much a 384-DOF σ-pair generator over a bijective octree can *express*. Surveys program-representation GP (CGP/GE/PushGP), indirect/developmental encodings (CPPN/HyperNEAT/L-systems/GRNs), the genotype–phenotype map, neutrality & evolvability, hypernetworks & steerable latent directions, and invertibility/MDL theory. **Recommends:** size the genome by an MDL codelength sweep (not assertion); a hand-writable feed-forward **CPPN-style generator** is the one developmental encoding compatible with the golden gate; a byte-exact **gene algebra** (blend/graft/crossover) done in the Q16 generator domain; turn the bijection's zero-neutrality into an *exactly checkable* neutral-equivalence relation to fuel the swap economy.

### [03 — Distributed Systems Modeled on Biology](03-distributed-biological-models.md)
How genes propagate device-to-device and guilds self-organize as demes. Surveys epidemic/gossip protocols (Demers, Push-Sum, SWIM, Plumtree), population protocols, population genetics & **evolutionary graph theory** (amplifiers/suppressors of selection), stigmergy/ACO, amorphous/morphogenetic computing & quorum sensing, and CRDT convergence. **Key result:** `Spec.Trade` is *already a Grow-Only-Set CRDT*, so it earns Strong Eventual Consistency provably in Haskell, with gossip anti-entropy as the homeostatic convergence mechanism; guilds map onto Wright/island demes with schism-as-fission.

### [04 — Non-Monetary Swap-Economy & Governance](04-swap-economy-governance.md)
Fair, incentive-compatible, money-free exchange + guild governance. Surveys mechanism design without money (Shapley–Scarf TTC, Gale–Shapley), gift & commons economies (Mauss, Ostrom's 8 principles), reputation & sybil resistance (EigenTrust, SybilLimit), social choice (Moulin median, Balinski–Laraki majority judgment, quadratic voting), Bradley–Terry preference learning, and DAO governance (incl. the 2026 "Concave is the New Linear" impossibility). **Key argument:** grant (non-rivalrous) semantics *dissolve* the classical allocation impossibilities but *sharpen* the reputation/sybil problem — so make `demand` a seed-anchored EigenTrust flow (not a self-count), use applicant-proposing deferred-acceptance for scarce council/guild seats, and ground the odd-7 council + majority judgment in Moulin's unique-strategyproof-median result.

## Cross-cutting takeaways

- **One object, four folds.** Content-addressed append-only log → Merkle-DAG pedigree (genealogy) · monotone semilattice (convergence) · reputation eigenvector up that pedigree (governance) · island-model allele population (selection). See [00](00-synthesis.md).
- **The design already earned convergence.** The monotone-grant ledger is a CRDT; Strong Eventual Consistency is a theorem, not an engineering task ([03]).
- **Genealogy unlocks creator rewards.** Propagate `demand` concavely up the provenance DAG so foundational-gene authors are paid ([01]⨯[04]).
- **Verifiability defines neutrality.** The octree bijection lets neutral-equivalence be *decided byte-exactly*, which is what makes the trading population evolvable ([02]⨯[03]).
- **Three verification tiers.** Provable (CRDT/DAG/threshold laws) · bounded (epidemic/eigenvector convergence — specify + simulate) · heuristic (stigmergy/tuning — keep outside the verified core). See [00 §4](00-synthesis.md).

## Provenance of this research

Four parallel research agents, each doing live web search + source fetching with adversarial citation discipline (only fetched/verified sources cited; unreadable PDFs flagged and cross-checked against venue summaries). Grounded in a prior codebase map of the gene/swap/genealogy architecture. Commissioned 2026-07-02.
