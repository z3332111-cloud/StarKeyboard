'use strict';

// Node 22+；只開啟本機預覽，使用 Chromium DevTools Protocol，不需 npm 套件。
const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const root = path.resolve(__dirname, '..');

function findChrome() {
  if (process.env.CHROME_BIN) return process.env.CHROME_BIN;
  for (const candidate of ['/usr/bin/chromium', '/usr/bin/chromium-browser', '/usr/bin/google-chrome']) {
    if (fs.existsSync(candidate)) return candidate;
  }
  const cache = path.join(os.homedir(), '.cache/ms-playwright');
  if (fs.existsSync(cache)) {
    for (const entry of fs.readdirSync(cache).filter(s => /^chromium-\d+$/.test(s)).sort().reverse()) {
      for (const folder of ['chrome-linux64', 'chrome-linux']) {
        const candidate = path.join(cache, entry, folder, 'chrome');
        if (fs.existsSync(candidate)) return candidate;
      }
    }
  }
  throw new Error('找不到 Chromium；請用 CHROME_BIN 指定瀏覽器執行檔。');
}

function checkPrototype() {
  const set = (id, value) => {
    const e = document.getElementById(id);
    e.value = value;
    e.dispatchEvent(new Event('input', { bubbles: true }));
  };
  const require = (ok, message) => { if (!ok) throw new Error(message); };
  require(document.querySelectorAll('svg[aria-label]').length === 16, '單顆預覽數量');
  set('letter', 'W');
  require(document.querySelector('#large-en svg').getAttribute('aria-label') === 'W', '單顆換字');
  document.querySelector('#zones').click();
  require(!document.querySelector('#preview').classList.contains('zones-off'), '單顆分區');
  document.querySelector('#press').click();
  require(document.querySelector('#preview').classList.contains('dim'), '單顆按壓');
  let glyphs = 0;
  for (const height of [.8, 1, 1.3]) for (const font of [.8, 1.3]) {
    set('height', height); set('font', font);
    for (const id of ['en', 'zh', 'wide']) {
      const svg = document.querySelector('#large-' + id + ' svg');
      const box = svg.querySelector('text').getBBox();
      const face = svg.querySelector('.face-zone');
      require(box.y + box.height <= Number(face.getAttribute('y')) + .1, '單顆字形碰五官 ' + id);
      glyphs++;
    }
  }
  set('letter', 'A'); set('height', 1); set('font', 1);
  document.querySelector('#zones').click(); document.querySelector('#press').click();
  return { svgCount: 16, glyphs, controls: ['letter', 'height', 'font', 'zones', 'press'] };
}

