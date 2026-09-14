#!/usr/bin/env python3
"""Generate the does-gpt-cheat Codex pet ("Inspector Astra") with pure Python — no PIL needed.

Output (Codex pet v2 contract, see the bundled hatch-pet skill):
  plugin/assets/pet/spritesheet.png   1536x2288 RGBA, 8 columns x 11 rows of 192x208 cells
  plugin/assets/pet/pet.json          manifest with spriteVersionNumber 2
  plugin/assets/logo.png              the idle frame, used as the plugin logo

Rows: 0 idle(6) 1 running-right(8) 2 running-left(8) 3 waving(4) 4 jumping(5) 5 failed(8) 6 waiting(6)
      7 running/working(6) 8 review(6) 9-10 sixteen clockwise look directions (000 = up).
"""
import json
import math
import os
import struct
import sys
import zlib

CELL_W, CELL_H, COLS, ROWS = 192, 208, 8, 11
LW, LH, SCALE = 24, 26, 8  # logical pixels per cell; 24*8 = 192, 26*8 = 208

OUT = (52, 38, 24, 255)
BODY = (245, 200, 66, 255)
BODY_SH = (214, 166, 40, 255)
EYE_W = (255, 255, 255, 255)
PUPIL = (30, 30, 30, 255)
CHEEK = (240, 140, 110, 255)
CAP = (43, 58, 103, 255)
CAP_BAND = (229, 72, 77, 255)
RING = (120, 125, 135, 255)
LENS = (170, 215, 255, 190)
HANDLE = (110, 70, 35, 255)
GREEN = (60, 180, 110, 255)
BLUE = (70, 120, 220, 255)
FOOT = (52, 38, 24, 255)
CLEAR = (0, 0, 0, 0)


class Canvas:
    def __init__(self):
        self.px = [[CLEAR] * LW for _ in range(LH)]

    def put(self, x, y, c):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < LW and 0 <= y < LH:
            self.px[y][x] = c

    def ellipse(self, cx, cy, rx, ry, c):
        for y in range(int(cy - ry - 1), int(cy + ry + 2)):
            for x in range(int(cx - rx - 1), int(cx + rx + 2)):
                if rx <= 0 or ry <= 0:
                    continue
                if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0:
                    self.put(x, y, c)

    def disk(self, cx, cy, r, c):
        self.ellipse(cx, cy, r, r, c)

    def rect(self, x0, y0, x1, y1, c):
        for y in range(int(min(y0, y1)), int(max(y0, y1)) + 1):
            for x in range(int(min(x0, x1)), int(max(x0, x1)) + 1):
                self.put(x, y, c)

    def line(self, x0, y0, x1, y1, c, thick=1):
        x0, y0, x1, y1 = int(round(x0)), int(round(y0)), int(round(x1)), int(round(y1))
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
        err = dx + dy
        while True:
            for t in range(thick):
                self.put(x0 + (t if dx < -dy else 0), y0 + (t if dx >= -dy else 0), c)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def mirror(self):
        self.px = [row[::-1] for row in self.px]


