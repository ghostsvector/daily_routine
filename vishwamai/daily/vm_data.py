"""vm_data.py - builds the per-subject token shards used by the daily trainer.
One streaming pass over a few open corpora; a keyword router sends each document to the subject it fits best.
Shards are uint16 files {name}.train.bin / {name}.val.bin plus {name}.done (written last, so a half-built shard is never used)."""
import os, re, json, random
import numpy as np

VAL_TOKENS = 100_000

ROUTER = {   # subject shard -> keywords (lower-case); a document needs >= MIN_HITS distinct keyword hits and the highest score wins
 'subj_physics_chem': 'physics chemistry atom molecule energy force velocity acceleration quantum electron proton reaction acid base element compound thermodynamic entropy wavelength gravity magnetic voltage periodic table bond solution catalyst'.split(),
 'subj_biology_health': 'biology cell dna gene protein enzyme organism species evolution disease virus bacteria immune medicine patient symptom vaccine nutrition vitamin heart brain tissue ecosystem photosynthesis hormone'.split(),
 'subj_reasoning': 'therefore because hence implies conclude premise logic deduce proof argument if then contradiction puzzle riddle assume suppose consequently inference'.split(),
 'subj_history_geo': 'history empire war dynasty century revolution kingdom treaty colonial ancient medieval continent river mountain climate capital population border independence civilization'.split(),
 'subj_econ_law': 'economy economic market inflation gdp trade tax law court legal constitution contract rights government policy supply demand bank interest investment regulation judge statute'.split(),
 'subj_philosophy_lit': 'philosophy ethics moral metaphysics novel poem poetry author literature narrative metaphor theme shakespeare plato aristotle kant character plot essay philosopher'.split(),
 'subj_everyday': 'recipe cook kitchen travel health tips home garden budget shopping family friend weekend exercise sleep how to advice daily routine hobby cleaning'.split(),
 'subj_math': 'theorem lemma proof integral derivative equation polynomial matrix vector probability algebra geometry triangle prime function limit sum variance'.split(),
}
MIN_HITS = 3
SOURCES = [   # (hf path, config, split, text field, tag)
  ('HuggingFaceFW/fineweb-edu', 'sample-10BT', 'train', 'text', 'web'),
  ('HuggingFaceTB/cosmopedia', 'web_samples_v2', 'train', 'text', 'web'),
  ('wikimedia/wikipedia', '20231101.en', 'train', 'text', 'wiki'),
]

def route(text):
    """-> subject shard name or None"""
    low = text.lower(); words = set(re.findall(r"[a-z]+", low)); best, bs = None, 0
    for shard, kws in ROUTER.items():
        s = sum(1 for k in kws if (k in words if ' ' not in k else k in low))
        if s > bs: best, bs = shard, s
    return best if bs >= MIN_HITS else None

def reasoning_docs(n_arith=20000, seed=0, gsm_train=True):
    """verifiable reasoning text: programmatic arithmetic/logic word problems (+ GSM8K *train* solutions if available).
    GSM8K test is never touched."""
    r = random.Random(seed); out = []
    names = ['Asha', 'Ravi', 'Meera', 'Kiran', 'Sita', 'Arjun']; things = ['apples', 'books', 'pens', 'marbles', 'coins']
    for _ in range(n_arith):
        a, b, c = r.randint(2, 99), r.randint(2, 99), r.randint(2, 9); who = r.choice(names); th = r.choice(things)
        kind = r.randint(0, 3)
        if kind == 0:
            out.append(f"Question: {who} has {a} {th} and gets {b} more. How many {th} now?\nAnswer: {a} + {b} = {a+b}. The answer is {a+b}.")
        elif kind == 1:
            hi, lo = max(a, b), min(a, b)
            out.append(f"Question: {who} has {hi} {th} and gives away {lo}. How many are left?\nAnswer: {hi} - {lo} = {hi-lo}. The answer is {hi-lo}.")
        elif kind == 2:
            out.append(f"Question: There are {c} boxes with {a} {th} in each. How many {th} in total?\nAnswer: {c} x {a} = {c*a}. The answer is {c*a}.")
        else:
            out.append(f"Question: If all {th} are useful and {who}'s bag has only {th}, is everything in the bag useful?\nAnswer: Yes. Every item in the bag is one of the {th}, and all {th} are useful, therefore everything is useful.")
    if gsm_train:
        try:
            from datasets import load_dataset
            for ex in load_dataset('openai/gsm8k', 'main', split='train'):
                sol = re.sub(r'<<[^>]*>>', '', ex['answer']).replace('####', 'The answer is')
                out.append(f"Question: {ex['question']}\nAnswer: {sol}")
        except Exception as e:
            print('GSM8K train not loaded:', type(e).__name__, str(e)[:80])
    r.shuffle(out); return out

