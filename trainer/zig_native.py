"""zig_native.py — ctypes binding to the SixFour native Zig core (the trainer's
synthetic-GIF DATA ENGINE).

HAND-WRITTEN trainer tooling (NOT generated). The look-NN trainer has no captured
data (trainer/data/ is empty), so we generate it: this module loads the host build
of libsixfour_native (Native/zig-out/lib/libsixfour_native.dylib) and exposes the
deterministic kernels —

    s4_synth_burst        procedural OKLab Q16 burst (seed-deterministic)
    s4_quantize_frame     per-frame 256-colour palette + indices (maximin+Lloyd)
    s4_palette_oklab_to_srgb8 / s4_gif_assemble   OKLab → sRGB8 → GIF89a

— so the per-frame palettes the trainer learns from are produced by the SAME code
the iPhone runs (build-ios.sh compiles the identical root.zig). No train/deploy
skew. The high-level `synth_sample()` returns one labeled burst as numpy arrays.

Build the dylib first:  `cd Native && zig build`  (this module will also auto-build
it on import if it is missing and `zig` is on PATH).
"""
from __future__ import annotations

import ctypes
import subprocess
from dataclasses import dataclass
from pathlib import Path

import numpy as np

# ── shape contract (mirror Native/src/kernels.zig + spec) ──────────────────────
Q16 = 1 << 16          # OKLab Q16 scale (kernels.zig Q16_ONE)
FRAME_COUNT = 64       # frames per burst   (kernels.zig FRAME_COUNT)
SIDE = 64              # 64×64 frame        (kernels.zig SIDE)
K = 256                # palette entries    (kernels.zig K)

SYNTH_COLOR = 0        # sixfour_native.h S4_SYNTH_COLOR
SYNTH_GRAYSCALE = 1    # sixfour_native.h S4_SYNTH_GRAYSCALE
RC_OK = 0

# Default grey dynamic range [Lmin,Lmax] + chroma bound (Q16) — mirror synth.zig
# L_MIN/L_MAX/CHROMA. L SETS the dynamic range; pass narrower spans to exercise it.
L_MIN_Q16 = 5243       # ≈0.08
L_MAX_Q16 = 60293      # ≈0.92
CHROMA_MAX_Q16 = 18350  # ≈0.28

_NATIVE = Path(__file__).resolve().parent.parent / "Native"
_DYLIB = _NATIVE / "zig-out" / "lib" / "libsixfour_native.dylib"


def _load() -> ctypes.CDLL:
    if not _DYLIB.exists():
        # Best-effort auto-build; surfaces a clear error if zig is absent.
        try:
            subprocess.run(["zig", "build"], cwd=_NATIVE, check=True)
        except (FileNotFoundError, subprocess.CalledProcessError) as e:
            raise RuntimeError(
                f"{_DYLIB} not found and `zig build` failed ({e}). "
                f"Run `cd {_NATIVE} && zig build` first."
            ) from e
    lib = ctypes.CDLL(str(_DYLIB))

    c_i32, c_i32p, c_u8p = ctypes.c_int32, ctypes.POINTER(ctypes.c_int32), ctypes.POINTER(ctypes.c_uint8)
    c_szp, c_void, c_sz = ctypes.POINTER(ctypes.c_size_t), ctypes.c_void_p, ctypes.c_size_t

    lib.s4_synth_burst.restype = c_i32
    lib.s4_synth_burst.argtypes = [
        ctypes.c_uint64, c_i32, c_i32, c_i32, c_i32, c_i32, c_i32, c_i32p,
    ]

    lib.s4_quantize_frame.restype = c_i32
    lib.s4_quantize_frame.argtypes = [c_i32p, c_i32, c_i32, c_i32, c_i32p, c_u8p, c_void, c_sz]

    lib.s4_palette_oklab_to_srgb8.restype = c_i32
    lib.s4_palette_oklab_to_srgb8.argtypes = [c_i32p, c_i32, c_u8p, c_void, c_sz]

    lib.s4_gif_assemble.restype = c_i32
    lib.s4_gif_assemble.argtypes = [
        c_u8p, c_u8p, c_i32, c_i32, c_i32, ctypes.c_uint16, c_u8p, c_i32, c_u8p, c_sz, c_szp,
    ]

    lib.s4_gif_encode_burst_bound.restype = c_sz
    lib.s4_gif_encode_burst_bound.argtypes = [c_i32, c_i32, c_i32]

    lib.s4_gif_decode_scratch_bytes.restype = c_sz
    lib.s4_gif_decode_scratch_bytes.argtypes = [c_sz]

    lib.s4_gif_decode.restype = c_i32
    lib.s4_gif_decode.argtypes = [
        c_u8p, c_sz, c_u8p, c_u8p, c_i32p, c_i32p, c_i32p, c_void, c_sz,
    ]

    lib.s4_srgb8_to_oklab_q16.restype = c_i32
    lib.s4_srgb8_to_oklab_q16.argtypes = [c_u8p, c_i32, c_i32p]
    return lib


