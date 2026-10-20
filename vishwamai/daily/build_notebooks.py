"""Builds the four daily-pretraining notebooks. Each notebook is self-contained: it writes vm_core.py / vm_data.py
itself with %%writefile, so no .py files need to be uploaded. Run: python3 build_notebooks.py"""
import json, os
HERE = os.path.dirname(os.path.abspath(__file__))
CORE = open(f'{HERE}/vm_core.py').read(); DATA = open(f'{HERE}/vm_data.py').read()

def md(s): return dict(cell_type='markdown', metadata={}, source=s.strip('\n').splitlines(True))
def code(s): return dict(cell_type='code', metadata={}, execution_count=None, outputs=[], source=s.strip('\n').splitlines(True))
def wf(name, body): return code(f'%%writefile {name}\n' + body)
def nb(cells, path):
    json.dump(dict(cells=cells, metadata=dict(kernelspec=dict(name='python3', display_name='Python 3'), accelerator='GPU',
              colab=dict(provenance=[], gpuType='T4')), nbformat=4, nbformat_minor=5), open(path, 'w'), indent=1)
    print('wrote', path, len(cells), 'cells')

SETUP = '''
# Where everything lives (same Drive folder as the original VishwamAI pre-training run).
import os, sys, json, time, glob, shutil, subprocess
try:
    from google.colab import drive; drive.mount('/content/drive'); WORK = '/content/drive/MyDrive/vishwamai'
except Exception:
    WORK = '/kaggle/working/vishwamai' if os.path.exists('/kaggle/working') else './vishwamai'
for sub in ('data', 'ckpt', 'tok', 'daily', 'export'): os.makedirs(f'{WORK}/{sub}', exist_ok=True)
DATA_DIR = f'{WORK}/data'; SP_PATH = f'{WORK}/tok/vishwamai.model'
print('WORK =', WORK)
'''
INSTALL = '''
%pip -q install sentencepiece safetensors datasets huggingface_hub flax optax
'''
TOKEN = '''
def get_hf_token(required=False):
    """env -> Colab/Kaggle secret HF_TOKEN -> saved login -> hidden prompt (only if required). Never printed or stored in the notebook."""
    t = os.environ.get('HF_TOKEN')
    if not t:
        try:
            from google.colab import userdata; t = userdata.get('HF_TOKEN')
        except Exception: pass
    if not t:
        try:
            from kaggle_secrets import UserSecretsClient; t = UserSecretsClient().get_secret('HF_TOKEN')
        except Exception: pass
    if not t:
        try:
            from huggingface_hub import get_token; t = get_token()
        except Exception: pass
    if not t and required:
        from getpass import getpass; t = getpass('Hugging Face token (hidden): ')
    return t or None
'''
TOKENIZER = '''
# The SentencePiece model must be the one the weights were trained with (vocab 40,960).
if not os.path.exists(SP_PATH):
    from huggingface_hub import hf_hub_download
    p = hf_hub_download('VishwamAI/vishwamai-base-v0', 'tokenizer.model', token=get_hf_token())
    shutil.copy(p, SP_PATH); print('tokenizer downloaded from VishwamAI/vishwamai-base-v0')
import sentencepiece as spm
sp = spm.SentencePieceProcessor(model_file=SP_PATH)
assert sp.get_piece_size() == 40960, f'unexpected vocab size {sp.get_piece_size()}'
print('tokenizer ok, vocab', sp.get_piece_size())
'''
HEAD = '''
sys.path.insert(0, os.getcwd())
import numpy as np, jax, jax.numpy as jnp
import vm_core as C
print('jax devices:', jax.devices())
'''

