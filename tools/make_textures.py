#!/usr/bin/env python3
"""v0.6: процедурные pixel-art текстуры 16x16 (атлас блоков) + иконки предметов 128x128.
Запуск: python3 tools/make_textures.py  (детерминированно, seed фиксирован)."""
import random, math, os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX = os.path.join(ROOT, "assets", "textures")
ICONS = os.path.join(ROOT, "assets", "icons")
os.makedirs(TEX, exist_ok=True)
os.makedirs(ICONS, exist_ok=True)

TILES = ["grass_top", "grass_side", "dirt", "stone", "brick", "brick_mossy", "log_side", "log_top",
         "leaves", "sand", "water", "dream_top", "dream_side", "dream_dirt", "drift", "drift_dream",
         "drift_anchored", "mouth", "bench_top", "bench_side", "beacon", "planks", "dream_brick", "torch"]


def rng(name):
    return random.Random(hash_str(name))


def hash_str(s):
    h = 2166136261
    for ch in s.encode():
        h = ((h ^ ch) * 16777619) & 0xffffffff
    return h


def clamp(v):
    return max(0, min(255, int(v)))


def shade(c, k):
    return tuple(clamp(x * k) for x in c[:3]) + ((c[3],) if len(c) > 3 else (255,))


def noise_fill(img, pal, r, weights=None):
    w, h = img.size
    for y in range(h):
        for x in range(w):
            img.putpixel((x, y), r.choices(pal, weights=weights)[0])


def new():
    return Image.new("RGBA", (16, 16), (0, 0, 0, 255))


GRASS = [(96, 152, 62), (106, 164, 68), (88, 140, 56), (118, 172, 76), (80, 128, 50)]
DIRT = [(134, 96, 67), (121, 85, 58), (145, 106, 74), (110, 77, 52), (151, 113, 80)]
STONE = [(125, 125, 125), (115, 115, 115), (136, 136, 136), (104, 104, 106), (145, 145, 143)]


def t_grass_top():
    im = new(); r = rng("gt")
    noise_fill(im, GRASS, r, [3, 3, 3, 2, 2])
    for _ in range(10):
        x, y = r.randrange(16), r.randrange(16)
        im.putpixel((x, y), (132, 186, 88, 255))
    return im


def t_dirt(seed="dirt"):
    im = new(); r = rng(seed)
    noise_fill(im, DIRT, r, [4, 3, 2, 2, 1])
    for _ in range(6):
        x, y = r.randrange(16), r.randrange(16)
        im.putpixel((x, y), (96, 70, 48, 255))
    for _ in range(3):
        x, y = r.randrange(16), r.randrange(16)
        im.putpixel((x, y), (160, 150, 140, 255))
    return im


def t_grass_side():
    im = t_dirt("gs"); r = rng("gs2")
    for x in range(16):
        depth = 3 + (1 if r.random() < 0.45 else 0) + (1 if r.random() < 0.2 else 0)
        for y in range(depth):
            im.putpixel((x, y), r.choice(GRASS) + (255,) if len(GRASS[0]) == 3 else r.choice(GRASS))
    return im


def t_stone():
    im = new(); r = rng("stone")
    noise_fill(im, STONE, r, [4, 3, 2, 2, 1])
    for _ in range(4):
        x, y = r.randrange(15), r.randrange(15)
        for dx, dy in ((0, 0), (1, 0), (1, 1)):
            im.putpixel((x + dx, y + dy), (92, 92, 94, 255))
    return im


def brick(seed, base, mortar, moss=None):
    im = new(); r = rng(seed)
    for y in range(16):
        for x in range(16):
            c = r.choice(base)
            im.putpixel((x, y), c + (255,))
    for y in (0, 4, 8, 12):
        for x in range(16):
            im.putpixel((x, y), mortar + (255,))
    for row, y0 in enumerate((0, 4, 8, 12)):
        off = 0 if row % 2 == 0 else 4
        for x in range(off, 16, 8):
            for y in range(y0, y0 + 4):
                im.putpixel((x, y), mortar + (255,))
    # верхняя кромка кирпича светлее
    for row, y0 in enumerate((0, 4, 8, 12)):
        for x in range(16):
            if im.getpixel((x, y0 + 1))[:3] != mortar:
                im.putpixel((x, y0 + 1), shade(im.getpixel((x, y0 + 1)), 1.12))
    if moss:
        for _ in range(38):
            x, y = r.randrange(16), r.randrange(16)
            if y > 9 and r.random() < 0.5:
                continue
            im.putpixel((x, y), r.choice(moss) + (255,))
    return im