_LIB = _load()


def _i32p(a: np.ndarray):
    return a.ctypes.data_as(ctypes.POINTER(ctypes.c_int32))


def _u8p(a: np.ndarray):
    return a.ctypes.data_as(ctypes.POINTER(ctypes.c_uint8))


# ── thin kernel wrappers ───────────────────────────────────────────────────────
def synth_burst(seed: int, mode: int, frame_count: int = FRAME_COUNT, side: int = SIDE,
                l_min_q16: int = L_MIN_Q16, l_max_q16: int = L_MAX_Q16,
                chroma_max_q16: int = CHROMA_MAX_Q16) -> np.ndarray:
    """(frame_count, side*side, 3) int32 OKLab Q16 burst, deterministic in seed.
    L anchors span [l_min_q16, l_max_q16] (the grey dynamic range); a,b are signed
    deviations within ±chroma_max_q16."""
    out = np.empty((frame_count, side * side, 3), dtype=np.int32)
    rc = _LIB.s4_synth_burst(ctypes.c_uint64(seed), mode, frame_count, side,
                             l_min_q16, l_max_q16, chroma_max_q16, _i32p(out))
    if rc != RC_OK:
        raise RuntimeError(f"s4_synth_burst rc={rc}")
    return out


def quantize_frame(oklab_q16: np.ndarray, k: int = K, lloyd_iters: int = 3):
    """One frame (p,3) int32 OKLab Q16 → (centroids (k,3) int32 Q16, indices (p,) uint8)."""
    oklab_q16 = np.ascontiguousarray(oklab_q16, dtype=np.int32)
    p = oklab_q16.shape[0]
    centroids = np.empty((k, 3), dtype=np.int32)
    indices = np.empty(p, dtype=np.uint8)
    need = p * 8 + 3 * k * 8 + k * 4  # kernels.zig: p·i64 + 3k·i64 + k·i32
    scratch = (ctypes.c_uint8 * need)()
    rc = _LIB.s4_quantize_frame(
        _i32p(oklab_q16), p, k, lloyd_iters, _i32p(centroids), _u8p(indices),
        ctypes.cast(scratch, ctypes.c_void_p), need,
    )
    if rc != RC_OK:
        raise RuntimeError(f"s4_quantize_frame rc={rc}")
    return centroids, indices


def palette_to_srgb8(centroids_q16: np.ndarray) -> np.ndarray:
    """(k,3) int32 OKLab Q16 centroids → (k,3) uint8 sRGB8 (the GIF colour table)."""
    centroids_q16 = np.ascontiguousarray(centroids_q16, dtype=np.int32)
    k = centroids_q16.shape[0]
    rgb = np.empty((k, 3), dtype=np.uint8)
    rc = _LIB.s4_palette_oklab_to_srgb8(_i32p(centroids_q16), k, _u8p(rgb), None, 0)
    if rc != RC_OK:
        raise RuntimeError(f"s4_palette_oklab_to_srgb8 rc={rc}")
    return rgb


