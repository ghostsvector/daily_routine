"""vm_core.py - VishwamAI model, checkpoints, subject data mixing and a time-budgeted trainer (JAX / Flax / Optax).

The model is the same MoE decoder as in vishwamai_pretrain.ipynb (QK-norm, YaRN RoPE, multi-token prediction, tied
embeddings). Everything here is used by the daily notebooks; they embed this file with %%writefile.
"""
import os, math, time, glob, json, zlib, re
from dataclasses import dataclass, replace
from functools import partial
from typing import Any

import numpy as np
import jax, jax.numpy as jnp
import flax.linen as nn
import flax.serialization as fser
import optax
from jax.sharding import Mesh, NamedSharding, PartitionSpec as P

PAD, UNK, BOS, EOS = 0, 1, 2, 3

PRESETS = {
  'nano':   dict(d_model=128,  n_layers=4,  n_heads=4,  n_kv_heads=2, d_ff=256,  moe_ff=128,  n_experts=4,  top_k=2),
  'base':   dict(d_model=512,  n_layers=12, n_heads=8,  n_kv_heads=2, d_ff=1536, moe_ff=704,  n_experts=8,  top_k=2),
  'medium': dict(d_model=768,  n_layers=16, n_heads=12, n_kv_heads=4, d_ff=2048, moe_ff=1024, n_experts=16, top_k=2),
  'large':  dict(d_model=1024, n_layers=24, n_heads=16, n_kv_heads=4, d_ff=3072, moe_ff=1408, n_experts=32, top_k=4),
}


@dataclass(frozen=True)
class Cfg:
    vocab: int
    d_model: int
    n_layers: int
    n_heads: int
    n_kv_heads: int
    d_ff: int                 # dense MLP width (used by the MTP blocks)
    moe_ff: int               # per-expert width
    n_experts: int
    top_k: int
    max_len: int = 1024
    rope_theta: float = 500000.0
    rope_scale: float = 1.0   # YaRN factor (1 = off)
    rope_orig_len: int = 1024
    cap_factor: float = 1.25  # expert capacity (training); >= n_experts means "no token dropped"
    aux_coef: float = 0.01    # load-balance loss weight
    router_z: float = 1e-3
    mtp_depth: int = 2        # extra future-token heads (training only)
    dtype: Any = jnp.float32


def make_cfgs(preset, vocab, seq_len, ctx_len, dtype):
    cfg = Cfg(vocab=vocab, max_len=seq_len, rope_orig_len=seq_len, dtype=dtype, **PRESETS[preset])
    cfg_ext = replace(cfg, max_len=ctx_len, rope_scale=ctx_len / seq_len, rope_orig_len=seq_len)   # YaRN stage
    return cfg, cfg_ext

def eval_cfg(c): return replace(c, cap_factor=float(c.n_experts), mtp_depth=0)             # dropless, no MTP heads


# ----------------------------------------------------------------------------- model
class RMSNorm(nn.Module):
    @nn.compact
    def __call__(self, x):
        w = self.param('w', nn.initializers.ones, (x.shape[-1],), jnp.float32)
        x32 = x.astype(jnp.float32)
        y = x32 * jax.lax.rsqrt(jnp.mean(x32 * x32, -1, keepdims=True) + 1e-6)
        return (y * w).astype(x.dtype)

