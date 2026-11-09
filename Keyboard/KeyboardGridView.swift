import UIKit

/// 一顆按鍵（只負責畫，觸控由 KeyboardGridView 統一處理）
final class KeyButton: UIView {
    var spec: KeySpec {
        didSet {
            updateFace()
            applyColors()
            if style.isIllustrated { setNeedsLayout() }
        }
    }
    var style: KeyboardStyle {
        didSet {
            updateFace()
            applyColors()
            setNeedsLayout()
        }
    }
    var isPressed = false {
        didSet { if oldValue != isPressed { pressChanged() } }
    }
    var visualOpacity: CGFloat = 1 {
        didSet { updateVisualOpacity() }
    }
    var illustratedIndex = 0 {
        didSet { if oldValue != illustratedIndex && style.isIllustrated { applyColors() } }
    }

    private let content = UIView()
    private var foxArtwork: FoxLetterArtworkView?
    private struct FoxInkConfiguration: Equatable {
        let fur: UIColor
        let preferred: UIColor
        let top: UIColor
        let bottom: UIColor
        let opacity: CGFloat
    }
    private var foxInkConfiguration: FoxInkConfiguration?
    private var foxNormalInk = FoxLetterTheme.Ink(color: .white, outline: nil)
    private var foxPressedInk = FoxLetterTheme.Ink(color: .white, outline: nil)
    private var foxNormalTitle: NSAttributedString?
    private var foxPressedTitle: NSAttributedString?
    private var foxNormalSymbol: UIImage?
    private var foxPressedSymbol: UIImage?
    private var hasPersonalSpaceArt = false
    private var nativeGlass: KeyboardGlassSurface?
    private let shadowLayer = CAShapeLayer()
    // 液態玻璃：透出後面的照片（模糊、稍微放大）＋亮亮的玻璃邊
    private let glassLayer = CALayer()
    private let glassMask = CAShapeLayer()
    private let rimLayer = CAGradientLayer()
    private let rimMask = CAShapeLayer()
    // 液態玻璃、金屬：邊緣往內一圈暗一點（厚度）、上半部一大片反光（鼓鼓的）
    private let edgeLayer = CAShapeLayer()
    private let edgeMask = CAShapeLayer()
    private let sheenLayer = CAGradientLayer()
    private let sheenMask = CAShapeLayer()
    // 反光和光點都放在這個照按鍵形狀剪裁的容器裡，造型（貓掌、熊熊…）外面才不會多出一圈圓邊
    private let shineClip = CALayer()
    private let shineClipMask = CAShapeLayer()
    private let dotLayer = CAShapeLayer()
    // 液態系列：肉球（細節）也立體：底下影子、上緣亮邊、下緣暗邊
    private let padShadow = CAShapeLayer()
    private let padHi = CAShapeLayer()
    private let padHiMask = CAShapeLayer()
    private let padLo = CAShapeLayer()
    private let padLoMask = CAShapeLayer()
    private var shiny: Bool { style.finish == .liquid || style.finish == .metal }
    private var glassVersion = -1
    private let bodyLayer = CAShapeLayer()
    private let glossLayer = CAShapeLayer()
    private let detailLayer = CAShapeLayer()
    private let linesLayer = CAShapeLayer()
    private let cushionLayer = CAGradientLayer()
    private let cushionMask = CAShapeLayer()
    // 影子只畫在按鍵外面（按鍵調透明時才不會看到兩層疊在一起）
    private let shadowMask = CAShapeLayer()
    // 立體：側面的厚度
    private var depth: CGFloat = 0
    private let label = UILabel()
    private let hintLabel = UILabel()
    private let icon = UIImageView()

