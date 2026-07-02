# Transferable Genes + Verifiable Genealogy: A Literature Review & Design Brief

**Abstract.** SixFour already content-addresses "genes" (learned parameter blobs) by the hash of their canonical weight bytes, but a gene's *lineage* — who created it and what it was derived from — lives loosely in a mutable tag rather than in the append-only trade ledger, so provenance and trade have drifted apart. This brief surveys the PhD-level literature on content-addressed Merkle DAGs, provenance data models, content authenticity, distributed causal history, reproducible-build lineage, and signed identity, then turns it into concrete, dependency-free, Haskell-verifiable recommendations for binding immutable genealogy to every gene.

---

## 1. Framing for SixFour

The project's own contract already contains most of the primitives that the provenance literature formalizes. A gene is **content-addressed** — "identified by hash of canonical weight bytes, not ownership." That is exactly the object identity that Git, IPFS/IPLD, and Nix are built on. The **swap-economy** (`Spec.Trade`) is an **append-only ledger** of `Trade` events folded into governance scalars (demand, reliability); that "fold of an append-only log" shape is precisely how provenance systems reduce a history graph into queryable state.

The gap is a *seam between two things that should be one graph*:

- **Trade** answers *"who now has access to gene G?"* — a monotone, grant-based reachability question over the ledger.
- **Provenance** should answer *"where did gene G come from, and who created it?"* — a lineage question that trade does not encode. Today the answer sits in a gene *tag* that is mutable, unsigned, and not causally ordered.

The literature gives us four things SixFour lacks and can adopt cheaply: (1) a **parent-hash DAG** so a gene immutably names its ancestors; (2) a **standard vocabulary** (PROV) for *derived-from / attributed-to / generated-by*; (3) **creator attestation** so "attributed-to" is cryptographically true, not merely asserted; and (4) **causal ordering** so lineage stays correct when two devices create derived genes concurrently. Crucially, all four are hash-and-signature constructions with no runtime dependency — a natural fit for the "Haskell-verified, dependency-free, hand-written" ethos.

---

## 2. Literature Survey

### 2.1 Content-addressed storage & Merkle DAGs

The foundational move is to make an object's *name* a function of its *content*. In Git, blobs (file content), trees (directories), and commits are each stored under the SHA-1 hash of their serialized bytes; a commit points to one top-level tree and to one or more **parent commits**, and "the parent pointer is what turns a set of independent snapshots into a lineage" — the recursive structure "forms a hash tree, often called a Merkle DAG" [1][2]. Because the hash is derived from content, the same content always produces the same identifier (deterministic, content-addressable) [2].

IPFS generalizes this. A **Content Identifier (CID)** is "a self-describing content-addressed label" derived from the content's hash (SHA-256/BLAKE2 typical), so "every time someone puts the same data into IPFS, they'll get back an identical CID" [3][4]. In a Merkle-DAG each node's CID "is the result of hashing the node's contents" *including the CIDs of its children*, which enforces immutability: "any change in a node would alter its identifier and thus affect all the ascendants in the DAG," and "two nodes with the same CID univocally represent exactly the same DAG," giving automatic **deduplication** [4]. **IPLD** (InterPlanetary Linked Data) is the separable data-model layer — "an ecosystem of standardized formats … universally addressable and linkable" — that defines how CID links are encoded (JSON, CBOR, DAG-CBOR) [5]. The key structural property for lineage: a Merkle-DAG "can only be constructed from the leaves" — children are hashed first, parents incorporate those hashes — so the hash chain is "an unbreakable mathematical record of relationships" [4]. Naming an ancestor by its hash *is* an immutable derived-from edge.

### 2.2 Provenance data models

The W3C **PROV** family (PROV-DM the data model, PROV-O its OWL ontology) is the standard vocabulary for lineage [6][7]. PROV-DM (W3C Recommendation, 30 April 2013; editors Luc Moreau and Paolo Missier) is built on three classes — **Entity** ("a physical, digital, conceptual … thing"), **Activity** ("something occurring over time that acts upon or with entities"), and **Agent** ("something that bears … responsibility") — related by properties including `wasGeneratedBy`, `used`, `wasAttributedTo` (entity→agent), `wasAssociatedWith` (activity→agent), and `wasDerivedFrom` (entity→entity) [6]. The canonical way to say *"gene B was derived from gene A by agent X"* is:

```
wasDerivedFrom(B, A)
wasGeneratedBy(B, trainA)         // trainA is the training/derivation Activity
used(trainA, A)
wasAssociatedWith(trainA, X)      // X = the creator Agent
wasAttributedTo(B, X)             // shorthand attribution
```