def t_log_side():
    im = new(); r = rng("logs")
    bark = [(102, 78, 48), (88, 66, 40), (116, 90, 56), (76, 57, 35)]
    for x in range(16):
        col = r.choice(bark)
        for y in range(16):
            c = col if r.random() < 0.7 else r.choice(bark)
            im.putpixel((x, y), c + (255,))
    for _ in range(5):
        x = r.randrange(16); y = r.randrange(13)
        for k in range(3):
            im.putpixel((x, y + k), (62, 46, 28, 255))
    return im


def t_log_top():
    im = new()
    for y in range(16):
        for x in range(16):
            d = max(abs(x - 7.5), abs(y - 7.5))
            if d > 6.6:
                c = (96, 72, 44)
            else:
                ring = int(d) % 2
                c = (176, 142, 90) if ring == 0 else (156, 122, 74)
            im.putpixel((x, y), c + (255,))
    return im


def t_leaves():
    im = new(); r = rng("leaves")
    pal = [(54, 112, 40), (64, 128, 46), (44, 96, 34), (74, 140, 52), (34, 78, 28)]
    noise_fill(im, pal, r, [3, 3, 2, 2, 2])
    for _ in range(14):
        x, y = r.randrange(16), r.randrange(16)
        im.putpixel((x, y), (26, 60, 22, 255))
    return im


def t_sand():
    im = new(); r = rng("sand")
    noise_fill(im, [(196, 182, 128), (186, 172, 120), (204, 192, 140), (176, 160, 110)], r)
    return im


def t_water():
    im = new(); r = rng("water")
    for y in range(16):
        for x in range(16):
            v = math.sin((x + y * 0.5) * 0.8) * 0.5 + math.sin((x * 0.3 - y) * 0.9) * 0.5
            c = (52 + v * 10, 104 + v * 18, 178 + v * 20)
            im.putpixel((x, y), (clamp(c[0]), clamp(c[1]), clamp(c[2]), 170))
    for _ in range(8):
        x, y = r.randrange(15), r.randrange(16)
        im.putpixel((x, y), (140, 190, 235, 190)); im.putpixel((x + 1, y), (140, 190, 235, 190))
    return im


def t_dream_top():
    im = new(); r = rng("dt")
    noise_fill(im, [(92, 74, 150), (104, 84, 166), (82, 66, 136), (118, 96, 180)], r)
    for _ in range(9):
        x, y = r.randrange(16), r.randrange(16)
        im.putpixel((x, y), (190, 160, 240, 255))
    return im


def t_dream_dirt(seed="dd"):
    im = new(); r = rng(seed)
    noise_fill(im, [(66, 52, 100), (58, 46, 90), (74, 60, 112), (50, 40, 78)], r)
    return im


def t_dream_side():
    im = t_dream_dirt("ds"); r = rng("ds2")
    for x in range(16):
        d = 3 + (1 if r.random() < 0.4 else 0)
        for y in range(d):
            im.putpixel((x, y), r.choice([(104, 84, 166), (92, 74, 150), (118, 96, 180)]) + (255,))
    return im


def framed(seed, pal, frame, inner=None):
    im = new(); r = rng(seed)
    noise_fill(im, pal, r)
    for i in range(16):
        for p in ((i, 0), (i, 15), (0, i), (15, i)):
            im.putpixel(p, frame + (255,))
    if inner:
        for i in range(2, 14):
            for p in ((i, 2), (i, 13), (2, i), (13, i)):
                im.putpixel(p, inner + (255,))
    return im


def t_drift():
    im = framed("drift", [(196, 156, 108), (184, 146, 98), (206, 168, 120), (176, 136, 90)], (122, 92, 60))
    r = rng("drift2")
    for y in range(3, 13, 3):
        for x in range(2, 14):
            if r.random() < 0.6:
                im.putpixel((x, y), (160, 122, 80, 255))
    return im


