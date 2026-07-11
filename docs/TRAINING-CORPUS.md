# TRAINING CORPUS — device captures → AirDrop → Mac trainer

> Status: LIVE · Created: 2026-07-11 · Flag: `Feature.trainingCorpus` (ON)
> App writer: `SixFour/Train/TrainingCorpus.swift` · Mac reader: `trainer/corpus_ingest.py`
> Tests: `SixFourTests/TrainingCorpusTests.swift` + `python3 trainer/corpus_ingest.py` (self-check)

## Why

Every "real phone data" training path was blocked on the same missing artifact: a corpus of
REAL captures on the Mac. `MetaInit.deployedW0` ships a synthetic stand-in "until real
AirDropped bursts supply the corpus" (`Feature.metaInitW0` OFF for exactly that reason); the
trainer's ingest modules (`v21_ingest.py`, `gif_to_capture.py`) were validated but had nothing
real to read; and the per-capture training substrate the phone manufactures — the θ_up gene,
the S_t band-head outcome, the drained t-band pairs — was computed and DROPPED at the burst
seam. This closes the loop: persist per capture, batch-export over AirDrop, ingest on the Mac.

## What the phone writes (per capture, shared stem, in Documents/)

| Artifact | Contents |
|---|---|
| `sixfour_<stamp>.gif` | the collapse (unchanged) |
| `sixfour_<stamp>.s4cr` | the shutter's ledger (unchanged; deterministic CBOR, `Spec.CaptureRecord`) |
| `sixfour_<stamp>.contact.png` | thumbnail contact sheet (unchanged) |
| **`sixfour_<stamp>.volume.npy`** | NEW — the burst as int32 Q16 OKLab, shape `(frames, side, side, 3)`, C order, LE. This is `CaptureGene.volume(from:)` — byte-identical to what the on-device somatic trainer consumed (zero train/deploy skew). |
| **`sixfour_<stamp>.train.json`** | NEW — schema `sixfour.corpus.capture/1`: shipped θ_up gene (absent == floor), band-head outcome (initial/final MSE + weights), per-slot certified halt orders, drained t-band pairs (the yin ladder's labels, pre-subsample), color-space tag, build SHA. |

**Raw-volume-first is the design rule**: derived features (octant pairs, root-chart bands, any
future basis) are re-manufactured Mac-side from the volume with the shared kernels — never
trusted from disk — so the corpus survives model pivots. The sidecar carries the device's
*verdicts* (what the phone's own training saw), not the substrate.

Documents/ is Files-app visible (`UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`,
Info.plist), so individual artifacts can also be pulled by cable/Files without the app.

## The AirDrop batch (the CORPUS button)

On the Done screen (`DonePhaseField`), when at least one capture has a persisted volume:
**CORPUS (N)** stages every capture's artifacts + `corpus_manifest.json` (schema
`sixfour.corpus/1`: createdAt, buildSHA, per-stem file lists) into one folder and zips it via
`NSFileCoordinator` `.forUploading` (Apple system facility — the zero-third-party rule stands),
then presents the share sheet → AirDrop `SixFour-corpus.zip` to the Mac.

## Mac ingest

```bash
unzip SixFour-corpus.zip
python3 trainer/corpus_ingest.py            # self-check
python3 -c "
from trainer.corpus_ingest import load_corpus, volumes_as_bursts
caps = load_corpus('SixFour-corpus')        # manifest-first, shape-validated
bursts = volumes_as_bursts(caps)            # (frames, side*side, 3) — the synth-burst shape
"
```

`volumes_as_bursts` returns the exact pixel-tensor shape the synthetic corpus produces
(`native_kernels.synth_burst` / `mlx.scene_corpus.scene_burst`), so real captures drop into
every existing consumer (`mlx/jepa_synth_octants.py` octant records, θ_up pair manufacture).
`load_s4cr` decodes the ledger (deterministic-CBOR subset only, hard error otherwise; parity
against the pinned `Spec.CaptureRecord` golden bytes verified). Sidecar JSON is returned as a
plain dict.

## Async assembly (app-side, for the curious)

The sidecar is born at burst commit and re-persisted as the async arrivals land (the θ_up gene
and band-head result are trained OFF the capture seam): commit merges anything already parked,
later arrivals re-attach and atomically rewrite `train.json`. All best-effort background writes
(the `saveBundleAsync` pattern) — no GIF byte depends on any of it, and `Feature.trainingCorpus
= false` restores exactly the previous disk footprint.

## Next (not built)

- **Real-corpus W₀** (`trainer/`): octant pairs from corpus volumes (reuse the jepa lift) →
  `MetaInit.reptile`-equivalent → `metainit-w0.bin` Resource → flip `Feature.metaInitW0` after
  held-out validation (few-step-from-W₀ must beat few-step-from-zero on REAL captures).
- **Corpus loader as `--kinds real:<dir>`** in `mlx/cli.py` (the SCENE-REGIMEN drop-in).
- **`.s4cr` v2 cubes in training**: derived t-band re-manufacture from `c64`/`c16` streams for
  bursts whose sidecar pairs were capped (`maxRetainedPairs`).
