#!/usr/bin/env python3
"""Generate packaging icons from assets/timer-logo.png.

Outputs:
  assets/timer-logo.ico      multi-resolution Windows icon (16-256 px)
  assets/timer-logo-256.png  256x256 PNG for Linux desktop entries / AppImage

Usage:  python packaging/make_icons.py      (requires Pillow)
"""
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "timer-logo.png")
ICO = os.path.join(ROOT, "assets", "timer-logo.ico")
PNG_256 = os.path.join(ROOT, "assets", "timer-logo-256.png")
ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]


def scaled(img: Image.Image, size: int) -> Image.Image:
    """Resize, keeping hard pixel edges for integer upscales of the small source logo."""
    if size == img.width:
        return img.copy()
    integer_upscale = size > img.width and size % img.width == 0
    resample = Image.NEAREST if integer_upscale else Image.LANCZOS
    return img.resize((size, size), resample)


def main() -> None:
    src = Image.open(SRC).convert("RGBA")
    frames = [scaled(src, s) for s in ICO_SIZES]
    # Pillow writes one ICO entry per size; the largest frame is the base image.
    frames[-1].save(ICO, format="ICO", sizes=[(s, s) for s in ICO_SIZES], append_images=frames[:-1])
    frames[-1].save(PNG_256, format="PNG")
    print(f"wrote {os.path.relpath(ICO, ROOT)} ({', '.join(map(str, ICO_SIZES))} px)")
    print(f"wrote {os.path.relpath(PNG_256, ROOT)}")


if __name__ == "__main__":
    main()

