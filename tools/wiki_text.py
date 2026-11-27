#!/usr/bin/env python3
"""從維基百科的 multistream 壓縮檔（可以只下載前面一段）抽出文章文字，一行一段，給 train_lm.py 用。

用法：python3 tools/wiki_text.py zhwiki-前面一段.xml.bz2 輸出.txt
只留文章內文：拿掉模板 {{…}}、表格、<ref>、檔案連結；[[連結|文字]] 只留文字。
檔案被截斷時讀到哪算到哪。
"""
import bz2
import re
import sys

TEMPLATE = re.compile(r"\{\{[^{}]*\}\}")
REF = re.compile(r"<ref[^>/]*/>|<ref[^>]*>.*?</ref>", re.S)
TAG = re.compile(r"<[^>]+>")
LINK = re.compile(r"\[\[(?:[^\]|]*\|)?([^\]]*)\]\]")
EXT = re.compile(r"\[https?://[^\s\]]+\s*([^\]]*)\]")
TABLE = re.compile(r"\{\|.*?\|\}", re.S)
VARIANT = re.compile(r"-\{(?:[^{}]*?zh-tw:([^;}]*))?[^{}]*?\}-")


def clean(text):
    text = REF.sub("", text)
    for _ in range(3):
        text = TEMPLATE.sub("", text)
    text = TABLE.sub("", text)
    text = VARIANT.sub(lambda m: m.group(1) or "", text)
    text = re.sub(r"\[\[(?:File|Image|Category|檔案|文件|图像|圖像|分类|分類):[^\]]*\]\]", "", text)
    text = LINK.sub(r"\1", text)
    text = EXT.sub(r"\1", text)
    text = TAG.sub("", text)
    text = text.replace("'''", "").replace("''", "")
    return text


def main():
    src, out = sys.argv[1], sys.argv[2]
    data = open(src, "rb").read()
    xml = []
    pos = 0
    while pos < len(data):
        d = bz2.BZ2Decompressor()
        try:
            xml.append(d.decompress(data[pos:]).decode("utf-8", "ignore"))
        except (OSError, EOFError):
            break
        if not d.eof:
            break
        pos = len(data) - len(d.unused_data)
    text = "".join(xml)
    n = 0
    with open(out, "w", encoding="utf-8") as f:
        for m in re.finditer(r"<text[^>]*>(.*?)</text>", text, re.S):
            body = m.group(1)
            if body.startswith("#REDIRECT") or body.startswith("#重定向"):
                continue
            body = body.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", '"').replace("&amp;", "&")
            for line in clean(body).split("\n"):
                line = line.strip()
                if len(line) >= 8 and not line.startswith(("|", "!", "*", "#", "=", "{", "}")):
                    f.write(line + "\n")
                    n += 1
    print(f"{n} lines", file=sys.stderr)


if __name__ == "__main__":
    main()