def t_drift_dream():
    im = framed("dd2", [(140, 122, 220), (128, 110, 206), (152, 136, 232), (118, 100, 192)], (78, 62, 150), (170, 156, 245))
    return im


def t_drift_anchored():
    im = framed("da", [(250, 186, 140), (240, 172, 128), (255, 200, 156)], (190, 110, 70), (255, 230, 190))
    for i in range(4, 12):
        im.putpixel((i, i), (255, 245, 220, 255)); im.putpixel((15 - i, i), (255, 245, 220, 255))
    return im


def t_mouth():
    im = new(); r = rng("mouth")
    noise_fill(im, [(170, 52, 72), (184, 62, 84), (150, 40, 62), (196, 76, 96)], r)
    for x in range(2, 14):
        for y in range(6, 11):
            im.putpixel((x, y), (40, 8, 16, 255))
    for x in range(3, 14, 2):
        im.putpixel((x, 6), (240, 236, 220, 255)); im.putpixel((x, 7), (220, 214, 200, 255))
        im.putpixel((x - 1 if x > 3 else x, 10), (240, 236, 220, 255))
    return im


def t_planks():
    im = new(); r = rng("planks")
    pal = [(170, 128, 80), (160, 118, 72), (180, 138, 88), (150, 110, 66)]
    for y in range(16):
        for x in range(16):
            im.putpixel((x, y), r.choice(pal) + (255,))
    for y in (3, 7, 11, 15):
        for x in range(16):
            im.putpixel((x, y), (112, 80, 46, 255))
    for row, y0 in enumerate((0, 4, 8, 12)):
        x = 5 if row % 2 else 12
        for y in range(y0, y0 + 3):
            im.putpixel((x, y), (122, 88, 52, 255))
    return im


def t_bench_top():
    im = t_planks()
    d = ImageDraw.Draw(im)
    d.rectangle([2, 2, 13, 13], outline=(84, 58, 32, 255))
    d.line([2, 7, 13, 7], fill=(84, 58, 32, 255)); d.line([7, 2, 7, 13], fill=(84, 58, 32, 255))
    return im


def t_bench_side():
    im = t_planks()
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, 15, 2], fill=(120, 86, 50, 255))
    # инструменты: пила и молоток
    d.line([3, 5, 3, 12], fill=(140, 140, 150, 255)); d.line([2, 5, 5, 5], fill=(90, 90, 100, 255))
    d.rectangle([9, 5, 12, 6], fill=(120, 120, 130, 255)); d.line([10, 7, 10, 12], fill=(96, 64, 34, 255))
    return im


def t_beacon():
    im = new(); r = rng("beacon")
    noise_fill(im, [(40, 46, 60), (34, 40, 54), (48, 56, 72)], r)
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, 15, 15], outline=(120, 220, 235, 255))
    d.rectangle([5, 5, 10, 10], fill=(110, 235, 250, 255))
    d.rectangle([6, 6, 9, 9], fill=(210, 255, 255, 255))
    return im


def t_dream_brick():
    return brick("dbrick", [(96, 80, 140), (86, 70, 128), (106, 90, 152)], (54, 44, 84))


def t_torch():
    im = t_log_side()
    return im


GEN = {
    "grass_top": t_grass_top, "grass_side": t_grass_side, "dirt": t_dirt, "stone": t_stone,
    "brick": lambda: brick("brick", [(128, 116, 104), (118, 106, 94), (138, 126, 112), (110, 98, 88)], (78, 70, 62)),
    "brick_mossy": lambda: brick("brickm", [(128, 116, 104), (118, 106, 94), (138, 126, 112)], (78, 70, 62),
                                 moss=[(76, 120, 52), (64, 104, 44), (90, 136, 60)]),
    "log_side": t_log_side, "log_top": t_log_top, "leaves": t_leaves, "sand": t_sand, "water": t_water,
    "dream_top": t_dream_top, "dream_side": t_dream_side, "dream_dirt": t_dream_dirt, "drift": t_drift,
    "drift_dream": t_drift_dream, "drift_anchored": t_drift_anchored, "mouth": t_mouth,
    "bench_top": t_bench_top, "bench_side": t_bench_side, "beacon": t_beacon, "planks": t_planks,
    "dream_brick": t_dream_brick, "torch": t_torch,
}

