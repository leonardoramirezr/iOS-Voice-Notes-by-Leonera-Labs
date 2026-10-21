#!/usr/bin/env python3
"""Renders the 1024x1024 app icon (requires Pillow). Run locally; the PNG is committed.

Usage: scripts/make_icon.py [output.png]
"""

from __future__ import annotations

import os
import sys

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SCALE = 4
CANVAS = SIZE * SCALE
TOP_LEFT = (255, 184, 77)
BOTTOM_RIGHT = (240, 82, 96)
CARD = (255, 255, 255)
LINE = (214, 214, 222)
TITLE_LINE = (60, 60, 72)
CHECK = (240, 120, 80)
BADGE = (28, 28, 52)
MIC = (255, 255, 255)


def gradient() -> Image.Image:
    small = Image.new("RGB", (256, 256))
    pixels = small.load()
    for y in range(256):
        for x in range(256):
            t = (x + y) / 510
            pixels[x, y] = tuple(int(a + (b - a) * t) for a, b in zip(TOP_LEFT, BOTTOM_RIGHT))
    return small.resize((CANVAS, CANVAS), Image.BICUBIC)


def s(value: float) -> int:
    return int(value * SCALE)


def draw_icon() -> Image.Image:
    image = gradient().convert("RGBA")

    shadow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((s(196), s(196), s(796), s(856)), radius=s(84), fill=(80, 20, 20, 90))
    image.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(s(28))))

    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((s(184), s(168), s(784), s(828)), radius=s(84), fill=CARD)

    # Title line and list items, the first one checked.
    draw.rounded_rectangle((s(264), s(260), s(620), s(312)), radius=s(26), fill=TITLE_LINE)
    rows = [(408, True), (512, False), (616, False)]
    for top, checked in rows:
        box = (s(264), s(top), s(316), s(top + 52))
        if checked:
            draw.rounded_rectangle(box, radius=s(12), fill=CHECK)
            draw.line(
                [(s(276), s(top + 27)), (s(288), s(top + 40)), (s(306), s(top + 13))],
                fill=CARD, width=s(9), joint="curve",
            )
        else:
            draw.rounded_rectangle(box, radius=s(12), outline=LINE, width=s(7))
        draw.rounded_rectangle((s(348), s(top + 8), s(700 if top != 616 else 560), s(top + 44)), radius=s(18), fill=LINE)

    # Microphone badge.
    cx, cy, radius = 742, 760, 168
    draw.ellipse((s(cx - radius), s(cy - radius), s(cx + radius), s(cy + radius)), fill=BADGE)
    draw.rounded_rectangle((s(cx - 42), s(cy - 104), s(cx + 42), s(cy + 26)), radius=s(42), fill=MIC)
    draw.arc((s(cx - 76), s(cy - 72), s(cx + 76), s(cy + 66)), start=20, end=160, fill=MIC, width=s(16))
    draw.rounded_rectangle((s(cx - 8), s(cy + 60), s(cx + 8), s(cy + 104)), radius=s(8), fill=MIC)
    draw.rounded_rectangle((s(cx - 46), s(cy + 96), s(cx + 46), s(cy + 112)), radius=s(8), fill=MIC)

    return image.resize((SIZE, SIZE), Image.LANCZOS).convert("RGB")


def main() -> int:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    default = os.path.join(root, "App", "Resources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")
    output = sys.argv[1] if len(sys.argv) > 1 else default
    os.makedirs(os.path.dirname(output), exist_ok=True)
    draw_icon().save(output, "PNG", optimize=True)
    print(f"Wrote {output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
