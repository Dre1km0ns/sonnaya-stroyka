"""Deterministic original CC0 pixel art, additive to the existing v0.8 atlas."""
from PIL import Image,ImageDraw,ImageChops
from pathlib import Path
import random
root=Path(__file__).resolve().parents[1]; icons=root/'assets/icons'; tex=root/'assets/textures'
for i in range(10):
 im=Image.new('RGBA',(64,64));d=ImageDraw.Draw(im);rng=random.Random(94)
 for n in range(1,35):
  x,y=32,32
  angle=rng.random()*6.28
  import math
  end=(32+math.cos(angle)*rng.randint(17,40),32+math.sin(angle)*rng.randint(17,40))
  mx=(x+end[0])/2+rng.randint(-10,10);my=(y+end[1])/2+rng.randint(-10,10)
  if n<=3+i*3:d.line([(x,y),(mx,my),end],fill=(90,75,65,235),width=2 if i>5 else 1)
  if i>3 and n<=3+i*3:d.line([(mx,my),(mx+rng.randint(-9,9),my+rng.randint(-9,9))],fill=(110,95,80,210),width=1)
 im.save(tex/f'crack_{i}.png')
# Dedicated carved wood and flaked-stone tool tiles.
atlas=Image.open(tex/'atlas.png').convert('RGB');base=38*16
out=Image.new('RGB',(40*16,16));out.paste(atlas.crop((0,0,base,16)),(0,0))
for ti,col in enumerate([(139,91,46),(117,132,143)]):
 tile=Image.new('RGB',(16,16));d=ImageDraw.Draw(tile);rng=random.Random(ti+900)
 for y in range(16):
  for x in range(16):
   noise=rng.randint(-18,18)+(10 if (y%5==0 and ti==0) else 0)
   d.point((x,y),fill=tuple(max(0,min(255,c+noise)) for c in col))
 if ti==1:
  for line in [[(0,6),(6,3),(10,8),(15,5)],[(2,14),(7,9),(12,13)]]:d.line(line,fill=(66,80,89))
 out.paste(tile,(base+ti*16,0))
out.save(tex/'atlas.png')
for tier in ['wood','scale']:
 col=(155,108,58,255) if tier=='wood' else (66,143,133,255);light=(212,166,95,255) if tier=='wood' else (123,220,187,255)
 for part in ['helmet','chest','legs','boots']:
  im=Image.new('RGBA',(48,48));d=ImageDraw.Draw(im)
  pts={'helmet':[(9,33),(9,16),(16,9),(32,9),(39,16),(39,33),(31,33),(31,23),(17,23),(17,33)],'chest':[(8,13),(17,8),(20,16),(28,16),(31,8),(40,13),(38,24),(33,22),(33,40),(15,40),(15,22),(10,24)],'legs':[(12,9),(36,9),(36,40),(26,40),(25,23),(23,23),(22,40),(12,40)],'boots':[(12,10),(22,10),(22,29),(24,32),(24,40),(7,40),(7,32),(12,29)]}[part]
  d.polygon(pts,fill=col,outline=(36,37,35,255),width=2)
  if part=='boots':d.polygon([(x+19,y) for x,y in pts],fill=col,outline=(36,37,35,255),width=2)
  # Texture is clipped to filled silhouette.
  mask=im.getchannel('A')
  grain=Image.new('RGBA',im.size);g=ImageDraw.Draw(grain)
  for y in range(12,42,5):
   if tier=='wood':g.line((6,y,43,y),fill=(94,61,31,255));g.line((6,y+1,43,y+1),fill=light)
   else:
    for x in range(8+(y%2)*3,44,6):g.arc((x,y,x+7,y+6),0,180,fill=light,width=1)
  grain.putalpha(ImageChops.multiply(grain.getchannel("A"),mask));im=Image.alpha_composite(im,grain)
  im.save(icons/f'{tier}_{part}.png')
im=Image.new('RGBA',(48,48));d=ImageDraw.Draw(im);d.polygon([(24,5),(40,17),(33,35),(24,43),(14,35),(8,17)],fill=(57,128,122),outline=(21,53,57),width=3)
for y in range(15,38,6):d.arc((12,y,36,y+9),0,180,fill=(150,236,183),width=2)
im.save(icons/'anaconda_scale.png')
for id in ['pickaxe','pickaxe2']:
 im=Image.new('RGBA',(48,48));d=ImageDraw.Draw(im)
 d.line((12,41,29,13),fill=(39,27,21),width=8);d.line((12,40,29,13),fill=(156,102,51),width=5);d.line((14,37,29,14),fill=(207,151,75),width=1)
 stone=id=='pickaxe2';col=(125,145,157) if stone else (152,99,44);light=(197,215,218) if stone else (226,172,85)
 pts=[(8,20),(12,11),(24,6),(35,7),(42,15),(42,22),(36,16),(29,13),(19,15)]
 d.polygon(pts,fill=col,outline=(35,42,44) if stone else (63,38,19),width=2);d.line([(11,16),(23,9),(34,10),(39,16)],fill=light,width=2)
 d.line((23,17,31,19),fill=(88,63,43),width=4);d.line((23,15,31,17),fill=(209,185,126),width=2)
 im.save(icons/f'{id}.png')
print('v0.9 original art generated: 10 crack stages, 2 tiles, 11 icons')