def gif_assemble(indices: np.ndarray, palettes_rgb: np.ndarray, side: int = SIDE,
                 k: int = K, frame_delay_cs: int = 5) -> bytes:
    """(F,p) uint8 indices + (F,k,3) uint8 palettes → GIF89a bytes."""
    indices = np.ascontiguousarray(indices, dtype=np.uint8)
    palettes_rgb = np.ascontiguousarray(palettes_rgb, dtype=np.uint8)
    frame_count = indices.shape[0]
    bound = _LIB.s4_gif_encode_burst_bound(frame_count, side, k)
    out = (ctypes.c_uint8 * bound)()
    out_len = ctypes.c_size_t(0)
    rc = _LIB.s4_gif_assemble(
        _u8p(indices), _u8p(palettes_rgb), frame_count, side, k, frame_delay_cs,
        None, 0, ctypes.cast(out, ctypes.POINTER(ctypes.c_uint8)), bound, ctypes.byref(out_len),
    )
    if rc != RC_OK:
        raise RuntimeError(f"s4_gif_assemble rc={rc}")
    return bytes(out[: out_len.value])


# ── GIF decode: a GIF can BE an input (inverse of gif_assemble) ────────────────
def gif_decode(gif: bytes):
    """Decode a GIF89a → (indices (F,P) uint8, palettes_rgb (F,K,3) uint8, frame_count, side, k).
    Shape-probe first (null outputs) to size buffers, then full decode."""
    buf = (ctypes.c_uint8 * len(gif)).from_buffer_copy(gif)
    bptr = ctypes.cast(buf, ctypes.POINTER(ctypes.c_uint8))
    fc, side, k = ctypes.c_int32(0), ctypes.c_int32(0), ctypes.c_int32(0)
    rc = _LIB.s4_gif_decode(bptr, len(gif), None, None,
                            ctypes.byref(fc), ctypes.byref(side), ctypes.byref(k), None, 0)
    if rc != RC_OK:
        raise RuntimeError(f"s4_gif_decode (probe) rc={rc}")
    F, S, Kk = fc.value, side.value, k.value
    p = S * S
    indices = np.empty((F, p), dtype=np.uint8)
    palettes = np.empty((F, Kk, 3), dtype=np.uint8)
    need = _LIB.s4_gif_decode_scratch_bytes(len(gif))
    scratch = (ctypes.c_uint8 * need)()
    rc = _LIB.s4_gif_decode(bptr, len(gif), _u8p(indices), _u8p(palettes),
                            ctypes.byref(fc), ctypes.byref(side), ctypes.byref(k),
                            ctypes.cast(scratch, ctypes.c_void_p), need)
    if rc != RC_OK:
        raise RuntimeError(f"s4_gif_decode (full) rc={rc}")
    return indices, palettes, F, S, Kk


def srgb8_to_oklab_q16(rgb: np.ndarray) -> np.ndarray:
    """(k,3) uint8 sRGB8 → (k,3) int32 OKLab Q16 (inverse of palette_to_srgb8; lossy)."""
    rgb = np.ascontiguousarray(rgb, dtype=np.uint8)
    k = rgb.shape[0]
    out = np.empty((k, 3), dtype=np.int32)
    rc = _LIB.s4_srgb8_to_oklab_q16(_u8p(rgb), k, _i32p(out))
    if rc != RC_OK:
        raise RuntimeError(f"s4_srgb8_to_oklab_q16 rc={rc}")
    return out


