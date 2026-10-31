#!/usr/bin/env python3
"""Resize the approved rounded artwork into legacy iOS and Cydia icon sizes."""
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parent.parent
output = root / "App/Resources"
output.mkdir(parents=True, exist_ok=True)
canvas = Image.open(root / "App/Artwork/Icon-rounded.png").convert("RGBA")
for name, size in [("Icon.png", 57), ("Icon@2x.png", 114), ("Icon-72.png", 72), ("Icon-72@2x.png", 144)]:
    canvas.resize((size, size), Image.Resampling.LANCZOS).save(output / name)
for name, size in [("icon.png", 144), ("CydiaIcon.png", 64), ("favicon.png", 32)]:
    canvas.resize((size, size), Image.Resampling.LANCZOS).save(root / "docs" / name)
