"""v0.24: процедурные звуки (собственный синтез, CC0). Пишет assets/audio/sfx_*.ogg через ffmpeg.
Запуск из корня проекта: python3 tools/make_v024_sfx.py"""
import numpy as np, wave, subprocess, os
SR = 22050
rng = np.random.default_rng(24)

def t(d): return np.arange(int(SR * d)) / SR
def env(n, a=0.005, r=None, curve=4.0):
    x = np.linspace(0, 1, n); e = np.exp(-curve * x)
    na = max(1, int(SR * a)); e[:na] *= np.linspace(0, 1, na)
    return e
def noise(d): return rng.uniform(-1, 1, int(SR * d))
def lp(x, k):
    # простой однополюсный ФНЧ, k∈(0,1): меньше — глуше
    y = np.zeros_like(x); acc = 0.0
    for i in range(len(x)):
        acc += k * (x[i] - acc); y[i] = acc
    return y
def hp(x, k): return x - lp(x, k)
def tone(f, d, shape='sin'):
    ph = 2 * np.pi * np.cumsum(np.full(int(SR * d), f) if np.isscalar(f) else f) / SR
    if shape == 'sin': return np.sin(ph)
    if shape == 'sq': return np.sign(np.sin(ph))
    if shape == 'saw': return 2 * ((ph / (2 * np.pi)) % 1) - 1
    if shape == 'tri': return 2 * np.abs(2 * ((ph / (2 * np.pi)) % 1) - 1) - 1
