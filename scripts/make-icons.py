#!/usr/bin/env python3
"""Render Receptor's geometric app icon. Requires Pillow only when regenerating."""
from pathlib import Path
from PIL import Image, ImageDraw

output = Path(__file__).resolve().parent.parent / "App/Resources"
output.mkdir(parents=True, exist_ok=True)
canvas = Image.new("RGB", (576, 576), (28, 62, 91))
draw = ImageDraw.Draw(canvas)
draw.rounded_rectangle((65, 191, 511, 467), radius=35, fill=(121, 216, 191))
draw.rounded_rectangle((65, 142, 275, 267), radius=24, fill=(121, 216, 191))
draw.rectangle((255, 224, 321, 337), fill=(28, 62, 91))
draw.polygon([(206, 309), (370, 309), (288, 391)], fill=(28, 62, 91))
for name, size in [("Icon.png", 57), ("Icon@2x.png", 114), ("Icon-72.png", 72), ("Icon-72@2x.png", 144)]:
    canvas.resize((size, size), Image.Resampling.LANCZOS).save(output / name)
