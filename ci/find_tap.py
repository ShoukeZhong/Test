"""從 uiautomator dump 的 XML 找出含指定文字的元件，印出中心座標 "x y"。找不到就 exit 1。"""
import re
import sys
import xml.etree.ElementTree as ET

path, label = sys.argv[1], sys.argv[2]
root = ET.parse(path).getroot()
for node in root.iter("node"):
    text = (node.get("text") or "") + "|" + (node.get("content-desc") or "")
    if label in text:
        x1, y1, x2, y2 = map(int, re.findall(r"\d+", node.get("bounds", "")))
        print((x1 + x2) // 2, (y1 + y2) // 2)
        sys.exit(0)
sys.exit(1)