def sweep(f0, f1, d): return np.linspace(f0, f1, int(SR * d))
def norm(x, peak=0.8):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak
def save(name, x, peak=0.8, loop=False):
    x = norm(x, peak)
    if loop:
        n = int(SR * 0.05); x[:n] = x[:n] * np.linspace(0, 1, n) + x[-n:] * np.linspace(1, 0, n); x = x[:-n]
    path = 'assets/audio/sfx_%s.wav' % name
    with wave.open(path, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', path, '-c:a', 'libvorbis', '-q:a', '4', path[:-4] + '.ogg'], check=True)
    os.remove(path)

def thump(f, d, nk, k):
    n = int(SR * d)
    return (tone(sweep(f, f * 0.5, d), d) * 0.7 + lp(noise(d), k) * nk) * env(n, 0.002, curve=9)

def make():
    # шаги по материалу
    save('step_grass', lp(noise(0.12), 0.25) * env(int(SR * .12), .004, curve=10), 0.5)
    save('step_stone', (hp(noise(0.09), 0.3) * 0.6 + thump(180, .09, .3, .3)) * 1.0, 0.5)
    save('step_wood', thump(260, 0.11, 0.25, 0.2) + tone(520, .11) * .2 * env(int(SR * .11), .002, curve=14), 0.5)
    save('step_sand', lp(noise(0.16), 0.45) * env(int(SR * .16), .02, curve=6), 0.45)
    # удар по мобу, урон игроку, подбор, постановка
    save('hit', thump(140, 0.16, 0.6, 0.35))
    save('hurt', thump(110, 0.25, 0.5, 0.15) + tone(sweep(420, 180, .25), .25, 'sq') * 0.15 * env(int(SR * .25), .002, curve=6))
    save('pickup', np.concatenate([tone(880, .05) * env(int(SR*.05), .002, curve=3), tone(1320, .07) * env(int(SR*.07), .002, curve=5)]), 0.45)
    save('place', thump(220, 0.12, 0.35, 0.25), 0.6)
    save('swing', hp(noise(0.18), 0.15) * np.sin(np.linspace(0, np.pi, int(SR*.18))) ** 2, 0.4)
    # добыча (тик удара) по материалу
    save('mine_stone', hp(noise(0.07), 0.5) * env(int(SR*.07), .001, curve=12) + thump(300, .07, .1, .3) * .5, 0.5)
    save('mine_wood', thump(330, 0.08, 0.2, 0.2), 0.5)
    save('mine_dirt', lp(noise(0.08), 0.2) * env(int(SR*.08), .002, curve=9), 0.5)
    save('mine_leaves', hp(noise(0.08), 0.6) * env(int(SR*.08), .002, curve=7) * 0.6, 0.4)
    save('break_metal', tone(sweep(900, 600, .35), .35, 'tri') * env(int(SR*.35), .001, curve=6) + hp(noise(.35), .5) * .3 * env(int(SR*.35), .001, curve=10), 0.6)
    # лук
    d = 0.5; save('bow_draw', lp(noise(d), 0.05) * np.linspace(0.2, 1, int(SR*d)) + tone(sweep(90, 160, d), d, 'saw') * .08, 0.35)
    save('bow_shot', tone(sweep(260, 180, .25), .25, 'tri') * env(int(SR*.25), .001, curve=10) + hp(noise(.25), .2) * .4 * env(int(SR*.25), .001, curve=14), 0.6)
    save('arrow_hit', thump(400, 0.09, 0.5, 0.5), 0.55)
    # мобы
    save('mob_die', tone(sweep(500, 90, .45), .45, 'sq') * 0.4 * env(int(SR*.45), .002, curve=3) + lp(noise(.45), .1) * .3 * env(int(SR*.45), .002, curve=5), 0.55)
    save('mob_jump', tone(sweep(200, 420, .15), .15, 'tri') * env(int(SR*.15), .002, curve=4), 0.45)
    save('mob_shoot', tone(sweep(700, 300, .18), .18, 'sq') * 0.4 * env(int(SR*.18), .001, curve=6), 0.45)
    save('mob_steal', np.concatenate([tone(660, .06), tone(990, .06), tone(1320, .08)]) * 0.5, 0.4)
    # Бургер Смерти
    save('clown_honk', (tone(sweep(330, 300, .35), .35, 'saw') + tone(sweep(415, 380, .35), .35, 'saw')) * env(int(SR*.35), .01, curve=2.5), 0.6)
    save('explosion', lp(noise(1.0), 0.08) * env(int(SR*1.0), .002, curve=4) + tone(sweep(80, 30, 1.0), 1.0) * env(int(SR*1.0), .002, curve=5), 0.9)
    d = 0.9; save('laser_charge', tone(sweep(200, 1200, d), d, 'saw') * np.linspace(0.1, 1, int(SR*d)) * 0.5, 0.45)
    d = 0.6; save('laser', (tone(sweep(1400, 900, d), d, 'sq') * .3 + hp(noise(d), .3) * .2) * env(int(SR*d), .002, curve=3), 0.6)
    save('slam', thump(70, 0.8, 0.9, 0.06), 0.9)
    save('rain_whistle', tone(sweep(1800, 600, .7), .7) * np.linspace(0.3, 1, int(SR*.7)) * 0.4, 0.4)
    save('eat', np.concatenate([lp(noise(.08), .3) * env(int(SR*.08), .001, curve=8)] * 3 + [np.zeros(int(SR*.05))]), 0.55)
    save('shard', tone(sweep(1200, 1500, .2), .2, 'tri') * env(int(SR*.2), .001, curve=5), 0.45)
    save('weakpoint', np.concatenate([tone(1000, .05, 'sq'), tone(1500, .05, 'sq'), tone(2000, .1, 'sq')]) * .35, 0.5)
    save('victory', np.concatenate([tone(f, .16, 'tri') * env(int(SR*.16), .005, curve=2) for f in [523, 659, 784, 1047, 784, 1047]] + [tone(1047, .6, 'tri') * env(int(SR*.6), .01, curve=2)]), 0.6)
    save('ui_click', tone(1200, .03, 'sq') * env(int(SR*.03), .001, curve=10), 0.3)
    save('summon', tone(sweep(80, 400, 1.2), 1.2, 'saw') * np.linspace(0.2, 1, int(SR*1.2)) * 0.4 + lp(noise(1.2), .1) * .3, 0.6)
    # фоновые петли
    d = 4.0; save('rain_loop', lp(hp(noise(d), 0.2), 0.6) * 0.8 + (rng.uniform(0, 1, int(SR*d)) > 0.9993) * 1.0 * 0.6, 0.35, loop=True)
    d = 8.0; tt = t(d)
    pad = sum(np.sin(2*np.pi*f*tt) * (0.5 + 0.5*np.sin(2*np.pi*tt/d*k)) for f, k in [(220, 1), (277.2, 2), (329.6, 1), (440, 3)])
    save('dream_ambience', pad * 0.3 + lp(noise(d), 0.02) * 0.4, 0.3, loop=True)
    d = 6.0; save('wind_loop', lp(noise(d), 0.03) * (0.6 + 0.4*np.sin(2*np.pi*t(d)/d*2)), 0.3, loop=True)

if __name__ == '__main__':
    make(); print('sfx ok')
