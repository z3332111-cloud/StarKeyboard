#!/usr/bin/env bash
# 把安裝網站（docs/ 裡給大家看的部分）複製到公開的 nuonuo-keyboard 倉庫。
# 用法：tools/publish_site.sh <nuonuo-keyboard 的資料夾>
# 只複製網頁、圖、聲音和主題包；開發筆記（*.md 設計稿、效能紀錄）和 previews/ 不公開。
set -euo pipefail
SRC="$(cd "$(dirname "$0")/../docs" && pwd)"
DST="${1:?要給 nuonuo-keyboard 的資料夾}"
[ -d "$DST/.git" ] || { echo "$DST 不是 git 資料夾"; exit 1; }

# 先清掉舊的網站檔案（保留 .git）
find "$DST" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +

cp "$SRC"/index.html "$SRC"/*.css "$SRC"/*.js "$DST"/
cp -R "$SRC"/assets "$SRC"/sim-fox "$SRC"/theme-packs "$DST"/
cp "$SRC"/privacy.md "$DST"/privacy.md
# 不經過 Jekyll，檔案原樣放上 GitHub Pages
touch "$DST/.nojekyll"
cat > "$DST/README.md" <<'MD'
# 糯糯鍵盤

iPhone／Android 的可愛注音鍵盤。

- 安裝網站（功能介紹、試玩、安裝教學）：https://z3332111-cloud.github.io/nuonuo-keyboard/
- 下載安裝檔：右邊的 **Releases**（iPhone 下載 `StarKeyboard.ipa`，Android 下載 `StarKeyboard.apk`）
- 隱私說明：[privacy.md](privacy.md)

這個倉庫只放安裝網站和安裝檔，網站內容會在每次發佈新版時自動更新。
MD
echo "網站檔案已複製到 $DST"
