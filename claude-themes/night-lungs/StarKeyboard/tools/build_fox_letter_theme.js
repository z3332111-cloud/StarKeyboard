'use strict';
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { source, layers, parsePath, geometry, svgPath } = require('./build_fox_letter_prototype');
const preview = require('./fox_letter_preview_layouts');
const watercolor = require('./fox_letter_watercolor');
const root = path.resolve(__dirname, '..');

function swiftSource() {
  const color = hex => `UIColor(hex: 0x${hex.slice(1)})`;
  const variants = source.variants.map(v => `        Palette(name: ${JSON.stringify(v.name)}, fur: ${color(v.fur)}, cheek: ${color(v.cheek)}, text: ${color(v.text)}, accessory: ${JSON.stringify(v.accessory)})`).join(',\n');
  const accessories = Object.entries(source.accessories).map(([name, layers]) => `        ${JSON.stringify(name)}: [\n${layers.map(l=>`            FoxLetterPrototype.ArtLayer(space: .head, fill: ${color(l.fill)}, stroke: ${l.stroke ? color(l.stroke) : 'nil'}, lineWidth: ${l.strokeWidth || 0},\n                ops: [${parsePath(l.path).join(', ')}])`).join(',\n')}\n        ]`).join(',\n');
  return `// 由 node tools/build_fox_letter_theme.js 產生，請修改 tools/fox_letter_prototype.json。
import UIKit

enum FoxLetterArtwork {
    static let paperPalettes: [[Int]] = ${JSON.stringify(watercolor.atlas.palettes)}
    static let paperCuts: [CGFloat] = ${JSON.stringify(watercolor.atlas.cuts)}
    static let paperWideCells: [[CGFloat]] = ${JSON.stringify(watercolor.atlas.wideCells)}
    static let theme = KeyboardTheme(id: "fox-letter", name: ${JSON.stringify(source.title)},
        ${Object.entries(source.themeColors).map(([name,value])=>`${name}: ${color(value)}`).join(', ')}, decoration: "", isDark: true)
    struct Palette {
        let name: String
        let fur: UIColor
        let cheek: UIColor
        let text: UIColor
        let accessory: String
    }
    static let palettes: [Palette] = [
${variants}
    ]
    static let accessories: [String: [FoxLetterPrototype.ArtLayer]] = [
${accessories}
    ]
}
`;
}

function artGeometry(width, height, gap, scale, compact) {
  const factor=Math.min(1.12,Math.max(.8,scale/1.15));
  gap=Math.min(1.8,Math.max(.3,gap));
  const w=Math.min(width-1.4,Math.max(5,width-2*gap)*factor),h=Math.min(height-1.4,Math.max(5,height-4*gap)*factor);
  const offset={x:(width-w)/2,y:(height-h)/2};
  const g=geometry(w,h);
  if(compact && h<38){g.face={x:0,y:0,width:0,height:0};g.label={x:g.frame.x+g.frame.width*.16,y:g.frame.y+g.frame.height*.24,width:g.frame.width*.68,height:g.frame.height*.64};}
  return {...g,offset,compact:compact&&h<38};
}

function legibleInk(palette, opacity, colors) {
  const rgb=hex=>hex.slice(1).match(/../g).map(x=>parseInt(x,16)/255);
  const lum=values=>values.map(c=>c<=.04045?c/12.92:((c+.055)/1.055)**2.4).reduce((sum,c,i)=>sum+c*[.2126,.7152,.0722][i],0);
  const fur=rgb(palette.fur),alpha=Math.min(1,Math.max(0,opacity));
  const backgrounds=[colors.backgroundTop,colors.backgroundBottom].map(b=>lum(rgb(b).map((c,i)=>fur[i]*alpha+c*(1-alpha))));
  const score=color=>{const l=lum(rgb(color));return Math.min(...backgrounds.map(b=>(Math.max(l,b)+.05)/(Math.min(l,b)+.05)))};
  if(score(palette.text)>=4.5)return {color:palette.text,outline:null};
  const color=[palette.text,'#FFF9EF','#000000'].reduce((best,color)=>score(color)>score(best)?color:best,palette.text);
  return {color,outline:score(color)>=4.5?null:lum(rgb(color))>.5?'#000000':'#FFFFFF'};
}
function legibleColor(palette, opacity, colors) { return legibleInk(palette,opacity,colors).color; }