tiles = {}
atlas = Image.new("RGBA", (16 * len(TILES), 16))
for i, name in enumerate(TILES):
    im = GEN[name]()
    tiles[name] = im
    atlas.paste(im, (i * 16, 0))
    im.save(os.path.join(TEX, name + ".png"))
atlas.save(os.path.join(TEX, "atlas.png"))

# ---------------------------------------------------------------- иконки 128x128
S = 128


def iso_cube(top, left, right):
    """Изометрический куб из трёх 16x16 текстур (nearest), как иконки блоков в Minecraft."""
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    cx, cy = S / 2, S / 2
    a = 52  # полуширина
    b = 26  # полувысота ромба
    hgt = 56
    top_c = (cx, cy - hgt / 2 - b)
    # вершины
    T = (cx, top_c[1])            # верх ромба
    Lp = (cx - a, top_c[1] + b)
    Rp = (cx + a, top_c[1] + b)
    C = (cx, top_c[1] + 2 * b)
    def put_face(tex, origin, ex, ey, k):
        px = tex.load()
        for v in range(64):
            for u in range(64):
                fu, fv = (u + 0.5) / 64, (v + 0.5) / 64
                x = origin[0] + ex[0] * fu + ey[0] * fv
                y = origin[1] + ex[1] * fu + ey[1] * fv
                c = px[min(15, int(fu * 16)), min(15, int(fv * 16))]
                if c[3] < 10:
                    continue
                cc = shade(c, k)
                for ox in (0, 1):
                    for oy in (0, 1):
                        xi, yi = int(x) + ox, int(y) + oy
                        if 0 <= xi < S and 0 <= yi < S:
                            out.putpixel((xi, yi), cc)
    put_face(left, Lp, (C[0] - Lp[0], C[1] - Lp[1]), (0, hgt), 0.78)
    put_face(right, C, (Rp[0] - C[0], Rp[1] - C[1]), (0, hgt), 0.62)
    put_face(top, Lp, (T[0] - Lp[0], T[1] - Lp[1]), (C[0] - Lp[0], C[1] - Lp[1]), 1.0)
    return out


def sprite(rows, palette, scale=8):
    """Пиксель-арт 16x16 по строкам-символам."""
    im = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in palette:
                im.putpixel((x, y), palette[ch])
    return outline(im).resize((S, S), Image.NEAREST)


