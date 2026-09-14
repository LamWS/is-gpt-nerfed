#!/usr/bin/env python3
"""Render the pet's idle frame into a 1024x1024 app icon PNG (pure Python, reuses tools/make_pet.py)."""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import make_pet  # noqa: E402

SIZE = 1024
SCALE = 36  # 24 logical px * 36 = 864, leaves a margin inside the 1024 canvas


def main():
    cv = make_pet.Canvas()
    make_pet.draw_pet(cv, acc="magnifier", arms=("down", "out"), pupil=(1, 1))
    rows = []
    margin_x = (SIZE - make_pet.LW * SCALE) // 2
    margin_y = (SIZE - make_pet.LH * SCALE) // 2
    blank = bytes(SIZE * 4)
    for y in range(SIZE):
        ly = (y - margin_y) // SCALE
        if ly < 0 or ly >= make_pet.LH:
            rows.append(blank)
            continue
        row = bytearray(margin_x * 4)
        for lx in range(make_pet.LW):
            row += bytes(cv.px[ly][lx]) * SCALE
        row += bytes((SIZE - len(row) // 4) * 4)
        rows.append(bytes(row[:SIZE * 4]))
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build", "icon_1024.png")
    make_pet.write_png(out, SIZE, SIZE, rows)
    print(out)


if __name__ == "__main__":
    main()
