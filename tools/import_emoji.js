// 用 Unicode 官方的 emoji-test.txt 產生 symbol_data.txt 的「# emoji」那一段（全部表情符號、不含膚色變化）。
// 用法：node tools/import_emoji.js <emoji-test.txt>
// 版本要配合最舊支援的系統：iOS 15.0 看得到 Emoji 13.1（https://unicode.org/Public/emoji/13.1/emoji-test.txt）
const fs = require('fs');
const path = require('path');
const titles = {
  'Smileys & Emotion': '😀', 'People & Body': '👋', 'Animals & Nature': '🐶', 'Food & Drink': '🍓',
  'Travel & Places': '🚗', 'Activities': '⚽', 'Objects': '💡', 'Symbols': '❤️', 'Flags': '🏳️',
};
const src = fs.readFileSync(process.argv[2], 'utf8');
const groups = [];
let cur = null;
for (const line of src.split(/\r?\n/)) {
  const g = line.match(/^# group: (.+)$/);
  if (g) { cur = titles[g[1]] ? { title: titles[g[1]], items: [] } : null; if (cur) groups.push(cur); continue; }
  if (!cur || line.startsWith('#') || !line.trim()) continue;
  const m = line.match(/^([0-9A-F ]+);\s*fully-qualified\s*#\s*(\S+)/);
  if (!m) continue;
  const cps = m[1].trim().split(' ').map(h => parseInt(h, 16));
  if (cps.some(c => c >= 0x1F3FB && c <= 0x1F3FF)) continue;   // 膚色變化不列（太多）
  cur.items.push(String.fromCodePoint(...cps));
}
const block = '# emoji\n' + groups.map(g => '== ' + g.title + '\n' + chunk(g.items).join('\n')).join('\n') + '\n';
function chunk(a) { const out = []; for (let i = 0; i < a.length; i += 30) out.push(a.slice(i, i + 30).join(' ')); return out; }
const file = path.join(__dirname, 'symbol_data.txt');
let data = fs.readFileSync(file, 'utf8');
// 拿掉所有舊的 # emoji 段落，再把新的放在最前面
data = data.replace(/(^|\n)(\/\/[^\n]*\n)?# emoji\n[\s\S]*?(?=\n(\/\/[^\n]*\n)?# |\s*$)/g, '\n');
data = '// ===== 表情符號（由 tools/import_emoji.js 從 Unicode 官方清單產生） =====\n' + block + '\n' + data.trim() + '\n';
fs.writeFileSync(file, data);
for (const g of groups) console.log(g.title, g.items.length);
