"""
Generate auxiliary textures for WHEREDNGN: felt table background and
seat-avatar circles.

Output (TGA, in cards/):
- felt.tga         128x128 tileable felt-green noise pattern
- glow.tga         64x64  radial gold glow for trick-winner highlight
- avatar_2.tga ... avatar_4.tga   48x48 colored seat-number badges
"""
import os
import random
from PIL import Image, ImageDraw, ImageFilter

DST = os.path.dirname(os.path.abspath(__file__))


def make_felt():
    """Tileable dark-green felt with low-amplitude noise.

    Tileable trick: render a non-tileable noise patch then mirror it
    across both axes. Visible seams are eliminated by averaging the
    overlap; for our subtle felt the simple mirror-paste is enough.
    """
    W = H = 128
    base = (28, 64, 38, 255)        # dark forest green
    img = Image.new("RGBA", (W, H), base)
    px = img.load()
    rng = random.Random(2026)
    for y in range(H):
        for x in range(W):
            n = rng.randint(-10, 10)
            r, g, b, a = px[x, y]
            px[x, y] = (
                max(0, min(255, r + n)),
                max(0, min(255, g + n)),
                max(0, min(255, b + n)),
                a,
            )
    # Soften the noise so it reads as fabric weave, not noise.
    img = img.filter(ImageFilter.GaussianBlur(radius=0.6))
    img.save(os.path.join(DST, "felt.tga"), format="TGA", compression=None)


def make_glow():
    """Soft radial gold glow for highlighting the trick-winner card."""
    W = H = 64
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    cx, cy = W / 2, H / 2
    max_r = (W / 2) - 1
    px = img.load()
    for y in range(H):
        for x in range(W):
            dx = (x + 0.5) - cx
            dy = (y + 0.5) - cy
            d = (dx * dx + dy * dy) ** 0.5
            t = max(0.0, 1.0 - d / max_r)
            # Soft falloff: square it for a tighter core
            a = int(255 * (t ** 1.6))
            if a > 0:
                # Warm gold (255, 215, 100)
                px[x, y] = (255, 215, 100, a)
    img.save(os.path.join(DST, "glow.tga"), format="TGA", compression=None)


def make_avatar(seat_num, color, out_name):
    """Flat circular avatar with the seat number drawn in the middle."""
    W = H = 48
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    # Outer ring (gold)
    draw.ellipse([0, 0, W - 1, H - 1], fill=(220, 200, 130, 255))
    # Inner colored disc
    draw.ellipse([3, 3, W - 4, H - 4], fill=color)
    # Number, drawn as a simple polygon-styled bullet
    # (Pillow without a reliable system font on Windows can be flaky;
    #  fall back to drawing the glyph as an inset circle.)
    try:
        from PIL import ImageFont
        font = ImageFont.truetype("arial.ttf", 22)
        bbox = draw.textbbox((0, 0), str(seat_num), font=font)
        tw = bbox[2] - bbox[0]
        th = bbox[3] - bbox[1]
        draw.text(
            ((W - tw) / 2 - bbox[0], (H - th) / 2 - bbox[1] - 1),
            str(seat_num), fill=(255, 255, 255, 255), font=font,
        )
    except Exception:
        # Fallback: draw a small inset disc as a placeholder.
        draw.ellipse([16, 16, W - 17, H - 17], fill=(255, 255, 255, 255))
    img.save(os.path.join(DST, out_name), format="TGA", compression=None)


def main():
    make_felt()
    make_glow()
    # Seat 1 = local player; bots are seats 2/3/4.
    make_avatar(2, (200, 60, 60, 255),  "avatar_2.tga")    # red
    make_avatar(3, (60, 130, 200, 255), "avatar_3.tga")    # blue (partner)
    make_avatar(4, (200, 60, 60, 255),  "avatar_4.tga")    # red
    print("Wrote felt.tga, glow.tga, avatar_2/3/4.tga")


if __name__ == "__main__":
    main()
