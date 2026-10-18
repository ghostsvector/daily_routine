"""Multi-teacher majority-vote filter for distilled answers.

Reads the out_*.jsonl files from distill_generate.py and writes one voted file.
  * verified rows (matched a known ground truth)      -> kept as is
  * unverified rows whose answer ends in '#### <num>' -> kept only if >= --min-agree
    different teachers gave the same final number, and that number strictly beats the rest
  * rows with no '####' answer (open-ended chat)      -> kept as is (nothing to vote on)
Each teacher gets one vote per prompt (its first response).

Usage:
    python vote_filter.py --inp 'DIR/out_*.jsonl' --out DIR/voted.jsonl [--min-agree 2] \
        [--prompts DIR/prompts.jsonl]     # optional: reports vote precision via 'gold_hidden'
"""
import argparse, collections, glob, json, re


def final_num(answer):
    m = re.findall(r'####\s*(-?[\d,]*\.?\d+)', answer or '')
    return m[-1].replace(',', '') if m else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--inp', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--min-agree', type=int, default=2)
    ap.add_argument('--prompts', help='prompts.jsonl; rows with gold_hidden are used only for reporting')
    a = ap.parse_args()

    rows = [json.loads(l) for p in sorted(glob.glob(a.inp)) for l in open(p, encoding='utf-8')]
    gold = {}
    if a.prompts:
        for l in open(a.prompts, encoding='utf-8'):
            r = json.loads(l)
            if 'gold_hidden' in r: gold[r['prompt']] = str(r['gold_hidden'])

    by_prompt = collections.defaultdict(list)
    for r in rows: by_prompt[r['prompt']].append(r)

    kept, st = [], collections.Counter()
    right = wrong = 0
    for prompt, rs in by_prompt.items():
        nums = [final_num(r['answer']) for r in rs]
        if all(r.get('verified') for r in rs) or all(n is None for n in nums):
            kept += rs; st['passthrough'] += len(rs); continue
        first = {}                                         # one vote per teacher
        for r, n in zip(rs, nums):
            if n is not None and r['teacher'] not in first: first[r['teacher']] = n
        ranked = collections.Counter(first.values()).most_common()
        if not ranked or ranked[0][1] < a.min_agree or (len(ranked) > 1 and ranked[0][1] == ranked[1][1]):
            st['no_majority'] += len(rs); continue
        win = ranked[0][0]
        for r, n in zip(rs, nums):
            if n == win: kept.append(r); st['voted_kept'] += 1
            else: st['voted_dropped'] += 1
        if prompt in gold:
            if win == gold[prompt]: right += 1
            else: wrong += 1

    with open(a.out, 'w', encoding='utf-8') as f:
        for r in kept: f.write(json.dumps(r, ensure_ascii=False) + '\n')
    print(dict(st), '| total kept', len(kept), 'of', len(rows))
    if right + wrong:
        print(f'majority answer correct on {right}/{right + wrong} prompts with a hidden gold ({right / (right + wrong):.1%})')


if __name__ == '__main__':
    main()
