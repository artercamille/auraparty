#!/usr/bin/env python3
# Extrait quelques fichiers d'un gros zip en ligne (ex. les modèles d'export Godot, .tpz de 1 Go) sans tout
# télécharger : requêtes HTTP Range (GitHub refuse les « suffix range », d'où la taille demandée d'abord).
# Lister : python3 -I zip_distant.py URL      Extraire : python3 -I zip_distant.py URL a,b,c DOSSIER
import io, sys, zipfile, urllib.request, os
URL = sys.argv[1]
def resolve(u):
    req = urllib.request.Request(u, method="GET", headers={"Range": "bytes=0-0"})
    with urllib.request.urlopen(req) as r:
        cr = r.headers.get("Content-Range")
        return r.geturl(), int(cr.split("/")[1])
class HF(io.RawIOBase):
    def __init__(self, url):
        self.url, self.size = resolve(url); self.pos = 0; self.cache = {}
    def seekable(self): return True
    def readable(self): return True
    def tell(self): return self.pos
    def seek(self, off, wh=0):
        self.pos = off if wh == 0 else self.pos + off if wh == 1 else self.size + off
        return self.pos
    def readinto(self, b):
        n = min(len(b), self.size - self.pos)
        if n <= 0: return 0
        req = urllib.request.Request(self.url, headers={"Range": "bytes=%d-%d" % (self.pos, self.pos + n - 1)})
        with urllib.request.urlopen(req) as r:
            data = r.read()
        b[:len(data)] = data; self.pos += len(data); return len(data)
f = io.BufferedReader(HF(URL), buffer_size=1 << 20)
z = zipfile.ZipFile(f)
if len(sys.argv) == 2:
    for i in z.infolist(): print(i.filename, i.file_size)
else:
    out = sys.argv[3]
    for name in sys.argv[2].split(","):
        with z.open(name) as src, open(os.path.join(out, os.path.basename(name)), "wb") as dst:
            while True:
                chunk = src.read(1 << 22)
                if not chunk: break
                dst.write(chunk)
        print("ok", name)