def draw_pet(cv, dx=0, dy=0, sx=1.0, sy=1.0, eyes="open", pupil=(0, 0), mouth="smile", arms=("down", "down"),
             legs=None, acc=None, acc_dx=0, acc_dy=0, cap=True, mirror=False):
    cx, cy = 12 + dx, 15 + dy
    rx, ry = 7 * sx, 6.5 * sy
    # feet
    if legs is None:
        cv.ellipse(cx - 3, cy + ry, 2, 1, FOOT)
        cv.ellipse(cx + 3, cy + ry, 2, 1, FOOT)
    else:  # running cadence
        ph = legs % 4
        lift = [0, -1, 0, 1][ph]
        cv.ellipse(cx - 3, cy + ry - lift, 2, 1, FOOT)
        cv.ellipse(cx + 3, cy + ry + lift, 2, 1, FOOT)
    # arms
    for side, pose in zip((-1, 1), arms):
        ax = cx + side * (rx - 0.5)
        ay = cy + 0.5
        if pose == "down":
            ex, ey = ax + side * 1.5, ay + 3
        elif pose == "out":
            ex, ey = ax + side * 3, ay
        elif pose == "up1":
            ex, ey = ax + side * 2.5, ay - 3.5
        elif pose == "up2":
            ex, ey = ax + side * 1.5, ay - 4.5
        elif pose.startswith("swing"):
            k = int(pose[-1]) % 4
            ang = [-0.9, 0.0, 0.9, 0.0][k] * side
            ex, ey = ax + side * 2.5 * math.cos(ang) , ay + 2.5 * math.sin(ang) + 1
        else:
            ex, ey = ax + side * 1.5, ay + 3
        cv.line(ax, ay, ex, ey, OUT, thick=2)
    # body with outline + shade
    cv.ellipse(cx, cy, rx + 1, ry + 1, OUT)
    cv.ellipse(cx, cy, rx, ry, BODY)
    cv.ellipse(cx, cy + 3, rx - 1.5, ry - 3.5, BODY_SH)
    cv.ellipse(cx, cy - 1, rx - 1, ry - 2.5, BODY)
    # cheeks
    cv.put(cx - 4, cy + 1, CHEEK)
    cv.put(cx + 4, cy + 1, CHEEK)
    # eyes
    for side in (-1, 1):
        ex, ey = cx + side * 3, cy - 1
        if eyes == "blink":
            cv.line(ex - 1, ey, ex + 1, ey, PUPIL)
        elif eyes == "sad":
            cv.ellipse(ex, ey, 1.4, 1.4, EYE_W)
            cv.put(ex + pupil[0], ey + 1, PUPIL)
            cv.line(ex - 1, ey - 1, ex + 1, ey - 1, OUT)
        elif eyes == "wide":
            cv.ellipse(ex, ey, 1.9, 2.1, EYE_W)
            cv.put(ex + pupil[0], ey + pupil[1], PUPIL)
        else:
            cv.ellipse(ex, ey, 1.4, 1.6, EYE_W)
            cv.put(ex + pupil[0], ey + pupil[1], PUPIL)
    # mouth
    my = cy + 3
    if mouth == "smile":
        cv.put(cx - 1, my, OUT)
        cv.put(cx, my + 1, OUT)
        cv.put(cx + 1, my, OUT)
    elif mouth == "flat":
        cv.line(cx - 1, my, cx + 1, my, OUT)
    elif mouth == "frown":
        cv.put(cx - 1, my + 1, OUT)
        cv.put(cx, my, OUT)
        cv.put(cx + 1, my + 1, OUT)
    elif mouth == "o":
        cv.ellipse(cx, my, 1, 1, OUT)
    # detective cap
    if cap:
        top = cy - ry
        cv.ellipse(cx, top + 0.5, rx - 0.5, 2.2, OUT)
        cv.ellipse(cx, top + 0.5, rx - 1.5, 1.6, CAP)
        cv.line(cx - rx + 1, top + 2, cx + rx - 1, top + 2, CAP_BAND)
        cv.rect(cx - rx + 2, top + 3, cx + rx + 1, top + 3, OUT)  # brim
    # accessories
    if acc and "magnifier" in acc:
        gx, gy = cx + rx + 2 + acc_dx, cy - 2 + acc_dy
        cv.disk(gx, gy, 2.6, RING)
        cv.disk(gx, gy, 1.7, LENS)
        cv.line(gx + 2, gy + 2, gx + 4, gy + 4, HANDLE, thick=2)
    if acc and "question" in acc:
        qx, qy = cx + 6, cy - ry - 5 + acc_dy
        cv.line(qx - 1, qy, qx + 1, qy, BLUE)
        cv.put(qx + 2, qy + 1, BLUE)
        cv.put(qx + 1, qy + 2, BLUE)
        cv.put(qx, qy + 3, BLUE)
        cv.put(qx, qy + 5, BLUE)
    if acc and "check" in acc:
        kx, ky = cx + 7, cy - ry - 2
        cv.line(kx - 2, ky, kx, ky + 2, GREEN, thick=2)
        cv.line(kx, ky + 2, kx + 3, ky - 2, GREEN, thick=2)
    if acc and "sweat" in acc:
        cv.put(cx + rx + 1, cy - 3 + acc_dy, BLUE)
        cv.put(cx + rx + 1, cy - 2 + acc_dy, BLUE)
    if acc and "glasses" in acc:
        for side in (-1, 1):
            ex, ey = cx + side * 3, cy - 1
            for a in range(0, 360, 20):
                cv.put(ex + 2.3 * math.cos(math.radians(a)), ey + 2.3 * math.sin(math.radians(a)), OUT)
        cv.line(cx - 1, cy - 1, cx + 1, cy - 1, OUT)
    if mirror:
        cv.mirror()


