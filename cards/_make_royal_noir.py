"""
Generate the 'royal_noir' card theme by rasterizing the user-supplied
SVG deck (extracted into cards/royal_noir/_src/) and saving as TGAs at
the addon's native 128×192 size.

Inputs:  cards/royal_noir/_src/{7C..AS,BACK}.svg  (33 files)
Outputs: cards/royal_noir/{7C..AS,back}.tga       (32 cards + back)

The SVGs are rendered via resvg_py (Rust-based; no system cairo
required). Source aspect 5:7 (750×1050) is squished slightly to fit
the addon's 2:3 target — same compromise the tattoo pipeline makes.

Run:
    python cards/_make_royal_noir.py
"""

import os
import sys
from io import BytesIO
from PIL import Image
import resvg_py

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC  = os.path.join(ROOT, "royal_noir", "_src")
DST  = os.path.join(ROOT, "royal_noir")

W, H = 128, 192


def src_to_dst_name(src_name):
    """10X.svg → TX.tga, BACK.svg → back.tga, otherwise verbatim."""
    base, _ext = os.path.splitext(src_name)
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
        src_path = os.path.join(SRC, name)
        dst_path = os.path.join(DST, src_to_dst_name(name))
        render_one(src_path, dst_path)
        written += 1
        print("  {} -> {}".format(name, src_to_dst_name(name)))
    print("Wrote {} TGAs to {}".format(written, DST))


if __name__ == "__main__":
    main()
