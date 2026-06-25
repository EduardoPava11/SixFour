"""The two differentiable delta HEADS (value + policy), the twin of
spec/SixFour/Spec/DeltaSurrogate.hs, plus a small trainer that learns the
data-manufactured temporal targets and a bridge proving the policy commit re-enters
the byte-exact transport of temporal_data.py.

The two carriers fall on OPPOSITE sides of the regression/classification line:

  VALUE head  = REGRESSION. A continuous OKLab displacement per palette slot; decode rounds it
                half-to-even to a ColourDelta; the loss is summed squared OKLab distance. The
                integer target is a FIXPOINT of decode . embed (the relaxation loses nothing).
  POLICY head = CLASSIFICATION. Per-voxel logits over the K palette slots; decode is a per-voxel
                argmax (lowest-index tie-break); the loss is categorical cross-entropy. A slot is
                a categorical label with no metric, so an L2 over slot NUMBERS would be meaningless.

Collapse-safety is INHERITED: both heads regress/classify toward the DATA-MANUFACTURED carriers
(temporal_data.py), which are theta-free, so there is no EMA and no L_close orbit
(RolloutTargetSource = NextFrameData only). THE KEYSTONE lawPolicySurrogateDecodesToTransport: a
head that classifies every voxel correctly decodes to EXACTLY the data-manufactured IndexDelta,
so the continuous head and the integer floor agree at the optimum.
"""
from __future__ import annotations

import os
from math import exp, log

import numpy as np

from temporal_data import index_delta_of, GOLDEN as TEMPORAL_GOLDEN
import json


# ============================================================================
# VALUE head — continuous OKLab regression surrogate
# ============================================================================

def embed_value(colour_delta):
    """Embed an integer ColourDelta [[l,a,b],...] as a continuous surrogate (the target witness)."""
    return [[float(l), float(a), float(b)] for l, a, b in colour_delta]


def decode_value(surrogate):
    """Commit the regression to the byte-exact carrier: round half-to-even (Python round)."""
    return [[round(l), round(a), round(b)] for l, a, b in surrogate]


def value_loss(surrogate, target):
    """Summed squared OKLab distance to the integer target (the regression objective)."""
    return sum((s[0]-t[0])**2 + (s[1]-t[1])**2 + (s[2]-t[2])**2
               for s, t in zip(surrogate, target))


# ============================================================================
# POLICY head — per-voxel categorical (softmax / cross-entropy) surrogate
# ============================================================================

def one_hot_policy(k: int, targets):
    """A one-hot surrogate over K slots (peak 10 at the target slot): the exact-target witness."""
    return [[10.0 if s == t else 0.0 for s in range(k)] for t in targets]


def argmax_first(xs):
    """Argmax with a deterministic LOWEST-INDEX tie-break (no float-order coin-flip)."""
    return xs.index(max(xs)) if xs else 0


def decode_policy(surrogate):
    """Commit the classification: the argmax slot per voxel (the Morton-order index map)."""
    return [argmax_first(row) for row in surrogate]


def softmax(zs):
    m = max(zs)
    es = [exp(z - m) for z in zs]
    s = sum(es)
    return [e / s for e in es]


def policy_loss(surrogate, targets):
    """Summed per-voxel categorical cross-entropy at the target slot."""
    return sum(-log(max(1e-12, softmax(row)[t])) for row, t in zip(surrogate, targets))


# ============================================================================
# Small trainers: learn the data-manufactured targets (numpy GD, the head realizers)
# ============================================================================

def train_value(target, steps: int = 400, eta: float = 0.2):
    """Regression GD on the OKLab L2 toward a ColourDelta target; converges to the exact target."""
    s = np.zeros((len(target), 3))
    t = np.array(target, dtype=float)
    for _ in range(steps):
        s -= eta * 2.0 * (s - t)
    return s.tolist()


