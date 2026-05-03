"""
Generate the "burgundy" card theme.

Card faces and back are the public-domain SVGCards "Accessible / Horizontal"
4-color deck by Saul Spatz (https://github.com/saulspatz/SVGCards). Suit
colors match the addon's four-color-deck convention (♠ black, ♥ red,
♦ blue, ♣ green) so same-shape suits stay distinguishable.

The felt + glow are generated procedurally to match the burgundy palette.

Outputs (all under cards/burgundy/):
  <rank><suit>.tga  32 face cards (128×192, RGBA)
  back.tga          Red lattice card back (128×192) — SVGCards redBack
  felt.tga          Burgundy noise felt (128×128, tileable)
  glow.tga          Warm gold radial glow (64×64) — shared style

Run:
    python cards/_make_burgundy.py

Network: pulls 33 files from raw.githubusercontent.com on the first run.
No network access is needed in-game; the bundled TGAs are read locally.
"""

import os
import random
import urllib.request
from io import BytesIO
from PIL import Image, ImageFilter

DST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "burgundy")
os.makedirs(DST, exist_ok=True)

# Target dimensions match the existing TGAs the addon already ships.
W, H = 128, 192

# SVGCards 4-color Accessible/Horizontal deck — public domain.
SVGCARDS_BASE = (
    "https://raw.githubusercontent.com/saulspatz/SVGCards/master/"
    "Decks/Accessible/Horizontal/pngs/"
)

SUIT_NAME = { "S": "spade", "H": "heart", "D": "diamond", "C": "club" }
RANK_NAME = {
    "7": "7", "8": "8", "9": "9", "T": "10",
    "J": "Jack", "Q": "Queen", "K": "King", "A": "Ace",
}


def fetch(rel_path, retries=3):
    """Download `rel_path` under SVGCARDS_BASE, return raw bytes."""
    url = SVGCARDS_BASE + rel_path
    last_err = None
    for _ in range(retries):
        try:
            return urllib.request.urlopen(url, timeout=20).read()
        except Exception as e:
            last_err = e
    raise RuntimeError("could not fetch {}: {}".format(url, last_err))


def fetch_card_image(rank, suit):
    """Return a Pillow Image for the given card, sized to (W, H)."""
    fname = SUIT_NAME[suit] + RANK_NAME[rank] + ".png"
    raw = fetch(fname)
    im = Image.open(BytesIO(raw)).convert("RGBA")
    # SVGCards PNGs are 75×113 (close to our 128×192 aspect). Upscale
    # with LANCZOS for a clean readable result at our target size.
    return im.resize((W, H), Image.LANCZOS)


def fetch_card_back():
    """Red card back from SVGCards. Returns Image at (W, H)."""
    raw = fetch("redBack.png")
    im = Image.open(BytesIO(raw)).convert("RGBA")
    return im.resize((W, H), Image.LANCZOS)


def make_felt():
    """Tileable burgundy felt with low-amplitude noise. Same generator
    geometry as the classic theme's felt — only the base color changes."""
    Wf = Hf = 128
    base = (62, 14, 24, 255)        # deep burgundy
    img = Image.new("RGBA", (Wf, Hf), base)
    px = img.load()
    rng = random.Random(2026)
    for y in range(Hf):
        for x in range(Wf):
            n = rng.randint(-10, 10)
            r, g, b, a = px[x, y]
            px[x, y] = (
                max(0, min(255, r + n)),
                max(0, min(255, g + n)),
                max(0, min(255, b + n)),
                a,
            )
    img = img.filter(ImageFilter.GaussianBlur(radius=0.6))
    img.save(os.path.join(DST, "felt.tga"), format="TGA", compression=None)


def make_glow():
    """Warm gold radial glow — pairs equally well with green or burgundy."""
    Wg = Hg = 64
    img = Image.new("RGBA", (Wg, Hg), (0, 0, 0, 0))
    cx, cy = Wg / 2, Hg / 2
    max_r = (Wg / 2) - 1
    px = img.load()
    for y in range(Hg):
        for x in range(Wg):
            dx = (x + 0.5) - cx
            dy = (y + 0.5) - cy
            d = (dx * dx + dy * dy) ** 0.5
            t = max(0.0, 1.0 - d / max_r)
            a = int(255 * (t ** 1.6))
            if a > 0:
                px[x, y] = (255, 215, 100, a)
    img.save(os.path.join(DST, "glow.tga"), format="TGA", compression=None)


def main():
    written = 0
    for suit in ("S", "H", "D", "C"):
        for rank in ("7", "8", "9", "T", "J", "Q", "K", "A"):
            im = fetch_card_image(rank, suit)
            path = os.path.join(DST, "{}{}.tga".format(rank, suit))
            im.save(path, format="TGA", compression=None)
            written += 1
            print("  {}".format(os.path.basename(path)))

    back = fetch_card_back()
    back.save(os.path.join(DST, "back.tga"), format="TGA", compression=None)

    make_felt()
    make_glow()
    print("Wrote {} face cards + back.tga + felt.tga + glow.tga to {}"
          .format(written, DST))


if __name__ == "__main__":
    main()
