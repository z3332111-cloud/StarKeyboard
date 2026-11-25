'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {source,parsePath,svgPath}=require('../build_fox_letter_prototype');
const {data,layout,positions}=require('../fox_letter_preview_layouts');
const {artGeometry,legibleColor,legibleInk,swiftSource,htmlSource}=require('../build_fox_letter_theme');
const modes=['zhuyin','english','pinyin','japanese','korean','handwriting'];
const maxY=r=>r.y+r.height;
const overlaps=(a,b)=>a.width>0&&b.width>0&&a.x<b.x+b.width&&b.x<a.x+a.width&&a.y<maxY(b)&&b.y<maxY(a);
const defaults={mode:'zhuyin',layer:'letters',globe:false,ten:true,shift:false,full:true};

test('現有模式與頁面的版面示意：按鍵不超出窄螢幕或橫向配置',()=>{
 let count=0;
 for(const mode of modes)for(const layer of ['letters','numbers','symbols','numpad'])for(const globe of [false,true])for(const ten of [false,true])for(const shift of [false,true]){
  const l=layout({...defaults,mode,layer,globe,ten,shift},data);
  for(const [w,h]of [[320,164],[390,252],[700,164]]){
   const keys=positions(l,w,h);
   assert.equal(keys.length,l.rows.flat().length);
   for(const k of keys){
    assert(k.width>0&&k.height>0);
    assert(k.x>=0&&k.x+k.width<=w+.01&&k.y>=0&&k.y+k.height<=h+.01,mode+' '+layer);
   }
  }
  count++;
 }
 assert.equal(count,192);
});

test('全部版面在極端字距與高度下，文字區不占用五官區',()=>{
 for(const mode of modes)for(const layer of ['letters','numbers','symbols','numpad'])for(const width of [320,700])for(const gap of [.3,1.8]){
  const l=layout({...defaults,mode,layer},data);
  const keys=positions(l,width,164*.8);
  for(const k of keys){
   const g=artGeometry(k.width,k.height,gap,1.3,k.action!=='text');
   assert(!overlaps(g.label,g.face),mode+' '+layer+' '+k.text);
   assert(!overlaps(g.label,g.hint));
   assert(g.offset.x>=0&&g.offset.y>=0);
   assert(g.label.width>0&&g.label.height>0);
  }
 }
});

test('五色配件都是有效向量路徑，生成檔與共用來源一致',()=>{
 assert.equal(source.variants.length,5);
 for(const v of source.variants){
  assert(source.accessories[v.accessory]);
  for(const color of [v.fur,v.cheek,v.text])assert(/^#[A-F\d]{6}$/i.test(color));
 }
 for(const defs of Object.values(source.accessories))for(const definition of defs){
  const ops=parsePath(definition.path);
  assert(ops.length&&ops.every(Number.isFinite));
  const g=artGeometry(160,46,1,1.15,false);
  assert(!/NaN|Infinity/.test(svgPath(ops,g.frame,g.ends)));
 }
 const root=path.resolve(__dirname,'../..');
 assert.equal(fs.readFileSync(path.join(root,'Keyboard/FoxLetterArtwork.swift'),'utf8'),swiftSource());
 assert.equal(fs.readFileSync(path.join(root,'docs/previews/fox-letter/theme.html'),'utf8'),htmlSource());
});

test('注音欄數、長提示字、日文羅馬字、韓文 Shift 與半形標點保留',()=>{
 const ten=layout(defaults,data),eleven=layout({...defaults,ten:false},data);
 assert.equal(ten.columns,10);assert.equal(eleven.columns,11);
 assert(ten.rows.flat().some(k=>k.hint==='……'));
 assert(eleven.rows[0].some(k=>k.text==='ㄦ'));
 const jp=layout({...defaults,mode:'japanese'},data);
 assert.equal(jp.rows[0].map(k=>k.text).join(''),'qwertyuiop');
 assert(jp.rows.flat().some(k=>k.text==='ー'));
 const ko=layout({...defaults,mode:'korean',shift:true},data);
 assert.equal(ko.rows[0][0].text,'ㅃ');
 const half=layout({...defaults,layer:'numbers',full:false},data).rows.flat();
 assert(half.some(k=>k.text==='?'));assert(half.some(k=>k.text==='。'));
 const symbols=layout({...defaults,layer:'symbols'},data).rows.flat().map(k=>k.text);
 for(const ch of ['`','*','_','~','|','#','\\','^','+','='])assert(symbols.includes(ch));
});

test('大小寫更新不改變角色交錯順序，手寫保留六個側欄功能',()=>{
 const lower=layout({...defaults,mode:'english'},data),upper=layout({...defaults,mode:'english',shift:true},data);
 const a=positions(lower,390,216),b=positions(upper,390,216);
 assert.equal(a.length,b.length);
 a.forEach((k,i)=>{assert.equal(k.index,b[i].index);assert.equal(k.x,b[i].x);assert.equal(k.width,b[i].width)});
 assert.equal(b[0].text,'Q');
 const hw=layout({...defaults,mode:'handwriting'},data);
 assert(hw.handwriting);assert.equal(hw.rows.length,6);
 assert(hw.rows.flat().some(k=>k.action==='clearCanvas'));
 assert(hw.rows.flat().some(k=>k.action==='returnKey'));
});

test('五色在完整透明度滑桿範圍及按壓後仍選擇可讀配色',()=>{
 const rgb=h=>h.slice(1).match(/../g).map(x=>parseInt(x,16)/255);
 const lum=values=>values.map(c=>c<=.04045?c/12.92:((c+.055)/1.055)**2.4).reduce((s,c,i)=>s+c*[.2126,.7152,.0722][i],0);
 for(const palette of source.variants)for(let step=0;step<=13;step++)for(const pressed of [false,true]){
  const opacity=(.35+step*.05)*(pressed?.82:1);
  const ink=legibleInk(palette,opacity,source.themeColors),l=lum(rgb(ink.color));
  assert.equal(ink.color,legibleColor(palette,opacity,source.themeColors));
  for(const background of [source.themeColors.backgroundTop,source.themeColors.backgroundBottom]){
   const fur=rgb(palette.fur),b=lum(rgb(background).map((v,i)=>fur[i]*opacity+v*(1-opacity)));
   const contrast=(Math.max(l,b)+.05)/(Math.min(l,b)+.05);
   if(contrast<4.5){
    assert(ink.outline,palette.name+' '+opacity+'：底色不足時需要細邊');
    const edge=lum(rgb(ink.outline));
    assert((Math.max(l,edge)+.05)/(Math.min(l,edge)+.05)>=4.5,'字與細邊須有足夠對比');
   }
  }
 }
 assert(legibleInk(source.variants[1],.4,source.themeColors).outline);
 assert(legibleInk(source.variants[1],.45,source.themeColors).outline);
 assert.equal(legibleInk(source.variants[1],1,source.themeColors).outline,null);
});
