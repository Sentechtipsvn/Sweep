"""Build the iOS icon from Sếp Sen's supplied art, without redrawing/cropping the character."""
from pathlib import Path
import json
from PIL import Image
root = Path(__file__).resolve().parents[1]
source = Image.open(root / 'Design/AppIcon-Source.jpeg').convert('RGB')
source.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
image = Image.new('RGB', (1024, 1024), '#336C68')
image.paste(source, ((1024-source.width)//2, (1024-source.height)//2))
target = root / 'Sweep/Assets.xcassets/AppIcon.appiconset'
image.save(target / 'AppIcon.png', optimize=True)
(target / 'Contents.json').write_text(json.dumps({'images':[{'filename':'AppIcon.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'author':'xcode','version':1}}, indent=2)+'\n')
