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

// 機械鍵盤軸改用真實錄音，要用時才下載：tools/import_switch_sounds.py（kbsim，MIT）

const root = path.join(__dirname, "..");
const dirs = [path.join(root, "android/app/src/main/res/raw"), path.join(root, "Keyboard/Resources/Sounds")];
for (const dir of dirs) {
  fs.mkdirSync(dir, { recursive: true });
  for (const [name, samples] of Object.entries(sounds)) {
    fs.writeFileSync(path.join(dir, name + ".wav"), wav(samples));
  }
}
console.log("ok", Object.keys(sounds).join(" "));
