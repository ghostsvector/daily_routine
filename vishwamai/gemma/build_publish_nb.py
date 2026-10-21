"""Builds vishwamai_gemma_publish_adapter.ipynb: standalone notebook that uploads the LoRA adapter to Hugging Face."""
import json, os
HERE = os.path.dirname(os.path.abspath(__file__))
def md(s): return dict(cell_type='markdown', metadata={}, source=s.strip('\n').splitlines(True))
def code(s): return dict(cell_type='code', metadata={}, execution_count=None, outputs=[], source=s.strip('\n').splitlines(True))
cells = [
md('''# Publish the VishwamAI Gemma 4 LoRA adapter to Hugging Face
Uploads only the adapter files (about 490 MB), not Gemma itself, with a model card that credits Gemma 4. **Private by default.**
Before running: add your token as a secret named `HF_TOKEN` (needs **write** access to the organization or account you push to; never paste it into a cell).
On Kaggle: Add Input -> your training notebook's output (so the adapter is under `/kaggle/input`), or run this in the training session itself.'''),
code('%pip -q install -U huggingface_hub'),
code('''
import os, glob, json, shutil, time
REPO = 'VishwamAI/vishwamai-gemma4-31b-lora-v0'     # change to your own account if the organization refuses (e.g. 'your-name/vishwamai-gemma4-31b-lora-v0')
PRIVATE = True                                       # keep True until you are happy with the evaluation
BASE_MODEL = 'google/gemma-4-31B'
ADAPTER_PATH = ''                                    # folder with adapter_config.json; '' = search automatically
NOTES = 'Trained for a short run on MMLU auxiliary-train + ARC train splits (multiple choice, answer = letter). Not evaluated on a held-out benchmark yet.'

def get_hf_token():
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
        from getpass import getpass; t = getpass('Hugging Face token with WRITE access (hidden): ')
    return t

def find_adapter():
    if ADAPTER_PATH: return ADAPTER_PATH
    for root in ('/kaggle/working', '/kaggle/input', '/content', '.'):
        hits = glob.glob(f'{root}/**/adapter_config.json', recursive=True)
        if hits: return os.path.dirname(hits[0])
    return None

ADAPTER = find_adapter()
assert ADAPTER and os.path.exists(f'{ADAPTER}/adapter_model.safetensors'), 'adapter not found: attach the training notebook output as an input or set ADAPTER_PATH'
print('adapter folder:', ADAPTER, '|', round(os.path.getsize(f'{ADAPTER}/adapter_model.safetensors') / 1e6), 'MB')
'''),
code('''
from huggingface_hub import HfApi
pub = '/kaggle/working/pub' if os.path.exists('/kaggle/working') else './pub'
shutil.rmtree(pub, ignore_errors=True); os.makedirs(pub)
for f in ('adapter_config.json', 'adapter_model.safetensors'): shutil.copy(f'{ADAPTER}/{f}', pub)
card = f"""---
license: apache-2.0
base_model: {BASE_MODEL}
library_name: peft
tags: [vishwamai, lora, qlora]
---
# VishwamAI on Gemma 4 31B (LoRA adapter, v0)

LoRA adapter trained on top of [{BASE_MODEL}](https://huggingface.co/{BASE_MODEL}) (Apache-2.0, Google).
This is a **derived model**: its capability comes from Gemma 4. The adapter was trained with QLoRA (4-bit base, rank 16).

{NOTES}

No benchmark claims are made in this card. Load with `peft`:
```python
from transformers import AutoModelForCausalLM, BitsAndBytesConfig
from peft import PeftModel
base = AutoModelForCausalLM.from_pretrained("{BASE_MODEL}", quantization_config=BitsAndBytesConfig(load_in_4bit=True), device_map="auto")
model = PeftModel.from_pretrained(base, "{REPO}")
```
Uploaded {time.strftime('%Y-%m-%d')}.
"""
open(f'{pub}/README.md', 'w').write(card)
api = HfApi(token=get_hf_token())
print('logged in as:', api.whoami()['name'])
api.create_repo(REPO, private=PRIVATE, exist_ok=True)
api.upload_folder(folder_path=pub, repo_id=REPO, commit_message='VishwamAI Gemma 4 31B LoRA adapter v0')
print('uploaded: https://huggingface.co/' + REPO, '(private)' if PRIVATE else '(public)')
'''),
md('If the upload says 403/forbidden: the token is read-only or has no write access to that organization. Create a token with *write* permission, or change `REPO` to your own username.'),
]
path = f'{HERE}/vishwamai_gemma_publish_adapter.ipynb'
json.dump(dict(cells=cells, metadata=dict(kernelspec=dict(name='python3', display_name='Python 3')), nbformat=4, nbformat_minor=5), open(path, 'w'), indent=1)
print('wrote', path)