def outline(im):
    out = im.copy()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            if im.getpixel((x, y))[3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and im.getpixel((nx, ny))[3] > 0:
                        out.putpixel((x, y), (24, 18, 28, 255))
                        break
    return out


P = {
    "w": (150, 108, 62, 255), "W": (104, 72, 40, 255), "s": (196, 200, 210, 255), "S": (140, 146, 160, 255),
    "k": (90, 96, 110, 255), "y": (255, 214, 90, 255), "o": (255, 150, 40, 255), "r": (220, 70, 40, 255),
    "p": (170, 110, 240, 255), "P": (120, 70, 200, 255), "l": (230, 200, 255, 255), "m": (200, 60, 60, 255),
    "M": (240, 230, 220, 255), "g": (110, 200, 120, 255), "G": (60, 140, 80, 255), "c": (120, 235, 250, 255),
    "C": (40, 150, 190, 255), "d": (60, 66, 84, 255), "b": (240, 190, 140, 255), "B": (190, 120, 80, 255),
    "e": (255, 120, 190, 255), "E": (200, 60, 140, 255), "u": (240, 230, 250, 255), "U": (180, 170, 200, 255),
    "h": (255, 240, 200, 255), "n": (255, 255, 255, 255),
}

SPR = {
    "pickaxe": ["", " SSSSSS", "SskkkkSS", "S      kSS", "        wkS", "       w  kS", "      w    S", "     w", "    w", "   w", "  w", " w", "w"],
    "sword": ["             sS", "            ssS", "           ssS", "          ssS", "         ssS", "        ssS", "  k    ssS", "   k  ssS", "    kssS", "    kkS", "   wk k", "  ww   k", " ww", "yw", "y"],
    "torch": ["", "", "      yo", "     yoor", "     oyyo", "      oo", "      ww", "      wW", "      ww", "      wW", "      ww", "      wW", "      ww", "      wW"],
    "nail": ["", "", "    SSSSSSS", "    SsssssS", "      Ss", "      Ss", "      Ss", "      Ss", "      Ss", "      Ss", "      Ss", "      Ss", "       S"],
    "wedge": ["", "", "   bbbbbbbb", "   bhhhhhhbB", "    bhhhhbB", "    bhhhhbB", "     bhhbB", "     bhhbB", "      bbB", "      bbB", "       B"],
    "anchor3": ["", "      kkk", "      k k", "      kkk", "   ssssssss", "       s", "       s", "       s", "  s    s    s", "  ss   s   ss", "   sss s sss", "     sssss", "       s"],
    "beacon": ["", "      cc", "     cnnc", "     cncc", "      cc", "      CC", "     dCCd", "    dddddd", "   dkkkkkkd", "   dkkkkkkd", "   dddddddd"],
    "dust": ["", "", "", "        u", "     U    u", "   u   uU", "  UuuUuuuU", " uUuUUuUuuU", " UUuUUUuUUuU", "  UUUUUUUUU"],
    "reagent1": ["", "       l", "      lpP", "     lppPP", "     lppPP", "    lpppPPP", "    lpppPPP", "    lpppPPP", "     lppPP", "     lppPP", "      lpP", "       P"],
    "reagent2": ["", "", "    mmmmmm", "   mMmmmMmm", "  mmmmmmmmMm", "  mmMmmmmmmm", "   mmmmmmmm", "      hh", "      hh", "      hh", "     hhhh", "    GGGGGG"],
    "reagent3": ["", "", "  e      e", "  ee    eE", "  eEe  eEE", "   eEe eE", "   eeE eE  e", "    eEeE  eE", "  e eeEE eEE", "  eEeeEEeEE", "   kkkkkkkk", "  kkkkkkkkkk"],
    "unknown": ["", "    UUUUUU", "   U      U", "         U", "        U", "       U", "      U", "      U", "", "      U"],
}

iso = {
    "hill": ("grass_top", "grass_side", "grass_side"),
    "ground": ("grass_top", "grass_side", "grass_side"),
    "ruin": ("brick", "brick_mossy", "brick"),
    "drift": ("drift", "drift", "drift"),
    "mouth": ("mouth", "mouth", "mouth"),
    "workbench": ("bench_top", "bench_side", "bench_side"),
    "log": ("log_top", "log_side", "log_side"),
    "leaves": ("leaves", "leaves", "leaves"),
    "planks": ("planks", "planks", "planks"),
    "dirt": ("dirt", "dirt", "dirt"),
}
for name, (t, l, rr) in iso.items():
    iso_cube(tiles[t], tiles[l], tiles[rr]).save(os.path.join(ICONS, name + ".png"))
for name, rows in SPR.items():
    sprite(rows, P).save(os.path.join(ICONS, name + ".png"))
print("textures:", len(TILES), "icons:", len(iso) + len(SPR))

# ---------------------------------------------------------------- UI: сердечки HP (9x9 → 36x36)
HEART = ["  rr rr", " rnrrrrr", " rnrrrrr", " rrrrrrr", "  rrrrr", "   rrr", "    r"]
def heart(kind):
    im = Image.new("RGBA", (9, 8), (0, 0, 0, 0))
    for y, row in enumerate(HEART):
        for x, ch in enumerate(row):
            if ch == " ":
                continue
            if kind == "empty":
                c = (60, 30, 34, 255)
            elif kind == "half" and x >= 4:
                c = (60, 30, 34, 255)
            else:
                c = (236, 48, 52, 255) if ch == "r" else (255, 200, 200, 255)
            im.putpixel((x, y + 1), c)
    return outline(im).resize((36, 32), Image.NEAREST)
for k in ("full", "half", "empty"):
    heart(k).save(os.path.join(ICONS, "ui_heart_%s.png" % k))
print("hearts ok")
