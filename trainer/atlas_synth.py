"""atlas_synth.py — synthetic curation-session generator for the Color Atlas trainer.

Phase-T1/T2 cold-start data per docs/COLOR-ATLAS.md §5: NO human data. Each
example is a (board, genome) pair with

  • board  — the [16,16,16,6] curation tensor, built by the EXACT
    Coverage.okLabBin arithmetic (16 bins/axis; L over [0,1], a/b over
    [-0.5,0.5], floor + clamp — mirrored bit-for-bit from
    spec/src/SixFour/Spec/Coverage.hs) over a random set of 64 per-frame
    256-colour OKLab palettes, plus synthetic curation edits (kills ch4,
    weights ch3, anchors ch5).
  • genome — a 384-DOF depth-7 σ-pair Haar tree (SigmaPairHead layout: root
    triple + level offsets [1,2,4,8,16,32,64] triples). Root genome = the
    deterministic MAXIMIN COLLAPSE (farthest-point selection of 128
    generators over occupied bin centres, σ-paired to 256 leaves), per the
    cold-start design; variants = random codebook walks (curriculum Medium).
  • value label — the deterministic shaped COVERAGE value (coverage fraction
    of occupied data bins hit by the candidate's 256 leaves, + weight-field /
    kill / anchor shaping — the shapedReward analogue, doc §4.0).
  • policy target — one-step-lookahead values over the FULL finite move
    vocabulary 127 slots × 12 codebook deltas = 1,524 (root unaddressable —
    lawVocab1524), top-k=8 + softmax renormalised (the mkAtlasOracle law,
    doc §4.1). Lookahead is exact + vectorised: reconstruction is linear in
    the coefficients, so each move shifts a signed generator block.
  • Compare pairs — synthetic Bradley-Terry pairs (winner = higher shaped
    value) for the value head's pairwise loss.

Pure numpy, fully seeded, deterministic. Constants mirror
trainer/generated/look_net_mlx.py (SIGMA_PAIR_*) and Coverage.hs.
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np

# ── Pinned constants (mirrors of spec / generated contracts) ───────────────
BINS = 16                       # Coverage.coverageBinsPerAxis
N_CELLS = BINS ** 3             # 4096
BOARD_CHANNELS = 6              # doc §2: ch0..ch5
N_FRAMES = 64
K = 256                         # colours per palette
PIXELS_PER_FRAME = 64 * 64      # 4096; 64 frames → 262144 total

SIGMA_PAIR_DEPTH = 7            # generated/look_net_mlx.SIGMA_PAIR_DEPTH
N_GENERATORS = 128
N_LEAVES = 256                  # = SIGMA_PAIR_LEAVES
GENOME_DOF = 384                # = SIGMA_PAIR_DOF
LEVEL_NODE_COUNTS = [1, 2, 4, 8, 16, 32, 64]   # offsets per Haar level
N_SLOTS = sum(LEVEL_NODE_COUNTS)               # 127 — root UNADDRESSABLE
N_DELTAS = 12
N_VOCAB = N_SLOTS * N_DELTAS                   # 1,524 (lawVocab1524)
TOP_K = 8                                      # mkAtlasOracle top-k law

ATLAS_TOKEN_DIM = 13            # 10 base GMM dims + 3 σ-invariant curation cols

# Shaping weights for the deterministic value (λw, λt, λa in doc §4.0).
W_WEIGHT = 0.5
W_KILL = 1.0
W_ANCHOR = 0.5

_SIG = np.array([1.0, -1.0, -1.0])   # σ(L,a,b) = (L,−a,−b)

# ── deltaCodebook: ±L/±a/±b × magnitudes {0.04, 0.01} (doc §3.2) ───────────
# Chroma rows 2i/2i+1 are σ-pairs (σ row2 = row3, σ row4 = row5, …).
# PROTOTYPE CAVEAT: the ±L rows are σ-FIXED individually (σ(+L) = +L), so the
# strict "rows 2i/2i+1 swap under σ" law holds for the 8 chroma rows only.
DELTA_CODEBOOK = np.array(
    [[m * s if ax == a else 0.0 for ax in range(3)]
     for m in (0.04, 0.01) for a in range(3) for s in (1.0, -1.0)],
    dtype=np.float64,
)  # (12, 3); row order: +L,−L,+a,−a,+b,−b at 0.04 then at 0.01
assert DELTA_CODEBOOK.shape == (N_DELTAS, 3)


# ── okLabBin — bit-mirror of Coverage.okLabBin (floor + clamp) ─────────────
def oklab_bin(lab: np.ndarray) -> np.ndarray:
    """OKLab (...,3) → flat bin id iL*256 + ia*16 + ib, each axis in [0,16)."""
    il = np.clip(np.floor(lab[..., 0] * BINS), 0, BINS - 1)
    ia = np.clip(np.floor((lab[..., 1] + 0.5) * BINS), 0, BINS - 1)
    ib = np.clip(np.floor((lab[..., 2] + 0.5) * BINS), 0, BINS - 1)
    return (il * BINS * BINS + ia * BINS + ib).astype(np.int64)


def bin_center(ids: np.ndarray) -> np.ndarray:
    """Flat bin id → OKLab centre of the cell (inverse-ish of oklab_bin)."""
    il, rem = np.divmod(ids, BINS * BINS)
    ia, ib = np.divmod(rem, BINS)
    return np.stack([(il + 0.5) / BINS,
                     (ia + 0.5) / BINS - 0.5,
                     (ib + 0.5) / BINS - 0.5], axis=-1)


# ── σ-pair Haar tree: reconstruct / analyze / move slot table ──────────────
def reconstruct_paired(genome: np.ndarray) -> np.ndarray:
    """(384,) coeffs → (256,3) σ-pair leaves [g0, σg0, g1, σg1, …].
    Numpy mirror of look_net_mlx.reconstruct_sigma_pair (root + 7 levels;
    node n with offset d yields [n+d, n−d])."""
    coeffs = genome.reshape(N_GENERATORS, 3)
    nodes = coeffs[0:1]
    cur = 1
    for lv in range(SIGMA_PAIR_DEPTH):
        n = 1 << lv
        offs = coeffs[cur:cur + n]
        cur += n
        nodes = np.stack([nodes + offs, nodes - offs], axis=1).reshape(2 * n, 3)
    gens = nodes                                       # (128, 3)
    return np.stack([gens, gens * _SIG], axis=1).reshape(N_LEAVES, 3)


def analyze_paired(gens: np.ndarray) -> np.ndarray:
    """(128,3) generators → (384,) coeffs. Exact inverse of the generator
    pyramid: parent = (c1+c2)/2, offset = (c1−c2)/2 per level."""
    levels = []
    nodes = gens.astype(np.float64)
    for _ in range(SIGMA_PAIR_DEPTH):
        a, b = nodes[0::2], nodes[1::2]
        levels.append((a - b) / 2.0)
        nodes = (a + b) / 2.0
    return np.concatenate([nodes] + levels[::-1], axis=0).reshape(GENOME_DOF)


def _slot_tables():
    """Per-slot (level, node-index), 2^−level magnitude scale, and the
    ±1 generator-sign matrix S[slot, generator] a move applies."""
    levels, scales = [], []
    signs = np.zeros((N_SLOTS, N_GENERATORS))
    s = 0
    for lv, n in enumerate(LEVEL_NODE_COUNTS):
        block = N_GENERATORS // n
        for ix in range(n):
            levels.append((lv, ix))
            scales.append(2.0 ** (-lv))                # magnitude halves per level
            signs[s, ix * block: ix * block + block // 2] = 1.0
            signs[s, ix * block + block // 2: (ix + 1) * block] = -1.0
            s += 1
    return levels, np.array(scales), signs


SLOT_LEVELS, SLOT_SCALE, SLOT_SIGNS = _slot_tables()

# Leaf-expanded signs (leaf 2g and 2g+1 share generator g's sign) and the
# per-leaf delta (even leaves get δ, odd σ-reflected leaves get σδ).
_LEAF_SIGNS = np.repeat(SLOT_SIGNS, 2, axis=1)                      # (127, 256)
_LEAF_DELTAS = np.stack([DELTA_CODEBOOK, DELTA_CODEBOOK * _SIG],
                        axis=1)[:, np.tile([0, 1], N_GENERATORS), :]  # (12, 256, 3)


def apply_vocab_move(genome: np.ndarray, slot: int, delta_idx: int) -> np.ndarray:
    """applyMove for the vocab: add codebook[δ]·2^−level to the slot's triple.
    (Root triple 0 is untouched — root unaddressable.)"""
    lv, ix = SLOT_LEVELS[slot]
    t = 1 + ((1 << lv) - 1) + ix                       # triple index in the flat genome
    g = genome.copy()
    g[3 * t: 3 * t + 3] += DELTA_CODEBOOK[delta_idx] * SLOT_SCALE[slot]
    return g


# ── Sessions: boards + curation edits ──────────────────────────────────────
@dataclass
class Session:
    board: np.ndarray          # (4096, 6) float64 — ch0..ch5 flattened over bins
    anchor_ids: np.ndarray     # flat bin ids of PinAnchor cells
    seed: int


def sample_session(seed: int, n_blobs: int = 6, n_kills: int = 24,
                   n_weights: int = 32, n_anchors: int = 3) -> Session:
    """Random per-frame palette set → board channels ch0/ch1 by okLabBin;
    synthetic curation edits fill ch3/ch4/ch5. ch2 (candidate coverage) is
    genome-dependent and computed per example by `tokens_of`."""
    rng = np.random.default_rng(seed)
    # Blob-structured OKLab colours (so coverage is non-trivial): per frame,
    # K colours drawn from n_blobs Gaussian clusters drifting over frames.
    centers = np.column_stack([rng.uniform(0.15, 0.85, n_blobs),
                               rng.uniform(-0.35, 0.35, (n_blobs, 2))])
    drift = rng.normal(0.0, 0.002, (n_blobs, 3))
    board = np.zeros((N_CELLS, BOARD_CHANNELS))
    for f in range(N_FRAMES):
        which = rng.integers(0, n_blobs, K)
        cols = centers[which] + drift[which] * f + rng.normal(0.0, 0.04, (K, 3))
        cols[:, 0] = np.clip(cols[:, 0], 0.0, 1.0)
        cols[:, 1:] = np.clip(cols[:, 1:], -0.5, 0.5)
        ids = oklab_bin(cols)
        # ch0 binMassPalettes: palette-entry count / (64×256)
        np.add.at(board[:, 0], ids, 1.0 / (N_FRAMES * K))
        # ch1 binMassPixels: Dirichlet per-slot pixel mass / 262144
        w = rng.dirichlet(np.full(K, 0.3)) * PIXELS_PER_FRAME
        np.add.at(board[:, 1], ids, w / (N_FRAMES * PIXELS_PER_FRAME))
    occ = np.flatnonzero(board[:, 0] > 0)
    # ToggleBin kills (ch4), WeightRegion deltas (ch3), PinAnchor (ch5).
    kills = rng.choice(occ, size=min(n_kills, len(occ)), replace=False)
    board[kills, 4] = 1.0
    weighted = rng.choice(occ, size=min(n_weights, len(occ)), replace=False)
    board[weighted, 3] = rng.uniform(-1.0, 1.0, len(weighted))
    free = np.setdiff1d(occ, kills)
    anchors = rng.choice(free, size=min(n_anchors, len(free)), replace=False)
    board[anchors, 5] = 1.0
    return Session(board=board, anchor_ids=anchors, seed=seed)


# ── Deterministic oracle: maximin collapse + shaped coverage value ─────────
def maximin_collapse(session: Session) -> np.ndarray:
    """Farthest-point selection of 128 generators over occupied, non-killed
    bin centres (mass-seeded, anchors forced first) → σ-paired root genome.
    The cold-start 'maximin collapse' policy: deterministic given the seed."""
    board = session.board
    cand_ids = np.flatnonzero((board[:, 0] > 0) & (board[:, 4] == 0))
    if len(cand_ids) == 0:
        cand_ids = np.flatnonzero(board[:, 0] > 0)
    cands = bin_center(cand_ids)
    rng = np.random.default_rng(session.seed + 0x5F64)
    if len(cands) < N_GENERATORS:                      # cycle + jitter (deterministic)
        reps = int(np.ceil(N_GENERATORS / len(cands)))
        cands = np.tile(cands, (reps, 1)) + rng.normal(0, 0.01, (reps * len(cands), 3))
        cand_ids = np.tile(cand_ids, reps)
    picked = [int(np.argmax(board[cand_ids, 0]))]      # seed: highest-mass bin
    for a in session.anchor_ids:                       # anchors forced in
        j = np.flatnonzero(cand_ids == a)
        if len(j) and int(j[0]) not in picked:
            picked.append(int(j[0]))
    d2 = np.min(np.sum((cands[:, None] - cands[picked][None]) ** 2, -1), axis=1)
    while len(picked) < N_GENERATORS:
        nxt = int(np.argmax(d2))                       # maximin step
        picked.append(nxt)
        d2 = np.minimum(d2, np.sum((cands - cands[nxt]) ** 2, -1))
    return analyze_paired(cands[picked])


def codebook_walk(genome: np.ndarray, rng: np.random.Generator,
                  n_moves: int = 12) -> np.ndarray:
    """Curriculum-Medium variant: a random walk over the 1,524 move vocab.
    Slots are sampled LEVEL-uniformly (coarse levels get more probability than
    slot-uniform would give) so walks actually cross bin boundaries — deep
    slots scale 0.01·2^−6 and rarely change the shaped value (all ties)."""
    g = genome.copy()
    level_start = np.cumsum([0] + LEVEL_NODE_COUNTS[:-1])
    for _ in range(n_moves):
        lv = int(rng.integers(SIGMA_PAIR_DEPTH))
        slot = int(level_start[lv] + rng.integers(LEVEL_NODE_COUNTS[lv]))
        g = apply_vocab_move(g, slot, int(rng.integers(N_DELTAS)))
    return g


def _shaped_from_occupancy(board: np.ndarray, occm: np.ndarray,
                           ids: np.ndarray) -> np.ndarray:
    """Shared shaping: occm (M,4096) bool leaf-occupancy, ids (M,256) leaf bins.
    value = coverage fraction of occupied data bins + λw·⟨ch3⟩ − λt·⟨ch4⟩ + λa·anchorHit."""
    occ = board[:, 0] > 0
    n_occ = max(int(occ.sum()), 1)
    covered = (occm & occ[None]).sum(axis=1) / n_occ
    wterm = board[:, 3][ids].sum(axis=1) / N_LEAVES
    kterm = board[:, 4][ids].sum(axis=1) / N_LEAVES
    anchors = np.flatnonzero(board[:, 5] > 0)
    ahit = occm[:, anchors].mean(axis=1) if len(anchors) else np.zeros(len(occm))
    return covered + W_WEIGHT * wterm - W_KILL * kterm + W_ANCHOR * ahit


def shaped_value(board: np.ndarray, genome: np.ndarray) -> float:
    """The deterministic value label V(board, genome) — coverage + shaping."""
    ids = oklab_bin(reconstruct_paired(genome))[None]            # (1, 256)
    occm = np.zeros((1, N_CELLS), dtype=bool)
    occm[0, ids[0]] = True
    return float(_shaped_from_occupancy(board, occm, ids)[0])


def lookahead_values(board: np.ndarray, genome: np.ndarray) -> np.ndarray:
    """(1524,) shaped value after EACH vocab move — exact, vectorised.
    Reconstruction is linear in the coeffs, so move (slot, δ) shifts leaves by
    sign[slot,leaf]·2^−level·(δ | σδ). Order: slot-major, slot*12 + delta."""
    leaves = reconstruct_paired(genome)                          # (256, 3)
    eff = (_LEAF_SIGNS * SLOT_SCALE[:, None])[:, None, :, None] * _LEAF_DELTAS[None]
    new_leaves = leaves[None, None] + eff                        # (127,12,256,3)
    ids = oklab_bin(new_leaves).reshape(N_VOCAB, N_LEAVES)
    occm = np.zeros((N_VOCAB, N_CELLS), dtype=bool)
    occm[np.arange(N_VOCAB)[:, None], ids] = True
    return _shaped_from_occupancy(board, occm, ids)


def policy_target(vals: np.ndarray, tau: float = 0.02) -> np.ndarray:
    """Oracle policy distribution: top-k=8 by one-step value, softmax(v/τ)
    renormalised over the k (zeros elsewhere) — the mkAtlasOracle discipline."""
    idx = np.argpartition(-vals, TOP_K)[:TOP_K]
    z = np.exp((vals[idx] - vals[idx].max()) / tau)
    t = np.zeros(N_VOCAB, dtype=np.float32)
    t[idx] = (z / z.sum()).astype(np.float32)
    return t


# ── Board → extended GMM tokens (doc §2 `tokens` [≤4096, 13]) ──────────────
def tokens_of(board: np.ndarray, genome: np.ndarray) -> np.ndarray:
    """Occupied bins → (T,13) tokens. Base 10 dims follow the GMM token σ-mask
    [F,T,T,F,T,T,F,F,F,F]: dims 1,2,4,5 are chroma (negate under σ — bin
    centres mirror i→15−i off-boundary); dim 9 is the Σ=1 pool weight (the
    existing pooled[:,9] convention). Cols 10..12 are the σ-INVARIANT curation
    scalars ch3/ch4/ch5 (the φ′ extension)."""
    occ_ids = np.flatnonzero((board[:, 0] > 0) | (board[:, 5] > 0))
    c = bin_center(occ_ids)
    m0 = board[occ_ids, 0]
    w = m0 / max(m0.sum(), 1e-12)
    ch2 = np.bincount(oklab_bin(reconstruct_paired(genome)),
                      minlength=N_CELLS) / N_LEAVES
    tok = np.zeros((len(occ_ids), ATLAS_TOKEN_DIM), dtype=np.float32)
    tok[:, 0] = c[:, 0]                  # L centre        (σ-fixed)
    tok[:, 1] = c[:, 1]                  # a centre        (σ-negated)
    tok[:, 2] = c[:, 2]                  # b centre        (σ-negated)
    tok[:, 3] = m0                       # ch0 mass        (σ-fixed)
    tok[:, 4] = c[:, 1] * m0             # chroma moment   (σ-negated)
    tok[:, 5] = c[:, 2] * m0             # chroma moment   (σ-negated)
    tok[:, 6] = board[occ_ids, 1]        # ch1 pixel mass  (σ-fixed)
    tok[:, 7] = ch2[occ_ids]             # ch2 coverage    (σ-fixed)
    tok[:, 8] = 0.0                      # reserved        (σ-fixed)
    tok[:, 9] = w                        # pool weight     (σ-fixed, Σ=1)
    tok[:, 10] = board[occ_ids, 3]       # ch3 weightField (σ-invariant ext)
    tok[:, 11] = board[occ_ids, 4]       # ch4 killMask    (σ-invariant ext)
    tok[:, 12] = board[occ_ids, 5]       # ch5 anchorMask  (σ-invariant ext)
    return tok


# ── Self-checks (run: uv run python atlas_synth.py) ────────────────────────
def _self_check() -> None:
    assert N_VOCAB == 1524, N_VOCAB                       # lawVocab1524
    # okLabBin pins (mirror Coverage.hs golden cases incl. clamping)
    assert oklab_bin(np.array([0.0, -0.5, -0.5])) == 0
    assert oklab_bin(np.array([1.0, 0.5, 0.5])) == N_CELLS - 1
    assert oklab_bin(np.array([5.0, 5.0, 5.0])) == N_CELLS - 1
    assert oklab_bin(np.array([0.5, 0.0, 0.0])) == 8 * 256 + 8 * 16 + 8
    rng = np.random.default_rng(7)
    # analyze ∘ reconstruct round-trip (generators)
    gens = rng.normal(0.4, 0.2, (N_GENERATORS, 3))
    assert np.allclose(reconstruct_paired(analyze_paired(gens))[0::2], gens)
    # σ-pairing: odd leaves are σ of even leaves
    leaves = reconstruct_paired(rng.normal(0, 0.05, GENOME_DOF))
    assert np.allclose(leaves[1::2], leaves[0::2] * _SIG)
    # lookahead linearity == explicit applyMove, on a handful of moves
    sess = sample_session(3)
    g0 = maximin_collapse(sess)
    la = lookahead_values(sess.board, g0)
    for slot, dk in [(0, 2), (13, 7), (126, 11)]:
        explicit = shaped_value(sess.board, apply_vocab_move(g0, slot, dk))
        assert abs(la[slot * N_DELTAS + dk] - explicit) < 1e-12, (slot, dk)
    t = policy_target(la)
    assert abs(t.sum() - 1.0) < 1e-6 and (t > 0).sum() <= TOP_K
    tok = tokens_of(sess.board, g0)
    assert tok.shape[1] == ATLAS_TOKEN_DIM and abs(tok[:, 9].sum() - 1.0) < 1e-5
    print(f"atlas_synth self-check OK — vocab={N_VOCAB}, "
          f"occupied bins={tok.shape[0]}, root value={shaped_value(sess.board, g0):.4f}")


if __name__ == "__main__":
    _self_check()
