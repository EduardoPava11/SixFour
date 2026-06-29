# SixFour — 5-Hour Full-Model Training Regimen (the meaningful scene set)

2026-06-28. How to train the FULL model (the 18.9M-param ViT JepaHead, `train_loop.py`
`train_persistent`) for ~5 hours on a corpus that genuinely carries learnable signal, with
checkpoint/resume so you can stop and continue.

## The set: `scene_corpus.py` (coherent, capture-shaped, learnable)

The trainer's gain is **smoothness-proportional** (`jepa_synth_octants.py:224`): on the Zig
`synth_burst` noise kinds the within-octant DETAIL is random and unlearnable; on COHERENT scenes it
is a function of position/motion and can be learned. `scene_corpus.scene_burst(seed, kind)` makes
`(64, 4096, 3)` Q16 OKLab bursts (the exact shape/dtype of `synth_burst`) with low-frequency,
temporally-coherent content, routed through the SAME 256-colour `quantize_frame` as a real capture —
so a scene clip is **structurally a real capture**, only the content is coherent instead of noise.

Kinds (gamut-clamped L∈[5243,60293], a,b∈±18350 Q16):
`scene-gradient` (drifting affine gradients), `scene-blob` (moving Gaussian bumps),
`scene-edge` (translating soft edges — strongest learnable within-octant detail),
`scene-waves` (low-freq drifting sinusoids), `scene-mixed` (a blend).

Self-check: `python3 mlx/scene_corpus.py` (gamut + temporal coherence + detail-present, all PASS).

### What actually learns (honest)
- **Value (colour) + content + cell (mean field): LEARNING.** Validated COLLAPSE→LEARNING in 300
  steps / 32 s: cell margin **+99.5%**, value **+94.9%**, collapse-guard clean. The model learns to
  reconstruct realistic colour/content above the floor.
- **Cell margin saturates fast and is mean-dominated** — both scenes and noise reach +99% on it, so it
  is NOT the discriminator. It confirms the mean field is easy.
- **Within-octant DETAIL (the super-res frontier): not yet beating its near-zero floor**, but on scenes
  it is *learnable in principle* (the margin climbs steeply with training) whereas on noise it is random.
  This is the real target of a long run; track the `detail` line in the dashboard.

## The 5-hour run (resumable, checkpointing, fresh data)

Throughput (MEASURED, not the warm-burst estimate): instantaneous ~3–4 steps/s, but the long-run
AVERAGE is ~1.2–2 steps/s once the every-2000 held-evals and every-1500 corpus resamples are amortized
(and mild thermal throttling). So **5 h ≈ ~20–40k steps**, NOT 200k — the 200k cap just means the run
never self-stops; you Ctrl-C at 5 h with a current checkpoint. The model converges on colour/cell fast
(see below), so the step count is not the bottleneck. Checkpoints every 2000 steps make it resumable;
fresh scenes every 1500 steps learn the DISTRIBUTION, not one clip; early-stop is OFF (we want the long
detail tail). NOTE: stdout is block-buffered to `run.log` (the live dashboards don't appear until the
buffer flushes) — use `eval_checkpoint.py` (below) for the verdict on demand, or add `python3 -u` to the
launch for unbuffered streaming on the next run.

### Watch the verdict any time (stdout is buffered)
```bash
.venv/bin/python mlx/eval_checkpoint.py --ckpt out/scene5h/head.safetensors
```
Prints VERDICT + cell/detail/value margins for the latest checkpoint. Measured trajectory of the
DETAIL frontier (the only metric that matters once colour saturates): −78336% (init) → −499% (step 300)
→ **−21.9% (step 4000)** — climbing toward and expected to cross 0% (positive = inventing real detail).

```bash
cd ~/SixFour/trainer
.venv/bin/python mlx/train_loop.py --long \
  --steps 200000 \
  --resample-every 1500 \
  --save-every 2000 --eval-every 2000 \
  --octants 96 --eval-octants 96 \
  --w-detail 0.3 \
  --kinds scene-gradient,scene-blob,scene-edge,scene-waves,scene-mixed \
  --out out/scene5h --seed 0
```

- **Monitor:**  `tail -f out/scene5h/loss.jsonl`  (per-step composite + held-out evals), and watch the
  `=== EVAL @ step … :: LEARNING ===` dashboards in stdout (cell / detail / value margins + VICReg guard + ETA).
- **Stop any time:** Ctrl-C. The last checkpoint is `out/scene5h/head.safetensors` (+ `.meta.json`).
- **Resume:**  add `--resume out/scene5h/head.safetensors` to the same command (continues at the saved step).
- **Knobs:** raise `--w-detail` (e.g. 0.5–1.0) to push the detail frontier harder; `--lr` default 1e-3 is the
  stable value (8e-3 NaNs — the "lr trap"); `--weight-decay` 1e-4 bounds the over-capacity ViT.

## Verdicts you'll see (`dashboard_verdict`)
`LEARNING` (primary margin beats the zero-floor by >2%) · `AT FLOOR` · `FLOORED` (worse than zero) ·
`COLLAPSE` (VICReg variance floor tripped — only expected at step 0 init) · `DIVERGED` (NaN — lr too hot).

## Provenance
The corpus is structurally a real capture and inter-operates with the new capture-format pipeline
(`Spec.CaptureFormat`, `gif_to_capture.py`): when you export real bursts from the app, `import_app_gif`
turns them into the same 64³ capture shape these scenes mimic, so swapping real captures in later is a
drop-in (`--kinds` → a real-capture loader). Until then, scenes are the meaningful stand-in.
