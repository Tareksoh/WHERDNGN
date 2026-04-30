"""
PNG -> TGA card conversion for WHEREDNGN.

Source: hayeah/playing-cards-assets (PNG, ~222x323).
Target: 128x192 TGA RGBA, written to cards/.

Naming output: <rank><suit>.tga where rank is one of 7,8,9,T,J,Q,K,A and
suit is one of S,H,D,C. Plus back.tga.  This matches the addon's internal
card-id convention (e.g. "AS" = Ace of Spades).
"""
import os
from PIL import Image

SRC_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_src")
DST_DIR = os.path.dirname(os.path.abspath(__file__))

RANK_NAME = {
    "7": "7", "8": "8", "9": "9", "T": "10",
    "J": "jack", "Q": "queen", "K": "king", "A": "ace",
}
SUIT_NAME = {"S": "spades", "H": "hearts", "D": "diamonds", "C": "clubs"}

TARGET_SIZE = (128, 192)
# How much transparent margin to leave around each card so the rounded
# corners don't clip against the rectangular UI backdrop. ~4px on each
# side leaves the card image at roughly 120x180.
PADDING = 4


def convert(src_path, dst_path):
    img = Image.open(src_path).convert("RGBA")
    # Preserve the source aspect ratio. Fit into (TARGET - 2*PADDING),
    # then center-paste onto a transparent TARGET-sized canvas.
    inner_w = TARGET_SIZE[0] - 2 * PADDING
    inner_h = TARGET_SIZE[1] - 2 * PADDING
    src_w, src_h = img.size
    scale = min(inner_w / src_w, inner_h / src_h)
    new_w, new_h = int(round(src_w * scale)), int(round(src_h * scale))
    resized = img.resize((new_w, new_h), Image.LANCZOS)
    canvas = Image.new("RGBA", TARGET_SIZE, (0, 0, 0, 0))
    canvas.paste(
        resized,
        ((TARGET_SIZE[0] - new_w) // 2, (TARGET_SIZE[1] - new_h) // 2),
        resized,
    )
    # WoW TGA loader handles 32-bit RGBA uncompressed cleanly. RLE
    # compression sometimes confuses older parsers; play it safe.
    canvas.save(dst_path, format="TGA", compression=None)


def main():
    converted = 0
    for r, rname in RANK_NAME.items():
        for s, sname in SUIT_NAME.items():
            src = os.path.join(SRC_DIR, f"{rname}_of_{sname}.png")
            dst = os.path.join(DST_DIR, f"{r}{s}.tga")
            convert(src, dst)
            converted += 1
    # Card back.
    convert(
        os.path.join(SRC_DIR, "back.png"),
        os.path.join(DST_DIR, "back.tga"),
    )
    converted += 1
    print(f"Converted {converted} files to {DST_DIR}")


if __name__ == "__main__":
    main()
