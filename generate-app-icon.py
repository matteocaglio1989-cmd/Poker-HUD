#!/usr/bin/env python3
"""Generate macOS app icon sizes from a source image.

Usage:
    python3 generate-app-icon.py <source-image.png>

The source image should be at least 1024x1024 pixels.
Outputs are written to PokerHUD/Assets.xcassets/AppIcon.appiconset/
"""

import sys
from pathlib import Path
from PIL import Image

SIZES = [16, 32, 64, 128, 256, 512, 1024]
OUTPUT_DIR = Path(__file__).parent / "PokerHUD" / "Assets.xcassets" / "AppIcon.appiconset"

def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <source-image.png>")
        sys.exit(1)

    src = Path(sys.argv[1])
    if not src.exists():
        print(f"Error: {src} not found")
        sys.exit(1)

    img = Image.open(src).convert("RGBA")
    print(f"Source: {src} ({img.width}x{img.height})")

    for size in SIZES:
        out = OUTPUT_DIR / f"icon_{size}.png"
        resized = img.resize((size, size), Image.LANCZOS)
        resized.save(out, "PNG")
        print(f"  -> {out.name} ({size}x{size})")

    print("Done! All icon sizes generated.")

if __name__ == "__main__":
    main()
