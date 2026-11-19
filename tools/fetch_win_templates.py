"""Скачать из tpz Godot 4.7.2 только шаблоны Windows (HTTP Range, ~210 МБ вместо 1,28 ГБ). python3 tools/fetch_win_templates.py"""
import urllib.request, zipfile, os, io
URL="https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"
class HF:
    def __init__(s,url):
        s.url=urllib.request.urlopen(urllib.request.Request(url,method="HEAD")).geturl()
        s.size=int(urllib.request.urlopen(urllib.request.Request(s.url,method="HEAD")).headers["Content-Length"]); s.pos=0
    def seekable(s): return True
    def readable(s): return True
    def seek(s,o,w=0):
        s.pos = o if w==0 else (s.pos+o if w==1 else s.size+o); return s.pos
    def tell(s): return s.pos
    def read(s,n=-1):
        if n<0: n=s.size-s.pos
        if n==0 or s.pos>=s.size: return b""
        end=min(s.size,s.pos+n)-1
        r=urllib.request.Request(s.url,headers={"Range":"bytes=%d-%d"%(s.pos,end)})
        d=urllib.request.urlopen(r).read(); s.pos+=len(d); return d
f=HF(URL)
z=zipfile.ZipFile(f)
dst=os.path.expanduser("~/.local/share/godot/export_templates/4.7.2.stable/"); os.makedirs(dst,exist_ok=True)
for n in z.namelist():
    if n.endswith(("windows_release_x86_64.exe","windows_debug_x86_64.exe","version.txt")):
        d=z.read(n); open(dst+os.path.basename(n),"wb").write(d); print(n,len(d))
