"""
Generate the 'wow' card theme by resizing the user-supplied PNG deck
(extracted into cards/wow/_src/) and saving as TGAs at the addon's
native 128×192 size, plus a synthesized purple/gold back.

Inputs:  cards/wow/_src/{7C,7D,...,AS}.png  (32 face cards, 512×768)
Outputs: cards/wow/{7C,7D,...,AS,back}.tga  (32 cards + back)

The PNGs are 5:7 aspect; addon target is 2:3 — same ~7% horizontal
squish the existing decks accept. LANCZOS for clean downsample.

The zip ships no back image, so we synthesize one matching the
"Battle of Heroes" purple/gold theme: charcoal body with a diagonal
lattice in deep violet and a warm gold edge border.

Run:
    python cards/_make_wow.py
"""

import os
import sys
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC  = os.path.join(ROOT, "wow", "_src")
DST  = os.path.join(ROOT, "wow")

W, H = 128, 192


def src_to_dst_name(src_name):
    """Map source PNG filename to our 2-char addon convention.
       10X.png -> TX.tga    (we use 'T' for ten internally)
       <RR><S>.png -> <RR><S>.tga otherwise (verbatim)"""
    base, ext = os.path.splitext(src_name)
    if base.startswith("10"):
        return "T" + base[2:] + ".tga"
    return base + ".tga"


def render_one(src_path, dst_path):
    im = Image.open(src_path).convert("RGBA")
    im = im.resize((W, H), Image.LANCZOS)
    im.save(dst_path, format="TGA", compression=None)


# --- back generator ---------------------------------------------------
# Charcoal body + violet diagonal lattice + warm-gold thin border.
# Distinctive at 128x192, complements the dark/jewel-toned faces.
BG        = (16, 14, 28, 255)
LATTICE   = (78, 50, 130, 255)
GOLD      = (220, 178, 100, 255)
GOLD_HI   = (240, 210, 140, 255)
INNER_BG  = (28, 22, 50, 255)


def make_back(dst_path):
    img = Image.new("RGBA", (W, H), BG)
    draw = ImageDraw.Draw(img)

    # Diagonal lattice
    spacing = 12
    for d in range(-H, W + H, spacing):
        draw.line([(d, 0), (d + H, H)], fill=LATTICE, width=1)
        draw.line([(d, H), (d + H, 0)], fill=LATTICE, width=1)

    # Inner rectangle (slightly different shade) so the lattice has
    # a visual frame and the border isn't lost on the lattice noise.
    pad = 8
    draw.rectangle((pad, pad, W - pad - 1, H - pad - 1),
                   outline=GOLD, width=2)
    pad2 = 12
    draw.rectangle((pad2, pad2, W - pad2 - 1, H - pad2 - 1),
                   outline=GOLD_HI, width=1)

    # Outer 1-pixel gold edge to crisp up against the felt.
    draw.rectangle((0, 0, W - 1, H - 1), outline=GOLD, width=1)

    img.save(dst_path, format="TGA", compression=None)


def main():
    if not os.path.isdir(SRC):
        print("error: {} not found".format(SRC), file=sys.stderr)
        sys.exit(2)

    written = 0
    for name in sorted(os.listdir(SRC)):
        if not name.lower().endswith(".png"):
            continue
        out = src_to_dst_name(name)
        src_path = os.path.join(SRC, name)
        dst_path = os.path.join(DST, out)
        render_one(src_path, dst_path)
        written += 1
        print("  {} -> {}".format(name, out))

    # Synthesize the back (zip ships no BACK image).
    back_path = os.path.join(DST, "back.tga")
    make_back(back_path)
    print("  [synth] -> back.tga")
    written += 1

    print("Wrote {} TGAs to {}".format(written, DST))


if __name__ == "__main__":
    main()
