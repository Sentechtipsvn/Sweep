"""Regenerate the code-drawn Sweep app icon (development tool; requires Pillow)."""
from pathlib import Path
import json
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
size = 1024
image = Image.new('RGB', (size, size))
pixels = image.load()
for y in range(size):
    for x in range(size):
        t = (x + y) / (2 * (size - 1))
        pixels[x, y] = tuple(round(a + (b - a) * t) for a, b in zip((5, 63, 48), (44, 204, 116)))
draw = ImageDraw.Draw(image)
# Three sweeping strokes and a small glint; no text or platform-specific glyphs.
for box, width in [((180, 260, 850, 790), 48), ((240, 355, 825, 815), 43), ((310, 450, 800, 840), 38)]:
    draw.arc(box, start=30, end=160, fill=(255, 255, 255), width=width)
draw.line([(389, 457), (627, 239)], fill=(255, 255, 255), width=55)
draw.ellipse((599, 213, 654, 268), fill=(255, 255, 255))
draw.polygon([(758, 234), (773, 279), (817, 294), (773, 309), (758, 354), (743, 309), (699, 294), (743, 279)], fill=(214, 255, 208))
target = root / 'Sweep/Assets.xcassets/AppIcon.appiconset'
target.mkdir(parents=True, exist_ok=True)
image.save(target / 'AppIcon.png', optimize=True)
(target / 'Contents.json').write_text(json.dumps({'images': [{'filename': 'AppIcon.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}], 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
(target.parent / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
