# ====================================================================================
# Full evaluation of VishwamAI models from Hugging Face: MMLU, MMMLU-Hindi and GSM8K, with 95% intervals.
# Paste into ONE notebook cell (GPU session, Internet on) and run. Prompts, letter scoring, subset order and
# sequence length follow the original pre-training notebook, so the numbers are comparable with its results.
# ====================================================================================
MODELS = ['VishwamAI/vishwamai-base-v0', 'VishwamAI/vishwamai-base-v0-gsm8k-sft-v0']
MMLU_N  = 1000     # first N questions of the shuffled test set (the original notebook used 1000). None = all 14,042 (slow)
MMMLU_N = 1000     # same for MMMLU-Hindi
GSM8K_N = 1319     # 1319 = the whole GSM8K test set
RUN_CHAT_FORMAT = True      # also score the 0-shot chat-format variants (MMLU, MMMLU) as in the original notebook
SEQ_LEN, MC_BS, GEN_BS, GEN_NEW = 1024, 16, 64, 256

import subprocess, sys, os, re, math, copy, random, concurrent.futures as cf
subprocess.run([sys.executable, "-m", "pip", "-q", "install", "-U", "transformers", "datasets", "accelerate", "sentencepiece"], check=False)
import numpy as np, torch
import sentencepiece as spm
from datasets import load_dataset
from huggingface_hub import hf_hub_download
from transformers import AutoModelForCausalLM

# ---- free GPU memory left over from an earlier failed cell in this session, and refuse to continue if it is still occupied ----
import gc
for _n in ('last_traceback', 'last_value', 'last_type'): setattr(sys, _n, None)      # a failed cell keeps its tensors alive through the traceback
gc.collect(); torch.cuda.empty_cache()
_used = [torch.cuda.memory_allocated(g) / 2**30 for g in range(torch.cuda.device_count())]
if max(_used) > 1.0:
    raise RuntimeError(f"GPU memory is already in use by an earlier cell in this session ({[round(u, 1) for u in _used]} GiB). "
                       "Restart the session (Run > Restart session), then run only this cell.")
print('GPUs:', torch.cuda.device_count(), '| memory in use at start (GiB):', [round(u, 2) for u in _used])

# ---- Hugging Face token: environment / Kaggle or Colab secret / saved login / typed (hidden) ----
token = os.environ.get('HF_TOKEN')
if not token:
    for lab in ('HF_TOKEN', 'hf_token'):
        try:
            from kaggle_secrets import UserSecretsClient
            token = UserSecretsClient().get_secret(lab); break
        except Exception: pass
        try:
            from google.colab import userdata
            token = userdata.get(lab); break
        except Exception: pass
if not token:
    try:
        from huggingface_hub import get_token; token = get_token()
    except Exception: pass
if not token:
    import getpass; token = getpass.getpass('Hugging Face token (hidden, empty for public repos): ').strip() or None
if token: os.environ['HF_TOKEN'] = token                   # so datasets / hub downloads are authenticated too

# ---- helpers ----
def wilson(k, n, z=1.96):
    p = k / n; d = 1 + z * z / n; c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return 100 * (c - h), 100 * (c + h)

SYSTEM_EN = "You are VishwamAI, a calm, witty and emotionally aware assistant."
def mc_prompt(q, choices, ans=None):
    s = q.strip() + "\n" + "\n".join(f"{l}. {c_}" for l, c_ in zip('ABCD', choices)) + "\nAnswer:"
    return s + (f" {'ABCD'[ans]}\n\n" if ans is not None else "")
def chat_prompt(user):          # original: render(SYSTEM['en'], [('user', user)], 'en') + '<|assistant|>'
    return f"<|system|>{SYSTEM_EN}<|end|><|lang:en|><|user|>{user}<|end|><|assistant|>"

def gold(a): return a.split('####')[-1].strip().replace(',', '')
def extract(text):
    m = re.findall(r'####\s*(-?[\d,]*\.?\d+)', text)
    if m: return m[0].replace(',', '')
    m = re.findall(r'-?\d[\d,]*\.?\d*', text)
    return m[-1].replace(',', '').rstrip('.') if m else None
def same(a, b):
    try: return abs(float(a) - float(b)) < 1e-4
    except Exception: return False
def gsm_prompt(q): return f"Question: {q}\nSolve step by step and end with '#### <number>'.\nAnswer:"

def run_parallel(reps, batches, fn):
    """each GPU replica takes alternate batches; fn(replica, batch_list) -> number correct"""
    with cf.ThreadPoolExecutor(len(reps)) as ex:
        return sum(ex.map(fn, reps, [batches[g::len(reps)] for g in range(len(reps))]))

