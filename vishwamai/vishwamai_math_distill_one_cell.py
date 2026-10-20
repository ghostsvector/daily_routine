# ====================================================================================
# VishwamAI GSM8K distillation - ONE CELL. Paste into a single notebook cell and run it once.
# Needs a GPU session with Internet ON. It installs packages, finds your Hugging Face token,
# measures the base model, trains on the human GSM8K solutions, measures again and saves.
# Set the options below. (Teacher generation is not included; see the notebook for that.)
# ====================================================================================
RUN_BASELINE = True       # False: skip the baseline measurement and use BASELINE_ACC below
BASELINE_ACC = 0.013      # only used when RUN_BASELINE is False (1.3% measured earlier on 300 questions)
import subprocess, sys
subprocess.run([sys.executable, "-m", "pip", "-q", "install", "-U", "transformers", "peft", "datasets", "accelerate", "bitsandbytes"], check=False)


# ---------------- 1. setup + Hugging Face token ----------------
import os, json, re, glob, random, math, shutil
import numpy as np, torch

# ---- where files live: Kaggle working dir, else Google Drive on Colab, else the current folder ----
if os.path.exists('/kaggle/working'):
    WORK = '/kaggle/working/vishwamai'
else:
    try:
        from google.colab import drive
        drive.mount('/content/drive'); WORK = '/content/drive/MyDrive/vishwamai'
    except Exception:
        WORK = './vishwamai'
print('work dir:', WORK)
os.makedirs(f'{WORK}/math', exist_ok=True)

STUDENT = 'VishwamAI/vishwamai-base-v0'    # or 'Qwen/Qwen2.5-Math-1.5B'
FULL_FT = STUDENT.startswith('VishwamAI/')   # tiny model: full fine-tune in fp32 instead of LoRA
SLUG = STUDENT.split('/')[-1]
MAX_LEN, N_EVAL, SEED = 768, 300, 0
MATH_SUFFIX = "\n\nEnd your reply with a final line '#### <number>'."
random.seed(SEED); np.random.seed(SEED); torch.manual_seed(SEED)
SKIP_TEACHER = True    # True: skip the hours-long teacher generation (section 4) and train on the human GSM8K solutions only

# ---------------- Hugging Face token ----------------
# Looks in: environment -> Kaggle Secrets / Colab Secrets (HF_TOKEN or hf_token) -> a saved login -> asks you to type one (interactive only).
HOW_TO_MAKE_TOKEN = """
No Hugging Face token found. To create one:
  1. Open https://huggingface.co/settings/tokens  ->  'Create new token'
  2. Type: 'Read' is enough (to publish later use 'Write'). If the VishwamAI repo is private, the token's account must have access to it.
  3. Copy the token (it starts with hf_...). Kaggle: Add-ons > Secrets > Add Secret, label HF_TOKEN, paste it, and TICK the checkbox so it is
     attached to this notebook. Colab: key icon > Add new secret, name HF_TOKEN, Notebook access on. (Secrets cannot be created from code.)
  4. Re-run this cell.  For a quick interactive test you can also just paste the token into the prompt that appears."""

def find_hf_token():
    t = os.environ.get('HF_TOKEN')
    if t: return t, 'environment'
    for label in ('HF_TOKEN', 'hf_token'):
        try:
            from kaggle_secrets import UserSecretsClient
            return UserSecretsClient().get_secret(label), f"Kaggle secret '{label}'"
        except Exception: pass
        try:
            from google.colab import userdata
            return userdata.get(label), f"Colab secret '{label}'"
        except Exception: pass
    try:
        from huggingface_hub import get_token
        t = get_token()
        if t: return t, 'saved Hugging Face login'
    except Exception: pass
    return None, None

HF_TOKEN, _src = find_hf_token()
if not HF_TOKEN and STUDENT.startswith('VishwamAI/'):            # the base repo is private: a token is required
    print(HOW_TO_MAKE_TOKEN)
    if os.environ.get('KAGGLE_KERNEL_RUN_TYPE') == 'Batch':      # a saved run cannot ask
        raise RuntimeError('HF_TOKEN missing in a saved run: create the Kaggle secret as described above, then Save Version again.')
    import getpass
    HF_TOKEN = getpass.getpass('Paste your Hugging Face token (hidden): ').strip(); _src = 'typed in'
