// 階段 A：同一份向量資料產生 UIKit 繪製碼與可離線開啟的 SVG 預覽。
// 不改既有造型產生器，也不接入目前使用中的鍵盤。
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const source = JSON.parse(fs.readFileSync(path.join(__dirname, 'fox_letter_prototype.json'), 'utf8'));

function parsePath(d) {
  const tokens = d.match(/[MLCQZE]|-?\d*\.?\d+/g) || [];
  const ops = [];
  let i = 0;
  const read = () => {
    const value = Number(tokens[i++]);
    assert(Number.isFinite(value), '路徑座標必須是數字');
    return value;
  };
  while (i < tokens.length) {
    const command = tokens[i++];
    if (command === 'M' || command === 'L') ops.push(command === 'M' ? 0 : 1, read(), read());
    else if (command === 'C') ops.push(2, read(), read(), read(), read(), read(), read());
    else if (command === 'Q') ops.push(3, read(), read(), read(), read());
    else if (command === 'Z') ops.push(4);
    else if (command === 'E') {
      const [cx, cy, rx, ry] = [read(), read(), read(), read()];
      const k = 0.5522847498307936;
      ops.push(0, cx + rx, cy,
        2, cx + rx, cy + ry * k, cx + rx * k, cy + ry, cx, cy + ry,
        2, cx - rx * k, cy + ry, cx - rx, cy + ry * k, cx - rx, cy,
        2, cx - rx, cy - ry * k, cx - rx * k, cy - ry, cx, cy - ry,
        2, cx + rx * k, cy - ry, cx + rx, cy - ry * k, cx + rx, cy, 4);
    } else throw new Error(`不支援的路徑指令：${command}`);
  }
  return ops.map(v => Number(v.toFixed(7)));
}

const layers = source.layers.map(layer => ({ ...layer, ops: parsePath(layer.path) }));
const watercolor = require('./fox_letter_watercolor');

function geometry(width, height) {
  assert(width > 0 && height > 0, '預覽尺寸必須大於零');
  const frame = { x: 2, y: 2, width: width - 4, height: height - 4 };
  assert(frame.width > 0 && frame.height > 0, '按鍵太小');
  const faceWidth = Math.min(frame.width * source.faceWidthFraction, frame.height * source.faceHeightLimit);
  const face = { x: frame.x + (frame.width - faceWidth) / 2,
    y: frame.y + frame.height * (1 - source.faceBottomInset) - faceWidth * source.faceAspect,
    width: faceWidth, height: faceWidth * source.faceAspect };
  const rect = ([x, y, w, h]) => ({ x: frame.x + frame.width * x / 100,
    y: frame.y + frame.height * y / 100, width: frame.width * w / 100, height: frame.height * h / 100 });
  return { frame, face, label: rect(source.labelRect), hint: rect(source.hintRect),
    ends: Math.min(frame.width, frame.height * source.endCapAspect) };
}

function svgPath(ops, rect, ends) {
  const px = x => ends === null ? rect.x + rect.width * x / 100
    : x < 50 ? rect.x + ends * x / 100 : rect.x + rect.width - ends * (100 - x) / 100;
  const pt = k => `${px(ops[k]).toFixed(4)} ${(rect.y + rect.height * ops[k + 1] / 100).toFixed(4)}`;
  let result = '', i = 0;
  while (i < ops.length) {
    switch (ops[i]) {
      case 0: result += `M${pt(i + 1)}`; i += 3; break;
      case 1: result += `L${pt(i + 1)}`; i += 3; break;
      case 2: result += `C${pt(i + 1)} ${pt(i + 3)} ${pt(i + 5)}`; i += 7; break;
      case 3: result += `Q${pt(i + 1)} ${pt(i + 3)}`; i += 5; break;
      case 4: result += 'Z'; i++; break;
      default: throw new Error('無效路徑操作');
    }
  }
  return result;
}

