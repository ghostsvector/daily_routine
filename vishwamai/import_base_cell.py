# ---- Import the pre-trained base model from the Kaggle draft (paste as a notebook cell,
# ---- after the setup cell that defines WORK, before any run_pretrain call) ----
# run_pretrain(tag, ...) already returns early with "already finished -> loading" when
# {WORK}/ckpt/{tag}_final.msgpack exists, so placing the draft's files is all that's needed.
#
# Where the draft's output lives (pick one):
#   a) running on Kaggle: attach the draft's output / a dataset to this notebook -> /kaggle/input/...
#   b) running elsewhere: set KAGGLE_REF to a dataset or kernel-output slug and provide
#      KAGGLE_USERNAME / KAGGLE_KEY as secrets (never paste them into the notebook).
KAGGLE_REF = ''   # e.g. 'kasinadhsarma1/vishwamai-draft' (dataset slug) - leave '' if attached on Kaggle
FILES = ['pt_final.msgpack', 'ctx_final.msgpack']      # ctx = after 4k YaRN extension (preferred)
TOK = ['vishwamai.model', 'vishwamai.vocab']

SRC = None
if KAGGLE_REF:
    os.system('pip -q install kagglehub')
    import kagglehub
    SRC = kagglehub.dataset_download(KAGGLE_REF)       # use kagglehub.model_download for a Kaggle Model
else:
    for root in ('/kaggle/input', '/kaggle/working'):
        hits = glob.glob(f'{root}/**/pt_final.msgpack', recursive=True)
        if hits:
            SRC = os.path.dirname(os.path.dirname(hits[0])) if hits[0].endswith('/ckpt/pt_final.msgpack') \
                else os.path.dirname(hits[0])
            break
assert SRC, 'draft output not found: attach it on Kaggle or set KAGGLE_REF'

def find(name):
    hits = glob.glob(f'{SRC}/**/{name}', recursive=True)
    return hits[0] if hits else None

for name, sub in [(n, 'ckpt') for n in FILES] + [(n, 'tok') for n in TOK]:
    p = find(name)
    if p is None:
        print(f'  - {name}: not in the draft output (skipped)'); continue
    shutil.copy(p, f'{WORK}/{sub}/{name}')
    print(f'  + {name} ({os.path.getsize(p) / 1e6:.1f} MB) -> {WORK}/{sub}/')

assert os.path.exists(f'{WORK}/ckpt/pt_final.msgpack'), 'pt_final.msgpack missing: draft did not finish pre-training'
assert os.path.exists(f'{WORK}/tok/vishwamai.model'), 'tokenizer missing: SentencePiece ids must match the weights'
# Config must match the draft: same PRESET ('base'), VOCAB (40960) and SEQ_LEN as the cell-5 config.
