"""截圖裡看不看得到寵物：數「橘色毛」色相的像素（白天晚上都適用）。用法：pet_visible.py 圖檔 [門檻]。"""
import colorsys
import sys
from PIL import Image

threshold = int(sys.argv[2]) if len(sys.argv) > 2 else 1500
img = Image.open(sys.argv[1]).convert("RGB")
img = img.resize((img.width // 2, img.height // 2))  # 加速；門檻以縮圖後計
n = 0
for r, g, b in img.getdata():
    h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    if 0.06 <= h <= 0.11 and s >= 0.45 and v >= 0.35:
        n += 1
print(n)
sys.exit(0 if n >= threshold else 1)