function swiftSource() {
  const rect = values => `CGRect(x: ${values[0] / 100}, y: ${values[1] / 100}, width: ${values[2] / 100}, height: ${values[3] / 100})`;
  const entries = layers.map(l => `        ArtLayer(space: .${l.space}, fill: UIColor(hex: 0x${l.fill.slice(1)}), stroke: ${l.stroke ? `UIColor(hex: 0x${l.stroke.slice(1)})` : 'nil'}, lineWidth: ${l.strokeWidth || 0},\n                 ops: [${l.ops.join(', ')}])`).join(',\n');
  return `// 由 node tools/build_fox_letter_prototype.js 產生，請修改 tools/fox_letter_prototype.json。
import UIKit

/// 共用狐狸臉形幾何，供單顆原型與正式角色主題使用。
/// 與離線預覽使用相同幾何資料；文字由各自的視圖疊上。
enum FoxLetterPrototype {
    enum Space { case head, face }
    struct ArtLayer {
        let space: Space
        let fill: UIColor
        let stroke: UIColor?
        let lineWidth: CGFloat
        let ops: [CGFloat]
    }
    struct Layout {
        let frame: CGRect
        let face: CGRect
        let label: CGRect
        let hint: CGRect
        let ends: CGFloat
    }
    static let textColor = UIColor(hex: 0x${source.textColor.slice(1)})
    static let hintColor = UIColor(hex: 0x${source.hintColor.slice(1)})
    static let layers: [ArtLayer] = [
${entries}
    ]

    static func layout(in bounds: CGRect) -> Layout {
        let frame = bounds.insetBy(dx: 2, dy: 2)
        guard frame.width > 0, frame.height > 0 else {
            return Layout(frame: .zero, face: .zero, label: .zero, hint: .zero, ends: 0)
        }
        let faceWidth = min(frame.width * ${source.faceWidthFraction}, frame.height * ${source.faceHeightLimit})
        let face = CGRect(x: frame.midX - faceWidth / 2,
                          y: frame.maxY - frame.height * ${source.faceBottomInset} - faceWidth * ${source.faceAspect},
                          width: faceWidth, height: faceWidth * ${source.faceAspect})
        func place(_ r: CGRect) -> CGRect {
            CGRect(x: frame.minX + frame.width * r.minX, y: frame.minY + frame.height * r.minY,
                   width: frame.width * r.width, height: frame.height * r.height)
        }
        return Layout(frame: frame, face: face,
                      label: place(${rect(source.labelRect)}),
                      hint: place(${rect(source.hintRect)}),
                      ends: min(frame.width, frame.height * ${source.endCapAspect}))
    }
}

/// 圖層只建立一次，調整尺寸時更新路徑，文字與插畫分開。
final class FoxLetterPrototypeView: UIView {
    var text = "A" { didSet { label.text = text; setNeedsLayout() } }
    var hint = "" { didSet { hintLabel.text = hint; setNeedsLayout() } }
    var fontScale: CGFloat = 1 { didSet { setNeedsLayout() } }
    var isPressed = false {
        didSet { drawing.opacity = isPressed ? 0.82 : 1 }
    }
    private let drawing = CALayer()
    private let label = UILabel()
    private let hintLabel = UILabel()
    private var artwork: [CAShapeLayer] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = false
        layer.addSublayer(drawing)
        for definition in FoxLetterPrototype.layers {
            let shape = CAShapeLayer()
            shape.fillColor = definition.fill.cgColor
            shape.strokeColor = definition.stroke?.cgColor
            shape.lineWidth = definition.lineWidth
            shape.lineJoin = .round
            shape.lineCap = .round
            drawing.addSublayer(shape)
            artwork.append(shape)
        }
        label.text = text
        label.textColor = FoxLetterPrototype.textColor
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        label.baselineAdjustment = .alignCenters
        addSubview(label)
        hintLabel.textColor = FoxLetterPrototype.hintColor
        hintLabel.textAlignment = .right
        hintLabel.adjustsFontSizeToFitWidth = true
        addSubview(hintLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let layout = FoxLetterPrototype.layout(in: bounds)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        drawing.frame = bounds
        for (shape, definition) in zip(artwork, FoxLetterPrototype.layers) {
            shape.isHidden = layout.frame.isEmpty
            shape.frame = bounds
            shape.path = KeyShapeArt.build(definition.ops,
                in: definition.space == .head ? layout.frame : layout.face,
                ends: definition.space == .head ? layout.ends : nil)
        }
        CATransaction.commit()
        label.isHidden = layout.frame.isEmpty
        hintLabel.isHidden = layout.frame.isEmpty || hint.isEmpty
        guard !layout.frame.isEmpty else { return }
        label.frame = layout.label
        let mainFont = UIFont.rounded(min(23 * fontScale, layout.label.height), .bold)
        label.font = mainFont.withSize(mainFont.pointSize * min(1, layout.label.height / mainFont.lineHeight))
        hintLabel.frame = layout.hint
        let hintFont = UIFont.rounded(min(9 * fontScale, layout.hint.height), .medium)
        hintLabel.font = hintFont.withSize(hintFont.pointSize * min(1, layout.hint.height / hintFont.lineHeight))
    }
}
`;
}

