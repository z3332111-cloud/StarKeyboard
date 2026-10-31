/* 網頁試玩鍵盤：照 App 的鍵盤做一個可以真的按的版本。
   顏色、造型、排列來自 Keyboard/Theme.swift、KeyLayouts.swift、SymbolData.swift；字典只放示範用的一小部分。 */
(function () {
  'use strict';
  var root = document.getElementById('preview');
  if (!root || !document.getElementById('sim-phone')) return;
  var $ = function (id) { return document.getElementById(id); };
  var phone = $('sim-phone'), kb = $('sim-keyboard'), topbar = $('sim-topbar'), main = $('sim-main');
  var inputEl = $('sim-input'), chatEl = $('sim-chat'), fxEl = $('sim-fx'), toastEl = $('sim-toast');

  // ===== 外觀資料 =====
  var THEMES = {
    strawberry: { name: '草莓牛奶', top: '#ffe4ec', bottom: '#ffd0de', key: '#ffffff', text: '#8a4b5c', special: '#ffc2d4', specialText: '#7a3045', accent: '#ff7fa6', accentText: '#ffffff', shadow: '#e8a2b6' },
    mint: { name: '薄荷蘇打', top: '#ddf7ef', bottom: '#c5efe3', key: '#ffffff', text: '#2f6b5e', special: '#a7e3d2', specialText: '#2f6b5e', accent: '#3cc5a0', accentText: '#ffffff', shadow: '#9fd8c7' },
    milktea: { name: '奶茶布丁', top: '#f3e6d6', bottom: '#e9d5bd', key: '#fff8ee', text: '#6b4a33', special: '#d9b994', specialText: '#5a3b24', accent: '#b9835a', accentText: '#ffffff', shadow: '#cbae8c' },
    lavender: { name: '薰衣草', top: '#ece4ff', bottom: '#dcd0ff', key: '#ffffff', text: '#5b4b8a', special: '#c7b8f5', specialText: '#4a3b78', accent: '#8d74e8', accentText: '#ffffff', shadow: '#b9a9ec' },
    lemon: { name: '檸檬小雞', top: '#fff6cc', bottom: '#ffec9e', key: '#ffffff', text: '#7a5b12', special: '#ffdd6b', specialText: '#6b4e0a', accent: '#ffa928', accentText: '#ffffff', shadow: '#e9cb6a' },
    night: { name: '星空夜', top: '#1e2245', bottom: '#2b2f63', key: '#3a3f7a', text: '#f3f0ff', special: '#2a2e5e', specialText: '#cfcbff', accent: '#ffd65c', accentText: '#2b2f63', shadow: '#14173a', dark: true },
    light: { name: '經典淺色', top: '#d3d6dc', bottom: '#cdd0d6', key: '#ffffff', text: '#000000', special: '#abb0ba', specialText: '#000000', accent: '#2f7bf6', accentText: '#ffffff', shadow: '#8e9196' },
    dark: { name: '經典深色', top: '#2b2b2d', bottom: '#232325', key: '#6b6b6e', text: '#ffffff', special: '#474749', specialText: '#ffffff', accent: '#2f7bf6', accentText: '#ffffff', shadow: '#111111', dark: true }
  };
  // center：字放在造型裡的高度（%），和 App 的 bodyRect 中心一樣；soft：有耳朵、尾巴的造型，寬鍵改成膠囊＋小圖
  var SHAPES = [
    ['rounded', '圓角', 50], ['jelly', '果凍', 50], ['catEar', '貓耳', 57], ['cloud', '雲朵', 58], ['bunny', '兔兔', 61, 1], ['puppy', '狗狗', 56, 1],
    ['pudding', '布丁', 59.5, 1], ['jellyfish', '水母', 46, 1], ['flame', '火焰', 62.5, 1], ['droplet', '水滴', 60.5, 1], ['duck', '鴨鴨', 65, 1],
    ['mochi', '麻糬', 51, 0, '新'], ['bubble', '泡泡', 50, 0, '新']
  ];
  var DETAIL = { pudding: ['#a86635', '#d7a15f'], flame: ['#ed914a', '#ffd46b'], droplet: ['#4aadd5', '#b8efff'], duck: ['#d78a32', '#ffd276'], bubble: ['#ffffff', '#ffffff'] };
  var FINISHES = [['flat', '平面'], ['puffy', '胖胖'], ['glass', '玻璃']];
  var EFFECTS = [['none', '無', []], ['stars', '星星', ['★', '☆', '✦']], ['hearts', '愛心', ['♥︎', '♡', '❤︎']], ['sparkles', '閃亮', ['✧', '✦', '⋆']], ['flowers', '花花', ['✿', '❀', '❁']], ['bubbles', '泡泡', ['○', '◦', '°']]];
  var JSD = 'https://cdn.jsdelivr.net/gh/';
  var FONTS = [
    ['system', '系統', ''],
    ['huninn', '粉圓', 'Huninn', 'google'],
    ['iansui', '芫荽', 'Iansui', 'google'],
    ['wenkai', '文楷', 'LXGW WenKai TC', 'google'],
    ['gensen', '源泉圓體', 'SimGenSen', JSD + 'ButTaiwan/gensen-font@master/otf/TW/GenSenRounded2TW-M.otf', '新・檔案比較大（約 16MB），手機上請用 Wi-Fi'],
    ['naikai', '內海', 'SimNaikai', JSD + 'max32002/naikaifont@master/webfont/NaikaiFont-Regular-Lite.woff2', '新'],
    ['cubic', '像素', 'SimCubic', JSD + 'ACh-K/Cubic-11@main/fonts/web/Cubic_11.woff2', '新']
  ];

  // ===== 狀態 =====
  var S = {
    theme: 'lavender', shape: 'bunny', finish: 'puffy', effect: 'stars', font: 'system',
    height: 1, fontScale: 1, gap: 1, sound: false,
    modes: ['zhuyin', 'english', 'pinyin', 'japanese', 'korean', 'handwriting'], mode: 'zhuyin', layer: 'letters', shift: 'off', fullWidth: true,
    text: '', caret: 0,
    zy: '', py: '', romaji: '', simplified: false, hangul: null,
    suggestions: [], suggestionKind: '', expanded: false,
    panel: null, panelTab: 0, editor: null, result: null,
    hidden: false, learned: {}
  };

  // ===== 注音字典（示範用；真正的鍵盤用小麥注音十幾萬詞） =====
  var DICT_TEXT = [
    'ㄋㄧˇ=你,妳,擬', 'ㄏㄠˇ=好', 'ㄏㄠˋ=號,浩', 'ㄨㄛˇ=我', 'ㄕˋ=是,事,試,市,室,世', 'ㄕˊ=時,十,實', 'ㄉㄜ˙=的', 'ㄅㄨˋ=不,部,步,布',
    'ㄧㄡˇ=有,友', 'ㄗㄞˋ=在,再,載', 'ㄇㄚ˙=嗎,嘛', 'ㄌㄜ˙=了', 'ㄊㄚ=他,她,它', 'ㄐㄧㄣ=今,金,斤', 'ㄊㄧㄢ=天,添', 'ㄒㄧㄤˇ=想,響', 'ㄔ=吃',
    'ㄈㄢˋ=飯,犯,範', 'ㄨㄢˇ=晚,碗', 'ㄨㄢˊ=玩,完', 'ㄢ=安', 'ㄒㄧㄝˋ=謝', 'ㄒㄧㄝ˙=謝', 'ㄞˋ=愛', 'ㄎㄜˇ=可,渴', 'ㄧˇ=以,已,椅', 'ㄇㄧㄥˊ=明,名',
    'ㄓ=之,知,隻', 'ㄉㄠˋ=到,道', 'ㄌㄞˊ=來', 'ㄑㄩˋ=去,趣', 'ㄏㄨㄟˊ=回', 'ㄈㄨˋ=覆,復,付,父', 'ㄉㄧㄢˇ=點,典', 'ㄎㄞ=開', 'ㄒㄧㄣ=心,新',
    'ㄇㄣ˙=們', 'ㄧ=一,衣,醫', 'ㄑㄧˇ=起', 'ㄓㄜˋ=這', 'ㄋㄚˋ=那', 'ㄕㄣˊ=什,神', 'ㄇㄜ˙=麼', 'ㄗㄣˇ=怎', 'ㄧㄤˋ=樣', 'ㄉㄨㄛ=多', 'ㄒㄧㄠˇ=小',
    'ㄒㄧㄠˋ=笑', 'ㄎㄨㄞˋ=快', 'ㄌㄜˋ=樂', 'ㄕㄥ=生,聲', 'ㄖˋ=日', 'ㄓㄣ=真', 'ㄅㄤˋ=棒', 'ㄕㄨㄟˋ=睡', 'ㄐㄧㄠˋ=覺,叫', 'ㄒㄧㄡ=休', 'ㄒㄧ=西,希,息',
    'ㄒㄧ˙=息,係', 'ㄐㄧㄢˋ=見,件,鍵', 'ㄇㄧㄢˋ=面', 'ㄏㄜ=喝', 'ㄕㄨㄟˇ=水', 'ㄋㄞˇ=奶', 'ㄔㄚˊ=茶', 'ㄉㄚˋ=大', 'ㄉㄚˇ=打', 'ㄐㄧㄚ=家,加',
    'ㄖㄣˊ=人', 'ㄅㄠˇ=寶,保', 'ㄅㄟˋ=貝,被', 'ㄗㄠˇ=早', 'ㄒㄧˇ=喜,洗', 'ㄏㄨㄢ=歡', 'ㄓㄠ=招', 'ㄏㄨ=呼', 'ㄇㄟˊ=沒', 'ㄍㄨㄢ=關', 'ㄒㄧˋ=係,系',
    'ㄉㄨㄟˋ=對', 'ㄏㄨㄚ=花', 'ㄊㄨˋ=兔', 'ㄊㄨㄟ=推', 'ㄋㄨㄛˋ=糯', 'ㄆㄢˊ=盤', 'ㄏㄣˇ=很', 'ㄎㄜˇ ㄞˋ=可愛',
    'ㄋㄧˇ ㄏㄠˇ=你好,妳好', 'ㄋㄧˇ ㄇㄣ˙=你們', 'ㄨㄛˇ ㄇㄣ˙=我們', 'ㄐㄧㄣ ㄊㄧㄢ=今天', 'ㄇㄧㄥˊ ㄊㄧㄢ=明天', 'ㄒㄧㄝˋ ㄒㄧㄝ˙=謝謝',
    'ㄎㄜˇ ㄧˇ=可以', 'ㄔ ㄈㄢˋ=吃飯', 'ㄨㄢˇ ㄢ=晚安', 'ㄗㄠˇ ㄢ=早安', 'ㄓ ㄉㄠˋ=知道', 'ㄏㄨㄟˊ ㄈㄨˋ=回覆', 'ㄨㄢˇ ㄉㄧㄢˇ=晚點', 'ㄎㄞ ㄒㄧㄣ=開心',
    'ㄒㄧㄤˇ ㄋㄧˇ=想你', 'ㄧ ㄑㄧˇ=一起', 'ㄕㄣˊ ㄇㄜ˙=什麼', 'ㄗㄣˇ ㄇㄜ˙=怎麼', 'ㄗㄣˇ ㄇㄜ˙ ㄧㄤˋ=怎麼樣', 'ㄓㄜˋ ㄧㄤˋ=這樣', 'ㄒㄧㄠˇ ㄒㄧㄣ=小心',
    'ㄎㄨㄞˋ ㄌㄜˋ=快樂', 'ㄕㄥ ㄖˋ=生日', 'ㄕㄥ ㄖˋ ㄎㄨㄞˋ ㄌㄜˋ=生日快樂', 'ㄓㄣ ㄉㄜ˙=真的', 'ㄏㄠˇ ㄅㄤˋ=好棒', 'ㄕㄨㄟˋ ㄐㄧㄠˋ=睡覺', 'ㄒㄧㄡ ㄒㄧ˙=休息',
    'ㄐㄧㄢˋ ㄇㄧㄢˋ=見面', 'ㄉㄚˋ ㄐㄧㄚ=大家', 'ㄅㄠˇ ㄅㄟˋ=寶貝', 'ㄏㄜ ㄕㄨㄟˇ=喝水', 'ㄋㄞˇ ㄔㄚˊ=奶茶', 'ㄒㄧˇ ㄏㄨㄢ=喜歡', 'ㄨㄛˇ ㄞˋ ㄋㄧˇ=我愛你',
    'ㄉㄚˇ ㄓㄠ ㄏㄨ=打招呼', 'ㄇㄟˊ ㄍㄨㄢ ㄒㄧ˙=沒關係', 'ㄉㄨㄟˋ ㄅㄨˋ ㄑㄧˇ=對不起', 'ㄐㄧㄢˋ ㄆㄢˊ=鍵盤', 'ㄋㄨㄛˋ ㄋㄨㄛˋ=糯糯', 'ㄊㄨㄟ ㄐㄧㄢˋ=推薦',
    'ㄏㄠˇ ㄉㄜ˙=好的', 'ㄕˋ ㄇㄚ˙=是嗎', 'ㄗㄞˋ ㄐㄧㄢˋ=再見', 'ㄏㄣˇ ㄏㄠˇ=很好'
  ];
  var TONES = 'ˊˇˋ˙', INITIALS = 'ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙ', MEDIALS = 'ㄧㄨㄩ';
  var DICT = DICT_TEXT.map(function (line, rank) {
    var p = line.split('=');
    return { syl: p[0].split(' ').map(splitTone), words: p[1].split(','), rank: rank };
  });
  // 自己設定的快捷片語（App 裡可以新增）：縮寫 → 整句
  var SHORTCUTS = { 'ㄨㄢ': '我晚點回覆你', 'ㄉㄉ': '等等我，馬上到！', 'ㄒㄒ': '謝謝你～超感謝 ♡' };
  function splitTone(s) { var t = s.slice(-1); return TONES.indexOf(t) >= 0 ? { base: s.slice(0, -1), tone: t } : { base: s, tone: '' }; }

  // 打的注音切成音節：聲調結束一個音節；聲母前面已經有東西也換下一個（所以「ㄋㄏ」是簡拼兩個音節）
  function parseZhuyin(buf) {
    var out = [], cur = null;
    function flush() { if (cur) out.push(cur); cur = null; }
    for (var i = 0; i < buf.length; i++) {
      var ch = buf[i];
      if (ch === 'ˉ' || TONES.indexOf(ch) >= 0) { if (!cur) cur = { base: '', tone: '' }; cur.tone = ch; flush(); continue; }
      if (INITIALS.indexOf(ch) >= 0) { flush(); cur = { base: ch, tone: '' }; continue; }
      if (!cur) cur = { base: '', tone: '' };
      var hasFinal = /[ㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦ]/.test(cur.base);
      if (MEDIALS.indexOf(ch) >= 0 ? (/[ㄧㄨㄩ]/.test(cur.base) || hasFinal) : hasFinal) { flush(); cur = { base: '', tone: '' }; }
      cur.base += ch;
    }
    flush();
    return out;
  }
  function sylMatch(t, e) {
    if (t.tone) return t.base === e.base && (t.tone === 'ˉ' ? e.tone === '' : e.tone === t.tone);
    return e.base.indexOf(t.base) === 0;
  }
  function prefixMatch(typed, entry, n) {
    if (entry.syl.length < n) return false;
    for (var i = 0; i < n; i++) if (!sylMatch(typed[i], entry.syl[i])) return false;
    return true;
  }
  function learnedBonus(word) { return S.learned[word] || 0; }
  function sortWords(list) {
    return list.sort(function (a, b) { return (learnedBonus(b.text) - learnedBonus(a.text)) || (a.rank - b.rank); });
  }
  function zhuyinCandidates() {
    var typed = parseZhuyin(S.zy), n = typed.length;
    if (!n) return [];
    var seen = {}, out = [];
    function add(text, consume, tag, rank) { if (!seen[text]) { seen[text] = 1; out.push({ text: text, consume: consume, tag: tag, rank: rank || 0 }); } }
    var key = typed.map(function (t) { return t.base; }).join('');
    if (SHORTCUTS[key] && typed.every(function (t) { return !t.tone; })) add(SHORTCUTS[key], n, '片語', -1);
    var full = [];
    DICT.forEach(function (e) {
      if (e.syl.length === n && prefixMatch(typed, e, n)) e.words.forEach(function (w, j) { full.push({ text: w, consume: n, rank: e.rank * 10 + j }); });
    });
    // 沒有剛好的詞：一段一段接起來（每段挑最長的詞）
    if (n > 1 && !full.length) {
      var sentence = '', i = 0;
      while (i < n) {
        var best = null;
        for (var len = n - i; len >= 1 && !best; len--) {
          var part = typed.slice(i, i + len);
          var hits = sortWords(DICT.filter(function (e) { return e.syl.length === len && prefixMatch(part, e, len); })
            .map(function (e) { return { text: e.words[0], rank: e.rank }; }));
          if (hits.length) best = { text: hits[0].text, len: len };
        }
        if (!best) { sentence = ''; break; }
        sentence += best.text; i += best.len;
      }
      if (sentence) add(sentence, n);
    }
    sortWords(full).forEach(function (c) { add(c.text, c.consume, '', c.rank); });
    // 只選前面幾個音節（剩下的注音留著繼續選）
    for (var k = n - 1; k >= 1; k--) {
      var part2 = typed.slice(0, k), hits2 = [];
      DICT.forEach(function (e) { if (e.syl.length === k && prefixMatch(part2, e, k)) e.words.forEach(function (w, j) { hits2.push({ text: w, rank: e.rank * 10 + j }); }); });
      sortWords(hits2).slice(0, k === 1 ? 6 : 4).forEach(function (c) { add(c.text, k); });
    }
    // 接下去的長詞預測放最後面，不搶真的要的字
    var longer = [];
    DICT.forEach(function (e) { if (e.syl.length > n && e.syl.length <= n + 2 && prefixMatch(typed, e, n)) longer.push({ text: e.words[0], rank: e.rank }); });
    sortWords(longer).slice(0, 3).forEach(function (c) { add(c.text, n, '預測'); });
    return out;
  }
  function associations(ch) {
    var out = [];
    DICT.forEach(function (e) { e.words.forEach(function (w) { if (w.length > 1 && w[0] === ch && out.indexOf(w.slice(1)) < 0) out.push(w.slice(1)); }); });
    return out.slice(0, 6);
  }

  // ===== 拼音（馬來西亞朋友用；可以出簡體） =====
  var PINYIN = {
    ni: '你,尼,泥', hao: '好,號', nihao: '你好', wo: '我,握', women: '我們', men: '們,門', xie: '謝,寫,些', xiexie: '謝謝', wan: '晚,玩,萬', an: '安,按',
    wanan: '晚安', jin: '今,金', tian: '天', jintian: '今天', ming: '明,名', mingtian: '明天', zai: '在,再', jian: '見,間,鍵', zaijian: '再見', ai: '愛',
    woaini: '我愛你', chi: '吃', fan: '飯', chifan: '吃飯', kai: '開', xin: '心,新', kaixin: '開心', ma: '嗎,媽', shi: '是,時', de: '的', bu: '不',
    you: '有', hen: '很', ke: '可', keai: '可愛', peng: '朋', pengyou: '朋友', lai: '來'
  };
  var T2S = { 謝: '谢', 們: '们', 號: '号', 萬: '万', 見: '见', 間: '间', 鍵: '键', 開: '开', 愛: '爱', 飯: '饭', 嗎: '吗', 媽: '妈', 時: '时', 門: '门', 來: '来' };
  function toSimp(s) { return S.simplified ? s.replace(/[\s\S]/g, function (c) { return T2S[c] || c; }) : s; }
  function pinyinCandidates() {
    var b = S.py.replace(/'/g, ''), out = [], seen = {};
    function add(t, consume) { t = toSimp(t); if (!seen[t]) { seen[t] = 1; out.push({ text: t, consume: consume }); } }
    if (!b) return out;
    if (PINYIN[b]) PINYIN[b].split(',').forEach(function (w) { add(w, S.py.length); });
    // 一段一段切成認得的音節
    var i = 0, sent = '', firstLen = 0;
    while (i < b.length) {
      var hit = 0;
      for (var l = Math.min(6, b.length - i); l >= 1; l--) if (PINYIN[b.substr(i, l)]) { hit = l; break; }
      if (!hit) { sent = ''; break; }
      if (!firstLen) firstLen = hit;
      sent += PINYIN[b.substr(i, hit)].split(',')[0]; i += hit;
    }
    if (sent) add(sent, S.py.length);
    if (firstLen && firstLen < b.length) PINYIN[b.substr(0, firstLen)].split(',').forEach(function (w) { add(w, firstLen); });
    Object.keys(PINYIN).forEach(function (k) { if (k.length > b.length && k.indexOf(b) === 0 && out.length < 12) add(PINYIN[k].split(',')[0], S.py.length); });
    return out;
  }

  // ===== 日文羅馬拼音 =====
  var KANA = { a: 'あ', i: 'い', u: 'う', e: 'え', o: 'お' };
  'k:かきくけこ s:さしすせそ t:たちつてと n:なにぬねの h:はひふへほ m:まみむめも r:らりるれろ g:がぎぐげご z:ざじずぜぞ d:だぢづでど b:ばびぶべぼ p:ぱぴぷぺぽ'
    .split(' ').forEach(function (g) { var c = g[0], ks = g.slice(2); 'aiueo'.split('').forEach(function (v, i) { KANA[c + v] = ks[i]; }); });
  Object.assign(KANA, { ya: 'や', yu: 'ゆ', yo: 'よ', wa: 'わ', wo: 'を', nn: 'ん', shi: 'し', chi: 'ち', tsu: 'つ', fu: 'ふ', ji: 'じ', '-': 'ー',
    kya: 'きゃ', kyu: 'きゅ', kyo: 'きょ', sha: 'しゃ', shu: 'しゅ', sho: 'しょ', cha: 'ちゃ', chu: 'ちゅ', cho: 'ちょ', nya: 'にゃ', nyu: 'にゅ', nyo: 'にょ',
    ja: 'じゃ', ju: 'じゅ', jo: 'じょ', ryo: 'りょ', rya: 'りゃ', ryu: 'りゅ', hya: 'ひゃ', gya: 'ぎゃ', byo: 'びょ', pyo: 'ぴょ', mya: 'みゃ' });
  var JWORDS = { watashi: '私', arigatou: 'ありがとう', konnichiha: 'こんにちは', konnichiwa: 'こんにちは', sakura: '桜', neko: '猫', inu: '犬', kawaii: '可愛い', sugoi: 'すごい', oyasumi: 'おやすみ', daisuki: '大好き', tomodachi: '友達' };
  function romajiToKana(s) {
    var out = '', i = 0;
    while (i < s.length) {
      if (i + 1 < s.length && s[i] === s[i + 1] && /[kstpgzdbhmrcfj]/.test(s[i])) { out += 'っ'; i++; continue; }
      var hit = 0;
      for (var l = 3; l >= 1; l--) if (KANA[s.substr(i, l)]) { hit = l; break; }
      if (!hit && s[i] === 'n' && (i + 1 === s.length ? false : !/[aiueoy]/.test(s[i + 1]))) { out += 'ん'; i++; continue; }
      if (!hit) { out += s[i]; i++; continue; }
      out += KANA[s.substr(i, hit)]; i += hit;
    }
    return out;
  }
  function toKatakana(s) { return s.replace(/[ぁ-ゖ]/g, function (c) { return String.fromCharCode(c.charCodeAt(0) + 0x60); }); }
  function japaneseCandidates() {
    if (!S.romaji) return [];
    var h = romajiToKana(S.romaji), out = [];
    if (JWORDS[S.romaji]) out.push({ text: JWORDS[S.romaji], consume: -1 });
    out.push({ text: h, consume: -1 }, { text: toKatakana(h), consume: -1 });
    return out.filter(function (c, i, a) { return a.findIndex(function (d) { return d.text === c.text; }) === i; });
  }

  // ===== 韓文兩排式拼字 =====
  var CHO = 'ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ', JUNG = 'ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ';
  var JONG = ['', 'ㄱ', 'ㄲ', 'ㄳ', 'ㄴ', 'ㄵ', 'ㄶ', 'ㄷ', 'ㄹ', 'ㄺ', 'ㄻ', 'ㄼ', 'ㄽ', 'ㄾ', 'ㄿ', 'ㅀ', 'ㅁ', 'ㅂ', 'ㅄ', 'ㅅ', 'ㅆ', 'ㅇ', 'ㅈ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ'];
  var VJOIN = { 'ㅗㅏ': 'ㅘ', 'ㅗㅐ': 'ㅙ', 'ㅗㅣ': 'ㅚ', 'ㅜㅓ': 'ㅝ', 'ㅜㅔ': 'ㅞ', 'ㅜㅣ': 'ㅟ', 'ㅡㅣ': 'ㅢ' };
  var CJOIN = { 'ㄱㅅ': 'ㄳ', 'ㄴㅈ': 'ㄵ', 'ㄴㅎ': 'ㄶ', 'ㄹㄱ': 'ㄺ', 'ㄹㅁ': 'ㄻ', 'ㄹㅂ': 'ㄼ', 'ㄹㅅ': 'ㄽ', 'ㄹㅌ': 'ㄾ', 'ㄹㅍ': 'ㄿ', 'ㄹㅎ': 'ㅀ', 'ㅂㅅ': 'ㅄ' };
  function hangulText(h) {
    if (!h) return '';
    if (h.cho && h.jung) return String.fromCharCode(0xAC00 + (CHO.indexOf(h.cho) * 21 + JUNG.indexOf(h.jung)) * 28 + JONG.indexOf(h.jong || ''));
    return h.cho || h.jung || '';
  }
  function hangulInput(c) {
    var h = S.hangul || { cho: '', jung: '', jong: '' }, vowel = JUNG.indexOf(c) >= 0;
    function commit() { output(hangulText(h)); h = { cho: '', jung: '', jong: '' }; }
    if (!vowel) {
      if (h.jung && h.cho && !h.jong && JONG.indexOf(c) > 0) h.jong = c;
      else if (h.jong && CJOIN[h.jong + c]) h.jong = CJOIN[h.jong + c];
      else { if (h.cho || h.jung) commit(); h.cho = c; }
    } else if (h.cho && !h.jung) h.jung = c;
    else if (h.jung && !h.jong && VJOIN[h.jung + c]) h.jung = VJOIN[h.jung + c];
    else if (h.jong) {
      // 收尾的子音搬到下一個字當開頭
      var last = h.jong, keep = '';
      Object.keys(CJOIN).forEach(function (k) { if (CJOIN[k] === h.jong) { keep = k[0]; last = k[1]; } });
      h.jong = keep; commit(); h.cho = last; h.jung = c;
    } else { if (h.cho || h.jung) commit(); h.jung = c; }
    S.hangul = h;
  }
  function hangulBack() {
    var h = S.hangul; if (!h) return false;
    if (h.jong) h.jong = ''; else if (h.jung) h.jung = ''; else if (h.cho) h.cho = '';
    if (!h.cho && !h.jung) S.hangul = null;
    return true;
  }

  // ===== 英文 =====
  var EN_WORDS = 'the to and you that it is for i in my on we so have this with what are be just like love good see your can thanks thank okay sure maybe tomorrow tonight today morning night happy birthday sorry please hello hey how are doing great cute miss friend dinner lunch later sleep sweet dream coffee'.split(' ');
  var AUTOCORRECT = { teh: 'the', dont: "don't", im: "I'm", i: 'I', thx: 'thanks', u: 'you', ur: 'your', cant: "can't", wont: "won't", ive: "I've" };
  function currentWord() { var m = S.text.slice(0, S.caret).match(/[A-Za-z']+$/); return m ? m[0] : ''; }
  function englishSuggestions() {
    var w = currentWord().toLowerCase(); if (!w) return [];
    var out = [];
    if (AUTOCORRECT[w]) out.push(AUTOCORRECT[w]);
    EN_WORDS.forEach(function (x) { if (x.indexOf(w) === 0 && x !== w && out.indexOf(x) < 0) out.push(x); });
    return out.slice(0, 5);
  }

  // ===== 工具列面板的資料（SymbolData.swift） =====
  function words(s) { return s.trim().split(/\s+/); }
  var EMOJI = [
    ['😀', words('😀 😃 😄 😁 😆 😅 🤣 😂 🙂 🙃 😉 😊 😇 🥰 😍 🤩 😘 😗 😚 😙 😋 😛 😜 🤪 😝 🤗 🤭 🤫 🤔 🤐 🤨 😐 😑 😶 😏 😒 🙄 😬 😌 😔 😪 🤤 😴 😷 🥵 🥶 🥴 😵 🤯 🥳 😎 🤓 🧐 😕 😟 🙁 😮 😯 😲 😳 🥺 😢 😭 😱 😖 😣 😞 😓 😩 😫 🥱 😤 😡 😠')],
    ['👋', words('👋 🤚 🖐️ ✋ 👌 🤌 🤏 ✌️ 🤞 🤟 🤘 🤙 👈 👉 👆 👇 ☝️ 👍 👎 ✊ 👊 👏 🙌 👐 🤲 🤝 🙏 💪 👀 💋 🙇 💁 🙅 🙆 🙋 🤦 🤷 💃 🕺')],
    ['🐶', words('🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐨 🐯 🦁 🐮 🐷 🐸 🐵 🐔 🐧 🐦 🐤 🦆 🦉 🦄 🐝 🦋 🐌 🐞 🐢 🐙 🐬 🐳 🐾 🌸 🌷 🌹 🌻 🌼 💐 🍀 🌿 🍄')],
    ['🍓', words('🍓 🍒 🍑 🍋 🍉 🍇 🍌 🍍 🥝 🥑 🍞 🧀 🍳 🥞 🍔 🍟 🍕 🍝 🍜 🍣 🍱 🍙 🍡 🍧 🍨 🍦 🧁 🍰 🎂 🍮 🍭 🍬 🍫 🍩 🍪 🥛 ☕ 🍵 🧋')],
    ['🎀', words('🎀 🎁 🎈 🎉 🎊 🧸 🎨 🎮 🎧 🎤 🎹 📷 📚 ✏️ 📝 📌 💡 💎 👑 👗 👟 🎒 ☂️ ⚽ 🏀 🏆')],
    ['🚗', words('🚗 🚕 🚌 🚲 🛵 🚃 🚄 ✈️ 🚀 🛸 ⛵ 🗼 🏰 🎡 🎢 🏖️ 🏝️ 🗻 🏠 🏫 🌃 🌉 🌌 🎆 🌠')],
    ['❤️', words('❤️ 🧡 💛 💚 💙 💜 🤎 🖤 🤍 💔 ❣️ 💕 💞 💓 💗 💖 💘 💝 💯 💢 💥 💫 💦 💬 💭 💤 ✨ ⭐ 🌟 🔥 🌈 ☀️ 🌙 ☁️ ❄️ 🎵 🎶 ✅ ❌')]
  ];
  var KAOMOJI = [
    ['開心', ['(≧▽≦)', '(*´▽`*)', 'ヽ(✿ﾟ▽ﾟ)ノ', '(๑˃ᴗ˂)ﻭ', '٩(◕‿◕｡)۶', '(ﾉ◕ヮ◕)ﾉ*:･ﾟ✧', '(＾▽＾)', 'o(〃＾▽＾〃)o', '＼(^o^)／', '(◍•ᴗ•◍)', '╰(*°▽°*)╯', '(•‿•)']],
    ['愛心', ['(♡˙︶˙♡)', '(´,,•ω•,,)♡', '(*˘︶˘*).｡.:*♡', '♡(ˊ͈ ꒳ ˋ͈)', '(๑´ㅂ`๑)♡', '( ˘ ³˘)♥', '♡( ◡‿◡ )', '(っ˘з(˘⌣˘ )']],
    ['難過', ['(´；ω；`)', '(╥﹏╥)', '(இ﹏இ)', '(ಥ_ಥ)', '(｡•́︿•̀｡)', '(T_T)', '(；へ：)', '(´・ω・`)']],
    ['生氣', ['(╬ Ò﹏Ó)', '(｀Д´)', 'ヽ(`Д´)ﾉ', '(＃`Д´)', '(︶︹︺)', '(ꐦ°᷄д°᷅)', '(◣_◢)', '(｀へ´)']],
    ['驚訝', ['(ﾟДﾟ;)', 'Σ(°△°|||)', '(⊙_⊙)', 'w(ﾟДﾟ)w', '(°ロ°) !', '(⊙o⊙)', '(ﾟoﾟ;)', 'Σ(・口・)']],
    ['害羞', ['(〃∀〃)', '(⁄ ⁄•⁄ω⁄•⁄ ⁄)', '(*/ω＼*)', '(///▽///)', '(〃ω〃)', '(/ω＼)', '(,,・ω・,,)', '(*ﾉωﾉ)']],
    ['動物', ['ʕ•ᴥ•ʔ', '(=^･ω･^=)', 'ฅ^•ﻌ•^ฅ', '∪･ω･∪', '(ᵔᴥᵔ)', '/ᐠ｡ꞈ｡ᐟ\\', '( ´(00)ˋ )', '(・⊝・)']],
    ['打招呼', ['(・ω・)ノ', 'ヾ(•ω•`)o', '(*・ω・)ﾉ', '( ´ ▽ ` )ﾉ', 'ヾ(＾▽＾*)))', '(｡･ω･)ﾉﾞ', '(￣▽￣)ノ', '＼(°o°)／']],
    ['其他', ['¯\\_(ツ)_/¯', '(｀・ω・´)', '(￣ー￣)', '( ˘•ω•˘ )', '(・_・;)', '┐(´д`)┌', '(￣﹃￣)', '(－_－) zzZ']],
    ['我的表符', ['(•ᴗ•)♡', '꒰ ˶• ༝ •˶꒱']]
  ];
  var SYMBOLS = [
    ['常用', words('♡ ♥ ❤ ☆ ★ ✦ ✧ ✩ ✿ ❀ ❁ ♪ ♫ ♬ ☀ ☁ ☂ ☃ ❄ ☾ ✓ ✔ ✗ ※ ○ ● ◎ ◇ ◆ □ ■ △ ▲ ▽ ▼ ☺ ✌ ☞ ✉ ☎')],
    ['括號', words('「 」 『 』 （ ） 【 】 《 》 〈 〉 〔 〕 ［ ］ ｛ ｝ 〖 〗 ‹ › « » “ ” ‘ ’ 〝 〞')],
    ['標點', words('， 。 、 ； ： ？ ！ … ‥ ‧ · ～ — ― ﹏ ＿ ＂ ＇ ＆ ＠ ＃ ＊ ％ ＄ ＾ ｜ ＼ ／ ¡ ¿ § ° ′ ″')],
    ['箭頭', words('← → ↑ ↓ ↖ ↗ ↘ ↙ ↔ ↕ ⇐ ⇒ ⇑ ⇓ ⇔ ➔ ➜ ➤ ↩ ↪ ⤴ ⤵ ↺ ↻ ▶ ◀ ▸ ◂')],
    ['數學', words('＋ － × ÷ ＝ ≠ ≈ ≡ ＜ ＞ ≤ ≥ ± √ ∞ ∑ ∫ ∂ ∈ ∩ ∪ ∴ ∵ ∠ ⊥ ‰ ½ ⅓ ¼ ¾ ² ³ π')],
    ['單位', words('℃ ℉ ㎜ ㎝ ㎞ ㎡ ㏄ ㎎ ㎏ ㎖ ℓ ¥ ￥ $ ￠ ￡ € ₩ № ™ © ®')],
    ['數字', words('① ② ③ ④ ⑤ ⑥ ⑦ ⑧ ⑨ ⑩ ❶ ❷ ❸ ❹ ❺ ❻ ❼ ❽ ❾ ❿ ⑴ ⑵ ⑶ ⑷ ⑸ Ⅰ Ⅱ Ⅲ Ⅳ Ⅴ ㈠ ㈡ ㈢ ㈣ ㈤')],
    ['希臘', words('α β γ δ ε ζ η θ ι κ λ μ ν ξ ο π ρ σ τ υ φ χ ψ ω Ω Σ Δ')],
    ['框線', words('─ │ ┌ ┐ └ ┘ ├ ┤ ┬ ┴ ┼ ═ ║ ╔ ╗ ╚ ╝ ╭ ╮ ╰ ╯ ▁ ▂ ▃ ▄ ▅ ▆ ▇ █ ░ ▒ ▓')],
    ['日文', words('あ い う え お か き く け こ さ し す せ そ ア イ ウ エ オ カ キ ク ケ コ ー ッ')],
    ['注音', words('ㄅ ㄆ ㄇ ㄈ ㄉ ㄊ ㄋ ㄌ ㄍ ㄎ ㄏ ㄐ ㄑ ㄒ ㄓ ㄔ ㄕ ㄖ ㄗ ㄘ ㄙ ㄧ ㄨ ㄩ ㄚ ㄛ ㄜ ㄝ ㄞ ㄟ ㄠ ㄡ ㄢ ㄣ ㄤ ㄥ ㄦ ˊ ˇ ˋ ˙')]
  ];
  var clipId = 4;
  var CLIP = {
    cats: ['工作', '常用回覆'],
    items: [
      { id: 1, text: '下午三點在捷運站二號出口見～記得帶傘', pinned: true, cat: '' },
      { id: 2, text: '收到！我晚點整理好再傳給你', pinned: false, cat: '常用回覆' },
      { id: 3, text: '會議連結：週五 10:00 線上週會', pinned: false, cat: '工作' },
      { id: 4, text: '台北市大安區星光路 18 號 3 樓', pinned: false, cat: '' }
    ]
  };

  // ===== 花式文字（FancyText.swift 的 21 種） =====
  function cp(n) { return String.fromCodePoint(n); }
  function letterIdx(c) { var n = c.charCodeAt(0); return n >= 65 && n <= 90 ? n - 65 : n >= 97 && n <= 122 ? n - 97 : -1; }
  function mapChars(s, f) { return Array.from(s).map(function (c) { var r = f(c); return r == null ? c : r; }).join(''); }
  function letters(up, low, digit) {
    return function (s) {
      return mapChars(s, function (c) {
        var n = c.charCodeAt(0);
        if (n >= 65 && n <= 90) return cp(up + n - 65);
        if (n >= 97 && n <= 122) return cp(low + n - 97);
        if (digit && n >= 48 && n <= 57) return cp(digit + n - 48);
        return null;
      });
    };
  }
  var SMALL = 'ᴀʙᴄᴅᴇꜰɢʜɪᴊᴋʟᴍɴᴏᴘǫʀꜱᴛᴜᴠᴡxʏᴢ', FLIP = 'ɐqɔpǝɟƃɥᴉɾʞlɯuodbɹsʇnʌʍxʎz';
  var FANCY = [
    ['草寫', letters(0x1D4D0, 0x1D4EA)], ['粗體', letters(0x1D5D4, 0x1D5EE, 0x1D7EC)], ['斜體', letters(0x1D608, 0x1D622)], ['哥德', letters(0x1D56C, 0x1D586)],
    ['打字機', letters(0x1D670, 0x1D68A, 0x1D7F6)],
    ['圈圈', function (s) { return mapChars(s, function (c) { var n = c.charCodeAt(0); if (n >= 65 && n <= 90) return cp(0x24B6 + n - 65); if (n >= 97 && n <= 122) return cp(0x24D0 + n - 97); if (n === 48) return '⓪'; if (n >= 49 && n <= 57) return cp(0x2460 + n - 49); return null; }); }],
    ['黑圈', function (s) { return mapChars(s, function (c) { var i = letterIdx(c); return i < 0 ? null : cp(0x1F150 + i); }); }],
    ['方塊', function (s) { return mapChars(s, function (c) { var i = letterIdx(c); return i < 0 ? null : cp(0x1F170 + i); }); }],
    ['小型大寫', function (s) { return mapChars(s, function (c) { var i = letterIdx(c); return i < 0 ? null : SMALL[i]; }); }],
    ['全形', function (s) { return mapChars(s, function (c) { var n = c.charCodeAt(0); return n === 32 ? '　' : n > 32 && n < 127 ? String.fromCharCode(n + 0xFEE0) : null; }); }],
    ['倒過來', function (s) { return Array.from(mapChars(s.toLowerCase(), function (c) { var i = letterIdx(c); return i < 0 ? null : FLIP[i]; })).reverse().join(''); }],
    ['刪除線', function (s) { return Array.from(s).map(function (c) { return c + '̶'; }).join(''); }],
    ['底線', function (s) { return Array.from(s).map(function (c) { return c + '̲'; }).join(''); }],
    ['波浪', function (s) { return Array.from(s).map(function (c) { return c + '̰'; }).join(''); }],
    ['愛心', function (s) { return '♡ ' + s + ' ♡'; }], ['閃亮', function (s) { return '✧ ' + s + ' ✧'; }], ['星星', function (s) { return '⋆｡˚ ' + s + ' ˚｡⋆'; }],
    ['花花', function (s) { return '✿ ' + s + ' ✿'; }], ['括號', function (s) { return '꒰ ' + s + ' ꒱'; }], ['標題', function (s) { return '【' + s + '】'; }],
    ['一字一星', function (s) { return Array.from(s).join(' ✦ '); }]
  ];

  // ===== 翻譯（網頁只認得幾句；真的鍵盤用 Apple／Google 翻譯） =====
  var TARGETS = [['en', '英文'], ['ja', '日文'], ['ko', '韓文'], ['it', '義大利文'], ['zh-Hans', '簡體']];
  var TRANSLATIONS = {
    '你好': { en: 'Hello', ja: 'こんにちは', ko: '안녕하세요', it: 'Ciao', 'zh-Hans': '你好' },
    '謝謝': { en: 'Thank you', ja: 'ありがとう', ko: '감사합니다', it: 'Grazie', 'zh-Hans': '谢谢' },
    '晚安': { en: 'Good night', ja: 'おやすみ', ko: '잘 자요', it: 'Buona notte', 'zh-Hans': '晚安' },
    '我愛你': { en: 'I love you', ja: '愛してる', ko: '사랑해', it: 'Ti amo', 'zh-Hans': '我爱你' },
    '早安': { en: 'Good morning', ja: 'おはよう', ko: '좋은 아침', it: 'Buongiorno', 'zh-Hans': '早安' },
    '生日快樂': { en: 'Happy birthday', ja: 'お誕生日おめでとう', ko: '생일 축하해', it: 'Buon compleanno', 'zh-Hans': '生日快乐' },
    '對不起': { en: 'Sorry', ja: 'ごめんね', ko: '미안해', it: 'Scusa', 'zh-Hans': '对不起' },
    '再見': { en: 'Goodbye', ja: 'またね', ko: '안녕', it: 'Arrivederci', 'zh-Hans': '再见' }
  };
  var target = 0;

  // ===== 輸出 =====
  function editorActive() { return S.editor && !S.result; }
  function output(s) {
    if (!s) return;
    if (editorActive()) {
      var e = S.editor, c = e.cursor == null ? e.text.length : e.cursor;
      e.text = e.text.slice(0, c) + s + e.text.slice(c);
      if (e.cursor != null) e.cursor = c + s.length;
      return;
    }
    S.text = S.text.slice(0, S.caret) + s + S.text.slice(S.caret);
    S.caret += s.length;
  }
  function deleteBack() {
    if (editorActive()) {
      var e = S.editor, c = e.cursor == null ? e.text.length : e.cursor;
      if (c > 0) { var ch = Array.from(e.text.slice(0, c)).pop(); e.text = e.text.slice(0, c - ch.length) + e.text.slice(c); if (e.cursor != null) e.cursor = c - ch.length; }
      return;
    }
    if (S.caret > 0) { var ch2 = Array.from(S.text.slice(0, S.caret)).pop(); S.text = S.text.slice(0, S.caret - ch2.length) + S.text.slice(S.caret); S.caret -= ch2.length; }
  }
  function isComposing() { return !!(S.zy || S.py || S.romaji); }
  function candidates() {
    if (S.mode === 'zhuyin' || (S.mode === 'handwriting' && S.zy)) return zhuyinCandidates();
    if (S.mode === 'pinyin') return pinyinCandidates();
    if (S.mode === 'japanese') return japaneseCandidates();
    return [];
  }
  function lastChar() { var t = editorActive() ? S.editor.text : S.text.slice(0, S.caret); return Array.from(t).pop() || ''; }
  function afterCommit() {
    var ch = lastChar();
    if (!ch || /[，。？！～、\s]/.test(ch)) { S.suggestions = []; return; }
    var assoc = /[一-鿿]/.test(ch) ? associations(ch) : [];
    S.suggestions = ['，', '。', '？', '！', '～'].concat(assoc);
    S.suggestionKind = 'punct';
  }
  function choose(c) {
    S.learned[c.text] = (S.learned[c.text] || 0) + 1;
    if (S.mode === 'pinyin') {
      output(c.text); S.py = c.consume >= S.py.length ? '' : S.py.slice(c.consume);
    } else if (S.mode === 'japanese') {
      output(c.text); S.romaji = '';
    } else {
      output(c.text);
      var syl = parseZhuyin(S.zy).slice(c.consume);
      S.zy = syl.map(function (s) { return s.base + s.tone; }).join('');
    }
    S.expanded = false;
    if (!isComposing()) afterCommit();
  }
  function commitFirst() { var c = candidates()[0]; if (c) choose(c); else { S.zy = S.py = S.romaji = ''; } }
  function finishHangul() { if (S.hangul) { output(hangulText(S.hangul)); S.hangul = null; } }

  // ===== 按鍵版面（KeyLayouts.swift） =====
  var DACHEN = ['ㄅㄉˇˋㄓˊ˙ㄚㄞㄢㄦ', 'ㄆㄊㄍㄐㄔㄗㄧㄛㄟㄣ', 'ㄇㄋㄎㄑㄕㄘㄨㄜㄠㄤ', 'ㄈㄌㄏㄒㄖㄙㄩㄝㄡㄥ'];
  var MODE_INFO = {
    zhuyin: ['注音', '中', 'ㄅㄆㄇ'], english: ['English', '英', 'ABC'], pinyin: ['拼音', '拼', '拼音'],
    japanese: ['日本語', 'あ', 'かな'], korean: ['한국어', '한', '한글'], handwriting: ['手寫', '寫', '手寫']
  };
  function K(label, act, o) { o = o || {}; o.label = label; o.act = act; return o; }
  function chars(s, o) { return Array.from(s).map(function (c) { return K(c, 'c:' + c, o ? Object.assign({}, o) : {}); }); }
  function nextMode() { return S.modes[(S.modes.indexOf(S.mode) + 1) % S.modes.length]; }
  function returnTitle() { return isComposing() || S.hangul ? '確認' : (S.editor ? '完成' : '傳送'); }
  function bottomRow(cols) {
    var k = cols / 10;
    var row = [S.layer === 'letters' ? K('123', 'layer:numbers', { w: 1.3 * k, kind: 'special', fs: 15 }) : K(MODE_INFO[S.mode][2], 'layer:letters', { w: 1.3 * k, kind: 'special', fs: 13 })];
    row.push(K(MODE_INFO[nextMode()][1], 'mode', { w: 1.1 * k, kind: 'special', fs: 17 }));
    row.push(K('☺', 'panel:emoji', { w: 1.1 * k, kind: 'special', fs: 19 }));
    row.push(K(MODE_INFO[S.mode][0], 'space', { w: 0, fs: 14, wide: 1 }));
    row.push(K(returnTitle(), 'return', { w: 2 * k, kind: 'accent', fs: 15, wide: 1 }));
    return row;
  }
  function shiftKey() { return K(S.shift === 'locked' ? '⇪' : S.shift === 'on' ? '⬆' : '⇧', 'shift', { w: 1.4, kind: 'special', fs: 19 }); }
  function back(w) { return K('⌫', 'back', { w: w || 1.4, kind: 'special', fs: 19 }); }
  function layout() {
    var full = S.fullWidth, chinese = S.mode !== 'english' && S.mode !== 'korean';
    if (S.layer === 'numbers') {
      if (!chinese) return { cols: 10, rows: [chars('1234567890'), chars('-/:;()$&@"'), [K('#+=', 'layer:symbols', { w: 1.4, kind: 'special', fs: 15 })].concat(chars(".,?!'", { w: 1.4 })).concat([back()]), bottomRow(10)] };
      var digits = full ? '１２３４５６７８９０' : '1234567890';
      return { cols: 10, rows: [chars(digits, { fs: 20 }), chars('-/：；（）$@「」', { fs: 19 }), [K('#+=', 'layer:symbols', { w: 1.4, kind: 'special', fs: 15 })].concat(chars('。，、？！.', { w: 1.2, fs: 19 })).concat([back()]), bottomRow(10)] };
    }
    if (S.layer === 'symbols') {
      if (!chinese) return { cols: 10, rows: [chars('[]{}#%^*+='), chars('_\\|~<>€£¥`'), [K('123', 'layer:numbers', { w: 1.4, kind: 'special', fs: 15 })].concat(chars(".,?!'", { w: 1.4 })).concat([back()]), bottomRow(10)] };
      return { cols: 10, rows: [chars('`*_~|#\\^+=', { fs: 18 }), chars('{[]<>%}～—…', { fs: 18 }),
        [K('123', 'layer:numbers', { w: 1.25, kind: 'special', fs: 15 })].concat(chars('『』♡☆‧→※', { w: 0.9, fs: 17 })).concat([K(full ? '全形' : '半形', 'width', { w: 1.1, kind: 'special', fs: 13 }), back(1.35)]), bottomRow(10)] };
    }
    if (S.mode === 'zhuyin') {
      var rows = DACHEN.map(function (r) { return chars(r, { fs: 20 }); });
      rows[3].push(back(1));
      rows.push(bottomRow(11));
      return { cols: 11, rows: rows };
    }
    if (S.mode === 'korean') {
      var top = S.shift === 'off' ? 'ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔ' : 'ㅃㅉㄸㄲㅆㅛㅕㅑㅒㅖ';
      return { cols: 10, rows: [chars(top, { fs: 20 }), chars('ㅁㄴㅇㄹㅎㅗㅓㅏㅣ', { fs: 20 }), [shiftKey()].concat(chars('ㅋㅌㅊㅍㅠㅜㅡ', { fs: 20 })).concat([back()]), bottomRow(10)] };
    }
    var up = S.mode === 'english' && S.shift !== 'off';
    function L(s) { return chars(up ? s.toUpperCase() : s, { fs: 22 }); }
    var first = S.mode === 'english' ? shiftKey() : S.mode === 'japanese' ? K('ー', 'c:-', { w: 1.4, kind: 'special', fs: 19 }) : K("'", "c:'", { w: 1.4, kind: 'special', fs: 20 });
    return { cols: 10, rows: [L('qwertyuiop'), L('asdfghjkl'), [first].concat(L('zxcvbnm')).concat([back()]), bottomRow(10)] };
  }

  // ===== 畫出來 =====
  function el(tag, cls, text) { var e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }
  function shapeInfo() { return SHAPES.filter(function (s) { return s[0] === S.shape; })[0]; }
  function shapeSvg(id, cls) {
    var svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('viewBox', '0 0 100 100'); svg.setAttribute('preserveAspectRatio', 'none'); svg.setAttribute('aria-hidden', 'true');
    if (cls) svg.setAttribute('class', cls);
    var use = document.createElementNS('http://www.w3.org/2000/svg', 'use');
    use.setAttribute('href', '#preview-shape-' + id);
    svg.appendChild(use);
    if (cls === 'shape') {
      // 上亮下暗的漸層蓋在按鍵上，看起來鼓鼓的（和 App 的 cushionLayer 一樣）
      var shade = document.createElementNS('http://www.w3.org/2000/svg', 'use');
      shade.setAttribute('href', '#preview-shape-' + id); shade.setAttribute('class', 'shade');
      svg.appendChild(shade);
    }
    return svg;
  }
  function keyButton(k) {
    var b = el('button', 'sim-key' + (k.kind ? ' ' + k.kind : '') + (k.wide ? ' wide' : ''));
    b.type = 'button';
    b.dataset.act = k.act;
    b.setAttribute('aria-label', k.label === '⌫' ? '刪除' : k.label);
    var face = el('span', 'face'), info = shapeInfo();
    var soft = info[3];
    if (k.wide) {
      face.appendChild(shapeSvg(S.shape === 'bubble' || S.shape === 'mochi' ? 'bubble' : 'wide', 'shape'));
      if (soft) { var badge = shapeSvg(S.shape, 'badge'); face.appendChild(badge); }
      face.style.setProperty('--label-y', '50%');
    } else {
      face.appendChild(shapeSvg(S.shape, 'shape'));
      face.style.setProperty('--label-y', info[2] + '%');
    }
    face.appendChild(el('i', 'gloss'));
    var lbl = el('span', 'lbl', k.label);
    if (k.fs) lbl.style.setProperty('--kfs', k.fs + 'px');
    if (k.wide && soft) lbl.style.paddingLeft = '18%';
    face.appendChild(lbl);
    b.appendChild(face);
    b.style.flex = k.w === 0 ? '1 1 0' : (k.w || 1) + ' 0 0';
    return b;
  }
  function renderKeys() {
    var lay = layout(), wrap = el('div', 'sim-keys');
    lay.rows.forEach(function (row) {
      var r = el('div', 'sim-row');
      var used = row.reduce(function (a, k) { return a + (k.w === 0 ? 0 : (k.w || 1)); }, 0);
      var flex = row.some(function (k) { return k.w === 0; });
      if (!flex && used < lay.cols) { var pad = (lay.cols - used) / 2; r.appendChild(spacer(pad)); }
      row.forEach(function (k) { if (k.w === 0) k.w = Math.max(1, lay.cols - used); r.appendChild(keyButton(k)); });
      if (!flex && used < lay.cols) r.appendChild(spacer((lay.cols - used) / 2));
      wrap.appendChild(r);
    });
    return wrap;
  }
  function spacer(w) { var s = el('span'); s.style.flex = w + ' 0 0'; return s; }

  var ICONS = {
    clipboard: '<svg viewBox="0 0 24 24"><rect x="6" y="4.5" width="12" height="16" rx="2.5"/><path d="M9 4.5h6v2.5H9z"/></svg>',
    emoji: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="8.5"/><path d="M8.5 14.2c1.8 2 5.2 2 7 0"/><circle cx="9.3" cy="10" r=".6" fill="currentColor"/><circle cx="14.7" cy="10" r=".6" fill="currentColor"/></svg>',
    translate: '<svg viewBox="0 0 24 24"><path d="M4 6h9M8.5 4v2M6 6c.8 3 3 5.5 6 7M11 6c-.8 3-3 5.5-6 7"/><path d="M13 20l3.5-8 3.5 8M14.2 17.5h4.6"/></svg>',
    handwriting: '<svg viewBox="0 0 24 24"><path d="M4 18c3-6 5-10 7-10s-1 8 2 8 3-5 7-5"/></svg>',
    voice: '<svg viewBox="0 0 24 24"><rect x="9" y="3.5" width="6" height="11" rx="3"/><path d="M6 11.5a6 6 0 0 0 12 0M12 17.5V20"/></svg>',
    settings: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="3"/><path d="M12 3.5v2.2M12 18.3v2.2M3.5 12h2.2M18.3 12h2.2M6 6l1.6 1.6M16.4 16.4 18 18M6 18l1.6-1.6M16.4 7.6 18 6"/></svg>',
    dismiss: '<svg viewBox="0 0 24 24"><rect x="3.5" y="5" width="17" height="10" rx="2"/><path d="M7 8.5h.01M10 8.5h.01M13 8.5h.01M16 8.5h.01M8 12h8M9 18.5l3 2 3-2"/></svg>'
  };
  var TOOLS = [['clipboard', '剪貼簿'], ['emoji', '表情符號'], ['kaomoji', '顏文字', '(•ᴗ•)'], ['symbols', '符號', '※'], ['fancy', '花式文字', '𝒜'], ['translate', '翻譯'], ['handwriting', '手寫'], ['voice', '語音輸入'], ['settings', '設定'], ['dismiss', '收起鍵盤']];

  function renderTop() {
    topbar.replaceChildren();
    if (S.hidden) return;
    if (S.result) {
      var bar = candBar(S.result.title, S.result.items.concat(['✏️ 修改']), function (t, i) {
        if (i === S.result.items.length) { S.result = null; render(); return; }
        var r = S.result.items[i]; S.result = null; S.editor = null; output(r); afterCommit(); render();
      }, 'close');
      topbar.appendChild(bar); return;
    }
    if (isComposing()) {
      var list = candidates(), reading = '';
      if (S.mode === 'zhuyin' || S.mode === 'handwriting') reading = parseZhuyin(S.zy).map(function (s) { return s.base + (s.tone === 'ˉ' ? '' : s.tone); }).join(' ');
      else if (S.mode === 'pinyin') reading = S.py;
      else reading = romajiToKana(S.romaji);
      if (S.editor) reading = editorLabel() + editorWindow('［' + reading + '］');
      topbar.appendChild(candBar(reading, list, function (t, i) { choose(list[i]); render(); }, 'expand'));
      return;
    }
    if (S.editor && !(S.suggestions.length && S.suggestionKind !== 'punct')) { topbar.appendChild(editorBar()); return; }
    if (S.suggestions.length) {
      topbar.appendChild(candBar('', S.suggestions, function (t) {
        if (S.suggestionKind === 'english') { var w = currentWord(); S.caret -= w.length; S.text = S.text.slice(0, S.caret) + S.text.slice(S.caret + w.length); output(t + ' '); S.suggestions = []; }
        else { output(t); if (/[，。？！～]/.test(t)) S.suggestions = []; else afterCommit(); }
        render();
      }, 'close'));
      return;
    }
    var tools = el('div', 'sim-tools');
    TOOLS.forEach(function (t) {
      var b = el('button'); b.type = 'button'; b.title = t[1]; b.setAttribute('aria-label', t[1]);
      if (t[2]) { b.textContent = t[2]; if (t[2].length > 2) b.className = 'small'; } else b.innerHTML = ICONS[t[0]];
      var on = S.panel === t[0] || (t[0] === 'handwriting' && S.mode === 'handwriting') || (S.editor && S.editor.kind === t[0]);
      b.setAttribute('aria-pressed', on ? 'true' : 'false');
      b.addEventListener('click', function () { tool(t[0]); });
      tools.appendChild(b);
    });
    topbar.appendChild(tools);
  }
  function candBar(reading, list, onPick, trailing) {
    var wrap = el('div', 'sim-candbar');
    wrap.appendChild(el('div', 'sim-reading', reading || ''));
    var row = el('div', 'sim-candrow');
    if (S.mode === 'pinyin' && isComposing()) {
      var sc = el('button', 'sim-script', S.simplified ? '簡' : '繁'); sc.type = 'button'; sc.title = '繁體／簡體';
      sc.addEventListener('click', function () { S.simplified = !S.simplified; render(); }); row.appendChild(sc);
    }
    var cands = el('div', 'sim-cands');
    list.forEach(function (c, i) {
      var text = typeof c === 'string' ? c : c.text;
      var b = el('button', (i === 0 && trailing === 'expand' ? 'first' : '') + (text.length === 1 && /[，。？！～]/.test(text) ? ' punct' : ''), text);
      b.type = 'button';
      if (c.tag) b.appendChild(el('span', 'tag', c.tag));
      b.addEventListener('click', function () { onPick(text, i); });
      cands.appendChild(b);
    });
    row.appendChild(cands);
    var more = el('button', 'more', trailing === 'expand' ? (S.expanded ? '︿' : '﹀') : '✕'); more.type = 'button';
    more.setAttribute('aria-label', trailing === 'expand' ? '展開候選字' : '關掉');
    more.addEventListener('click', function () {
      if (trailing === 'expand') S.expanded = !S.expanded; else { S.suggestions = []; S.result = null; }
      render();
    });
    row.appendChild(more);
    wrap.appendChild(row);
    return wrap;
  }
  // 編輯框的字只顯示游標附近，mid 放在游標的位置
  function editorWindow(mid) {
    var e = S.editor, arr = Array.from(e.text), c = e.cursor == null ? arr.length : Array.from(e.text.slice(0, e.cursor)).length;
    return (c > 10 ? '…' : '') + arr.slice(Math.max(0, c - 10), c).join('') + mid + arr.slice(c, c + 6).join('') + (arr.length - c > 6 ? '…' : '');
  }
  function editorLabel() { return { clip: '編輯剪貼簿：', translate: '翻譯：', fancy: '花式文字：', kao: '新增表符：' }[S.editor.kind]; }
  function editorBar() {
    var e = S.editor, bar = el('div', 'sim-editor'), txt = el('div', 'text');
    txt.appendChild(el('b', '', editorLabel()));
    var chars2 = Array.from(e.text), c = e.cursor == null ? chars2.length : Array.from(e.text.slice(0, e.cursor)).length;
    var before = chars2.slice(Math.max(0, c - 12), c).join(''), after = chars2.slice(c, c + 8).join('');
    txt.appendChild(document.createTextNode((c > 12 ? '…' : '') + before));
    txt.appendChild(el('span', 'sim-caret'));
    txt.appendChild(document.createTextNode(after + (chars2.length - c > 8 ? '…' : '')));
    if (!e.text && e.kind === 'fancy') txt.appendChild(el('span', '', ' 打英文看看'));
    bar.appendChild(txt);
    if (e.kind === 'translate') {
      var to = el('button', 'chip', '→' + TARGETS[target][1]); to.type = 'button';
      to.addEventListener('click', function () { target = (target + 1) % TARGETS.length; render(); });
      bar.appendChild(to);
    }
    var cancel = el('button', '', '取消'); cancel.type = 'button';
    cancel.addEventListener('click', function () { endEditor(); render(); });
    bar.appendChild(cancel);
    if (e.kind !== 'fancy') {
      var ok = el('button', 'ok', { clip: '儲存', translate: '翻譯', kao: '儲存' }[e.kind]); ok.type = 'button';
      ok.addEventListener('click', confirmEditor);
      bar.appendChild(ok);
    }
    return bar;
  }
  function endEditor() {
    var reopen = S.editor && (S.editor.kind === 'clip' || S.editor.kind === 'kao') ? (S.editor.kind === 'clip' ? 'clipboard' : 'kaomoji') : null;
    S.editor = null; S.result = null; S.zy = S.py = S.romaji = ''; S.suggestions = [];
    if (reopen) S.panel = reopen;
  }
  function confirmEditor() {
    var e = S.editor; commitFirst();
    if (e.kind === 'clip') {
      CLIP.items.forEach(function (it) { if (it.id === e.id) it.text = e.text || it.text; });
      endEditor(); toast('已儲存');
    } else if (e.kind === 'kao') {
      if (e.text.trim()) KAOMOJI[KAOMOJI.length - 1][1].push(e.text.trim());
      endEditor(); S.panelTab = KAOMOJI.length - 1; toast('加到「我的表符」了');
    } else if (e.kind === 'translate') {
      var src = e.text.replace(/[，。？！～\s]/g, ''), tr = TRANSLATIONS[src];
      if (!e.text.trim()) { toast('先打要翻譯的字'); return render(); }
      S.result = { title: '翻成' + TARGETS[target][1] + '：', items: [tr ? tr[TARGETS[target][0]] : '（網頁示範只認得：你好、謝謝、晚安、我愛你、早安、生日快樂、對不起、再見）'] };
      if (!tr) S.result.items = [];
      if (!tr) toast('網頁示範只認得幾句，例如「謝謝」');
    }
    render();
  }

  function renderMain() {
    main.replaceChildren();
    if (S.hidden) {
      var wake = el('button', 'sim-wake', '點這裡叫出鍵盤 ⌨︎'); wake.type = 'button';
      wake.addEventListener('click', function () { S.hidden = false; render(); });
      main.appendChild(wake); return;
    }
    if (S.expanded && isComposing()) return main.appendChild(expandedPanel());
    if (S.panel) return main.appendChild(panelView());
    if (S.editor && S.editor.kind === 'fancy' && !isComposing()) return main.appendChild(withKeys(fancyList()));
    if (S.mode === 'handwriting' && S.layer === 'letters') return main.appendChild(handwritingView());
    main.appendChild(renderKeys());
  }
  function withKeys(extra) { var w = el('div'); w.appendChild(extra); w.appendChild(renderKeys()); return w; }
  function expandedPanel() {
    var p = el('div', 'sim-panel'), g = el('div', 'sim-grid sym');
    candidates().forEach(function (c) { var b = el('button', '', c.text); b.type = 'button'; b.style.gridColumn = c.text.length > 2 ? 'span ' + Math.min(4, Math.ceil(c.text.length / 2)) : ''; b.addEventListener('click', function () { choose(c); render(); }); g.appendChild(b); });
    p.appendChild(g); p.appendChild(foot('收起', function () { S.expanded = false; render(); }));
    return p;
  }
  function foot(label, onBack, extra) {
    var f = el('div', 'sim-panel-foot'), b = el('button', '', label); b.type = 'button'; b.addEventListener('click', onBack); f.appendChild(b);
    f.appendChild(el('span', 'grow', extra || ''));
    var d = el('button', '', '⌫'); d.type = 'button'; d.setAttribute('aria-label', '刪除');
    d.addEventListener('click', function () { deleteBack(); render(); }); f.appendChild(d);
    return f;
  }
  function tabs(names, onPick) {
    var t = el('div', 'sim-tabs');
    names.forEach(function (n, i) { var b = el('button', '', n); b.type = 'button'; b.setAttribute('aria-pressed', i === S.panelTab ? 'true' : 'false'); b.addEventListener('click', function () { S.panelTab = i; onPick && onPick(i); render(); }); t.appendChild(b); });
    return t;
  }
  function closePanel() { S.panel = null; S.panelTab = 0; render(); }
  function panelView() {
    var p = el('div', 'sim-panel'), back = MODE_INFO[S.mode][2];
    if (S.panel === 'emoji' || S.panel === 'symbols' || S.panel === 'kaomoji') {
      var data = S.panel === 'emoji' ? EMOJI : S.panel === 'symbols' ? SYMBOLS : KAOMOJI;
      S.panelTab = Math.min(S.panelTab, data.length - 1);
      p.appendChild(tabs(data.map(function (d) { return d[0]; })));
      var g = el('div', 'sim-grid ' + (S.panel === 'emoji' ? 'emoji' : S.panel === 'symbols' ? 'sym' : 'kao'));
      data[S.panelTab][1].forEach(function (s) { var b = el('button', '', s); b.type = 'button'; b.addEventListener('click', function () { output(s); toastOnce(S.panel); renderInput(); }); g.appendChild(b); });
      if (S.panel === 'kaomoji' && S.panelTab === data.length - 1) {
        var add = el('button', '', '＋ 新增'); add.type = 'button';
        add.addEventListener('click', function () { S.panel = null; S.editor = { kind: 'kao', text: '', cursor: null }; render(); });
        g.appendChild(add);
      }
      p.appendChild(g);
      p.appendChild(foot(back, closePanel, S.panel === 'kaomoji' ? '「我的表符」可以自己新增' : ''));
    } else if (S.panel === 'clipboard') {
      var names = ['全部', '📌 釘選'].concat(CLIP.cats);
      p.appendChild(tabs(names));
      var list = el('div', 'sim-grid list');
      CLIP.items.filter(function (it) { return S.panelTab === 0 || (S.panelTab === 1 ? it.pinned : it.cat === names[S.panelTab]); })
        .sort(function (a, b) { return b.pinned - a.pinned; })
        .forEach(function (it) {
          var row = el('div', 'sim-clip'), t = el('button', 't', it.text); t.type = 'button'; t.title = '點一下貼上';
          t.addEventListener('click', function () { output(it.text); afterCommit(); closePanel(); });
          var pin = el('button', 'i' + (it.pinned ? ' pin' : ''), '📌'); pin.type = 'button'; pin.setAttribute('aria-label', it.pinned ? '取消釘選' : '釘選');
          pin.style.opacity = it.pinned ? 1 : .35;
          pin.addEventListener('click', function () { it.pinned = !it.pinned; render(); });
          var ed = el('button', 'i', '✎'); ed.type = 'button'; ed.setAttribute('aria-label', '編輯');
          ed.addEventListener('click', function () {
            S.panel = null; S.editor = { kind: 'clip', id: it.id, text: it.text, cursor: it.text.length };
            toast('按住空白鍵左右滑，移到要改的地方'); render();
          });
          row.appendChild(t); row.appendChild(pin); row.appendChild(ed); list.appendChild(row);
        });
      var addCur = el('button', '', '＋ 加入剛剛複製的文字'); addCur.type = 'button'; addCur.style.fontSize = '14px';
      addCur.addEventListener('click', function () { CLIP.items.unshift({ id: ++clipId, text: '（網頁示範）剛剛複製的一段話 ' + clipId, pinned: false, cat: '' }); S.panelTab = 0; render(); });
      list.appendChild(addCur);
      p.appendChild(list);
      p.appendChild(foot(back, closePanel, '可以釘選、分類、改內容'));
    } else if (S.panel === 'voice') {
      var n = el('div', 'sim-note');
      n.innerHTML = '<b>語音輸入</b><br>iPhone：鍵盤下面的 🎤 是系統聽寫，講完會自動變成字。<br>Android：工具列的麥克風會打開 Google 語音輸入。<br><small>網頁試玩沒有收音。</small>';
      p.appendChild(n); var sp = el('div'); sp.style.flex = '1'; p.appendChild(sp);
      p.appendChild(foot(back, closePanel));
    } else if (S.panel === 'settings') {
      p.appendChild(settingsView());
      p.appendChild(foot('完成', closePanel, '和右邊的選項是同一組設定'));
    }
    return p;
  }
  var toasted = {};
  function toastOnce(kind) { if (!toasted[kind]) { toasted[kind] = 1; toast('已打到上面的輸入框'); } }
  function fancyList() {
    var src = S.editor.text || 'Hello', g = el('div', 'sim-grid list');
    g.style.height = 'calc(var(--row-h) * 2.2)'; g.style.padding = '0 4px 4px';
    FANCY.forEach(function (f) {
      var out = f[1](src), b = el('button', 'sim-fancy'); b.type = 'button';
      b.appendChild(el('small', '', f[0])); b.appendChild(el('span', '', out));
      b.addEventListener('click', function () { S.editor = null; output(out); afterCommit(); toast('已打進輸入框'); render(); });
      g.appendChild(b);
    });
    return g;
  }
  var hwGuesses = [['一', '二', '三', '十', '土'], ['人', '入', '八', '大', '天'], ['你', '好', '愛', '心', '的']], hwStrokes = 0;
  function handwritingView() {
    var w = el('div', 'sim-hw'), c = el('canvas'); c.setAttribute('aria-label', '手寫板');
    w.appendChild(c);
    var side = el('div', 'side');
    [K('⌫', 'back', { kind: 'special', fs: 18 }), K('重寫', 'clear', { kind: 'special', fs: 13 }), K('123', 'layer:numbers', { kind: 'special', fs: 13 }),
      K('空白', 'space', { fs: 13 }), K(MODE_INFO[nextMode()][1], 'mode', { kind: 'special', fs: 16 }), K(returnTitle(), 'return', { kind: 'accent', fs: 13 })]
      .forEach(function (k) { var r = el('div', 'sim-row'); r.appendChild(keyButton(k)); side.appendChild(r); });
    w.appendChild(side);
    requestAnimationFrame(function () { setupCanvas(c); });
    return w;
  }
  function setupCanvas(c) {
    var r = c.getBoundingClientRect(), dpr = window.devicePixelRatio || 1;
    c.width = r.width * dpr; c.height = r.height * dpr;
    var g = c.getContext('2d'); g.scale(dpr, dpr); g.lineWidth = 5; g.lineCap = g.lineJoin = 'round';
    g.strokeStyle = getComputedStyle(phone).getPropertyValue('--key-text');
    g.font = '13px system-ui'; g.fillStyle = g.strokeStyle; g.globalAlpha = .45; g.fillText('在這裡用手指寫字（網頁示意）', 12, 22); g.globalAlpha = 1;
    var drawing = false, first = true;
    c.addEventListener('pointerdown', function (e) {
      if (first) { g.clearRect(0, 0, r.width, r.height); first = false; }
      drawing = true; c.setPointerCapture(e.pointerId); g.beginPath(); g.moveTo(e.offsetX, e.offsetY);
    });
    c.addEventListener('pointermove', function (e) { if (drawing) { g.lineTo(e.offsetX, e.offsetY); g.stroke(); } });
    c.addEventListener('pointerup', function () {
      if (!drawing) return; drawing = false; hwStrokes++;
      var list = hwGuesses[Math.min(2, Math.floor((hwStrokes - 1) / 2))];
      topbar.replaceChildren(candBar('手寫（網頁示意：真的鍵盤會認你寫的字）', list, function (t) { output(t); hwStrokes = 0; afterCommit(); render(); }, 'close'));
    });
  }
  function settingsView() {
    var s = el('div', 'sim-set');
    function group(title, items, cur, set) {
      s.appendChild(el('h4', '', title));
      var row = el('div', 'row');
      items.forEach(function (it) { var b = el('button', '', it[1]); b.type = 'button'; b.setAttribute('aria-pressed', it[0] === cur ? 'true' : 'false'); b.addEventListener('click', function () { set(it[0]); }); row.appendChild(b); });
      s.appendChild(row);
    }
    group('主題', Object.keys(THEMES).map(function (k) { return [k, THEMES[k].name]; }), S.theme, setTheme);
    group('按鍵造型', SHAPES, S.shape, setShape);
    group('按鍵質感', FINISHES, S.finish, setFinish);
    group('按鍵特效', EFFECTS, S.effect, setEffect);
    group('字體', FONTS, S.font, setFont);
    group('按鍵聲', [['off', '關'], ['on', '叮叮']], S.sound ? 'on' : 'off', function (v) { S.sound = v === 'on'; $('sim-sound').checked = S.sound; render(); });
    return s;
  }

  function renderInput() {
    inputEl.replaceChildren();
    var before = S.text.slice(0, S.caret), after = S.text.slice(S.caret), mark = S.hangul ? hangulText(S.hangul) : '';
    if (!S.text && !mark) { inputEl.appendChild(el('span', 'sim-caret')); inputEl.appendChild(el('span', 'ph', '傳訊息給糯糯…')); return; }
    inputEl.appendChild(document.createTextNode(before));
    if (mark) inputEl.appendChild(el('span', 'comp', mark));
    if (!S.editor) inputEl.appendChild(el('span', 'sim-caret'));
    inputEl.appendChild(document.createTextNode(after));
  }
  function render() {
    phone.dataset.shape = S.shape; phone.dataset.finish = S.finish; phone.dataset.soft = shapeInfo()[3] ? "1" : "0";
    kb.classList.toggle('hidden', S.hidden);
    if (!isComposing() && S.mode === 'english' && !S.editor && !S.result) {
      var en = englishSuggestions();
      if (en.length) { S.suggestions = en; S.suggestionKind = 'english'; } else if (S.suggestionKind === 'english') S.suggestions = [];
    }
    renderTop(); renderMain(); renderInput();
  }

  // ===== 按鍵動作 =====
  function act(a) {
    var p = a.split(':'), kind = p[0], val = a.slice(kind.length + 1);
    if (kind !== 'back' && kind !== 'c' && S.suggestionKind === 'punct') S.suggestions = [];
    if (kind === 'c') {
      if (S.suggestionKind !== 'english') S.suggestions = [];
      if (S.layer !== 'letters') { output(val); if (/[。，？！]/.test(val)) S.suggestions = []; return; }
      if (S.mode === 'zhuyin' || S.mode === 'handwriting') {
        // 同一個音節打第二個聲調：換掉
        if (TONES.indexOf(val) >= 0 && !S.zy) { output(val); return; }
        S.zy += val; S.expanded = false; return;
      }
      if (S.mode === 'pinyin') { S.py += val.toLowerCase(); return; }
      if (S.mode === 'japanese') { S.romaji += val.toLowerCase(); return; }
      if (S.mode === 'korean') { hangulInput(val); if (S.shift === 'on') S.shift = 'off'; return; }
      // 英文
      output(val);
      if (S.shift === 'on') S.shift = 'off';
      return;
    }
    if (kind === 'back') {
      if (S.zy) { S.zy = S.zy.slice(0, -1); return; }
      if (S.py) { S.py = S.py.slice(0, -1); return; }
      if (S.romaji) { S.romaji = S.romaji.slice(0, -1); return; }
      if (S.mode === 'korean' && hangulBack()) return;
      if (S.suggestions.length && S.suggestionKind === 'punct') S.suggestions = [];
      deleteBack(); return;
    }
    if (kind === 'space') {
      if (S.zy) {
        var last = parseZhuyin(S.zy).pop();
        if (last && !last.tone) S.zy += 'ˉ'; else commitFirst();
        return;
      }
      if (S.py || S.romaji) { commitFirst(); return; }
      finishHangul();
      if (S.mode === 'english') {
        var w = currentWord(), fix = AUTOCORRECT[w.toLowerCase()];
        if (fix && !S.editor) { S.text = S.text.slice(0, S.caret - w.length) + fix + S.text.slice(S.caret); S.caret += fix.length - w.length; toast('自動修正：' + w + ' → ' + fix); }
        if (S.text.slice(S.caret - 1, S.caret) === ' ' && /\w/.test(S.text.slice(S.caret - 2, S.caret - 1))) { deleteBack(); output('. '); S.shift = 'on'; return; }
      }
      output(' '); S.suggestions = []; return;
    }
    if (kind === 'return') {
      if (isComposing()) { commitFirst(); return; }
      finishHangul();
      if (S.editor) { confirmEditor(); return; }
      send(); return;
    }
    if (kind === 'shift') { S.shift = S.shift === 'off' ? 'on' : S.shift === 'on' ? 'locked' : 'off'; return; }
    if (kind === 'layer') { commitFirst(); finishHangul(); S.layer = val; return; }
    if (kind === 'width') { S.fullWidth = !S.fullWidth; toast(S.fullWidth ? '數字改成全形' : '數字改成半形'); return; }
    if (kind === 'mode') { commitFirst(); finishHangul(); S.mode = nextMode(); S.layer = 'letters'; S.shift = S.mode === 'english' && !S.text ? 'on' : 'off'; S.suggestions = []; toast(MODE_INFO[S.mode][0]); return; }
    if (kind === 'panel') { tool(val); return; }
    if (kind === 'clear') { hwStrokes = 0; return; }
  }
  function tool(name) {
    commitFirst(); finishHangul(); S.suggestions = []; S.expanded = false;
    if (name === 'dismiss') { S.hidden = true; S.panel = null; return render(); }
    if (name === 'handwriting') { S.panel = null; S.mode = S.mode === 'handwriting' ? 'zhuyin' : 'handwriting'; S.layer = 'letters'; return render(); }
    if (name === 'fancy' || name === 'translate') {
      S.panel = null;
      S.editor = S.editor && S.editor.kind === name ? null : { kind: name, text: '', cursor: null };
      if (name === 'fancy' && S.editor && S.mode === 'zhuyin') { S.mode = 'english'; toast('花式文字要打英文，已切到英文'); }
      return render();
    }
    S.panel = S.panel === name ? null : name; S.panelTab = 0;
    render();
  }

  // ===== 聊天 =====
  var REPLIES = [['你好', '你好呀～ (◍•ᴗ•◍)'], ['晚安', '晚安，好夢 🌙'], ['謝', '不客氣 ♡'], ['愛', '我也愛你 (*´▽`*)'], ['生日', '生日快樂！🎂'], ['可愛', '你也很可愛 (〃∀〃)'], ['hello', 'Hi there! ✧'], ['hi', 'Hello～ ʕ•ᴥ•ʔ']];
  var FALLBACK = ['收到～', '哈哈哈 (≧▽≦)', '好喔！', '嗯嗯 (•ᴗ•)', '真的嗎！', '太棒了 ✨'];
  function addMsg(text, who) { var m = el('div', 'sim-msg ' + who, text); chatEl.appendChild(m); chatEl.scrollTop = chatEl.scrollHeight; }
  function send() {
    var t = S.text.trim(); if (!t) { toast('先打點字再傳送'); return; }
    addMsg(t, 'me'); S.text = ''; S.caret = 0; S.suggestions = [];
    var reply = REPLIES.filter(function (r) { return t.toLowerCase().indexOf(r[0]) >= 0; })[0];
    setTimeout(function () { addMsg(reply ? reply[1] : FALLBACK[Math.floor(Math.random() * FALLBACK.length)], 'them'); }, 700);
  }

  // ===== 觸控：按下去的樣子、特效、刪除鍵連續刪、空白鍵拖曳移動游標 =====
  var audio = null, repeatTimer = null, drag = null;
  function sound() {
    if (!S.sound) return;
    if (!audio) { audio = new Audio('assets/preview-tink.wav'); audio.volume = .5; }
    try { audio.currentTime = 0; audio.play().catch(function () {}); } catch (e) {}
  }
  function spawnFx(b) {
    var glyphs = EFFECTS.filter(function (e) { return e[0] === S.effect; })[0][2];
    if (!glyphs.length || fxEl.childElementCount > 40) return;
    var kr = kb.getBoundingClientRect(), r = b.getBoundingClientRect();
    for (var i = 0; i < 3; i++) {
      var s = el('span', '', glyphs[Math.floor(Math.random() * glyphs.length)]);
      s.style.left = (r.left - kr.left + r.width / 2 - 6) + 'px'; s.style.top = (r.top - kr.top + r.height / 3) + 'px';
      s.style.setProperty('--dx', ((Math.random() - .5) * 50) + 'px'); s.style.setProperty('--dy', (-(26 + Math.random() * 26)) + 'px');
      s.style.setProperty('--rot', ((Math.random() - .5) * 90) + 'deg');
      s.style.color = i === 0 ? THEMES[S.theme].accent : THEMES[S.theme].text;
      s.style.fontSize = (11 + Math.random() * 8) + 'px';
      fxEl.appendChild(s);
      s.addEventListener('animationend', function () { this.remove(); });
    }
  }
  var popup = null;
  function showPopup(b) {
    if (b.classList.contains('special') || b.classList.contains('accent') || b.classList.contains('wide')) return;
    var kr = kb.getBoundingClientRect(), r = b.getBoundingClientRect();
    popup = el('div', 'sim-popup', b.querySelector('.lbl').textContent);
    popup.style.left = (r.left - kr.left + r.width / 2) + 'px'; popup.style.top = (r.top - kr.top + 2) + 'px';
    kb.appendChild(popup);
  }
  function hidePopup() { if (popup) { popup.remove(); popup = null; } }
  main.addEventListener('pointerdown', function (e) {
    var b = e.target.closest('.sim-key'); if (!b) return;
    e.preventDefault();
    b.setPointerCapture(e.pointerId);
    b.classList.add('down'); spawnFx(b); sound(); showPopup(b);
    if (navigator.vibrate) try { navigator.vibrate(8); } catch (x) {}
    var a = b.dataset.act;
    if (a === 'back') {
      act('back'); render(); var bb = main.querySelector('[data-act="back"]'); if (bb) bb.classList.add('down');
      repeatTimer = setTimeout(function rep() { act('back'); renderTop(); renderInput(); repeatTimer = setTimeout(rep, 70); }, 420);
    }
    if (a === 'space') drag = { x: e.clientX, moved: false, steps: 0 };
  });
  main.addEventListener('pointermove', function (e) {
    if (!drag) return;
    var dx = e.clientX - drag.x;
    if (!drag.moved && Math.abs(dx) > 14 && !isComposing()) { drag.moved = true; drag.x = e.clientX; dx = 0; toast('游標移動中…'); }
    if (drag.moved) {
      var steps = Math.trunc(dx / 9);
      if (steps !== drag.steps) { moveCursor(steps - drag.steps); drag.steps = steps; }
    }
  });
  function moveCursor(n) {
    if (S.editor && S.editor.cursor != null) {
      var arr = Array.from(S.editor.text), c = Array.from(S.editor.text.slice(0, S.editor.cursor)).length;
      c = Math.max(0, Math.min(arr.length, c + n)); S.editor.cursor = arr.slice(0, c).join('').length; renderTop(); return;
    }
    var a2 = Array.from(S.text), c2 = Array.from(S.text.slice(0, S.caret)).length;
    c2 = Math.max(0, Math.min(a2.length, c2 + n)); S.caret = a2.slice(0, c2).join('').length; renderInput();
  }
  function release(e, cancel) {
    var b = e.target.closest && e.target.closest('.sim-key');
    clearTimeout(repeatTimer); repeatTimer = null; hidePopup();
    main.querySelectorAll('.sim-key.down').forEach(function (k) { k.classList.remove('down'); });
    if (!b || cancel) { drag = null; return; }
    var a = b.dataset.act;
    if (a === 'back') return;
    if (a === 'space' && drag && drag.moved) { drag = null; return; }
    drag = null;
    act(a);
    // 剪貼簿編輯時，空白鍵沒有拖就是打空白
    render();
  }
  main.addEventListener('pointerup', function (e) { release(e, false); });
  main.addEventListener('pointercancel', function (e) { release(e, true); });
  // 實體鍵盤也可以打（電腦上試玩）
  var KEYMAP = {};
  'ㄅ1ㄉ2ˇ3ˋ4ㄓ5ˊ6˙7ㄚ8ㄞ9ㄢ0ㄦ-ㄆqㄊwㄍeㄐrㄔtㄗyㄧuㄛiㄟoㄣpㄇaㄋsㄎdㄑfㄕgㄘhㄨjㄜkㄠlㄤ;ㄈzㄌxㄏcㄒvㄖbㄙnㄩmㄝ,ㄡ.ㄥ/'.replace(/(.)(.)/g, function (m, z, k) { KEYMAP[k] = z; return ''; });
  phone.tabIndex = 0;
  phone.addEventListener('keydown', function (e) {
    if (e.metaKey || e.ctrlKey || e.altKey || S.hidden) return;
    var k = e.key, a = null;
    if (k === 'Backspace') a = 'back'; else if (k === ' ') a = 'space'; else if (k === 'Enter') a = 'return';
    else if (k === 'ArrowLeft') { moveCursor(-1); e.preventDefault(); return; } else if (k === 'ArrowRight') { moveCursor(1); e.preventDefault(); return; }
    else if (k.length === 1) {
      if (S.layer === 'letters' && (S.mode === 'zhuyin' || S.mode === 'handwriting') && KEYMAP[k.toLowerCase()]) a = 'c:' + KEYMAP[k.toLowerCase()];
      else if (S.mode === 'korean' && S.layer === 'letters') return;
      else a = 'c:' + k;
    }
    if (!a) return;
    e.preventDefault(); act(a); render();
  });

  function toast(t) {
    toastEl.textContent = t; toastEl.hidden = false;
    clearTimeout(toast.timer); toast.timer = setTimeout(function () { toastEl.hidden = true; }, 1800);
  }

  // ===== 外觀設定 =====
  function setTheme(id) {
    S.theme = id; var t = THEMES[id];
    var map = { top: 'top', bottom: 'bottom', key: 'key', text: 'key-text', special: 'special', specialText: 'special-text', accent: 'key-accent', accentText: 'accent-text', shadow: 'key-shadow' };
    Object.keys(map).forEach(function (k) { phone.style.setProperty('--' + map[k], t[k]); });
    phone.style.setProperty('--key-face', t.key);
    $('sim-theme-name').textContent = t.name;
    pressed('#sim-colors button', id); setDetail(); render();
  }
  function setDetail() { var d = DETAIL[S.shape], t = THEMES[S.theme]; phone.style.setProperty('--detail', d ? d[t.dark ? 1 : 0] : t.accent); }
  function setShape(id) { S.shape = id; $('sim-shape-name').textContent = shapeInfo()[1]; pressed('#sim-shapes button', id); setDetail(); render(); }
  function setFinish(id) { S.finish = id; pressed('#sim-finishes button', id); render(); }
  function setEffect(id) { S.effect = id; pressed('#sim-effects button', id); render(); }
  var loadedFonts = {};
  function setFont(id) {
    var f = FONTS.filter(function (x) { return x[0] === id; })[0];
    S.font = id; pressed('#sim-fonts button', id); $('sim-font-name').textContent = f[1];
    var stack = ', system-ui, -apple-system, "PingFang TC", "Noto Sans TC", sans-serif';
    function apply() { phone.style.setProperty('--kfont', f[2] ? '"' + f[2] + '"' + stack : stack.slice(2)); }
    if (!f[2] || loadedFonts[id]) { apply(); render(); return; }
    $('sim-font-hint').textContent = '「' + f[1] + '」下載中…' + (f[4] && f[4].indexOf('MB') > 0 ? '（約 16MB，手機上請用 Wi-Fi）' : '');
    var done = function (ok) {
      loadedFonts[id] = ok; apply(); render();
      $('sim-font-hint').textContent = ok ? '換成「' + f[1] + '」了。字體只改鍵盤上看到的字。' : '「' + f[1] + '」下載不下來，網頁先用系統字體；手機上的鍵盤已經內建這個字體。';
    };
    if (f[3] === 'google') {
      var link = document.createElement('link'); link.rel = 'stylesheet';
      link.href = 'https://fonts.googleapis.com/css2?family=' + encodeURIComponent(f[2]).replace(/%20/g, '+') + '&display=swap';
      document.head.appendChild(link);
      link.onload = function () { document.fonts.load('20px "' + f[2] + '"', '你好ㄅ').then(function (r) { done(r.length > 0); }, function () { done(false); }); };
      link.onerror = function () { done(false); };
    } else {
      new FontFace(f[2], 'url(' + f[3] + ')').load().then(function (face) { document.fonts.add(face); done(true); }, function () { done(false); });
    }
    apply(); render();
  }
  function pressed(sel, id) { root.querySelectorAll(sel).forEach(function (b) { b.setAttribute('aria-pressed', b.dataset.id === id ? 'true' : 'false'); }); }
  function chipGroup(box, items, onPick, extra) {
    items.forEach(function (it) {
      var b = el('button', '', it[1]); b.type = 'button'; b.dataset.id = it[0];
      if (extra) extra(b, it);
      b.addEventListener('click', function () { onPick(it[0]); });
      box.appendChild(b);
    });
  }
  chipGroup($('sim-shapes'), SHAPES, setShape, function (b, it) {
    b.textContent = ''; var svg = shapeSvg(it[0]); b.appendChild(svg); b.appendChild(el('span', '', it[1] + (it[4] ? ' ✦' : '')));
    if (DETAIL[it[0]]) b.style.setProperty('--detail', DETAIL[it[0]][0]);
  });
  chipGroup($('sim-finishes'), FINISHES, setFinish);
  chipGroup($('sim-effects'), EFFECTS, setEffect);
  chipGroup($('sim-fonts'), FONTS, setFont, function (b, it) { if (it[4]) b.textContent = it[1] + ' ✦'; });
  chipGroup($('sim-colors'), Object.keys(THEMES).map(function (k) { return [k, THEMES[k].name]; }), setTheme, function (b, it) {
    var t = THEMES[it[0]]; b.textContent = ''; b.title = t.name; b.setAttribute('aria-label', t.name);
    var sw = el('span'); sw.style.setProperty('--swatch', 'linear-gradient(135deg,' + t.top + ' 50%,' + t.accent + ' 50%)'); b.appendChild(sw);
  });
  $('sim-height').addEventListener('input', function () { phone.style.setProperty('--row-h', (46 * this.value) + 'px'); });
  $('sim-fontsize').addEventListener('input', function () { phone.style.setProperty('--fs', this.value); });
  $('sim-gap').addEventListener('input', function () { phone.style.setProperty('--gap', this.value); });
  $('sim-sound').addEventListener('change', function () { S.sound = this.checked; if (S.sound) sound(); });
  var photoUrl = null;
  $('sim-photo').addEventListener('change', function () {
    var file = this.files && this.files[0]; if (!file) return;
    if (photoUrl) URL.revokeObjectURL(photoUrl);
    photoUrl = URL.createObjectURL(file);
    var bg = $('sim-bg'); bg.style.backgroundImage = 'url("' + photoUrl + '")'; bg.classList.add('has-photo');
    $('sim-photo-clear').hidden = false;
    if (S.finish === 'flat') setFinish('glass');
    toast('配玻璃質感最好看');
  });
  $('sim-photo-clear').addEventListener('click', function () {
    var bg = $('sim-bg'); bg.style.backgroundImage = ''; bg.classList.remove('has-photo'); this.hidden = true; $('sim-photo').value = '';
  });
  $('sim-hide').addEventListener('click', function () { S.hidden = !S.hidden; render(); });
  $('sim-globe').addEventListener('click', function () { act('mode'); render(); });

  // ===== 功能導覽 =====
  var TOURS = {
    zhuyin: ['注音打字', '按注音鍵拼字，上面會出現候選字；選過的字下次會排前面。試試「ㄋㄧˇ ㄏㄠˇ」，再按「傳送」。', function () { reset('zhuyin'); }],
    abbr: ['簡拼', '只打每個字的第一個注音也可以：試試「ㄋ」「ㄏ」→ 你好、「ㄐ」「ㄊ」→ 今天、「ㄒ」「ㄒ」→ 謝謝。', function () { reset('zhuyin'); S.zy = 'ㄐㄊ'; }],
    punct: ['順手加標點', '選完字以後，候選列會出現「，。？！～」和接下去的詞，不用切到符號頁。', function () { reset('zhuyin'); S.text = '今天一起吃飯'; S.caret = S.text.length; afterCommit(); }],
    shortcut: ['快捷片語', '在 App 裡設定縮寫，例如「ㄨㄢ」→「我晚點回覆你」，打縮寫就會出現整句（標著「片語」）。', function () { reset('zhuyin'); S.zy = 'ㄨㄢ'; }],
    cursor: ['移動游標', '按住空白鍵左右滑，游標就會跟著移動（電腦上也可以按左右方向鍵）。', function () { reset('zhuyin'); S.text = '今天晚上一起去吃飯好嗎'; S.caret = 4; }],
    clipboard: ['剪貼簿', '點一則就貼上；📌 釘選、分類、✎ 直接在原本的文字上改：按住空白鍵滑到要改的地方，打字插進去，⌫ 刪游標前面的字。', function () { reset('zhuyin'); S.panel = 'clipboard'; }],
    kaomoji: ['顏文字', '工具列的 (•ᴗ•)：分成開心、愛心、害羞、動物…，最後一頁「我的表符」可以自己新增。', function () { reset('zhuyin'); S.panel = 'kaomoji'; }],
    fancy: ['花式文字', '工具列的 𝒜：打英文，下面會變成 21 種花式字，點一下就打出去，對方也看得到。', function () { reset('english'); S.editor = { kind: 'fancy', text: 'Hello', cursor: null }; }],
    translate: ['翻譯', '工具列的翻譯：先打中文，點「→英文」可以換語言（日文、韓文、義大利文…），再按「翻譯」。網頁只認得幾句，例如「謝謝」。', function () { reset('zhuyin'); S.editor = { kind: 'translate', text: '謝謝', cursor: null }; }],
    handwriting: ['手寫', '在格子裡用手指寫字，上面會出現認出來的字（網頁是示意，真的鍵盤會認）。', function () { reset('handwriting'); }],
    languages: ['英／拼／日／韓', '按左下角第二顆鍵切換：英文（自動修正、空白鍵兩下打句點）、拼音（可以出簡體）、日文羅馬拼音、韓文兩排式。', function () { reset('english'); S.shift = 'on'; }]
  };
  function reset(mode) {
    S.text = ''; S.caret = 0;
    S.mode = mode; S.layer = 'letters'; S.shift = 'off'; S.zy = S.py = S.romaji = ''; S.hangul = null; S.suggestions = []; S.suggestionKind = '';
    S.panel = null; S.panelTab = 0; S.editor = null; S.result = null; S.expanded = false; S.hidden = false;
  }
  root.querySelectorAll('[data-tour]').forEach(function (b) {
    b.addEventListener('click', function () {
      var t = TOURS[b.dataset.tour]; t[2]();
      $('sim-tip-title').textContent = t[0]; $('sim-tip-text').textContent = t[1];
      root.querySelectorAll('[data-tour]').forEach(function (x) { x.setAttribute('aria-pressed', x === b ? 'true' : 'false'); });
      render();
      if (window.innerWidth < 760) phone.scrollIntoView({ behavior: 'smooth', block: 'center' });
    });
  });

  addMsg('嗨嗨～這支手機可以真的打字喔 (◍•ᴗ•◍)', 'them');
  addMsg('上面的按鈕會教你每個功能，右邊可以換造型和顏色 ✨', 'them');
  setTheme('lavender'); setShape('bunny'); setFinish('puffy'); setEffect('stars'); setFont('system');
}());
