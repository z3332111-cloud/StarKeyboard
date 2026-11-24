#!/usr/bin/env python3
"""機械鍵盤軸的真實錄音：從 kbsim（kbs.im，Thomas Lai，MIT 授權）轉成鍵盤用的 wav。

用法：
  git clone --depth 1 https://github.com/tplai/kbsim /tmp/kbsim
  python3 tools/import_switch_sounds.py /tmp/kbsim

需要 ffmpeg 和 numpy。輸出到 iPhone 的 Keyboard/Resources/Sounds、Android 的 res/raw，
網站試聽用的放 docs/assets/sounds（每種一個）。

每種軸：
- 按下去：一般鍵 5 個（kbsim 鍵盤每一排的錄音，輪流播），大鍵 1 個（空白鍵的錄音）
- 放開：一般鍵 1 個、大鍵 1 個（真的機械鍵盤彈回來還有一聲，比較小聲）
去掉開頭的空白、統一音量、結尾淡出。

kbsim 的錄音偏尖、偏薄（聲音重心約 4.5～5 kHz）。手機喇叭小，尖的聲音聽起來像塑膠喀喀，
所以把 3 kHz 以上壓低、400 Hz 附近加厚，重心降到 2～3 kHz，聽起來比較像「咚咚」的實體鍵盤。
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
    # 音量（最大值）：0.8 在 iPhone 喇叭上太炸、會破音，降到 0.35 左右
    "red": ("redink", 0.35, None),          # Gateron 紅墨軸（線性）
    "brown": ("mxbrown", 0.35, None),       # Cherry MX 茶軸
    "blue": ("mxblue", 0.32, None),         # Cherry MX 青軸（本來就響，再小一點）
    "black": ("mxblack", 0.35, None),       # Cherry MX 黑軸
    "silent": ("mxblack", 0.18, 900),       # 靜音軸：黑軸錄音悶住、調小聲（kbsim 沒有靜音軸）
    "cream": ("cream", 0.35, None),         # NovelKeys 奶油軸
    "holypanda": ("holypanda", 0.35, None), # 熊貓軸
    "topre": ("topre", 0.35, None),         # 靜電容
    "buckling": ("buckling", 0.3, None),    # IBM 彈簧老鍵盤（很響）
    "alpaca": ("alpaca", 0.35, None),       # 羊駝軸（線性）
    "blackink": ("blackink", 0.35, None),   # Gateron 黑墨軸（線性、偏低沉）
    "turquoise": ("turquoise", 0.35, None), # Tealios 湖水綠軸（線性）
    "boxnavy": ("boxnavy", 0.3, None),      # Kailh BOX 海軍軸（很響的有聲軸）
    "bluealps": ("bluealps", 0.32, None),   # SKCM 藍色 Alps（老式有聲軸）
}


def decode(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(RATE), "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def biquad(x, kind, f, gain_db=0.0, q=0.707):
    """RBJ 濾波器：shelf_hi（高頻架）、peak（某個頻率加減）"""
    A = 10 ** (gain_db / 40)
    w = 2 * np.pi * f / RATE
    cos, alpha = np.cos(w), np.sin(w) / (2 * q)
    if kind == "hp":
        b = [(1 + cos) / 2, -(1 + cos), (1 + cos) / 2]
        a = [1 + alpha, -2 * cos, 1 - alpha]
    elif kind == "peak":
        b = [1 + alpha * A, -2 * cos, 1 - alpha * A]
        a = [1 + alpha / A, -2 * cos, 1 - alpha / A]
    else:  # shelf_hi
        sq = 2 * np.sqrt(A) * alpha
        b = [A * ((A + 1) + (A - 1) * cos + sq), -2 * A * ((A - 1) + (A + 1) * cos), A * ((A + 1) + (A - 1) * cos - sq)]
        a = [(A + 1) - (A - 1) * cos + sq, 2 * ((A - 1) - (A + 1) * cos), (A + 1) - (A - 1) * cos - sq]
    b = [v / a[0] for v in b]
    a = [v / a[0] for v in a]
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i, v in enumerate(x):
        out = b[0] * v + b[1] * x1 + b[2] * x2 - a[1] * y1 - a[2] * y2
        x2, x1, y2, y1 = x1, v, y1, out
        y[i] = out
    return y


def warm(x):
    """壓掉尖的高頻、中低頻稍微加厚（像實體鍵盤的外殼共鳴）。
    手機小喇叭放不出 150 Hz 以下，硬推會破音，所以先切掉；中低頻也只加一點點。"""
    x = biquad(x, "hp", 150)
    x = biquad(x, "shelf_hi", 3000, -8)
    x = biquad(x, "peak", 450, 2.5, 0.9)
    return biquad(x, "peak", 1300, 1.5, 1.0)


def centroid(x):
    s = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    f = np.fft.rfftfreq(len(x), 1 / RATE)
    return float((s * f).sum() / (s.sum() or 1))


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
    x = warm(x)
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
        big = clean(decode(space), peak * 1.05, muffle) if os.path.exists(space) else normal[2]
        # 放開：音量大約是按下去的三分之一（照實體鍵盤錄音量的比例）
        release = os.path.join(audio, folder, "release")
        up = clean(decode(os.path.join(release, "GENERIC.mp3")), peak * 0.35, muffle)
        up_space = os.path.join(release, "SPACE.mp3")
        up_big = clean(decode(up_space), peak * 0.4, muffle) if os.path.exists(up_space) else up
        for d in OUT_DIRS:
            for i, x in enumerate(normal):
                write_wav(os.path.join(d, "key_%s_%d.wav" % (name, i + 1)), x)
            write_wav(os.path.join(d, "key_%s_big.wav" % name), big)
            write_wav(os.path.join(d, "key_%s_up.wav" % name), up)
            write_wav(os.path.join(d, "key_%s_up_big.wav" % name), up_big)
        # 網站試聽：按下去＋0.1 秒後放開，跟真的按一下一樣
        gap = np.zeros(int(RATE * 0.1) - len(normal[0])) if len(normal[0]) < RATE * 0.1 else np.zeros(0)
        write_wav(os.path.join(WEB_DIR, name + ".wav"), np.concatenate([normal[0], gap, up]))
        print(name, "←", folder, "重心 %d Hz" % centroid(normal[0]))
    # MIT 授權要附上原本的版權聲明
    shutil.copy(os.path.join(kbsim, "LICENSE.md"), os.path.join(OUT_DIRS[0], "kbsim-LICENSE.txt"))
    shutil.copy(os.path.join(kbsim, "LICENSE.md"), os.path.join(OUT_DIRS[1], "kbsim_license.txt"))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1])