def frames():
    rows = {}
    rows[0] = [dict(dy=d, sy=s, eyes=e) for d, s, e in
               [(0, 1.0, "open"), (0, 1.0, "open"), (-1, 1.03, "open"), (-1, 1.03, "blink"), (0, 1.0, "open"), (0, 1.0, "open")]]
    run = [dict(dx=1, dy=[0, -1, -1, 0, 0, -1, -1, 0][i], legs=i, arms=(f"swing{i % 4}", f"swing{(i + 2) % 4}"),
                pupil=(1, 0), sx=1.05, sy=0.96) for i in range(8)]
    rows[1] = run
    rows[2] = [dict(f, mirror=True) for f in run]
    rows[3] = [dict(arms=("down", "up1")), dict(arms=("down", "up2")), dict(arms=("down", "up1")), dict(arms=("down", "down"))]
    rows[4] = [dict(sy=0.9, sx=1.08, dy=1), dict(dy=-3, sy=1.08, sx=0.95, eyes="wide"),
               dict(dy=-6, arms=("up1", "up1"), eyes="wide", mouth="o"), dict(dy=-3, sy=1.05), dict(dy=1, sy=0.92, sx=1.06)]
    rows[5] = [dict(dy=1, eyes="sad", mouth="frown", acc="sweat", acc_dy=[0, 1, 2, 3, 0, 1, 2, 3][i],
                    dx=[0, -1, 1, -1, 1, 0, 0, 0][i]) for i in range(8)]
    rows[6] = [dict(eyes="wide", mouth="o", acc="question", acc_dy=[0, -1, -1, 0, 0, 1][i],
                    pupil=[(0, -1), (0, -1), (1, -1), (1, -1), (-1, -1), (-1, -1)][i]) for i in range(6)]
    rows[7] = [dict(acc="magnifier", acc_dx=[0, 1, 2, 2, 1, 0][i], acc_dy=[0, 0, -1, -1, 0, 0][i],
                    pupil=[(1, 1), (1, 1), (1, 1), (0, 1), (-1, 1), (-1, 1)][i], dy=[0, 0, -1, -1, 0, 0][i],
                    arms=("down", "out")) for i in range(6)]
    rows[8] = [dict(acc="glasses", pupil=(0, 1)), dict(acc="glasses", pupil=(1, 1)), dict(acc="glasses", pupil=(-1, 1)),
               dict(acc="glasses", pupil=(0, 0)), dict(acc="glasses check", mouth="smile"), dict(acc="glasses check", mouth="smile", dy=-1)]
    look = []
    for k in range(16):
        th = math.radians(k * 22.5)
        look.append(dict(pupil=(int(round(math.sin(th) * 1.4)), int(round(-math.cos(th) * 1.4))),
                         dx=int(round(math.sin(th))), dy=int(round(-math.cos(th) * 0.8))))
    rows[9], rows[10] = look[:8], look[8:]
    return rows


def write_png(path, width, height, rows):
    raw = b"".join(b"\x00" + bytes(r) for r in rows)

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)


def render_cell(frame):
    cv = Canvas()
    draw_pet(cv, **frame)
    return cv


def cell_rows(cv):
    """Scale a logical canvas to CELL_W x CELL_H rows of RGBA bytes."""
    out = []
    for ly in range(LH):
        row = bytearray()
        for lx in range(LW):
            row += bytes(cv.px[ly][lx]) * SCALE
        for _ in range(SCALE):
            out.append(bytes(row))
    return out


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    pet_dir = os.path.join(root, "plugin", "assets", "pet")
    atlas = [bytearray(COLS * CELL_W * 4) for _ in range(ROWS * CELL_H)]
    table = frames()
    for r in range(ROWS):
        for c, frame in enumerate(table[r]):
            rows = cell_rows(render_cell(frame))
            for i, row in enumerate(rows):
                y = r * CELL_H + i
                x0 = c * CELL_W * 4
                atlas[y][x0:x0 + CELL_W * 4] = row
    write_png(os.path.join(pet_dir, "spritesheet.png"), COLS * CELL_W, ROWS * CELL_H, atlas)
    with open(os.path.join(pet_dir, "pet.json"), "w", encoding="utf-8") as f:
        json.dump({
            "id": "does-gpt-cheat",
            "displayName": "Inspector Astra",
            "description": "Sniffs out silent model downgrades and congratulates you when it finds one.",
            "spriteVersionNumber": 2,
            "spritesheetPath": "spritesheet.png",
        }, f, indent=2)
        f.write("\n")
    logo = cell_rows(render_cell(dict(acc="magnifier", arms=("down", "out"), pupil=(1, 1))))
    write_png(os.path.join(root, "plugin", "assets", "logo.png"), CELL_W, CELL_H, logo)
    print(f"wrote {pet_dir}/spritesheet.png ({COLS * CELL_W}x{ROWS * CELL_H}), pet.json and plugin/assets/logo.png")


if __name__ == "__main__":
    sys.exit(main())