PROV deliberately "separates the derivation relationship from responsibility attribution," so you can record lineage at coarse or fine precision [6]. PROV-O expresses the same model as an OWL ontology for RDF interoperability [7]. PROV is the modern successor to the earlier **Open Provenance Model (OPM)**; the W3C PROV family is explicitly designed to be "generic and domain-agnostic" with extension mechanisms for specific domains [6][7] — SixFour's "gene" is one such domain entity.

### 2.3 Content authenticity & attribution

**C2PA / Content Credentials** is the deployed industry standard for cryptographically bound media provenance, and it is the closest existing analogue to what SixFour wants (provenance carried *inside the file*). A C2PA **Manifest** contains a **Claim** (assertions + metadata), **Assertions** (origin, tools, AI use), a **hard binding** — a SHA-256 hash of the actual content so any alteration breaks the match — and a **Claim Signature** using standard X.509 credentials [8][9]. Its lineage model is a family tree: assets built from sources embed those sources as **ingredients**, "creating a tree of provenance … that can stretch all the way back to each ingredient's creation," and each edit adds a new manifest layer [9]. Verification is exactly the check SixFour would run on a received GIF: (1) recompute the content's SHA-256, (2) compare to the manifest's hard binding, (3) verify the X.509 signature with the signer's public key, (4) confirm the signer is trusted [9]. C2PA 2.1 (Sept 2024) added AI-training-data-disclosure assertions [8]. Known limitations are relevant to SixFour: manifests can be stripped (no binding survives a re-encode that discards the block), and trust ultimately rests on the certificate/trust-list infrastructure [8].

For provenance of the **model weights themselves**, the neural-network watermarking literature is relevant. Uchida et al. (2017) introduced embedding a multi-bit watermark **directly into a network's weights** via a regularization term during training, recoverable by projecting flattened weights through a fixed matrix and threshold [10][11]. Later work embeds identifiers into normalization-layer scale parameters for GANs and uses "passport" layers to resist ambiguity attacks [10]. For ML *documentation* provenance, **Model Cards** (Mitchell et al., 2019) and **Datasheets for Datasets** (Gebru et al., 2018/2021) standardize human-readable records of a model/dataset's motivation, composition, intended use, and history — bringing "data provenance to the forefront of broader ML practice" [12][13].

### 2.4 Distributed causal history

To keep lineage correct when genes are created concurrently on different devices, SixFour needs a causal-ordering mechanism. **Lamport's happened-before** relation and scalar clocks give a *necessary* condition (A→B ⇒ TS(A)<TS(B)) but not sufficient; **vector clocks**, established independently by Fidge (1988, Australian Computer Science Conference) and Mattern (1989, *Parallel Computing*), capture causality in both directions and can distinguish concurrency from ordering [14][15]. **Version vectors** are the closely related construct for tracking which versions of a replicated item a node has observed [14].

The decisive result for SixFour is **Merkle-CRDTs** (Sanjuán, Pöyhtäri, Teixeira, Psaras; arXiv:2004.00107, 2020; Protocol Labs) [16]. Its core insight: **a Merkle-DAG *is* a logical clock.** Because each node's hash includes its parents' hashes, a descendant necessarily *happened-after* its ancestors, while nodes on concurrent branches are causally incomparable — so the DAG structure encodes the same partial order a vector clock would, *without maintaining explicit per-replica counters*. This "can act as logical clocks giving Merkle-CRDTs the potential to greatly simplify the design and implementation of convergent data types in systems with weak messaging-layer guarantees and a very large number of replicas," while inheriting content-addressing's "security and de-duplication properties" [16]. Merging two replicas is just DAG union (add missing nodes, keeping both concurrent branches); convergence is automatic because the same set of nodes always hashes to the same roots. The main limitation is that history is **append-only** — removal is done by tombstones, not deletion, so causal history and storage grow monotonically [16]. That limitation is *not a problem here*: SixFour's holdings and ledger are already explicitly **monotone / append-only**, so a Merkle-CRDT is a structural match rather than a compromise.

### 2.5 Reproducible-build lineage as a model

