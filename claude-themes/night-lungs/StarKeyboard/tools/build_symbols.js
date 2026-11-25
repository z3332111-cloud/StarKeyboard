// 表符、顏文字、特殊符號的清單只寫在 tools/symbol_data.txt 一個地方，
// 這支程式產生 iPhone（SymbolData.swift）和 Android（SymbolData.kt）兩份，兩邊內容一定一樣。
// 用法：node tools/build_symbols.js
//
// symbol_data.txt 的格式：
//   # emoji / # kaomoji / # symbols   開始一組
//   == 分類名稱                        開始一個分類
//   表情符號、特殊符號：一行可以放好幾個，用空白隔開
//   顏文字：一行一個（顏文字裡面本來就有空白）
const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..');
const src = fs.readFileSync(path.join(__dirname, 'symbol_data.txt'), 'utf8');

const groups = { emoji: [], kaomoji: [], symbols: [] };
let group = null, cat = null;
for (const raw of src.split(/\r?\n/)) {
  const line = raw.trim();
  if (!line || line.startsWith('//')) continue;
  const g = line.match(/^# (emoji|kaomoji|symbols)$/);
  if (g) { group = groups[g[1]]; cat = null; continue; }
  const c = line.match(/^== (.+)$/);
  if (c) {
    // 同一個分類可以分好幾段寫，會合在一起
    cat = group.find(x => x.title === c[1].trim());
    if (!cat) { cat = { title: c[1].trim(), items: [] }; group.push(cat); }
    continue;
  }
  if (!cat) throw new Error('沒有分類就出現內容：' + line);
  const items = group === groups.kaomoji ? [line] : line.split(/\s+/);
  // 同一組裡重複的只留第一次出現的（顏文字很容易在好幾類都放一次）
  for (const it of items) if (!group.some(c => c.items.includes(it))) cat.items.push(it);
}
for (const [name, cats] of Object.entries(groups)) {
  if (!cats.length) throw new Error('沒有 ' + name);
  for (const c of cats) if (!c.items.length) throw new Error('空的分類：' + c.title);
}

const esc = s => JSON.stringify(s);   // JSON 字串在 Swift 和 Kotlin 都能用（Kotlin 另外跳脫 $）
const ktEsc = s => esc(s).replace(/\$/g, '\$');

function swiftGroup(name, cats) {
  return `    static let ${name}: [SymbolCategory] = [\n` + cats.map(c =>
    `        SymbolCategory(title: ${esc(c.title)}, items: [\n` +
    c.items.map(i => `            ${esc(i)},`).join('\n') + `\n        ]),`).join('\n') + `\n    ]\n`;
}
function ktGroup(name, cats) {
  return `    val ${name} = listOf(\n` + cats.map(c =>
    `        SymbolCategory(${ktEsc(c.title)}, listOf(\n` +
    c.items.map(i => `            ${ktEsc(i)},`).join('\n') + `\n        )),`).join('\n') + `\n    )\n`;
}
const header = '由 tools/symbol_data.txt 產生（node tools/build_symbols.js），不要直接改這個檔案';
const swift = `import Foundation\n\n// ${header}\n\nstruct SymbolCategory {\n    let title: String\n    let items: [String]\n}\n\n/// 表符、顏文字、特殊符號的內建清單\nenum SymbolData {\n` +
  swiftGroup('emoji', groups.emoji) + '\n' + swiftGroup('kaomoji', groups.kaomoji) + '\n' + swiftGroup('symbols', groups.symbols) + '}\n';
const kt = `package com.startown.starkeyboard.core\n\n// ${header}\n\ndata class SymbolCategory(val title: String, val items: List<String>)\n\nobject SymbolData {\n` +
  ktGroup('emoji', groups.emoji) + '\n' + ktGroup('kaomoji', groups.kaomoji) + '\n' + ktGroup('symbols', groups.symbols) + '}\n';
fs.writeFileSync(path.join(root, 'Core/Sources/KeyboardCore/SymbolData.swift'), swift);
fs.writeFileSync(path.join(root, 'android/app/src/main/java/com/startown/starkeyboard/core/SymbolData.kt'), kt);
for (const [name, cats] of Object.entries(groups)) {
  console.log(name + '：' + cats.length + ' 類、' + cats.reduce((a, c) => a + c.items.length, 0) + ' 個');
}
