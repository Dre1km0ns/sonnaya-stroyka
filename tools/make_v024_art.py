"""v0.24: тайлы атласа (руда, металл, бургер, клоун) и иконки 16×16 новых предметов.
Запуск из корня проекта; перезаписывает тайлы начиная с 41-го (после strut) и иконки ниже."""
from PIL import Image, ImageDraw
import random, colorsys
BASE_TILES = 41  # grass_top … strut
NEW_TILES = ["metal_ore", "metal", "bun", "patty", "lettuce", "clown", "cheese", "saucer"]

def noise_tile(seed, cols):
    r = random.Random(seed); t = Image.new('RGBA', (16, 16))
    for y in range(16):
        for x in range(16):
            t.putpixel((x, y), r.choice(cols) + (255,))
    return t

def stone_cols(): return [(118,118,118),(128,128,128),(108,108,110),(136,134,132)]

def tile_metal_ore():
    t = noise_tile("ore", stone_cols()); r = random.Random("ore2")
    spots = [(3,3),(10,2),(6,8),(12,10),(2,12),(9,13)]
    for (sx, sy) in spots:
        for dx, dy in [(0,0),(1,0),(0,1),(1,1)]:
            if r.random() < 0.85:
                t.putpixel((sx+dx, sy+dy), r.choice([(214,190,160),(196,170,140),(232,214,188)]) + (255,))
        t.putpixel((sx, sy), (250, 240, 220, 255))
    return t

def tile_metal():
    t = noise_tile("metal", [(176,180,188),(168,172,180),(186,190,198)])
    for i in range(16): t.putpixel((i, 0), (210,214,222,255)); t.putpixel((i, 15), (120,124,132,255))
    return t

def tile_bun():
    t = noise_tile("bun", [(214,140,60),(204,130,52),(224,152,70)]); r = random.Random("sesame")
    for _ in range(9): t.putpixel((r.randrange(1,15), r.randrange(1,15)), (250,240,200,255))
    return t

def tile_patty(): return noise_tile("patty", [(92,52,30),(80,44,26),(104,60,36),(70,38,22)])
def tile_lettuce(): return noise_tile("let", [(90,180,60),(76,160,50),(110,200,76)])
def tile_cheese(): return noise_tile("ch", [(250,200,50),(240,190,40),(255,214,80)])
def tile_saucer():
    t = noise_tile("sau", [(150,156,170),(140,146,160),(160,166,180)])
    for x in range(0,16,4): t.putpixel((x, 7), (255,80,60,255)); t.putpixel((x+1, 7), (255,200,60,255))
    return t
def tile_clown():
    t = Image.new('RGBA', (16,16))
    for y in range(16):
        for x in range(16):
            c = (230,40,40) if ((x//4)+(y//4)) % 2 == 0 else (250,250,250)
            t.putpixel((x,y), c+(255,))
    return t

MAKERS = [tile_metal_ore, tile_metal, tile_bun, tile_patty, tile_lettuce, tile_clown, tile_cheese, tile_saucer]

def build_atlas():
    atlas = Image.open('assets/textures/atlas.png').convert('RGBA')
    w = BASE_TILES * 16
    na = Image.new('RGBA', (w + 16 * len(MAKERS), 16))
    na.paste(atlas.crop((0, 0, w, 16)), (0, 0))
    for i, m in enumerate(MAKERS):
        na.paste(m(), (w + i * 16, 0))
    na.save('assets/textures/atlas.png')
    return na

# ---------------------------------------------------------------- иконки 16×16
def icon(): return Image.new('RGBA', (16, 16), (0,0,0,0))
def px(im, pts, col):
    for p in pts:
        if 0 <= p[0] < 16 and 0 <= p[1] < 16: im.putpixel(p, col + (255,) if len(col) == 3 else col)
def line(im, a, b, col):
    (x0,y0),(x1,y1) = a,b; n = max(abs(x1-x0), abs(y1-y0), 1)
    px(im, [(round(x0+(x1-x0)*i/n), round(y0+(y1-y0)*i/n)) for i in range(n+1)], col)
def outline(im, col=(30,24,20)):
    src = im.copy()
    for y in range(16):
        for x in range(16):
            if src.getpixel((x,y))[3] == 0:
                for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)]:
                    xx,yy = x+dx,y+dy
                    if 0<=xx<16 and 0<=yy<16 and src.getpixel((xx,yy))[3] > 0:
                        im.putpixel((x,y), col+(255,)); break
    return im