function checkTheme() {
  const require = (ok, message) => { if (!ok) throw new Error(message); };
  const set = (id, value) => {
    const e = document.getElementById(id);
    if (e.type === 'checkbox') e.checked = value;
    else e.value = value;
  };
  const reset = () => {
    for (const [id, v] of Object.entries({ mode: 'zhuyin', layer: 'letters', panel: 'keyboard',
      ten: true, shift: false, globe: false, full: true, candidates: false, zones: false,
      width: 390, height: 1, font: 1, gap: 1, shape: 1.15, alpha: 1, zoom: 1.7 })) set(id, v);
    render();
  };
  reset();
  const profiles = [
    { height: .8, font: 1.3, gap: 1.8, shape: .8, alpha: .35 },
    { height: .8, font: 1.3, gap: .3, shape: 1.3, alpha: 1 },
    { height: 1.3, font: .8, gap: 1.8, shape: .8, alpha: .35 },
    { height: 1.3, font: 1.3, gap: .3, shape: 1.3, alpha: 1 }
  ];
  let scenes = 0, labels = 0, keys = 0;
  for (const mode of ['zhuyin', 'english', 'pinyin', 'japanese', 'korean', 'handwriting']) {
    for (const page of ['letters', 'numbers', 'symbols', 'numpad']) for (const width of [320, 390, 430, 700]) {
      for (const profile of profiles) {
        for (const [id, v] of Object.entries({ mode, layer: page, width, zoom: 1, ...profile })) set(id, v);
        render(); scenes++;
        const scene = document.querySelector('.key-scene').viewBox.baseVal;
        const context = [mode, page, width, JSON.stringify(profile)].join(' ');
        require(document.querySelectorAll('.key').length > 0, '沒有按鍵 ' + context);
        for (const key of document.querySelectorAll('.key')) {
          keys++;
          const v = name => Number(key.getAttribute(name));
          require(v('x') >= 0 && v('y') >= 0 && v('x') + v('width') <= scene.width + .1 &&
            v('y') + v('height') <= scene.height + .1, '按鍵超出畫布 ' + context);
          for (const [text, zone] of [['.main-text', '.label-zone'], ['.hint-text', '.hint-zone']]) {
            const t = key.querySelector(text), z = key.querySelector(zone);
            if (!t || !t.textContent) continue;
            labels++;
            const b = t.getBBox(), x = Number(z.getAttribute('x')), y = Number(z.getAttribute('y'));
            const w = Number(z.getAttribute('width')), h = Number(z.getAttribute('height'));
            require(b.width > 0 && b.height > 0 && b.x >= x - .15 && b.y >= y - .15 &&
              b.x + b.width <= x + w + .15 && b.y + b.height <= y + h + .15,
            '字形超出分區 ' + context + ' ' + key.dataset.label + ' ' + text);
            const face = key.querySelector('.face-zone');
            require(!Number(face.getAttribute('height')) || b.y + b.height <= Number(face.getAttribute('y')) + .15,
              '文字碰五官 ' + context + ' ' + key.dataset.label);
          }
        }
      }
    }
  }
  reset();
  const before = document.querySelector('.key').getAttribute('width');
  set('ten', false); render();
  require(document.querySelector('.key').getAttribute('width') !== before, '注音欄數切換');
  set('ten', true); set('mode', 'korean'); set('shift', true); render();
  require(document.querySelector('.key').dataset.label === 'ㅃ', '韓文 Shift');
  set('shift', false); set('mode', 'japanese'); render();
  require(document.querySelector('.key').dataset.label === 'q', '日文羅馬字');
  set('mode', 'english'); set('globe', true); render();
  require(document.querySelector('[data-action="globe"]'), '地球鍵');
  set('mode', 'zhuyin'); set('layer', 'numbers'); set('full', false); render();
  require([...document.querySelectorAll('.key')].some(k => k.dataset.label === '?'), '半形符號');
  set('full', true); render();
  require([...document.querySelectorAll('.key')].some(k => k.dataset.label === '？'), '全形符號');
  for (const panel of ['emoji', 'clipboard', 'settings']) {
    set('panel', panel); render(); require(document.querySelector('.panel'), '面板 ' + panel);
  }
  reset(); set('candidates', true); render();
  require(document.querySelector('.toolbar').textContent.includes('楓葉'), '候選列示意');
  set('candidates', false); render();
  const key = document.querySelector('.key'); key.dispatchEvent(new MouseEvent('click', { bubbles: true }));
  require(document.querySelector('#status').textContent.includes('點選'), '點按回饋');
  reset(); set('mode', 'english');
  // 完整透明度滑桿範圍；直接檢查 CSS 生效的按壓透明度與文字／圖示字色。
  let feedback = 0;
  const rgb = hex => 'rgb(' + hex.slice(1).match(/../g).map(v => parseInt(v, 16)).join(', ') + ')';
  for (let n = 0; n <= 13; n++) {
    const alpha = .35 + n * .05; set('alpha', alpha); render();
    const config = state();
    const specs = positions(layout(config, data), config.width, 216);
    for (const [i, key] of [...document.querySelectorAll('.key')].entries()) {
      const spec = specs[i];
      const index = spec.action === 'returnKey' ? 2 : spec.action === 'space' ? 0 : spec.index % source.variants.length;
      const p = source.variants[index];
      key.querySelector('.art').style.transition = 'none';
      for (const pressed of [false, true]) {
        key.classList.toggle('pressed', pressed);
        const expectedAlpha = config.alpha * (pressed ? .82 : 1);
        const actual = Number(getComputedStyle(key.querySelector('.art')).opacity);
        require(Math.abs(expectedAlpha - actual) < .0001, '按壓透明度 ' + alpha + ' ' + spec.text);
        const ink = legibleInk(p, expectedAlpha, source.themeColors);
        const expectedInk = rgb(ink.color);
        const text = key.querySelector('.main-text'), icon = key.querySelector('.icon path');
        require((text ? getComputedStyle(text).fill : getComputedStyle(icon).stroke) === expectedInk,
          '按壓字色 ' + alpha + ' ' + spec.text);
        if (ink.outline && text) {
          require(getComputedStyle(text).stroke === rgb(ink.outline), '缺少對比細邊');
          const edge = parseFloat(getComputedStyle(text).strokeWidth) / 2;
          require(edge > 0, '細邊寬度');
          const b = text.getBBox(), zone = key.querySelector('.label-zone');
          const z = name => Number(zone.getAttribute(name));
          require(b.x - edge >= z('x') - .15 && b.y - edge >= z('y') - .15 &&
            b.x + b.width + edge <= z('x') + z('width') + .15 &&
            b.y + b.height + edge <= z('y') + z('height') + .15, '細邊超出文字區');
        }
        feedback++;
      }
    }
  }
  reset();
  return { scenes, keys, labels, feedback,
    controls: ['ten', 'shift', 'globe', 'full', 'candidates', 'panels', 'click', 'pressed'] };
}

