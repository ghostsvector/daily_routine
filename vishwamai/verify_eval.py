# ====================================================================================
# Re-verify a model's GSM8K score: whole test set (1,319 questions), greedy decoding, 95% interval.
# Paste into ONE notebook cell (GPU session, Internet on) and run. Change MODEL / settings below.
# ====================================================================================
MODEL = 'VishwamAI/vishwamai-base-v0'     # any Hugging Face causal LM repo or local folder
N = 1319                                  # number of GSM8K test questions (1319 = all)
MAX_NEW, BATCH = 256, 64
VISHWAMAI_BOS = True                      # True: start every prompt with the EOS token, as VishwamAI was pre-trained

import subprocess, sys, os, re, math, copy, concurrent.futures as cf
subprocess.run([sys.executable, "-m", "pip", "-q", "install", "-U", "transformers", "datasets", "accelerate"], check=False)
import torch
from datasets import load_dataset
from transformers import AutoTokenizer, AutoModelForCausalLM

# ---- Hugging Face token (secret HF_TOKEN / hf_token, saved login, or typed) ----
token = os.environ.get('HF_TOKEN')
if not token:
    try:
        from kaggle_secrets import UserSecretsClient
        for lab in ('HF_TOKEN', 'hf_token'):
            try: token = UserSecretsClient().get_secret(lab); break
            except Exception: pass
    except Exception: pass
if not token:
    try:
        from huggingface_hub import get_token; token = get_token()
    except Exception: pass
if not token and not os.path.isdir(MODEL):
    import getpass; token = getpass.getpass('Hugging Face token (hidden, leave empty for a public repo): ').strip() or None

# ---- helpers ----
def wilson(k, n, z=1.96):
    p = k / n; d = 1 + z * z / n; c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return 100 * (c - h), 100 * (c + h)

def gold(a): return a.split('####')[-1].strip().replace(',', '')
def extract(text):
    m = re.findall(r'####\s*(-?[\d,]*\.?\d+)', text)
    if m: return m[0].replace(',', '')
    m = re.findall(r'-?\d[\d,]*\.?\d*', text)
    return m[-1].replace(',', '').rstrip('.') if m else None
def same(a, b):
    try: return abs(float(a) - float(b)) < 1e-4
    except Exception: return False
def make_prompt(q): return f"Question: {q}\nSolve step by step and end with '#### <number>'.\nAnswer:"

# ---- model ----
tok = AutoTokenizer.from_pretrained(MODEL, token=token)
if tok.pad_token is None: tok.pad_token = tok.eos_token
dtype = torch.float32 if VISHWAMAI_BOS else torch.float16
try:    model = AutoModelForCausalLM.from_pretrained(MODEL, dtype=dtype, token=token)
except TypeError: model = AutoModelForCausalLM.from_pretrained(MODEL, torch_dtype=dtype, token=token)
model = model.to('cuda:0').eval()
NG = torch.cuda.device_count()
BOS = [tok.eos_token_id] if VISHWAMAI_BOS else []
def enc(q): return BOS + tok(make_prompt(q), add_special_tokens=False)['input_ids']

# ---- evaluation (every visible GPU runs a copy on alternate batches) ----
test = load_dataset('openai/gsm8k', 'main', split='test')
qs, ans = test['question'][:N], [gold(a) for a in test['answer'][:N]]
reps = [model] + [copy.deepcopy(model).to(f'cuda:{g}').eval() for g in range(1, NG)]
batches = [(qs[i:i + BATCH], ans[i:i + BATCH]) for i in range(0, len(qs), BATCH)]

@torch.no_grad()
def work(rep, mine):
    dev = next(rep.parameters()).device; ok = 0
    for qb, ab in mine:
        ids = [enc(q) for q in qb]; L = max(map(len, ids))
        inp = torch.tensor([[tok.pad_token_id] * (L - len(x)) + x for x in ids]).to(dev)
        att = torch.tensor([[0] * (L - len(x)) + [1] * len(x) for x in ids]).to(dev)
        out = rep.generate(input_ids=inp, attention_mask=att, max_new_tokens=MAX_NEW, do_sample=False, pad_token_id=tok.pad_token_id)
        for o, a in zip(out[:, L:], ab):
            ok += same(extract(tok.decode(o, skip_special_tokens=True).split('\nQuestion:')[0]), a)
    return ok

with cf.ThreadPoolExecutor(len(reps)) as ex:
    k = sum(ex.map(work, reps, [batches[g::len(reps)] for g in range(len(reps))]))
lo, hi = wilson(k, len(qs))
print(f"\n{MODEL}\nGSM8K greedy, {len(qs)} test questions: {100 * k / len(qs):.2f}%  ({k}/{len(qs)} correct), 95% interval {lo:.1f}-{hi:.1f}%")
print("settings: max_new_tokens =", MAX_NEW, "| prompt format = 'Question: ...\\nSolve step by step ...\\nAnswer:' | answer = first '####' number, else last number")