Functional package managers show how to make a *derivation graph* itself content-addressed and reproducible — a direct template for gene derivation. **Nix** installs each build output into a unique store path derived from a cryptographic hash of all its inputs; **fixed-output / content-addressed derivations** hash the *expected output* (SHA-256), so "the store path reflects the actual content without depending on build-time variations," and `nix make-content-addressed` rewrites input-addressed builds into content-addressed ones [17]. **GNU Guix**, built on Nix's model, achieves "bit-for-bit identical results" from the same inputs across heterogeneous machines and is explicitly valued for "referential transparency and provenance tracking … critical for scientific validation," using Scheme for reproducible derivations [18]. The lesson for SixFour: if a gene's identity is the hash of its *canonical bytes* and its derivation records the hashes of its *input genes* plus the (deterministic) training recipe, then the derivation graph is itself a reproducible, content-addressed provenance DAG — the same discipline SixFour already applies to golden vectors.

### 2.6 Signed lineage & identity

For "attributed-to" to be *true* rather than merely claimed, the creator must be cryptographically bound to the gene, and that binding must resist Sybil forgery. **Keybase sigchains** are the canonical construction: every account has a public, append-only **sigchain** — "an ordered list of statements about how the account has changed over time"; each link is signed by one of the user's keys and "includes a sequence number and the hash of the previous link," so "the server can't create links on its own or omit links without invalidating the whole sigchain," and a public Merkle tree makes rollback detectable [19]. This is a per-identity hash chain + signature — exactly the primitive needed to say "creator X, holding key K, signs gene B's derivation record," with the signature chaining X's other statements so identity is tamper-evident. (Sigstore/keyless signing is a related, CA-backed alternative surfaced in the same search space, but sigchains map more directly onto SixFour's self-contained, offline-capable model.) Sybil resistance for *attribution* is partly structural here: because holdings only grow and trades are grant-based, a forged creator identity gains nothing by minting fake accounts unless it can also produce genes others want — reliability (a governance scalar SixFour already folds) becomes the natural anti-Sybil weight.

---

## 3. Comparative Analysis / Tradeoffs

| System | Object identity | Lineage encoding | Creator binding | Causal ordering | Fit for SixFour |
|---|---|---|---|---|---|
| **Git** [1][2] | SHA of serialized object | parent-commit pointers (Merkle DAG) | optional GPG sign | DAG partial order | Model for parent-hash edges; no built-in attribution |
| **IPFS/IPLD** [3][4][5] | CID (content hash) | child-CID links in node | none native | DAG partial order | Best template for content-addressed gene DAG + dedup |
| **W3C PROV** [6][7] | URI/id (not content) | `wasDerivedFrom`/`used`/`wasGeneratedBy` | `wasAttributedTo` agent | none (needs external) | Best *vocabulary*; adopt as the semantic layer |
| **C2PA** [8][9] | asset + SHA-256 hard binding | ingredient tree, per-edit manifest | X.509 claim signature | none (linear edit tree) | Best *in-file carriage* model; but X.509/trust-list is dependency-heavy |
| **Nix/Guix** [17][18] | store path = hash of inputs | input-derivation graph | none | build graph order | Best *reproducible-derivation* discipline |
| **Vector clocks** [14][15] | n/a | n/a | n/a | full causality | Concept only; Merkle-DAG subsumes it |
| **Merkle-CRDT** [16] | CID | parent-hash DAG *as* clock | none native | DAG = logical clock, auto-converge | **Best structural match** — append-only, offline, convergent |
| **Keybase sigchain** [19] | account + key | prev-link hash chain | per-link signature | chain order | Best *creator attestation* primitive |

The synthesis: **no single system does everything, but they compose cleanly.** IPFS/Nix give content-addressed identity; PROV gives the vocabulary; Merkle-CRDT gives lineage-as-logical-clock that converges under concurrency; sigchains give creator attestation; C2PA shows how to *carry* it in-file (with its X.509 machinery swapped for a hand-written Ed25519 signature to honor the zero-dependency rule).

---

## 4. Design Implications for SixFour

**D1 — Add a parent-hash DAG to the gene, reusing the existing content address.** A gene is already `hash(canonical weight bytes)`. Extend the canonical serialization with a small, ordered `parents: [GeneHash]` field and a `derivation` field (the deterministic recipe: base gene(s) + training-op tag + epoch). Hash *that whole record*. Now the gene's identity commits to its ancestry exactly as an IPFS node's CID commits to its children [4], and as a Git commit's SHA commits to its parents [2]. Immutability is free: you cannot alter an ancestor without changing every descendant's hash. This keeps the "zero-gene == floor" contract intact — a missing ancestor is a dangling hash the receiver detects, and the gene degrades to the deterministic floor rather than to garbage.

**D2 — Model the record on PROV, minimally.** Encode each derivation as the PROV quad specialized to genes: `wasDerivedFrom(childHash, parentHash)`, `wasGeneratedBy(childHash, trainingActivity)`, `wasAssociatedWith(trainingActivity, creatorKey)`, `wasAttributedTo(childHash, creatorKey)` [6]. You do **not** need OWL/RDF — encode it as a fixed-shape Haskell record (a `Spec.Provenance` module) that codegens the byte-exact Swift/Zig struct, matching how the rest of the spec is ported. The training-site taxonomy SixFour already has (`DevicePerCapture`/`MacOffline`/`DevicePerUser`/`NotTrained`) *is* the PROV Activity's site attribute — the vocabulary already fits your taxonomy.

**D3 — Make provenance a fold of the append-only ledger — same style as governance.** SixFour already folds `Trade` events into `demand`/`reliability`. Add a second event kind (or a parallel append-only log) of **derivation events**, and compute lineage as `foldl` over that log into a `GeneGraph` (map from gene hash → its parents + creator + epoch). This is a Merkle-CRDT in miniature [16]: the events are content-addressed, the DAG *is* the logical clock, and two devices that concurrently derive genes converge under DAG union with no vector-clock bookkeeping — which is why Merkle-CRDTs "simplify the design of convergent data types … with a very large number of replicas" [16]. Because history is append-only, this matches SixFour's monotone-holdings invariant rather than fighting it. Reachability queries ("is G an ancestor of H?", "list all creators in H's lineage") are pure folds over the resulting DAG — trivially Haskell-verifiable with QuickCheck laws (e.g. *derivation edges never form a cycle*, *every non-root gene names ≥1 in-graph parent*, *ancestor-closure is monotone under event append*).

**D4 — Bind the creator with a hand-written signature, not X.509.** C2PA's model (hash the content, sign the claim, receiver re-hashes + verifies the signature) is exactly right [9], but its X.509/trust-list stack violates the zero-third-party rule. Substitute a **hand-written Ed25519 (or the project's chosen curve) verify** in Swift/Zig, golden-gated against Haskell like every other primitive: the creator signs the derivation record's hash; the signature travels in the same GIF89a Application-Extension block as the σ-pair genome. Give each creator a **sigchain** [19]: each new signed derivation links the hash of the creator's previous statement, so identity is tamper-evident and offline-verifiable, no server needed. Attestation lives **beside `Spec.Trade`, not inside it**: trade grants *access* (monotone reachability); the sigchain-signed provenance record asserts *origin*. A trade event and a derivation event may reference the same gene hash, but they answer different questions — keep them as two folds over one content-addressed history.

