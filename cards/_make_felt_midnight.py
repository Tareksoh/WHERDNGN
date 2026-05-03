"""
Generate cards/felt_midnight.tga — a near-black felt that pairs
naturally with the royal_noir gold-on-charcoal deck (gold cards on
deep navy/black) but works as an independent FELT_THEMES entry under
the mix-and-match system.

Base color is a slightly warm near-black (#100e16) — pure black on a
felt reads as dead/flat, so a touch of indigo + low-amplitude noise
gives it a subtle "casino velvet" feel.

Same 128×128 tileable geometry as the green/burgundy/vintage felts.

Run:
    python cards/_make_felt_midnight.py
"""

import os
import random
from PIL import Image, ImageFilter

DST = os.path.dirname(os.path.abspath(__file__))


def main():
    Wf = Hf = 128
    base = (16, 14, 22, 255)        # near-black with a hint of indigo
    img = Image.new("RGBA", (Wf, Hf), base)
    px = img.load()
    rng = random.Random(2026)
    for y in range(Hf):
        for x in range(Wf):
            n = rng.randint(-5, 5)   # tighter range than the brighter
                                     # felts so the texture stays subtle
                                     # against gold-on-black cards
            r, g, b, a = px[x, y]
            px[x, y] = (
                max(0, min(255, r + n)),
                max(0, min(255, g + n)),
                max(0, min(255, b + n)),
                a,
            )
    img = img.filter(ImageFilter.GaussianBlur(radius=0.7))
    out = os.path.join(DST, "felt_midnight.tga")
    img.save(out, format="TGA", compression=None)
    print("Wrote", out)


if __name__ == "__main__":
    main()
