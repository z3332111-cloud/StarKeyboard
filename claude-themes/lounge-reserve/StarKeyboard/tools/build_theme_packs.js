// 把 docs/previews/theme-gallery 的設計稿切成主題素材，放到 docs/theme-packs（鍵盤要用時才下載）
// 圖集 768×448：上面一排三顆鍵帽（各 256×256），下面一條寬鍵（768×192）。底色去掉（透明）。
// 用法：node tools/build_theme_packs.js
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const FFMPEG = process.env.FFMPEG || 'ffmpeg';
const root = path.join(__dirname, '..');
const out = path.join(root, 'docs/theme-packs');
const gallery = path.join(root, 'docs/previews/theme-gallery');

const THEMES = [
  { id: 'persimmon', tol: [9, 20], src: 'autumn-keyboards/persimmon.png', caps: [[23, 490, 390, 346], [430, 490, 392, 346], [840, 490, 390, 346]], wide: [45, 948, 1163, 270] },
  { id: 'observatory', src: 'autumn-keyboards/observatory.png', caps: [[26, 470, 382, 354], [432, 470, 384, 354], [840, 470, 386, 354]], wide: [51, 961, 1144, 231] },
  { id: 'railway', src: 'autumn-keyboards/railway.png', caps: [[19, 481, 389, 356], [428, 481, 388, 356], [838, 481, 406, 356]], wide: [82, 953, 1089, 259] },
  { id: 'pool', src: 'keyboard-collection/pool.png', caps: [[14, 497, 412, 419], [435, 497, 391, 419], [831, 497, 408, 419]], wide: [46, 1013, 1163, 199] },
  { id: 'fern', src: 'keyboard-collection/fern.png', caps: [[59, 441, 332, 470], [461, 440, 329, 473], [863, 441, 333, 472]], wide: [27, 989, 1201, 226] },
];
const CELL = 256, WIDE_H = 192, W = 768, H = 448;

function readRaw(file) {
  return execFileSync(FFMPEG, ['-hide_banner', '-loglevel', 'error', '-i', file, '-f', 'rawvideo', '-pix_fmt', 'rgba', '-'], { maxBuffer: 2e8 });
}

// 從裁切範圍的四邊開始，把連到邊框、顏色接近底色的地方變透明（鍵帽中間同色的地方不受影響）；
// 顏色和底色太近的主題（三花貓的白臉）要把 tol 調小，不然會一路漏進臉裡
function cut(src, sw, [x, y, w, h], [low, high] = [34, 60]) {
  const px = Buffer.alloc(w * h * 4);
  for (let r = 0; r < h; r++) src.copy(px, r * w * 4, ((y + r) * sw + x) * 4, ((y + r) * sw + x + w) * 4);
  const bed = [px[0], px[1], px[2]];
  const dist = i => Math.abs(px[i] - bed[0]) + Math.abs(px[i + 1] - bed[1]) + Math.abs(px[i + 2] - bed[2]);
  const seen = new Uint8Array(w * h);
  const stack = [];
  const push = (cx, cy) => { const k = cy * w + cx; if (!seen[k]) { seen[k] = 1; stack.push(k); } };
  for (let i = 0; i < w; i++) { push(i, 0); push(i, h - 1); }
  for (let i = 0; i < h; i++) { push(0, i); push(w - 1, i); }
  while (stack.length) {
    const k = stack.pop(), i = k * 4, d = dist(i);
    if (d > high) continue;
    px[i + 3] = d < low ? 0 : Math.round((d - low) / (high - low) * 255);
    const cx = k % w, cy = (k - cx) / w;
    if (cx > 0) push(cx - 1, cy);
    if (cx < w - 1) push(cx + 1, cy);
    if (cy > 0) push(cx, cy - 1);
    if (cy < h - 1) push(cx, cy + 1);
  }
  return { px, w, h };
}

function scale({ px, w, h }, tw, th) {
  return execFileSync(FFMPEG, ['-hide_banner', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgba', '-s', `${w}x${h}`, '-i', '-',
    '-vf', `scale=${tw}:${th}:flags=lanczos`, '-f', 'rawvideo', '-pix_fmt', 'rgba', '-'], { input: px, maxBuffer: 2e8 });
}

function blit(canvas, img, tw, th, x, y) {
  for (let r = 0; r < th; r++) img.copy(canvas, ((y + r) * W + x) * 4, r * tw * 4, (r + 1) * tw * 4);
}

// 保持比例放進方框，置中
function place(canvas, piece, bx, by, bw, bh) {
  const s = Math.min(bw / piece.w, bh / piece.h);
  const tw = Math.round(piece.w * s), th = Math.round(piece.h * s);
  blit(canvas, scale(piece, tw, th), tw, th, bx + Math.floor((bw - tw) / 2), by + Math.floor((bh - th) / 2));
}

fs.mkdirSync(out, { recursive: true });
for (const t of THEMES) {
  const file = path.join(gallery, t.src);
  const data = fs.readFileSync(file);
  const sw = data.readUInt32BE(16);
  const src = readRaw(file);
  const canvas = Buffer.alloc(W * H * 4);
  t.caps.forEach((rect, i) => place(canvas, cut(src, sw, rect, t.tol), i * CELL, 0, CELL, CELL));
  place(canvas, cut(src, sw, t.wide, t.tol), 0, CELL, W, WIDE_H);
  const target = path.join(out, `theme-${t.id}.png`);
  execFileSync(FFMPEG, ['-hide_banner', '-loglevel', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgba', '-s', `${W}x${H}`, '-i', '-', '-frames:v', '1', target], { input: canvas });
  console.log(path.basename(target), Math.round(fs.statSync(target).size / 1024) + 'KB');
}
// 小狐狸的三張圖也放這裡，App 裡不再內建
for (const name of ['keycaps-watercolor-v2', 'wide-keycaps-watercolor-v2', 'background-watercolor-v2']) {
  fs.copyFileSync(path.join(root, 'Keyboard/Resources/FoxLetter', name + '.png'), path.join(out, name + '.png'));
}