if HF_TOKEN:
    from huggingface_hub import HfApi
    try:
        print(f"Hugging Face token found ({_src}); logged in as:", HfApi().whoami(token=HF_TOKEN)['name'])
    except Exception as e:
        raise RuntimeError(f'The token was rejected ({type(e).__name__}). Create a new one as described above.')
    os.environ['HF_TOKEN'] = HF_TOKEN

print('GPU:', torch.cuda.get_device_name(0), '| fp16 only on T4 (no bf16)')

# ---------------- 2. GSM8K data and helpers ----------------
from datasets import load_dataset
gtr = load_dataset('openai/gsm8k', 'main', split='train')
gte = load_dataset('openai/gsm8k', 'main', split='test')
def gold(a): return a.split('####')[-1].strip().replace(',', '')
def make_prompt(q): return f"Question: {q}\nSolve step by step and end with '#### <number>'.\nAnswer:"

def extract(text):
    m = re.findall(r'####\s*(-?[\d,]*\.?\d+)', text)
    if m: return m[0].replace(',', '')
    m = re.findall(r'-?\d[\d,]*\.?\d*', text)            # fallback: last number
    return m[-1].replace(',', '').rstrip('.') if m else None
def same(a, b):
    try: return abs(float(a) - float(b)) < 1e-4
    except Exception: return False

# decontamination: drop any training question sharing an 8-word window with a GSM8K *test* question
def grams(t, n=8):
    w = re.findall(r'\w+', t.lower()); return {' '.join(w[i:i + n]) for i in range(max(0, len(w) - n + 1))}
TEST_GRAMS = set().union(*[grams(q) for q in gte['question']])
def contaminated(q): return bool(grams(q) & TEST_GRAMS)
print('train', len(gtr), '| test', len(gte), '| test 8-grams', len(TEST_GRAMS))
print('contaminated train questions:', sum(contaminated(q) for q in gtr['question']), '(expected ~0)')

# ---------------- 3. load the student ----------------
from transformers import AutoTokenizer, AutoModelForCausalLM
HF_TOKEN = os.environ.get('HF_TOKEN')                   # set by the setup cell (None for a public student)

dtype = torch.float32 if FULL_FT else torch.float16
tok = AutoTokenizer.from_pretrained(STUDENT, token=HF_TOKEN)
if tok.pad_token is None: tok.pad_token = tok.eos_token
try:                                                    # newer transformers: `dtype`; older: `torch_dtype`
    model = AutoModelForCausalLM.from_pretrained(STUDENT, dtype=dtype, token=HF_TOKEN)
except TypeError:
    model = AutoModelForCausalLM.from_pretrained(STUDENT, torch_dtype=dtype, token=HF_TOKEN)
model = model.to('cuda:0')
NG = torch.cuda.device_count(); print('GPUs:', NG)

# VishwamAI was pre-trained with every sequence starting with the EOS token (its BOS convention)
BOS_IDS = [tok.eos_token_id] if FULL_FT else []
def encode_prompt(q): return BOS_IDS + tok(make_prompt(q), add_special_tokens=False)['input_ids']

import copy, concurrent.futures as cf

@torch.no_grad()
def evaluate(m, n=N_EVAL, bs=75, max_new=256):   # big batches: these small models leave the GPUs idle at bs=16
    """Greedy GSM8K accuracy. With 2 GPUs a copy of the model runs on each and they take alternate batches."""
    m.eval(); qs, ans = gte['question'][:n], [gold(a) for a in gte['answer'][:n]]
    reps = [m] + [copy.deepcopy(m).to(f'cuda:{g}').eval() for g in range(1, NG)]
    batches = [(qs[i:i + bs], ans[i:i + bs]) for i in range(0, len(qs), bs)]
    def work(rep, mine):
        dev = next(rep.parameters()).device; ok = 0
        for qb, ab in mine:
            ids = [encode_prompt(q) for q in qb]; L = max(map(len, ids))
            inp = torch.tensor([[tok.pad_token_id] * (L - len(x)) + x for x in ids]).to(dev)        # left padding
            att = torch.tensor([[0] * (L - len(x)) + [1] * len(x) for x in ids]).to(dev)
            out = rep.generate(input_ids=inp, attention_mask=att, max_new_tokens=max_new, do_sample=False,
                               pad_token_id=tok.pad_token_id)
            for o, a in zip(out[:, L:], ab):
                t = tok.decode(o, skip_special_tokens=True).split('\nQuestion:')[0]
                ok += same(extract(t), a)
        return ok
    with cf.ThreadPoolExecutor(len(reps)) as ex:
        oks = list(ex.map(work, reps, [batches[g::len(reps)] for g in range(len(reps))]))
    del reps
    torch.cuda.empty_cache()
    return sum(oks) / len(qs)