**D5 — Carry lineage in-file exactly like the genome already is.** The 384-DOF σ-pair genome already rides inside the GIF89a Application-Extension block [project contract]. Append a compact, canonical provenance block there: `{geneHash, parents[], creatorPubKey, sig, epoch}`, Int-encoded and little-endian like the Q16 coefficients, so "any receiver can extract and verify it" — the C2PA carriage pattern [9] realized with SixFour's own hand-written codec. A receiver recomputes the gene hash, checks each parent hash resolves (or is a known floor), and verifies the signature — the four-step C2PA validation [9], dependency-free.

**D6 — Treat the derivation recipe as a reproducible derivation.** Borrow the Nix/Guix discipline [17][18]: if the training op is deterministic given (input-gene hashes, op tag, seed/epoch), then the child gene's hash is *reproducible* — a third party can re-derive it and confirm the lineage claim, not just trust it. This upgrades provenance from *attested* to *verifiable*, and it is the same golden-vector discipline SixFour already lives by.

---

## 5. Open Questions / Gaps

1. **Signature scheme choice under the zero-dependency rule.** A hand-written, constant-time Ed25519 verify is a non-trivial (but bounded, well-specified) amount of Zig/Swift; is byte-exact golden-gating against a Haskell reference realistic here, or is a simpler MAC-plus-key-registry acceptable for MVP? (Ed25519 gives non-repudiation; a MAC does not.)
2. **Genome mutability vs. content address.** Genes are *blended* on receipt (the σ-pair genome is designed to be blended). A blend produces a *new* gene with *new* parents — is every blend a first-class derivation event, and does that make the DAG explode? A dedup/threshold policy (only record blends that are kept/traded) may be needed.
3. **Tombstones and monotone growth.** Merkle-CRDT history only grows [16]; how does SixFour bound on-device provenance-DAG size — snapshotting, pruning to a signed root, or capping ancestry depth carried in-file?
4. **Sybil resistance strength.** Grant-based, monotone holdings blunt Sybil incentives, but a determined actor could still fabricate a lineage of self-signed "creators." Does reliability-weighting (an existing governance scalar) suffice, or is a scarce/earned identity primitive (guild membership, council attestation) needed to make attribution costly?
5. **Provenance under the swap-economy's grant semantics.** When a trade *grants* both parties access, does provenance need a "custody" edge distinct from "derivation," or is creator-attribution the only lineage that matters? (Custody is a trade-ledger fold; derivation is a separate DAG — see [[04-swap-economy-governance]].)
6. **Concurrent-creation identity of "the same" gene.** Two devices independently training on the same capture may produce byte-identical genes (→ identical hash, auto-dedup [4]) *or* near-identical ones (→ different hashes, spurious distinct lineage). A canonicalization/quantization policy determines which, and it interacts with expressiveness — see [[02-gene-expressiveness]].

