"""
Generate cards/felt_vintage.tga — a deep saddle-brown noise felt that
pairs naturally with the tattoo card deck (cream cards on warm leather)
but works as an independent FELT_THEMES entry the user can mix with
any card style.

Same tile geometry as the classic + burgundy felts (128×128, tileable
under the SetHorizTile / SetVertTile path) — just a different base
color and a touch more noise amplitude for a leathery rather than
woven feel.

Run:
    python cards/_make_felt_vintage.py
"""

import os
import random
from PIL import Image, ImageFilter

DST = os.path.dirname(os.path.abspath(__file__))


def main():
    Wf = Hf = 128
    base = (40, 24, 16, 255)        # deep saddle brown
    img = Image.new("RGBA", (Wf, Hf), base)
    px = img.load()
    rng = random.Random(2026)
    for y in range(Hf):
        for x in range(Wf):
            n = rng.randint(-12, 12)
            r, g, b, a = px[x, y]
            px[x, y] = (
                max(0, min(255, r + n)),
                max(0, min(255, g + n)),
                max(0, min(255, b + n)),
                a,
            )
    # Slightly stronger blur than the green/burgundy felts so the
    # noise reads as worn leather rather than woven cloth.
    img = img.filter(ImageFilter.GaussianBlur(radius=0.8))
    out = os.path.join(DST, "felt_vintage.tga")
    img.save(out, format="TGA", compression=None)
    print("Wrote", out)


if __name__ == "__main__":
    main()
