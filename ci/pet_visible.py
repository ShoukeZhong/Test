"""截圖裡看不看得到橘色的貓：數「橘色毛」色相的像素。
用法：pet_visible.py 圖檔 [門檻]
輸出："像素數 重心x 重心y"（原圖像素座標；看不到時重心為 -1）。像素數 >= 門檻時 exit 0。"""
import colorsys
import sys
from PIL import Image

threshold = int(sys.argv[2]) if len(sys.argv) > 2 else 200
img = Image.open(sys.argv[1]).convert("RGB")
small = img.resize((img.width // 2, img.height // 2))  # 加速；門檻以縮圖後計
n = sx = sy = 0
w = small.width
for i, (r, g, b) in enumerate(small.getdata()):
    h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    if 0.06 <= h <= 0.11 and s >= 0.45 and v >= 0.35:
        n += 1
        sx += i % w
        sy += i // w
if n:
    print(n, sx * 2 // n, sy * 2 // n)
else:
    print(0, -1, -1)
sys.exit(0 if n >= threshold else 1)
