#!/usr/bin/env python3
"""做字體預覽小圖：App 裡還沒下載的字體，先看這張圖就知道長什麼樣子。

用法：python3 tools/font_preview.py 輸出資料夾 備用字體.ttf 字體1.ttf 字體2.ttf ...
每款輸出「檔名-preview.png」：黑字、透明底（App 會照深色／淺色模式把字染成對的顏色）。
字體裡沒有的字（例如有的手寫字沒有注音）改用備用字體畫，和鍵盤上看到的一樣。
"""
import os
import sys

import tempfile

from fontTools import subset
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFont

TEXT = "糯糯鍵盤 ㄅㄆㄇ Aa 123"
SIZE = 44          # 字的大小（像素）
HEIGHT = 64        # 圖的高度
PAD = 6


def dehinted(path):
    """有的字體的微調程式 FreeType 跑不動（too many function definitions）：拿掉微調再畫"""
    options = subset.Options()
    options.hinting = False
    options.notdef_outline = True
    options.layout_features = ["*"]
    font = subset.load_font(path, options)
    sub = subset.Subsetter(options)
    sub.populate(unicodes=font.getBestCmap().keys())
    sub.subset(font)
    out = tempfile.NamedTemporaryFile(suffix=".ttf", delete=False).name
    subset.save_font(font, out, options)
    return out


def render(path, cmap, fallback):
    font = ImageFont.truetype(path, SIZE)
    pieces = [(ch, font if ch == " " or ord(ch) in cmap else fallback) for ch in TEXT]
    width = PAD * 2 + sum(int(round(f.getlength(ch))) for ch, f in pieces)
    image = Image.new("LA", (max(1, width), HEIGHT), (0, 0))
    draw = ImageDraw.Draw(image)
    x = PAD
    for ch, f in pieces:
        # 用基線對齊：每個字的基線都放在同一條線上
        draw.text((x, HEIGHT * 0.78), ch, font=f, fill=(0, 255), anchor="ls")
        x += int(round(f.getlength(ch)))
    return image


def main():
    out_dir, fallback_path, *fonts = sys.argv[1:]
    os.makedirs(out_dir, exist_ok=True)
    fallback = ImageFont.truetype(fallback_path, SIZE)
    for path in fonts:
        name = os.path.splitext(os.path.basename(path))[0]
        try:
            cmap = TTFont(path, lazy=True).getBestCmap()
            try:
                image = render(path, cmap, fallback)
            except OSError:
                image = render(dehinted(path), cmap, fallback)
        except Exception as e:  # 壞掉的字體跳過，不要讓整批失敗
            print(f"{name}：做不出預覽（{e}），跳過")
            continue
        width = image.width
        out = os.path.join(out_dir, f"{name}-preview.png")
        image.save(out, optimize=True)
        print(f"{name}：{width}×{HEIGHT}，{os.path.getsize(out) // 1024} KB")


if __name__ == "__main__":
    main()