def recolor(path, hue_to=None, sat=None, light=1.0):
    im = Image.open(path).convert('RGBA'); out = icon()
    for y in range(16):
        for x in range(16):
            r,g,b,a = im.getpixel((x,y))
            if a == 0: continue
            h,l,s = colorsys.rgb_to_hls(r/255,g/255,b/255)
            if hue_to is not None and s > 0.12: h = hue_to
            if sat is not None: s = s*sat
            l = min(1.0, l*light)
            rr,gg,bb = colorsys.hls_to_rgb(h,l,s)
            out.putpixel((x,y),(int(rr*255),int(gg*255),int(bb*255),a))
    return out

def tool_pick(head, shine):
    im = icon()
    line(im, (4,12), (11,5), (120,80,44)); line(im, (5,12), (12,5), (98,64,34))
    for p in [(7,2),(8,2),(9,2),(10,2),(11,3),(12,4),(13,5),(13,6),(13,7),(6,3),(5,3)]: px(im,[p],head)
    px(im, [(8,3),(9,3),(10,3),(11,4),(12,5),(12,6)], shine)
    return outline(im)

def tool_sword(blade, shine, guard):
    im = icon()
    for i in range(9): px(im, [(4+i, 11-i), (5+i, 11-i)], blade)
    line(im, (5,10), (12,3), shine)
    line(im, (2,10), (6,14), guard)
    line(im, (1,15), (4,12), (98,64,34)); px(im,[(0,15)],(200,170,90))
    return outline(im)

def bow(wood, string):
    im = icon()
    arc = [(4,1),(6,1),(8,2),(10,3),(11,5),(12,7),(12,8),(11,10),(10,12),(8,13),(6,14),(4,14),(5,1),(7,2),(9,2),(11,4),(12,6),(12,9),(11,11),(9,13),(7,14)]
    px(im, arc, wood)
    line(im, (4,2), (4,13), string)
    return outline(im)

def arrow(head, fletch, shaft=(170,130,80)):
    im = icon()
    line(im, (3,12), (12,3), shaft)
    px(im, [(12,2),(13,2),(13,3),(13,4),(11,2),(12,4),(14,1)], head)
    px(im, [(2,12),(3,13),(2,13),(1,12),(3,14),(1,14),(2,11)], fletch)
    return outline(im)

def blob(cols, pts_fn):
    im = icon(); pts_fn(im, cols); return outline(im)

