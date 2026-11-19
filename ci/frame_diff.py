"""兩張截圖有幾個像素明顯不同（任一色版差 > 24）。用來確認畫面一直在動、不是靜止圖。"""
import sys
from PIL import Image, ImageChops

a = Image.open(sys.argv[1]).convert("RGB")
b = Image.open(sys.argv[2]).convert("RGB")
if a.size != b.size:
    print(0)
    sys.exit(0)
d = ImageChops.difference(a, b).convert("L")
print(sum(1 for v in d.getdata() if v > 24))
