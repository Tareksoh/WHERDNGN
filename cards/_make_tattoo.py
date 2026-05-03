"""
Generate the 'tattoo' card theme by rasterizing the user-supplied SVG
deck (extracted into cards/tattoo/_src/) and saving as TGAs at the
addon's native 128×192 size.

Inputs:  cards/tattoo/_src/{7C,7D,...,AS,BACK}.svg
Outputs: cards/tattoo/{7C,7D,...,AS,back}.tga (32 cards + back)

The SVGs are rendered via resvg_py (Rust-based; no system cairo
required). Source aspect 5:7 (750×1050) is squished slightly to fit
the addon's 2:3 target — same compromise the existing decks make.

Run:
    python cards/_make_tattoo.py
"""

import os
import sys
from io import BytesIO
from PIL import Image
import resvg_py

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC  = os.path.join(ROOT, "tattoo", "_src")
DST  = os.path.join(ROOT, "tattoo")

W, H = 128, 192


def src_to_dst_name(src_name):
    """Map source SVG filename to our 2-char addon convention.
       10X.svg  -> TX.tga    (we use 'T' for ten internally)
       BACK.svg -> back.tga
       <RR><S>.svg -> <RR><S>.tga otherwise (verbatim)"""
    base, ext = os.path.splitext(src_name)
    if base.upper() == "BACK":
        return "back.tga"
    if base.startswith("10"):
        return "T" + base[2:] + ".tga"
    return base + ".tga"


def render_one(src_path, dst_path):
    with open(src_path, "rb") as f:
        svg_text = f.read().decode("utf-8")
    png_bytes = resvg_py.svg_to_bytes(svg_string=svg_text)
    im = Image.open(BytesIO(bytes(png_bytes))).convert("RGBA")
    # Resize to addon's native 128×192. Source aspect 5:7 vs target
    # 2:3 → ~7% horizontal squish. LANCZOS for clean downsample.
    im = im.resize((W, H), Image.LANCZOS)
    im.save(dst_path, format="TGA", compression=None)


def main():
    if not os.path.isdir(SRC):
        print("error: {} not found".format(SRC), file=sys.stderr)
        sys.exit(2)

    written = 0
    for name in sorted(os.listdir(SRC)):
        if not name.lower().endswith(".svg"):
            continue
        out = src_to_dst_name(name)
        src_path = os.path.join(SRC, name)
        dst_path = os.path.join(DST, out)
        render_one(src_path, dst_path)
        written += 1
        print("  {} -> {}".format(name, out))
    print("Wrote {} TGAs to {}".format(written, DST))


if __name__ == "__main__":
    main()
