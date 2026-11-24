// 產生按鍵音（程式合成，原創，不用授權）：node tools/make_sounds.js
// 輸出到 Android 的 res/raw 和 iPhone 的 Keyboard/Resources/Sounds
const fs = require("fs");
const path = require("path");

const RATE = 22050;

function wav(samples, rate = RATE) {
  const data = Buffer.alloc(samples.length * 2);
  samples.forEach((v, i) => data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, v)) * 32767), i * 2));
  const h = Buffer.alloc(44);
  h.write("RIFF", 0); h.writeUInt32LE(36 + data.length, 4); h.write("WAVE", 8);
  h.write("fmt ", 12); h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22);
  h.writeUInt32LE(rate, 24); h.writeUInt32LE(rate * 2, 28); h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34);
  h.write("data", 36); h.writeUInt32LE(data.length, 40);
  return Buffer.concat([h, data]);
}

/** 合成：freq(t) 是每個時間點的頻率，partials 是 [倍數, 音量]，tau 是衰減時間 */
function synth({ ms, freq, partials = [[1, 1]], tau, attack = 0.004, peak = 0.6 }) {
  const n = Math.round(RATE * ms / 1000);
  const out = new Array(n);
  const phase = partials.map(() => 0);
  for (let i = 0; i < n; i++) {
    const t = i / RATE;
    const env = Math.min(1, t / attack) * Math.exp(-t / tau);
    let v = 0;
    partials.forEach(([mult, amp], j) => {
      phase[j] += 2 * Math.PI * freq(t) * mult / RATE;
      v += Math.sin(phase[j]) * amp;
    });
    out[i] = v * env;
  }
  // 結尾淡出，避免喀一聲
  const fade = Math.round(RATE * 0.01);
  for (let i = 0; i < fade; i++) out[n - 1 - i] *= i / fade;
  const max = Math.max(...out.map(Math.abs)) || 1;
  return out.map((v) => v / max * peak);
}

const sounds = {
  // 短促、低音量的柔和叮聲，連續輸入時不拖尾。
  key_tink: synth({ ms: 45, freq: () => 1046, partials: [[1, 1], [2, 0.08]], tau: 0.012, attack: 0.002, peak: 0.2 }),
  // 泡泡：音高快速往上滑
  key_bubble: synth({ ms: 90, freq: (t) => 320 + 900 * Math.min(1, t / 0.07), partials: [[1, 1], [2, 0.15]], tau: 0.035 }),
  // 木琴：短短的木頭聲
  key_marimba: synth({ ms: 170, freq: () => 784, partials: [[1, 1], [4, 0.35], [9.2, 0.08]], tau: 0.05, attack: 0.002 }),
  // 叮鈴：小鈴鐺
  key_bell: synth({ ms: 230, freq: () => 1568, partials: [[1, 1], [2.76, 0.4], [5.4, 0.18]], tau: 0.08, attack: 0.002, peak: 0.45 }),
  // 啵啵：音高往下掉的小氣泡破掉聲
  key_pop: synth({ ms: 80, freq: (t) => 950 - 700 * Math.min(1, t / 0.04), partials: [[1, 1]], tau: 0.025, attack: 0.002 }),
};

// ===== 機械鍵盤和敲擊聲 =====
// 一顆鍵的聲音＝幾個「事件」疊在一起：一小段濾過的雜音（塑膠碰撞的沙沙聲）＋幾個會衰減的共振（鍵帽、底板、外殼）。
// 每種做 5 個稍微不一樣的版本輪流播（連打不會像機關槍），再做一個給空白、換行、刪除這些大鍵用的低沉版。
const MECH_RATE = 44100;