# ---------------- 3b. baseline ----------------
if RUN_BASELINE:
    base_acc = evaluate(model)
else:
    base_acc = BASELINE_ACC
print(f'student BEFORE distillation: {100 * base_acc:.1f}% on {N_EVAL} GSM8K test questions (greedy)')


# ---------------- 4. build the SFT set (human GSM8K solutions; teacher rows are used if present) ----------------
import os, json, re, glob, random
import torch

# --- preflight: stop early with a clear message instead of a NameError ---
_missing = [n for n in ('tok', 'gtr', 'gte', 'encode_prompt', 'make_prompt', 'MATH_SUFFIX', 'WORK', 'contaminated', 'FULL_FT', 'MAX_LEN') if n not in globals()]
if _missing:
    raise RuntimeError("Not defined yet: " + ", ".join(_missing) + ". This session was probably restarted. Run these cells first, in order: "
                       "1) pip install  2) setup (token)  3) GSM8K data and helpers  4) load the student  5) build the SFT set"
                       " - then run this cell again. (You need to run up to: section 3, load the student.)")

def clean_human(a):
    body, ans = a.split('####'); body = re.sub(r'<<.*?>>', '', body).strip()
    return f"{body}\n#### {ans.strip().replace(',', '')}"

pairs = []                                            # (question, target)
for p in sorted(glob.glob(f'{WORK}/math/out_*.jsonl')) + [f'{WORK}/distill/voted.jsonl']:
    if not os.path.exists(p): continue
    for line in open(p, encoding='utf-8'):
        r = json.loads(line)
        if '####' not in r['answer']: continue                    # math rows only
        q = r['prompt'].replace(MATH_SUFFIX, '')
        think = r['think'] if 0 < len(r['think']) <= 2500 else ''
        pairs.append((q, (think + '\n' if think else '') + r['answer']))
n_teacher = len(pairs)
pairs += [(q, clean_human(a)) for q, a in zip(gtr['question'], gtr['answer'])]       # human solutions as extra data
pairs = [(q, t) for q, t in pairs if not contaminated(q)]
random.shuffle(pairs)

examples = []
for q, t in pairs:
    pi = encode_prompt(q)
    ti = tok(' ' + t, add_special_tokens=False)['input_ids'] + [tok.eos_token_id]
    if len(pi) + len(ti) <= MAX_LEN:
        examples.append(dict(input_ids=pi + ti, labels=[-100] * len(pi) + ti))      # loss on the answer only
print(f'{len(examples)} examples ({n_teacher} teacher rows before filtering, {len(gtr)} human GSM8K-train solutions)')
assert len(examples) > 0

def collate(b):
    L = max(len(x['input_ids']) for x in b)
    pad = lambda v, fill: v + [fill] * (L - len(v))
    return dict(input_ids=torch.tensor([pad(x['input_ids'], tok.pad_token_id) for x in b]),
                labels=torch.tensor([pad(x['labels'], -100) for x in b]),
                attention_mask=torch.tensor([[1] * len(x['input_ids']) + [0] * (L - len(x['input_ids'])) for x in b]))

# ---------------- 5. train ----------------
# --- preflight: stop early with a clear message instead of a NameError ---
_missing = [n for n in ('FULL_FT', 'model', 'tok', 'examples', 'collate', 'NG', 'WORK', 'SLUG') if n not in globals()]
if _missing:
    raise RuntimeError("Not defined yet: " + ", ".join(_missing) + ". This session was probably restarted. Run these cells first, in order: "
                       "1) pip install  2) setup (token)  3) GSM8K data and helpers  4) load the student  5) build the SFT set"
                       " - then run this cell again. (You need to run up to: section 5, build the SFT set.)")

from transformers import Trainer, TrainingArguments
import inspect, math

if FULL_FT:
    GC = False                                            # 132M model: no need to trade speed for memory
    LR, EPOCHS = 1e-4, 3                                  # 132M from-scratch model: full fine-tune, fp32 weights + fp16 autocast
