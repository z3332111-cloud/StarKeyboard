'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { source, layers, geometry, svgPath, outputs } = require('../build_fox_letter_prototype');

const maxY = r => r.y + r.height;
const overlap = (a, b) => a.x < b.x + b.width && b.x < a.x + a.width && a.y < maxY(b) && b.y < maxY(a);

test('文字與提示字不占用五官區：窄鍵、注音、寬鍵及高度上下限', () => {
  for (const [width, baseHeight] of [[28, 38], [34, 48], [36, 46], [48, 42], [160, 46], [240, 36]]) {
    for (const scale of [0.8, 1, 1.3]) {
      const g = geometry(width, baseHeight * scale);
      assert(!overlap(g.label, g.face), `${width} × ${baseHeight * scale}：主要文字撞到五官`);
      assert(!overlap(g.hint, g.label), '提示字撞到主要文字');
      assert(!overlap(g.hint, g.face), '提示字撞到五官');
      assert(g.face.y > g.frame.y + g.frame.height * 0.7, '五官必須留在臉形下緣');
      for (const rect of [g.label, g.hint, g.face]) {
        assert(rect.width > 0 && rect.height > 0);
        assert(rect.x >= 0 && rect.y >= 0 && rect.x + rect.width <= width && maxY(rect) <= baseHeight * scale);
      }
    }
  }
});

test('寬鍵不能把五官與耳朵一起水平拉長', () => {
  const normal = geometry(48, 46), wide = geometry(160, 46), veryWide = geometry(240, 46);
  assert.equal(normal.face.width, wide.face.width);
  assert.equal(wide.face.width, veryWide.face.width);
  assert.equal(normal.face.height, wide.face.height);
  assert.equal(normal.ends, wide.ends);
  assert.equal(wide.ends, veryWide.ends);
  assert(wide.label.width > normal.label.width, '寬鍵仍需為文字提供更大的空間');
});

test('分開的眼睛在實際座標仍維持圓形', () => {
  const expression = layers.find(layer => layer.name === 'expression');
  // 第一個 E 在編譯後是四段 Bézier，檢查實際視窗中的寬高。
  for (const size of [[28, 38], [36, 46], [160, 46]]) {
    const face = geometry(...size).face;
    const eyeWidth = 12 / 100 * face.width;
    const eyeHeight = 26.666666 / 100 * face.height;
    assert(Math.abs(eyeWidth - eyeHeight) < 0.0001);
    assert(svgPath(expression.ops, face, null).startsWith('M'));
  }
});

test('所有圖層路徑能解析、輸出有限座標，眼鼻獨立於可延展輪廓', () => {
  assert.equal(layers.filter(layer => layer.space === 'face').length, 1);
  for (const layer of layers) {
    assert(layer.ops.length > 0);
    assert(layer.ops.every(Number.isFinite));
    for (const [width, height] of [[28, 31], [34, 48], [160, 46]]) {
      const g = geometry(width, height);
      const d = svgPath(layer.ops, layer.space === 'face' ? g.face : g.frame, layer.space === 'face' ? null : g.ends);
      assert(!/NaN|Infinity/.test(d));
      assert(d.endsWith('Z'));
    }
  }
  assert.equal(source.layers.some(layer => /body|torso/i.test(layer.name)), false);
});

test('UIKit 與離線預覽沒有脫離共用原始資料', () => {
  const root = path.resolve(__dirname, '../..');
  for (const [file, content] of outputs()) {
    assert.equal(fs.readFileSync(path.join(root, file), 'utf8'), content, `${file} 尚未重新產生`);
  }
});