/** 固定種子的亂數，每次產生的檔案都一樣 */
function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** RBJ 雙二階濾波器：type = lp（低通）、hp（高通）、bp（帶通） */
function filter(x, type, f, q = 0.707) {
  const w = 2 * Math.PI * Math.min(f, MECH_RATE * 0.45) / MECH_RATE;
  const cos = Math.cos(w), alpha = Math.sin(w) / (2 * q);
  let b0, b1, b2;
  if (type === "lp") { b0 = (1 - cos) / 2; b1 = 1 - cos; b2 = b0; }
  else if (type === "hp") { b0 = (1 + cos) / 2; b1 = -(1 + cos); b2 = b0; }
  else { b0 = alpha; b1 = 0; b2 = -alpha; }
  const a0 = 1 + alpha, a1 = -2 * cos, a2 = 1 - alpha;
  const y = new Float64Array(x.length);
  let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
  for (let i = 0; i < x.length; i++) {
    const v = (b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0;
    x2 = x1; x1 = x[i]; y2 = y1; y1 = v; y[i] = v;
  }
  return y;
}

/**
 * 一個敲擊事件
 * at：幾毫秒開始；amp：音量
 * noise：[濾波種類, 頻率, Q, 衰減秒數]，碰撞的雜音
 * modes：[[頻率, 音量, 衰減秒數], ...]，碰完之後的共振
 */
function hit(buf, r, { at = 0, amp = 1, noise, modes = [] }) {
  const start = Math.round(MECH_RATE * at / 1000);
  const len = buf.length - start;
  if (len <= 0) return;
  const part = new Float64Array(len);
  if (noise) {
    const [type, f, q, tau] = noise;
    const raw = new Float64Array(len);
    for (let i = 0; i < len; i++) raw[i] = (r() * 2 - 1) * Math.exp(-i / MECH_RATE / tau);
    const filtered = filter(raw, type, f, q);
    // 濾波會讓音量差很多，先把雜音自己的最大值調到 1
    let m = 0;
    for (const v of filtered) m = Math.max(m, Math.abs(v));
    for (let i = 0; i < len; i++) part[i] += filtered[i] / (m || 1);
  }
  for (const [f, a, tau] of modes) {
    const ph = r() * Math.PI * 2;
    for (let i = 0; i < len; i++) {
      const t = i / MECH_RATE;
      part[i] += Math.sin(2 * Math.PI * f * t + ph) * a * Math.exp(-t / tau);
    }
  }
  // 0.4 毫秒淡入，避免數位的「啪」
  const atk = Math.round(MECH_RATE * 0.0004);
  for (let i = 0; i < len; i++) buf[start + i] += part[i] * amp * Math.min(1, i / atk);
}

function render(ms, peak, events, seed) {
  const r = rng(seed);
  const buf = new Float64Array(Math.round(MECH_RATE * ms / 1000));
  for (const e of events) hit(buf, r, e);
  const fade = Math.round(MECH_RATE * 0.012);
  for (let i = 0; i < fade; i++) buf[buf.length - 1 - i] *= i / fade;
  let m = 0;
  for (const v of buf) m = Math.max(m, Math.abs(v));
  return Array.from(buf, (v) => v / (m || 1) * peak);
}

/**
 * 每種軸：make(j) 回傳事件清單。j 是 { f: 頻率倍數, t: 時間偏移, a: 音量倍數, big: 是不是大鍵 }
 * 大鍵：音高低一點、尾巴長一點，再加一點衛星軸的「喀啦」
 */
// 機械鍵盤軸改用真實錄音（tools/import_switch_sounds.py，kbsim，MIT）；這裡只剩不是鍵盤的趣味音
const switches = {
  // 麻將：兩張牌碰在一起「喀喀」，硬硬的高音
  mahjong: { ms: 120, peak: 0.5, make: (j) => [
    { amp: 1 * j.a, noise: ["hp", 2200 * j.f, 0.8, 0.0015], modes: [[2380 * j.f, 0.6, 0.014], [3950 * j.f, 0.45, 0.01], [5620 * j.f, 0.3, 0.008], [7400 * j.f, 0.15, 0.005]] },
    { at: 24 + j.t * 3, amp: 0.5 * j.a, noise: ["hp", 2400 * j.f, 0.8, 0.0012], modes: [[2450 * j.f, 0.5, 0.012], [4080 * j.f, 0.35, 0.008], [5800 * j.f, 0.2, 0.006]] },
  ] },
  // 木魚：空心木頭「叩」
  woodfish: { ms: 200, peak: 0.5, make: (j) => [
    { amp: 1 * j.a, noise: ["bp", 1800 * j.f, 1.2, 0.0015], modes: [[480 * j.f, 1, 0.045 * j.l], [1290 * j.f, 0.35, 0.016], [2410 * j.f, 0.15, 0.008]] },
  ] },
};

// 5 個版本（和真實錄音一樣多）：音高、時間、音量各差一點點
const variants = [
  { f: 1, t: 0, a: 1, l: 1 },
  { f: 1.035, t: 1.5, a: 0.92, l: 0.95 },
  { f: 0.97, t: -1, a: 0.96, l: 1.05 },
  { f: 1.015, t: 0.8, a: 0.97, l: 1 },
  { f: 0.985, t: -0.5, a: 0.94, l: 1.02 },
];
const BIG = { f: 0.82, t: 2, a: 1, l: 1.35 };

const mech = {};
let seed = 1;
for (const [id, sw] of Object.entries(switches)) {
  variants.forEach((v, i) => {
    mech[`key_${id}_${i + 1}`] = render(sw.ms, sw.peak, sw.make(v), seed++);
  });
  // 大鍵：多一點長度、加一下衛星軸的喀啦
  const bigEvents = sw.make(BIG).concat([{ at: 7, amp: 0.18, noise: ["bp", 1700, 1.4, 0.003] }]);
  mech[`key_${id}_big`] = render(Math.round(sw.ms * 1.25), Math.min(0.6, sw.peak * 1.1), bigEvents, seed++);
}

const root = path.join(__dirname, "..");
const dirs = [path.join(root, "android/app/src/main/res/raw"), path.join(root, "Keyboard/Resources/Sounds")];
for (const dir of dirs) {
  fs.mkdirSync(dir, { recursive: true });
  for (const [name, samples] of Object.entries(sounds)) {
    fs.writeFileSync(path.join(dir, name + ".wav"), wav(samples));
  }
  for (const [name, samples] of Object.entries(mech)) {
    fs.writeFileSync(path.join(dir, name + ".wav"), wav(samples, MECH_RATE));
  }
}
// 網站預覽用（docs/assets/sounds）
const webDir = path.join(root, "docs/assets/sounds");
fs.mkdirSync(webDir, { recursive: true });
for (const [name, samples] of Object.entries(mech)) {
  if (name.endsWith("_1")) fs.writeFileSync(path.join(webDir, name.replace(/^key_|_1$/g, "") + ".wav"), wav(samples, MECH_RATE));
}
console.log("ok", Object.keys(sounds).concat(Object.keys(mech)).join(" "));
