# 03 — Distributed Systems Modeled on Biology

*A literature review + design brief for SixFour: how learned "genes" propagate device-to-device, how guilds self-organize as biological demes, and how the whole network stays coherent without central control.*

**Abstract.** SixFour is a peer network of users who trade content-addressed learned parameter blobs ("genes") under a monotone, append-only grant ledger, organized into biologically-scaled social units (Council = 7, Guild cap = 150, geometric Dunbar layers). This review surveys six threads of PhD-level distributed-systems literature that are explicitly biological in their metaphors and mechanisms — epidemic/gossip protocols, population protocols, evolutionary graph theory, stigmergy, amorphous/morphogenetic computing, and CRDT convergence — and maps each to a concrete SixFour concern (dissemination, governance, selection, or coherence), yielding a decentralized-yet-convergent design that is largely amenable to Haskell verification.

Cross-links: [[01-transferable-genes-genealogy]] · [[02-gene-expressiveness]] · [[04-swap-economy-governance]]

---

## 1. Framing for SixFour

SixFour's substrate is already a biological analogy taken almost literally:

- **Genes** are content-addressed learned parameter blobs (e.g. a 384-DOF σ-pair genome). They are *alleles* — heritable units of "phenotype" (a look/palette behavior) that copy between hosts.
- **Users are hosts**; **devices are cells** carrying and expressing genes.
- **Guilds are demes** — semi-isolated subpopulations. The Guild cap of 150 (Dunbar's number) and the "schism split into halves" rule are *deme fission*; the geometric Dunbar layers `[5, 15, 45, 135, …]` are nested population structure.
- **Trades are pairwise interactions.** `Spec.Trade` is an append-only, hybrid-grant ledger: both parties gain access, nobody is stripped, holdings are **monotone** (only grow). This is exactly the algebraic shape that distributed-systems theory uses to guarantee convergence.
- **Governance scalars** (reliability, demand, council membership) must be *computed from the trade history* without a central tallying authority.

The engineering question is therefore not "should this be biological?" — it already is — but **which biological/distributed model rigorously governs each behavior**, so the SixFour ethos ("Haskell-verified, formal laws gate everything") can attach a proof or a bounded guarantee to each one. The four concerns to separate throughout:

1. **Dissemination** — how a gene physically spreads host-to-host (gossip/epidemic).
2. **Governance** — how global scalars emerge from local trades (population protocols; CRDTs).
3. **Selection** — which genes/guild topologies win (population genetics; evolutionary graph theory).
4. **Coherence** — how the network converges to a stable, consistent state without a leader (anti-entropy, CRDT strong eventual consistency, reaction-diffusion homeostasis).

---

## 2. Literature survey by thread

### Thread A — Epidemic / gossip protocols (dissemination + coherence)

The canonical result is **Demers et al. (1987)**, *Epidemic Algorithms for Replicated Database Maintenance*, PODC '87 [1]. Motivated by synchronizing Clearinghouse servers on the Xerox internet, it frames replica consistency in the vocabulary of *epidemiology* (susceptible / infective / removed) and defines the strategies still used today:

- **Direct mail** — sender pushes each update to every known site; unreliable when hosts are down.
- **Anti-entropy** — each site periodically picks a random peer, exchanges full contents, and reconciles differences. Highly reliable (guarantees eventual convergence) but expensive and slow.
- **Rumor mongering** — a fresh update is a "hot rumor"; a site holding it repeatedly picks random peers to infect and *loses interest* (stops spreading) once it meets too many peers who already have it. Fast and cheap, but a small non-zero probability that an update misses some sites.

Their key practical synthesis is the **hybrid**: rumor-monger for speed, backstopped by periodic anti-entropy for the completeness guarantee; and **death certificates** to propagate deletions so a delete is not "resurrected" by a stale replica. Convergence of the simple-epidemic push model follows the logistic curve of epidemiology; anti-entropy converges with probability 1 given fair peer selection [1].

Building on gossip as a *computation* primitive, **Kempe, Dobra & Gehrke (2003)**, *Gossip-Based Computation of Aggregate Information*, FOCS '44 [2], introduce **Push-Sum**: each node maintains a (sum, weight) pair and repeatedly sends half to a random peer; the running ratio converges to the global average. On well-connected (high-expansion) graphs it converges in **O(log N + log(1/ε))** rounds — exponentially fast — using O(N log N) messages. **Jelasity, Montresor & Babaoğlu (2005)**, *Gossip-Based Aggregation in Large Dynamic Networks*, ACM TOCS 23(3):219–252 [3], make this robust to churn: an anti-entropy-style push-pull aggregation protocol that continuously estimates network size, averages, extrema, and variance in dynamic overlays, with restart/epoch handling for joins and leaves.

For **membership and failure detection**, **Das, Gupta & Motivala (2002)**, *SWIM: Scalable Weakly-consistent Infection-style Process Group Membership*, DSN 2002:303–312 [4], detach failure detection (randomized pinging with indirect probes to suppress false positives) from **infection-style dissemination** of membership changes, achieving message load and detection time that stay **constant as the group grows** — a direct fix for the O(N²) blow-up of naïve heartbeating. SWIM is production-hardened (e.g. HashiCorp Serf/Memberlist; Uber's Ringpop).

For **efficient broadcast**, **Leitão, Pereira & Rodrigues (2007)**, *Epidemic Broadcast Trees* (Plumtree), SRDS 2007 [5], resolve the tree-vs-gossip tradeoff: payload flows along a spanning **tree** (low steady-state cost) embedded in a gossip overlay, while the remaining "lazy" gossip links carry only message IDs and are used to *repair the tree* after failures. It keeps tree efficiency with epidemic resilience.

*SixFour mapping.* This thread models **how a σ-genome physically propagates**. Rumor-mongering = "hot new gene" spreads eagerly between paired devices; anti-entropy = a periodic guild-level reconciliation that guarantees no gene is permanently lost; Plumtree = a low-bandwidth propagation tree within a guild with gossip backstop; SWIM = knowing which peers/devices are reachable. Push-Sum/aggregation = computing guild-global scalars (see Threads B and the governance concern).

### Thread B — Population protocols (governance from pairwise interactions)

**Angluin, Aspnes, Diamadi, Fischer & Peralta**, *Computation in Networks of Passively Mobile Finite-State Sensors*, PODC 2004 / *Distributed Computing* 18(4):235–253, 2006 (2020 Dijkstra Prize) [6], asks what a swarm of tiny finite-state agents can compute when the *only* operation is: two agents meet and jointly update their states. Under a **fairness condition**, the population "eventually computes" a predicate if it stabilizes to the right answer. Their results:

- Eventually-computable predicates include Boolean combinations of **threshold-k, parity, majority, and simple modular arithmetic** — precisely the family later characterized as the **semilinear / Presburger-definable** predicates.
- All eventually-computable predicates lie in **NL**; under uniform random pairing (conjugating automata) high-probability computation lands in **P ∩ RL**, and O(1) counters of O(n) capacity can be simulated w.h.p.

The lesson: **globally meaningful predicates emerge from anonymous, memoryless, bilateral encounters** — no coordinator, no addresses, no aggregation tree.

*SixFour mapping.* A SixFour **trade is a pairwise interaction**. Population-protocol theory tells us *which governance facts are computable purely from trades*: "does gene G's holder-count exceed threshold T?" (threshold), "is demand for G in the majority vs. gene H?" (majority), "council quorum reached?" (threshold-7). Because the computable class is exactly the semilinear predicates, SixFour should express governance triggers (promotion to Council, schism, gene "endorsement") as **threshold/majority predicates over trade counts** — those are provably reachable by the local process, whereas arbitrary arithmetic (e.g. multiplicative reputation) is not, and would need explicit aggregation (Thread A's Push-Sum).

### Thread C — Population genetics on structured populations (selection & gene flow)

Two classical layers and one modern one:

**Wright's shifting-balance theory (1931, 1932)** [7] holds that adaptation proceeds fastest when a species is *subdivided into small, partially-isolated demes* exchanging a few migrants. Three phases: (I) drift explores gene combinations within demes; (II) selection fixes good combinations locally; (III) the fittest demes export migrants in proportion to their fitness, spreading superior combinations across the metapopulation. Subdivision lets a population cross an "adaptive valley" that a single panmictic population could not.

**Island / deme models in evolutionary computation** operationalize this. **Whitley, Rana & Heckendorn (1999)**, *The Island Model Genetic Algorithm: On Separability, Population Size and Convergence*, J. Computing & Information Technology [8], subdivide the global population into semi-isolated "islands," each running its own EA, with periodic **migration** of elite/random individuals. This preserves diversity (defers premature convergence) and, for separable problems, can find good solutions faster than one large panmictic population. Migration parameters — number of islands, island size, migration rate, migration interval, topology, emigration/immigration policy — are the tuning knobs.

**Evolutionary graph theory.** **Lieberman, Hauert & Nowak (2005)**, *Evolutionary dynamics on graphs*, *Nature* 433(7023):312–316, DOI 10.1038/nature03204 [9], place a Moran process on a weighted graph: vertices are individuals, edge weights are reproduction probabilities. The **isothermal theorem** shows that any graph whose weighted in-degree equals out-degree everywhere ("isothermal") has the *same* fixation probability as the well-mixed Moran population — neither helping nor hindering selection. Deviations produce **amplifiers of selection** (structures like the star and the "superstar" that *raise* the fixation probability of advantageous mutants and *lower* that of deleterious ones) and **suppressors** (e.g. certain directed chains that flatten selection toward neutral drift). Topology alone can tune how strongly "fitness" translates into "spread." **Allen, Lippner, Chen, Fotouhi, Momeni, Yau & Nowak (2017)**, *Evolutionary dynamics on any population structure*, *Nature* 544(7649):227–230, DOI 10.1038/nature21723 [10], extend this to *arbitrary* weighted graphs under weak selection, giving a computable condition (in terms of coalescence/random-walk times on the graph) for when selection favors one strategy over another — and showing which structures promote cooperation.

*SixFour mapping.* **Guilds are Wright's demes.** Restricted inter-guild gene flow *is a feature*: it lets different guilds explore different regions of "gene space" (Phase I), fix locally good genes (Phase II), and export winners (Phase III). **Schism-fission** is deme splitting that resets local diversity. Evolutionary graph theory is the sharpest tool here: the **inter-guild trade topology determines whether good genes spread or die**. A star-like topology (a hub guild everyone trades with) is an *amplifier* — good genes fixate readily but so does anything the hub touches; a more homogeneous/isothermal mesh is neutral and drift-dominated. SixFour can *choose* its guild-graph shape to amplify selection for high-quality genes while avoiding hub-driven monoculture.

### Thread D — Stigmergy & swarm intelligence (indirect coordination)

**Grassé (1959)** coined **stigmergy**: coordination via *modification of a shared environment* rather than direct signaling — termites are stimulated to build by the state of the construction itself ("stimulation of workers by the performance they have achieved") [11]. **Dorigo (1991/1992)** turned this into **Ant Colony Optimization (ACO)**: artificial ants deposit and follow *pheromone* on a shared graph; short/good paths accumulate more pheromone (reinforcement) while evaporation forgets stale choices, so the colony converges on good solutions with no central planner. The canonical reference is **Dorigo & Stützle (2004)**, *Ant Colony Optimization*, MIT Press [12]. Preceding empirical work — Deneubourg's and Goss/Aron/Deneubourg/Pasteels' Argentine-ant double-bridge experiments — grounded the pheromone-reinforcement model [12].

*SixFour mapping.* The **trade ledger is a pheromone field**. A gene that is traded often accumulates "trail strength" (holder count, trade frequency); this is a *stigmergic signal* that guides other users toward high-value genes without anyone broadcasting a recommendation. Evaporation ↔ a time-decay on demand so stale genes fade. This is the mechanism behind "which genes are hot" and feeds the population-protocol demand predicates (Thread B).

### Thread E — Amorphous / cellular / morphogenetic computing (structure without blueprint)

**Abelson, Allen, Coore, Hanson, Homsy, Knight, Nagpal, Rauch, Sussman & Weiss (2000)**, *Amorphous Computing*, *Communications of the ACM* 43(5):74–82 [13], asks how to obtain **coherent global behavior from vast numbers of unreliable, identically-programmed, locally-communicating parts with no precise geometry** — explicitly borrowing from cellular cooperation in developing organisms. Programs run the *same* code on every "cell"; global structure (gradients, regions, patterns) emerges from local rules and message diffusion. This is the computing-side sibling of developmental biology.

The biological anchor is **Turing (1952)**, *The Chemical Basis of Morphogenesis*, *Phil. Trans. R. Soc. B* 237(641):37–72 [14]: two diffusing chemicals with local reaction kinetics can spontaneously break a uniform steady state into stable spatial patterns (stripes, spots) — the **reaction-diffusion / diffusion-driven instability** now called *Turing patterns*. Pattern arises from purely local interaction plus differential diffusion; no blueprint is stored anywhere.

**Quorum sensing** is the microbial analog of a distributed vote. **Miller & Bassler (2001)**, *Quorum Sensing in Bacteria*, *Annu. Rev. Microbiol.* 55:165–199 [15], describe how bacteria secrete **autoinducers** whose concentration tracks population density; once a threshold is crossed, the whole population synchronously switches gene expression (bioluminescence, virulence, biofilm). It is a decentralized threshold-triggered collective decision — biology's version of a population-protocol threshold predicate.

*SixFour mapping.* Amorphous computing is the **design stance**: run *identical local rules* on every device/guild, expect global order to emerge, tolerate unreliable members. **Quorum sensing is the schism/promotion trigger**: a guild "senses" its own size via local trade encounters and, at the 150 threshold, collectively triggers fission — no census server needed. Turing/reaction-diffusion is the conceptual model for how *specialization/differentiation* across guilds can arise from uniform starting conditions plus differential "diffusion rates" of genes.

### Thread F — Convergence, consistency & homeostasis (CRDTs ↔ biological equilibrium)

**Shapiro, Preguiça, Baquero & Zawirski (2011)**, *Conflict-Free Replicated Data Types*, SSS 2011, LNCS 6976:386–400 [16], give the algebraic conditions under which replicas converge with **zero coordination** — **Strong Eventual Consistency (SEC)**: replicas that have received the same set of updates are in the same state, regardless of order. Two families:

- **State-based (CvRDT):** replica states form a **join-semilattice**; the *merge* is the least-upper-bound (join), which is **commutative, associative, and idempotent**; and every update is **monotone** — state only moves *up* the partial order, never down. Merges may be lost, duplicated, or reordered without harm.
- **Operation-based (CmRDT):** updates commute, so causal-order delivery suffices.

The monotone-semilattice condition is *exactly* what makes convergence a theorem rather than a hope, and it is the formal cousin of **anti-entropy as homeostasis**: an organism/replica continuously exchanges with neighbors and relaxes toward a stable fixed point.

*SixFour mapping — this is the tightest fit in the entire review.* `Spec.Trade` is **already a CRDT by construction**: it is an *append-only, grant-only (monotone), holdings-only-grow* ledger. "Holdings only grow" = monotonicity in the semilattice order; "hybrid grant, nobody stripped" = the join never removes elements; set-union of grants is commutative/associative/idempotent. Therefore two devices that have seen the same trades **hold identical state regardless of the order** in which gossip delivered those trades — this is precisely a **Grow-Only Set (G-Set) / append-only-log CRDT**, and SixFour gets **Strong Eventual Consistency for free**, provable in Haskell by exhibiting the join-semilattice laws. Anti-entropy (Thread A) is then the *mechanism* that drives every replica to the CRDT's least-upper-bound — homeostasis of the ledger.

---

## 3. Comparative analysis

| SixFour concern | Best-fit model(s) | What it buys | Formal handle |
|---|---|---|---|
| **Gene dissemination (device→device)** | Rumor mongering + anti-entropy [1]; Plumtree [5] | Fast spread, guaranteed completeness, low steady-state cost | Epidemic convergence bounds; tree+gossip resilience |
| **Membership / reachability** | SWIM [4] | Constant-cost failure detection as guilds grow | Bounded detection time, suppressed false positives |
| **Guild-global scalars (size, avg demand)** | Push-Sum [2]; gossip aggregation [3] | O(log N) decentralized averages/counts, churn-robust | Convergence rate O(log N + log 1/ε) |
| **Governance predicates from trades** | Population protocols [6] | Threshold/majority/parity computed by bilateral trades, no coordinator | Semilinear predicates; NL / P∩RL bounds |
| **Which genes win** | Population genetics / island models [7][8]; evolutionary graph theory [9][10] | Diversity + selection; topology tunes fixation | Fixation probability; isothermal theorem; weak-selection condition |
| **Which guild topologies amplify quality** | Evolutionary graph theory [9][10] | Choose amplifier vs. neutral vs. suppressor structure | Amplifier/suppressor classification |
| **"Hot gene" surfacing** | Stigmergy / ACO [11][12] | Indirect, decentralized quality signal via trade trails | Pheromone reinforcement + evaporation dynamics |
| **Size-triggered schism / promotion** | Quorum sensing [15]; population-protocol thresholds [6]; amorphous rules [13] | Local-only threshold decisions (150→fission, 7→council) | Threshold predicate; density-sensing |
| **Ledger coherence w/o leader** | CRDTs / SEC [16]; anti-entropy [1] | Order-independent convergence, provable | Join-semilattice + monotonicity ⇒ SEC |
| **Differentiation across guilds** | Reaction-diffusion / Turing [14]; amorphous [13] | Emergent specialization from uniform rules | Diffusion-driven instability |

**Reading of the table.** Dissemination and coherence are *solved problems* with tight guarantees (Threads A, F) and map onto SixFour almost verbatim. Governance splits cleanly: **threshold/majority facts** are population-protocol-native (Thread B), while **numeric aggregates** need gossip aggregation (Thread A). Selection is where SixFour has the most *design freedom*: it chooses its guild graph, and evolutionary graph theory (Thread C) predicts the consequences. Stigmergy and quorum sensing (Threads D, E) are the "soft" coordination layers that turn raw trade counts into signals and triggers.

---

## 4. Design implications for SixFour (concrete)

### 4.1 Gene propagation protocol (Threads A, F)
Adopt a **Demers hybrid**, scoped by guild:

1. **Rumor-monger within a guild.** When a device acquires a gene, mark it a *hot rumor*; on each pairing (trade or background sync) push it to a random guild peer; lose interest after *k* redundant hits (feedback counter, Demers "blind coin" with p ≈ 1/k). This spreads a new gene through a 150-member guild in O(log 150) ≈ a handful of rounds.
2. **Anti-entropy backstop.** On a slow timer, each device picks a random guild peer and reconciles gene-set differences. Because the gene set is a **G-Set CRDT** (grow-only, content-addressed), reconciliation is a set-union merge and is *idempotent* — safe to run redundantly. This is the completeness guarantee and the homeostasis mechanism.
3. **Plumtree for cross-guild.** Between guilds, embed a lazy broadcast tree over the inter-guild overlay so "released" genes cross demes cheaply, with gossip repair on churn.
4. **SWIM membership** underneath, so a guild knows which of its ~150 members are live without O(N²) heartbeats.

Deletions are *not needed* on the gene set (holdings only grow), which sidesteps Demers' death-certificate complexity entirely — a direct dividend of the monotone-grant design.

### 4.2 Guilds as islands with migration; schism as deme fission (Thread C)
Treat each guild as an **island EA deme**. Inter-guild trades are **migration/gene flow**; the migration *rate* (how permeable guild boundaries are) is the single most important diversity/selection knob. Low migration → guilds explore divergent gene niches (good for exploration); periodic elevated migration → good genes propagate across the metapopulation (Wright Phase III). **Schism at 150 is deme fission**: split into halves, which *resets local diversity* and prevents any one guild from converging to monoculture — the island model's premature-convergence defense, realized socially.

### 4.3 Evolutionary-graph-theory view of guild topology (Threads C)
Model the inter-guild trade network as an evolutionary graph and *choose its shape deliberately*:
- A **star/superstar** guild topology **amplifies selection**: high-quality genes fixate quickly across the network — but so does whatever the hub adopts, risking hub capture. Use sparingly / for curated "seed" guilds.
- An **isothermal (balanced-degree) mesh** is selection-neutral (drift-dominated): maximal diversity, slow to crown winners.
- **Practical target:** a mostly-isothermal mesh with a few weak amplifier hubs, tuned via the Allen et al. (2017) weak-selection condition, so good genes are favored *without* collapsing diversity. This is a knob SixFour can expose and even A/B test.

### 4.4 Population-protocol view of computing reliability/demand from trades (Thread B)
Express governance triggers as **semilinear predicates over the trade ledger**, because those are exactly what pairwise interactions can compute without a coordinator:
- **Council promotion** = a threshold-7 predicate (Miller 7±2) — reachable.
- **Schism** = a threshold-150 predicate — reachable, and doubles as **quorum sensing** (a guild locally senses its own density and fires).
- **Gene endorsement / "reliability"** = a *majority* or *threshold-k* predicate over successful trades — reachable.
- **Numeric aggregates** (average demand, holder count, uptime) that are *not* semilinear should be computed by **Push-Sum / gossip aggregation** (Thread A) rather than pretending a population protocol will produce them. Stigmergic trail strength (Thread D) — trade frequency with evaporation — is the natural "demand" signal feeding these predicates.

### 4.5 Decentralized yet convergent — and how much is Haskell-verifiable
The spine of coherence is: **monotone grant ledger (CRDT) + anti-entropy (homeostasis) ⇒ Strong Eventual Consistency.** What can be *formally verified in the SixFour Haskell spec*:

- **CRDT laws (highest value, fully provable).** Prove `Spec.Trade` forms a **join-semilattice**: merge is commutative, associative, idempotent, and each `applyTrade` is **monotone** in the partial order. This *is* the SEC proof (Shapiro et al.); it certifies "any two devices with the same trades agree, regardless of gossip order." These are ordinary QuickCheck/algebraic laws — squarely in SixFour's existing golden-law style.
- **Threshold/quorum predicates (provable).** Prove council-7 and schism-150 predicates are monotone and *stable* (once true under fair interactions, they stay decidable) — the population-protocol fairness/stabilization argument, expressible as invariants.
- **Bounded, not proven-exact (specify as guarantees, test empirically).** Epidemic convergence time, Push-Sum error bounds, and evolutionary-graph fixation probabilities are *probabilistic* — encode their assumptions (fair peer selection, connectivity) as spec-level preconditions and verify the bounds by simulation, not by a closed proof.
- **Design-stance, not verified (Threads D, E).** Stigmergic reinforcement/evaporation and Turing-style differentiation are tuning heuristics; keep them outside the verified core and let the CRDT layer guarantee that *whatever* they do, the ledger still converges.

The upshot: SixFour can be **decentralized (no central tally, gossip-only) yet provably convergent** because its economy was, perhaps accidentally, already designed as a monotone CRDT — the single most important structural fact in this review.

---

## 5. Open questions

1. **Migration-rate control loop.** Wright's Phase III makes migration fitness-proportional; SixFour has no central fitness authority. Can migration permeability be made a *local* function of stigmergic trail strength, and does that preserve the island model's diversity guarantee?
2. **Amplifier without capture.** Evolutionary graph theory says stars amplify selection but concentrate power. Is there a topology (weighted, dynamic) that amplifies *gene quality* while resisting *hub/governance* capture — and can the anti-capture property be stated as a law?
3. **Predicate expressiveness gap.** Governance needs may exceed semilinear predicates (e.g. ratios, weighted reputation). What is the minimal aggregation layer (Push-Sum epochs?) that extends computability while staying leaderless and CRDT-compatible?
4. **Schism consistency.** When a guild fissions at 150, the ledger must fork/relabel demes without violating monotonicity. Is deme fission expressible as a CRDT operation (a monotone partition), or does it require a coordination point?
5. **Adversarial gossip.** Demers/SWIM assume non-Byzantine peers. What is SixFour's threat model for a device that forges trades or floods hot rumors, and how much of the CRDT guarantee survives it? (Content-addressing helps: forged *genes* are self-verifying; forged *grants* are the risk.)
6. **Convergence-vs-freshness tradeoff.** Anti-entropy period vs. rumor-mongering aggressiveness sets the latency/bandwidth frontier; the biologically "right" homeostatic setpoint for a 150-cell guild is unknown and worth simulating.

---

## 6. References (verified)

1. A. Demers, D. Greene, C. Hauser, W. Irish, J. Larson, S. Shenker, H. Sturgis, D. Swinehart, D. Terry. **Epidemic Algorithms for Replicated Database Maintenance.** *Proc. 6th ACM PODC*, 1987. Verified copy: https://courses.grainger.illinois.edu/cs525/sp2015/Epidemic%20Algorithms.pdf
2. D. Kempe, A. Dobra, J. Gehrke. **Gossip-Based Computation of Aggregate Information.** *Proc. 44th IEEE FOCS*, pp. 482–491, 2003. Author copy: https://david-kempe.com/publications/aggregation.pdf · ACM: https://dl.acm.org/doi/10.5555/946243.946317
3. M. Jelasity, A. Montresor, O. Babaoğlu. **Gossip-Based Aggregation in Large Dynamic Networks.** *ACM Trans. Computer Systems* 23(3):219–252, 2005. https://dl.acm.org/doi/10.1145/1082469.1082470 · PDF: http://www.cs.unibo.it/bison/publications/aggregation-tocs.pdf
4. A. Das, I. Gupta, A. Motivala. **SWIM: Scalable Weakly-consistent Infection-style Process Group Membership Protocol.** *Proc. IEEE DSN*, pp. 303–312, 2002. https://www.cs.cornell.edu/projects/Quicksilver/public_pdfs/SWIM.pdf
5. J. Leitão, J. Pereira, L. Rodrigues. **Epidemic Broadcast Trees (Plumtree).** *Proc. 26th IEEE SRDS*, 2007. https://asc.di.fct.unl.pt/~jleitao/pdf/srds07-leitao.pdf
6. D. Angluin, J. Aspnes, Z. Diamadi, M. J. Fischer, R. Peralta. **Computation in Networks of Passively Mobile Finite-State Sensors.** PODC 2004; *Distributed Computing* 18(4):235–253, 2006 (2020 Dijkstra Prize). https://www.cs.yale.edu/homes/aspnes/papers/passively-mobile-abstract.html
7. S. Wright. **The Shifting Balance Theory of Evolution** (1931 "Evolution in Mendelian Populations"; 1932 6th Int. Congr. Genetics). Overview verified: https://en.wikipedia.org/wiki/Shifting_balance_theory · https://www.nature.com/scitable/topicpage/sewall-wright-and-the-development-of-shifting-30508/
8. D. Whitley, S. Rana, R. B. Heckendorn. **The Island Model Genetic Algorithm: On Separability, Population Size and Convergence.** *J. Computing & Information Technology*, 1999. https://www.researchgate.net/publication/2244494_The_Island_Model_Genetic_Algorithm_On_Separability_Population_Size_and_Convergence
9. E. Lieberman, C. Hauert, M. A. Nowak. **Evolutionary dynamics on graphs.** *Nature* 433(7023):312–316, 2005. DOI 10.1038/nature03204. PMID 15662424. https://pubmed.ncbi.nlm.nih.gov/15662424/ · https://www.nature.com/articles/nature03204
10. B. Allen, G. Lippner, Y.-T. Chen, B. Fotouhi, N. Momeni, S.-T. Yau, M. A. Nowak. **Evolutionary dynamics on any population structure.** *Nature* 544(7649):227–230, 2017. DOI 10.1038/nature21723. https://www.nature.com/articles/nature21723
11. P.-P. Grassé. **Stigmergy** (theory of indirect coordination via environment; termite nest-building), 1959. Overview verified: https://en.wikipedia.org/wiki/Ant_colony_optimization_algorithms (history section)
12. M. Dorigo, T. Stützle. **Ant Colony Optimization.** MIT Press, 2004 (Dorigo's ant system, PhD thesis 1991/1992). https://mitpress.mit.edu/9780262042192/ant-colony-optimization/ · Full text PDF: https://web2.qatar.cmu.edu/~gdicaro/15382/additional/aco-book.pdf
13. H. Abelson, D. Allen, D. Coore, C. Hanson, G. Homsy, T. F. Knight Jr., R. Nagpal, E. Rauch, G. J. Sussman, R. Weiss. **Amorphous Computing.** *Communications of the ACM* 43(5):74–82, 2000. https://dl.acm.org/doi/10.1145/332833.332842
14. A. M. Turing. **The Chemical Basis of Morphogenesis.** *Phil. Trans. R. Soc. B* 237(641):37–72, 1952. Overview verified: https://en.wikipedia.org/wiki/The_Chemical_Basis_of_Morphogenesis · commentary: https://pmc.ncbi.nlm.nih.gov/articles/PMC4360114/
15. M. B. Miller, B. L. Bassler. **Quorum Sensing in Bacteria.** *Annual Review of Microbiology* 55:165–199, 2001. https://www.annualreviews.org/content/journals/10.1146/annurev.micro.55.1.165
16. M. Shapiro, N. Preguiça, C. Baquero, M. Zawirski. **Conflict-Free Replicated Data Types.** *Proc. SSS 2011*, LNCS 6976, pp. 386–400, Springer. https://link.springer.com/chapter/10.1007/978-3-642-24550-3_29 · summary: https://crdt.tech/
17. R. I. M. Dunbar. **Neocortex size as a constraint on group size in primates** (1992) / social brain hypothesis — basis for "Dunbar's number" ≈ 150. Verified: https://en.wikipedia.org/wiki/Dunbar%27s_number · https://pdodds.w3.uvm.edu/files/papers/others/1993/dunbar1993a.pdf

*All URLs above were fetched or returned by live web search during preparation of this review; citations are limited to sources actually retrieved.*
