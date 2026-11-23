"""v0.22.1: тайл «strut» (подпорка: тёмная рамка с крестом) — дописывается 41-м тайлом в atlas.png и иконку.
Запуск один раз из корня проекта; повторный запуск заменит последний тайл."""
from PIL import Image
import random
r = random.Random("strut")
t = Image.new('RGBA', (16, 16), (40, 30, 24, 255))
dark = [(92, 62, 38), (84, 56, 34), (100, 68, 42)]
mid = [(128, 90, 54), (120, 84, 50), (136, 96, 58)]
for i in range(16):
    for w in (0, 1):
        for p in [(i, w), (i, 15 - w), (w, i), (15 - w, i)]:
            t.putpixel(p, r.choice(dark) + (255,))
for i in range(2, 14):
    for dx in (0, 1):
        for (x, y) in [(i + dx, i), (15 - i - dx, i)]:
            if 1 < x < 14:
                t.putpixel((x, y), r.choice(mid) + (255,))
for (x, y) in [(1, 1), (14, 1), (1, 14), (14, 14), (7, 7), (8, 8)]:
    t.putpixel((x, y), (170, 170, 175, 255))
atlas = Image.open('assets/textures/atlas.png').convert('RGBA')
w = 640 if atlas.size[0] >= 656 else atlas.size[0]
na = Image.new('RGBA', (w + 16, 16)); na.paste(atlas.crop((0, 0, w, 16)), (0, 0)); na.paste(t, (w, 0))
na.save('assets/textures/atlas.png')
out = Image.new('RGBA', (128, 128), (0, 0, 0, 0)); out.paste(t.resize((112, 112), Image.NEAREST), (8, 8))
out.save('assets/icons/strut.png')
