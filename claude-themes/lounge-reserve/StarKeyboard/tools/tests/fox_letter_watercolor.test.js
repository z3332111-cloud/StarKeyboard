'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { atlas, spriteIndex, imageSlices } = require('../fox_letter_watercolor');

test('水彩圖集與背景為實際存在的 PNG 素材，透明圖集支援九個格位', () => {
  const directory = path.resolve(__dirname, '../../docs/previews/fox-letter');
  for (const file of [atlas.keycaps, atlas.wideKeycaps, atlas.backdrop]) {
    const data = fs.readFileSync(path.resolve(directory, file));
    assert.equal(data.subarray(1, 4).toString(), 'PNG');
    assert(data.readUInt32BE(16) > 0 && data.readUInt32BE(20) > 0);
    if (file === atlas.keycaps) {
      assert.equal(data[25], 6, '鍵帽必須保留 RGBA 透明背景');
      assert.equal(data.readUInt32BE(16) % 3, 0);
      assert.equal(data.readUInt32BE(20) % 3, 0);
    }
  }
});

test('九款帽子、楓葉、圍巾與信封變體皆會出現；同位置選擇固定', () => {
  const seen = new Set();
  for (let i = 0; i < 90; i++) {
    const sprite = spriteIndex(i, 'text');
    assert(sprite >= 0 && sprite < 9);
    assert.equal(sprite, spriteIndex(i, 'text'));
    seen.add(sprite);
  }
  assert.equal(seen.size, 9);
  assert.equal(spriteIndex(0, 'space', true), 3);
});

test('寬鍵的圖集取樣不越界，耳朵端部與中央五官尺寸不隨鍵寬增加', () => {
  for (let sprite = 0; sprite < 9; sprite++) {
    let original;
    for (const width of [80, 160, 240]) {
      const frame = { x: 2, y: 2, width, height: 42 };
      const parts = imageSlices(frame, sprite);
      assert.equal(parts.length, 5);
      assert(Math.abs(parts.reduce((sum, p) => sum + p.frame.width, 0) - width) < .001);
      for (const p of parts) {
        assert(p.frame.width > 0);
        assert(p.source.x >= 0 && p.source.y >= 0 && p.source.width > 0 && p.source.height > 0);
        assert(p.source.x + p.source.width <= 1.00001 && p.source.y + p.source.height <= 1.00001);
      }
      if (original) for (const index of [0, 2, 4]) assert.equal(parts[index].frame.width, original[index].frame.width);
      original = parts;
    }
  }
});
