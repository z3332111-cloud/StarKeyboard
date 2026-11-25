'use strict';

// 所有平台以同一張透明圖集取樣；沒有把字母或注音烘焙進圖片。
const atlas = {
  revision: 'watercolor-v2', columns: 3, rows: 3,
  keycaps: '../../../Keyboard/Resources/FoxLetter/keycaps-watercolor-v2.png',
  wideKeycaps: '../../../Keyboard/Resources/FoxLetter/wide-keycaps-watercolor-v2.png',
  backdrop: '../../../Keyboard/Resources/FoxLetter/background-watercolor-v2.png',
  palettes: [[0, 3, 6], [1, 5], [2, 7], [4], [8]],
  cuts: [0, .15, .425, .575, .85, 1],
  wideCells: [[.02, .065, .96, .40], [.02, .54, .96, .40]]
};

function spriteIndex(index, action, personalSpaceArt = false) {
  if (action === 'space') return personalSpaceArt ? 3 : 0;
  if (action === 'returnKey') return 7;
  const options = atlas.palettes[Math.max(0, index) % 5];
  return options[Math.floor(Math.max(0, index) / 5) % options.length];
}

function imageSlices(frame, sprite, compact = false, wideRow = 0) {
  const cell = { x: (sprite % 3) / 3, y: Math.floor(sprite / 3) / 3,
    width: 1 / 3, height: (compact ? .78 : 1) / 3 };
  const wide = frame.width > frame.height * 1.35;
  if (!wide) return [{ frame, source: cell, url: atlas.keycaps }];
  const [sx, sy, sw, sh] = atlas.wideCells[wideRow];
  const wideCell = { x: sx, y: sy, width: sw, height: sh * (compact ? .78 : 1) };
  const naturalWidth = frame.height * 2.9;
  const stretch = (frame.width - naturalWidth * .45) / 2;
  let x = frame.x;
  return atlas.cuts.slice(0, -1).map((start, i) => {
    const fraction = atlas.cuts[i + 1] - start;
    const width = i === 1 || i === 3 ? stretch : naturalWidth * fraction;
    const result = { frame: { x, y: frame.y, width, height: frame.height },
      source: { x: wideCell.x + wideCell.width * start, y: wideCell.y, width: wideCell.width * fraction, height: wideCell.height },
      url: atlas.wideKeycaps };
    x += width;
    return result;
  });
}

function watercolorSVG(frame, index, action, compact = false) {
  return imageSlices(frame, spriteIndex(index, action), compact, action === 'space' ? 0 : 1).map(piece => {
    const f = piece.frame, s = piece.source;
    return '<svg class="watercolor-piece" x="' + f.x + '" y="' + f.y + '" width="' + f.width + '" height="' + f.height +
      '" viewBox="' + [s.x, s.y, s.width, s.height].join(' ') + '" preserveAspectRatio="none" overflow="hidden" style="overflow:hidden">' +
      '<image href="' + piece.url + '" x="0" y="0" width="1" height="1" preserveAspectRatio="none"/></svg>';
  }).join('');
}

module.exports = { atlas, spriteIndex, imageSlices, watercolorSVG };
