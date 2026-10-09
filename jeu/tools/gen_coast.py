#!/usr/bin/env python3
"""Génère la silhouette de l'île (BoardMap.COAST) à partir du contenu du plateau.

L'île épouse les chemins et les lieux (lac, château, volcan, plage, village...) avec une marge,
puis on lisse et on ajoute une ondulation douce : on obtient des presqu'îles et des criques
naturelles au lieu d'un gros rectangle. Lit les chemins dans board/map.gd.

Usage : python3 tools/gen_coast.py  (écrit le tableau COAST dans board/map.gd)
"""
import re
import sys
import numpy as np
import cv2
from scipy import ndimage
from skimage import measure

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
SRC = ROOT + "/board/map.gd"
SCALE = 0.125          # 1 px du masque = 8 px du plateau
PAD = 800              # marge autour du plateau
MARGIN = 300           # distance mini entre un chemin et la côte

src = open(SRC, encoding="utf-8").read()
K = float(re.search(r"const K := ([\d.]+)", src).group(1))


def vec(s):
    return [(float(a), float(b)) for a, b in re.findall(r"Vector2\(\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*\)", s)]


# carrefours
junc = {}
for name, x, y in re.findall(r'"(\w+)": \[Vector2\((-?[\d.]+), (-?[\d.]+)\)', src.split("const J_ORDER")[0]):
    junc[name] = (float(x) * K, float(y) * K)
# chemins
segs = []
block = src.split("const SEGMENTS := [")[1].split("\n]\n")[0]
for line in block.strip().split("\n"):
    m = re.match(r'\s*\["(\w+)", "(\w+)", "\w+", \[(.*?)\]', line)
    if m:
        segs.append([junc[m.group(1)]] + [(x * K, y * K) for x, y in vec(m.group(3))] + [junc[m.group(2)]])


def catmull(pts, steps=24):
    out = []
    n = len(pts)
    for i in range(n - 1):
        p0 = np.array(pts[max(i - 1, 0)])
        p1 = np.array(pts[i])
        p2 = np.array(pts[i + 1])
        p3 = np.array(pts[min(i + 2, n - 1)])
        for k in range(steps):
            u = k / steps
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u * u + (-p0 + 3 * p1 - 3 * p2 + p3) * u ** 3))
    out.append(np.array(pts[-1]))
    return np.array(out)


W, H = int(4000 * K) + 2 * PAD, int(2700 * K) + 2 * PAD
mask = np.zeros((int(H * SCALE), int(W * SCALE)), np.uint8)
safe = np.zeros_like(mask)    # zone que les criques ne doivent jamais toucher


def P(x, y):
    return (int((x + PAD) * SCALE), int((y + PAD) * SCALE))


for s in segs:
    c = catmull(s)
    pts = np.array([P(x, y) for x, y in c], np.int32)
    cv2.polylines(mask, [pts], False, 255, int(2 * MARGIN * SCALE), lineType=cv2.LINE_AA)
    cv2.polylines(safe, [pts], False, 255, int(2 * 190 * SCALE), lineType=cv2.LINE_AA)
for (x, y) in junc.values():
    cv2.circle(mask, P(x, y), int(MARGIN * SCALE), 255, -1)

# lieux à garder sur l'île : (centre, rayons) en coordonnées du plateau
FEATURES = [
    ((820, 750), (430, 350)),      # lac
    ((1520, 700), (470, 380)),     # château
    ((3080, 760), (520, 470)),     # volcan
    ((3120, 1820), (440, 360)),    # lagon
    ((770, 1910), (260, 200)),     # étang
    ((2060, 1640), (260, 200)),    # statue
    ((1880, 1430), (200, 200)),    # moulin
    ((1570, 1520), (260, 180)),    # champ
    ((2370, 1310), (260, 180)),    # champ
    ((1700, 2050), (200, 200)),    # banque
    ((1705, 2520), (240, 190)),    # boutique du village
    ((1950, 2520), (620, 230)),    # maisons du bas du village
    ((2200, 2100), (330, 170)),    # maisons du haut du village
    ((3790, 2230), (190, 200)),    # phare
    ((3140, 2080), (430, 220)),    # plage (parasols)
]
FEATURES = [((cx * K, cy * K), (rx * K, ry * K)) for (cx, cy), (rx, ry) in FEATURES]
for (cx, cy), (rx, ry) in FEATURES:
    cv2.ellipse(mask, P(cx, cy), (int(rx * SCALE), int(ry * SCALE)), 0, 0, 360, 255, -1)

# caps : le phare au bout d'une presqu'île, une pointe au nord-ouest, une au sud-ouest
CAPES = [
    ((3900, 2420), (300, 170)),
]
CAPES = [((cx * K, cy * K), (rx * K, ry * K)) for (cx, cy), (rx, ry) in CAPES]
for (cx, cy), (rx, ry) in CAPES:
    cv2.ellipse(mask, P(cx, cy), (int(rx * SCALE), int(ry * SCALE)), 0, 0, 360, 255, -1)
