"""Sequence-level distillation data generator for VishwamAI (local weights, no API).

Loads an open-weight teacher from safetensors with transformers and writes JSONL
ready to merge into the Stage-3 SFT data of vishwamai_pretrain.ipynb.

Teachers (override the repo with --model):
    deepseek  deepseek-ai/DeepSeek-R1-Distill-Qwen-7B   (the full 671B R1 does not fit one GPU)
    gptoss    openai/gpt-oss-20b                        (Apache 2.0, needs a recent transformers)
    gemma     google/gemma-2-9b-it                      (gated: accept the licence, set HF_TOKEN)

Usage:
    python distill_generate.py --teacher deepseek --prompts prompts.jsonl \
        --out out_deepseek.jsonl --limit 20000 --batch 16 [--4bit]

prompts.jsonl: one object per line: {"prompt": str, "lang": "en|hi|te",
"answer": optional verifiable final answer}.

Output line: {"system", "lang", "prompt", "think", "answer", "verified", "teacher"}
(verified = matched a known ground truth; unverified numeric answers go through vote_filter.py)
mapping onto the notebook's chat format
    <|user|>..<|end|><|assistant|><|think|>{think}<|/think|>{answer}<|end|>
Check each teacher's licence before releasing a model trained on its output.
"""
import argparse, json, re

import torch
from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig

TEACHERS = {
    'deepseek': 'deepseek-ai/DeepSeek-R1-Distill-Qwen-7B',
    'gptoss':   'openai/gpt-oss-20b',
    'gemma':    'google/gemma-2-9b-it',
}
SYSTEM = {
    'en': 'You are VishwamAI, a calm, witty and emotionally aware assistant. '
          'Reason briefly step by step, then give the final answer.',
    'hi': 'आप विश्वमAI हैं, एक शांत और संवेदनशील सहायक। पहले संक्षेप में चरण-दर-चरण सोचें, फिर उत्तर दें।',
    'te': 'మీరు విశ్వమAI, ప్రశాంతమైన సహాయకుడు. ముందు క్లుప్తంగా ఆలోచించి, తర్వాత సమాధానం ఇవ్వండి.',
}


def final_number(s):
    m = re.findall(r'-?\d[\d,]*\.?\d*', s or '')
    return m[-1].replace(',', '').rstrip('.') if m else None


def split_reasoning(teacher, raw):
    """raw is decoded with special tokens kept; returns (think, answer)."""
    if teacher == 'deepseek':                       # R1-distill: <think>...</think>answer
        raw = re.sub(r'<｜[^>]*｜>', '', raw)
        if '</think>' in raw:
            think, ans = raw.split('</think>', 1)
            return think.replace('<think>', '').strip(), ans.strip()
        return '', raw.strip()
    if teacher == 'gptoss':                         # harmony: analysis channel, then final
        m = re.search(r'<\|channel\|>analysis<\|message\|>(.*?)<\|end\|>', raw, re.S)
        f = re.search(r'<\|channel\|>final<\|message\|>(.*?)(?:<\|return\|>|<\|end\|>|$)', raw, re.S)
        return (m.group(1).strip() if m else ''), (f.group(1).strip() if f else '')
    raw = re.sub(r'<[^>]*>', '', raw)               # gemma: no native reasoning trace
    parts = re.split(r'(?i)\bfinal answer\s*:', raw, maxsplit=1)
    return (parts[0].strip(), parts[1].strip()) if len(parts) == 2 else ('', raw.strip())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--teacher', choices=TEACHERS, required=True)
    ap.add_argument('--model', help='override the Hugging Face repo or a local path')
    ap.add_argument('--prompts', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--limit', type=int, default=1000)
    ap.add_argument('--batch', type=int, default=8)
    ap.add_argument('--max-new', type=int, default=1024)
    ap.add_argument('--4bit', dest='four_bit', action='store_true', help='bitsandbytes 4-bit (fits a T4)')
    a = ap.parse_args()

    name = a.model or TEACHERS[a.teacher]
    tok = AutoTokenizer.from_pretrained(name)
    tok.padding_side = 'left'
    if tok.pad_token is None:
        tok.pad_token = tok.eos_token
    kw = dict(device_map='auto', torch_dtype=torch.bfloat16 if torch.cuda.is_bf16_supported() else torch.float16)
    if a.four_bit:
        kw['quantization_config'] = BitsAndBytesConfig(load_in_4bit=True, bnb_4bit_compute_dtype=torch.float16)
    model = AutoModelForCausalLM.from_pretrained(name, **kw).eval()

    exs = [json.loads(l) for l in open(a.prompts, encoding='utf-8')][:a.limit]
    kept = dropped = 0
    with open(a.out, 'a', encoding='utf-8') as f:
        for i in range(0, len(exs), a.batch):
            chunk = exs[i:i + a.batch]
            texts = []
            for ex in chunk:
                msgs = [{'role': 'user', 'content': SYSTEM.get(ex.get('lang', 'en'), SYSTEM['en'])
                         + '\n\n' + ex['prompt']}]    # system folded into user: Gemma has no system role
                texts.append(tok.apply_chat_template(msgs, tokenize=False, add_generation_prompt=True))
            enc = tok(texts, return_tensors='pt', padding=True, add_special_tokens=False).to(model.device)
            with torch.no_grad():
                out = model.generate(**enc, max_new_tokens=a.max_new, do_sample=True,
                                     temperature=0.6, top_p=0.95)
            for ex, ids in zip(chunk, out[:, enc['input_ids'].shape[1]:]):
                think, answer = split_reasoning(a.teacher, tok.decode(ids, skip_special_tokens=False))
                for s in (tok.eos_token, tok.pad_token):
                    answer = answer.replace(s or '', '').strip()
                if not answer:
                    dropped += 1; continue
                # rejection sampling: keep only answers matching a known ground truth
                if ex.get('answer') is not None and final_number(answer) != str(ex['answer']):
                    dropped += 1; continue
                lang = ex.get('lang', 'en')
                f.write(json.dumps(dict(system=SYSTEM.get(lang, SYSTEM['en']), lang=lang,
                                        prompt=ex['prompt'], think=think, answer=answer,
                                        verified=ex.get('answer') is not None,
                                        teacher=a.teacher), ensure_ascii=False) + '\n')
                kept += 1
            f.flush()
            print(f'{i + len(chunk)}/{len(exs)} kept {kept} dropped {dropped}', flush=True)


if __name__ == '__main__':
    main()