else:
    from peft import LoraConfig, get_peft_model
    GC = True
    model.gradient_checkpointing_enable(); model.enable_input_require_grads()
    model = get_peft_model(model, LoraConfig(r=16, lora_alpha=32, lora_dropout=0.05, task_type='CAUSAL_LM',
            target_modules=['q_proj', 'k_proj', 'v_proj', 'o_proj', 'gate_proj', 'up_proj', 'down_proj']))
    for p in model.parameters():
        if p.requires_grad: p.data = p.data.float()       # fp16 base + fp32 adapters (required for fp16 training)
    model.print_trainable_parameters()
    LR, EPOCHS = 2e-4, 2

NGPU = max(1, NG)
PER_DEV, ACC = (4, 8) if not FULL_FT else (16, 2)         # tiny model: large per-GPU batch; lower 16 -> 8 if you hit out-of-memory
ACC = max(1, ACC // NGPU)                                  # Trainer uses every visible GPU (DataParallel): keep the effective batch size
EFF = PER_DEV * NGPU * ACC
TOTAL_STEPS = math.ceil(len(examples) / EFF) * EPOCHS
WARMUP = max(1, int(0.03 * TOTAL_STEPS))                   # explicit steps: `warmup_ratio` was removed in newer transformers
print(f'effective batch = {PER_DEV} x {NGPU} GPUs x {ACC} accumulation = {EFF} | {len(examples)} examples | {TOTAL_STEPS} steps | warmup {WARMUP}')

arg_kw = dict(output_dir=f'{WORK}/math/run_{SLUG}', per_device_train_batch_size=PER_DEV,
              gradient_accumulation_steps=ACC, num_train_epochs=EPOCHS, learning_rate=LR,
              lr_scheduler_type='cosine', warmup_steps=WARMUP, fp16=True, logging_steps=20,
              save_strategy='epoch', save_total_limit=1, report_to='none',
              gradient_checkpointing=GC, remove_unused_columns=False,
              group_by_length=True, dataloader_num_workers=2)
supported = set(inspect.signature(TrainingArguments.__init__).parameters)
skipped = [k for k in arg_kw if k not in supported]
if skipped: print('this transformers version does not support, skipping:', skipped)
args = TrainingArguments(**{k: v for k, v in arg_kw.items() if k in supported})

class DS(torch.utils.data.Dataset):
    def __len__(self): return len(examples)
    def __getitem__(self, i): return examples[i]
trainer = Trainer(model=model, args=args, train_dataset=DS(), data_collator=collate)
trainer.train()
OUT_DIR = f'{WORK}/math/{SLUG}-{"full" if FULL_FT else "lora"}'
model.save_pretrained(OUT_DIR); tok.save_pretrained(OUT_DIR)     # full weights for FULL_FT, adapter for LoRA
print('saved', OUT_DIR)


# ---------------- 6. evaluate AFTER and compare ----------------
# --- preflight: stop early with a clear message instead of a NameError ---
_missing = [n for n in ('model', 'evaluate', 'base_acc', 'examples', 'STUDENT', 'N_EVAL', 'FULL_FT', 'WORK') if n not in globals()]
if _missing:
    raise RuntimeError("Not defined yet: " + ", ".join(_missing) + ". This session was probably restarted. Run these cells first, in order: "
                       "1) pip install  2) setup (token)  3) GSM8K data and helpers  4) load the student  5) build the SFT set"
                       " - then run this cell again. (You need to run up to: section 6, training (and run the baseline cell in section 3 or set base_acc = 0.013).)")

model.config.use_cache = True
after_acc = evaluate(model)
print(f"{'':28s}{'GSM8K (greedy, ' + str(N_EVAL) + ' q)':>26s}")
print(f"{'student before':28s}{100 * base_acc:>25.1f}%")
print(f"{'after distillation + SFT':28s}{100 * after_acc:>25.1f}%")
print(f"{'change':28s}{100 * (after_acc - base_acc):>+25.1f} points   (noise is about +-3 points at n={N_EVAL})")
print('target: 50%  ->', 'reached' if after_acc >= 0.5 else 'not reached')
rp = f'{WORK}/math/results.json'
R = json.load(open(rp)) if os.path.exists(rp) else {}
R[STUDENT] = dict(before=base_acc, after=after_acc, n_eval=N_EVAL, full_ft=FULL_FT, examples=len(examples))
json.dump(R, open(rp, 'w'), indent=1)
print('\nall runs so far (GSM8K greedy):')
for k, v in R.items():
    print(f"  {k:36s} before {100 * v['before']:5.1f}%  after {100 * v['after']:5.1f}%  (n={v['n_eval']}, {v['examples']} examples)")
