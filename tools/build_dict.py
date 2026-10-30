#!/usr/bin/env python3
"""把小麥注音的 data.txt 轉成鍵盤用的 SQLite 字典。

用法：python3 tools/build_dict.py <data.txt> <輸出.sqlite> [OpenCC 的 TSCharacters.txt TSPhrases.txt]

data.txt 每行是「讀音 字詞 分數」，讀音的音節用 - 連接，例如：ㄋㄧˇ-ㄏㄠˇ 你好 -4.38

資料表：
- phrases(reading, plain, phrase, score)
    reading：有聲調的注音（注音輸入法用），例如 ㄋㄧˇ-ㄏㄠˇ
    plain：拿掉聲調的注音（拼音輸入法用），例如 ㄋㄧ-ㄏㄠ
    abbr：每個音節的第一個注音（只打開頭的簡拼用），例如 ㄋㄏ
- pinyin(py, bpmf)：漢語拼音音節 → 沒聲調的注音，例如 hao → ㄏㄠ、lv → ㄌㄩ
- t2s(trad, simp)：繁體 → 簡體（OpenCC，Apache 2.0；有給 OpenCC 檔案才會有）

另外會讀同一個資料夾的 chat_phrases.txt（聊天常用句），分數拉到至少 CHAT_SCORE。
"""
import os
import re
import sqlite3
import sys

SYLLABLE = "[ㄅ-ㄩˊˇˋ˙]+"
READING = re.compile("^%s(-%s)*$" % (SYLLABLE, SYLLABLE))
TONES = "ˊˇˋ˙"
# 聊天常用句的分數下限（log10 機率）：比「女孩」「們」這類新聞常見詞高一點，簡拼才猜得到「你好」「可以嗎」
CHAT_SCORE = -3.5
CHAT_PHRASES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "chat_phrases.txt")

INITIALS = {
    "ㄅ": "b", "ㄆ": "p", "ㄇ": "m", "ㄈ": "f", "ㄉ": "d", "ㄊ": "t", "ㄋ": "n", "ㄌ": "l",
    "ㄍ": "g", "ㄎ": "k", "ㄏ": "h", "ㄐ": "j", "ㄑ": "q", "ㄒ": "x", "ㄓ": "zh", "ㄔ": "ch",
    "ㄕ": "sh", "ㄖ": "r", "ㄗ": "z", "ㄘ": "c", "ㄙ": "s",
}
# 有聲母時的韻母
FINALS = {
    "ㄚ": "a", "ㄛ": "o", "ㄜ": "e", "ㄞ": "ai", "ㄟ": "ei", "ㄠ": "ao", "ㄡ": "ou",
    "ㄢ": "an", "ㄣ": "en", "ㄤ": "ang", "ㄥ": "eng", "ㄦ": "er",
    "ㄧ": "i", "ㄧㄚ": "ia", "ㄧㄛ": "io", "ㄧㄝ": "ie", "ㄧㄞ": "iai", "ㄧㄠ": "iao", "ㄧㄡ": "iu",
    "ㄧㄢ": "ian", "ㄧㄣ": "in", "ㄧㄤ": "iang", "ㄧㄥ": "ing",
    "ㄨ": "u", "ㄨㄚ": "ua", "ㄨㄛ": "uo", "ㄨㄞ": "uai", "ㄨㄟ": "ui", "ㄨㄢ": "uan", "ㄨㄣ": "un",
    "ㄨㄤ": "uang", "ㄨㄥ": "ong",
    "ㄩ": "v", "ㄩㄝ": "ve", "ㄩㄢ": "van", "ㄩㄣ": "vn", "ㄩㄥ": "iong",
}
# 沒有聲母時的寫法
ALONE = {
    "ㄧ": "yi", "ㄧㄚ": "ya", "ㄧㄛ": "yo", "ㄧㄝ": "ye", "ㄧㄞ": "yai", "ㄧㄠ": "yao", "ㄧㄡ": "you",
    "ㄧㄢ": "yan", "ㄧㄣ": "yin", "ㄧㄤ": "yang", "ㄧㄥ": "ying",
    "ㄨ": "wu", "ㄨㄚ": "wa", "ㄨㄛ": "wo", "ㄨㄞ": "wai", "ㄨㄟ": "wei", "ㄨㄢ": "wan", "ㄨㄣ": "wen",
    "ㄨㄤ": "wang", "ㄨㄥ": "weng",
    "ㄩ": "yu", "ㄩㄝ": "yue", "ㄩㄢ": "yuan", "ㄩㄣ": "yun", "ㄩㄥ": "yong",
}


