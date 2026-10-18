"""Генератор дорожного тайлсета и раскладки дорог уровня 01.

Запуск (из корня проекта, нужен Python 3 + numpy + scipy + Pillow):
    python tools/road/build_road_tiles.py            # только картинки тайлсета
    python tools/road/build_road_tiles.py --level    # + раскладка дорог Level01 (JSON для сборщика)

Что делает:
1. Вырезает чистые кусочки асфальта с листа-референса
   assets/tilesets/road/reference/road-tileset-sheet.png и собирает из них бесшовную
   текстуру asphalt-v001.png (512×256). Её в игре накладывает шейдер по мировым координатам,
   поэтому асфальт не повторяется по клеткам и не имеет швов.
2. Рисует тайлы 64×32 (road-tiles-v001.png):
   ряд 0 — 15 тайлов автотайлинга «по углам» (Terrain «Асфальт», Match Corners);
   следующие ряды — скругления углов (внутренние радиус 6, внешние радиус 3 клетки)
   и особые тайлы раскладки уровня (например, сужения автобусного кармана).
   Пиксели асфальта в атласе помечены альфой 254 — шейдер заменяет их мировой текстурой.
3. Рисует разметку (road-markings-v001.png): осевая пунктирная линия и полосы «зебры» в обе стороны.
4. С флагом --level считает раскладку дорог Level01 и пишет tools/road/out/level01_cells.json.

ВНИМАНИЕ: Level01.tscn после сборки редактируется в Godot вручную. Повторная сборка уровня
(tools/road/build_road_resources.gd с флагом level) перезапишет ручные правки слоёв Road и RoadMarkings.
"""
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "tilesets", "road")
SHEET = os.path.join(OUT_DIR, "reference", "road-tileset-sheet.png")
TOOL_OUT = os.path.join(ROOT, "tools", "road", "out")

TW, TH = 64, 32            # размер тайла
RES = 16                   # отсчётов растра на клетку
R_CONCAVE = 6              # радиус скругления внутренних углов (перекрёстки), клеток
R_CONVEX = 3               # радиус скругления внешних углов (повороты), клеток
TERRAIN_ROUND = 0.5        # скругление внутри одного тайла автотайлинга

# Профиль края дороги от границы асфальта внутрь, в клетках (1 клетка ≈ 0,6 м).
C_EDGE = 0.05              # тёмная внешняя грань бордюра
C_CURB = 0.27              # верх бордюрного камня
C_GUTTER = 0.32            # тёмная полоса-лоток у бордюра

ASPHALT_FLAG = 254
CURB_RGB = np.array([169, 141, 117], float)    # цвета взяты с листа-референса
EDGE_RGB = np.array([92, 78, 68], float)
JOINT_RGB = np.array([110, 92, 78], float)
GUTTER_RGB = np.array([58, 52, 50], float)
PAINT_RGB = np.array([221, 195, 170], float)

ATLAS_COLS = 16