def train_policy(targets, k: int, steps: int = 400, eta: float = 0.5):
    """Cross-entropy GD on per-voxel logits toward the data slots; argmax converges to the target."""
    logits = np.zeros((len(targets), k))
    for _ in range(steps):
        # CE gradient at logit j of voxel v: softmax_j - [j == target_v]
        e = np.exp(logits - logits.max(axis=1, keepdims=True))
        p = e / e.sum(axis=1, keepdims=True)
        grad = p.copy()
        for v, t in enumerate(targets):
            grad[v, t] -= 1.0
        logits -= eta * grad
    return logits.tolist()


if __name__ == "__main__":
    fails = 0

    # --- VALUE laws ---
    cd = [[100, 10, -5], [-100, 20, -10], [50, 0, 0]]
    if decode_value(embed_value(cd)) != cd:                            # decodes to carrier (fixpoint)
        print("FAIL: value surrogate does not decode to its carrier"); fails += 1
    if value_loss(embed_value(cd), cd) != 0:                           # loss zero at target
        print("FAIL: value loss nonzero at the exact target"); fails += 1
    # regression: scaling the error by c scales the loss by c^2
    base = [[3, -4, 0], [0, 0, 5]]
    l1 = value_loss([[v*1 for v in c] for c in base], [[0, 0, 0]] * len(base))
    l3 = value_loss([[v*3 for v in c] for c in base], [[0, 0, 0]] * len(base))
    if abs(l3 - 9 * l1) > 1e-9:
        print(f"FAIL: value loss not a squared metric ({l3} != 9*{l1})"); fails += 1

    # --- POLICY laws ---
    # keystone: a one-hot-at-target head decodes to exactly the target index map
    base_idx, target_idx, k = [0, 1, 2, 3], [3, 2, 1, 0], 4
    dec = decode_policy(one_hot_policy(k, target_idx))
    if dec != target_idx:
        print(f"FAIL: policy decode {dec} != target {target_idx}"); fails += 1
    if index_delta_of(base_idx, dec) != index_delta_of(base_idx, target_idx):
        print("FAIL: decoded transport != data-manufactured transport (keystone)"); fails += 1
    # deterministic lowest-index tie-break
    if decode_policy([[1, 3, 3], [5, 2, 2, 2], [0]]) != [1, 0, 0]:
        print("FAIL: policy argmax tie-break not lowest-index"); fails += 1
    # cross-entropy strictly prefers the target slot
    if not (policy_loss(one_hot_policy(4, [2]), [2]) < policy_loss(one_hot_policy(4, [0]), [2])):
        print("FAIL: cross-entropy does not prefer the target slot"); fails += 1

    # --- the heads actually TRAIN to the data-manufactured targets ---
    vt = train_value(cd)
    if decode_value(vt) != cd:
        print(f"FAIL: trained value head did not reach the target ({decode_value(vt)})"); fails += 1
    pt = decode_policy(train_policy(target_idx, k))
    if pt != target_idx:
        print(f"FAIL: trained policy head did not reach the target ({pt})"); fails += 1
    else:
        print(f"  heads train: value -> {decode_value(vt)} exact; policy argmax -> {pt} exact")

    # --- the bridge to the temporal data engine (the keystone on REAL manufactured targets) ---
    g = json.load(open(TEMPORAL_GOLDEN))
    checked = 0
    for r in g["records"]:
        idx_t, idx_n = r["index_t"], r["index_next"]
        kk = len(r["palette_t"])
        decoded = decode_policy(one_hot_policy(kk, idx_n))             # head classifies frame t+1's slots
        manufactured = [list(p) for p in r["policy"]]                  # the temporal golden's IndexDelta
        if index_delta_of(idx_t, decoded) != manufactured:
            print(f"FAIL: policy decode != temporal transport [{r['label']}]"); fails += 1
        checked += 1
    if fails == 0:
        print(f"  transport bridge: policy argmax re-enters the temporal IndexDelta on "
              f"{checked} real frame pairs (no self-produced rollout)")

    print("delta_surrogate: PASS" if fails == 0 else f"delta_surrogate: {fails} FAIL")
    raise SystemExit(1 if fails else 0)
