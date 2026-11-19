#!/usr/bin/env python3
"""v0.20: процедурные звуки Сна (собственная генерация, CC0). Запуск: python3 tools/gen_dream_sfx.py
Пишет assets/audio/sfx_*.wav и dream_tone_*.wav (22050 Гц, моно, 16 бит). Детерминированно (seed 20)."""
import numpy as np, wave, os
SR = 22050
rng = np.random.default_rng(20)
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")

def t(d): return np.arange(int(SR * d)) / SR
def env(n, a=0.01, r=None, d=None):
    e = np.ones(n); na = max(1, int(a * SR)); e[:na] = np.linspace(0, 1, na)
    if r is not None: e *= np.exp(-np.arange(n) / (r * SR))
    if d is not None:
        nd = max(1, int(d * SR)); e[-nd:] *= np.linspace(1, 0, nd)
    return e
def bell(f, d, r=0.35, parts=((1, 1), (2.76, .4), (5.4, .18))):
    x = t(d); s = sum(g * np.sin(2 * np.pi * f * m * x) * np.exp(-x * m / r) for m, g in parts)
    return s * env(len(x), 0.004)
def noise(d): return rng.standard_normal(int(SR * d))
def lp(x, k):
    y = np.zeros_like(x); a = 0.0
    for i, v in enumerate(x): a += k * (v - a); y[i] = a
    return y
def mix(*parts):
    n = max(len(p[1]) + int(p[0] * SR) for p in parts); y = np.zeros(n)
    for off, p in parts: o = int(off * SR); y[o:o + len(p)] += p
    return y
def save(name, y, peak=0.8):
    y = y / (np.max(np.abs(y)) + 1e-9) * peak
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((y * 32767).astype("<i2").tobytes())

# короткие эффекты
x = t(0.5); save("sfx_dream_fill", lp(noise(0.5), 0.08) * np.sin(np.pi * x / 0.5) ** 2 + 0.3 * bell(660, 0.5, 0.25))
save("sfx_dream_materialize", mix(*[(i * 0.11, bell(f, 1.1, 0.45)) for i, f in enumerate([523.25, 659.25, 783.99, 1046.5])],
     (0.0, 0.25 * lp(noise(1.3), 0.05) * np.linspace(0, 1, int(SR * 1.3)) ** 2 * env(int(SR * 1.3), d=0.3))))
save("sfx_dream_imprint", mix((0, bell(880, 1.0, 0.5)), (0.12, 0.6 * bell(1318.5, 0.9, 0.4))))
cr = np.zeros(int(SR * 0.5))
for k in rng.integers(0, len(cr) - 200, 26): cr[k:k + 120] += rng.standard_normal(120) * np.exp(-np.arange(120) / 25)
x = t(0.5); save("sfx_dream_crack", cr + 0.8 * np.sin(2 * np.pi * 55 * x) * np.exp(-x / 0.08))
x = t(1.4); saw = 2 * ((70 * x) % 1) - 1
save("sfx_dream_nightmare", lp(saw * (0.6 + 0.4 * np.sin(2 * np.pi * 6 * x)) + 0.5 * lp(noise(1.4), 0.03), 0.12) * env(len(x), 0.15, d=0.5))
x = t(1.5); f = 220 * 2 ** (x / 1.5)
save("sfx_dream_enter", (np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.5 * np.sin(2 * np.pi * np.cumsum(f * 1.5) / SR)) * np.sin(np.pi * x / 1.5) ** 2, 0.55)
x = t(0.6); save("sfx_dream_anchor", 0.8 * np.sin(2 * np.pi * 110 * x) * np.exp(-x / 0.06) + bell(392, 0.6, 0.2) + 0.2 * noise(0.6) * np.exp(-x / 0.01))
save("sfx_tutorial_step", mix((0, bell(784, 0.5, 0.25)), (0.12, bell(1175, 0.45, 0.25))), 0.6)
x = t(1.0); save("sfx_trial_start", 0.9 * np.sin(2 * np.pi * 60 * x) * np.exp(-x / 0.12) + 0.35 * lp(noise(1.0), 0.06) * (x / 1.0) ** 2)
save("sfx_trial_held", mix((0, bell(523.25, 1.2, 0.5)), (0.0, bell(659.25, 1.2, 0.5)), (0.0, bell(783.99, 1.2, 0.5)), (0.25, bell(1046.5, 1.0, 0.4))))
save("sfx_trial_fail", mix((0, bell(440, 0.8, 0.3)), (0.22, bell(415.3, 0.8, 0.3)), (0.44, bell(349.2, 0.9, 0.35))))
x = t(0.25); save("sfx_trial_burn", lp(noise(0.25), 0.4) * np.exp(-x / 0.07) + 0.3 * np.sin(2 * np.pi * 1400 * x) * np.exp(-x / 0.05), 0.5)
x = t(0.3); save("sfx_trial_breach", np.sin(2 * np.pi * 80 * x) * np.exp(-x / 0.07) + 0.3 * lp(noise(0.3), 0.1) * np.exp(-x / 0.05))

# фоновые петли (8 с; частоты — целое число периодов за 8 с, шов петли бесшовный)
L = 8.0; x = t(L)
def q(f): return round(f * L) / L
calm = sum(g * np.sin(2 * np.pi * q(f) * x) for f, g in [(110, 1), (164.8, .6), (220, .5), (277.2, .25), (329.6, .2)])
calm *= 0.75 + 0.25 * np.sin(2 * np.pi * x / L)
save("dream_tone_calm", calm, 0.5)
uneasy = sum(g * np.sin(2 * np.pi * q(f) * x) for f, g in [(98, 1), (103.8, .8), (146.8, .5), (155.6, .45), (207.7, .3)])
uneasy *= 0.6 + 0.4 * np.sin(2 * np.pi * 3 * x / L)
save("dream_tone_uneasy", uneasy, 0.5)
print("ok")