def gif_to_tokens(gif: bytes) -> np.ndarray:
    """A GIF → its pooled (F·K, 10) GMM-token tensor — a PURE FUNCTION of the GIF
    bytes (the device sees nothing else). The Python twin of Haskell
    SixFour.Gen.AxisInput.decodedGifToTokenSet: per palette slot,
    μ = srgb8→oklab(slot) (lossy decode), Σ = 0 (a GIF carries no covariance —
    the degenerate-token contract), w = slot pixel population; pooled and
    renormalised to Σw = 1. THIS is "tensor of a GIF" — the look-NN input."""
    idx, pal_rgb, F, S, Kk = gif_decode(gif)
    toks = np.zeros((F, Kk, GMM_TOKEN_DIM), dtype=np.float64)
    for f in range(F):
        toks[f, :, 0:3] = srgb8_to_oklab_q16(pal_rgb[f]).astype(np.float64) / Q16  # μ (Σ stays 0)
        toks[f, :, 9] = np.bincount(idx[f].astype(np.int64), minlength=Kk).astype(np.float64)
    pooled = toks.reshape(-1, GMM_TOKEN_DIM)
    w = pooled[:, 9].sum()
    if w > 0:
        pooled[:, 9] /= w
    return pooled


# ── GMM tokens: the ACTUAL look-NN input type (mirror Spec/GMM.hs) ──────────────
# The app feeds the NN per-frame ClusterStatistics → 10-D GMM tokens, NOT centroids
# + indices. Token = [μL,μa,μb, ΣLL,ΣLa,ΣLb,Σaa,Σab,Σbb, w] (Spec/GMM.hs:67,
# ClusterStatistics.swift:50). Σ = E[xxᵀ]−μμᵀ over assigned pixels (population);
# empty clusters carry identity·1e-6 (ClusterStatistics.swift:56). We compute these
# from the synthetic pixels + the s4_quantize_frame assignment so the synthetic
# training input is the SAME TYPE the device produces.
GMM_TOKEN_DIM = 10
_EMPTY_COV = np.array([1e-6, 0.0, 0.0, 1e-6, 0.0, 1e-6], dtype=np.float64)
# Upper-triangle index pairs (LL,La,Lb,aa,ab,bb) into a 3-vector's components.
_UT_I = np.array([0, 0, 0, 1, 1, 2])
_UT_J = np.array([0, 1, 2, 1, 2, 2])


def frame_gmm_tokens(oklab_q16_frame: np.ndarray, centroids_q16: np.ndarray,
                     indices: np.ndarray) -> np.ndarray:
    """One frame → (k, 10) float64 GMM tokens. μ = centroid (float OKLab), Σ =
    E[xxᵀ]−μμᵀ over assigned pixels (upper-tri), w = cluster pixel count (raw;
    pooling renormalises). Mirrors Spec/GMM.hs gaussianToken + ClusterStatistics."""
    x = oklab_q16_frame.astype(np.float64) / Q16          # (p, 3) float OKLab
    mu = centroids_q16.astype(np.float64) / Q16           # (k, 3)
    k = mu.shape[0]
    idx = indices.astype(np.int64)

    counts = np.bincount(idx, minlength=k).astype(np.float64)        # (k,)
    # Centered form Σ(x−μ)(x−μ)ᵀ/count — the numerically-stable, guaranteed-PSD
    # computation of E[xxᵀ]−μμᵀ (Spec/GMM.hs / ClusterStatistics.swift:53). μ is
    # the cluster centroid; centering on it avoids catastrophic cancellation.
    dx = x - mu[idx]                                                 # (p, 3) centered pixels
    prod = dx[:, _UT_I] * dx[:, _UT_J]                               # (p, 6) (x−μ)(x−μ)ᵀ upper-tri
    sum6 = np.zeros((k, 6), dtype=np.float64)
    np.add.at(sum6, idx, prod)
    nz = counts > 0
    cov6 = np.zeros((k, 6), dtype=np.float64)
    cov6[nz] = sum6[nz] / counts[nz, None]
    cov6[~nz] = _EMPTY_COV                                           # empty-cluster convention

    tokens = np.empty((k, GMM_TOKEN_DIM), dtype=np.float64)
    tokens[:, 0:3] = mu
    tokens[:, 3:9] = cov6
    tokens[:, 9] = counts
    return tokens


