"""Sequence-level distillation data generator for VishwamAI.

Queries one or more OpenAI-compatible teachers (DeepSeek, gpt-oss, or Gemma
served via vLLM/Ollama) and writes JSONL ready to merge into the Stage-3 SFT
data of vishwamai_pretrain.ipynb.

Keys come from environment variables (use Colab/Kaggle secrets), never code:
    DEEPSEEK_API_KEY, GPTOSS_API_KEY, GEMMA_API_KEY (any value for local servers)

Usage:
    python distill_generate.py --teacher deepseek --prompts prompts.jsonl \
        --out out_deepseek.jsonl --limit 20000

prompts.jsonl: one object per line: {"prompt": str, "lang": "en|hi|te",
"answer": optional verifiable final answer}.

Output line: {"system", "lang", "prompt", "think", "answer", "teacher"}
mapping directly onto the notebook's chat format
    <|user|>..<|end|><|assistant|><|think|>{think}<|/think|>{answer}<|end|>
Check each teacher's current terms before releasing a model trained on its output.
"""
import argparse, json, os, re, sys, time
from concurrent.futures import ThreadPoolExecutor

from openai import OpenAI

TEACHERS = {
    'deepseek': dict(base_url='https://api.deepseek.com', key='DEEPSEEK_API_KEY',
                     model='deepseek-reasoner'),
    # open-weight OpenAI models (Apache 2.0), served locally e.g. `vllm serve openai/gpt-oss-20b`
    'gptoss':   dict(base_url=os.environ.get('GPTOSS_BASE_URL', 'http://localhost:8000/v1'),
                     key='GPTOSS_API_KEY', model=os.environ.get('GPTOSS_MODEL', 'openai/gpt-oss-20b')),
    'gemma':    dict(base_url=os.environ.get('GEMMA_BASE_URL', 'http://localhost:8000/v1'),
                     key='GEMMA_API_KEY', model=os.environ.get('GEMMA_MODEL', 'google/gemma-2-9b-it')),
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


def ask(client, cfg, ex, retries=4):
    system = SYSTEM.get(ex.get('lang', 'en'), SYSTEM['en'])
    for i in range(retries):
        try:
            r = client.chat.completions.create(
                model=cfg['model'], temperature=0.7, max_tokens=1024,
                messages=[{'role': 'system', 'content': system},
                          {'role': 'user', 'content': ex['prompt']}])
            msg = r.choices[0].message
            think = (getattr(msg, 'reasoning_content', None)      # DeepSeek R1 trace
                     or getattr(msg, 'reasoning', None) or '')  # gpt-oss via vLLM
            text = msg.content or ''
            if not think:                       # non-reasoning teachers: split on a marker
                parts = re.split(r'(?i)\bfinal answer\s*:', text, maxsplit=1)
                think, text = (parts[0].strip(), parts[1].strip()) if len(parts) == 2 else ('', text)
            return think.strip(), text.strip()
        except Exception as e:                  # rate limit / transient
            time.sleep(2 ** (i + 1))
            err = e
    print('fail:', err, file=sys.stderr)
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--teacher', choices=TEACHERS, required=True)
    ap.add_argument('--prompts', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--limit', type=int, default=1000)
    ap.add_argument('--workers', type=int, default=8)
    a = ap.parse_args()
    cfg = TEACHERS[a.teacher]
    client = OpenAI(base_url=cfg['base_url'], api_key=os.environ[cfg['key']])

    exs = [json.loads(l) for l in open(a.prompts, encoding='utf-8')][:a.limit]
    kept = dropped = 0
    with ThreadPoolExecutor(a.workers) as pool, open(a.out, 'a', encoding='utf-8') as f:
        for ex, res in zip(exs, pool.map(lambda e: ask(client, cfg, e), exs)):
            if not res or not res[1]:
                dropped += 1; continue
            think, answer = res
            # rejection sampling: keep only answers matching a known ground truth
            if ex.get('answer') is not None and final_number(answer) != str(ex['answer']):
                dropped += 1; continue
            f.write(json.dumps(dict(system=SYSTEM.get(ex.get('lang', 'en'), SYSTEM['en']),
                                    lang=ex.get('lang', 'en'), prompt=ex['prompt'],
                                    think=think, answer=answer, teacher=a.teacher),
                               ensure_ascii=False) + '\n')
            kept += 1
    print(f'{a.teacher}: kept {kept}, dropped {dropped}')


if __name__ == '__main__':
    main()