def make_icons():
    I = 'assets/icons/'
    ore = tile_metal_ore(); ore.save(I+'metal_ore.png')
    ing = icon()
    for y in range(6, 12):
        for x in range(2 + (11 - y)//2, 14 - (11 - y)//2): px(ing, [(x, y)], (190,194,204) if y > 6 else (226,230,238))
    px(ing, [(5,8),(6,8),(7,9)], (240,244,250)); outline(ing).save(I+'metal_ingot.png')
    tool_pick((180,184,196), (230,234,244)).save(I+'pickaxe3.png')
    tool_sword((186,190,202), (236,240,248), (90,90,100)).save(I+'metal_sword.png')
    for part in ['helmet','chest','legs','boots']:
        recolor(I+"wood_%s.png" % part, sat=0.1, light=1.9).save(I+'metal_%s.png' % part)
    bow((150,98,50), (235,235,220)).save(I+'bow.png')
    bow((170,176,190), (235,235,220)).save(I+'bow2.png')
    arrow((190,190,200), (240,240,240)).save(I+'arrow.png')
    arrow((250,246,226), (110,160,70), (130,150,80)).save(I+'arrow2.png')
    t = icon(); px(t, [(7,3),(8,3),(6,4),(9,4),(6,5),(9,5),(6,6),(7,6),(8,6),(9,6),(7,7),(8,7),(7,8),(8,8),(7,9),(8,10)], (250,248,236)); px(t,[(7,4),(8,4),(7,5)],(255,255,255)); outline(t).save(I+'milk_tooth.png')
    h = icon()
    for y in range(16):
        for x in range(16):
            dx, dy = x - 7.5, y - 7.0
            if (dx*dx/30 + dy*dy/26) < 1 and not (y < 5 and abs(dx) < 1): px(h, [(x,y)], (120,116,112) if (x+y)%3 else (96,92,90))
    px(h, [(6,6),(7,7),(8,6),(9,8)], (240,80,60)); outline(h).save(I+'stone_heart.png')
    f = icon(); line(f,(5,2),(10,13),(230,220,170)); line(f,(6,2),(10,12),(250,244,200)); line(f,(7,2),(11,12),(200,190,140)); px(f,[(4,2),(5,1),(6,1),(7,1),(8,2)],(70,120,60)); outline(f).save(I+'scale_fang.png')
    # бургер: булка, сыр, котлета, салат
    def burger(im, y0=3):
        for x in range(3,13): px(im,[(x,y0)],(214,140,60))
        for x in range(2,14): px(im,[(x,y0+1),(x,y0+2)],(224,152,70))
        px(im,[(5,y0+1),(9,y0+1),(11,y0+2),(7,y0+2)],(250,240,200))
        for x in range(2,14): px(im,[(x,y0+3)],(110,200,76))
        for x in range(2,14): px(im,[(x,y0+4)],(250,200,50))
        for x in range(2,14): px(im,[(x,y0+5),(x,y0+6)],(92,52,30))
        for x in range(2,14): px(im,[(x,y0+7)],(214,140,60))
        for x in range(3,13): px(im,[(x,y0+8)],(196,124,50))
    b = icon(); burger(b); px(b,[(7,12),(8,12),(7,13),(8,13),(7,14),(8,14)],(140,60,200)); outline(b).save(I+'burger_summoner.png')
    c = icon()
    for y in range(16):
        for x in range(16):
            d = ((x-7.5)**2 + (y-7.5)**2) ** 0.5
            if d < 6.5: px(c,[(x,y)], (255,170,40) if d > 4 else ((255,240,120) if d > 2 else (255,255,230)))
    outline(c, (90,40,10)).save(I+'burger_core.png')
    n = icon()
    for y in range(16):
        for x in range(16):
            d = ((x-7.5)**2 + (y-8)**2) ** 0.5
            if d < 5.5: px(n,[(x,y)], (230,30,40) if d > 1.8 else (255,120,120))
    px(n,[(6,5),(5,6)],(255,200,200)); outline(n).save(I+'clown_nose.png')
    g = icon()
    for x in range(1,15): px(g,[(x,8)],(150,156,170))
    for x in range(3,13): px(g,[(x,7),(x,9)],(170,176,190))
    for x in range(5,11): px(g,[(x,5),(x,6)],(130,200,255))
    for x in range(1,15,3): px(g,[(x,8)],(255,80,60))
    for x in range(4,12,2): px(g,[(x,10)],(60,60,70))
    outline(g).save(I+'grill_saucer.png')
    tr = icon(); burger(tr, 1)
    for x in range(5,11): px(tr,[(x,11),(x,12)],(220,180,50))
    for x in range(3,13): px(tr,[(x,13),(x,14)],(190,150,40))
    outline(tr).save(I+'burger_trophy.png')
    recolor(I+'heal1.png', hue_to=0.5, light=1.05).save(I+'speed_potion.png')

if __name__ == '__main__':
    build_atlas(); make_icons(); print("ok tiles", BASE_TILES, "+", len(MAKERS))