def to_pinyin(bpmf):
    """沒聲調的注音音節 → 漢語拼音（ü 寫成 v，鍵盤上的打法）；不認得就回傳 None"""
    initial = INITIALS.get(bpmf[:1], "")
    rest = bpmf[1:] if initial else bpmf
    if not rest:
        # ㄓ ㄔ ㄕ ㄖ ㄗ ㄘ ㄙ 單獨一個字：zhi chi shi ri zi ci si
        return initial + "i" if initial in ("zh", "ch", "sh", "r", "z", "c", "s") else None
    if not initial:
        if rest in ALONE:
            return ALONE[rest]
        return FINALS.get(rest) if rest[:1] not in "ㄧㄨㄩ" else None
    final = FINALS.get(rest)
    if final is None:
        return None
    if initial in ("j", "q", "x") and final.startswith("v"):
        final = "u" + final[1:]       # ju jue juan jun
    if initial in ("j", "q", "x") and final == "iong":
        final = "iong"
    return initial + final


def plain(reading):
    return "".join(c for c in reading if c not in TONES)


def abbr(reading):
    return "".join(syl[0] for syl in reading.split("-"))


def load_opencc(paths):
    table = {}
    for path in paths:
        with open(path, encoding="utf-8") as f:
            for line in f:
                if line.startswith("#") or "\t" not in line:
                    continue
                trad, simp = line.rstrip("\n").split("\t", 1)
                simp = simp.split(" ")[0]
                if trad and simp and trad != simp:
                    table[trad] = simp
    return table