    init(spec: KeySpec, style: KeyboardStyle) {
        self.spec = spec
        self.style = style
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        addSubview(content)
        shadowMask.fillRule = .evenOdd
        shadowLayer.mask = shadowMask
        content.layer.addSublayer(shadowLayer)
        glassLayer.mask = glassMask
        glassLayer.contentsGravity = .resize
        content.layer.addSublayer(glassLayer)
        content.layer.addSublayer(bodyLayer)
        content.layer.addSublayer(glossLayer)
        cushionLayer.mask = cushionMask
        cushionLayer.locations = [0, 0.55, 1]
        content.layer.addSublayer(cushionLayer)
        content.layer.addSublayer(padShadow)
        content.layer.addSublayer(detailLayer)
        padHi.fillRule = .evenOdd
        padHi.fillColor = UIColor.white.withAlphaComponent(0.75).cgColor
        padHi.mask = padHiMask
        content.layer.addSublayer(padHi)
        padLo.fillRule = .evenOdd
        padLo.fillColor = UIColor.black.withAlphaComponent(0.2).cgColor
        padLo.mask = padLoMask
        content.layer.addSublayer(padLo)
        linesLayer.fillColor = nil
        linesLayer.lineCap = .round
        linesLayer.lineJoin = .round
        content.layer.addSublayer(linesLayer)
        rimMask.fillColor = nil
        rimMask.strokeColor = UIColor.black.cgColor
        rimMask.lineJoin = .round
        rimLayer.mask = rimMask
        rimLayer.locations = [0, 0.5, 1]
        edgeLayer.fillColor = nil
        edgeLayer.lineJoin = .round
        edgeLayer.mask = edgeMask
        content.layer.insertSublayer(edgeLayer, above: cushionLayer)
        sheenLayer.mask = sheenMask
        sheenLayer.colors = [UIColor.white.withAlphaComponent(0.72).cgColor, UIColor.white.withAlphaComponent(0).cgColor]
        shineClip.mask = shineClipMask
        shineClip.addSublayer(sheenLayer)
        dotLayer.fillColor = UIColor.white.withAlphaComponent(0.9).cgColor
        shineClip.addSublayer(dotLayer)
        content.layer.insertSublayer(shineClip, above: edgeLayer)
        content.layer.addSublayer(rimLayer)
        bodyLayer.lineJoin = .round
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        label.baselineAdjustment = .alignCenters
        content.addSubview(label)
        hintLabel.textAlignment = .right
        hintLabel.adjustsFontSizeToFitWidth = true
        hintLabel.minimumScaleFactor = 0.5
        content.addSubview(hintLabel)
        icon.contentMode = .center
        content.addSubview(icon)
        updateFace()
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        content.bounds = bounds
        content.center = CGPoint(x: bounds.midX, y: bounds.midY)
        if style.isIllustrated {
            layoutFoxLetter()
            return
        }
        // 線條造型（貓咪、熊熊…）有自己的形狀，空隙留小一點，圖案才夠大
        let art = style.shape.art != nil
        var outer = bounds.insetBy(dx: (art ? 1.2 : 3) * style.gapScale, dy: (art ? 1.8 : 4.5) * style.gapScale)
        guard outer.width > 4, outer.height > 4 else { return }
        // 「造型大小」：造型可以畫得比按鍵大一點（寬的空白鍵不放大，才不會蓋到上一排）
        if art && outer.width < outer.height * 1.65 {
            let grow = style.shapeScale - 1
            outer = outer.insetBy(dx: -outer.width * grow / 2, dy: -outer.height * grow / 2)
        }
        let finish = style.finish
        // 立體：按鍵往上留出側面的厚度
        depth = finish == .raised ? min(4.5, outer.height * 0.12) : 0
        outer.size.height -= depth
        outer = style.shape.naturalRect(in: outer, scale: style.shapeScale)
        let path = style.shape.path(in: outer)
        var shift = CGAffineTransform(translationX: 0, y: depth > 0 ? depth : (finish == .puffy ? 3 : 1.5))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bodyLayer.path = path
        // 漸層的範圍比按鍵大，放大的造型才整個都有漸層
        let grow: CGFloat = (finish == .liquid || finish == .metal) ? 0.2 : 0.5
        let big = bounds.insetBy(dx: -bounds.width * grow, dy: -bounds.height * grow)
        cushionLayer.frame = big
        var toBig = CGAffineTransform(translationX: -big.minX, y: -big.minY)
        cushionMask.path = path.copy(using: &toBig)
        cushionLayer.isHidden = finish == .outline || (!style.shape.isSoftShape && finish == .flat)
        // 線稿：線的粗細跟著按鍵大小，細細的
        let lineWidth = min(1.6, max(0.9, outer.height * 0.028))
        bodyLayer.lineWidth = lineWidth
        linesLayer.lineWidth = lineWidth * 0.9
        linesLayer.path = style.shape.linesPath(in: outer)
        let detail = style.shape.detailPath(in: outer)
        detailLayer.path = detail
        let padOn = finish == .liquid || finish == .metal
        padShadow.isHidden = !padOn
        padHi.isHidden = !padOn
        padLo.isHidden = !padOn
        if padOn, let detail = detail {
            // 肉球往下、往上各移一點：「原本的」減掉「移過的」就是上緣、下緣那一彎
            let d = max(1, outer.height * 0.035)
            var down = CGAffineTransform(translationX: 0, y: d)
            var up = CGAffineTransform(translationX: 0, y: -d)
            let shiftedDown = detail.copy(using: &down)
            let shiftedUp = detail.copy(using: &up)
            for l in [padShadow, padHi, padLo, padHiMask, padLoMask] { l.frame = bounds }
            padShadow.path = shiftedDown
            let hi = CGMutablePath(); hi.addPath(detail); if let s = shiftedDown { hi.addPath(s) }
            padHi.path = hi
            padHiMask.path = detail
            let lo = CGMutablePath(); lo.addPath(detail); if let s = shiftedUp { lo.addPath(s) }
            padLo.path = lo
            padLoMask.path = detail
        }
        detailLayer.opacity = Float(style.shape.detailOpacity(in: outer))
        shadowLayer.path = path.copy(using: &shift)
        shadowLayer.frame = bounds
        shadowMask.frame = bounds
        let hole = CGMutablePath()
        hole.addRect(bounds.insetBy(dx: -bounds.width, dy: -bounds.height))
        hole.addPath(path)
        shadowMask.path = hole
        let body = style.shape.bodyRect(in: outer)
        layoutGlass(path: path, outer: outer, body: body)
        if finish == .puffy {
            // 左上角一顆圓圓的反光，看起來鼓鼓的
            let gloss = CGRect(x: body.minX + body.width * 0.14, y: body.minY + body.height * 0.1,
                               width: body.width * 0.32, height: body.height * 0.2)
            glossLayer.path = UIBezierPath(ovalIn: gloss).cgPath
        } else if finish == .liquid || finish == .metal {
            // 光點畫在 dotLayer（會照按鍵形狀剪裁）
            glossLayer.path = nil
        } else if style.shape == .jelly && finish != .outline {
            let gloss = CGRect(x: body.minX + body.width * 0.2, y: body.minY + 2.5,
                               width: body.width * 0.6, height: max(2.5, body.height * 0.16))
            glossLayer.path = UIBezierPath(roundedRect: gloss, cornerRadius: gloss.height / 2).cgPath
        } else {
            glossLayer.path = nil
        }
        CATransaction.commit()
        let textRect = body
        if style.shape.isSoftShape {
            // 上限跟著整顆按鍵，不跟著造型裡放字的框：造型不拉長之後框變小，字會被卡住，「字的大小」就調不動
            let cap = bounds.height * 0.75
            label.font = KeyFonts.font(style.fontID, size: min(spec.fontSize * style.fontScale, cap),
                                       weight: spec.kind == .normal ? .regular : .semibold)
            if case .symbol(let name) = spec.face {
                icon.image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: min(18 * style.fontScale, cap), weight: .medium))
            }
        }
        // 字的框以造型的字區為中心放寬到整顆按鍵，字放大時才不會被縮回去（寬鍵和長方形的圓角照舊）
        if style.shape != .rounded && bounds.width <= bounds.height * 1.35 {
            let w = max(textRect.width, bounds.width - 2), h = max(textRect.height, label.font.lineHeight)
            label.frame = CGRect(x: textRect.midX - w / 2, y: textRect.midY - h / 2, width: w, height: h)
        } else {
            label.frame = textRect.insetBy(dx: 2, dy: 0)
        }
        icon.frame = textRect
        hintLabel.font = .systemFont(ofSize: min(10 * style.fontScale, textRect.height * 0.3), weight: .medium)
        hintLabel.frame = CGRect(x: textRect.minX, y: textRect.minY + 1, width: textRect.width - 3, height: hintLabel.font.lineHeight)
        if icon.contentMode == .scaleAspectFit {
            // 空白鍵的圖：小小的放在正中間
            let h = textRect.height * 0.8
            icon.frame = CGRect(x: textRect.midX - h * 1.5, y: textRect.midY - h / 2, width: h * 3, height: h)
        }
    }

    /// 照片或位置真的變了才重新對準（打字時版面常常重排，不用每次都重做）
    func refreshGlassIfNeeded() {
        guard glassVersion != GlassBackdrop.version else { return }
        glassVersion = GlassBackdrop.version
        layoutGlass()
    }

    /// 原生玻璃直接取景；替代畫法則把背景照片換成按鍵座標，再稍微放大。
    func layoutGlass(path: CGPath? = nil, outer: CGRect? = nil, body: CGRect? = nil) {
        if style.isIllustrated {
            glassVersion = GlassBackdrop.version
            setPaintedLayersHidden(true)
            return
        }
        let on = style.finish == .liquid
        let native = style.usesNativeGlassKeys
        let paintedShine = shiny && !native
        glassVersion = GlassBackdrop.version
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        rimLayer.isHidden = !paintedShine
        edgeLayer.isHidden = !paintedShine
        shineClip.isHidden = !paintedShine
        shadowLayer.isHidden = native
        cushionLayer.isHidden = native || style.finish == .outline || (!style.shape.isSoftShape && style.finish == .flat)
        // 再往下一點一層淡淡的影子：浮起來的感覺（給形狀，系統才不用每次自己算）
        shadowLayer.shadowOpacity = paintedShine ? 0.16 : 0
        shadowLayer.shadowColor = UIColor.black.cgColor
        shadowLayer.shadowOffset = CGSize(width: 0, height: 2.5)
        shadowLayer.shadowRadius = 2
        shadowLayer.shadowPath = paintedShine ? shadowLayer.path : nil
        // 只有替代畫法與金屬才快取；原生玻璃必須保留即時合成。
        content.layer.shouldRasterize = paintedShine
        content.layer.rasterizationScale = UIScreen.main.scale
        let keyPath = path ?? bodyLayer.path
        if native {
            if let area = keyPath?.boundingBoxOfPath {
                nativeGlass?.frame = area
                let radius = style.shape == .jelly ? min(area.width, area.height) * 0.42 : min(7, area.height * 0.22)
                nativeGlass?.setCornerRadius(radius)
            }
            glassLayer.isHidden = true
            glassLayer.contents = nil
            return
        }
        if paintedShine {
            rimLayer.frame = bounds
            rimMask.frame = bounds
            rimMask.path = keyPath
            rimMask.lineWidth = 1.7
            edgeLayer.frame = bounds
            edgeMask.frame = bounds
            edgeLayer.path = keyPath
            edgeMask.path = keyPath
            edgeLayer.lineWidth = 5
            shineClip.frame = bounds
            shineClipMask.frame = bounds
            shineClipMask.path = keyPath
            if let o = outer {
                let r = CGRect(x: o.minX + o.width * 0.07, y: o.minY + o.height * 0.06, width: o.width * 0.86, height: o.height * 0.44)
                sheenLayer.frame = r
                sheenMask.frame = sheenLayer.bounds
                sheenMask.path = UIBezierPath(roundedRect: sheenLayer.bounds, cornerRadius: r.height * 0.6).cgPath
                // 左上角一顆很亮的小光點
                let dot = min(o.height * 0.13, 6)
                dotLayer.frame = bounds
                dotLayer.path = UIBezierPath(ovalIn: CGRect(x: o.minX + o.width * 0.12, y: o.minY + o.height * 0.12,
                                                            width: dot * 1.8, height: dot)).cgPath
            }
        }
        guard on else { glassLayer.isHidden = true; return }
        guard let img = GlassBackdrop.image, let keyPath = keyPath, GlassBackdrop.rect.width > 0 else {
            glassLayer.isHidden = true
            return
        }
        let c = CGPoint(x: (body ?? bounds).midX, y: (body ?? bounds).midY)
        let r = GlassBackdrop.rect.offsetBy(dx: -frame.minX, dy: -frame.minY)
        let zoom: CGFloat = 1.08
        let lens = CGRect(x: c.x + (r.minX - c.x) * zoom, y: c.y + (r.minY - c.y) * zoom, width: r.width * zoom, height: r.height * zoom)
        guard lens.width > 0, lens.height > 0 else { glassLayer.isHidden = true; return }
        // 只放這顆鍵後面那一小塊照片（以前放整張再裁，每顆鍵都吃一大塊記憶體）
        let area = keyPath.boundingBoxOfPath.insetBy(dx: -2, dy: -2)
        glassLayer.isHidden = false
        glassLayer.contents = img
        glassLayer.frame = area
        glassLayer.contentsRect = CGRect(x: (area.minX - lens.minX) / lens.width, y: (area.minY - lens.minY) / lens.height,
                                         width: area.width / lens.width, height: area.height / lens.height)
        glassMask.frame = glassLayer.bounds
        var toLayer = CGAffineTransform(translationX: -area.minX, y: -area.minY)
        glassMask.path = keyPath.copy(using: &toLayer)
    }

    /// 空白鍵要畫自己的圖片
    private var spaceArt: UIImage? {
        guard case .text(let s) = spec.face, s.hasPrefix(KeySpec.spaceArtMark) else { return nil }
        return SpaceArt.image()
    }

    private func updateFace() {
        foxNormalSymbol = nil
        foxPressedSymbol = nil
        hintLabel.text = spec.hint
        hintLabel.isHidden = spec.hint.isEmpty
        if let art = spaceArt {
            hasPersonalSpaceArt = true
            label.isHidden = true
            icon.isHidden = false
            icon.contentMode = .scaleAspectFit
            icon.image = art
            return
        }
        hasPersonalSpaceArt = false
        switch spec.face {
        case .text(let s):
            label.isHidden = false
            icon.isHidden = true
            label.attributedText = nil
            label.text = s
            label.font = KeyFonts.font(style.fontID, size: spec.fontSize * style.fontScale, weight: spec.kind == .normal ? .regular : .semibold)
        case .symbol(let name):
            label.isHidden = true
            icon.isHidden = false
            icon.contentMode = .center
            icon.image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18 * style.fontScale, weight: .medium))
        }
    }

    private func applyColors() {
        if style.isIllustrated {
            nativeGlass?.removeFromSuperview()
            nativeGlass = nil
            if foxArtwork == nil {
                let artwork = FoxLetterArtworkView(frame: .zero)
                content.insertSubview(artwork, at: 0)
                foxArtwork = artwork
                setNeedsLayout()
            }
            foxArtwork?.look = style.themeLook
            setPaintedLayersHidden(true)
            glassLayer.contents = nil
            content.layer.shouldRasterize = false
            foxArtwork?.configure(index: illustratedIndex, action: spec.action, personalSpaceArt: hasPersonalSpaceArt)
            guard let artwork = foxArtwork else { return }
            let configuration = FoxInkConfiguration(fur: artwork.furColor, preferred: artwork.textColor,
                top: style.theme.backgroundTop, bottom: style.theme.backgroundBottom, opacity: style.keyAlpha)
            if style.themeLook != nil {
                // 設計圖鑑的主題字色已經配好，不用再算對比
                foxInkConfiguration = nil
                foxNormalInk = FoxLetterTheme.Ink(color: artwork.textColor, outline: nil)
                foxPressedInk = foxNormalInk
            } else if configuration != foxInkConfiguration {
                foxInkConfiguration = configuration
                foxNormalInk = FoxLetterTheme.paperInk(FoxLetterTheme.ink(fur: artwork.furColor, preferred: artwork.textColor,
                    opacity: style.keyAlpha, theme: style.theme))
                foxPressedInk = FoxLetterTheme.paperInk(FoxLetterTheme.ink(fur: artwork.furColor, preferred: artwork.textColor,
                    opacity: style.keyAlpha * 0.82, theme: style.theme))
            }
            foxNormalTitle = nil
            foxPressedTitle = nil
            if case .text(let text) = spec.face {
                label.attributedText = nil
                label.text = text
                if foxNormalInk.outline != nil || foxPressedInk.outline != nil {
                    foxNormalTitle = FoxLetterTheme.title(text, ink: foxNormalInk)
                    foxPressedTitle = FoxLetterTheme.title(text, ink: foxPressedInk)
                }
            } else {
                foxNormalSymbol = nil
                foxPressedSymbol = nil
                setNeedsLayout()
            }
            hintLabel.textColor = style.themeLook?.hint ?? style.theme.keyText
            hintLabel.textAlignment = .center
            updateFoxFeedback()
            return
        }
        if let artwork = foxArtwork {
            artwork.removeFromSuperview()
            foxArtwork = nil
            foxInkConfiguration = nil
            foxNormalTitle = nil
            foxPressedTitle = nil
            foxNormalSymbol = nil
            foxPressedSymbol = nil
            setPaintedLayersHidden(false)
            setNeedsLayout()
        }
        let t = style.theme
        hintLabel.textAlignment = .right
        var fill: UIColor
        let text: UIColor
        switch spec.kind {
        case .normal:
            fill = t.key
            text = t.keyText
        case .special:
            fill = t.specialKey
            text = t.specialText
        case .accent:
            fill = t.accent
            text = t.accentText
        }
        let native = style.usesNativeGlassKeys
        if native {
            // 原生材質即時取景，不能把它的父層快取成一張圖片。
            content.layer.shouldRasterize = false
            if nativeGlass == nil {
                let glass = KeyboardGlassSurface()
                content.insertSubview(glass, at: 0)
                content.layer.insertSublayer(glass.layer, below: shadowLayer)
                nativeGlass = glass
                setNeedsLayout()
            }
            let strength: CGFloat = spec.kind == .accent ? 0.65 : (spec.kind == .special ? 0.30 : 0.16)
            nativeGlass?.configure(tint: fill.withAlphaComponent(style.keyAlpha * strength), isDark: t.isDark)
        } else if let glass = nativeGlass {
            glass.removeFromSuperview()
            nativeGlass = nil
        }
        updateVisualOpacity()
        if isPressed {
            fill = spec.kind == .normal ? t.specialKey : t.key
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let a = style.keyAlpha
        switch style.finish {
        case .flat:
            bodyLayer.fillColor = fill.withAlphaComponent(a).cgColor
            bodyLayer.strokeColor = nil
            shadowLayer.fillColor = t.shadow.withAlphaComponent(style.shape.isSoftShape ? a * 0.32 : min(1, a + 0.1)).cgColor
            cushionLayer.colors = [UIColor.white.withAlphaComponent(a * 0.30).cgColor,
                                   UIColor.clear.cgColor, UIColor.black.withAlphaComponent(a * 0.04).cgColor]
        case .puffy:
            bodyLayer.fillColor = fill.withAlphaComponent(a).cgColor
            bodyLayer.strokeColor = nil
            shadowLayer.fillColor = t.shadow.withAlphaComponent(min(1, a * 0.75)).cgColor
            cushionLayer.colors = [UIColor.white.withAlphaComponent(a * 0.5).cgColor,
                                   UIColor.clear.cgColor, UIColor.black.withAlphaComponent(a * (t.isDark ? 0.22 : 0.10)).cgColor]
        case .outline:
            // 線稿：只畫一條細線，裡面透明（背景照片完全露出來）；按下去時淡淡填一層
            bodyLayer.fillColor = isPressed ? style.lineColor.withAlphaComponent(0.14).cgColor : UIColor.clear.cgColor
            bodyLayer.strokeColor = style.lineColor.cgColor
            shadowLayer.fillColor = UIColor.clear.cgColor
            cushionLayer.colors = [UIColor.clear.cgColor, UIColor.clear.cgColor, UIColor.clear.cgColor]
        case .liquid:
            // 原生玻璃自己產生折射與亮邊；只疊淡色與按壓回饋，不再疊大白光點。
            bodyLayer.fillColor = native
                ? fill.withAlphaComponent(a * (isPressed ? 0.32 : 0.08)).cgColor
                : fill.withAlphaComponent(a * (isPressed ? 0.55 : 0.28)).blended(white: t.isDark ? 0.05 : 0.12).cgColor
            bodyLayer.strokeColor = nil
            shadowLayer.fillColor = t.shadow.withAlphaComponent(0.32).cgColor
            cushionLayer.colors = [UIColor.white.withAlphaComponent(t.isDark ? 0.3 : 0.45).cgColor,
                                   UIColor.clear.cgColor, UIColor.white.withAlphaComponent(t.isDark ? 0.3 : 0.5).cgColor]
        case .metal:
            // 液態金屬：按鍵的顏色做成一條一條明暗的金屬反光（像鉻、像水銀）
            bodyLayer.fillColor = fill.withAlphaComponent(max(a, 0.9)).cgColor
            bodyLayer.strokeColor = nil
            shadowLayer.fillColor = fill.darker(0.35).withAlphaComponent(0.55).cgColor
            cushionLayer.colors = [fill.lighter(0.8), fill.lighter(0.35), fill.darker(0.62), fill.lighter(0.45), fill, fill.darker(0.55)]
                .map { $0.withAlphaComponent(max(a, 0.9)).cgColor }
        case .raised:
            // 側面用按鍵本身的顏色調暗，按鍵調得很透明也一定看得出厚度；按下去時側面消失（沉下去了）
            bodyLayer.fillColor = fill.withAlphaComponent(a).cgColor
            bodyLayer.strokeColor = nil
            shadowLayer.fillColor = fill.darker(t.isDark ? 0.55 : 0.78).withAlphaComponent(isPressed ? 0 : max(a, 0.85)).cgColor
            let v = max(a, 0.6)
            cushionLayer.colors = [UIColor.white.withAlphaComponent(v * (t.isDark ? 0.3 : 0.55)).cgColor,
                                   UIColor.clear.cgColor, UIColor.black.withAlphaComponent(v * (t.isDark ? 0.25 : 0.12)).cgColor]
        }
        // 金屬是六段明暗，其他是三段
        cushionLayer.locations = style.finish == .metal ? [0, 0.3, 0.5, 0.62, 0.82, 1] : [0, 0.55, 1]
        cushionLayer.isHidden = native || style.finish == .outline || (!style.shape.isSoftShape && style.finish == .flat)
        shadowLayer.isHidden = native
        rimLayer.isHidden = !shiny || native
        edgeLayer.isHidden = !shiny || native
        shineClip.isHidden = !shiny || native
        // 玻璃邊：上面最亮、中間淡、底部又亮起來；金屬邊：上亮下暗（像斜切的邊）
        rimLayer.colors = style.finish == .metal
            ? [UIColor.white.withAlphaComponent(0.95).cgColor, UIColor.white.withAlphaComponent(0.2).cgColor, UIColor.black.withAlphaComponent(0.45).cgColor]
            : [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0.2).cgColor, UIColor.white.withAlphaComponent(0.85).cgColor]
        edgeLayer.strokeColor = UIColor.black.withAlphaComponent(style.finish == .metal ? 0.22 : 0.13).cgColor
        if style.shape.art?.lineDetail == true {
            detailLayer.fillColor = style.lineColor.cgColor
        } else {
            detailLayer.fillColor = style.shape.detailColor(theme: t).withAlphaComponent(style.keyAlpha).cgColor
        }
        // 肉球底下的影子：肉球顏色調暗
        if let c = detailLayer.fillColor {
            padShadow.fillColor = UIColor(cgColor: c).darker(0.55).withAlphaComponent(0.45).cgColor
        }
        linesLayer.strokeColor = style.lineColor.cgColor
        glossLayer.fillColor = UIColor.white.withAlphaComponent(style.finish == .puffy ? (t.isDark ? 0.3 : 0.75)
            : (style.finish == .liquid || style.finish == .metal) ? 0.9 : (t.isDark ? 0.18 : 0.55)).cgColor
        CATransaction.commit()
        label.textColor = text
        hintLabel.textColor = text.withAlphaComponent(0.6)
        icon.tintColor = text
    }

    private func pressChanged() {
        if style.isIllustrated { updateFoxFeedback() }
        else { applyColors() }
        if (style.usesNativeGlassKeys || style.isIllustrated) && UIAccessibility.isReduceMotionEnabled {
            content.layer.removeAllAnimations()
            content.transform = .identity
            return
        }
        // 可愛的動作只給字的按鍵；空白、刪除這些照質感本來的樣子
        let motion = spec.action.isCharacter ? (KeyMotion(rawValue: style.motion) ?? .none) : .none
        let h = bounds.height
        let opts: UIView.AnimationOptions = [.allowUserInteraction, .beginFromCurrentState]
        if motion != .none {
            // 動起來的鍵放到最上面；按鍵特效是之後才加的，還是在它上面
            superview?.bringSubviewToFront(self)
        }
        if isPressed {
            switch motion {
            case .pop:
                UIView.animate(withDuration: 0.08, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0.8, options: opts) {
                    self.content.transform = CGAffineTransform(translationX: 0, y: -h * 0.22).scaledBy(x: 1.25, y: 1.25)
                }
                return
            case .jelly:
                // 壓扁（貼著地板）
                UIView.animate(withDuration: 0.06, delay: 0, options: opts) {
                    self.content.transform = CGAffineTransform(translationX: 0, y: h * 0.1).scaledBy(x: 1.18, y: 0.8)
                }
                return
            case .hop:
                UIView.animate(withDuration: 0.05, delay: 0, options: opts) {
                    self.content.transform = CGAffineTransform(translationX: 0, y: h * 0.04).scaledBy(x: 1.06, y: 0.9)
                }
                return
            case .wiggle:
                UIView.animate(withDuration: 0.06, delay: 0, options: opts) {
                    self.content.transform = CGAffineTransform(rotationAngle: 0.16).scaledBy(x: 1.08, y: 1.08)
                }
                return
            case .none:
                break
            }
            UIView.animate(withDuration: 0.05, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                // 胖胖的鍵按下去會被壓扁
                switch self.style.finish {
                case _ where self.style.isIllustrated: self.content.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
                case .puffy: self.content.transform = CGAffineTransform(scaleX: 1.06, y: 0.86)
                case .raised: self.content.transform = CGAffineTransform(translationX: 0, y: self.depth * 0.85)
                case .liquid:
                    let scale: CGFloat = self.style.usesNativeGlassKeys ? 0.97 : 0.9
                    self.content.transform = CGAffineTransform(scaleX: scale, y: scale)
                case .flat, .outline, .metal: self.content.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
                }
            }
        } else {
            switch motion {
            case .jelly:
                // 像果凍一樣 duang duang 抖回來
                UIView.animate(withDuration: 0.55, delay: 0, usingSpringWithDamping: 0.22, initialSpringVelocity: 4, options: opts) {
                    self.content.transform = .identity
                }
            case .hop:
                // 蹦一下：往上跳（拉長）→ 落地壓扁 → 回來
                UIView.animateKeyframes(withDuration: 0.42, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                    UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.35) {
                        self.content.transform = CGAffineTransform(translationX: 0, y: -h * 0.45).scaledBy(x: 0.92, y: 1.12)
                    }
                    UIView.addKeyframe(withRelativeStartTime: 0.35, relativeDuration: 0.3) {
                        self.content.transform = CGAffineTransform(translationX: 0, y: h * 0.08).scaledBy(x: 1.15, y: 0.85)
                    }
                    UIView.addKeyframe(withRelativeStartTime: 0.65, relativeDuration: 0.35) {
                        self.content.transform = .identity
                    }
                }
            case .wiggle:
                // 左右扭一扭
                UIView.animateKeyframes(withDuration: 0.4, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                    for (i, angle) in [-0.2, 0.13, -0.07, 0.03, 0].enumerated() {
                        UIView.addKeyframe(withRelativeStartTime: Double(i) * 0.2, relativeDuration: 0.2) {
                            self.content.transform = CGAffineTransform(rotationAngle: CGFloat(angle))
                        }
                    }
                }
            default:
                // 放開後很快回到原狀。0.3 秒的彈簧會讓按鍵浮起的樣子留在畫面上。
                UIView.animate(withDuration: 0.08, delay: 0, options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) {
                    self.content.transform = .identity
                }
            }
        }
    }

    /// 連打時只改既有圖層與字色；不重新配置插畫、讀取圖片或要求排版。
    private func updateFoxFeedback() {
        let ink = isPressed ? foxPressedInk : foxNormalInk
        label.textColor = ink.color
        icon.tintColor = ink.color
        if let title = isPressed ? foxPressedTitle : foxNormalTitle { label.attributedText = title }
        if let symbol = isPressed ? foxPressedSymbol : foxNormalSymbol { icon.image = symbol }
        updateVisualOpacity()
    }

    private func updateVisualOpacity() {
        if style.isIllustrated {
            content.alpha = 1
            foxArtwork?.setSurfaceOpacity(style.keyAlpha * visualOpacity, pressed: isPressed)
            label.alpha = visualOpacity
            hintLabel.alpha = visualOpacity
            icon.alpha = visualOpacity
            return
        }
        let native = style.usesNativeGlassKeys
        // 游標模式／照片調整時暫時隱藏材質，只淡化字面，避免整個玻璃父層 alpha < 1。
        content.alpha = native ? 1 : visualOpacity
        nativeGlass?.isHidden = visualOpacity < 1
        label.alpha = native ? visualOpacity : 1
        hintLabel.alpha = native ? visualOpacity : 1
        icon.alpha = native ? visualOpacity : 1
    }

    private func setPaintedLayersHidden(_ hidden: Bool) {
        let layers: [CALayer] = [shadowLayer, glassLayer, bodyLayer, glossLayer, cushionLayer, padShadow,
                                detailLayer, padHi, padLo, linesLayer, rimLayer, edgeLayer, shineClip]
        for layer in layers {
            layer.isHidden = hidden
        }
    }

    private func layoutFoxLetter() {
        guard let artwork = foxArtwork else { return }
        if style.themeLook != nil && !spec.action.isCharacter && spec.action != .space {
            // 設計圖鑑主題的功能鍵：素色方塊，字放中間
            let chipFrame = bounds.insetBy(dx: 2.5 * style.gapScale, dy: 4 * style.gapScale)
            artwork.frame = chipFrame
            artwork.configure(index: illustratedIndex, action: spec.action, personalSpaceArt: hasPersonalSpaceArt)
            label.font = KeyFonts.font(style.fontID, size: min(spec.fontSize * style.fontScale, chipFrame.height * 0.8), weight: .semibold)
            label.frame = chipFrame.insetBy(dx: 2, dy: 0)
            icon.frame = chipFrame
            hintLabel.frame = .zero
            if case .symbol(let name) = spec.face {
                icon.image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: min(18 * style.fontScale, chipFrame.height * 0.6), weight: .semibold))
            }
            return
        }
        let compact = style.isFoxLetter && bounds.height < 40 && !spec.action.isCharacter
        let frame = FoxLetterTheme.frame(in: bounds, gap: style.gapScale, scale: style.shapeScale, compact: compact)
        artwork.frame = frame
        artwork.configure(index: illustratedIndex, action: spec.action, personalSpaceArt: hasPersonalSpaceArt, compact: compact)
        let geometry = FoxLetterTheme.layout(in: artwork.bounds, compact: compact)
        guard !geometry.frame.isEmpty else {
            label.frame = .zero
            hintLabel.frame = .zero
            icon.frame = .zero
            return
        }
        let edge = foxNormalInk.outline != nil || foxPressedInk.outline != nil ? min(0.6, geometry.label.height * 0.05) : 0
        // 造型放大時字還是留在按鍵裡
        var textRect = geometry.label.offsetBy(dx: frame.minX, dy: frame.minY).insetBy(dx: edge, dy: edge).intersection(bounds)
        // 插畫裡放字的框比較小：字放大時框跟著撐開（中心不動、不超出按鍵），「字的大小」才調得動
        let wanted = KeyFonts.font(style.fontID, size: min(spec.fontSize * style.fontScale, bounds.height * 0.75), weight: .bold)
        if bounds.width <= bounds.height * 1.35 {
            let w = max(textRect.width, bounds.width - 2), h = max(textRect.height, wanted.lineHeight)
            textRect = CGRect(x: textRect.midX - w / 2, y: textRect.midY - h / 2, width: w, height: h).intersection(bounds)
        }
        label.font = wanted.withSize(wanted.pointSize * min(1, textRect.height / wanted.lineHeight))
        label.frame = textRect
        icon.frame = textRect
        if case .symbol(let name) = spec.face {
            if let image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(
                pointSize: min(18 * style.fontScale, textRect.height * 0.9), weight: .semibold)) {
                foxNormalSymbol = FoxLetterTheme.outlinedSymbol(image, ink: foxNormalInk)
                foxPressedSymbol = FoxLetterTheme.outlinedSymbol(image, ink: foxPressedInk)
                icon.image = isPressed ? foxPressedSymbol : foxNormalSymbol
            }
        }
        hintLabel.frame = geometry.hint.offsetBy(dx: frame.minX, dy: frame.minY)
        let hintFont = UIFont.rounded(min(9 * style.fontScale, geometry.hint.height), .medium)
        hintLabel.font = hintFont.withSize(hintFont.pointSize * min(1, geometry.hint.height / hintFont.lineHeight))
        // 自選空白鍵圖片沿用原圖比例，不與主題配件重疊。
        if hasPersonalSpaceArt { icon.contentMode = .scaleAspectFit }
    }
}

