"""Original 16px icons/textures and connected crack graph. No copied Minecraft assets."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
root=Path(__file__).resolve().parents[1]; tex=root/'assets/textures'; icons=root/'assets/icons';shots=Path('/workspace/shots');shots.mkdir(exist_ok=True)
# Each edge starts on an existing junction; growth follows a fault, never a radial starburst.
edges=[(0,[(8,8),(7,7),(7,6),(6,5),(6,4),(5,3),(5,2),(4,1),(4,0)]),
 (1,[(8,8),(9,8),(10,9),(11,9),(12,10),(12,11),(13,12),(14,12),(15,13)]),
 (2,[(8,8),(7,9),(7,10),(6,11),(6,12),(5,13),(5,14),(4,15)]),
 (2,[(7,6),(8,5),(9,5),(10,4),(11,4),(12,3),(12,2),(13,1),(13,0)]),
 (3,[(6,11),(5,10),(4,10),(3,9),(2,9),(1,8),(0,8)]),
 (4,[(10,9),(11,8),(11,7),(12,6),(13,6),(14,5),(15,5)]),
 (5,[(6,4),(5,5),(4,5),(3,4),(2,4),(1,3),(0,3)]),
 (6,[(12,11),(11,12),(11,13),(10,14),(10,15)]),
 (7,[(2,9),(2,10),(1,11),(1,12),(0,13)]),
 (7,[(9,5),(9,4),(8,3),(8,2),(9,1),(9,0)]),
 (8,[(5,13),(6,14),(7,14),(8,15)]),
 (8,[(13,6),(13,7),(14,8),(15,8)]),
 (9,[(4,5),(3,6),(3,7),(2,7)]),
 (9,[(11,4),(11,3),(10,2)])]
for stage in range(10):
 im=Image.new('RGBA',(16,16));d=ImageDraw.Draw(im)
 for start,points in edges:
  if stage<start:continue
  count=min(len(points),2+int((stage-start)*(len(points)-2)/max(1,9-start)))
  d.line(points[:count], fill=(28,25,23,190 if start<4 else 172),width=1)
 im.save(tex/f'crack_{stage}.png')
# Sparse, deliberate texture clusters instead of procedural white-noise grit.
for name,base,light,shadow in [('handle',(138,92,45),(180,126,62),(99,60,28)),('wood_head',(158,112,60),(206,156,87),(112,73,35)),('stone_head',(137,144,149),(187,194,197),(94,102,110))]:
 im=Image.new('RGB',(16,16),base);d=ImageDraw.Draw(im)
 if name=='stone_head':
  for rect in [(1,2,4,3),(9,1,12,2),(6,7,8,8),(11,11,14,12),(1,12,3,14)]:d.rectangle(rect,fill=light)
  for rect in [(5,3,6,4),(12,6,14,7),(3,9,5,10),(8,13,10,14)]:d.rectangle(rect,fill=shadow)
 else:
  for x,y,length in [(3,1,6),(8,4,8),(13,0,5),(1,10,4),(11,12,3)]:
   d.line((x,y,x,y+length),fill=shadow);d.line((x+1,y+1,x+1,y+length-1),fill=light)
 im.save(tex/f'pickaxe_{name}.png')
for name,stone in [('pickaxe',False),('pickaxe2',True)]:
 im=Image.new('RGBA',(16,16));d=ImageDraw.Draw(im)
 outline=(47,35,24,255);wood=(146,96,44,255);hi=(207,158,83,255)
 d.line([(2,14),(10,5)],fill=outline,width=4)
 d.line([(3,13),(10,5)],fill=wood,width=2)
 d.line([(3,12),(9,5)],fill=hi,width=1)
 # Curved arch of the Kenney pickaxe, in the same diagonal icon presentation.
 pts=[(2,2),(5,0),(8,0),(11,2),(13,5),(15,8),(15,11),(13,10),(12,7),(10,5),(7,3),(4,3)]
 edge=(46,51,55,255) if stone else (66,43,24,255)
 mid=(135,145,151,255) if stone else (157,111,57,255)
 top=(210,217,219,255) if stone else (223,177,101,255)
 low=(88,99,107,255) if stone else (108,69,33,255)
 d.polygon(pts,fill=edge)
 d.line([(4,2),(6,1),(8,1),(10,2),(12,5),(14,8),(14,9)],fill=mid,width=2)
 d.line([(4,1),(6,1),(8,1),(10,3),(12,5)],fill=top,width=1)
 d.line([(8,3),(10,4),(12,6),(13,8)],fill=low,width=1)
 d.point((14,10),fill=low)
 d.line([(8,4),(10,6)],fill=outline,width=2);d.point((9,4),fill=hi)
 im.save(icons/f'{name}.png')
font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',19)
preview=Image.new('RGB',(640,370),(27,32,39));d=ImageDraw.Draw(preview)
for i,(name,label) in enumerate([('pickaxe','Деревянная'),('pickaxe2','Каменная')]):
 sprite=Image.open(icons/f'{name}.png');preview.paste(sprite.resize((256,256),Image.Resampling.NEAREST),(32+i*320,40),sprite.resize((256,256),Image.Resampling.NEAREST));d.text((64+i*320,310),label,font=font,fill='white')
preview.save(shots/'v091_pickaxe_icons.png')
# All ten actual overlay files over the game's stone and dirt atlas tiles.
atlas=Image.open(tex/'atlas.png').convert('RGBA')
# Resolve tile indices from BlockTex list below rather than hard-code an unrelated background.
import re
text=(root/'scripts/block_tex.gd').read_text();names=re.findall(r'"([^"]+)"',text.split('const TILES')[1].split(']')[0])
strip=Image.new('RGB',(1120,290),(27,32,39));d=ImageDraw.Draw(strip)
for row,kind in enumerate(['stone','dirt']):
 tile=atlas.crop((names.index(kind)*16,0,names.index(kind)*16+16,16))
 for i in range(10):
  image=Image.alpha_composite(tile,Image.open(tex/f'crack_{i}.png')).resize((96,96),Image.Resampling.NEAREST)
  strip.paste(image,(70+i*104,42+row*123));d.text((100+i*104,13+row*123),str(i),font=font,fill='white')
 d.text((3,78+row*123),'Камень' if row==0 else 'Земля',font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',13),fill='white')
strip.save(shots/'v091_cracks_strip.png')
print('v0.9.1 art + previews generated')
