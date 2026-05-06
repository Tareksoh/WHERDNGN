"""Fetch xCards face PNGs from GitHub and convert to TGA for the Ba8ala
deck (replaces royal_noir, internal key preserved per user request).

Usage: python tools/convert_xcards_to_baqala.py

Notes:
- Uses xCards @2x density (750x1050) for better source quality, downscales
  to 128x192 32bpp BGRA TGA via Pillow Lanczos.
- Saudi Baloot uses 32 cards: 7,8,9,T,J,Q,K,A x 4 suits.
- Output: C:/CLAUDE/WHEREDNGN/cards/royal_noir/<rank><suit>.tga (in-place
  replacement). The internal deck key stays "royal_noir" so existing
  WHEREDNGNDB.cardStyle entries keep working without migration; only the
  display name in UI.lua changes to "Ba8ala SET".
- Skips back.tga (preserves the existing card-back texture).
"""
import os
import sys
import urllib.request
from PIL import Image
import io

BASE_URL = "https://raw.githubusercontent.com/Xadeck/xCards/master/png/face"
DENSITY = "2x"
OUT_DIR = r"C:\CLAUDE\WHEREDNGN\cards\royal_noir"
TARGET_W, TARGET_H = 128, 192

SAUDI_RANKS = ["7", "8", "9", "T", "J", "Q", "K", "A"]
SUITS = ["S", "H", "D", "C"]


def download_png(rank, suit):
    """Fetch PNG bytes from xCards repo for a given card."""
    url = f"{BASE_URL}/{rank}{suit}@{DENSITY}.png"
    print(f"  [GET] {url}")
    req = urllib.request.Request(url, headers={"User-Agent": "WHEREDNGN-deck-converter/1.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read()


def to_tga(png_bytes, out_path):
    """Convert PNG bytes to 128x192 32bpp BGRA TGA."""
    img = Image.open(io.BytesIO(png_bytes)).convert("RGBA")
    # Lanczos preserves edge sharpness on the 5.86x downscale.
    img = img.resize((TARGET_W, TARGET_H), Image.Resampling.LANCZOS)
    img.save(out_path, format="TGA")


def main():
    if not os.path.isdir(OUT_DIR):
        print(f"ERROR: output dir not found: {OUT_DIR}")
        return 1
    print(f"Converting 32 cards from xCards @{DENSITY} to {TARGET_W}x{TARGET_H} TGA")
    print(f"Output: {OUT_DIR}")
    print()
    converted = 0
    failed = []
    for rank in SAUDI_RANKS:
        for suit in SUITS:
            card = f"{rank}{suit}"
            try:
                png = download_png(rank, suit)
                tga_path = os.path.join(OUT_DIR, f"{card}.tga")
                to_tga(png, tga_path)
                converted += 1
            except Exception as e:
                print(f"  [FAIL] {card}: {e}")
                failed.append(card)
    print()
    print(f"Done: {converted}/32 converted. Failed: {len(failed)}")
    if failed:
        print(f"  Failed cards: {failed}")
        return 2
    print("back.tga preserved (existing royal_noir back).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