/// 一整片按鍵：處理多指連打、滑動修正、刪除鍵連續刪、空白鍵拖曳移動游標
final class KeyboardGridView: UIView {
    var onKey: ((KeySpec) -> Void)?
    var onGlobe: ((UIView, UIEvent?) -> Void)?
    var onCursorMove: ((Int) -> Void)?
    /// 按住空白鍵上下滑：游標換到上一行（-1）或下一行（1）
    var onCursorLine: ((Int) -> Void)?
    /// 開始／結束用空白鍵移動游標（整片鍵盤變淡，看得出來現在是觸控板）
    var onCursorMode: ((Bool) -> Void)?

    var previewOpacity: CGFloat = 1 {
        didSet { updateKeyOpacity() }
    }
    private var cursorModeActive = false

    private func updateKeyOpacity() {
        let opacity = previewOpacity * (cursorModeActive ? 0.45 : 1)
        keys.forEach { $0.visualOpacity = opacity }
    }

    private func updateCursorLook() {
        let on = tracks.values.contains { $0.cursorMode }
        if cursorModeActive != on {
            cursorModeActive = on
            updateKeyOpacity()
            onCursorMode?(on)
        }
    }
    /// 手指按下去的那一刻（震動、按鍵聲）
    var onPress: (() -> Void)?
    /// 英文滑行輸入：手指滑過三個以上字母鍵才放開時，把畫的線交出去
    var glideEnabled = false
    var onGlide: (([CGPoint], [Character: CGPoint], CGFloat) -> Void)?
    private let trail = CAShapeLayer()
    var style: KeyboardStyle {
        didSet { keys.forEach { $0.style = style } }
    }