async function main() {
  const args = process.argv.slice(2);
  assert(args.length === 0 || (args.length === 2 && args[0] === '--output'), '用法：node tools/check_fox_letter_browser.js [--output 目錄]');
  assert(typeof WebSocket === 'function', '需要 Node 22+ 的 WebSocket');
  const output = path.resolve(args[1] || path.join(os.tmpdir(), 'fox-letter-acceptance'));
  fs.mkdirSync(output, { recursive: true });
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'fox-letter-chrome-'));
  const flags = ['--headless', '--disable-dev-shm-usage', '--disable-gpu', '--no-zygote',
    '--disable-background-networking', '--disable-component-update', '--no-first-run', '--no-default-browser-check',
    '--remote-debugging-port=0', '--remote-debugging-address=127.0.0.1', '--user-data-dir=' + profile, 'about:blank'];
  if (process.env.FOX_CHROME_NO_SANDBOX === '1') flags.unshift('--no-sandbox');
  const child = spawn(findChrome(), flags, { stdio: ['ignore', 'ignore', 'pipe'] });
  let socket;
  const timeout = setTimeout(() => { console.error('瀏覽器驗收逾時'); child.kill(); process.exitCode = 1; socket?.close(); }, 55000);
  try {
    const endpoint = await new Promise((resolve, reject) => {
      let log = '';
      child.stderr.on('data', chunk => {
        log = (log + chunk).slice(-16000);
        const match = log.match(/DevTools listening on (ws:\/\/[^\s]+)/);
        if (match) resolve(match[1]);
      });
      child.once('error', reject);
      child.once('exit', code => reject(new Error('Chromium 結束 ' + code + ': ' + log.slice(-1500))));
    });
    socket = new WebSocket(endpoint);
    await new Promise((resolve, reject) => { socket.onopen = resolve; socket.onerror = reject; });
    let id = 0;
    const pending = new Map(), exceptions = [];
    socket.onmessage = event => {
      const m = JSON.parse(event.data);
      if (m.method === 'Runtime.exceptionThrown') exceptions.push(m.params.exceptionDetails);
      if (!pending.has(m.id)) return;
      const p = pending.get(m.id); pending.delete(m.id);
      m.error ? p.reject(new Error(JSON.stringify(m.error))) : p.resolve(m.result);
    };
    socket.onclose = () => { for (const p of pending.values()) p.reject(new Error('CDP 連線結束')); pending.clear(); };
    const call = (method, params = {}, sessionId) => new Promise((resolve, reject) => {
      const n = ++id; pending.set(n, { resolve, reject });
      socket.send(JSON.stringify({ id: n, method, params, ...(sessionId ? { sessionId } : {}) }));
    });
    const version = await call('Browser.getVersion');
    const { targetId } = await call('Target.createTarget', { url: 'about:blank' });
    const { sessionId } = await call('Target.attachToTarget', { targetId, flatten: true });
    const c = (method, params) => call(method, params, sessionId);
    const evaluate = async expression => {
      const r = await c('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
      if (r.exceptionDetails) throw new Error(JSON.stringify(r.exceptionDetails));
      return r.result.value;
    };
    await c('Runtime.enable'); await c('Page.enable'); await c('DOM.enable'); await c('CSS.enable');
    const viewport = (width, height, mobile = false) => c('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile });
    await viewport(1100, 1150);
    const open = async name => {
      await c('Page.navigate', { url: pathToFileURL(path.join(root, 'docs/previews/fox-letter', name)).href });
      let ready = false;
      for (let n = 0; n < 50; n++) {
        ready = await evaluate('document.readyState === "complete" && !!document.querySelector("#preview svg, .key")');
        if (ready) break;
        await new Promise(resolve => setTimeout(resolve, 100));
      }
      assert(ready, name + ' 沒有載入完成');
      await evaluate('document.fonts.ready.then(() => true)');
      await evaluate(`Promise.all([...new Set([...document.querySelectorAll('svg image')].map(e=>e.href.baseVal))].map(src=>{const image=new Image();image.src=src;return image.decode();})).then(()=>true)`);
    };
    const shot = async (name, selector) => {
      const clip = selector ? await evaluate(`(()=>{const r=document.querySelector(${JSON.stringify(selector)}).getBoundingClientRect();return {x:r.x+scrollX,y:r.y+scrollY,width:r.width,height:r.height,scale:2};})()`) : undefined;
      const screenshot = await c('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true, ...(clip ? {clip} : {}) });
      fs.writeFileSync(path.join(output, name), Buffer.from(screenshot.data, 'base64'));
    };
    await open('index.html');
    const prototype = await evaluate('(' + checkPrototype.toString() + ')()');
    await shot('preview.png');
    await open('theme.html');
    const theme = await evaluate('(' + checkTheme.toString() + ')()');
    const doc = await c('DOM.getDocument');
    const { nodeId } = await c('DOM.querySelector', { nodeId: doc.root.nodeId, selector: '.key .main-text' });
    const { fonts } = await c('CSS.getPlatformFontsForNode', { nodeId });
    assert(fonts.some(f => f.glyphCount > 0 && /huninn|cjk|han|hei|sung|song|ming|gothic|(?:^|[\s-])(?:tc|sc|jp|kr)(?:$|[\s-])/i.test(f.familyName)),
      '需安裝支援注音的 CJK 字體，或透過 FONTCONFIG_FILE 指定字體；避免以缺字方塊驗收。實際字體：' + JSON.stringify(fonts));
    await shot('theme-zhuyin.png');
    await shot('theme-keyboard-zhuyin-v2.png', '#keyboard');
    for (const mode of ['english', 'handwriting']) {
      await evaluate('document.querySelector("#mode").value=' + JSON.stringify(mode) + ';render()');
      await shot('theme-' + mode + '.png');
      if (mode === 'english') await shot('theme-keyboard-english-v2.png', '#keyboard');
    }
    await evaluate('document.querySelector("#mode").value="english";document.querySelector("#alpha").value="0.4";render()');
    await shot('theme-contrast.png');
    await evaluate('document.querySelector("#mode").value="zhuyin";document.querySelector("#width").value="320";document.querySelector("#zoom").value="1";document.querySelector("#height").value="0.8";document.querySelector("#font").value="1.3";document.querySelector("#shape").value="0.8";document.querySelector("#gap").value="1.8";document.querySelector("#alpha").value="1";render()');
    await shot('theme-compact.png');
    const mobile = [];
    for (const page of ['index.html', 'theme.html']) {
      await open(page);
      for (const width of [320, 390, 430]) {
        await viewport(width, 844, true);
        const size = await evaluate('({viewport: innerWidth, document: document.documentElement.scrollWidth})');
        assert(size.document <= size.viewport, page + ' 手機整頁水平溢出：' + JSON.stringify(size));
        mobile.push({ page, ...size });
      }
    }
    assert.equal(exceptions.length, 0, JSON.stringify(exceptions));
    const checkedFiles = ['tools/check_fox_letter_browser.js', 'tools/fox_letter_prototype.json', 'tools/fox_letter_watercolor.js',
      'tools/build_fox_letter_prototype.js', 'tools/build_fox_letter_theme.js', 'tools/fox_letter_preview_layouts.js',
      'docs/previews/fox-letter/index.html', 'docs/previews/fox-letter/theme.html',
      'Keyboard/Resources/FoxLetter/keycaps-watercolor-v2.png', 'Keyboard/Resources/FoxLetter/wide-keycaps-watercolor-v2.png',
      'Keyboard/Resources/FoxLetter/background-watercolor-v2.png'];
    const sha256 = Object.fromEntries(checkedFiles.map(file => [file, createHash('sha256').update(fs.readFileSync(path.join(root, file))).digest('hex')]));
    const report = { status: 'passed', checkedAt: new Date().toISOString(), scope: 'Linux Chromium offline previews; not UIKit or iPhone',
      node: process.version, browser: version.product, fonts: fonts.map(f => f.familyName),
      prototype, theme, mobile, javascriptExceptions: exceptions.length,
      screenshots: ['preview.png', 'theme-zhuyin.png', 'theme-english.png', 'theme-handwriting.png', 'theme-compact.png', 'theme-contrast.png',
        'theme-keyboard-zhuyin-v2.png', 'theme-keyboard-english-v2.png'], sha256 };
    fs.writeFileSync(path.join(output, 'acceptance.json'), JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify(report, null, 2));
    await call('Browser.close');
  } finally {
    clearTimeout(timeout); socket?.close();
    const exited = new Promise(resolve => child.once('exit', resolve));
    if (child.exitCode === null && child.signalCode === null) { child.kill(); await exited; }
    await fs.promises.rm(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
