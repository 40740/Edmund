#!/usr/bin/env python3
"""ui-measure.py — pixel measurements off a window screenshot.

Turns "is the icon centred / is the padding balanced" into numbers. Captures
are Retina, so **2 device px = 1 point**; every command reports both.

    ui-measure.py box   <png> X0 X1 Y0 Y1     # ink bounding box in a region
    ui-measure.py runs  <png> X0 X1 Y0 Y1     # control runs + the gaps between
    ui-measure.py rows  <png> X Y0 Y1         # colour transitions down a column

Coordinates are device pixels in the PNG. Region args are inclusive-exclusive.

`box` is the workhorse: it reports the tight bounding box of "ink" (dark on
light, light on dark — pass --dark) plus its centre, which is what you compare
against a control's centre to prove an icon is or is not centred.

`runs` finds horizontal spans of control-fill colour and prints the gaps
between them — the way to check that button spacing is even without eyeballing.

`rows` dumps where colours change down a single column: use it to find a
field's bezel and focus-ring boundaries before measuring anything inside it.
"""
import sys

import numpy as np
from PIL import Image


def load(path):
    return np.array(Image.open(path).convert("RGB")).astype(int)


def ink_mask(sub, dark_mode=False):
    """Ink = clearly darker (light mode) or lighter (dark mode) than the local
    background, with blue-dominant pixels excluded so a focus ring or text
    caret is never mistaken for glyph ink."""
    lum = sub.mean(axis=2)
    bg = np.median(lum)
    not_blue = (sub[:, :, 2] - sub[:, :, 0]) < 40
    return ((lum > bg + 30) if dark_mode else (lum < bg - 30)) & not_blue


def cmd_box(png, x0, x1, y0, y1, dark_mode=False):
    a = load(png)
    m = ink_mask(a[y0:y1, x0:x1], dark_mode)
    if not m.any():
        print("no ink found in region")
        return
    rs, cs = np.where(m.any(axis=1))[0], np.where(m.any(axis=0))[0]
    top, bot, left, right = rs.min() + y0, rs.max() + y0, cs.min() + x0, cs.max() + x0
    print(f"x {left}..{right} ({(right - left + 1) / 2:.2f} pt wide)")
    print(f"y {top}..{bot} ({(bot - top + 1) / 2:.2f} pt tall)")
    print(f"centre x={(left + right) / 2:.1f} y={(top + bot) / 2:.1f} (device px)")


def cmd_runs(png, x0, x1, y0, y1):
    a = load(png)
    sub = a[y0:y1, x0:x1]
    # Control fill: mid greys, plus anything strongly blue (a checked checkbox).
    fill = (((sub[:, :, 0] > 215) & (sub[:, :, 0] < 242)) |
            ((sub[:, :, 2] - sub[:, :, 0]) > 60)).sum(axis=0)
    runs, start = [], None
    for i, v in enumerate(fill):
        on = v > 15
        if on and start is None:
            start = i
        if not on and start is not None:
            runs.append((start + x0, i - 1 + x0))
            start = None
    if start is not None:
        runs.append((start + x0, len(fill) - 1 + x0))
    runs = [r for r in runs if r[1] - r[0] > 3]
    print("runs:", runs)
    for i in range(len(runs) - 1):
        gap = runs[i + 1][0] - runs[i][1] - 1
        print(f"  gap {runs[i][1]}..{runs[i + 1][0]} = {gap} px = {gap / 2:.1f} pt")


def cmd_rows(png, x, y0, y1):
    a = load(png)
    prev = None
    for y in range(y0, y1):
        cur = tuple(a[y, x])
        if cur != prev:
            print(y, cur)
            prev = cur


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 64
    cmd, png, rest = argv[0], argv[1], [int(v) for v in argv[2:] if v != "--dark"]
    dark = "--dark" in argv
    if cmd == "box":
        cmd_box(png, *rest[:4], dark_mode=dark)
    elif cmd == "runs":
        cmd_runs(png, *rest[:4])
    elif cmd == "rows":
        cmd_rows(png, *rest[:3])
    else:
        print(__doc__)
        return 64
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