# ------------------------------------------------------------------ 1. data
nb([
 md('''# 1 - Build the subject data (run once; resumable)
Creates one token shard per school subject next to your existing shards in `MyDrive/vishwamai/data`.
Subjects: physics/chemistry, biology/health, reasoning, history/geography, economics/law, philosophy/literature, everyday life, extra math.
English, math, code, Hindi and Telugu shards already exist from the first run.

Method: one streaming pass over FineWeb-Edu, Cosmopedia and Wikipedia; a keyword router assigns each document to the subject it matches best (>= 3 distinct keywords).
This is a *heuristic*: some documents land in the wrong subject. `subj_reasoning` is programmatic arithmetic/logic text plus GSM8K **train** solutions (the GSM8K test set is never used).
Re-running skips finished shards. Colab free: expect a few hours for the streaming pass; stop and re-run any time (a shard only counts once finished).'''),
 code(INSTALL), code(SETUP), wf('vm_data.py', DATA), code(TOKEN), code(TOKENIZER),
 code('''
sys.path.insert(0, os.getcwd())
import vm_data as D
TOKENS_PER_SUBJECT = 20_000_000      # lower (e.g. 5_000_000) for a quick first pass
D.build_subject_shards(DATA_DIR, sp, tokens_per_subject=TOKENS_PER_SUBJECT)
'''),
 code('''
# Inventory: what the trainer will be able to use
for p in sorted(glob.glob(f'{DATA_DIR}/*.done')):
    n = os.path.basename(p)[:-5]; tr = os.path.getsize(f'{DATA_DIR}/{n}.train.bin') // 2
    print(f'{n:22s} {tr/1e6:8.1f}M train tokens')
'''),
], f'{HERE}/daily_1_build_data.ipynb')

# ------------------------------------------------------------------ 2. trainer
nb([
 md('''# 2 - Daily trainer (run once per day)
Set `DAY` (1, 2, 3 ...) and `TIME_BUDGET_MIN`, then run all. Two focus subjects per day (7-day cycle), 50% focus / 30% replay of earlier subjects / 20% general text.
The learning-rate schedule spans *all* days, so each day continues exactly where the previous one stopped; a session that disconnects resumes from its last checkpoint (saved every 15 min).

| day in cycle | focus |
|---|---|
| 1 | English + Math |
| 2 | Physics/Chemistry + Biology/Health |
| 3 | CS/Code + Reasoning |
| 4 | History/Geography + Economics/Law |
| 5 | Philosophy/Literature + Everyday |
| 6 | Hindi + Telugu |
| 7 | Review: all subjects equally |

Starts from `ckpt/daily_latest.msgpack` if present, else `ckpt/ctx_final.msgpack` / `pt_final.msgpack` from the original run, else the published `VishwamAI/vishwamai-base-v0` safetensors.
Use **Runtime -> Change runtime type -> T4 GPU**. Tip: keep the browser tab open; free Colab can disconnect at any time (progress is checkpointed).'''),
 code(INSTALL), code(SETUP), wf('vm_core.py', CORE), code(TOKEN),
 code('''
DAY = 1                     # <- change every day
TIME_BUDGET_MIN = 210       # stay under the session limit (free T4: roughly 3.5-4 h)
PLAN_DAYS = 56              # length of the whole program; the LR schedule is spread over this
PRESET, VOCAB, SEQ_LEN, CTX_LEN = 'base', 40960, 1024, 4096      # must match the first run
PER_DEVICE_TOKENS = 8192    # tokens per micro-batch (lower if out of memory)
GLOBAL_TOKENS_PER_STEP = 65536
LR = 3e-4                   # lowish: we continue an already-trained model
# Throughput on a T4 is roughly 2-3k tokens/s for this model (an estimate, measure it in the first log lines).
'''),
 code(HEAD), code(TOKENIZER),
 code('''
cfg, cfg_ext = C.make_cfgs(PRESET, VOCAB, SEQ_LEN, CTX_LEN, jnp.float16 if False else jnp.float32)
template = C.init_params(cfg)
print('params (total, active, mtp):', C.count_params(template, cfg))

latest = f'{WORK}/ckpt/daily_latest.msgpack'
start = None
if not (os.path.exists(latest) or os.path.exists(latest + '.prev')):
    for name in ('ctx_final.msgpack', 'pt_final.msgpack'):
        if os.path.exists(f'{WORK}/ckpt/{name}'): start = f'{WORK}/ckpt/{name}'; break
if os.path.exists(latest) or os.path.exists(latest + '.prev'):
    params0 = template; print('will resume the daily checkpoint')
elif start:
    params0 = C.load_params_from_checkpoint(start, template); print('starting from', start)
else:
    from huggingface_hub import hf_hub_download
    p = hf_hub_download('VishwamAI/vishwamai-base-v0', 'model.safetensors', token=get_hf_token())
    params0 = C.import_hf(template, cfg, p); print('starting from the published safetensors (MTP heads re-initialised)')
'''),
 code('''
data = C.Shards(DATA_DIR)
avail = data.names(); sizes = data.sizes()
print({k: f'{v/1e6:.1f}M' for k, v in sizes.items()})
cycle, d_in, focus, replay = C.plan_for_day(DAY)
print(f'DAY {DAY}: cycle {cycle+1}, day {d_in}, focus = {focus}')
missing = [s for s in focus for sh in C.SUBJECTS[s] if sh not in avail]
if missing: print('WARNING - shards missing for today (run notebook 1 first):', missing)
weights = C.day_mixture(DAY, avail)
print({k: round(v, 3) for k, v in weights.items()})
'''),
 code('''
import jax
n_dev = max(1, jax.device_count())
tokens_per_day = 2800 * TIME_BUDGET_MIN * 60                      # planning estimate only
plan_total = int(tokens_per_day * PLAN_DAYS)
# train_session stops by time; plan_total only shapes the LR schedule. If you measure a different tok/s, adjust it here.
params, stats = C.train_session(cfg, params0, data, weights, WORK, TIME_BUDGET_MIN, plan_total_tokens=plan_total,
    seq_len=SEQ_LEN, per_device_tokens=PER_DEVICE_TOKENS, global_tokens_per_step=GLOBAL_TOKENS_PER_STEP,
    lr=LR, warmup_steps=200, day=DAY, log=print)
with open(f'{WORK}/daily/progress.jsonl', 'a') as f: f.write(json.dumps({k: v for k, v in stats.items() if k != 'mix'} | {'time': time.strftime('%Y-%m-%d %H:%M')}) + '\\n')
'''),
 code('''
# Quick check after training: held-out loss per shard + a short sample
data_names = [s for s in avail]
nll = C.subject_val_nll(params, cfg, data, data_names, SEQ_LEN)
for k, v in sorted(nll.items()): print(f'{k:22s} val nll {v:.3f}  ppl {np.exp(v):8.1f}')
'''),
 md('Next: run notebook 3 (evaluation) to compare against earlier days, and notebook 4 to publish when you are happy.'),
], f'{HERE}/daily_2_train.ipynb')

