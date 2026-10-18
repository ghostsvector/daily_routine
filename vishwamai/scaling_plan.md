# VishwamAI scaling plan (estimates, not measurements)

Sizes are computed from the notebook's architecture formulas (vocab 40,960, head_dim 64, tied embeddings,
router + norms included, MTP heads excluded). The `base` row reproduces the real model: 132.7M total / 54.9M active.
Memory = fp32 params + Adam (16 bytes/param), before activations. Tokens = 20 x active params (a rough
heuristic; MoE models usually want more). FLOPs = 6 x active x tokens. A100 time assumes 40% MFU at bf16.

| preset | d / layers / experts / top-k | total | active | train state | tokens | FLOPs | A100-days |
|---|---|---|---|---|---|---|---|
| base (done, uploaded) | 512 / 12 / 8 / 2 | 0.13B | 0.055B | 2 GB | 1.1B | 3.6e17 | ~0 |
| medium | 768 / 16 / 16 / 2 | 0.66B | 0.132B | 11 GB | 2.6B | 2.1e18 | ~0.2 |
| large | 1024 / 24 / 32 / 4 | 3.43B | 0.521B | 55 GB | 10.4B | 3.3e19 | ~3 |
| xl (new) | 1536 / 28 / 64 / 4 | 15.0B | 1.16B | 240 GB | 23B | 1.6e20 | ~15 |
| xxl (new) | 2048 / 32 / 64 / 4 | 26.2B | 2.03B | 419 GB | 41B | 5.0e20 | ~46 |

Notes
* The notebook labels `large` "~2.6B"; the formulas give 3.4B total.
* The current training code is data-parallel only (one `data` mesh axis, full replica per device).
  `medium` fits one 24-40 GB GPU. `large` and above need parameter/optimizer sharding (FSDP) and expert
  parallelism, which is not implemented yet.
* Data is the other limit: the shards built so far hold about 0.43B tokens, so even `medium` needs ~6x more.
* Keep the 40,960 tokenizer for every preset so checkpoints and exports stay compatible.
* A bigger model cannot be initialised from the base weights without a growth method; plan on fresh pre-training.