function htmlSource() {
  const data = JSON.stringify({ source, layers });
  return `<!doctype html>
<html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>小狐狸的楓葉信 · 水彩修正版</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#f7f0e8;color:#483b36;font:15px/1.6 system-ui,"Microsoft JhengHei","PingFang TC",sans-serif}main{max-width:1100px;margin:auto;padding:36px 36px 28px}header{display:flex;align-items:end;justify-content:space-between;gap:20px;margin-bottom:22px}h1{font-size:29px;margin:3px 0 0;letter-spacing:.07em}h2{font-size:17px;margin:0 0 4px}p{margin:4px 0;color:#766b63}.eyebrow{font-size:12px;letter-spacing:.15em;color:#9f653f}.badge{border:1px solid #cbb7a3;padding:6px 12px;border-radius:20px;font-size:12px;white-space:nowrap}.controls{display:flex;gap:20px;align-items:center;flex-wrap:wrap;background:#fffaf4;border:1px solid #e6d8c8;padding:12px 16px;border-radius:12px;margin-bottom:20px}label{display:flex;align-items:center;gap:8px}input{accent-color:#aa623c}input[type=range]{width:100px}input[type=text]{width:58px;padding:5px;border:1px solid #d9c6b5;border-radius:5px;background:white}button{border:1px solid #d5bba5;background:#f5e0cb;color:#65452f;padding:6px 12px;border-radius:7px;cursor:pointer}.cards{display:grid;grid-template-columns:1fr 1fr 1.35fr;gap:16px}.card{background:#fffaf4;border:1px solid #e5d5c4;border-radius:15px;padding:17px;min-width:0}.stage{height:278px;border-radius:10px;background:#493e49;margin:13px 0 14px;display:flex;align-items:center;justify-content:center;overflow:hidden}.actual{height:90px;display:flex;gap:13px;align-items:center;justify-content:center;border-top:1px solid #e9dccc;border-bottom:1px solid #e9dccc;background:#eee3d7}.actual.dark{background:#493e49}.caption{font-size:12px;margin-top:9px}.note{font-size:12px;color:#87766a}.strip{background:#493e49;border-radius:12px;margin-top:18px;padding:15px;display:flex;align-items:center;justify-content:center;gap:3px;min-height:90px}.strip svg{flex:none}footer{margin-top:18px;font-size:12px;color:#89796e}.zone{pointer-events:none;fill:#50cdb828;stroke:#50cdb8;stroke-width:.35}.hint-zone{fill:#e4af3028;stroke:#e4af30}.face-zone{fill:#e0709020;stroke:#e07090}.zones-off .zone{display:none}.legend span{margin-right:14px}.dot{display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:4px}.dim .art{opacity:.82}svg{display:block;overflow:visible}.small-label{font-size:11px;text-align:center;min-height:20px}@media(max-width:760px){main{padding:22px 16px}.cards{grid-template-columns:1fr}.stage{height:230px}.strip{overflow:auto;justify-content:flex-start}header{align-items:start}h1{font-size:23px}}
</style>
<main class="zones-off" id="preview">
<header><div><div class="eyebrow">FOX LETTER / WATERCOLOR REVISION</div><h1>小狐狸的楓葉信</h1><p>水彩插畫鍵帽 · 中央文字 · 下緣小五官</p></div><div class="badge">水彩修正版 · 素材接入</div></header>
<p style="margin-bottom:14px"><a href="theme.html" style="color:#98542f;font-weight:600">查看整套主題與各輸入法預覽 →</a></p>
<div class="controls"><label>英文字母 <input id="letter" type="text" value="A" maxlength="3"></label><label>高度 <input id="height" type="range" min="0.8" max="1.3" step="0.05" value="1"><output id="heightValue">100%</output></label><label>字體 <input id="font" type="range" min="0.8" max="1.3" step="0.05" value="1"></label><label><input id="zones" type="checkbox">顯示分區</label><button id="press">切換按下狀態</button></div>
<section class="cards">
<article class="card"><h2>英文窄鍵</h2><p>34 × 48 pt</p><div class="stage" id="large-en"></div><div class="actual dark" id="actual-en"></div><div class="caption">放大 4 倍 + 原尺寸 1 倍</div><p class="note">耳朵與臉形是一體，沒有另外畫身體。</p></article>
<article class="card"><h2>注音與提示字</h2><p>36 × 46 pt</p><div class="stage" id="large-zh"></div><div class="actual dark" id="actual-zh"></div><div class="caption">放大 4 倍 + 原尺寸 1 倍</div><p class="note">主要文字、提示字、五官各有獨立區域。</p></article>
<article class="card"><h2>寬鍵構圖</h2><p>160 × 46 pt</p><div class="stage" id="large-wide"></div><div class="actual dark" id="actual-wide"></div><div class="caption">放大 1.8 倍 + 原尺寸 1 倍</div><p class="note">只延展臉形中段，五官與耳朵維持尺寸。</p></article>
</section>
<p class="note legend" style="margin-top:14px"><span><i class="dot" style="background:#50cdb8"></i>主要文字區</span><span><i class="dot" style="background:#e4af30"></i>提示字區</span><span><i class="dot" style="background:#e07090"></i>五官區</span></p>
<h2 style="margin-top:20px">連續窄鍵可讀性</h2><div class="strip" id="strip"></div>
<footer>本頁已改用水彩鍵帽素材。文字、提示字與寬鍵切片仍獨立排版；iPhone 實際字型與渲染待驗證。<br>前一版平面向量外觀已退回，不代表本次美術目標。</footer>
</main>
<script>
'use strict';
const {source,layers}=${data};
const atlas=${JSON.stringify(watercolor.atlas)},spriteIndex=${watercolor.spriteIndex.toString()},imageSlices=${watercolor.imageSlices.toString()},watercolorSVG=${watercolor.watercolorSVG.toString()};
const geometry=${geometry.toString()};
const svgPath=${svgPath.toString()};
const assert=(condition,message)=>{if(!condition)throw new Error(message)};
const escape=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function key(width,height,text,hint,scale,fontScale){
 const g=geometry(width,height);
 const art=watercolorSVG({x:0,y:0,width,height},0,'text');
 const zone=(r,cls)=>'<rect class="zone '+cls+'" x="'+r.x+'" y="'+r.y+'" width="'+r.width+'" height="'+r.height+'"/>';
 const font=Math.min(23*fontScale,g.label.height,g.label.width/Math.max(1,[...text].length)*1.45);
 return '<svg xmlns="http://www.w3.org/2000/svg" aria-label="'+escape(text)+'" width="'+width*scale+'" height="'+height*scale+'" viewBox="0 0 '+width+' '+height+'"><g class="art">'+art+'</g>'+zone(g.label,'')+zone(g.hint,'hint-zone')+zone(g.face,'face-zone')+'<text x="'+(g.label.x+g.label.width/2)+'" y="'+(g.label.y+g.label.height/2)+'" dominant-baseline="central" text-anchor="middle" fill="'+source.textColor+'" font-family="system-ui, sans-serif" font-size="'+font+'" font-weight="750">'+escape(text)+'</text><text x="'+(g.hint.x+g.hint.width)+'" y="'+(g.hint.y+g.hint.height/2)+'" dominant-baseline="central" text-anchor="end" fill="'+source.hintColor+'" font-size="'+Math.min(9*fontScale,g.hint.height)+'">'+escape(hint)+'</text></svg>';
}
function fitText(svg){
 const zones=svg.querySelectorAll('.zone'),texts=svg.querySelectorAll('text');
 texts.forEach((text,i)=>{
  if(!text.textContent)return;
  const zone=zones[i],width=Number(zone.getAttribute('width')),height=Number(zone.getAttribute('height'));
  let box=text.getBBox();
  for(let attempt=0;attempt<8;attempt++){
   box=text.getBBox();
   const fit=Math.min(1,width/Math.max(box.width,0.01),height/Math.max(box.height,0.01));
   if(fit>=.999)break;
   text.setAttribute('font-size',Number(text.getAttribute('font-size'))*fit*.96);
  }
  box=text.getBBox();
  const center=Number(zone.getAttribute('y'))+height/2;
  text.setAttribute('y',Number(text.getAttribute('y'))+center-box.y-box.height/2);
 });
}
function render(){
 const h=Number(document.querySelector('#height').value),f=Number(document.querySelector('#font').value),t=document.querySelector('#letter').value||'A';
 document.querySelector('#heightValue').value=Math.round(h*100)+'%';
 for(const [id,w,base,text,hint,zoom] of [['en',34,48,t,'',4],['zh',36,46,'ㄅ','1',4],['wide',160,46,'空白','',1.8]]){
  document.querySelector('#large-'+id).innerHTML=key(w,base*h,text,hint,zoom,f);
  document.querySelector('#actual-'+id).innerHTML=key(w,base*h,text,hint,1,f);
 }
 document.querySelector('#strip').innerHTML=[...'qwertyuiop'].map(c=>key(34,48*h,c,'',1,f)).join('');
 document.querySelectorAll('svg[aria-label]').forEach(fitText);
 document.querySelector('#preview').classList.toggle('zones-off',!document.querySelector('#zones').checked);
}
for(const id of ['letter','height','font','zones'])document.querySelector('#'+id).addEventListener('input',render);
document.querySelector('#press').addEventListener('click',()=>document.querySelector('#preview').classList.toggle('dim'));
render();
document.fonts.ready.then(render);
</script></html>
`;
}

function outputs() {
  return new Map([
    ['Keyboard/FoxLetterPrototype.swift', swiftSource()],
    ['docs/previews/fox-letter/index.html', htmlSource()]
  ]);
}

if (require.main === module) {
  for (const [name, content] of outputs()) {
    const file = path.join(root, name);
    if (process.argv.includes('--check')) {
      assert(fs.existsSync(file) && fs.readFileSync(file, 'utf8') === content, `${name} 需要重新產生`);
    } else {
      fs.mkdirSync(path.dirname(file), { recursive: true });
      fs.writeFileSync(file, content);
      console.log(name);
    }
  }
}
module.exports = { source, layers, parsePath, geometry, svgPath, outputs };