@torch.no_grad()
def eval_mc(reps, sp, rows, shots=(), chat=False, L=SEQ_LEN, bs=MC_BS):
    BOS = [sp.eos_id()]                                     # the model starts every sequence with the EOS token
    lid = [sp.encode('<|assistant|>' + l)[-1] for l in 'ABCD'] if chat else [sp.piece_to_id('▁' + l) for l in 'ABCD']
    assert all(i != sp.unk_id() for i in lid), lid
    items = []
    for q, ch, a in rows:
        head = ''
        for sq, sc, sa in shots:
            cand = head + mc_prompt(sq, sc, sa)
            if len(sp.encode(cand + mc_prompt(q, ch))) < L - 4: head = cand
        ids = BOS + sp.encode(chat_prompt(mc_prompt(q, ch)) if chat else head + mc_prompt(q, ch))
        items.append((ids[-L:], a))
    items.sort(key=lambda x: len(x[0]))                     # similar lengths together = less padding
    batches = [items[i:i + bs] for i in range(0, len(items), bs)]
    @torch.no_grad()                                        # grad mode is per-thread: the worker threads need it themselves
    def work(rep, mine):
        dev = next(rep.parameters()).device; ok = 0
        for b in mine:
            Lb = max(len(x[0]) for x in b)
            ids = torch.tensor([x[0] + [0] * (Lb - len(x[0])) for x in b]).to(dev)               # right padding
            att = torch.tensor([[1] * len(x[0]) + [0] * (Lb - len(x[0])) for x in b]).to(dev)
            last = torch.tensor([len(x[0]) - 1 for x in b]).to(dev)
            h = rep.model(input_ids=ids, attention_mask=att).last_hidden_state                   # hidden states only
            logits = rep.lm_head(h[torch.arange(len(b), device=dev), last])[:, lid]              # logits for A/B/C/D at the last real token
            ok += int((logits.argmax(-1).cpu() == torch.tensor([x[1] for x in b])).sum())
        return ok
    return run_parallel(reps, batches, work), len(items)

@torch.no_grad()
def eval_gsm8k(reps, sp, n, bs=GEN_BS, max_new=GEN_NEW):
    test = load_dataset('openai/gsm8k', 'main', split='test')
    qs, ans = test['question'][:n], [gold(a) for a in test['answer'][:n]]
    BOS, EOS = [sp.eos_id()], sp.eos_id()
    batches = [(qs[i:i + bs], ans[i:i + bs]) for i in range(0, len(qs), bs)]
    @torch.no_grad()                                        # grad mode is per-thread: the worker threads need it themselves
    def work(rep, mine):
        dev = next(rep.parameters()).device; ok = 0
        for qb, ab in mine:
            ids = [BOS + sp.encode(gsm_prompt(q)) for q in qb]; Lb = max(map(len, ids))
            inp = torch.tensor([[0] * (Lb - len(x)) + x for x in ids]).to(dev)                   # left padding for generation
            att = torch.tensor([[0] * (Lb - len(x)) + [1] * len(x) for x in ids]).to(dev)
            out = rep.generate(input_ids=inp, attention_mask=att, max_new_tokens=max_new, do_sample=False, pad_token_id=0, eos_token_id=EOS)
            for o, a in zip(out[:, Lb:].tolist(), ab):
                o = o[:o.index(EOS)] if EOS in o else o
                ok += same(extract(sp.decode(o).split('\nQuestion:')[0]), a)
        return ok
    return run_parallel(reps, batches, work), len(qs)

# ---- data (same subsets and order as the original notebook) ----
mmlu = load_dataset('cais/mmlu', 'all')
mm_dev = [(r['question'], r['choices'], r['answer']) for r in mmlu['dev']][:5]
mm_test = [(r['question'], r['choices'], r['answer']) for r in mmlu['test']]; random.Random(0).shuffle(mm_test)
mm_test = mm_test[:MMLU_N] if MMLU_N else mm_test
hi = load_dataset('openai/MMMLU', 'HI_IN', split='test')
hi_rows = [(r['Question'], [r['A'], r['B'], r['C'], r['D']], 'ABCD'.index(r['Answer'])) for r in hi]; random.Random(0).shuffle(hi_rows)
hi_rows = hi_rows[:MMMLU_N] if MMMLU_N else hi_rows

# ---- run every model ----
results = {}
for name in MODELS:
    print(f'\n=== {name} ===', flush=True)
    tkp = os.path.join(name, 'tokenizer.model') if os.path.isdir(name) else hf_hub_download(name, 'tokenizer.model', token=token)
    sp = spm.SentencePieceProcessor(model_file=tkp)
    try:    model = AutoModelForCausalLM.from_pretrained(name, dtype=torch.float32, token=token)
    except TypeError: model = AutoModelForCausalLM.from_pretrained(name, torch_dtype=torch.float32, token=token)
    model = model.to('cuda:0').eval()
    reps = [model] + [copy.deepcopy(model).to(f'cuda:{g}').eval() for g in range(1, torch.cuda.device_count())]
    r = {}
    r['MMLU 5-shot (raw format)'] = eval_mc(reps, sp, mm_test, shots=mm_dev); print('MMLU raw done', flush=True)
    r['MMMLU-Hindi 0-shot (raw)'] = eval_mc(reps, sp, hi_rows); print('MMMLU raw done', flush=True)
    if RUN_CHAT_FORMAT:
        r['MMLU 0-shot (chat format)'] = eval_mc(reps, sp, mm_test, chat=True); print('MMLU chat done', flush=True)
        r['MMMLU-Hindi 0-shot (chat)'] = eval_mc(reps, sp, hi_rows, chat=True); print('MMMLU chat done', flush=True)
    r['GSM8K greedy'] = eval_gsm8k(reps, sp, GSM8K_N); print('GSM8K done', flush=True)
    results[name] = r
    del reps, model; gc.collect(); torch.cuda.empty_cache()

# ---- report ----
print('\n' + '=' * 100)
for name, r in results.items():
    print(f'\n{name}')
    for metric, (k, n) in r.items():
        lo, hi_ = wilson(k, n)
        print(f'  {metric:30s} {100 * k / n:6.2f}%   ({k}/{n})   95% interval {lo:5.1f}-{hi_:5.1f}%')
print('\nchance level for the 4-choice MMLU/MMMLU questions is 25%. Differences smaller than the interval width are noise.')