# ------------------------------------------------------------------ 3. eval
nb([
 md('''# 3 - Per-subject evaluation
Reads the current `daily_latest.msgpack` and reports **held-out validation loss per subject shard** (lower = better; comparable only to earlier runs of this same notebook), appending to `daily/eval_log.jsonl` so you can see progress day by day.
Validation text is held out from training (the first 100k tokens of each shard), but it comes from the same sources as the training text.

Honesty note: at 132M parameters, validation-loss gains do **not** imply higher MMLU/GSM8K scores. For benchmark numbers use the earlier benchmark notebooks (`eval_all_hf.ipynb`).'''),
 code(INSTALL), code(SETUP), wf('vm_core.py', CORE),
 code('''
DAY = 1             # label for the log only
PRESET, VOCAB, SEQ_LEN, CTX_LEN = 'base', 40960, 1024, 4096
'''),
 code(HEAD), code(TOKEN + TOKENIZER),
 code('''
cfg, cfg_ext = C.make_cfgs(PRESET, VOCAB, SEQ_LEN, CTX_LEN, jnp.float32)
template = C.init_params(cfg)
ck = f'{WORK}/ckpt/daily_latest.msgpack'
assert os.path.exists(ck), 'no daily_latest.msgpack yet - run notebook 2 first'
params = C.load_params_from_checkpoint(ck, template)
data = C.Shards(DATA_DIR)
nll = C.subject_val_nll(params, cfg, data, data.names(), SEQ_LEN, n_batches=8)
by_subject = {s: [nll[sh] for sh in shs if sh in nll] for s, shs in C.SUBJECTS.items()}
rows = {s: float(np.mean(v)) for s, v in by_subject.items() if v}
for s, v in rows.items(): print(f'{s:16s} nll {v:.3f}  ppl {np.exp(v):8.1f}')
with open(f'{WORK}/daily/eval_log.jsonl', 'a') as f: f.write(json.dumps(dict(day=DAY, time=time.strftime('%Y-%m-%d %H:%M'), subject_nll=rows)) + '\\n')
'''),
 code('''
# History across days (rows = days). Different tokenizers/shards are not comparable; same notebook over time is.
import pandas as pd
log = [json.loads(l) for l in open(f'{WORK}/daily/eval_log.jsonl')]
print(pd.DataFrame([dict(day=r['day'], **{k: round(v, 3) for k, v in r['subject_nll'].items()}) for r in log]).to_string(index=False))
'''),
 code('''
# A few samples, for reading (not a benchmark)
f = C.make_fwd(C.eval_cfg(cfg))
for prompt in ['The theory of relativity states that', 'Question: Asha has 12 apples and gets 7 more. How many apples now?\\nAnswer:', 'भारत की राजधानी']:
    ids = [C.EOS] + sp.encode(prompt)
    out = C.sample_text(f, params, ids, max_new=60, temperature=0.7)
    print(repr(sp.decode(out if isinstance(out, list) else list(out))), '\\n')
'''),
], f'{HERE}/daily_3_eval.ipynb')

