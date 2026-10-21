"""Builds vishwamai_gemma31b_eval.ipynb: plain Gemma 4 31B vs Gemma + LoRA adapter on MMLU / MMLU-Pro (test sets used for evaluation only)."""
import json, os
HERE = os.path.dirname(os.path.abspath(__file__))
src = json.load(open(f'{HERE}/vishwamai_gemma31b_topics_qlora.ipynb'))['cells']
def find(marker, kind='code'):
    for c in src:
        t = ''.join(c['source'])
        if c['cell_type'] == kind and marker in t: return t
    raise KeyError(marker)
def md(s): return dict(cell_type='markdown', metadata={}, source=s.strip('\n').splitlines(True))
def code(s): return dict(cell_type='code', metadata={}, execution_count=None, outputs=[], source=s.strip('\n').splitlines(True))

cfg = find('import os, sys, json, time').replace("TOPIC = 'mmlu'", "TOPIC = 'eval'") + '''
N_MMLU = 300; N_PRO = 300           # questions sampled from each test set (fixed seed, same for base and tuned)
MAX_EVAL_TOKENS = 1024              # longer questions are skipped (for both models)
'''
cells = [
md('''# Evaluate: plain Gemma 4 31B vs Gemma + VishwamAI LoRA adapter
Both models answer the **same** randomly sampled questions from the MMLU and MMLU-Pro **test** sets (used for evaluation only, never for training). Scoring: the model's probability for each answer letter right after the prompt; the highest wins.
Reports accuracy with a 95% Wilson interval and a paired comparison (how many questions only the tuned model got right vs only the base model). With 300 questions the interval is about +-5 points, so a small difference is not evidence of a gain.

**Setup on Kaggle:** Accelerator GPU T4 x2, Internet on, secret `HF_TOKEN`. Add your training notebook's output as an input (Add Input -> Notebook Output Files -> *Vishwamai QLORA*) so the adapter is found at `/kaggle/input/...`; or leave it if the adapter is in `/kaggle/working`.'''),
code('%pip -q install -U transformers peft bitsandbytes accelerate datasets huggingface_hub safetensors'),
code(cfg),
code(find('def get_hf_token')),
code(find('# Guard:')),
code(find('from transformers import AutoTokenizer, BitsAndBytesConfig')),
code('''
# Find the adapter and attach it. Order: ADAPTER_PATH (a folder you set) -> ADAPTER_REPO (Hugging Face) -> files already here
# (this session / attached inputs / WORK) -> download the public Kaggle notebook output (kagglehub, then the kaggle CLI).
ADAPTER_PATH = ''                          # e.g. '/kaggle/input/vishwamai-qlora/vishwamai/gemma/adapter'
ADAPTER_REPO = ''                          # e.g. 'VishwamAI/vishwamai-gemma4-31b-lora-v0' (private is fine; needs HF_TOKEN)
KAGGLE_NOTEBOOK = 'bmentech/vishwamai-qlora'
from peft import PeftModel
def find_adapter(root):
    hits = glob.glob(f'{root}/**/adapter_config.json', recursive=True)
    return os.path.dirname(hits[0]) if hits else None
ADAPTER = ADAPTER_PATH or None
if ADAPTER:
    assert os.path.exists(f'{ADAPTER}/adapter_config.json'), f'no adapter_config.json in {ADAPTER}'
if not ADAPTER and ADAPTER_REPO:
    from huggingface_hub import snapshot_download
    ADAPTER = snapshot_download(ADAPTER_REPO, token=HF_TOKEN, allow_patterns=['adapter_*'])
for root in (ADAPTER_DIR, '/kaggle/input', WORK):
    if not ADAPTER and os.path.exists(root): ADAPTER = find_adapter(root)
if not ADAPTER and KAGGLE_NOTEBOOK:
    print('adapter not found locally; downloading the output of', KAGGLE_NOTEBOOK)
    dest = '/kaggle/working/adapter_dl'; os.makedirs(dest, exist_ok=True)
    try:
        import kagglehub
        ADAPTER = find_adapter(kagglehub.notebook_output_download(KAGGLE_NOTEBOOK))
    except Exception as e:
        print('  kagglehub failed:', type(e).__name__, str(e)[:200])
    if not ADAPTER:
        r = subprocess.run(['kaggle', 'kernels', 'output', KAGGLE_NOTEBOOK, '-p', dest], capture_output=True, text=True)
        print('  kaggle CLI:', (r.stdout + r.stderr)[-400:]); ADAPTER = find_adapter(dest)
if not ADAPTER:
    print('/kaggle/input contains:', [os.path.join(d, x) for d, _, fs in os.walk('/kaggle/input') for x in fs][:30] if os.path.exists('/kaggle/input') else 'nothing')
    raise RuntimeError('adapter not found. Use Add Input -> your vishwamai-qlora notebook output, or set ADAPTER_PATH / ADAPTER_REPO, then re-run this cell.')
print('adapter:', ADAPTER)
model = PeftModel.from_pretrained(model, ADAPTER, is_trainable=False)
model.eval(); model.config.use_cache = True
'''),
code('''
import random, math
from datasets import load_dataset
tok.truncation_side = 'left'
if not getattr(tok, 'chat_template', None):          # same template logic as in training
    try: tok.chat_template = AutoTokenizer.from_pretrained(MODEL_ID + '-it', token=HF_TOKEN, cache_dir=CACHE_DIR).chat_template; print('chat template from -it')
    except Exception as e:
        print('using simple template:', type(e).__name__)
        tok.chat_template = ("{{ bos_token }}{% for m in messages %}<start_of_turn>{{ 'model' if m['role'] == 'assistant' else m['role'] }}\\n"
                             "{{ m['content'] }}<end_of_turn>\\n{% endfor %}{% if add_generation_prompt %}<start_of_turn>model\\n{% endif %}")
LET = 'ABCDEFGHIJ'
let_ids = [tok.encode(c, add_special_tokens=False) for c in LET]
assert all(len(x) == 1 for x in let_ids), 'letters are not single tokens in this tokenizer'
let_ids = [x[0] for x in let_ids]

def build(q, opts):
    body = q + '\\n' + '\\n'.join(f'{LET[i]}. {o}' for i, o in enumerate(opts)) + '\\nAnswer with the letter.'
    return tok.apply_chat_template([{'role': 'user', 'content': body}], tokenize=False, add_generation_prompt=True)

def sample(ds, n, to_item, seed=0):
    idx = list(range(len(ds))); random.Random(seed).shuffle(idx); out = []
    for i in idx:
        q, opts, gold = to_item(ds[i]); text = build(q, opts)
        ids = tok(text, add_special_tokens=False, return_tensors='pt').input_ids
        if ids.shape[1] <= MAX_EVAL_TOKENS: out.append((ids, len(opts), gold))
        if len(out) >= n: break
    return out

mmlu = load_dataset('cais/mmlu', 'all', split='test', token=HF_TOKEN)
items_mmlu = sample(mmlu, N_MMLU, lambda ex: (ex['question'], ex['choices'], ex['answer']))
try:
    pro = load_dataset('TIGER-Lab/MMLU-Pro', split='test', token=HF_TOKEN)
    items_pro = sample(pro, N_PRO, lambda ex: (ex['question'], ex['options'], ex['answer_index']), seed=1)
except Exception as e:
    print('MMLU-Pro not loaded:', type(e).__name__, str(e)[:200]); items_pro = []
print(len(items_mmlu), 'MMLU questions,', len(items_pro), 'MMLU-Pro questions')
'''),
code('''
@torch.no_grad()
def run(items, tag):
    ok = []; t0 = time.time()
    for j, (ids, n_opt, gold) in enumerate(items):
        ids = ids.to('cuda:0')
        with torch.autocast('cuda', dtype=DT):
            try: lg = model(input_ids=ids, logits_to_keep=1).logits[0, -1]
            except TypeError: lg = model(input_ids=ids).logits[0, -1]
        pred = int(torch.argmax(lg[let_ids[:n_opt]]).item()); ok.append(int(pred == gold))
        if (j + 1) % 50 == 0: print(f'  {tag}: {j+1}/{len(items)}  acc so far {sum(ok)/len(ok):.3f}  ({(time.time()-t0)/60:.1f} min)')
    return ok

def wilson(k, n, z=1.96):
    if n == 0: return (float('nan'),) * 2
    p = k / n; d = 1 + z*z/n; c = (p + z*z/(2*n)) / d; h = z * math.sqrt(p*(1-p)/n + z*z/(4*n*n)) / d
    return c - h, c + h

def sign_test(b, c):          # exact two-sided sign test on the questions where the two models differ
    n = b + c
    if n == 0: return 1.0
    k = min(b, c); p = sum(math.comb(n, i) for i in range(0, k + 1)) / 2**n
    return min(1.0, 2 * p)

results = {}
for name, items in (('MMLU', items_mmlu), ('MMLU-Pro', items_pro)):
    if not items: continue
    with model.disable_adapter(): base = run(items, name + ' base')
    tuned = run(items, name + ' tuned')
    n = len(items); kb, kt = sum(base), sum(tuned)
    only_t = sum(1 for x, y in zip(base, tuned) if y and not x); only_b = sum(1 for x, y in zip(base, tuned) if x and not y)
    lb, ub = wilson(kb, n); lt, ut = wilson(kt, n)
    results[name] = dict(n=n, base=kb/n, base_ci=[lb, ub], tuned=kt/n, tuned_ci=[lt, ut], only_tuned_right=only_t, only_base_right=only_b, sign_test_p=sign_test(only_t, only_b))
    print(f"\\n{name} (n={n}): base {kb/n:.3f} [{lb:.3f}, {ub:.3f}] | tuned {kt/n:.3f} [{lt:.3f}, {ut:.3f}] | only tuned right {only_t}, only base right {only_b}, sign-test p={results[name]['sign_test_p']:.3f}")
os.makedirs(f'{GDIR}/results', exist_ok=True)
json.dump(dict(model=MODEL_ID, adapter=ADAPTER, time=time.strftime('%Y-%m-%d %H:%M'), results=results), open(f'{GDIR}/results/eval_{time.strftime("%Y%m%d_%H%M")}.json', 'w'), indent=1)
print('\\nsaved to', f'{GDIR}/results/')
'''),
md('''## How to read the result
- If the two intervals overlap heavily and the sign-test p-value is above 0.05, the adapter did **not** measurably change MMLU on this sample. That is an honest result, not a failure of the notebook.
- A gain on MMLU-Pro from MMLU-style training would be a bonus; no change is the expected outcome.
- For a tighter estimate raise `N_MMLU` / `N_PRO` (each model needs roughly 1 second per question on two T4s - an estimate, check the timing lines).'''),
]
path = f'{HERE}/vishwamai_gemma31b_eval.ipynb'
json.dump(dict(cells=cells, metadata=dict(kernelspec=dict(name='python3', display_name='Python 3'), accelerator='GPU'), nbformat=4, nbformat_minor=5), open(path, 'w'), indent=1)
print('wrote', path, len(cells), 'cells')