class ShardWriter:
    def __init__(self, d, name, sp):
        self.d, self.name, self.sp = d, name, sp
        self.tr = open(f'{d}/{name}.train.bin.part', 'wb'); self.va = open(f'{d}/{name}.val.bin.part', 'wb')
        self.n_tr = self.n_va = 0
    def add(self, text, eos=3):
        ids = np.asarray(self.sp.encode(text) + [eos], dtype=np.uint16)
        if self.n_va < VAL_TOKENS: ids.tofile(self.va); self.n_va += len(ids)
        else: ids.tofile(self.tr); self.n_tr += len(ids)
    def close(self):
        self.tr.close(); self.va.close()
        for sp in ('train', 'val'): os.replace(f'{self.d}/{self.name}.{sp}.bin.part', f'{self.d}/{self.name}.{sp}.bin')
        open(f'{self.d}/{self.name}.done', 'w').write(json.dumps(dict(train=self.n_tr, val=self.n_va)))
        return self.n_tr, self.n_va

def _stream(path, cfg, split, field):
    from datasets import load_dataset
    for ex in load_dataset(path, cfg, split=split, streaming=True):
        t = ex.get(field)
        if t and len(t) > 300: yield t

def build_subject_shards(data_dir, sp, tokens_per_subject=20_000_000, max_docs_per_source=3_000_000, log=print):
    """reasoning shard from programmatic + GSM8K-train text; the other subjects from one streaming pass over SOURCES
    (router picks the subject; a subject stops at its token budget). Subjects whose .done exists are skipped."""
    os.makedirs(data_dir, exist_ok=True)
    pending = lambda s: not os.path.exists(f'{data_dir}/{s}.done')
    if pending('subj_reasoning'):
        w = ShardWriter(data_dir, 'subj_reasoning', sp)
        for t in reasoning_docs(): w.add(t)
        n = w.close(); log('subj_reasoning: train/val tokens', n)
    W = {s: ShardWriter(data_dir, s, sp) for s in ROUTER if s != 'subj_reasoning' and pending(s)}
    if not W: log('all subject shards already built'); return
    open_w = lambda: [s for s, w in W.items() if w.n_tr < tokens_per_subject]
    for path, cfg, split, field, tag in SOURCES:
        if not open_w(): break
        log(f'streaming {path} ...'); seen = 0
        try:
            for text in _stream(path, cfg, split, field):
                seen += 1
                if seen > max_docs_per_source: break
                s = route(text)
                if s in W and W[s].n_tr < tokens_per_subject: W[s].add(text)
                if seen % 20000 == 0:
                    log(f'  {seen} docs | ' + ' '.join(f'{k[5:]}={w.n_tr/1e6:.1f}M' for k, w in W.items()))
                    if not open_w(): break
        except Exception as e:
            log(f'  source failed: {type(e).__name__}: {str(e)[:120]}')
    for s, w in W.items():
        n_tr, n_va = w.close(); log(f'{s}: train {n_tr/1e6:.2f}M val {n_va/1e3:.0f}k tokens')