# ------------------------------------------------------------------ 4. publish
nb([
 md('''# 4 - Export and publish to Hugging Face
Exports the current weights as Hugging Face safetensors (Qwen3-MoE layout) and uploads them.
**Private by default.** Add your token as a Colab secret named `HF_TOKEN` (never paste it into a cell).
The model card is generated from the real training log (days trained, tokens seen) and states what the model is and is not.
Choose the license yourself - set `LICENSE` before publishing (the placeholder `other` is not a decision).'''),
 code(INSTALL), code(SETUP), wf('vm_core.py', CORE), code(TOKEN),
 code('''
REPO = 'VishwamAI/vishwamai-base-daily-v0'
PRIVATE = True
LICENSE = 'other'            # <- decide: e.g. 'apache-2.0', 'mit', ...
PRESET, VOCAB, SEQ_LEN, CTX_LEN = 'base', 40960, 1024, 4096
'''),
 code(HEAD),
 code('''
cfg, cfg_ext = C.make_cfgs(PRESET, VOCAB, SEQ_LEN, CTX_LEN, jnp.float32)
params = C.load_params_from_checkpoint(f'{WORK}/ckpt/daily_latest.msgpack', C.init_params(cfg))
out = f'{WORK}/export/daily'; shutil.rmtree(out, ignore_errors=True); os.makedirs(out)
C.export_hf(params, cfg_ext if False else cfg, out, SP_PATH)
print(os.listdir(out))
'''),
 code('''
prog = [json.loads(l) for l in open(f'{WORK}/daily/progress.jsonl')] if os.path.exists(f'{WORK}/daily/progress.jsonl') else []
ev = [json.loads(l) for l in open(f'{WORK}/daily/eval_log.jsonl')] if os.path.exists(f'{WORK}/daily/eval_log.jsonl') else []
tok_total = prog[-1]['tokens_total'] if prog else 0
card = f"""---
license: {LICENSE}
library_name: transformers
tags: [vishwamai, moe, from-scratch, multilingual]
---
# VishwamAI base (daily subject pretraining)

A small (about 133M total / 55M active parameters) Mixture-of-Experts decoder trained from scratch by VishwamAI, then
further pretrained on a daily, subject-by-subject schedule (English, math, science, biology, code, reasoning, history,
economics/law, philosophy/literature, everyday text, Hindi, Telugu).

* Sessions logged: {len(prog)}; tokens seen in the daily phase: {tok_total/1e6:.1f}M (see `progress.jsonl` in the training folder).
* Subject routing of web text is keyword-based, so subject labels are approximate.
* This is a **base** model: it is not instruction-tuned, makes frequent factual errors, and scores near chance on MMLU-style
  multiple choice at this size. Do not use it for decisions that matter.
* No data from a paid or closed model API was used. GSM8K train solutions were used; GSM8K test was not.
"""
open(f'{out}/README.md', 'w').write(card)
from huggingface_hub import HfApi
api = HfApi(token=get_hf_token(required=True))
api.create_repo(REPO, private=PRIVATE, exist_ok=True)
api.upload_folder(folder_path=out, repo_id=REPO, commit_message='daily subject pretraining checkpoint')
print('uploaded to https://huggingface.co/' + REPO, '(private)' if PRIVATE else '')
'''),
], f'{HERE}/daily_4_publish.ipynb')
