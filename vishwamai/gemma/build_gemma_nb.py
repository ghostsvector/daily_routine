"""Builds vishwamai_gemma31b_topics_qlora.ipynb (self-contained). python3 build_gemma_nb.py"""
import json, os
HERE = os.path.dirname(os.path.abspath(__file__))
def md(s): return dict(cell_type='markdown', metadata={}, source=s.strip('\n').splitlines(True))
def code(s): return dict(cell_type='code', metadata={}, execution_count=None, outputs=[], source=s.strip('\n').splitlines(True))

cells = [
md('''# VishwamAI on Gemma 4 31B - QLoRA training (not pretraining)
Starts from the open **google/gemma-4-31B** weights (Apache-2.0 per its model card) and trains a small LoRA adapter on top: software-engineering (SWE) skill, Hindi/Telugu, VishwamAI identity and the `<think>` style. Nothing is trained from scratch; the result is a *derived* model and must credit Gemma 4.

**Hardware (read first).** The bf16 weights are 62.6 GB. In 4-bit they are roughly 17-20 GB, so this does **not** fit the free Colab T4 (15 GB). You need a 40-80 GB GPU: Colab **A100** (paid compute units), or a rented L40S/A100. A guard cell below stops early on a GPU that is too small instead of crashing 40 minutes in. You also need about 70 GB free disk for the download (Colab A100 has enough; Drive does not).
Rough cost (an estimate, check current prices): a few hours on an A100 / L40S. Use the time budget so it stops by itself.

**Data.** Put your own SFT file at `MyDrive/vishwamai/gemma/sft.jsonl`, one JSON object per line: `{"messages": [{"role":"user","content":"..."},{"role":"assistant","content":"..."}]}`.
Good sources: open-teacher outputs (`distill_generate.py`), your own verified traces, and open SWE datasets whose license you checked. **Warning:** the public `SWE-bench/SWE-smith-trajectories` were generated with Claude 3.7 Sonnet, a closed model, which conflicts with your open-models-only rule and may have terms that limit training on its outputs - off by default (`USE_SWE_SMITH_TRAJECTORIES = False`); check its license and terms yourself first.

**Honesty.** This notebook has *not* been run on a GPU by me (no GPU in my environment); the Gemma 4 class names and module names may need a small fix on first run, and the cells print what they found so the fix is quick. A LoRA adapter keeps Gemma's abilities but also its mistakes; run the baseline-vs-tuned evaluation cell before claiming any improvement.'''),
code('''
%pip -q install -U transformers peft bitsandbytes accelerate datasets huggingface_hub safetensors
'''),
code('''
import os, sys, json, time, glob, shutil, math, random, subprocess
try:
    from google.colab import drive; drive.mount('/content/drive'); WORK = '/content/drive/MyDrive/vishwamai'
except Exception:
    WORK = '/kaggle/working/vishwamai' if os.path.exists('/kaggle/working') else './vishwamai'
GDIR = f'{WORK}/gemma'; os.makedirs(GDIR, exist_ok=True)

MODEL_ID = 'google/gemma-4-31B'            # base weights. Try 'google/gemma-4-E4B' first if you only have a small GPU.
ADAPTER_DIR = f'{GDIR}/adapter'; SFT_FILE = f'{GDIR}/sft.jsonl'
USE_SWE_SMITH_TRAJECTORIES = False          # see the warning above before turning this on
MAX_LEN = 4096; LORA_R = 16; LORA_ALPHA = 32; LR = 1e-4
TOPIC = 'mmlu'                              # today's topic, see TOPICS in the data cell
MAX_EXAMPLES_PER_SOURCE = 20000
TIME_BUDGET_MIN = 180; BATCH_TOKENS_ACCUM = 16   # sequences per optimiser step (micro-batch is 1 sequence)
'''),
code('''
def get_hf_token(required=False):
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
HF_TOKEN = get_hf_token()
'''),
code('''
# Guard: refuse to start on a GPU / disk that cannot work
import torch
assert torch.cuda.is_available(), 'No GPU: Runtime -> Change runtime type -> A100 (or L4/L40S).'
gb = torch.cuda.get_device_properties(0).total_memory / 1e9
free_disk = shutil.disk_usage('/').free / 1e9
print(f'GPU {torch.cuda.get_device_name(0)} {gb:.0f} GB | free disk {free_disk:.0f} GB | bf16 {torch.cuda.is_bf16_supported()}')
big = '31B' in MODEL_ID or '26B' in MODEL_ID
if big:
    assert gb >= 38, f'{MODEL_ID} in 4-bit needs a 40 GB+ GPU (this one has {gb:.0f} GB). Use an A100/L40S, or set MODEL_ID to a smaller Gemma 4.'
    assert free_disk >= 75, f'need ~70 GB free disk for the download, have {free_disk:.0f} GB'
'''),
code('''
from transformers import AutoTokenizer, BitsAndBytesConfig, AutoModelForCausalLM
tok = AutoTokenizer.from_pretrained(MODEL_ID, token=HF_TOKEN)
bnb = BitsAndBytesConfig(load_in_4bit=True, bnb_4bit_quant_type='nf4', bnb_4bit_use_double_quant=True,
                         bnb_4bit_compute_dtype=torch.bfloat16 if torch.cuda.is_bf16_supported() else torch.float16)
kw = dict(quantization_config=bnb, device_map={'': 0}, token=HF_TOKEN, torch_dtype=torch.bfloat16)
try:
    model = AutoModelForCausalLM.from_pretrained(MODEL_ID, **kw)
except Exception as e:
    print('AutoModelForCausalLM failed:', type(e).__name__, str(e)[:200], '\\n-> trying AutoModelForImageTextToText')
    from transformers import AutoModelForImageTextToText
    model = AutoModelForImageTextToText.from_pretrained(MODEL_ID, **kw)
print(type(model).__name__, f'| GPU memory used {torch.cuda.memory_allocated()/1e9:.1f} GB')
'''),
code('''
from peft import LoraConfig, get_peft_model, prepare_model_for_kbit_training, PeftModel
import bitsandbytes as bnb_lib
# LoRA on the text model's linear layers only (skip vision/audio towers)
SUFFIX = ('q_proj', 'k_proj', 'v_proj', 'o_proj', 'gate_proj', 'up_proj', 'down_proj')
targets = [n for n, m in model.named_modules()
           if isinstance(m, bnb_lib.nn.Linear4bit) and n.endswith(SUFFIX) and not any(x in n for x in ('vision', 'audio', 'visual'))]
print(len(targets), 'LoRA target modules, e.g.', targets[:2])
assert targets, 'no target modules found - print model.named_modules() and adjust SUFFIX'
model = prepare_model_for_kbit_training(model, use_gradient_checkpointing=True)
if os.path.exists(f'{ADAPTER_DIR}/adapter_config.json'):
    model = PeftModel.from_pretrained(model, ADAPTER_DIR, is_trainable=True); print('resumed adapter from', ADAPTER_DIR)
else:
    model = get_peft_model(model, LoraConfig(r=LORA_R, lora_alpha=LORA_ALPHA, lora_dropout=0.05, target_modules=targets, task_type='CAUSAL_LM'))
model.print_trainable_parameters()
'''),
code('''
# Data: your own sft.jsonl (+ optionally SWE-smith trajectories, off by default)
rows = []
if os.path.exists(SFT_FILE):
    rows += [json.loads(l) for l in open(SFT_FILE, encoding='utf-8') if l.strip()]
if USE_SWE_SMITH_TRAJECTORIES:
    from datasets import load_dataset
    ds = load_dataset('SWE-bench/SWE-smith-trajectories', split='train', token=HF_TOKEN)
    print('SWE-smith columns:', ds.column_names)
    for ex in ds:
        if isinstance(ex.get('messages'), list): rows.append({'messages': ex['messages']})
# ---- daily topic curriculum: TRAIN-split data only. Benchmark TEST sets are never trained on (that would be contamination).
TOPICS = {   # topic -> candidate (hf id, config, split); each is tried and skipped with a message if it does not load. IDs are unverified candidates.
  'mmlu':        [('cais/mmlu', 'auxiliary_train', 'train')],
  'mmlu_pro':    [('cais/mmlu', 'auxiliary_train', 'train'), ('TIGER-Lab/WebInstructSub', None, 'train')],
  'aime_math':   [('AI-MO/NuminaMath-CoT', None, 'train'), ('open-r1/OpenR1-Math-220k', 'default', 'train')],
  'code_contest':[('open-r1/codeforces-cots', 'solutions', 'train'), ('open-r1/codeforces', None, 'train')],
  'tool_use':    [('Salesforce/xlam-function-calling-60k', None, 'train')],
  'science':     [],     # GPQA/HLE have no public train set - supply your own sft.jsonl for this topic
}
PAIRS = [('question', 'answer'), ('problem', 'solution'), ('prompt', 'response'), ('instruction', 'output'), ('query', 'answers')]
def to_messages(ex):
    for k in ('messages', 'conversations'):
        if isinstance(ex.get(k), list) and ex[k] and 'role' in ex[k][0]: return ex[k]
    for q, a in PAIRS:
        if ex.get(q) and ex.get(a):
            if q == 'question' and isinstance(ex.get('choices'), list):     # MMLU-style multiple choice
                opts = '\\n'.join(f'{"ABCD"[i]}. {c}' for i, c in enumerate(ex['choices'][:4])); ai = ex['answer'] if isinstance(ex['answer'], int) else None
                if ai is None: return None
                return [{'role': 'user', 'content': f"{ex['question']}\\n{opts}\\nAnswer with the letter."}, {'role': 'assistant', 'content': "ABCD"[ai]}]
            return [{'role': 'user', 'content': str(ex[q])}, {'role': 'assistant', 'content': str(ex[a] if not isinstance(ex[a], list) else ex[a][0])}]
    return None
from datasets import load_dataset
for path, cfg, split in TOPICS.get(TOPIC, []):
    try:
        ds = load_dataset(path, cfg, split=split, streaming=True, token=HF_TOKEN) if cfg else load_dataset(path, split=split, streaming=True, token=HF_TOKEN)
        n = 0
        for ex in ds:
            m = to_messages(ex)
            if m: rows.append({'messages': m}); n += 1
            if n >= MAX_EXAMPLES_PER_SOURCE: break
        print(f'topic {TOPIC}: {path}: {n} examples' + ('' if n else '  (no usable columns - check the schema)'))
    except Exception as e:
        print(f'topic {TOPIC}: {path} skipped: {type(e).__name__}: {str(e)[:100]}')
assert rows, f'no training data: create {SFT_FILE} (one {{"messages": [...]}} per line)'
random.Random(0).shuffle(rows)
def encode(ex):
    msgs = ex['messages']; last = max(i for i, m in enumerate(msgs) if m['role'] == 'assistant')
    prompt = tok.apply_chat_template(msgs[:last], tokenize=False, add_generation_prompt=True)
    full = prompt + msgs[last]['content'] + (tok.eos_token or '')
    p = tok(prompt, add_special_tokens=False)['input_ids']; f = tok(full, add_special_tokens=False)['input_ids'][:MAX_LEN]
    labels = [-100] * min(len(p), len(f)) + f[len(p):]
    return dict(input_ids=f, labels=labels[:len(f)])
enc = [e for e in map(encode, rows) if any(l != -100 for l in e['labels'])]
print(len(rows), 'examples ->', len(enc), 'usable; mean length', sum(len(e['input_ids']) for e in enc) // max(1, len(enc)))
'''),
code('''
# Training loop: time-budgeted, checkpoints the adapter every 10 min, resumes if you re-run
opt = torch.optim.AdamW([p for p in model.parameters() if p.requires_grad], lr=LR, weight_decay=0.0, betas=(0.9, 0.99))
steps_total = max(1, len(enc) // BATCH_TOKENS_ACCUM)
sched = torch.optim.lr_scheduler.LambdaLR(opt, lambda s: min(1.0, (s + 1) / 10) * (0.1 + 0.9 * 0.5 * (1 + math.cos(math.pi * min(1.0, s / steps_total)))))
state_f = f'{GDIR}/train_state.json'
st = json.load(open(state_f)) if os.path.exists(state_f) else dict(step=0)
model.train(); t0 = time.time(); last_save = t0; step = st['step']
def save():
    model.save_pretrained(ADAPTER_DIR); json.dump(dict(step=step), open(state_f, 'w'))
try:
    while step < steps_total and time.time() - t0 < TIME_BUDGET_MIN * 60:
        loss_sum = 0.0
        for i in range(BATCH_TOKENS_ACCUM):
            ex = enc[(step * BATCH_TOKENS_ACCUM + i) % len(enc)]
            ids = torch.tensor([ex['input_ids']], device='cuda'); lab = torch.tensor([ex['labels']], device='cuda')
            loss = model(input_ids=ids, labels=lab).loss / BATCH_TOKENS_ACCUM
            assert torch.isfinite(loss), 'loss is not finite - lower LR'
            loss.backward(); loss_sum += loss.item()
        torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0); opt.step(); sched.step(); opt.zero_grad(set_to_none=True); step += 1
        if step % 5 == 0 or step == 1:
            print(f'step {step}/{steps_total} loss {loss_sum:.4f} lr {sched.get_last_lr()[0]:.2e} | {(time.time()-t0)/60:.0f}/{TIME_BUDGET_MIN} min | mem {torch.cuda.max_memory_allocated()/1e9:.0f} GB')
        if time.time() - last_save > 600: save(); last_save = time.time(); print('  adapter saved')
except KeyboardInterrupt:
    print('interrupted - saving'); save(); raise
save(); print('done; adapter in', ADAPTER_DIR)
'''),
code('''
# Baseline vs tuned on a held-out slice (do this before claiming any gain). Uses the last 50 usable examples' *prompts*
# you did not train on only if you reserve them: put held-out lines in MyDrive/vishwamai/gemma/heldout.jsonl (same format; verifiable answers).
HELD = f'{GDIR}/heldout.jsonl'
if os.path.exists(HELD):
    held = [json.loads(l) for l in open(HELD, encoding='utf-8')][:50]
    def nll(m):
        m.eval(); tot = n = 0
        with torch.no_grad():
            for ex in map(encode, held):
                ids = torch.tensor([ex['input_ids']], device='cuda'); lab = torch.tensor([ex['labels']], device='cuda')
                k = sum(1 for l in ex['labels'] if l != -100); tot += m(input_ids=ids, labels=lab).loss.item() * k; n += k
        return tot / max(n, 1)
    tuned = nll(model)
    with model.disable_adapter(): base = nll(model)
    print(f'held-out answer NLL  base Gemma {base:.3f} | tuned {tuned:.3f}  (lower is better; only a loss, not a benchmark score)')
else:
    print('no heldout.jsonl: skipped. Create one to compare base vs tuned.')
'''),
code('''
# Real benchmark scores for today's topic with lm-evaluation-harness (held-out TEST sets; run for base and tuned and compare).
# Which tasks: mmlu -> mmlu ; mmlu_pro -> mmlu_pro ; science -> gpqa_main_zeroshot. Others (AIME, LiveCodeBench, Codeforces, tau2, HLE, vision/audio) need their own harnesses.
RUN_LM_EVAL = False; LM_TASKS = 'mmlu_pro'; LM_LIMIT = 200      # limit = examples per task; small limit = wide error bars
if RUN_LM_EVAL:
    model.save_pretrained(ADAPTER_DIR)
    os.system('pip -q install lm_eval')
    for tag, extra in (('base', ''), ('tuned', f',peft={ADAPTER_DIR}')):
        os.system(f"lm_eval --model hf --model_args pretrained={MODEL_ID},load_in_4bit=True,dtype=bfloat16{extra} --tasks {LM_TASKS} --limit {LM_LIMIT} --batch_size 1 --output_path {GDIR}/lm_eval_{tag}")
'''),
code('''
# Publish the adapter (small, private by default). Merging into full 62 GB weights is a separate step on a big-RAM machine.
REPO = 'VishwamAI/vishwamai-gemma4-31b-lora-v0'; PRIVATE = True; LICENSE = 'apache-2.0'   # adapter inherits Gemma 4's license; confirm on the model card
from huggingface_hub import HfApi
card = f"""---
license: {LICENSE}
base_model: {MODEL_ID}
library_name: peft
---
# VishwamAI on Gemma 4 (LoRA adapter)

A LoRA adapter trained on top of [{MODEL_ID}](https://huggingface.co/{MODEL_ID}). This is a **derived model**, not trained from scratch:
all base capability comes from Google's Gemma 4. Training data: user-provided SFT file ({len(enc)} usable examples). No benchmark
claims are made here; evaluate before use.
"""
open(f'{ADAPTER_DIR}/README.md', 'w').write(card)
api = HfApi(token=get_hf_token(required=True)); api.create_repo(REPO, private=PRIVATE, exist_ok=True)
api.upload_folder(folder_path=ADAPTER_DIR, repo_id=REPO, commit_message='LoRA adapter')
print('uploaded', REPO)
'''),
]
path = f'{HERE}/vishwamai_gemma31b_topics_qlora.ipynb'
json.dump(dict(cells=cells, metadata=dict(kernelspec=dict(name='python3', display_name='Python 3'), accelerator='GPU', colab=dict(gpuType='A100')), nbformat=4, nbformat_minor=5), open(path, 'w'), indent=1)
print('wrote', path)
