# Session handoff — 2026-07-02 — transferable-gene genealogy + real crypto

Branch: `claude/sharp-bardeen-01e312` (6 commits, fast-forward of `master` @ d32a774).
Spec gate: **`cabal test` green at 1442 tests**, `cabal run spec-codegen` shows **no drift**.
Everything added is **GHC-boot-only, hand-written, byte-exact, zero third-party dependency**.

## What shipped

The goal was the "genes as transferable, tracked with genealogy to their creator" direction from the
research corpus. The whole social layer is now **one content-addressed append-only log, folded four
ways** (see `research/00-synthesis.md`). This session built the foundation end-to-end, plus the real
cryptography under it.

| Commit | Module(s) | What it establishes |
|--------|-----------|---------------------|
| `85b3e30` | `Spec.GeneHash` | A gene's `GeneId` = FNV-1a over a canonical preimage **including its parents**, so the content-address commits to ancestry. Turns `Spec.Lineage`'s "acyclic by construction" into a proven theorem (`lawBuiltGenealogyAcyclic`). Injective length-prefixed LE serialisation (`lawCanonicalRoundTrip`). Also lands the cited `research/` corpus. |
| `fe3f28b` | `Spec.DerivationLog` | Genealogy as an **order-independent fold** of an append-only derivation log — a Merkle-CRDT in miniature. Proven order-independent + idempotent + monotone (SEC via a permutation test), so concurrent creators converge with no coordination. `logFromOps` bridges `GeneHash` transcripts to a gossip-able log. |
| `a2271e7` | `Spec.LedgerCRDT` | Proof that `Spec.Trade` is a **Grow-only-Set CvRDT**: grant set is a join-semilattice, fold is a monotone homomorphism ⇒ **Strong Eventual Consistency** (Shapiro et al.). `lawHoldingsFromState` pins it to the shipped `Trade.holdings`. |
| `ef075a6` | `Codegen.GeneHash` → `SixFour/Generated/GeneHashGolden.swift` | Byte-exact golden for the content-address so the Swift port reproduces `canonicalBytes`/`geneId` bit-for-bit. **Decision committed: parent order is significant** (not sorted), pinned by a reversed-parents fixture that must hash differently. |
| `c0c7c96` | `Spec.SigChain` | Tamper-evident authorship: per-creator append-only, hash-linked chain of signed authorship attestations (Keybase construction). Hash chain and signature each proven load-bearing (a re-signed interior splice is still caught by the successor's back-pointer). Initially bootstrapped on an RSA stand-in. |
| `0d3b5fd` | `Spec.Sha512`, `Spec.Ed25519`, `Spec.SigChain` (rewired) | **Real Ed25519 (RFC 8032) + SHA-512 (FIPS 180-4)**, hand-written from scratch. SigChain now signs with genuine Ed25519; the RSA stand-in is gone. |

## Verification notes (important)

- **SHA-512** gated against NIST known-answer vectors (`""`, `"abc"`).
- **Ed25519** gated against RFC 8032 tests 1–3 **plus an OpenSSL-3.6.1-generated vector**. Public
  keys, signatures, and verification reproduced bit-for-bit.
- **Trap encountered:** a `WebFetch` of RFC 8032 silently corrupted several hex digits (an inserted
  `1` in the SHA-512(`abc`) vector; an inserted `5` in Ed25519 test-1's signature). This surfaced only
  as golden-test failures. Ground truth was re-established with local `shasum -a 512` and `openssl`
  (3.6.1, which supports Ed25519). **Lesson: never trust fetched crypto constants — verify against a
  local oracle.** The known-answer gates are what caught it.
- Crypto property tests are capped (`withMaxSuccess 20–25`, small chains) so the suite stays ~69s;
  Ed25519 sign/verify is ~8k `Integer` mults each.

## State of the build order (`research/00-synthesis.md` §5)

```
✅ GeneHash        parents[] in the content-address (acyclicity theorem)
✅ DerivationLog   genealogy = order-independent fold (Merkle-CRDT)
✅ LedgerCRDT      trade ledger is a G-Set CvRDT (Strong Eventual Consistency)
✅ Codegen.GeneHash byte-exact Swift gate; parent-order decided (significant)
✅ SigChain        tamper-evident authorship — on real Ed25519
✅ Sha512+Ed25519  hand-written, byte-exact, RFC/OpenSSL-verified
```

## Next steps

1. **Reputation (build-order Step 4)** — `demand` as a seed-anchored EigenTrust flow, propagated
   *concavely* up the genealogy DAG (`research/04-swap-economy-governance.md` §4c; ties to
   `01-transferable-genes-genealogy`). **Needs a product decision first:** where to sit on the
   concave↔linear frontier (anti-plutocracy vs. anti-sybil, per the 2026 "Concave is the New Linear"
   impossibility) and what the pre-trusted seed set is. Open sub-question: is power-iteration-to-a-
   tolerance acceptable as a "pure fold"?
2. **Device port** — hand-write `geneHash` + Ed25519 in Swift/Zig (hardening timing) against the
   emitted goldens. `GeneHashGolden.swift` exists; SigChain/DerivationLog/Ed25519 wire-format codegen
   contracts are not yet emitted and should precede the port.
3. **Ed25519 note** — the reference is intentionally simple (not constant-time). The device port
   hardens timing while matching these bytes.

## How to verify

```bash
cd spec && cabal build && cabal test && cabal run spec-codegen   # 1442 tests, no drift
# git checkout SixFour/Generated/BuildStamp.swift  # if the stamp changed
```
Spec browse entry point: module `SixFour.Spec.Map` (economy & governance section, §11).
