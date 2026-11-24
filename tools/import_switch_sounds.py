#!/usr/bin/env python3
"""機械鍵盤軸的真實錄音：從 kbsim（kbs.im，Thomas Lai，MIT 授權）轉成鍵盤用的 wav。

用法：
  git clone --depth 1 https://github.com/tplai/kbsim /tmp/kbsim
  python3 tools/import_switch_sounds.py /tmp/kbsim

需要 ffmpeg 和 numpy。輸出到 iPhone 的 Keyboard/Resources/Sounds、Android 的 res/raw，
網站試聽用的放 docs/assets/sounds（每種一個）。

每種軸：一般鍵 5 個（kbsim 鍵盤每一排的錄音，輪流播），大鍵 1 個（空白鍵的錄音）。
只取「按下去」的聲音；去掉開頭的空白、統一音量、結尾淡出。
"""
import os
import shutil
import subprocess
import sys

import numpy as np

RATE = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT_DIRS = [os.path.join(ROOT, "Keyboard/Resources/Sounds"), os.path.join(ROOT, "android/app/src/main/res/raw")]
WEB_DIR = os.path.join(ROOT, "docs/assets/sounds")

# 鍵盤裡的名字 → kbsim 的資料夾、音量（最大值）、要不要悶住（靜音軸）
SWITCHES = {
    "red": ("redink", 0.5, None),          # Gateron 紅墨軸（線性）
    "brown": ("mxbrown", 0.5, None),       # Cherry MX 茶軸
    "blue": ("mxblue", 0.55, None),        # Cherry MX 青軸
    "black": ("mxblack", 0.5, None),       # Cherry MX 黑軸
    "silent": ("mxblack", 0.2, 900),       # 靜音軸：黑軸錄音悶住、調小聲（kbsim 沒有靜音軸）
    "cream": ("cream", 0.5, None),         # NovelKeys 奶油軸
    "holypanda": ("holypanda", 0.5, None), # 熊貓軸
    "topre": ("topre", 0.5, None),         # 靜電容
    "buckling": ("buckling", 0.55, None),  # IBM 彈簧老鍵盤
}


def decode(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(RATE), "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def lowpass(x, cutoff):
    # 一階低通跑兩次，讓聲音悶一點（像有消音墊）
    a = np.exp(-2 * np.pi * cutoff / RATE)
    for _ in range(2):
        y = np.empty_like(x)
        prev = 0.0
        for i, v in enumerate(x):
            prev = (1 - a) * v + a * prev
            y[i] = prev
        x = y
    return x


def clean(x, peak, muffle):
    top = np.max(np.abs(x)) or 1
    onset = int(np.argmax(np.abs(x) > top * 0.08))
    x = x[max(0, onset - int(RATE * 0.001)):]          # 留 1 毫秒，聲音一按就出來
    x = x[: int(RATE * 0.18)]                            # 最長 0.18 秒
    if muffle:
        x = lowpass(x, muffle)
    fade = min(len(x), int(RATE * 0.012))
    x[-fade:] *= np.linspace(1, 0, fade)
    return x / (np.max(np.abs(x)) or 1) * peak


def write_wav(path, x):
    data = (np.clip(x, -1, 1) * 32767).round().astype("<i2").tobytes()
    header = b"RIFF" + (36 + len(data)).to_bytes(4, "little") + b"WAVEfmt " + (16).to_bytes(4, "little")
    header += (1).to_bytes(2, "little") + (1).to_bytes(2, "little") + RATE.to_bytes(4, "little")
    header += (RATE * 2).to_bytes(4, "little") + (2).to_bytes(2, "little") + (16).to_bytes(2, "little")
    header += b"data" + len(data).to_bytes(4, "little")
    with open(path, "wb") as f:
        f.write(header + data)


def main(kbsim):
    audio = os.path.join(kbsim, "src/assets/audio")
    for d in OUT_DIRS + [WEB_DIR]:
        os.makedirs(d, exist_ok=True)
    for name, (folder, peak, muffle) in SWITCHES.items():
        press = os.path.join(audio, folder, "press")
        normal = [clean(decode(os.path.join(press, "GENERIC_R%d.mp3" % i)), peak, muffle) for i in range(5)]
        # 空白鍵的錄音當大鍵；青軸沒有，就用中間那排的一般鍵
        space = os.path.join(press, "SPACE.mp3")
        big = clean(decode(space), min(0.6, peak * 1.1), muffle) if os.path.exists(space) else normal[2]
        for d in OUT_DIRS:
            for i, x in enumerate(normal):
                write_wav(os.path.join(d, "key_%s_%d.wav" % (name, i + 1)), x)
            write_wav(os.path.join(d, "key_%s_big.wav" % name), big)
        write_wav(os.path.join(WEB_DIR, name + ".wav"), normal[0])
        print(name, "←", folder)
    # MIT 授權要附上原本的版權聲明
    shutil.copy(os.path.join(kbsim, "LICENSE.md"), os.path.join(OUT_DIRS[0], "kbsim-LICENSE.txt"))
    shutil.copy(os.path.join(kbsim, "LICENSE.md"), os.path.join(OUT_DIRS[1], "kbsim_license.txt"))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1])
