"""截圖裡看不看得到寵物：數接近寵物橘色 (242,166,90) 的像素。看得到 exit 0，否則 exit 1。"""
import sys
from PIL import Image

data = Image.open(sys.argv[1]).convert("RGB").tobytes()
n = sum(
    1
    for i in range(0, len(data), 3)
    if abs(data[i] - 242) <= 12 and abs(data[i + 1] - 166) <= 12 and abs(data[i + 2] - 90) <= 12
)
print(n)
sys.exit(0 if n >= 1500 else 1)
