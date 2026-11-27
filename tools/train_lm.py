#!/usr/bin/env python3
"""統計「哪些字常接在一起」：從開放授權的中文句子算 1～3 個字的字串出現幾次，給選字時看前後文用。

資料來源（.github/workflows/train-lm.yml 會下載）：
- Mozilla Common Voice 台灣華語句子（CC0）：口語、短句
- Tatoeba 中文句子（CC BY 2.0 FR）：日常對話
- 維基百科中文版前面一部分（CC BY-SA 4.0）：量大、補書面語

用法：python3 tools/train_lm.py 輸出檔 [--exclude 測試句子檔] --weight 20 口語檔... --weight 1 維基檔...
（--weight 之後的檔案用那個權重；口語句子少，乘上權重才不會被維基百科蓋過去）
簡體字先用 OpenCC 轉成台灣繁體。只算漢字連在一起的部分，標點、英文、數字會把句子切開。
"""
import collections
import re
import sys

HAN = re.compile(r"[㐀-䶿一-鿿]+")


def converter():
    try:
        import opencc
        cc = opencc.OpenCC("s2twp")
        return cc.convert
    except Exception:
        return lambda s: s


def main():
    args = sys.argv[1:]
    out_path = args.pop(0)
    convert = converter()
    counts = [collections.Counter() for _ in range(4)]
    weight = 1
    exclude = []
    while args:
        a = args.pop(0)
        if a == "--weight":
            weight = int(args.pop(0))
            continue
        if a == "--exclude":
            # 測試用的句子不能拿來訓練，不然量出來的準確度不準
            with open(args.pop(0), encoding="utf-8") as f:
                exclude = [l.strip() for l in f if l.strip()]
            continue
        lines = 0
        with open(a, encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = convert(line)
                if exclude and weight > 1 and any(t in line for t in exclude):
                    continue
                for run in HAN.findall(line):
                    for n in (1, 2, 3):
                        c = counts[n]
                        for i in range(len(run) - n + 1):
                            c[run[i:i + n]] += weight
                lines += 1
        print(f"{a}: {lines} lines, weight {weight}", file=sys.stderr)
    # 太少見的去掉，檔案才不會太大：兩個字至少 3 次、三個字至少 4 次
    keep = []
    keep += [(g, n) for g, n in counts[1].items() if n >= 2]
    keep += [(g, n) for g, n in counts[2].items() if n >= 3]
    keep += [(g, n) for g, n in counts[3].items() if n >= 4]
    keep.sort(key=lambda x: (-x[1], x[0]))
    limit = 900_000
    keep = keep[:limit]
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("# 字串出現次數（1～3 個字），選字時看前後文用。tools/train_lm.py 產生。\n")
        f.write("# 來源：Mozilla Common Voice zh-TW 句子（CC0）、Tatoeba（CC BY 2.0 FR）、維基百科中文版（CC BY-SA 4.0）\n")
        for g, n in keep:
            f.write(f"{g}\t{n}\n")
    total = {n: sum(1 for g, _ in keep if len(g) == n) for n in (1, 2, 3)}
    print(f"kept {len(keep)} grams {total}", file=sys.stderr)


if __name__ == "__main__":
    main()
