#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 App 图标（含全套尺寸 + Contents.json）。

为什么用脚本而不是放一张图?
    1) 每个尺寸都用 LANCZOS 从 1024 母版缩放，边缘干净；
    2) Contents.json 和文件名永远一致，不会出现"图标缺失"的黄叹号；
    3) 想换配色只改这里两行常量。

用法: python tools/make_icon.py
"""

import json
import math
import os
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:
    print("[FAIL] 需要 Pillow：pip install Pillow")
    sys.exit(1)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICONSET = os.path.join(ROOT, "AIAssistant", "Assets.xcassets", "AppIcon.appiconset")

TOP_COLOR = (86, 116, 255)      # #5674FF
BOTTOM_COLOR = (122, 84, 240)   # #7A54F0

# (文件名, 像素尺寸, idiom, size, scale)
ENTRIES = [
    ("icon-20@2x.png", 40, "iphone", "20x20", "2x"),
    ("icon-20@3x.png", 60, "iphone", "20x20", "3x"),
    ("icon-29@2x.png", 58, "iphone", "29x29", "2x"),
    ("icon-29@3x.png", 87, "iphone", "29x29", "3x"),
    ("icon-40@2x.png", 80, "iphone", "40x40", "2x"),
    ("icon-40@3x.png", 120, "iphone", "40x40", "3x"),
    ("icon-60@2x.png", 120, "iphone", "60x60", "2x"),
    ("icon-60@3x.png", 180, "iphone", "60x60", "3x"),
    ("icon-20@1x-ipad.png", 20, "ipad", "20x20", "1x"),
    ("icon-20@2x-ipad.png", 40, "ipad", "20x20", "2x"),
    ("icon-29@1x-ipad.png", 29, "ipad", "29x29", "1x"),
    ("icon-29@2x-ipad.png", 58, "ipad", "29x29", "2x"),
    ("icon-40@1x-ipad.png", 40, "ipad", "40x40", "1x"),
    ("icon-40@2x-ipad.png", 80, "ipad", "40x40", "2x"),
    ("icon-76@1x.png", 76, "ipad", "76x76", "1x"),
    ("icon-76@2x.png", 152, "ipad", "76x76", "2x"),
    ("icon-83.5@2x.png", 167, "ipad", "83.5x83.5", "2x"),
    ("icon-1024.png", 1024, "ios-marketing", "1024x1024", "1x"),
]


def master(size=1024):
    image = Image.new("RGB", (size, size), TOP_COLOR)
    draw = ImageDraw.Draw(image)

    # 竖向渐变
    for y in range(size):
        ratio = y / (size - 1)
        color = tuple(
            int(TOP_COLOR[i] + (BOTTOM_COLOR[i] - TOP_COLOR[i]) * ratio) for i in range(3)
        )
        draw.line([(0, y), (size, y)], fill=color)

    # 圆角对话框
    bubble = (size * 0.20, size * 0.24, size * 0.80, size * 0.66)
    draw.rounded_rectangle(bubble, radius=int(size * 0.11), fill=(255, 255, 255))

    # 尾巴
    tail = [
        (size * 0.34, size * 0.64),
        (size * 0.34, size * 0.80),
        (size * 0.50, size * 0.64),
    ]
    draw.polygon(tail, fill=(255, 255, 255))

    # 中间的四角星（AI 味）
    cx, cy = size * 0.50, size * 0.45
    inner, outer = size * 0.045, size * 0.135
    points = []
    for index in range(8):
        angle = math.pi / 4 * index - math.pi / 2
        radius = outer if index % 2 == 0 else inner
        points.append((cx + math.cos(angle) * radius, cy + math.sin(angle) * radius))
    draw.polygon(points, fill=TOP_COLOR)

    return image


def main():
    os.makedirs(ICONSET, exist_ok=True)
    base = master(1024)

    for filename, pixels, _, _, _ in ENTRIES:
        image = base if pixels == 1024 else base.resize((pixels, pixels), Image.LANCZOS)
        path = os.path.join(ICONSET, filename)
        image.save(path, "PNG", optimize=True)
        print("  %-22s %4dpx" % (filename, pixels))

    contents = {
        "images": [
            {
                "filename": filename,
                "idiom": idiom,
                "scale": scale,
                "size": size,
            }
            for filename, _, idiom, size, scale in ENTRIES
        ],
        "info": {"author": "xcode", "version": 1},
    }
    with open(os.path.join(ICONSET, "Contents.json"), "w", encoding="utf-8", newline="\n") as handle:
        json.dump(contents, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    print("[OK] 图标已生成到 %s" % os.path.relpath(ICONSET, ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
