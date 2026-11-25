// 離線外觀預覽的版面示意；真正輸入行為仍由 Keyboard/KeyLayouts.swift 管理。
// 字元資料直接讀取原生的 Bopomofo／SymbolPages，避免手工重打一份符號表。
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const core = path.resolve(__dirname, '../Core/Sources/KeyboardCore');
const bopomofo = fs.readFileSync(path.join(core, 'Bopomofo.swift'), 'utf8');
const symbols = fs.readFileSync(path.join(core, 'SymbolPages.swift'), 'utf8');
const rows = [...bopomofo.match(/static let dachenRows[^=]*=\s*\[([\s\S]*?)\]/)[1].matchAll(/"([^"]+)"/g)].map(m => m[1]);
const symbolData = Object.fromEntries([...symbols.matchAll(/static let (\w+) = ("(?:\\.|[^"\\])*")/g)].map(m => [m[1], JSON.parse(m[2])]));
const data = { rows, symbols: symbolData };

function layout(c, data) {
  const names = {zhuyin:'注音',english:'English',pinyin:'拼音',japanese:'日本語',korean:'한국어',handwriting:'手寫'};
  const key=(text,w=1,role='normal',action='text',hint='',symbol=false)=>({text,w,role,action,hint,symbol});
  const chars=(text,w=1)=>[...text].map(ch=>key(ch,w));
  const icon=(name,w=1,action=name,role='special')=>key(name,w,role,action,'',true);
  const back=(w=1.4)=>icon('backspace',w);
  const enter=(w=2)=>icon('return',w,'returnKey','accent');
  const shift=()=>icon(c.shift?'shift.fill':'shift',1.4,'shift');
  const bottom=columns=>{
    const k=columns/10;
    const title=c.layer==='letters'?(c.mode==='pinyin'?'!#1':'123'):({zhuyin:'ㄅㄆㄇ',english:'ABC',handwriting:'手寫',japanese:'かな',korean:'한글',pinyin:'拼音'}[c.mode]);
    const row=[key(title,1.3*k,'special',c.layer==='letters'?'numbers':'letters')];
    if(c.globe)row.push(icon('globe',1.1*k));
    row.push(key(c.layer==='letters'?'英':'數字',1.1*k,'special',c.layer==='letters'?'nextMode':'numpad'));
    if(c.layer==='letters'&&c.mode==='pinyin')return [...row,key('，',.9*k),key(names[c.mode],0,'normal','space'),key('。',.9*k),key('123',1.1*k,'special','numpad'),enter(1.6*k)];
    if(!c.globe)row.push(icon('smile',1.1*k,'emoji'));
    return [...row,key(names[c.mode],0,'normal','space'),enter(2*k)];
  };
  const s=data.symbols;
  const chinese=c.mode!=='english'&&c.mode!=='korean';
  if(c.layer==='numpad')return {columns:5,rows:[
    [key('-',1,'special'),...chars('123'),back(1)],
    [key('@',1,'special'),...chars('456'),key('.',1,'special')],
    [key(':',1,'special'),...chars('789'),key(',',1,'special')],
    [key('!#1',1,'special','numbers'),key(({zhuyin:'ㄅㄆㄇ',english:'ABC',handwriting:'手寫',japanese:'かな',korean:'한글',pinyin:'拼音'})[c.mode],1,'special','letters'),key('0'),icon('space',1,'space'),enter(1)]
  ]};
  if(c.layer==='numbers')return chinese?{columns:10,rows:[chars('1234567890'),chars(c.full?s.zhuyinNumberRow2:s.zhuyinNumberRow2Half),chars(s.zhuyinNumberExtra),[key('#+=',1.25,'special','symbols'),...chars(c.full?s.zhuyinNumberRow3:s.zhuyinNumberRow3Half,1.05),key(c.full?'全形':'半形',1.1,'special','full'),back(1.35)],bottom(10)]}
    :{columns:10,rows:[chars('1234567890'),chars('-/:;()$&@"'),chars(s.englishNumberExtra),[key('#+=',1.4,'special','symbols'),...chars(".,?!'",1.4),back()],bottom(10)]};
  if(c.layer==='symbols')return chinese?{columns:10,rows:[chars(s.zhuyinSymbolRow1),chars(s.zhuyinSymbolRow2),[key('123',1.25,'special','numbers'),...chars('『』♡☆‧→※',.9),key(c.full?'全形':'半形',1.1,'special','full'),back(1.35)],bottom(10)]}
    :{columns:10,rows:[chars(s.englishSymbolRow1),chars(s.englishSymbolRow2),[key('123',1.4,'special','numbers'),...chars(".,?!'",1.4),back()],bottom(10)]};
  if(c.mode==='handwriting')return {columns:1,handwriting:true,rows:[[back(1)],[key('重寫',1,'special','clearCanvas')],[key('123',1,'special','numbers')],[key('空白',1,'normal','space')],[key('英',1,'special','nextMode')],[enter(1)]]};
  if(c.mode==='zhuyin'){
    if(!c.ten)return {columns:11,rows:[...data.rows.map((row,i)=>i===3?[...chars(row),back(1)]:chars(row)),bottom(11)]};
    const hints=[...'1234567890',...'qwertyuiop',...'asdfghjkl','：',...'zxcvbnm','……','！','？'];
    let h=0;const rows=data.rows.map(row=>[...row].filter(x=>x!=='ㄦ').map(ch=>key(ch,1,'normal','text',hints[h++])));
    const last=[key('123',1.2,'special','numbers')];
    if(c.globe)last.push(icon('globe',1));
    last.push(key('英',1,'special','nextMode'),key('，',1,'normal','text','。'),key('注音',0,'normal','space'),key('ㄦ'),back(1.2),enter(1.5));
    return {columns:10,rows:[...rows,last]};
  }
  if(c.mode==='korean')return {columns:10,rows:[chars(c.shift?'ㅃㅉㄸㄲㅆㅛㅕㅑㅒㅖ':'ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔ'),chars('ㅁㄴㅇㄹㅎㅗㅓㅏㅣ'),[shift(),...chars('ㅋㅌㅊㅍㅠㅜㅡ'),back()],bottom(10)]};
  const latin=text=>chars(c.mode==='english'&&c.shift?text.toUpperCase():text);
  const first=c.mode==='english'?shift():key(c.mode==='japanese'?'ー':"'",1.4,'special');
  const rows=[latin('qwertyuiop'),latin('asdfghjkl'),[first,...latin('zxcvbnm'),back()],bottom(10)];
  if(c.mode==='pinyin')rows.unshift(chars('1234567890'));
  return {columns:10,rows};
}

function positions(layout, width, height) {
  const side=layout.handwriting?Math.min(84,width*.22):width;
  const left=layout.handwriting?width-side-2:0;
  const unit=(side-4)/layout.columns,rowHeight=(height-6)/layout.rows.length;
  let index=0;
  return layout.rows.flatMap((row,r)=>{
    const fixed=row.reduce((sum,k)=>sum+Math.max(k.w,0),0),flexCount=row.filter(k=>k.w===0).length;
    const flex=flexCount?Math.max(1,(layout.columns-fixed)/flexCount):0;
    let x=left+2+Math.max(0,layout.columns-fixed-flex*flexCount)*unit/2;
    return row.map(k=>{const item={...k,index:index++,x,y:3+r*rowHeight,width:(k.w||flex)*unit,height:rowHeight};x+=item.width;return item;});
  });
}
module.exports={data,layout,positions};