---

## 6. References

1. Enginerds, *Git's Data Model — Commits, Trees, Blobs, and SHA-1 Hashes*. https://www.enginerds.dev/docs/courses/git/06-git-data-model/
2. Kivabe, K., *Git Object Hashing and Content Addressability*. https://blogs.kenokivabe.com/article/git-object-hashing-and-content-addressability
3. IPFS Docs, *How IPFS works*. https://docs.ipfs.tech/concepts/how-ipfs-works/
4. IPFS Docs, *Merkle Directed Acyclic Graphs (DAG)*. https://docs.ipfs.tech/concepts/merkle-dag/
5. ProtoSchool / IPFS Docs, *IPLD (InterPlanetary Linked Data)*. https://proto.school/course/ipld/ ; https://docs.ipfs.tech/concepts/glossary/
6. Moreau, L. & Missier, P. (eds.), *PROV-DM: The PROV Data Model*, W3C Recommendation, 30 April 2013. https://www.w3.org/TR/prov-dm/
7. Lebo, T., Sahoo, S., McGuinness, D. (eds.), *PROV-O: The PROV Ontology*, W3C Recommendation. https://www.w3.org/TR/prov-o/
8. *Content Credentials: C2PA Technical Specification* (v2.1, 2024-09-20; v2.4). https://spec.c2pa.org/specifications/specifications/2.1/specs/_attachments/C2PA_Specification.pdf ; https://spec.c2pa.org/specifications/specifications/2.4/specs/C2PA_Specification.html
9. *C2PA and Content Credentials Explainer* (v2.4). https://spec.c2pa.org/specifications/specifications/2.4/explainer/Explainer.html
10. *A survey of deep neural network watermarking techniques* (arXiv:2103.09274). https://arxiv.org/pdf/2103.09274 (covers Uchida et al. 2017 and passport/normalization-layer methods)
11. *A comprehensive survey of watermarking techniques for copyright protection and integrity verification on DNNs and generative models*, Discover Applied Sciences (Springer). https://link.springer.com/article/10.1007/s42452-026-08576-3
12. Mitchell, M. et al., *Model Cards for Model Reporting* (2019). https://www.researchgate.net/publication/330268857_Model_Cards_for_Model_Reporting
13. Gebru, T. et al., *Datasheets for Datasets* (2018/2021). https://www.researchgate.net/publication/324055506_Datasheets_for_Datasets
14. *Vector clock*, Wikipedia (summarizes Fidge 1988 & Mattern 1989; version vectors). https://en.wikipedia.org/wiki/Vector_clock
15. Sookocheff, K., *Vector Clocks*. https://sookocheff.com/post/time/vector-clocks/
16. Sanjuán, H., Pöyhtäri, S., Teixeira, P., Psaras, I., *Merkle-CRDTs: Merkle-DAGs meet CRDTs*, arXiv:2004.00107 (2020); Protocol Labs draft. https://arxiv.org/abs/2004.00107 ; https://research.protocol.ai/blog/2019/a-new-lab-for-resilient-networks-research/PL-TechRep-merkleCRDT-v0.1-Dec30.pdf
17. *Nix (package manager)*, Wikipedia (fixed-output / content-addressed derivations). https://en.wikipedia.org/wiki/Nix_(package_manager)
18. *GNU Guix*, Wikipedia (reproducible builds, provenance tracking). https://en.wikipedia.org/wiki/GNU_Guix
19. *Keybase Book: Signature Chains (sigchain)*. https://book.keybase.io/docs/teams/sigchain ; https://book.keybase.io/docs/teams/details

---

*Sibling briefs:* [[02-gene-expressiveness]] · [[03-distributed-biological-models]] · [[04-swap-economy-governance]]