# ── high-level: one labeled training sample ────────────────────────────────────
@dataclass
class Burst:
    """One synthetic capture: the look-NN INPUT (per-frame palettes) + the rendered GIF.

    oklab_q16     (F, p, 3) int32 — raw OKLab Q16 pixels (the quantiser input)
    palettes_q16  (F, k, 3) int32 — per-frame palette centroids in OKLab Q16  ← NN input source
    indices       (F, p)    uint8 — per-frame palette indices
    palettes_rgb  (F, k, 3) uint8 — per-frame sRGB8 colour tables
    gif           bytes           — the assembled GIF89a (verification artifact)
    """
    oklab_q16: np.ndarray
    palettes_q16: np.ndarray
    indices: np.ndarray
    palettes_rgb: np.ndarray
    gif: bytes

    def palettes_oklab(self) -> np.ndarray:
        """Per-frame palettes as float OKLab (F, k, 3): L∈[0,1], a,b∈[-0.5,0.5]."""
        return self.palettes_q16.astype(np.float64) / Q16

    def gmm_tokens(self) -> np.ndarray:
        """(F, k, 10) per-frame GMM tokens — the ACTUAL look-NN input type."""
        f, k = self.palettes_q16.shape[0], self.palettes_q16.shape[1]
        out = np.empty((f, k, GMM_TOKEN_DIM), dtype=np.float64)
        for i in range(f):
            out[i] = frame_gmm_tokens(self.oklab_q16[i], self.palettes_q16[i], self.indices[i])
        return out

    def pooled_tokens(self) -> np.ndarray:
        """(F·k, 10) pooled capture tokens, weights renormalised to sum 1
        (poolGMM = normalizeGMM . concat, Spec/GMM.hs:101). F·k = MAX_TOKENS=16384.
        This is the permutation-invariant set the look-NN encoder sum-pools."""
        toks = self.gmm_tokens().reshape(-1, GMM_TOKEN_DIM)
        w = toks[:, 9].sum()
        if w > 0:
            toks[:, 9] /= w
        return toks


def synth_sample(seed: int, mode: int = SYNTH_GRAYSCALE,
                 frame_count: int = FRAME_COUNT, side: int = SIDE,
                 k: int = K, lloyd_iters: int = 3,
                 l_min_q16: int = L_MIN_Q16, l_max_q16: int = L_MAX_Q16,
                 chroma_max_q16: int = CHROMA_MAX_Q16) -> Burst:
    """Generate one labeled burst end-to-end through the production Zig kernels.
    `[l_min_q16, l_max_q16]` is the grey dynamic range L spans (L SETS the range).

    Default mode is GRAYSCALE — the Milestone-L training data (a=b=0 exactly)."""
    oklab = synth_burst(seed, mode, frame_count, side, l_min_q16, l_max_q16, chroma_max_q16)
    p = side * side
    palettes_q16 = np.empty((frame_count, k, 3), dtype=np.int32)
    indices = np.empty((frame_count, p), dtype=np.uint8)
    palettes_rgb = np.empty((frame_count, k, 3), dtype=np.uint8)
    for f in range(frame_count):
        cen, idx = quantize_frame(oklab[f], k, lloyd_iters)
        palettes_q16[f] = cen
        indices[f] = idx
        palettes_rgb[f] = palette_to_srgb8(cen)
    gif = gif_assemble(indices, palettes_rgb, side, k)
    return Burst(oklab, palettes_q16, indices, palettes_rgb, gif)


