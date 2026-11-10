from pathlib import Path
from PIL import Image,ImageDraw
# Original project art, exact 16 pixels per block; no external licence dependency.
im=Image.new('RGBA',(16,32));p=im.load()
for y in range(32):
 for x in range(16):
  grain=((x*17+y*7)%5)-2;p[x,y]=(124+grain*3,80+grain*2,44+grain,255)
d=ImageDraw.Draw(im)
for x in [0,15]:d.line((x,0,x,31),fill=(45,31,24))
for x in [1,14]:d.line((x,1,x,30),fill=(183,126,64) if x==1 else (76,46,29))
for y in [0,15,31]:d.line((0,y,15,y),fill=(48,32,24));d.line((1,y+1,14,min(31,y+1)),fill=(178,120,62))
for box in [(3,3,12,12),(3,19,12,28)]:
 d.rectangle(box,fill=(69,45,30),outline=(46,31,25));x,y,xx,yy=box;d.rectangle((x+1,y+1,xx-1,yy-1),fill=(111,73,40));d.line((x+1,y+1,xx-1,y+1),fill=(164,111,58));d.line((x+1,y+1,x+1,yy-1),fill=(151,101,54))
# Upper inset glazing with wood mullions.
d.rectangle((5,5,10,10),fill=(44,73,74),outline=(41,33,27));d.line((6,6,8,6),fill=(116,166,164));d.line((7,5,7,10),fill=(114,76,42));d.line((5,8,10,8),fill=(114,76,42))
for y in [5,24]:d.rectangle((0,y,2,y+2),fill=(47,49,47));d.point((1,y),fill=(133,140,128));d.point((1,y+2),fill=(19,23,23))
d.rectangle((12,17,13,20),fill=(34,37,33));d.point((12,17),fill=(180,168,109));d.line((12,18,14,18),fill=(204,178,102));im.save('assets/textures/door_v010.png')
# Inventory image of the same pixel door with an edge, no blurred upscale.
icon=Image.new('RGBA',(32,32));icon.paste(im,(8,0),im);ImageDraw.Draw(icon).line((24,1,24,30),fill=(56,38,28));icon.save('assets/icons/door.png')
# Scale sword: own jade-scale blade, bone/bronze guard and dark wood grip.
im=Image.new('RGBA',(24,24));d=ImageDraw.Draw(im)
d.polygon([(4,23),(1,20),(5,16),(3,14),(5,12),(8,14),(19,1),(22,0),(23,3),(10,16),(12,18),(10,20),(8,18)],fill=(14,36,36))
d.line((3,21,7,17),fill=(102,65,40),width=2);d.line((3,20,6,17),fill=(187,127,62))
d.line((5,14,10,19),fill=(165,137,72),width=2);d.line((6,13,11,18),fill=(227,205,116))
d.polygon([(8,14),(20,2),(22,1),(22,3),(10,16)],fill=(41,122,103));d.line((8,14,21,1),fill=(141,223,179));d.line((10,15,22,3),fill=(22,68,65))
for x,y in [(12,11),(15,8),(18,5)]:d.line((x,y,x+2,y),fill=(69,164,129))
im.save('assets/icons/sword3.png');im.save('assets/textures/sword3.png')

