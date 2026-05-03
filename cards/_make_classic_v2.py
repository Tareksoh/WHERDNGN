"""
Generate the "classic_v2" card theme.

Card faces and back come from David Bellot's SVG-cards (Wikimedia /
LGPL-2.1) via Huub de Beer's PNG mirror at
https://github.com/htdebeer/SVG-cards. We pull the 2x PNGs (~340x460)
which downscale cleanly to our 128x192 in-game card size. The back is
the matching `back-black.png` from the same set.

Suit ordering and four-color tinting match the existing burgundy/
royal_noir scripts so same-shape suits stay distinguishable. The
htdebeer set is already four-color so we leave its colors as-is.

Outputs (all under cards/classic_v2/):
  <rank><suit>.tga   32 face cards (128x192, RGBA)
  back.tga           Black-back design from the same source

Run:
    python cards/_make_classic_v2.py

Network: pulls 33 files from raw.githubusercontent.com on the first
run. No network access is needed in-game; the bundled TGAs are read
locally.
"""

import os
import urllib.request
from io import BytesIO
from PIL import Image

DST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "classic_v2")
os.makedirs(DST, exist_ok=True)

# Target dimensions match the existing TGAs the addon already ships.
W, H = 128, 192

HTDEBEER_BASE = (
    "https://raw.githubusercontent.com/htdebeer/SVG-cards/master/png/2x/"
)

SUIT_NAME = {
    "S": "spade",
    "H": "heart",
    "D": "diamond",
    "C": "club",
}

# htdebeer numbers Ace as 1, T as 10, and uses spelled-out face names.
RANK_NAME = {
    "7": "7",
    "8": "8",
    "9": "9",
    "T": "10",
    "J": "jack",
    "Q": "queen",
    "K": "king",
    "A": "1",
}


def fetch(rel_path, retries=3):
    """Download `rel_path` under HTDEBEER_BASE, return raw bytes."""
    url = HTDEBEER_BASE + rel_path
    last_err = None
    for _ in range(retries):
        try:
            return urllib.request.urlopen(url, timeout=20).read()
        except Exception as e:
            last_err = e
    raise RuntimeError("could not fetch {}: {}".format(url, last_err))


def fetch_card_image(rank, suit):
    """Return a Pillow Image for the given card, sized to (W, H)."""
    # htdebeer naming is <suit>_<rank>.png (singular suit; ace=1).
    fname = "{}_{}.png".format(SUIT_NAME[suit], RANK_NAME[rank])
    raw = fetch(fname)
    im = Image.open(BytesIO(raw)).convert("RGBA")
    # htdebeer 2x PNGs are roughly 334x468 — close to our 2:3 aspect.
    # LANCZOS gives a clean readable result at 128x192.
    return im.resize((W, H), Image.LANCZOS)


def fetch_card_back():
    """back-black.png from the same source. Returns Image at (W, H)."""
    raw = fetch("back-black.png")
    im = Image.open(BytesIO(raw)).convert("RGBA")
    return im.resize((W, H), Image.LANCZOS)


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
    print("  back.tga")

    print("Wrote {} face cards + back.tga to {}".format(written, DST))


if __name__ == "__main__":
    main()