m = mask > 127
# on bouche les trous intérieurs et on lisse (fermeture)
k = int(110 * SCALE)
m = ndimage.binary_closing(m, structure=np.ones((3, 3)), iterations=k)
m = ndimage.binary_fill_holes(m)
f = ndimage.gaussian_filter(m.astype(np.float32), 7)
# ondulation de la côte : bruit très basse fréquence + un peu de détail
rng = np.random.default_rng(7)
n1 = ndimage.gaussian_filter(rng.standard_normal(f.shape).astype(np.float32), 22)
n2 = ndimage.gaussian_filter(rng.standard_normal(f.shape).astype(np.float32), 7)
n1 /= np.abs(n1).max()
n2 /= np.abs(n2).max()
# le bruit ne doit pas grignoter les chemins : on le limite là où le masque est déjà « plein »
core = ndimage.gaussian_filter(mask.astype(np.float32) / 255.0, 3)
f = f + (n1 * 0.32 + n2 * 0.08) * (1.0 - np.clip(core * 2.0, 0, 1))
# criques taillées dans la côte, là où il n'y a ni chemin ni lieu
BAYS = [
    ((-80, 1320), (430, 210)),      # ouest, entre le lac et la forêt
    ((3960, 1330), (560, 250)),     # est, entre le volcan et la plage
    ((1130, 2930), (270, 340)),     # sud, entre la forêt et le village
    ((2580, -90), (330, 320)),      # nord, au col
    ((2860, 2830), (330, 340)),     # sud-est, entre le village et la plage
]
BAYS = [((cx * K, cy * K), (rx * K, ry * K)) for (cx, cy), (rx, ry) in BAYS]
for (cx, cy), (rx, ry) in BAYS:
    b = np.zeros_like(mask)
    cv2.ellipse(b, P(cx, cy), (int(rx * SCALE), int(ry * SCALE)), 0, 0, 360, 255, -1)
    b = ndimage.gaussian_filter(b.astype(np.float32) / 255.0, 4)
    f = f * (1.0 - b)
# on garde toujours les chemins et les lieux, avec une petite marge (sécurité)
for (cx, cy), (rx, ry) in FEATURES:
    cv2.ellipse(safe, P(cx, cy), (int(rx * SCALE * 0.8), int(ry * SCALE * 0.8)), 0, 0, 360, 255, -1)
f = np.maximum(f, ndimage.gaussian_filter((safe > 127).astype(np.float32), 2) * 0.75)
f = ndimage.gaussian_filter(f, 2)
cont = measure.find_contours(f, 0.5)
cont = max(cont, key=len)
pts = [((c[1] / SCALE) - PAD, (c[0] / SCALE) - PAD) for c in cont]
# simplification
arr = np.array(pts, np.float32).reshape(-1, 1, 2)
approx = cv2.approxPolyDP(arr, 14.0, True).reshape(-1, 2)
# sens horaire comme l'ancien contour
area = 0.5 * np.sum(approx[:, 0] * np.roll(approx[:, 1], -1) - np.roll(approx[:, 0], -1) * approx[:, 1])
if area < 0:
    approx = approx[::-1]
print("points :", len(approx), " x", approx[:, 0].min(), approx[:, 0].max(), " y", approx[:, 1].min(), approx[:, 1].max())
txt = "const COAST := [" + ", ".join("Vector2(%d, %d)" % (round(x), round(y)) for x, y in approx) + "]"
# retour à la ligne tous les 6 points
parts = txt.split("), ")
lines = []
for i in range(0, len(parts), 6):
    lines.append("), ".join(parts[i:i + 6]))
txt = "),\n\t".join(lines)
new = re.sub(r"const COAST := \[.*?\]\n", txt + "\n", src, flags=re.S)
open(SRC, "w", encoding="utf-8").write(new)
# aperçu
prev = np.zeros((H // 6, W // 6, 3), np.uint8)
prev[:] = (250, 230, 200)
poly = np.array([((x + PAD) / 6, (y + PAD) / 6) for x, y in approx], np.int32)
cv2.fillPoly(prev, [poly], (90, 200, 120))
cv2.polylines(prev, [poly], True, (60, 50, 40), 3)
for (cx, cy), (rx, ry) in FEATURES:
    cv2.ellipse(prev, (int((cx + PAD) / 6), int((cy + PAD) / 6)), (int(rx / 6), int(ry / 6)), 0, 0, 360, (200, 120, 60), 2)
for s in segs:
    c = catmull(s)
    cv2.polylines(prev, [np.array([((x + PAD) / 6, (y + PAD) / 6) for x, y in c], np.int32)], False, (230, 240, 250), 10)
cv2.imwrite(sys.argv[2] if len(sys.argv) > 2 else "/tmp/coast.png", prev)
