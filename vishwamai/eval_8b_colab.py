# ====================================================================================
# Baseline: DeepSeek-R1-0528-Qwen3-8B (4-bit) on GSM8K, on a free Colab T4. Resumable: every answer is saved to Drive.
# Paste into ONE cell (Runtime > Change runtime type > T4 GPU), run, and re-run after a disconnect to continue.
# ====================================================================================
MODEL = 'deepseek-ai/DeepSeek-R1-0528-Qwen3-8B'
N_EVAL = 100            # number of GSM8K test questions (start small: reasoning models write long answers)
MAX_NEW = 2048          # thinking budget; answers cut off before the final answer count as wrong (reported as 'truncated')
BATCH = 16
TEMPERATURE, TOP_P = 0.6, 0.95      # DeepSeek's recommended sampling for R1 models (greedy tends to loop)
SEED = 0

import subprocess, sys, os, re, json, math, time
subprocess.run([sys.executable, "-m", "pip", "-q", "install", "-U", "transformers", "accelerate", "bitsandbytes", "datasets"], check=False)
import torch
from datasets import load_dataset
from transformers import AutoTokenizer, AutoModelForCausalLM, BitsAndBytesConfig

# ---- Google Drive (results survive disconnects) ----
try:
    from google.colab import drive
    drive.mount('/content/drive'); OUT = '/content/drive/MyDrive/vishwamai/eval8b'
except Exception:
    OUT = './vishwamai_eval8b'
os.makedirs(OUT, exist_ok=True)
RES = f"{OUT}/gsm8k_{MODEL.split('/')[-1]}_n{N_EVAL}.jsonl"
print('results file:', RES)

# ---- helpers ----
def wilson(k, n, z=1.96):
    p = k / n; d = 1 + z * z / n; c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return 100 * (c - h), 100 * (c + h)
def gold(a): return a.split('####')[-1].strip().replace(',', '')
def to_num(s):
    s = re.sub(r'[\$,\s]|\\%|%|\\text\{[^}]*\}|\\!|\\,', '', s or '')
    m = re.findall(r'-?\d+\.?\d*', s)
    return m[-1] if m else None
def boxed(text):
    i = text.rfind('\\boxed{')
    if i < 0: return None
    j, depth = i + 7, 1
    while j < len(text) and depth:
        depth += (text[j] == '{') - (text[j] == '}'); j += 1
    return text[i + 7:j - 1] if depth == 0 else None
def answer_of(text):
    """returns (number or None, finished_thinking). Only text after </think> counts."""
    if '</think>' not in text: return None, False
    final = text.split('</think>')[-1]
    b = boxed(final)
    if b is not None: return to_num(b), True
    nums = re.findall(r'-?\d[\d,]*\.?\d*', final)
    return (nums[-1].replace(',', '') if nums else None), True
def same(a, b):
    try: return abs(float(a) - float(b)) < 1e-4
    except Exception: return False
def make_prompt(tok, q):
    msg = [{'role': 'user', 'content': q + "\nPlease reason step by step, and put your final answer within \\boxed{}."}]
    return tok.apply_chat_template(msg, tokenize=False, add_generation_prompt=True)

# ---- resume ----
done = {}
if os.path.exists(RES):
    for l in open(RES, encoding='utf-8'):
        r = json.loads(l); done[r['idx']] = r
print(f'{len(done)} of {N_EVAL} already done')

test = load_dataset('openai/gsm8k', 'main', split='test')
todo = [i for i in range(N_EVAL) if i not in done]

if todo:
    tok = AutoTokenizer.from_pretrained(MODEL); tok.padding_side = 'left'
    if tok.pad_token is None: tok.pad_token = tok.eos_token
    bnb = BitsAndBytesConfig(load_in_4bit=True, bnb_4bit_quant_type='nf4', bnb_4bit_compute_dtype=torch.float16, bnb_4bit_use_double_quant=True)
    model = AutoModelForCausalLM.from_pretrained(MODEL, quantization_config=bnb, device_map={'': 0}).eval()
    print('loaded; GPU memory used (GiB):', round(torch.cuda.memory_allocated() / 2**30, 1))
    torch.manual_seed(SEED)
    t0 = time.time()
    with open(RES, 'a', encoding='utf-8') as f:
        for s in range(0, len(todo), BATCH):
            idxs = todo[s:s + BATCH]
            prompts = [make_prompt(tok, test[i]['question']) for i in idxs]
            enc = tok(prompts, return_tensors='pt', padding=True, add_special_tokens=False).to('cuda:0')
            with torch.no_grad():
                out = model.generate(**enc, max_new_tokens=MAX_NEW, do_sample=True, temperature=TEMPERATURE, top_p=TOP_P, pad_token_id=tok.pad_token_id)
            for i, o in zip(idxs, out[:, enc['input_ids'].shape[1]:]):
                text = tok.decode(o, skip_special_tokens=True)
                # the template may already contain '<think>' in the prompt, so the generated text may lack the opening tag but has '</think>'
                num, finished = answer_of(text)
                rec = dict(idx=i, correct=bool(finished and same(num, gold(test[i]['answer']))), finished=finished, pred=num,
                           gold=gold(test[i]['answer']), tokens=int((o != tok.pad_token_id).sum()), text=text[-1500:])
                done[i] = rec; f.write(json.dumps(rec, ensure_ascii=False) + '\n')
            f.flush()
            print(f'{len(done)}/{N_EVAL} done | correct so far {sum(r["correct"] for r in done.values())} | {int(time.time() - t0)}s', flush=True)

# ---- report ----
R = [done[i] for i in range(N_EVAL) if i in done]
k, n = sum(r['correct'] for r in R), len(R)
lo, hi = wilson(k, n)
fin = sum(r['finished'] for r in R)
print(f"\n{MODEL}\nGSM8K, {n} test questions, sampling T={TEMPERATURE} top_p={TOP_P}, max_new_tokens={MAX_NEW}")
print(f"accuracy {100 * k / n:.1f}% ({k}/{n}), 95% interval {lo:.1f}-{hi:.1f}%")
print(f"finished thinking within the budget: {fin}/{n} ({100 * fin / n:.0f}%); average generated tokens: {sum(r['tokens'] for r in R) / n:.0f}")
print("If many answers were cut off, raise MAX_NEW (slower) before trusting the accuracy.")
