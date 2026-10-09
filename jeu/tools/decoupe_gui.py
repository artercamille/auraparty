#!/usr/bin/env python3
"""Découpe une planche d'éléments d'interface (générée par une IA) en PNG transparents.

Gère 3 cas de fond : vrai fond transparent, faux damier gris/blanc dessiné, ou fond uni
(vert fluo par défaut). Le fond est retiré par remplissage depuis les bords, donc l'intérieur
blanc des cadres (entouré d'un contour) est conservé.

Usage : python3 decoupe_gui.py planche.png dossier_sortie [--marge 6] [--fusion 14]
Produit element_01.png, element_02.png... (de gauche à droite, de haut en bas)
et _sommaire.png avec les numéros pour s'y retrouver.
"""
import sys
import os
import argparse
from collections import deque

from PIL import Image, ImageDraw, ImageFilter, ImageFont


def is_bg_factory(im):
    w, h = im.size
    px = im.load()
    # échantillon des bords pour deviner le type de fond
    border = [px[x, 0] for x in range(0, w, 7)] + [px[0, y] for y in range(0, h, 7)]
    alpha_bg = sum(1 for p in border if p[3] < 20) > len(border) * 0.6
    green_bg = sum(1 for p in border if p[1] > 180 and p[0] < 110 and p[2] < 110) > len(border) * 0.6
    if alpha_bg:
        # vrai fond transparent ; on retire aussi les halos flous, les traits de séparation
        # et les fonds gris clair opaques laissés par l'IA (arrêtés par les contours foncés)
        return "alpha", lambda p: p[3] < 150 or (min(p[:3]) > 175 and max(p[:3]) - min(p[:3]) < 28)
    if green_bg:
        return "vert", lambda p: p[1] > 150 and p[1] - max(p[0], p[2]) > 60
    # faux damier : gris très clairs sans couleur
    return "damier", lambda p: (max(p[:3]) - min(p[:3]) < 14 and min(p[:3]) > 212)


def remove_bg(im):
    kind, is_bg = is_bg_factory(im)
    w, h = im.size
    px = im.load()
    bg = bytearray(w * h)
    q = deque()
    for x in range(w):
        q.append((x, 0))
        q.append((x, h - 1))
    for y in range(h):
        q.append((0, y))
        q.append((w - 1, y))
    while q:
        x, y = q.popleft()
        i = y * w + x
        if bg[i] or not is_bg(px[x, y]):
            continue
        bg[i] = 1
        if x > 0:
            q.append((x - 1, y))
        if x < w - 1:
            q.append((x + 1, y))
        if y > 0:
            q.append((x, y - 1))
        if y < h - 1:
            q.append((x, y + 1))
    mask = Image.frombytes("L", (w, h), bytes(0 if b else 255 for b in bg))
    # bord adouci : on ronge 1 px puis on floute légèrement
    mask = mask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.8))
    out = im.copy()
    if kind == "vert":
        # retire le reflet vert sur les bords
        rgb = out.convert("RGB")
        rgb.putdata([(r, min(g, max(r, b) + 20), b) for r, g, b in rgb.getdata()])
        out = rgb.convert("RGBA")
    out.putalpha(mask)
    return kind, out, mask


def components(mask, fuse):
    w, h = mask.size
    m = mask.point(lambda v: 255 if v > 60 else 0)
    if fuse > 0:
        m = m.filter(ImageFilter.MaxFilter(fuse | 1))
    px = m.load()
    seen = bytearray(w * h)
    boxes = []
    for y in range(h):
        for x in range(w):
            if px[x, y] and not seen[y * w + x]:
                x0 = x1 = x
                y0 = y1 = y
                q = deque([(x, y)])
                seen[y * w + x] = 1
                n = 0
                while q:
                    cx, cy = q.popleft()
                    n += 1
                    x0, x1, y0, y1 = min(x0, cx), max(x1, cx), min(y0, cy), max(y1, cy)
                    for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                        if 0 <= nx < w and 0 <= ny < h and px[nx, ny] and not seen[ny * w + nx]:
                            seen[ny * w + nx] = 1
                            q.append((nx, ny))
                if n > 150:
                    boxes.append((x0, y0, x1 + 1, y1 + 1))
    # ordre de lecture : par bandes horizontales puis de gauche à droite
    boxes.sort(key=lambda b: (b[1] // 60, b[0]))
    return boxes


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("planche")
    ap.add_argument("sortie")
    ap.add_argument("--marge", type=int, default=6)
    ap.add_argument("--fusion", type=int, default=9, help="distance (px) sous laquelle deux morceaux forment un seul élément")
    a = ap.parse_args()
    im = Image.open(a.planche).convert("RGBA")
    kind, cut, mask = remove_bg(im)
    os.makedirs(a.sortie, exist_ok=True)
    boxes = components(mask, a.fusion)
    sheet = Image.new("RGBA", im.size, (40, 40, 60, 255))
    sheet.alpha_composite(cut)
    d = ImageDraw.Draw(sheet)
    for i, (x0, y0, x1, y1) in enumerate(boxes, 1):
        x0, y0 = max(0, x0 - a.marge), max(0, y0 - a.marge)
        x1, y1 = min(im.width, x1 + a.marge), min(im.height, y1 + a.marge)
        el = cut.crop((x0, y0, x1, y1))
        el.save(os.path.join(a.sortie, "element_%02d.png" % i))
        d.rectangle((x0, y0, x1, y1), outline=(255, 80, 80, 255), width=2)
        d.text((x0 + 3, y0 + 2), str(i), fill=(255, 255, 0, 255))
    sheet.save(os.path.join(a.sortie, "_sommaire.png"))
    print("fond :", kind, "·", len(boxes), "éléments ->", a.sortie)


if __name__ == "__main__":
    main()
