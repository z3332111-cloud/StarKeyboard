#!/usr/bin/env python3
"""下載字體／字體 ZIP；來源失敗時切換備援，驗證成功後才取代輸出。

python3 tools/download_font.py [--sha256 HASH] OUTPUT URL [FALLBACK_URL ...]
只使用 Python 標準函式庫與 curl，可在 Linux、macOS 執行。
"""

import argparse
import hashlib
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import zipfile


def validate(path, suffix, sha256):
    if sha256:
        digest = hashlib.sha256()
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
        if digest.hexdigest() != sha256.lower():
            raise ValueError("SHA-256 不符")

    if suffix == ".zip":
        with zipfile.ZipFile(path) as archive:
            if not any(name.lower().endswith((".ttf", ".otf")) for name in archive.namelist()):
                raise ValueError("ZIP 裡沒有字體")
            if archive.testzip() is not None:
                raise ValueError("ZIP 內容損壞")
        return

    # 檢查 SFNT 表目錄與每個表的範圍，避免把 HTML 錯誤頁或截斷檔案交給縮字工具。
    size = path.stat().st_size
    with path.open("rb") as source:
        header = source.read(12)
        if len(header) != 12 or header[:4] not in (b"\x00\x01\x00\x00", b"OTTO", b"true"):
            raise ValueError("不是 TTF／OTF 字體")
        table_count = struct.unpack(">H", header[4:6])[0]
        directory_end = 12 + table_count * 16
        if not table_count or directory_end > size:
            raise ValueError("字體表目錄不完整")
        for _ in range(table_count):
            _, _, offset, length = struct.unpack(">4sIII", source.read(16))
            if offset < directory_end or offset + length > size:
                raise ValueError("字體表資料不完整")


def download(output, urls, sha256=None):
    output.parent.mkdir(parents=True, exist_ok=True)
    # 同一個檔案系統內取代檔案；失敗時保留原檔且清除所有未完成下載。
    with tempfile.TemporaryDirectory(prefix=f".{output.name}-", dir=output.parent) as scratch:
        partial = Path(scratch) / "download"
        for index, url in enumerate(urls, 1):
            partial.unlink(missing_ok=True)
            print(f"下載字體：{output.name}，來源 {index}/{len(urls)}：{url}", flush=True)
            result = subprocess.run([
                "curl", "-sSfL", "--retry", "4", "--retry-delay", "3",
                "--retry-max-time", "180", "--connect-timeout", "20", "--max-time", "120",
                "-o", str(partial), url,
            ])
            if result.returncode:
                print(f"來源下載失敗（curl {result.returncode}），嘗試下一個來源。", file=sys.stderr)
                continue
            try:
                validate(partial, output.suffix.lower(), sha256)
            except (OSError, ValueError, zipfile.BadZipFile, EOFError) as error:
                print(f"來源驗證失敗：{error}，嘗試下一個來源。", file=sys.stderr)
                continue
            partial.replace(output)
            print(f"字體下載及驗證完成：{output.name}", flush=True)
            return
    raise RuntimeError(f"{output.name} 的所有下載來源均失敗；停止打包。")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sha256")
    parser.add_argument("output", type=Path)
    parser.add_argument("urls", nargs="+")
    args = parser.parse_args()
    try:
        download(args.output, args.urls, args.sha256)
    except (OSError, RuntimeError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