    private(set) var keys: [KeyButton] = []

    /// 液態玻璃：照片或位置變了，每顆鍵重新對準後面那一塊
    func refreshGlass() {
        for k in keys { k.refreshGlassIfNeeded() }
    }
    private var layout = KeyboardLayout(rows: [], columns: 10)
    private var tracks: [UITouch: Track] = [:]
    private var repeatTimer: Timer?

    private struct Track {
        var key: KeyButton
        let action: KeyAction   // 按下時的功能（版面中途換掉也照這個處理）
        var fired = false
        var origin: CGPoint
        var cursorX: CGFloat = 0
        var cursorY: CGFloat = 0
        var cursorMode = false
        var points: [CGPoint] = []   // 滑行輸入：手指經過的點
        var visited = 1              // 經過幾個不同的鍵
        var gliding = false
    }

    private func isLetter(_ k: KeyButton) -> Bool {
        guard case .text = k.spec.action, case .text(let s) = k.spec.face, s.count == 1,
              let c = s.lowercased().first else { return false }
        return ("a"..."z").contains(c)
    }

    /// 每個字母鍵的中心（滑行輸入用）
    private func letterCenters() -> [Character: CGPoint] {
        var map: [Character: CGPoint] = [:]
        for k in keys where isLetter(k) {
            if case .text(let s) = k.spec.face, let c = s.lowercased().first { map[c] = k.center }
        }
        return map
    }

