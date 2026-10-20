# VishwamAI on Gemma 4 31B - plan

Goal: a VishwamAI model derived from Gemma 4 (Apache-2.0, credit Gemma) that is measurably better than plain Gemma 4 on our target skills, with every claim backed by our own held-out measurements.

## Rules (they keep the numbers meaningful)
1. Never train on a benchmark's test questions (MMLU test, MMLU-Pro, GPQA, HLE, AIME 2026, LiveCodeBench, SWE-bench Verified, Terminal-Bench tasks). Train on separate training sets or on our own verified generations.
2. Measure plain Gemma first (the baseline). A tuned score only counts as a gain over that baseline, with an interval.
3. Open models only as teachers; no closed-model outputs (e.g. do not use SWE-smith trajectories that came from Claude).
4. Publish what we measured, including "no change" and "worse".

## Phase 0 - Baselines (before any more training)
Run plain `gemma-4-31B` (4-bit) on: MMLU, MMLU-Pro, GPQA Diamond, a math set, a small code set. Use `lm-evaluation-harness` where tasks exist. Store the numbers in `gemma/results/baseline.json`. On 2xT4 use a subset (e.g. 200 questions) and report the interval.

## Phase 1 - Knowledge + format: MMLU, MMLU-Pro, GPQA (2xT4 is enough)
- Data: MMLU `auxiliary_train` + ARC (running now), then science/exam reasoning sets whose licenses we check.
- GPQA / HLE have no train set. Method: **self-consistency distillation** - sample several answers from Gemma (or an open reasoning model) on *training* science questions with known answers (ARC, SciQ, MMLU-aux science), keep only reasoning chains that reach the known answer (rejection sampling, `vote_filter.py` majority vote), SFT on those chains. This trains reasoning habits, not test content.
- Expect: small gains at best. Gemma already learned most of this.

## Phase 2 - Math and code reasoning (2xT4 for short sequences)
- `aime_math` (NuminaMath-CoT, OpenR1-Math) and `code_contest` (open-r1 Codeforces). Same rejection-sampling filter when answers are checkable.
- Evaluate on held-out math/code sets; AIME 2026 and LiveCodeBench v6 only as final tests.

## Phase 3 - Tool use (2xT4, short sequences)
- `tool_use`: function-calling data. This teaches the call format; it is the base for Phase 4.

## Phase 4 - Agentic software engineering and terminal (needs more than the free setup)
What is different: the model works in a loop (read files, run commands, edit, run tests) over many turns; one trajectory is 10k-60k tokens.
Needs:
- A machine with **Docker** (Kaggle and Colab generally do not give it): a rented GPU VM with a 80 GB GPU (A100/H100 class) is the practical minimum for 32k-token LoRA training on a 31B model. Cost: estimate roughly tens of dollars per training run on rented hardware - check current prices.
- Harnesses: SWE-bench (Verified for evaluation) and Terminal-Bench for the terminal skill. Training tasks come from *training* task sets (SWE-Gym / SWE-smith task instances, not their Claude trajectories), never from the evaluation sets.
- Data by **rejection-sampling fine-tuning**: run Gemma (or an open code-agent model such as Qwen3-Coder, license checked) inside the harness on training tasks, keep only trajectories whose tests pass, SFT on them. Repeat (round 2 uses the improved model).
- DeepSWE-Preview (Agentica, RL on Qwen3-32B) shows RL helps, but RL needs far more compute; treat RL as a later stage, not part of the first release.
Expect: this is the phase most likely to give real gains, and the most expensive.

## Phase 5 - Self-correction ("knows its mistakes")
- Build wrong-attempt -> reflection -> fix examples only from checkable tasks (math, code with tests, MCQ with known answers). Measure calibration: accuracy when it says "confident" vs "unsure".

## Phase 6 - Evaluate and publish
- Same harnesses, base Gemma vs VishwamAI-Gemma, intervals, all topics including the ones that did not improve. Model card: derived from Gemma 4, license, data sources, known weaknesses.
- Publish the LoRA adapter first (small, private), merged weights later.

## Out of scope for the text adapter
MATH-Vision, OmniDocBench, MedXPertQA-MM, CoVoST, FLEURS (vision/audio), MRCR 128k (long context): separate notebooks, later.

## Order and rough effort
| Phase | Hardware | Status |
|---|---|---|
| 0 baselines | 2xT4 | started: 132M base model measured (MMLU/MMMLU at chance, GSM8K 1.1% -> 2.5% after SFT); plain Gemma 4 baseline not yet run |
| 1 knowledge (MMLU) | 2xT4 | running (`mmlu` topic) |
| 2 math/code | 2xT4 | notebook ready, untested |
| 3 tool use | 2xT4 | notebook ready, untested |
| 4 agentic SWE/terminal | rented 80 GB GPU + Docker | not started |
| 5 self-correction | 2xT4 | not started |
| 6 evaluate/publish | 2xT4 | partly ready |
