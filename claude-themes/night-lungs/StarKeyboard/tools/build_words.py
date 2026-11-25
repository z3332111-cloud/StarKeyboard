#!/usr/bin/env python3
"""英文滑行輸入用的字表：每行「單字 次數」，只留小寫英文字母的字，最常用的前 25000 個。

用法：python3 tools/build_words.py <en_50k.txt> <輸出.txt> [<輸出2.txt> ...]

來源：hermitdave/FrequencyWords（OpenSubtitles 2018 英文字幕統計），內容授權 CC BY-SA 4.0。
"""
import re
import sys

KEEP = 25000
WORD = re.compile("^[a-z]+$")


def main(src, outs):
    rows = []
    with open(src, encoding="utf-8") as f:
        for line in f:
            parts = line.split()
            if len(parts) != 2 or not WORD.match(parts[0]) or not parts[1].isdigit():
                continue
            if len(parts[0]) < 2 and parts[0] not in ("a", "i"):
                continue
            rows.append((parts[0], int(parts[1])))
    rows = rows[:KEEP]
    text = "".join("%s %d\n" % r for r in rows)
    for out in outs:
        with open(out, "w", encoding="utf-8") as f:
            f.write(text)
    print("英文字表：%d 個字" % len(rows))
    words = {w for w, _ in rows}
    for must in ("the", "hello", "keyboard", "thanks", "love"):
        assert must in words, must


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1], sys.argv[2:])