def main(src, dst, opencc):
    best = {}
    with open(src, encoding="utf-8") as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            parts = line.rstrip("\n").split(" ")
            if len(parts) != 3:
                continue
            reading, phrase, score = parts
            if not READING.match(reading) or phrase.startswith("MACRO@"):
                continue
            try:
                score = float(score)
            except ValueError:
                continue
            key = (reading, phrase)
            if key not in best or best[key] < score:
                best[key] = score

    chat = 0
    with open(CHAT_PHRASES, encoding="utf-8") as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            reading, phrase = line.split()
            if not READING.match(reading):
                sys.exit("chat_phrases.txt 讀音格式不對：%s" % line.strip())
            key = (reading, phrase)
            if best.get(key, -99) < CHAT_SCORE:
                best[key] = CHAT_SCORE
                chat += 1

    pinyin = {}
    unknown = set()
    for (reading, _) in best:
        for syl in plain(reading).split("-"):
            py = to_pinyin(syl)
            if py is None:
                unknown.add(syl)
            elif py not in pinyin:
                pinyin[py] = syl

    if os.path.exists(dst):
        os.remove(dst)
    os.makedirs(os.path.dirname(os.path.abspath(dst)), exist_ok=True)
    db = sqlite3.connect(dst)
    db.execute("PRAGMA page_size=4096")
    db.execute("CREATE TABLE phrases(reading TEXT NOT NULL, plain TEXT NOT NULL, abbr TEXT NOT NULL, phrase TEXT NOT NULL, score REAL NOT NULL)")
    db.executemany("INSERT INTO phrases(reading, plain, abbr, phrase, score) VALUES (?, ?, ?, ?, ?)",
                   ((r, plain(r), abbr(r), p, round(s, 4)) for (r, p), s in sorted(best.items())))
    db.execute("CREATE INDEX idx_reading ON phrases(reading, score DESC)")
    db.execute("CREATE INDEX idx_plain ON phrases(plain, score DESC)")
    db.execute("CREATE INDEX idx_abbr ON phrases(abbr, score DESC)")
    db.execute("CREATE INDEX idx_phrase ON phrases(phrase)")
    db.execute("CREATE TABLE pinyin(py TEXT PRIMARY KEY, bpmf TEXT NOT NULL)")
    db.executemany("INSERT INTO pinyin VALUES (?, ?)", sorted(pinyin.items()))
    t2s = load_opencc(opencc) if opencc else {}
    db.execute("CREATE TABLE t2s(trad TEXT PRIMARY KEY, simp TEXT NOT NULL)")
    db.executemany("INSERT INTO t2s VALUES (?, ?)", sorted(t2s.items()))
    db.commit()
    db.execute("VACUUM")
    db.close()

    singles = sum(1 for (r, _) in best if "-" not in r)
    print("字詞 %d 筆（單字 %d，聊天常用句調整 %d 筆）、拼音音節 %d 個、繁簡對照 %d 筆、檔案 %.1f MB"
          % (len(best), singles, chat, len(pinyin), len(t2s), os.path.getsize(dst) / 1e6))
    if unknown:
        print("轉不出拼音的注音音節：", " ".join(sorted(unknown)[:30]))

    # 簡單檢查：常用字、拼音、繁簡要查得到
    db = sqlite3.connect(dst)
    def top(sql, arg):
        return [r[0] for r in db.execute(sql, (arg,))]
    checks = [
        ("SELECT phrase FROM phrases WHERE reading=? ORDER BY score DESC LIMIT 5", "ㄋㄧˇ-ㄏㄠˇ", "你好"),
        ("SELECT phrase FROM phrases WHERE reading=? ORDER BY score DESC LIMIT 5", "ㄉㄜ˙", "的"),
        ("SELECT phrase FROM phrases WHERE plain=? ORDER BY score DESC LIMIT 5", "ㄋㄧ-ㄏㄠ", "你好"),
        ("SELECT phrase FROM phrases WHERE abbr=? ORDER BY score DESC LIMIT 20", "ㄋㄏ", "你好"),
        ("SELECT phrase FROM phrases WHERE abbr=? ORDER BY score DESC LIMIT 5", "ㄎㄧㄇ", "可以嗎"),
        ("SELECT phrase FROM phrases WHERE reading=? ORDER BY score DESC LIMIT 5", "ㄗㄣˇ-ㄇㄜ˙-ㄌㄜ˙", "怎麼了"),
        ("SELECT phrase FROM phrases WHERE reading=? ORDER BY score DESC LIMIT 5", "ㄕㄣˊ-ㄇㄜ˙", "什麼"),
        ("SELECT phrase FROM phrases WHERE reading=? ORDER BY score DESC LIMIT 5", "ㄏㄠˇ-ㄆㄧㄠˋ-ㄌㄧㄤˋ", "好漂亮"),
        ("SELECT bpmf FROM pinyin WHERE py=?", "zhong", "ㄓㄨㄥ"),
        ("SELECT bpmf FROM pinyin WHERE py=?", "lv", "ㄌㄩ"),
        ("SELECT bpmf FROM pinyin WHERE py=?", "jue", "ㄐㄩㄝ"),
        ("SELECT bpmf FROM pinyin WHERE py=?", "shi", "ㄕ"),
        ("SELECT bpmf FROM pinyin WHERE py=?", "wo", "ㄨㄛ"),
    ]
    if t2s:
        checks.append(("SELECT simp FROM t2s WHERE trad=?", "灣", "湾"))
    for sql, arg, want in checks:
        got = top(sql, arg)
        print(arg, got)
        if want not in got:
            sys.exit("字典檢查失敗：%s 找不到 %s" % (arg, want))


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2], sys.argv[3:])
