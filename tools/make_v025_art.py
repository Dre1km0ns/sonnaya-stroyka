"""v0.25 (t143u): нормальные иконки зелья скорости и металлической брони. python3 tools/make_v025_art.py
Зелье — из heal1.png (128 px): жидкость перекрашена в бирюзово-голубую, поверх молния.
Броня — из деревянной (48 px): дерево → сталь (яркость → стальная палитра), блик и заклёпки."""
from PIL import Image, ImageDraw
import colorsys
I = 'assets/icons/'

def speed_potion():
    im = Image.open(I + 'heal1.png').convert('RGBA')
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a == 0: continue
            h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
            if s > 0.35 and (h < 0.08 or h > 0.85):      # красная жидкость → бирюза
                r2, g2, b2 = colorsys.hls_to_rgb(0.52, min(1, l * 1.08), s)
                px[x, y] = (int(r2 * 255), int(g2 * 255), int(b2 * 255), a)
    d = ImageDraw.Draw(im)
    W = im.width / 128.0
    bolt = [(70, 62), (52, 92), (64, 92), (56, 116), (80, 82), (67, 82), (76, 62)]
    bolt = [(x * W, y * W) for x, y in bolt]
    d.polygon(bolt, fill=(255, 236, 90, 255), outline=(120, 80, 10, 255))
    im.save(I + 'speed_potion.png')

STEEL = [(46, 50, 58), (82, 88, 100), (128, 136, 150), (176, 184, 198), (222, 228, 238)]

def steel(lum):
    f = max(0.0, min(0.999, lum)) * (len(STEEL) - 1)
    k = int(f); t = f - k
    a, b = STEEL[k], STEEL[min(k + 1, len(STEEL) - 1)]
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def metal_from(wood, out):
    ## Силуэт берём у деревянной брони, заливка — гладкая сталь: сверху светлее, контур тёмный, блик слева.
    src = Image.open(I + wood).convert('RGBA')
    sp = src.load()
    W, H = src.size
    im = Image.new('RGBA', src.size, (0, 0, 0, 0))
    px = im.load()
    def inside(x, y):
        return 0 <= x < W and 0 <= y < H and sp[x, y][3] > 0
    bbox = src.getbbox() or (0, 0, W, H)
    x0, y0, x1, y1 = bbox
    for y in range(H):
        for x in range(W):
            if not inside(x, y): continue
            edge = not (inside(x - 1, y) and inside(x + 1, y) and inside(x, y - 1) and inside(x, y + 1))
            if edge:
                px[x, y] = (34, 38, 46, 255); continue
            fy = (y - y0) / max(1, y1 - y0); fx = (x - x0) / max(1, x1 - x0)
            l = 0.78 - 0.45 * fy + (0.15 if fx < 0.3 else 0.0) - (0.1 if fx > 0.8 else 0.0)
            c = steel(l)
            px[x, y] = (c[0], c[1], c[2], 255)
    for fx in (0.22, 0.78):
        cx, cy = int(x0 + (x1 - x0) * fx), int(y0 + (y1 - y0) * 0.28)
        if inside(cx, cy) and inside(cx + 1, cy + 1):
            for dx in (0, 1):
                for dy in (0, 1): px[cx + dx, cy + dy] = (236, 240, 248, 255)
    im.save(I + out)


if __name__ == '__main__':
    speed_potion()
    for part in ('helmet', 'chest', 'legs', 'boots'):
        metal_from('wood_%s.png' % part, 'metal_%s.png' % part)
    print('ok v025 art')