    private func drawTrail() {
        let gliding = tracks.values.first { $0.gliding }
        guard let pts = gliding?.points.suffix(40), pts.count > 1 else {
            trail.path = nil
            return
        }
        let path = UIBezierPath()
        path.move(to: pts.first!)
        for p in pts.dropFirst() { path.addLine(to: p) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trail.strokeColor = style.theme.accent.withAlphaComponent(0.55).cgColor
        trail.path = path.cgPath
        CATransaction.commit()
    }

    init(style: KeyboardStyle) {
        self.style = style
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        trail.fillColor = nil
        trail.lineWidth = 5
        trail.lineCap = .round
        trail.lineJoin = .round
        trail.zPosition = 10
        layer.addSublayer(trail)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // 按鍵物件會重用，所以換版面時手指還按著也不會出錯
    func setLayout(_ newLayout: KeyboardLayout) {
        closePopup(commit: false)
        layout = newLayout
        let specs = newLayout.rows.flatMap { $0 }
        while keys.count > specs.count {
            keys.removeLast().removeFromSuperview()
        }
        for (i, spec) in specs.enumerated() {
            if i < keys.count {
                keys[i].spec = spec
            } else {
                let key = KeyButton(spec: spec, style: style)
                addSubview(key)
                keys.append(key)
            }
            keys[i].illustratedIndex = i
        }
        updateKeyOpacity()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !layout.rows.isEmpty else { return }
        let padX: CGFloat = 2, padY: CGFloat = 3
        let rowH = (bounds.height - padY * 2) / CGFloat(layout.rows.count)
        let unit = (bounds.width - padX * 2) / layout.columns
        var index = 0
        for (r, row) in layout.rows.enumerated() {
            let fixed = row.reduce(CGFloat(0)) { $0 + max($1.width, 0) }
            let flexCount = row.filter { $0.width == 0 }.count
            let flexW = flexCount > 0 ? max(1, (layout.columns - fixed) / CGFloat(flexCount)) : 0
            let total = fixed + flexW * CGFloat(flexCount)
            var x = padX + max(0, layout.columns - total) * unit / 2
            let y = padY + rowH * CGFloat(r)
            for spec in row {
                guard index < keys.count else { return }
                let w = (spec.width > 0 ? spec.width : flexW) * unit
                keys[index].frame = CGRect(x: x, y: y, width: w, height: rowH)
                x += w
                index += 1
            }
        }
    }

    // MARK: 觸控

    private func key(at p: CGPoint) -> KeyButton? {
        if let k = keys.first(where: { $0.frame.contains(p) }) { return k }
        return keys.min { distance($0.frame, p) < distance($1.frame, p) }
    }

    private func distance(_ r: CGRect, _ p: CGPoint) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return dx * dx + dy * dy
    }

    /// 按鍵特效：從按鍵往上飄、慢慢變透明的小圖案
    private func spawnEffect(from key: KeyButton) {
        let glyphs = (KeyEffect(rawValue: style.keyEffect) ?? .none).glyphs
        guard !glyphs.isEmpty, !UIAccessibility.isReduceMotionEnabled else { return }
        for i in 0..<3 {
            let l = UILabel()
            l.text = glyphs.randomElement()
            l.font = .systemFont(ofSize: CGFloat.random(in: 15...24))
            l.textColor = i == 0 ? style.theme.accent : style.theme.keyText
            l.isUserInteractionEnabled = false
            l.sizeToFit()
            l.center = key.center
            addSubview(l)
            let dx = CGFloat.random(in: -30...30)
            let dy = CGFloat.random(in: -75 ... -45)
            let turn = CGFloat.random(in: -0.6...0.6)
            // 飄久一點（0.8 秒），前半段清楚看得到，後半段才慢慢變透明
            UIView.animate(withDuration: 0.8, delay: 0, options: [.curveEaseOut, .allowUserInteraction], animations: {
                l.center = CGPoint(x: l.center.x + dx, y: l.center.y + dy)
                l.transform = CGAffineTransform(scaleX: 1.35, y: 1.35).rotated(by: turn)
            }, completion: { _ in l.removeFromSuperview() })
            UIView.animate(withDuration: 0.4, delay: 0.4, options: [.curveEaseIn, .allowUserInteraction], animations: {
                l.alpha = 0
            })
        }
    }

    /// 長按有小字的鍵：打出右上角那個字（數字、字母、句號）
    private func startHint(_ touch: UITouch, _ key: KeyButton) {
        let hint = key.spec.hint
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self, weak touch, weak key] in
            guard let self = self, let touch = touch, let key = key, var track = self.tracks[touch],
                  !track.fired, !track.cursorMode, !track.gliding, track.key === key else { return }
            track.fired = true
            self.tracks[touch] = track
            key.isPressed = false
            if !key.spec.popup.isEmpty {
                self.showPopup(touch, key)
            } else {
                self.onKey?(KeySpec(face: .text(hint), action: .text(hint)))
            }
        }
    }

    // MARK: 按住跳出的標點清單

    private final class Popup {
        let touch: UITouch
        let view: UIView
        let items: [String]
        var cells: [UILabel] = []
        var selected = -1
        init(touch: UITouch, view: UIView, items: [String]) { self.touch = touch; self.view = view; self.items = items }
    }
    private var popup: Popup?

    private func showPopup(_ touch: UITouch, _ key: KeyButton) {
        closePopup(commit: false)
        let items = key.spec.popup
        let perRow = min(items.count, 7)
        let rowCount = (items.count + perRow - 1) / perRow
        let cw = max(32, min(44, (bounds.width - 12) / CGFloat(perRow)))
        let ch = max(36, min(46, key.bounds.height * 0.9))
        let w = cw * CGFloat(perRow) + 8, h = ch * CGFloat(rowCount) + 8
        let x = min(max(2, key.frame.midX - w / 2), bounds.width - w - 2)
        let y = max(0, key.frame.minY - h - 4)
        let v = UIView(frame: CGRect(x: x, y: y, width: w, height: h))
        v.backgroundColor = UIColor(white: 0.17, alpha: 0.97)
        v.layer.cornerRadius = 12
        v.isUserInteractionEnabled = false
        let p = Popup(touch: touch, view: v, items: items)
        for (i, s) in items.enumerated() {
            let l = UILabel(frame: CGRect(x: 4 + CGFloat(i % perRow) * cw, y: 4 + CGFloat(i / perRow) * ch, width: cw, height: ch))
            l.text = s
            l.textAlignment = .center
            l.textColor = .white
            l.font = .systemFont(ofSize: 20, weight: .medium)
            l.layer.cornerRadius = 8
            l.clipsToBounds = true
            v.addSubview(l)
            p.cells.append(l)
        }
        addSubview(v)
        popup = p
        onPress?()
        selectPopup(at: touch.location(in: self))
    }

    /// 手指在哪一格就選哪一格；離清單太遠就不選（放開等於取消）
    private func selectPopup(at point: CGPoint) {
        guard let p = popup else { return }
        let local = p.view.convert(point, from: self)
        var best = -1
        if p.view.bounds.insetBy(dx: -24, dy: -60).contains(local) {
            var bestD = CGFloat.greatestFiniteMagnitude
            for (i, c) in p.cells.enumerated() {
                let d = hypot(c.center.x - local.x, c.center.y - local.y)
                if d < bestD { bestD = d; best = i }
            }
        }
        guard best != p.selected else { return }
        p.selected = best
        for (i, c) in p.cells.enumerated() {
            c.backgroundColor = i == best ? style.theme.accent : .clear
            c.textColor = i == best ? style.theme.accentText : .white
        }
        if best >= 0 { onPress?() }
    }

    private func closePopup(commit: Bool) {
        guard let p = popup else { return }
        popup = nil
        p.view.removeFromSuperview()
        if commit, p.items.indices.contains(p.selected) {
            let s = p.items[p.selected]
            onKey?(KeySpec(face: .text(s), action: .text(s)))
        }
    }

    private func fire(_ key: KeyButton) {
        onKey?(key.spec)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // 外層如果是可以滑的畫面，預設會把點擊延遲大約 300ms。鍵盤不能等。
        var ancestor: UIView? = superview
        while let view = ancestor {
            if let scroll = view as? UIScrollView {
                scroll.delaysContentTouches = false
                scroll.canCancelContentTouches = true
            }
            ancestor = view.superview
        }
    }

    private func touchOrder(_ a: UITouch, _ b: UITouch) -> Bool {
        a.timestamp < b.timestamp
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // 先把這次按下的鍵亮起來，再處理上一拍還沒放開的字。選字不能擋住按鍵變色。
        var fresh: [(UITouch, KeyButton)] = []
        for touch in touches.sorted(by: touchOrder) {
            let p = touch.location(in: self)
            guard let key = key(at: p) else { continue }
            key.isPressed = true
            fresh.append((touch, key))
        }
        let pending = tracks.keys.filter { !touches.contains($0) }.sorted(by: touchOrder)
        for other in pending {
            guard var track = tracks[other], !track.fired, !track.cursorMode, !track.gliding,
                  track.key.spec.action.isCharacter || track.key.spec.action == .space else { continue }
            track.fired = true
            track.key.isPressed = false
            tracks[other] = track
            fire(track.key)
        }
        for (touch, key) in fresh {
            onPress?()
            let p = touch.location(in: self)
            var track = Track(key: key, action: key.spec.action, origin: p)
            if glideEnabled && isLetter(key) { track.points.append(p) }
            spawnEffect(from: key)
            tracks[touch] = track
            if !key.spec.hint.isEmpty || !key.spec.popup.isEmpty { startHint(touch, key) }
            switch key.spec.action {
            case .backspace:
                track.fired = true
                tracks[touch] = track
                fire(key)
                startRepeat(key)
            case .shift:
                track.fired = true
                tracks[touch] = track
                fire(key)
            case .globe:
                onGlobe?(self, event)
            default:
                break
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if let p = popup, p.touch === touch {
                selectPopup(at: touch.location(in: self))
                continue
            }
            guard var track = tracks[touch], !track.fired else { continue }
            let p = touch.location(in: self)
            var entered = false
            if track.key.spec.action == .space {
                if !track.cursorMode && (abs(p.x - track.origin.x) > 16 || abs(p.y - track.origin.y) > 18) {
                    track.cursorMode = true
                    track.cursorX = p.x
                    // 上下從按下去的地方算起：空白鍵在最下面，往下能滑的距離很短
                    track.cursorY = track.origin.y
                    entered = true
                }
                if track.cursorMode {
                    // 左右：每 10 點一個字，跟手、不加速，慢慢滑可以停在任何兩個字中間
                    let steps = Int((p.x - track.cursorX) / 10)
                    if steps != 0 {
                        onCursorMove?(steps)
                        track.cursorX += CGFloat(steps) * 10
                    }
                    // 上下：往上 24 點換一行；往下 16 點（空白鍵在最下面，往下能滑的地方少）
                    let dy = p.y - track.cursorY
                    let step: CGFloat = dy > 0 ? 16 : 24
                    if abs(dy) >= step {
                        onCursorLine?(dy > 0 ? 1 : -1)
                        track.cursorY += dy > 0 ? step : -step
                        // 換行時手指左右晃一點不算，游標留在原本的直排位置
                        track.cursorX = p.x - max(-4, min(4, (p.x - track.cursorX).truncatingRemainder(dividingBy: 10)))
                    }
                }
            } else if track.key.spec.action.isCharacter {
                if !track.points.isEmpty { track.points.append(p) }
                if let k = key(at: p), k !== track.key, k.spec.action.isCharacter {
                    track.key.isPressed = false
                    k.isPressed = true
                    track.key = k
                    if !track.points.isEmpty {
                        track.visited += 1
                        if track.visited >= 3 { track.gliding = true }
                    }
                }
            }
            tracks[touch] = track
            if track.gliding { drawTrail() }
            if entered { updateCursorLook() }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches.sorted(by: touchOrder) {
            if let p = popup, p.touch === touch {
                if let t = tracks.removeValue(forKey: touch) { t.key.isPressed = false }
                closePopup(commit: true)
                continue
            }
            guard let track = tracks.removeValue(forKey: touch) else { continue }
            track.key.isPressed = false
            switch track.action {
            case .backspace:
                stopRepeat()
            case .globe:
                onGlobe?(self, event)
            default:
                if track.gliding {
                    let kw = keys.first(where: isLetter)?.bounds.width ?? 30
                    onGlide?(track.points + [touch.location(in: self)], letterCenters(), kw)
                    drawTrail()
                } else if !track.fired && !track.cursorMode {
                    fire(track.key)
                }
            }
        }
        updateCursorLook()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // 系統把觸控取消時仍送出已經按下的字，避免快速打字時整段注音消失。
        if let p = popup, touches.contains(p.touch) { closePopup(commit: false) }
        for touch in touches.sorted(by: touchOrder) {
            guard let track = tracks.removeValue(forKey: touch) else { continue }
            track.key.isPressed = false
            if track.action == .backspace {
                stopRepeat()
                continue
            }
            if !track.fired && !track.cursorMode && !track.gliding && track.action.isCharacter {
                fire(track.key)
            }
        }
        updateCursorLook()
    }

    private func startRepeat(_ key: KeyButton) {
        stopRepeat()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                self?.fire(key)
            }
        }
    }

    private func stopRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }
}

extension UIColor {
    /// 疊一層白色（液態玻璃：顏色淡淡的、亮亮的）；w 是白色的濃度
    func blended(white w: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let outA = a + w * (1 - a)
        guard outA > 0 else { return .clear }
        return UIColor(red: (r * a + w * (1 - a)) / outA, green: (g * a + w * (1 - a)) / outA,
                       blue: (b * a + w * (1 - a)) / outA, alpha: outA)
    }

    /// 調亮：往白色靠 f（0～1）
    func lighter(_ f: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r + (1 - r) * f, green: g + (1 - g) * f, blue: b + (1 - b) * f, alpha: a)
    }

    /// 調暗（立體按鍵的側面）
    func darker(_ f: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r * f, green: g * f, blue: b * f, alpha: a)
    }
}