def rope_tables(T, hd, theta, scale=1.0, orig_len=1024):
    # Plain RoPE when scale == 1; YaRN (NTK-by-parts + attention temperature) when scale > 1.
    pos_freqs = theta ** (jnp.arange(0, hd, 2, dtype=jnp.float32) / hd)
    inv = 1.0 / pos_freqs
    mscale = 1.0
    if scale > 1.0:
        corr = lambda n_rot: hd * math.log(orig_len / (n_rot * 2 * math.pi)) / (2 * math.log(theta))
        low, high = max(math.floor(corr(32)), 0), min(math.ceil(corr(1)), hd - 1)
        if low == high: high = high + 0.001
        ramp = jnp.clip((jnp.arange(hd // 2, dtype=jnp.float32) - low) / (high - low), 0, 1)
        extrap = 1.0 - ramp
        inv = (1.0 / (scale * pos_freqs)) * (1 - extrap) + inv * extrap
        mscale = 0.1 * math.log(scale) + 1.0
    f = jnp.outer(jnp.arange(T, dtype=jnp.float32), inv)
    return jnp.cos(f) * mscale, jnp.sin(f) * mscale

def apply_rope(x, cos, sin):                      # x: [B,T,H,D]; half-split layout == HF rotate_half
    h = x.shape[-1] // 2
    x1, x2 = x[..., :h], x[..., h:]
    c, s = cos[None, :, None, :].astype(x.dtype), sin[None, :, None, :].astype(x.dtype)
    return jnp.concatenate([x1 * c - x2 * s, x1 * s + x2 * c], -1)

def dense(cfg, n, name, scale=1.0):
    return nn.Dense(n, use_bias=False, dtype=cfg.dtype, param_dtype=jnp.float32, name=name,
                    kernel_init=nn.initializers.normal(0.02 * scale))

class Attn(nn.Module):
    cfg: Cfg
    @nn.compact
    def __call__(self, x, cos, sin):
        c = self.cfg; hd = c.d_model // c.n_heads; B, T, _ = x.shape
        q = dense(c, c.n_heads * hd, 'q')(x).reshape(B, T, c.n_heads, hd)
        k = dense(c, c.n_kv_heads * hd, 'k')(x).reshape(B, T, c.n_kv_heads, hd)
        v = dense(c, c.n_kv_heads * hd, 'v')(x).reshape(B, T, c.n_kv_heads, hd)
        q, k = RMSNorm(name='q_norm')(q), RMSNorm(name='k_norm')(k)          # QK-norm (per head, before RoPE)
        q, k = apply_rope(q, cos, sin), apply_rope(k, cos, sin)
        r = c.n_heads // c.n_kv_heads
        k, v = jnp.repeat(k, r, axis=2), jnp.repeat(v, r, axis=2)
        o = jax.nn.dot_product_attention(q, k, v, is_causal=True)
        return dense(c, c.d_model, 'o', scale=1 / math.sqrt(2 * c.n_layers))(o.reshape(B, T, -1))

class MLP(nn.Module):                              # dense SwiGLU (used by the MTP blocks)
    cfg: Cfg
    @nn.compact
    def __call__(self, x):
        c = self.cfg
        h = nn.silu(dense(c, c.d_ff, 'gate')(x)) * dense(c, c.d_ff, 'up')(x)
        return dense(c, c.d_model, 'down', scale=1 / math.sqrt(2 * c.n_layers))(h)

class MoE(nn.Module):
    # Top-k routed SwiGLU experts. Routing is per sequence (vmap over batch) so it stays local to a device;
    # tokens are scattered into [E, capacity, d] buffers (no giant one-hot dispatch tensor).
    cfg: Cfg
    @nn.compact
    def __call__(self, x):                         # x: [B,T,d] -> (y, aux_loss)
        c = self.cfg; B, T, d = x.shape; E, K, dt = c.n_experts, c.top_k, c.dtype
        init = nn.initializers.normal(0.02)
        router = self.param('router', init, (d, E), jnp.float32)
        wg = self.param('wg', init, (E, d, c.moe_ff), jnp.float32)
        wu = self.param('wu', init, (E, d, c.moe_ff), jnp.float32)
        wd = self.param('wd', nn.initializers.normal(0.02 / math.sqrt(2 * c.n_layers)), (E, c.moe_ff, d), jnp.float32)
        C = min(T * K, int(math.ceil(c.cap_factor * T * K / E)))
        def one(xs):                               # xs: [T,d]
            logits = xs.astype(jnp.float32) @ router
            probs = jax.nn.softmax(logits, -1)
            topw, topi = jax.lax.top_k(probs, K)
            topw = topw / topw.sum(-1, keepdims=True)           # normalise top-k weights
            fe, fw, ft = topi.reshape(-1), topw.reshape(-1), jnp.repeat(jnp.arange(T), K)
            oh = jax.nn.one_hot(fe, E, dtype=jnp.int32)
            pos = jnp.take_along_axis(jnp.cumsum(oh, 0) - 1, fe[:, None], 1)[:, 0]   # slot inside the expert
            keep = pos < C
            slot = jnp.where(keep, fe * C + pos, E * C)
            tok = jnp.zeros(E * C + 1, jnp.int32).at[slot].set(ft)
            val = jnp.zeros(E * C + 1, jnp.float32).at[slot].set(1.0)
            xe = (xs[tok[:E * C]] * val[:E * C, None].astype(xs.dtype)).reshape(E, C, d)
            h = nn.silu(jnp.einsum('ecd,edf->ecf', xe, wg.astype(dt))) * jnp.einsum('ecd,edf->ecf', xe, wu.astype(dt))
            ye = jnp.einsum('ecf,efd->ecd', h, wd.astype(dt)).reshape(E * C, d)
            ya = jnp.where(keep[:, None], ye[jnp.minimum(slot, E * C - 1)], 0) * fw[:, None].astype(dt)
            f = oh.sum(0).astype(jnp.float32) / (T * K)                      # routed fraction (pre-drop)
            lb = E * jnp.sum(f * probs.mean(0))                              # Switch load-balance loss
            z = jnp.mean(jax.nn.logsumexp(logits, -1) ** 2)                  # router z-loss
            return ya.reshape(T, K, d).sum(1), lb, z
        y, lb, z = jax.vmap(one)(x)
        return y, c.aux_coef * lb.mean() + c.router_z * z.mean()

class Block(nn.Module):
    cfg: Cfg
    moe: bool = True
    @nn.compact
    def __call__(self, x, cos, sin):
        x = x + Attn(self.cfg, name='attn')(RMSNorm(name='n1')(x), cos, sin)
        h = RMSNorm(name='n2')(x)
        if self.moe:
            y, aux = MoE(self.cfg, name='moe')(h)
        else:
            y, aux = MLP(self.cfg, name='mlp')(h), jnp.zeros((), jnp.float32)
        return x + y, aux

class VishwamAI(nn.Module):
    cfg: Cfg
    @nn.compact
    def __call__(self, ids, train_mtp=False):      # -> (logits, [mtp_logits...], aux_loss)
        c = self.cfg; B, T = ids.shape
        emb = nn.Embed(c.vocab, c.d_model, dtype=c.dtype, param_dtype=jnp.float32,
                       embedding_init=nn.initializers.normal(0.02), name='embed')
        head = lambda h: h.astype(jnp.float32) @ emb.embedding.astype(jnp.float32).T      # tied output head
        x = emb(ids)
        cos, sin = rope_tables(T, c.d_model // c.n_heads, c.rope_theta, c.rope_scale, c.rope_orig_len)
        RBlock = nn.remat(Block)                   # activation checkpointing
        aux = jnp.zeros((), jnp.float32)
        for i in range(c.n_layers):
            x, a = RBlock(c, True, name=f'block_{i}')(x, cos, sin); aux = aux + a
        logits = head(RMSNorm(name='norm_f')(x))
        mtp, hp = [], x
        if train_mtp and c.mtp_depth > 0:          # multi-token prediction: head j predicts token t+j+1
            for j in range(1, c.mtp_depth + 1):
                e = jnp.concatenate([emb(ids)[:, j:], jnp.zeros((B, j, c.d_model), c.dtype)], 1)
                z = dense(c, c.d_model, f'mtp{j}_proj')(jnp.concatenate(
                    [RMSNorm(name=f'mtp{j}_nh')(hp), RMSNorm(name=f'mtp{j}_ne')(e)], -1))
                hp, _ = Block(c, False, name=f'mtp{j}_block')(z, cos, sin)
                mtp.append(head(RMSNorm(name=f'mtp{j}_nf')(hp)))
        return logits, mtp, aux

def count_params(params, c):
    flat = jax.tree_util.tree_flatten_with_path(params)[0]
    key = lambda path: '/'.join(str(getattr(k, 'key', k)) for k in path)
    tot = sum(v.size for _, v in flat)
    mtp = sum(v.size for p, v in flat if 'mtp' in key(p))
    exp = sum(v.size for p, v in flat if key(p).split('/')[-1] in ('wg', 'wu', 'wd'))
    total_inf = tot - mtp
    active = total_inf - exp * (1 - c.top_k / c.n_experts)
    return total_inf, active, mtp

def init_params(cfg, seed=0):
    return VishwamAI(cfg).init(jax.random.PRNGKey(seed), jnp.zeros((1, 16), jnp.int32), train_mtp=True)['params']


# ----------------------------------------------------------------------------- checkpoints
def save_tree(path, tree):
    tmp = path + '.tmp'; open(tmp, 'wb').write(fser.to_bytes(jax.device_get(tree))); os.replace(tmp, path)

def load_tree(path, like):
    return fser.from_bytes(jax.device_get(like), open(path, 'rb').read())


# ----------------------------------------------------------------------------- losses / eval helpers
def ce_terms(logits, y, m):
    m = m.astype(jnp.float32)
    logz = jax.nn.logsumexp(logits, -1)
    nll = logz - jnp.take_along_axis(logits, y[..., None], -1)[..., 0]
    n = jnp.maximum(m.sum(), 1.0)
    return (nll * m).sum() / n, ((logz ** 2) * m).sum() / n

def make_pretrain_loss(mdl, z_loss=1e-4, mtp_w=0.3):
    def loss_fn(p, batch):                                   # batch: [B, T+1]
        x, y = batch[:, :-1], batch[:, 1:]
        logits, mtp, aux = mdl.apply({'params': p}, x, train_mtp=True)
        main, z = ce_terms(logits, y, y != PAD)
        total = main + z_loss * z + aux
        mt = jnp.zeros(())
        for j, lg in enumerate(mtp, 1):                      # head j predicts token t+j+1
            yj = jnp.pad(batch[:, j + 1:], ((0, 0), (0, j)))
            l, _ = ce_terms(lg, yj, yj != PAD); mt = mt + l
        if mtp: total = total + mtp_w * mt / len(mtp)
        return total, (main, aux, mt)
    return loss_fn

def make_fwd(c):                                              # dropless inference forward -> logits
    m = VishwamAI(eval_cfg(c))
    return jax.jit(lambda p, x: m.apply({'params': p}, x)[0])

def make_eval_nll(c):
    m = VishwamAI(eval_cfg(c))
    @jax.jit
    def f(p, batch):
        logits, _, _ = m.apply({'params': p}, batch[:, :-1]); y = batch[:, 1:]
        return ce_terms(logits, y, y != PAD)[0]
    return f

def sample_text(fwd, params, prompt_ids, max_new=120, temperature=0.8, top_p=0.9, seed=0, buf_len=256):
    ids = list(prompt_ids); buf = np.zeros((1, buf_len), np.int32); buf[0, :len(ids)] = ids; n = len(ids)
    r = np.random.default_rng(seed)
    for _ in range(min(max_new, buf_len - n)):
        lg = np.asarray(fwd(params, jnp.asarray(buf))[0, n - 1], dtype=np.float64) / max(temperature, 1e-4)
        pr = np.exp(lg - lg.max()); pr /= pr.sum()
        o = np.argsort(-pr); cs = np.cumsum(pr[o]); keep = o[:max(1, int((cs < top_p).sum()) + 1)]
        nxt = int(r.choice(keep, p=pr[keep] / pr[keep].sum()))
        if nxt == EOS: break
        buf[0, n] = nxt; n += 1
    return buf[0, len(prompt_ids):n].tolist()


# ----------------------------------------------------------------------------- subject data
SUBJECTS = {            # subject -> shard names (uint16 token files named {shard}.train.bin / .val.bin / .done in the data folder)
    'english':      ['en_edu', 'en_wiki'],
    'math':         ['math', 'subj_math'],
    'physics_chem': ['subj_physics_chem'],
    'biology_health': ['subj_biology_health'],
    'cs_code':      ['code', 'swe'],
    'reasoning':    ['subj_reasoning'],
    'history_geo':  ['subj_history_geo'],
    'econ_law':     ['subj_econ_law'],
    'philosophy_lit': ['subj_philosophy_lit'],
    'everyday':     ['subj_everyday'],
    'hindi':        ['hi_web', 'hi_wiki'],
    'telugu':       ['te_web', 'te_wiki'],
}
GENERAL = ['en_edu', 'en_cosmo', 'en_wiki']          # always mixed in, so the model keeps its broad base

DAY_PLAN = {            # day within a 7-day cycle -> the two focus subjects (day 7 = review: light mixed training + evaluation)
    1: ['english', 'math'],
    2: ['physics_chem', 'biology_health'],
    3: ['cs_code', 'reasoning'],
    4: ['history_geo', 'econ_law'],
    5: ['philosophy_lit', 'everyday'],
    6: ['hindi', 'telugu'],
    7: [],
}

def plan_for_day(day):
    """day 1,2,3... -> (cycle_no, day_in_cycle, focus subjects, replay subjects)"""
    cycle, d = (day - 1) // 7, (day - 1) % 7 + 1
    focus = DAY_PLAN[d]
    if cycle == 0:
        seen = [s for k in range(1, d) for s in DAY_PLAN[k]]
    else:
        seen = list(SUBJECTS)
    replay = [s for s in seen if s not in focus]
    if not focus: focus, replay = list(SUBJECTS), []          # review day: everything equally
    return cycle, d, focus, replay

def day_mixture(day, avail, w_focus=0.5, w_replay=0.3, w_general=0.2):
    """-> {shard_name: weight} for the day. Subjects whose shards are missing are skipped with their weight redistributed."""
    cycle, d, focus, replay = plan_for_day(day)
    have = lambda subj: [s for s in SUBJECTS[subj] if s in avail]
    focus = [s for s in focus if have(s)]; replay = [s for s in replay if have(s)]
    general = [s for s in GENERAL if s in avail]
    if not replay: w_focus, w_replay = w_focus + w_replay, 0.0
    if not general: w_focus, w_general = w_focus + w_general, 0.0
    if not focus and not replay and not general: raise RuntimeError('no data shards available for this day')
    if not focus: w_replay, w_focus = w_replay + w_focus, 0.0
    w = {}
    def add(group_subjects, weight):
        for s in group_subjects:
            shards = have(s)
            for sh in shards: w[sh] = w.get(sh, 0.0) + weight / len(group_subjects) / len(shards)
    add(focus, w_focus); add(replay, w_replay)
    for sh in general: w[sh] = w.get(sh, 0.0) + w_general / len(general)
    tot = sum(w.values()); return {k: v / tot for k, v in w.items()}

class Shards:
    """memory-mapped uint16 token shards in one folder"""
    def __init__(self, data_dir):
        self.s = {}
        for p in sorted(glob.glob(os.path.join(data_dir, '*.done'))):
            name = os.path.basename(p)[:-5]
            tr, va = os.path.join(data_dir, f'{name}.train.bin'), os.path.join(data_dir, f'{name}.val.bin')
            if os.path.exists(tr) and os.path.getsize(tr) >= 4 and os.path.exists(va) and os.path.getsize(va) >= 4:
                self.s[name] = dict(train=np.memmap(tr, dtype=np.uint16, mode='r'), val=np.memmap(va, dtype=np.uint16, mode='r'))
    def names(self): return list(self.s)
    def sizes(self): return {n: len(v['train']) for n, v in self.s.items()}
    def sample(self, rng, n_seq, seq_len, weights, split='train'):
        names = [n for n in weights if n in self.s and len(self.s[n][split]) > seq_len + 2]
        if not names: raise RuntimeError('no shard is large enough for this sequence length')
        p = np.array([weights[n] for n in names], dtype=np.float64); p /= p.sum()
        out = np.empty((n_seq, seq_len + 1), dtype=np.int32)
        for i, k in enumerate(rng.choice(len(names), size=n_seq, p=p)):
            arr = self.s[names[k]][split]
            s = int(rng.integers(0, len(arr) - seq_len - 1))
            out[i] = arr[s:s + seq_len + 1]
        return out


# ----------------------------------------------------------------------------- time-budgeted training session
def train_session(cfg, params0, data, weights, work, minutes, *, plan_total_tokens, seq_len, per_device_tokens, global_tokens_per_step,
                  lr, warmup_steps=200, min_lr_frac=0.1, wd=0.1, z_loss=1e-4, mtp_w=0.3, seed=0, ckpt_every_min=15,
                  log_every=20, ckpt_name='daily_latest.msgpack', day=None, log=print):
    """Resume (or start) training and run for `minutes` of wall-clock time, then save and return a stats dict.
    The learning-rate schedule spans `plan_total_tokens` over ALL sessions, so day 2 continues where day 1 stopped."""
    devices = jax.devices(); nd = len(devices)
    mesh = Mesh(np.array(devices), ('data',))
    REPL, ACC_ROW = NamedSharding(mesh, P()), NamedSharding(mesh, P(None, 'data'))
    mg = nd * max(1, per_device_tokens // seq_len)                      # sequences per micro-step (global)
    accum = max(1, global_tokens_per_step // (mg * seq_len)); tok_step = accum * mg * seq_len
    plan_steps = max(10, int(plan_total_tokens // tok_step))
    sched = optax.warmup_cosine_decay_schedule(0.0, lr, min(warmup_steps, max(1, plan_steps // 10)), plan_steps, lr * min_lr_frac)
    tx = optax.chain(optax.clip_by_global_norm(1.0),
                     optax.adamw(sched, b1=0.9, b2=0.95, eps=1e-8, weight_decay=wd,
                                 mask=lambda p: jax.tree.map(lambda x: x.ndim >= 2, p)))
    loss_fn = make_pretrain_loss(VishwamAI(cfg), z_loss, mtp_w)

    @partial(jax.jit, donate_argnums=(0, 1))
    def step_fn(p, o, batch):                                            # batch: [accum, B, T+1]
        def micro(carry, mb):
            g_acc, m_acc = carry
            (_, (main, aux, mt)), g = jax.value_and_grad(loss_fn, has_aux=True)(p, mb)
            return (jax.tree.map(jnp.add, g_acc, g), m_acc + jnp.stack([main, aux, mt])), None
        (g, m), _ = jax.lax.scan(micro, (jax.tree.map(jnp.zeros_like, p), jnp.zeros(3)), batch)
        g = jax.tree.map(lambda x: x / batch.shape[0], g)
        upd, o = tx.update(g, o, p)
        return optax.apply_updates(p, upd), o, m / batch.shape[0], optax.global_norm(g)

    params = jax.device_put(jax.tree.map(lambda x: np.array(x), params0), REPL); opt = jax.device_put(tx.init(params), REPL)
    step0, tokens0 = 0, 0
    ck = os.path.join(work, 'ckpt', ckpt_name); os.makedirs(os.path.dirname(ck), exist_ok=True)
    src = next((p for p in (ck, ck + '.prev') if os.path.exists(p)), None)
    if src:
        st = load_tree(src, {'params': params, 'opt': opt, 'step': 0, 'tokens': 0})
        params, opt = jax.device_put(st['params'], REPL), jax.device_put(st['opt'], REPL)
        step0, tokens0 = int(st['step']), int(st['tokens'])
        log(f'resumed from {os.path.basename(src)}: step {step0}, {tokens0 / 1e6:.1f}M tokens seen so far')
    else:
        log('no training checkpoint found: starting from the given weights with a fresh optimiser')

    def save(step, tokens):
        if os.path.exists(ck): os.replace(ck, ck + '.prev')              # keep one older copy in case a save is interrupted
        save_tree(ck, {'params': params, 'opt': opt, 'step': step, 'tokens': tokens})

    def get_batch(step):
        r = np.random.default_rng(seed * 1_000_003 + step)               # deterministic per global step
        b = data.sample(r, accum * mg, seq_len, weights).reshape(accum, mg, seq_len + 1)
        return jax.device_put(b, ACC_ROW)

    log(f'{nd} device(s) | seq {seq_len} | {tok_step / 1e3:.0f}k tokens/step | plan {plan_steps} steps ({plan_total_tokens / 1e9:.2f}B tokens) | '
        f'session budget {minutes:.0f} min | data mix: ' + ', '.join(f'{k} {v:.0%}' for k, v in sorted(weights.items(), key=lambda kv: -kv[1])))
    t0 = time.time(); last_ckpt = t0; step = step0; sess_tokens = 0; nll_hist = []; last_main = float('nan')
    try:
        while time.time() - t0 < minutes * 60 and step < plan_steps:
            params, opt, m, gn = step_fn(params, opt, get_batch(step)); step += 1; sess_tokens += tok_step
            if step == step0 + 1 or step % log_every == 0:
                main, aux, mt = [float(v) for v in m]; last_main = main; nll_hist.append(main)
                if not math.isfinite(main): raise RuntimeError('loss diverged - lower the learning rate and resume from the previous checkpoint')
                tps = sess_tokens / (time.time() - t0)
                log(f'step {step} nll {main:.3f} ppl {math.exp(main):.1f} aux {aux:.4f} gnorm {float(gn):.2f} {tps / 1e3:.1f}k tok/s | '
                    f'{(time.time() - t0) / 60:.0f}/{minutes:.0f} min | {(tokens0 + sess_tokens) / 1e6:.1f}M tokens total')
            if time.time() - last_ckpt > ckpt_every_min * 60:
                save(step, tokens0 + sess_tokens); last_ckpt = time.time(); log('  checkpoint saved')
    except KeyboardInterrupt:
        log('interrupted: saving a checkpoint before stopping'); save(step, tokens0 + sess_tokens); raise
    save(step, tokens0 + sess_tokens)
    stats = dict(day=day, steps=step - step0, step_end=step, tokens_session=sess_tokens, tokens_total=tokens0 + sess_tokens,
                 minutes=round((time.time() - t0) / 60, 1), nll_last=last_main, nll_mean=float(np.mean(nll_hist)) if nll_hist else None,
                 tok_per_s=round(sess_tokens / max(time.time() - t0, 1e-9)), mix=weights)
    log('session finished: ' + json.dumps({k: v for k, v in stats.items() if k != 'mix'}))
    return params, stats

def load_params_from_checkpoint(path, template):
    """accepts a plain params checkpoint ({..}) or a training checkpoint ({'params':..}); returns params"""
    raw = fser.msgpack_restore(open(path, 'rb').read())
    tree = raw['params'] if isinstance(raw, dict) and 'params' in raw and 'opt' in raw else raw
    return fser.from_state_dict(template, tree)

def subject_val_nll(params, cfg, data, shard_names, seq_len, n_batches=4, batch=8, seed=999):
    """held-out cross-entropy (nats/token) on each shard's validation split -> {shard: nll}; deterministic"""
    f = make_eval_nll(cfg); out = {}
    for n in shard_names:
        if n not in data.s or len(data.s[n]['val']) < seq_len + 3: continue
        r = np.random.default_rng(seed); tot = 0.0
        for _ in range(n_batches): tot += float(f(params, jnp.asarray(data.sample(r, batch, seq_len, {n: 1.0}, 'val'))))
        out[n] = tot / n_batches
    return out


# ----------------------------------------------------------------------------- Hugging Face export / import (Qwen3-MoE layout)
def export_hf(params, cfg, out_dir, sp_path, bos=BOS, eos=EOS, pad=PAD):
    from safetensors.numpy import save_file
    import shutil
    os.makedirs(out_dir, exist_ok=True)
    hp = jax.device_get(params); f32 = lambda a: np.asarray(a, dtype=np.float32)
    T_ = {'model.embed_tokens.weight': f32(hp['embed']['embedding']), 'model.norm.weight': f32(hp['norm_f']['w'])}
    for i in range(cfg.n_layers):
        b, pre = hp[f'block_{i}'], f'model.layers.{i}.'
        for a, n in (('q', 'q_proj'), ('k', 'k_proj'), ('v', 'v_proj'), ('o', 'o_proj')):
            T_[pre + f'self_attn.{n}.weight'] = f32(b['attn'][a]['kernel']).T.copy()          # flax [in,out] -> torch [out,in]
        T_[pre + 'self_attn.q_norm.weight'] = f32(b['attn']['q_norm']['w'])
        T_[pre + 'self_attn.k_norm.weight'] = f32(b['attn']['k_norm']['w'])
        T_[pre + 'input_layernorm.weight'] = f32(b['n1']['w'])
        T_[pre + 'post_attention_layernorm.weight'] = f32(b['n2']['w'])
        T_[pre + 'mlp.gate.weight'] = f32(b['moe']['router']).T.copy()                         # router [d,E] -> [E,d]
        for e in range(cfg.n_experts):
            T_[pre + f'mlp.experts.{e}.gate_proj.weight'] = f32(b['moe']['wg'][e]).T.copy()
            T_[pre + f'mlp.experts.{e}.up_proj.weight'] = f32(b['moe']['wu'][e]).T.copy()
            T_[pre + f'mlp.experts.{e}.down_proj.weight'] = f32(b['moe']['wd'][e]).T.copy()
    save_file(T_, os.path.join(out_dir, 'model.safetensors'), metadata={'format': 'pt'})
    hf_cfg = {
      "architectures": ["Qwen3MoeForCausalLM"], "model_type": "qwen3_moe", "vocab_size": cfg.vocab,
      "hidden_size": cfg.d_model, "intermediate_size": cfg.d_ff, "moe_intermediate_size": cfg.moe_ff,
      "num_hidden_layers": cfg.n_layers, "num_attention_heads": cfg.n_heads, "num_key_value_heads": cfg.n_kv_heads,
      "head_dim": cfg.d_model // cfg.n_heads, "num_experts": cfg.n_experts, "num_experts_per_tok": cfg.top_k,
      "norm_topk_prob": True, "decoder_sparse_step": 1, "mlp_only_layers": [], "router_aux_loss_coef": cfg.aux_coef,
      "max_position_embeddings": cfg.max_len, "rms_norm_eps": 1e-6, "rope_theta": cfg.rope_theta,
      "tie_word_embeddings": True, "hidden_act": "silu", "attention_bias": False, "use_sliding_window": False,
      "torch_dtype": "float32", "bos_token_id": bos, "eos_token_id": eos, "pad_token_id": pad}
    if cfg.rope_scale > 1:
        hf_cfg["rope_scaling"] = {"rope_type": "yarn", "factor": cfg.rope_scale, "original_max_position_embeddings": cfg.rope_orig_len}
    json.dump(hf_cfg, open(os.path.join(out_dir, 'config.json'), 'w'), indent=2)
    if sp_path and os.path.exists(sp_path): shutil.copy(sp_path, os.path.join(out_dir, 'tokenizer.model'))
    json.dump({"tokenizer_class": "LlamaTokenizer", "legacy": False, "model_max_length": cfg.max_len,
               "bos_token": "<s>", "eos_token": "</s>", "unk_token": "<unk>", "pad_token": "<pad>"},
              open(os.path.join(out_dir, 'tokenizer_config.json'), 'w'))
    return T_

def import_hf(template, cfg, safetensors_path):
    """inverse of export_hf: fills `template` (a params tree from init_params) from a model.safetensors file.
    The training-only MTP heads are not in the file and keep the template's values."""
    from safetensors.numpy import load_file
    W = load_file(safetensors_path); used = set()
    tree = jax.tree.map(np.asarray, jax.device_get(template))
    tree = fser.to_state_dict(tree)
    def put(path, name, arr, transpose=False):
        used.add(name); arr = np.asarray(W[name] if arr is None else arr, dtype=np.float32); arr = arr.T if transpose else arr
        d = tree
        for k in path[:-1]: d = d[k]
        assert d[path[-1]].shape == arr.shape, f'{name}: {arr.shape} vs {d[path[-1]].shape}'
        d[path[-1]] = arr
    put(('embed', 'embedding'), 'model.embed_tokens.weight', None); put(('norm_f', 'w'), 'model.norm.weight', None)
    for i in range(cfg.n_layers):
        pre, b = f'model.layers.{i}.', f'block_{i}'
        for a, n in (('q', 'q_proj'), ('k', 'k_proj'), ('v', 'v_proj'), ('o', 'o_proj')):
            put((b, 'attn', a, 'kernel'), pre + f'self_attn.{n}.weight', None, transpose=True)
        put((b, 'attn', 'q_norm', 'w'), pre + 'self_attn.q_norm.weight', None); put((b, 'attn', 'k_norm', 'w'), pre + 'self_attn.k_norm.weight', None)
        put((b, 'n1', 'w'), pre + 'input_layernorm.weight', None); put((b, 'n2', 'w'), pre + 'post_attention_layernorm.weight', None)
        put((b, 'moe', 'router'), pre + 'mlp.gate.weight', None, transpose=True)
        for key, n in (('wg', 'gate_proj'), ('wu', 'up_proj'), ('wd', 'down_proj')):
            names = [pre + f'mlp.experts.{e}.{n}.weight' for e in range(cfg.n_experts)]; used.update(names)
            put((b, 'moe', key), names[0], np.stack([W[x].T for x in names]))
    assert used == set(W), f'unmapped tensors: {sorted(set(W) - used)[:5]}'
    return fser.from_state_dict(template, tree)
