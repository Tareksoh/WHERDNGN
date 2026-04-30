"""
Generate a proper card back texture (back.tga, 128x192).

The hayeah back.png is essentially plain white at this size, which renders
as a featureless rectangle on the WoW seat-side face-down stacks. This
script makes a navy-blue back with a diagonal lattice pattern and an
inner border — distinctive at any size, matches the deeper red/blue art
of the face cards.
"""
from PIL import Image, ImageDraw

W, H = 128, 192

NAVY      = (10, 30, 78, 255)
NAVY_HI   = (32, 60, 130, 255)
BORDER    = (220, 200, 130, 255)   # warm gold edge
LINE      = (60, 95, 165, 255)     # lattice line color


def main():
    img = Image.new("RGBA", (W, H), NAVY)
    draw = ImageDraw.Draw(img)

    # Diagonal lattice pattern
    spacing = 12
    for d in range(-H, W + H, spacing):
        draw.line([(d, 0), (d + H, H)], fill=LINE, width=1)
        draw.line([(d, H), (d + H, 0)], fill=LINE, width=1)

    # Outer thin gold border
    for i in range(2):
        draw.rectangle([i, i, W - 1 - i, H - 1 - i], outline=BORDER)

    # Inner darker frame: creates a "card back" feel.
    inset = 8
    draw.rectangle(
        [inset, inset, W - 1 - inset, H - 1 - inset],
        outline=NAVY_HI, width=2
    )

    # Center medallion: filled diamond
    cx, cy = W // 2, H // 2
    diamond_size = 24
    draw.polygon(
        [(cx, cy - diamond_size), (cx + diamond_size, cy),
         (cx, cy + diamond_size), (cx - diamond_size, cy)],
        fill=BORDER, outline=NAVY,
    )
    # Smaller inner diamond for detail
    inner = 12
    draw.polygon(
        [(cx, cy - inner), (cx + inner, cy),
         (cx, cy + inner), (cx - inner, cy)],
        fill=NAVY,
    )

    img.save(r"C:\CLAUDE\WHEREDNGN\cards\back.tga", format="TGA",
             compression=None)
    print("Wrote back.tga ({}x{})".format(W, H))


if __name__ == "__main__":
    main()
