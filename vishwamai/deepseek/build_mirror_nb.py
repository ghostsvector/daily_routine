"""Builds vishwamai_mirror_deepseek.ipynb: copies a Hugging Face model repo (files unchanged) to your own repo, keeping LICENSE + credit."""
import json, os
HERE = os.path.dirname(os.path.abspath(__file__))
def md(s): return dict(cell_type='markdown', metadata={}, source=s.strip('\n').splitlines(True))
def code(s): return dict(cell_type='code', metadata={}, execution_count=None, outputs=[], source=s.strip('\n').splitlines(True))
cells = [
md('''# Mirror a Hugging Face model repo to your own account (files unchanged)
Copies `deepseek-ai/DeepSeek-V4.1-Flash` file for file to a repo you own. The weights, `config.json` and `LICENSE` are **not modified** (an exact copy), and a short notice crediting the original is added to the README.
Nothing is hidden or renamed inside the files: DeepSeek's license (MIT, per its listing - confirm on the repo's LICENSE file) requires the copyright notice and license text to stay with any copy.

**This copies the model; it does not make it run on Kaggle** (it is far too large for the GPUs there). Needs: Kaggle Internet on, secret `HF_TOKEN` with **write** access to the destination, and free disk of about the repo size (Kaggle `/tmp` showed ~1 TB free earlier).
The first cell checks the real size and refuses to start if the disk is too small. Both download and upload resume if the session stops: just run again.'''),
code('%pip -q install -U huggingface_hub hf_xet'),
code('''
import os, glob, shutil, time, json
SRC = 'deepseek-ai/DeepSeek-V4.1-Flash'
DST = 'VishwamAI/DeepSeek-V4.1-Flash-mirror'      # your destination repo (change to your own account if the organization refuses)
PRIVATE = True                                     # keep private; check the destination's storage quota first
WORK_DIR = '/tmp/mirror'                           # download folder (needs ~repo size free)

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
HF_TOKEN = get_hf_token()

from huggingface_hub import HfApi, snapshot_download
api = HfApi(token=HF_TOKEN)
print('logged in as:', api.whoami()['name'])
info = api.model_info(SRC, files_metadata=True)
files = [(s.rfilename, s.size or 0) for s in info.siblings]
total = sum(sz for _, sz in files)
print(f'{SRC}: {len(files)} files, total {total/1e9:.1f} GB, license tag: {[t for t in (info.tags or []) if t.startswith("license")]}')
for n, sz in sorted(files, key=lambda x: -x[1])[:8]: print(f'  {sz/1e9:8.1f} GB  {n}')
os.makedirs(WORK_DIR, exist_ok=True)
free = shutil.disk_usage(WORK_DIR).free
print(f'free disk at {WORK_DIR}: {free/1e9:.0f} GB')
assert free > total * 1.05, f'not enough disk: need ~{total*1.05/1e9:.0f} GB, have {free/1e9:.0f} GB'
assert any(n.upper().startswith('LICENSE') for n, _ in files), 'no LICENSE file in the source repo: check its license terms before copying'
'''),
code('''
# 1) download (resumable)
t0 = time.time()
local = snapshot_download(SRC, local_dir=WORK_DIR, token=HF_TOKEN, max_workers=8)
print(f'downloaded in {(time.time()-t0)/60:.0f} min to', local)
# verify every file arrived at the right size
bad = [(n, sz, os.path.getsize(f'{WORK_DIR}/{n}')) for n, sz in files if sz and (not os.path.exists(f'{WORK_DIR}/{n}') or os.path.getsize(f'{WORK_DIR}/{n}') != sz)]
assert not bad, f'size mismatch / missing: {bad[:5]}'
print('all', len(files), 'files present with the expected sizes')
'''),
code('''
# 2) add a notice to the README (inside the YAML front matter if there is one); weights, config and LICENSE are left untouched
notice = (f"> **Mirror notice.** This repository is an unmodified copy of [{SRC}](https://huggingface.co/{SRC}) "
          f"made by VishwamAI for research use. All credit to DeepSeek. The original license (see `LICENSE`) applies to every file here.\\n\\n")
rp = f'{WORK_DIR}/README.md'
orig = open(rp, encoding='utf-8').read() if os.path.exists(rp) else ''
if orig.startswith('---'):
    end = orig.find('\\n---', 3); end = orig.find('\\n', end + 1) + 1 if end != -1 else 0
    new = orig[:end] + '\\n' + notice + orig[end:]
else:
    new = notice + orig
if 'Mirror notice' not in orig: open(rp, 'w', encoding='utf-8').write(new)
print(open(rp, encoding='utf-8').read()[:700])
'''),
code('''
# 3) upload (resumable; run this cell again if it stops)
api.create_repo(DST, private=PRIVATE, exist_ok=True)
api.upload_large_folder(repo_id=DST, folder_path=WORK_DIR, repo_type='model')
print('done: https://huggingface.co/' + DST, '(private)' if PRIVATE else '(public)')
'''),
md('''## After copying
- This is a copy, not a new model. Call it a mirror/derivative of DeepSeek, keep the LICENSE and the notice.
- To make it *VishwamAI's own*, post-train it (needs rented multi-GPU hardware) and publish the result with a card that says "derived from DeepSeek-V4.1-Flash (MIT)" plus your changes and measured results.
- Check the destination account's storage quota before uploading hundreds of GB.'''),
]
path = f'{HERE}/vishwamai_mirror_deepseek.ipynb'
json.dump(dict(cells=cells, metadata=dict(kernelspec=dict(name='python3', display_name='Python 3')), nbformat=4, nbformat_minor=5), open(path, 'w'), indent=1)
print('wrote', path)
