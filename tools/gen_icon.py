"""v0.21: иконка игры (окно и Windows .exe). python3 tools/gen_icon.py → assets/icon/icon_256.png, icon.ico"""
from PIL import Image, ImageDraw, ImageFilter
S = 1024
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
# фон: ночное небо Сна с градиентом
bg = Image.new("RGBA", (S, S))
for y in range(S):
    t = y / S
    c = (int(40 + 60 * t), int(26 + 30 * t), int(80 + 50 * t), 255)
    ImageDraw.Draw(bg).line([(0, y), (S, y)], fill=c)
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=190, fill=255)
img.paste(bg, (0, 0), mask)
d = ImageDraw.Draw(img)
# звёзды
import random
random.seed(21)
for _ in range(40):
    x, y = random.randint(80, S - 80), random.randint(70, 520)
    r = random.choice([4, 5, 7])
    d.ellipse([x - r, y - r, x + r, y + r], fill=(240, 235, 255, random.randint(150, 255)))
# луна Сна с кольцом
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse([600, 110, 900, 410], fill=(255, 200, 150, 140))
img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(40)))
d.ellipse([650, 160, 850, 360], fill=(255, 214, 160, 255))
d.ellipse([705, 140, 905, 340], fill=(70, 46, 112, 255))  # серп
d.arc([590, 210, 910, 310], 200, 340, fill=(200, 180, 255, 220), width=14)
def cube(x, y, s, top, left, right, outline=None):
    h = s // 2
    d.polygon([(x, y), (x + s, y - h), (x + 2 * s, y), (x + s, y + h)], fill=top, outline=outline)
    d.polygon([(x, y), (x + s, y + h), (x + s, y + h + s), (x, y + s)], fill=left, outline=outline)
    d.polygon([(x + s, y + h), (x + 2 * s, y), (x + 2 * s, y + s), (x + s, y + h + s)], fill=right, outline=outline)
# сияние за блоком Сна
g2 = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(g2).ellipse([450, 330, 930, 810], fill=(170, 140, 255, 150))
img.alpha_composite(g2.filter(ImageFilter.GaussianBlur(60)))
d = ImageDraw.Draw(img)
# блок Яви (камень/кирпич) и парящий блок Сна
cube(150, 610, 210, (196, 168, 130, 255), (150, 120, 88, 255), (120, 94, 68, 255))
cube(520, 440, 190, (205, 185, 255, 255), (150, 120, 235, 255), (115, 88, 200, 255))
# «нить якоря» между ними
for i in range(9):
    x = 450 + i * 18; y = 690 - i * 22
    d.ellipse([x - 9, y - 9, x + 9, y + 9], fill=(255, 220, 140, 230))
img.save("assets/icon/icon_1024.png")
img.resize((256, 256), Image.LANCZOS).save("assets/icon/icon_256.png")
img.resize((256, 256), Image.LANCZOS).save("assets/icon/icon.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print("ok")
