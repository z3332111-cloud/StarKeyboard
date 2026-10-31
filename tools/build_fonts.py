#!/usr/bin/env python3
"""把可愛字體縮小成鍵盤用的大小（只留常用字），放進 App。

用法：python3 tools/build_fonts.py <zhuyin.sqlite> <輸出資料夾> 名稱=字體檔 [名稱=字體檔 ...]

字體都是 SIL Open Font License 1.1（可以免費使用、改小、一起散布）：
- huninn：jf open 粉圓（justfont）
- iansui：芫荽（But Ko）
- wenkai：霞鶩文楷 TC（LXGW）
- gensen：源泉圓體 TW（ButTaiwan）
- naikai：內海字體 Lite（max32002）
- cubic：俐方體11號（ACh-K，像素風）

完整的中文字體每個 4～14 MB。鍵盤只用來顯示按鍵和候選字，所以只留字典裡最常用的字，
少見的字手機會自動用內建字體補上。
"""
import os
import sqlite3
import sys

from fontTools import subset

KEEP_CHARS = 8000


def charset(dict_path):
    db = sqlite3.connect(dict_path)
    best = {}
    for phrase, score in db.execute("SELECT phrase, score FROM phrases WHERE length(phrase) = 1"):
        if phrase not in best or best[phrase] < score:
            best[phrase] = score
    common = sorted(best, key=lambda c: -best[c])[:KEEP_CHARS]
    chars = set(common)
    ranges = [
        (0x20, 0x7E),        # 英文、數字、符號
        (0xA0, 0x24F),       # 拉丁字母（有重音的）
        (0x2000, 0x206F),    # 標點
        (0x2190, 0x21FF),    # 箭頭
        (0x2460, 0x24FF),    # 圈圈數字
        (0x2600, 0x27BF),    # 雜項符號
        (0x3000, 0x303F),    # 中文標點
        (0x3040, 0x30FF),    # 平假名、片假名
        (0x3100, 0x312F),    # 注音
        (0x31A0, 0x31BF),    # 注音擴充
        (0xFF00, 0xFFEF),    # 全形
    ]
    for lo, hi in ranges:
        chars.update(chr(c) for c in range(lo, hi + 1))
    chars.update("ˊˇˋ˙")
    return "".join(sorted(chars))


def main(dict_path, out_dir, fonts):
    os.makedirs(out_dir, exist_ok=True)
    text = charset(dict_path)
    for item in fonts:
        name, path = item.split("=", 1)
        if not path or not os.path.exists(path):
            print("%s：找不到字體檔，跳過（鍵盤會改用內建圓體）" % name)
            continue
        out = os.path.join(out_dir, name + ".ttf")
        options = subset.Options()
        options.layout_features = ["*"]
        options.name_IDs = ["*"]
        options.name_languages = ["*"]
        options.notdef_outline = True
        options.glyph_names = False
        font = subset.load_font(path, options)
        sub = subset.Subsetter(options)
        sub.populate(text=text)
        sub.subset(font)
        subset.save_font(font, out, options)
        print("%s：%.1f MB → %.1f MB" % (name, os.path.getsize(path) / 1e6, os.path.getsize(out) / 1e6))


if __name__ == "__main__":
    if len(sys.argv) < 4:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1], sys.argv[2], sys.argv[3:])