function htmlSource(){
  const accessories=Object.fromEntries(Object.entries(source.accessories).map(([name,list])=>[name,list.map(l=>({...l,ops:parsePath(l.path)}))]));
  return `<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>小狐狸的楓葉信 · 輸入法與版面預覽</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#eee5df;color:#513e3b;font:14px/1.6 system-ui,"Microsoft JhengHei","PingFang TC",sans-serif}main{max-width:1180px;margin:auto;padding:28px}h1{font-size:29px;letter-spacing:.06em;margin:2px 0 6px}h2{font-size:15px;margin:0}p{margin:5px 0}.eyebrow{font-size:11px;letter-spacing:.18em;color:#a26c4b}.subtitle{color:#8b7066}.controls{background:#fffbf6;border:1px solid #d9c6b8;padding:14px 18px;border-radius:14px;display:flex;gap:10px 17px;flex-wrap:wrap;margin:22px 0}label{display:flex;align-items:center;gap:6px;font-size:12px}select,input{accent-color:#a8623e}select{border:1px solid #d9c6b8;background:white;border-radius:6px;padding:5px;color:#513e3b}input[type=range]{width:86px}.workspace{background:#e5d7ce;border-radius:20px;padding:25px 14px;overflow:auto;display:flex;justify-content:center}.keyboard{flex:none;background:linear-gradient(#51424d,#392f3d);border:1px solid #8b737b;border-radius:20px;overflow:hidden;box-shadow:0 12px 22px #46303a25}.banner{height:50px;background:#e1c2b8;color:#654738;display:flex;align-items:center;justify-content:center;gap:14px;font-size:15px;font-weight:700;letter-spacing:.09em}.banner span{font-size:20px}.toolbar{background:#362d34;color:#fff5e4;display:flex;align-items:center;justify-content:space-around;border:1px solid #c1a49a;border-radius:18px;margin:7px 8px 3px;height:41px;font-size:18px}.toolbar svg{width:21px;height:21px}.keyboard>svg{display:block}.foot{padding:6px 20px 10px;color:#e1c8b8;border-top:1px solid #81677355;display:flex;align-items:center;gap:12px;font-size:12px}.foot svg{width:20px;height:20px}.art{transition:opacity .08s}.key{cursor:pointer}.key:active .art,.key.pressed .art{opacity:var(--pressed-alpha)!important}.key:active .main-text,.key.pressed .main-text{fill:var(--pressed-ink)}.key:active .icon path,.key.pressed .icon path{stroke:var(--pressed-ink)}.zone{fill:#50cdb826;stroke:#72e3ca;stroke-width:.3;pointer-events:none}.face-zone{fill:#e0709026;stroke:#f1a0bb}.hint-zone{fill:#e4af3030;stroke:#f6cf67}.zones-off .zone{display:none}.meta{display:flex;gap:13px;flex-wrap:wrap;margin-top:15px;font-size:12px;color:#826b60}.swatches{display:flex;gap:12px;flex-wrap:wrap;margin:15px 0}.swatch{display:flex;gap:5px;align-items:center;font-size:12px}.swatch i{width:20px;height:20px;border-radius:50%;border:1px solid #80554340}.status{padding:9px 13px;background:#fff9f1;border-radius:8px;margin:14px 0;font-size:12px}.note{font-size:12px;color:#897568}.panel{background:#46353e;color:#fff5e4;padding:12px;min-height:250px}.panel .item{background:#6c5050;border-radius:10px;margin:8px 0;padding:11px;font-size:12px}.emoji-grid{display:grid;grid-template-columns:repeat(6,1fr);gap:8px;padding:18px 0;font-size:24px;text-align:center}.panel h2{color:#edba8d}.caption{font-size:11px;color:#876c5e;margin-top:9px}.backlink{color:#956044;font-size:12px}.illustration-header{font-size:12px;margin-top:20px}@media(max-width:750px){main{padding:18px 12px}.workspace{justify-content:flex-start}h1{font-size:23px}.controls{padding:10px;gap:10px}.banner{font-size:12px}}
</style><style>.workspace{display:block}.keyboard{margin-inline:auto}
.keyboard{background:#443741;border-color:#967f82;box-shadow:0 12px 25px #30242f33}
.banner{position:relative;isolation:isolate;background:none;color:#674838;font-family:"jf-openhuninn-2.1","Chiron GoRound TC",system-ui,sans-serif;letter-spacing:.08em}.banner .landscape{position:absolute;inset:0;z-index:-1;width:100%;height:100%}.banner .theme-title{font-size:inherit;text-shadow:0 1px #fff8e8;max-width:57%;text-align:center;line-height:1.2}
.toolbar{background:linear-gradient(#151218a8,#151218a8),url('${watercolor.atlas.backdrop}') center bottom/100% auto;border:1px solid #e4d9ce;border-radius:999px;box-shadow:inset 0 0 0 2px #fff1,inset 0 1px 8px #110d16}.foot{background:#e9e7ee;border:0;color:#17131b}
.toolbar .icon{width:var(--tool-size,21px);height:var(--tool-size,21px)}.foot .icon{width:var(--globe-size,30px);height:var(--globe-size,30px)}
.key .main-text{stroke:var(--normal-outline);stroke-width:.03em;paint-order:stroke fill}.key:active .main-text,.key.pressed .main-text{stroke:var(--pressed-outline)}
.key .icon{--edge:var(--normal-outline);filter:drop-shadow(.45px 0 0 var(--edge)) drop-shadow(-.45px 0 0 var(--edge)) drop-shadow(0 .45px 0 var(--edge)) drop-shadow(0 -.45px 0 var(--edge))}.key:active .icon,.key.pressed .icon{--edge:var(--pressed-outline)}
</style>
<main id="app" class="zones-off"><div class="eyebrow">FOX LETTER / THEME PREVIEW</div><h1>小狐狸的楓葉信</h1><p class="subtitle">狐狸臉形 · 五色交錯 · 楓葉、帽子、信封與圍巾</p>
<div class="controls">
<label>輸入法 <select id="mode"><option value="zhuyin">注音</option><option value="english">英文</option><option value="pinyin">拼音</option><option value="japanese">日文（羅馬字）</option><option value="korean">韓文</option><option value="handwriting">手寫</option></select></label>
<label>頁面 <select id="layer"><option value="letters">文字／手寫</option><option value="numbers">123</option><option value="symbols">#+=</option><option value="numpad">數字盤</option></select></label>
<label>面板 <select id="panel"><option value="keyboard">鍵盤</option><option value="emoji">表情</option><option value="clipboard">剪貼簿</option><option value="settings">設定</option></select></label>
<label><input type="checkbox" id="ten" checked>注音十欄</label><label><input type="checkbox" id="shift">Shift</label><label><input type="checkbox" id="globe">地球鍵</label><label><input type="checkbox" id="full" checked>全形</label><label><input type="checkbox" id="candidates">候選字</label>
<label>高度 <input type="range" id="height" min="0.8" max="1.3" step="0.05" value="1"></label><label>字體 <input type="range" id="font" min="0.8" max="1.3" step="0.05" value="1"></label><label>間距 <input type="range" id="gap" min="0.3" max="1.8" step="0.1" value="1"></label><label>造型大小 <input type="range" id="shape" min="0.8" max="1.3" step="0.05" value="1.15"></label><label>透明度 <input type="range" id="alpha" min="0.35" max="1" step="0.05" value="1"></label>
<label>寬度 <select id="width"><option>320</option><option selected>390</option><option>430</option><option>700</option></select></label><label>預覽倍率 <select id="zoom"><option value="1">1 倍</option><option value="1.7" selected>1.7 倍</option></select></label><label><input type="checkbox" id="zones">顯示分區</label>
</div><div class="workspace"><div class="keyboard" id="keyboard"></div></div><div class="caption">放大預覽可看配件細節；切到 1 倍檢查實際可讀性。山景標題區已接入 iPhone 主題；下方地球區為系統區域示意，仍由 iOS 管理。</div>
<div class="swatches" id="swatches"></div><div class="status" id="status">可切換所有現有輸入法與數字／符號頁，點按鍵檢查按下回饋。</div><div class="meta"><span id="summary"></span><a class="backlink" href="index.html">查看單顆水彩版型</a></div><p class="note">這是離線外觀預覽，未連接文字辨識或輸入引擎。注音與符號字元取自專案資料；真實配置及觸控行為以 iPhone 的 KeyLayouts 為準。UIKit 編譯、實際字型和效能仍需 Xcode 與真機驗證。</p></main>
<script>
'use strict';
const source=${JSON.stringify(source)},layers=${JSON.stringify(layers)},accessories=${JSON.stringify(accessories)},data=${JSON.stringify(preview.data)};
const atlas=${JSON.stringify(watercolor.atlas)},spriteIndex=${watercolor.spriteIndex.toString()},imageSlices=${watercolor.imageSlices.toString()},watercolorSVG=${watercolor.watercolorSVG.toString()};
const layout=${preview.layout.toString()},positions=${preview.positions.toString()},geometry=${geometry.toString()},svgPath=${svgPath.toString()},artGeometry=${artGeometry.toString()},legibleInk=${legibleInk.toString()},legibleColor=${legibleColor.toString()};
const assert=(x,message)=>{if(!x)throw new Error(message)},escape=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const iconPaths={backspace:'M9 5H21V19H9L2 12ZM12 9L18 15M18 9L12 15',return:'M20 4V13H5M10 8L5 13L10 18',shift:'M3 11L12 2L21 11H16V21H8V11Z','shift.fill':'M3 11L12 2L21 11H16V21H8V11Z',globe:'M21 12A9 9 0 1 1 3 12A9 9 0 1 1 21 12M3 12H21M12 3C6 8 6 16 12 21C18 16 18 8 12 3',smile:'M21 12A9 9 0 1 1 3 12A9 9 0 1 1 21 12M8 9H8.1M16 9H16.1M7 14Q12 19 17 14',space:'M3 8V16H21V8',clipboard:'M9 5H5V22H20V5H16M9 2H16V7H9ZM8 11H17M8 16H17',gear:'M9 2H15L16 6L20 5L23 10L20 13L22 17L17 21L14 19L10 22L7 19L3 19L1 13L5 11L4 6L9 6ZM16 12A4 4 0 1 1 8 12A4 4 0 1 1 16 12',dismiss:'M3 4H21V15H3ZM8 19L12 23L16 19'};
function icon(name,x,y,w,h,color){const d=iconPaths[name]||iconPaths.smile;return '<svg class="icon" x="'+x+'" y="'+y+'" width="'+w+'" height="'+h+'" viewBox="0 0 24 24"><path d="'+d+'" fill="none" stroke="'+color+'" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>'}
function motif(name){return '<svg width="25" height="25" viewBox="65 0 35 33" aria-hidden="true">'+accessories[name].map(l=>'<path d="'+svgPath(l.ops,{x:0,y:0,width:100,height:100},null)+'" fill="'+l.fill+'"'+(l.stroke?' stroke="'+l.stroke+'" stroke-width="1"':'')+'/>').join('')+'</svg>'}
function drawKey(k,c){
 const functional=k.action!=='text';const g=artGeometry(k.width,k.height,c.gap,c.shape,functional);
 const index=k.action==='returnKey'?2:k.action==='space'?0:k.index%source.variants.length,p=source.variants[index];
 const normal=legibleInk(p,c.alpha,source.themeColors),pressed=legibleInk(p,c.alpha*.82,source.themeColors);
 for(const ink of [normal,pressed])if(!ink.outline&&parseInt(ink.color.slice(1,3),16)>200)ink.outline='#68472BA6';
 const ink=normal.color,pressedInk=pressed.color;
 const accessory=k.action==='space'?'letter':k.action==='returnKey'?'leaf':p.accessory;
 const defs=g.compact?layers.slice(0,2):[...layers.slice(0,-1),...(accessories[accessory]||[]),layers[layers.length-1]];
 const parts=watercolorSVG({x:0,y:0,width:g.frame.width+4,height:g.frame.height+4},k.index,k.action,g.compact);
 const zone=(r,cls)=>'<rect class="zone '+cls+'" x="'+r.x+'" y="'+r.y+'" width="'+r.width+'" height="'+r.height+'"/>';
 const r=g.label,hint=g.hint;
 let face=k.symbol?icon(k.text,r.x,r.y,r.width,r.height,ink):'<text class="main-text" x="'+(r.x+r.width/2)+'" y="'+(r.y+r.height/2)+'" dominant-baseline="central" text-anchor="middle" fill="'+ink+'" font-size="'+Math.min(24*c.font,r.height)+'" font-weight="750">'+escape(k.text)+'</text>';
 face+='<text class="hint-text" x="'+(hint.x+hint.width/2)+'" y="'+(hint.y+hint.height/2)+'" dominant-baseline="central" text-anchor="middle" fill="#FFF5E4" font-size="'+Math.min(9*c.font,hint.height)+'">'+escape(k.hint)+'</text>';
 return '<svg class="key" data-label="'+escape(k.text)+'" data-action="'+k.action+'" style="--pressed-alpha:'+c.alpha*.82+';--pressed-ink:'+pressedInk+';--normal-outline:'+(normal.outline||'transparent')+';--pressed-outline:'+(pressed.outline||'transparent')+'" x="'+k.x+'" y="'+k.y+'" width="'+k.width+'" height="'+k.height+'" viewBox="0 0 '+k.width+' '+k.height+'"><g transform="translate('+g.offset.x+' '+g.offset.y+')"><g class="art" opacity="'+c.alpha+'">'+parts+'</g>'+zone(r,'label-zone')+zone(hint,'hint-zone')+zone(g.face,'face-zone')+face+'</g></svg>';
}
function fitText(svg){
 for(const [selector,zoneSelector]of [['.main-text','.label-zone'],['.hint-text','.hint-zone']]){
  const text=svg.querySelector(selector),r=svg.querySelector(zoneSelector);if(!text||!text.textContent)continue;
  const outlined=selector==='.main-text'&&['--normal-outline','--pressed-outline'].some(name=>svg.style.getPropertyValue(name)!=='transparent');
  const edge=outlined?Math.min(.6,Number(r.getAttribute('height'))*.05):0;
  let b=text.getBBox();const w=Number(r.getAttribute('width'))-2*edge,h=Number(r.getAttribute('height'))-2*edge;
  // 小字型的像素對齊並非完全線性，反覆量測，避免提示字卡在整數像素行高。
  for(let i=0;i<8;i++){
   b=text.getBBox();const fit=Math.min(1,w/Math.max(.01,b.width),h/Math.max(.01,b.height));
   if(fit>=.999)break;
   text.setAttribute('font-size',Number(text.getAttribute('font-size'))*fit*.96);
  }
  b=text.getBBox();text.setAttribute('y',Number(text.getAttribute('y'))+Number(r.getAttribute('y'))+edge+h/2-b.y-b.height/2);
  text.setAttribute('x',Number(text.getAttribute('x'))+Number(r.getAttribute('x'))+edge+w/2-b.x-b.width/2);
 }
}
function state(){const c={};for(const id of ['mode','layer','panel'])c[id]=document.querySelector('#'+id).value;for(const id of ['ten','shift','globe','full','candidates','zones'])c[id]=document.querySelector('#'+id).checked;for(const id of ['height','font','gap','shape','alpha','width','zoom'])c[id]=Number(document.querySelector('#'+id).value);return c;}
function render(){
 const c=state(),l=layout(c,data),w=c.width,h=Math.round((l.rows.length>=5?252:216)*c.height);
 const keys=positions(l,w,h);let main='';
 if(c.panel==='keyboard'){
  if(l.handwriting){const cw=w-Math.min(84,w*.22)-10;main+='<rect x="6" y="6" width="'+cw+'" height="'+(h-12)+'" rx="10" fill="#654b4c"/><text x="'+cw/2+'" y="'+h/2+'" fill="#e9c4a9" font-size="16" text-anchor="middle">手寫區</text>';}
  main='<svg class="key-scene" width="'+w*c.zoom+'" height="'+h*c.zoom+'" viewBox="0 0 '+w+' '+h+'"><svg width="'+w+'" height="'+h+'" viewBox="0 .2 1 .8" preserveAspectRatio="none"><image href="'+atlas.backdrop+'" width="1" height="1"/></svg>'+main+keys.map(k=>drawKey(k,c)).join('')+'</svg>';
 }else if(c.panel==='emoji')main='<div class="panel" style="width:'+w*c.zoom+'px"><h2>最近使用 · 表情 · 顏文字</h2><div class="emoji-grid">🦊 🍁 ✉️ 🍂 🐻 🌰 😊 🧡 🌿 🍄 ☺️ ⭐</div><div class="item">(•ᴗ•)　(˶ᵔ ᵕ ᵔ˶)　♡</div></div>';
 else if(c.panel==='clipboard')main='<div class="panel" style="width:'+w*c.zoom+'px"><h2>剪貼簿 · 釘選</h2><div class="item">把秋天寄給你 🍁</div><div class="item">小狐狸的楓葉信</div><div class="item">今天也要好好休息。</div></div>';
 else main='<div class="panel" style="width:'+w*c.zoom+'px"><h2>主題 · 小狐狸的楓葉信 ✓</h2><div class="item">角色造型與插畫質感已搭配好</div><div class="item">原本的造型、質感、照片都會保留</div><div class="item">高度、字體、間距與空白鍵圖片可繼續使用</div></div>';
 const toolbar=c.candidates?'<div>秋天　 楓葉　 寄信　▾</div>':['clipboard','smile','gear','dismiss'].map(name=>icon(name,0,0,22,22,'#fff5e4')).join('<span style="font-size:12px;opacity:.45">│</span>');
 const keyboard=document.querySelector('#keyboard');keyboard.style.width=w*c.zoom+'px';
 keyboard.innerHTML='<div class="banner" style="height:'+52*c.zoom+'px;font-size:'+18*c.zoom+'px"><svg class="landscape" viewBox="0 0 1 .18" preserveAspectRatio="none"><image href="'+atlas.backdrop+'" width="1" height="1"/></svg><span class="theme-title">小狐狸的楓葉信</span></div><div class="toolbar" style="height:'+41*c.zoom+'px;--tool-size:'+21*c.zoom+'px">'+toolbar+'</div>'+main+'<div class="foot" style="height:'+66*c.zoom+'px;padding-left:'+22*c.zoom+'px;--globe-size:'+30*c.zoom+'px">'+icon('globe',0,0,30,30,'#17131b')+'</div>';
 keyboard.querySelectorAll('.key').forEach(fitText);
 document.querySelector('#app').classList.toggle('zones-off',!c.zones);
 document.querySelector('#summary').textContent=w+' pt 寬 · '+Math.round(c.height*100)+'% 高度 · '+keys.length+' 顆鍵 · '+(l.handwriting?'手寫側欄':l.rows.length+' 排');
 keyboard.querySelectorAll('.key').forEach(key=>key.addEventListener('click',()=>{key.classList.add('pressed');setTimeout(()=>key.classList.remove('pressed'),130);document.querySelector('#status').textContent='點選：'+key.dataset.label+'（'+key.dataset.action+'） · 此頁只測外觀，iPhone 保留原本按鍵行為。';}));
}
document.querySelector('#swatches').innerHTML=source.variants.map(p=>'<span class="swatch"><i style="background:'+p.fur+'"></i>'+p.name+'</span>').join('');
document.querySelectorAll('.controls input,.controls select').forEach(e=>e.addEventListener('input',render));render();document.fonts.ready.then(render);
</script></html>`;
}

function write(check = false) {
  for(const [name,content] of [['Keyboard/FoxLetterArtwork.swift',swiftSource()],['docs/previews/fox-letter/theme.html',htmlSource()]]){
    const file=path.join(root,name);
    if (check) assert(fs.readFileSync(file,'utf8')===content,name+' 需要重新產生');
    else {fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,content);console.log(name);}
  }
}
if (require.main === module) write(process.argv.includes('--check'));
module.exports = { swiftSource, artGeometry, legibleColor, legibleInk, htmlSource, write };