# ---------------------------------------------------------------- асфальт
def build_asphalt(seed=7):
    rng = np.random.default_rng(seed)
    a = np.array(Image.open(SHEET).convert("RGB")).astype(float)
    R, G, B = a[..., 0], a[..., 1], a[..., 2]
    L = (R + G + B) / 3
    ok = (R - B >= -4) & (R - B <= 34) & (L >= 45) & (L <= 145) & (G - B >= -6)
    PW, PH = 24, 12
    pts = []
    for y in range(100, 1020 - PH, 3):
        if 790 < y < 830:          # полоса заголовка «Примеры стыковки»
            continue
        for x in range(125, a.shape[1] - PW, 3):
            if ok[y:y + PH, x:x + PW].all():
                pts.append((x, y))
    pts = np.array(pts)
    W, H = 512, 256
    mu = np.array([102.0, 92.0, 88.0])
    yy, xx = np.mgrid[0:PH, 0:PW]
    bx = np.minimum(xx + 0.5, PW - xx - 0.5) / (PW * 0.17)
    by = np.minimum(yy + 0.5, PH - yy - 0.5) / (PH * 0.17)
    w = np.clip(np.minimum(bx, by), 0, 1)
    w = w * w * (3 - 2 * w)
    acc = np.zeros((H, W, 3))
    acc2 = np.zeros((H, W))
    sx_, sy_ = 19, 9
    for gy in range(0, H + sy_, sy_):
        for gx in range(0, W + sx_, sx_):
            x0 = gx + rng.integers(-2, 3) + (sx_ // 2 if (gy // sy_) % 2 else 0)
            y0 = gy + rng.integers(-1, 2)
            px, py = pts[rng.integers(len(pts))]
            p = a[py:py + PH, px:px + PW] - mu
            ys = (np.arange(PH) + y0) % H
            xs = (np.arange(PW) + x0) % W
            acc[np.ix_(ys, xs)] += w[..., None] * p
            acc2[np.ix_(ys, xs)] += w * w
    out = acc / np.sqrt(np.maximum(acc2, 1e-6))[..., None]

    def pnoise(cx, cy):
        g = rng.random((cy, cx))
        Y, X = np.mgrid[0:H, 0:W]
        fx, fy = X / W * cx, Y / H * cy
        x0, y0 = np.floor(fx).astype(int), np.floor(fy).astype(int)
        tx, ty = fx - x0, fy - y0
        tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
        x1, y1 = (x0 + 1) % cx, (y0 + 1) % cy
        x0, y0 = x0 % cx, y0 % cy
        return (g[y0, x0] * (1 - tx) + g[y0, x1] * tx) * (1 - ty) + (g[y1, x0] * (1 - tx) + g[y1, x1] * tx) * ty

    n = 0.6 * pnoise(8, 8) + 0.4 * pnoise(16, 16) - 0.5
    dust = np.clip((pnoise(12, 12) - 0.62) * 4, 0, 1)
    out = mu + out * 1.15 + n[..., None] * 38
    out = out * (1 - 0.35 * dust[..., None]) + np.array([150, 128, 100]) * 0.35 * dust[..., None]
    return np.clip(out, 0, 255).astype(np.uint8)


# ---------------------------------------------------------------- растр формы
class Field:
    """Знаковое расстояние до края асфальта (в клетках, > 0 внутри) на растре в координатах сетки Godot."""

    def __init__(self, x0, y0, nx, ny):
        self.x0, self.y0 = x0, y0
        gx = x0 + (np.arange(nx * RES) + 0.5) / RES
        gy = y0 + (np.arange(ny * RES) + 0.5) / RES
        self.GX, self.GY = np.meshgrid(gx, gy)       # [строка=y, столбец=x]
        self.mask = np.zeros(self.GX.shape, bool)

    def add_rect(self, xa, xb, ya, yb):
        self.mask |= (self.GX > xa) & (self.GX < xb) & (self.GY > ya) & (self.GY < yb)

    def round(self, r_concave, r_convex):
        m = self.mask
        if r_concave > 0:     # закрытие: скругляет внутренние углы
            m = m | (distance_transform_edt(~m) <= r_concave * RES)
            m = distance_transform_edt(m) > r_concave * RES
        if r_convex > 0:      # открытие: скругляет внешние углы
            m = distance_transform_edt(m) > r_convex * RES
            m = m | (distance_transform_edt(~m) <= r_convex * RES)
        self.mask = m

    def finish(self):
        di = distance_transform_edt(self.mask)
        do = distance_transform_edt(~self.mask)
        self.sdf = np.where(self.mask, di - 0.5, -(do - 0.5)) / RES
        gy, gx = np.gradient(self.sdf)
        self.gx, self.gy = gx, gy

    def sample(self, arr, X, Y):
        fx = (X - self.x0) * RES - 0.5
        fy = (Y - self.y0) * RES - 0.5
        ix, iy = np.floor(fx).astype(int), np.floor(fy).astype(int)
        tx, ty = fx - ix, fy - iy
        ix = np.clip(ix, 0, arr.shape[1] - 2)
        iy = np.clip(iy, 0, arr.shape[0] - 2)
        return ((arr[iy, ix] * (1 - tx) + arr[iy, ix + 1] * tx) * (1 - ty)
                + (arr[iy + 1, ix] * (1 - tx) + arr[iy + 1, ix + 1] * tx) * ty)


# Пиксель тайла → смещение в клетках от центра клетки (раскладка Godot DIAMOND_DOWN:
# +x — вправо-вниз (32, 16), +y — влево-вниз (−32, 16)).
_py, _px = np.mgrid[0:TH, 0:TW]
_sx = _px + 0.5 - TW / 2
_sy = _py + 0.5 - TH / 2
DX = (_sx / 32 + _sy / 16) / 2
DY = (_sy / 16 - _sx / 32) / 2
INSIDE = (np.abs(DX) < 0.5) & (np.abs(DY) < 0.5)

_rng = np.random.default_rng(3)
CURB_NOISE = _rng.random((3, 12))
PAINT_NOISE = _rng.random((8, 24))
ASPHALT_PREVIEW = None


def render_cell(field, cx, cy):
    X, Y = cx + DX, cy + DY
    d = field.sample(field.sdf, X, Y)
    nx = field.sample(field.gx, X, Y)
    ny = field.sample(field.gy, X, Y)
    nl = np.hypot(nx, ny) + 1e-9
    nx, ny = nx / nl, ny / nl
    img = np.zeros((TH, TW, 4), np.uint8)
    rgb = np.zeros((TH, TW, 3))
    a = np.zeros((TH, TW))

    asph = d >= C_GUTTER
    rgb[asph] = ASPHALT_PREVIEW[asph]
    a[asph] = ASPHALT_FLAG

    gut = (d >= C_CURB) & (d < C_GUTTER)
    rgb[gut] = GUTTER_RGB
    a[gut] = 255

    curb = (d >= C_EDGE) & (d < C_CURB)
    # координата вдоль бордюра: камни по одной клетке, стыки на границах клеток
    s = np.where(np.abs(ny) > np.abs(nx), X, Y)
    f = np.mod(s + 0.5, 1.0)
    straight = np.maximum(np.abs(nx), np.abs(ny)) > 0.97
    joint = straight & (np.minimum(f, 1 - f) < 0.022)
    si = np.clip((f * 12).astype(int), 0, 11)
    di = np.clip(((d - C_EDGE) / (C_CURB - C_EDGE) * 3).astype(int), 0, 2)
    shade = 0.9 + 0.18 * CURB_NOISE[di, si]
    shade = np.where(d < C_EDGE + 0.04, shade * 1.08, shade)        # светлая кромка
    crgb = np.clip(CURB_RGB[None, None, :] * shade[..., None], 0, 255)
    crgb = np.where(joint[..., None], JOINT_RGB[None, None, :], crgb)
    rgb[curb] = crgb[curb]
    a[curb] = 255

    edge = (d >= 0) & (d < C_EDGE)
    rgb[edge] = EDGE_RGB
    a[edge] = 255

    img[..., :3] = np.round(rgb).astype(np.uint8)
    img[..., 3] = a.astype(np.uint8)
    img[~INSIDE] = 0
    return img


def classify(img):
    """'empty', 'full' или 'partial'."""
    al = img[..., 3][INSIDE]
    if (al == 0).all():
        return "empty"
    if (al == ASPHALT_FLAG).all():
        return "full"
    return "partial"


# ---------------------------------------------------------------- наборы тайлов
CORNERS = {"top": (-0.5, -0.5), "right": (0.5, -0.5), "bottom": (0.5, 0.5), "left": (-0.5, 0.5)}
CORNER_BITS = [("top", 1), ("right", 2), ("bottom", 4), ("left", 8)]


def combo_tile(bits):
    """Тайл автотайлинга: асфальт в отмеченных углах клетки, края продолжаются прямо за пределы."""
    f = Field(-6, -6, 12, 12)
    on = {name: bool(bits & b) for name, b in CORNER_BITS}
    # вершина (vx, vy) — угол клетки; за пределами 2×2 значения продолжаются (как у бесконечной прямой)
    for vx in np.arange(-5.5, 6.0, 1.0):
        for vy in np.arange(-5.5, 6.0, 1.0):
            cx, cy = (0.5 if vx > 0 else -0.5), (0.5 if vy > 0 else -0.5)
            name = [n for n, c in CORNERS.items() if c == (cx, cy)][0]
            if on[name]:
                f.add_rect(vx - 0.5, vx + 0.5, vy - 0.5, vy + 0.5)
    f.round(TERRAIN_ROUND, TERRAIN_ROUND)
    f.finish()
    return render_cell(f, 0, 0)


def canonical_corner_tiles():
    """Тайлы больших скруглений: внутренний угол (перекрёсток) и внешний угол (поворот), 4 поворота каждого."""
    tiles = []
    for kind in ("concave", "convex"):
        for sxg in (1, -1):
            for syg in (1, -1):
                f = Field(-14, -14, 28, 28)
                if kind == "concave":       # асфальт везде, кроме четверти (sxg*x > 0 и syg*y > 0)
                    f.add_rect(-99, 99, -99, 99)
                    xa, xb = (0, 99) if sxg > 0 else (-99, 0)
                    ya, yb = (0, 99) if syg > 0 else (-99, 0)
                    f.mask &= ~((f.GX > xa) & (f.GX < xb) & (f.GY > ya) & (f.GY < yb))
                else:                        # асфальт только в четверти
                    xa, xb = (0, 99) if sxg > 0 else (-99, 0)
                    ya, yb = (0, 99) if syg > 0 else (-99, 0)
                    f.add_rect(xa, xb, ya, yb)
                f.round(R_CONCAVE, R_CONVEX)
                f.finish()
                for cy in range(-9, 10):
                    for cx in range(-9, 10):
                        img = render_cell(f, cx, cy)
                        if classify(img) == "partial":
                            tiles.append(img)
    return tiles


def marking_tiles():
    """Разметка: 0 — пунктир вдоль оси x, 1 — вдоль y, 2 — полоса зебры вдоль x, 3 — вдоль y."""
    out = []
    for kind, half in (("dash", 0.075), ("zebra", 0.4)):
        for axis in ("x", "y"):
            across = DY if axis == "x" else DX
            along = DX if axis == "x" else DY
            m = INSIDE & (np.abs(across) < half)
            ia = np.clip(((along + 0.5) * 24).astype(int), 0, 23)
            ic = np.clip(((across + half) / (2 * half) * 8).astype(int), 0, 7)
            wear = PAINT_NOISE[ic, ia]
            img = np.zeros((TH, TW, 4), np.uint8)
            img[..., :3] = np.clip(PAINT_RGB * (0.92 + 0.1 * wear[..., None]), 0, 255).astype(np.uint8)
            alpha = np.where(wear < 0.16, 0, np.where(wear < 0.3, 150, 225))
            img[..., 3] = np.where(m, alpha, 0).astype(np.uint8)
            out.append(img)
    return out


# ---------------------------------------------------------------- уровень 01
# План в координатах схемы уровня: u — вправо по схеме (на экране вправо-вверх),
# v — вниз по схеме (на экране вправо-вниз). Границы — по центрам клеток.
# Перевод в сетку Godot: x = v, y = 159 − u.
LEVEL_W_U, LEVEL_H_V = 160, 120
MAIN, SIDE = 10, 8
LEVEL_RECTS = {
    # имя: (u0, u1, v0, v1)
    "T_main_top":      (-4, 164, 26, 26 + MAIN),   # главная улица от остановки (въезд слева, выезд справа)
    "bus_bay":         (8, 42, 20, 26),            # автобусный карман: 34 × 6 клеток (≈ 21 × 3,7 м)
    "R_main_upper":    (94, 94 + MAIN, 30, 74),     # главная вниз от верхней улицы
    "R_main_jog":      (94, 124, 64, 74),          # сдвиг главной дороги вправо
    "R_main_lower":    (114, 114 + MAIN, 64, 124),  # главная вниз к дому героя (выезд снизу)
    "L_side":          (36, 36 + SIDE, 30, 110),    # левая второстепенная
    "M_side":          (36, 94, 66, 66 + SIDE),     # средняя второстепенная
    "B_side":          (36, 114, 102, 102 + SIDE),  # нижняя второстепенная
}
# Осевая пунктирная линия: (дорога, ось вдоль, координата оси, от, до)
CENTER_LINES = [
    ("T_main_top", "u", 31, 0, 159),
    ("R_main_upper", "v", 99, 36, 64),
    ("R_main_lower", "v", 119, 74, 119),
]
# Зебры: (направление движения по дороге, диапазон вдоль, диапазон поперёк)
ZEBRAS = [
    ("u", (50, 54), (27, 35)),      # через верхнюю улицу справа от левой
    ("v", (54, 58), (95, 103)),     # через главную над средней улицей
    ("u", (48, 52), (67, 73)),      # через среднюю у левой
    ("u", (100, 104), (103, 109)),  # через нижнюю у главной
]


def uv_to_grid(u, v):
    return v, LEVEL_W_U - 1 - u


def build_level(atlas_index, extras):
    f = Field(-3, -3, LEVEL_H_V + 6, LEVEL_W_U + 6)
    for (u0, u1, v0, v1) in LEVEL_RECTS.values():
        xa, xb = v0, v1
        ya, yb = LEVEL_W_U - 1 - u1, LEVEL_W_U - 1 - u0
        f.add_rect(xa, xb, ya, yb)
    f.round(R_CONCAVE, R_CONVEX)
    f.finish()
    road = []
    for gx in range(LEVEL_H_V):
        for gy in range(LEVEL_W_U):
            img = render_cell(f, gx, gy)
            c = classify(img)
            if c == "empty":
                continue
            key = img.tobytes()
            if key not in atlas_index:
                atlas_index[key] = None
                extras.append(img)
            road.append((gx, gy, key))

    # разметка
    full = {(gx, gy) for gx, gy, k in road if atlas_index[k] == "FULL"}
    marks = {}
    zebra_cells = set()
    for along, (a0, a1), (c0, c1) in ZEBRAS:
        for a in range(a0, a1 + 1):
            for c in range(c0, c1 + 1):
                u, v = (a, c) if along == "u" else (c, a)
                g = uv_to_grid(u, v)
                zebra_cells.add(g)
                if (c - c0) % 2 == 0 and g in full:
                    # полосы параллельны движению: дорога вдоль u = вдоль оси y Godot
                    marks[g] = 3 if along == "u" else 2
    for name, along, coord, a0, a1 in CENTER_LINES:
        for a in range(a0, a1 + 1):
            if a % 8 >= 3:
                continue
            u, v = (a, coord) if along == "u" else (coord, a)
            g = uv_to_grid(u, v)
            # пропускаем перекрёстки (рядом с чужими дорогами) и зебры
            near_other = False
            for other, (u0, u1, v0, v1) in LEVEL_RECTS.items():
                if other == name or (name.startswith("R_main") and other.startswith("R_main")):
                    continue
                if other == "bus_bay":
                    continue
                if u0 - 8 <= u <= u1 + 8 and v0 - 8 <= v <= v1 + 8:
                    near_other = True
            if near_other or any(abs(g[0] - z[0]) + abs(g[1] - z[1]) <= 3 for z in zebra_cells):
                continue
            if g in full:
                marks[g] = 1 if along == "u" else 0
    return road, marks


# ---------------------------------------------------------------- main
def main():
    global ASPHALT_PREVIEW
    want_level = "--level" in sys.argv
    os.makedirs(TOOL_OUT, exist_ok=True)

    asphalt = build_asphalt()
    Image.fromarray(asphalt).save(os.path.join(OUT_DIR, "asphalt-v001.png"))
    ASPHALT_PREVIEW = asphalt[:TH, :TW].astype(float)

    tiles = []          # (img, info)
    atlas_index = {}
    for bits in range(1, 16):
        img = combo_tile(bits)
        info = {"bits": bits}
        if bits == 15:
            atlas_index[img.tobytes()] = "FULL"
        else:
            atlas_index.setdefault(img.tobytes(), len(tiles))
        tiles.append((img, info))
    n_combo = len(tiles)
    for img in canonical_corner_tiles():
        k = img.tobytes()
        if k in atlas_index:
            continue
        atlas_index[k] = len(tiles)
        tiles.append((img, {"kind": "corner"}))
    n_corner = len(tiles) - n_combo

    level = None
    if want_level:
        extras = []
        road, marks = build_level(atlas_index, extras)
        for img in extras:
            atlas_index[img.tobytes()] = len(tiles)
            tiles.append((img, {"kind": "level01"}))
        level = (road, marks)
        print(f"особых тайлов уровня: {len(extras)}")

    # раскладка атласа: ряд 0 — автотайлинг (столбец = битовая маска углов), дальше по 16 в ряд
    coords = []
    for i, (img, info) in enumerate(tiles):
        if i < n_combo:
            coords.append((info["bits"], 0))
        else:
            j = i - n_combo
            coords.append((j % ATLAS_COLS, 1 + j // ATLAS_COLS))
    rows = 1 + max(c[1] for c in coords)
    atlas = np.zeros((rows * TH, ATLAS_COLS * TW, 4), np.uint8)
    meta = []
    for (img, info), (cx, cy) in zip(tiles, coords):
        atlas[cy * TH:(cy + 1) * TH, cx * TW:(cx + 1) * TW] = img
        meta.append({"x": cx, "y": cy, **info})
    Image.fromarray(atlas).save(os.path.join(OUT_DIR, "road-tiles-v001.png"))

    marks_img = np.concatenate(marking_tiles(), axis=1)
    Image.fromarray(marks_img).save(os.path.join(OUT_DIR, "road-markings-v001.png"))

    with open(os.path.join(TOOL_OUT, "road_tiles.json"), "w", encoding="utf-8") as fp:
        json.dump({"tiles": meta}, fp, ensure_ascii=False)
    print(f"тайлов: автотайлинг {n_combo}, скругления {n_corner}, всего {len(tiles)}; атлас {atlas.shape[1]}×{atlas.shape[0]}")

    if level:
        road, marks = level
        key_to_coord = {}
        for (img, info), c in zip(tiles, coords):
            key_to_coord[img.tobytes()] = c
        cells = []
        for gx, gy, k in road:
            cx, cy = key_to_coord[k]
            cells.append([gx, gy, cx, cy])
        mk = [[g[0], g[1], t, 0] for g, t in marks.items()]
        start_u, start_v = 24, 22
        sx, sy = uv_to_grid(start_u, start_v)
        with open(os.path.join(TOOL_OUT, "level01_cells.json"), "w", encoding="utf-8") as fp:
            json.dump({"road": cells, "marks": mk, "player_start_cell": [sx, sy],
                       "size_cells": [LEVEL_H_V, LEVEL_W_U]}, fp)
        print(f"клеток дороги: {len(cells)}, разметки: {len(mk)}")


if __name__ == "__main__":
    main()
