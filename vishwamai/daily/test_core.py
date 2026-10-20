import sys, os, tempfile, numpy as np, jax, jax.numpy as jnp
sys.path.insert(0, '/home/user/daily_routine/vishwamai/daily')
import vm_core as C
cfg, cfg_ext = C.make_cfgs('nano', 512, 64, 128, jnp.float32)
p = C.init_params(cfg)
print('params', C.count_params(p, cfg))
print([C.plan_for_day(d)[:3] for d in (1,7,8)])
d = tempfile.mkdtemp(); rng = np.random.default_rng(0)
for n in ['en_edu','math','subj_math','code','hi_web']:
    for sp, k in (('train', 50000), ('val', 5000)):
        rng.integers(4, 512, k).astype(np.uint16).tofile(f'{d}/{n}.{sp}.bin')
    open(f'{d}/{n}.done','w').close()
data = C.Shards(d)
w = C.day_mixture(1, data.names())
print('mix', w)
work = tempfile.mkdtemp(); os.makedirs(work+'/ckpt', exist_ok=True)
kw = dict(plan_total_tokens=200000, seq_len=64, per_device_tokens=512, global_tokens_per_step=512, lr=1e-3, warmup_steps=2,
          min_lr_frac=0.1, wd=0.1, z_loss=1e-4, mtp_w=0.3, seed=0, ckpt_every_min=0.05, log_every=5)
p1, s1 = C.train_session(cfg, p, data, w, work, 0.15, day=1, log=print, **kw); print('s1', s1)
p2, s2 = C.train_session(cfg, p, data, w, work, 0.15, day=2, log=print, **kw); print('s2', s2)
out = work+'/hf'; os.makedirs(out)
C.export_hf(p2, cfg, out, None)
p3 = C.import_hf(C.init_params(cfg, seed=5), cfg, out+'/model.safetensors')
f = C.make_fwd(C.eval_cfg(cfg)); x = jnp.arange(4,36)[None]
print('roundtrip maxdiff', float(jnp.abs(f(p2,x)-f(p3,x)).max()))