# ── smoke test / data-gen demo ──────────────────────────────────────────────────
if __name__ == "__main__":
    import sys

    out_dir = Path(__file__).resolve().parent / "out"
    out_dir.mkdir(parents=True, exist_ok=True)

    b = synth_sample(seed=42, mode=SYNTH_GRAYSCALE)
    pal = b.palettes_oklab()

    # Determinism: regenerating with the same seed is bit-identical.
    b2 = synth_sample(seed=42, mode=SYNTH_GRAYSCALE)
    assert np.array_equal(b.palettes_q16, b2.palettes_q16), "synth not deterministic"

    # Grayscale invariant: chroma is exactly zero through quantization.
    assert np.all(b.palettes_q16[..., 1:] == 0), "grayscale chroma leaked"
    # sRGB8 table is neutral grey (R=G=B).
    assert np.all(b.palettes_rgb[..., 0] == b.palettes_rgb[..., 1]) and \
           np.all(b.palettes_rgb[..., 1] == b.palettes_rgb[..., 2]), "not neutral grey"
    # Temporal drift: frame 0 and the midpoint frame have different palettes.
    assert not np.array_equal(b.palettes_q16[0], b.palettes_q16[FRAME_COUNT // 2]), "no temporal drift"

    # NN input type: per-frame GMM tokens (F,K,10) and pooled capture set (16384,10).
    toks = b.gmm_tokens()
    pooled = b.pooled_tokens()
    assert toks.shape == (FRAME_COUNT, K, GMM_TOKEN_DIM), toks.shape
    assert pooled.shape == (FRAME_COUNT * K, GMM_TOKEN_DIM), pooled.shape  # = MAX_TOKENS
    assert abs(pooled[:, 9].sum() - 1.0) < 1e-9, "pooled weights must sum to 1 (poolGMM)"
    # Grayscale: chroma means AND every Σ term touching a/b are exactly zero.
    assert np.all(toks[..., 1:3] == 0), "grayscale μa,μb leaked"
    assert np.all(toks[..., [4, 5, 6, 7, 8]] == 0), "grayscale chroma covariance leaked"
    # Per-cluster covariance is PSD on L: ΣLL ≥ 0.
    assert np.all(toks[..., 3] >= -1e-12), "negative ΣLL"

    # SOLID-GIF round-trip from Python: a GIF decodes back to its (indices, palettes).
    dec_idx, dec_pal, F, S, Kk = gif_decode(b.gif)
    assert (F, S, Kk) == (FRAME_COUNT, SIDE, K), (F, S, Kk)
    assert np.array_equal(dec_idx, b.indices), "decoded indices != input (round-trip A broken)"
    assert np.array_equal(dec_pal, b.palettes_rgb), "decoded palettes != input (round-trip A broken)"
    # Decoded palette inverts back to OKLab. LOSSY by design (byte round-trip ≠ OKLab
    # round-trip): grey stays NEAR-grey, with only Q16 matrix-rounding residual chroma.
    ok = srgb8_to_oklab_q16(dec_pal[0])
    max_chroma = int(np.max(np.abs(ok[:, 1:])))
    assert max_chroma < 0.02 * Q16, f"decoded grayscale gained real chroma ({max_chroma} Q16)"

    gif_path = out_dir / "synth_grayscale.gif"
    gif_path.write_bytes(b.gif)

    print(f"OK  burst: {FRAME_COUNT}×{SIDE}×{SIDE}, {K} colours/frame")
    print(f"    per-frame L range: [{pal[..., 0].min():.3f}, {pal[..., 0].max():.3f}]")
    print(f"    distinct L per frame (mean): {np.mean([len(np.unique(pal[f, :, 0])) for f in range(FRAME_COUNT)]):.1f}")
    print(f"    NN input: per-frame tokens {toks.shape}, pooled {pooled.shape} (=MAX_TOKENS), Σw={pooled[:,9].sum():.6f}")
    print(f"    token[0,0] = [μL,μa,μb, ΣLL,ΣLa,ΣLb,Σaa,Σab,Σbb, w] = {np.round(toks[0,0], 5).tolist()}")
    print(f"    GIF: {len(b.gif)} bytes -> {gif_path}")
    sys.exit(0)
