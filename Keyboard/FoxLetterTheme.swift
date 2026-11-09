import UIKit

/// iPhone 的角色主題：只提供外觀，按鍵動作、配置和個人設定由既有程式管理。
enum FoxLetterTheme {
    static let id = "fox-letter"

    struct Ink {
        let color: UIColor
        let outline: UIColor?
    }

    static func textColor(fur: UIColor, preferred: UIColor, opacity: CGFloat, theme: KeyboardTheme) -> UIColor {
        ink(fur: fur, preferred: preferred, opacity: opacity, theme: theme).color
    }

    static func ink(fur: UIColor, preferred: UIColor, opacity: CGFloat, theme: KeyboardTheme) -> Ink {
        func rgb(_ color: UIColor) -> [CGFloat] {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            return [r, g, b]
        }
        func luminance(_ values: [CGFloat]) -> CGFloat {
            let c = values.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return c[0] * 0.2126 + c[1] * 0.7152 + c[2] * 0.0722
        }
        let alpha = min(1, max(0, opacity)), surface = rgb(fur)
        let backgrounds = [theme.backgroundTop, theme.backgroundBottom].map { background -> CGFloat in
            let b = rgb(background)
            return luminance(zip(surface, b).map { $0.0 * alpha + $0.1 * (1 - alpha) })
        }
        let candidates = [preferred, UIColor(hex: 0xFFF9EF), UIColor.black]
        func score(_ color: UIColor) -> CGFloat {
            let value = luminance(rgb(color))
            return backgrounds.map { (max(value, $0) + 0.05) / (min(value, $0) + 0.05) }.min() ?? 1
        }
        if score(preferred) >= 4.5 { return Ink(color: preferred, outline: nil) }
        let color = candidates.max { score($0) < score($1) } ?? preferred
        // 漸層在中間亮度時，黑／白字都可能無法同時與上下底色達標。
        // 此時加相反明暗的細邊，保留表面透明度與角色配色。
        return Ink(color: color, outline: score(color) >= 4.5 ? nil :
            (luminance(rgb(color)) > 0.5 ? .black : .white))
    }

    static func title(_ text: String, ink: Ink) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: ink.color]
        if let outline = ink.outline {
            attributes[.strokeColor] = outline
            attributes[.strokeWidth] = -3 // 字體大小的百分比；同時填色與描邊。
        }
        return NSAttributedString(string: text, attributes: attributes)
    }

    @MainActor
    static func paperInk(_ ink: Ink) -> Ink {
        guard ink.outline == nil, FoxLetterWatercolor.keycaps != nil else { return ink }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        ink.color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return red > 0.78 ? Ink(color: ink.color, outline: UIColor(hex: 0x68472B).withAlphaComponent(0.65)) : ink
    }

    /// 只有需要細邊的 SF Symbol 才建立小圖；在排版時預備兩個狀態，連打不產圖。
    static func outlinedSymbol(_ image: UIImage, ink: Ink) -> UIImage {
        guard let outline = ink.outline else { return image }
        let edge = max(0.4, image.size.height * 0.03)
        let size = CGSize(width: image.size.width + edge * 2, height: image.size.height + edge * 2)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let border = image.withTintColor(outline, renderingMode: .alwaysOriginal)
            for x in [-edge, CGFloat.zero, edge] {
                for y in [-edge, CGFloat.zero, edge] where x != 0 || y != 0 {
                    border.draw(at: CGPoint(x: edge + x, y: edge + y))
                }
            }
            image.withTintColor(ink.color, renderingMode: .alwaysOriginal).draw(at: CGPoint(x: edge, y: edge))
        }.withRenderingMode(.alwaysOriginal)
    }

    static func variant(at index: Int, action: KeyAction) -> Int {
        switch action {
        case .returnKey: return 2
        case .space: return 0
        default: return max(0, index) % FoxLetterArtwork.palettes.count
        }
    }

    /// 保留原設定物件；離開角色主題即可恢復之前的造型和質感。
    static func resolved(_ style: KeyboardStyle) -> KeyboardStyle {
        if let look = ThemeLook.named(style.theme.id) {
            var result = style
            result.shape = look.shape
            result.finish = look.finish
            return result
        }
        guard style.theme.id == id else { return style }
        var result = style
        result.shape = .rounded
        result.finish = .flat
        return result
    }

    static func frame(in bounds: CGRect, gap: CGFloat, scale: CGFloat, compact: Bool = false) -> CGRect {
        guard bounds.width > 6, bounds.height > 6 else { return .zero }
        let gap = min(1.8, max(0.3, gap))
        let baseW = max(5, bounds.width - 2 * gap), baseH = max(5, bounds.height - 4 * gap)
        var width: CGFloat, height: CGFloat
        if bounds.width > bounds.height * 1.35 {
            // 寬鍵的中間會延展，不會變形；不超出按鍵，才不會蓋到旁邊
            let factor = min(1.12, max(0.8, scale / 1.15))
            width = min(bounds.width - 1.4, baseW * factor)
            height = min(bounds.height - 1.4, baseH * factor)
        } else {
            // 一般的鍵：照原圖的比例（圓的就是圓的），按鍵再瘦也不拉高；「造型大小」整顆等比放大縮小，可以超出按鍵一點
            let part: CGFloat = compact ? 0.78 : 1
            width = baseW
            height = min(baseH, width * part)
            if width > height / part { width = height / part }
            let factor = min(1.4, max(0.75, scale / 1.15))
            width *= factor
            height *= factor
        }
        return CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
    }

    static func layout(in bounds: CGRect, compact: Bool) -> FoxLetterPrototype.Layout {
        let layout = FoxLetterPrototype.layout(in: bounds)
        guard compact, !layout.frame.isEmpty else { return layout }
        let f = layout.frame
        // 手寫側欄等矮功能鍵讓出五官區，優先保持文字與圖示大小。
        return FoxLetterPrototype.Layout(frame: f, face: .zero,
            label: CGRect(x: f.minX + f.width * 0.16, y: f.minY + f.height * 0.24,
                          width: f.width * 0.68, height: f.height * 0.64),
            hint: layout.hint, ends: layout.ends)
    }

    static func layers(accessory: String, compact: Bool) -> [FoxLetterPrototype.ArtLayer] {
        compact ? Array(FoxLetterPrototype.layers.prefix(2)) : Array(FoxLetterPrototype.layers.dropLast())
            + (FoxLetterArtwork.accessories[accessory] ?? [])
            + Array(FoxLetterPrototype.layers.suffix(1))
    }
}

extension KeyboardStyle {
    var isFoxLetter: Bool { theme.id == FoxLetterTheme.id }
}

/// 同尺寸、同配件的按鍵共用不可變路徑。容量限制避免持續調整尺寸累積記憶體；
/// NSCache 亦可在記憶體壓力時釋放，已顯示的圖層仍持有自己的路徑。
@MainActor
enum FoxLetterPathCache {
    final class Paths {
        let values: [CGPath]
        init(_ values: [CGPath]) { self.values = values }
    }

    private final class Key: NSObject {
        let bounds: CGRect
        let compact: Bool
        let accessory: String

        init(bounds: CGRect, compact: Bool, accessory: String) {
            self.bounds = bounds
            self.compact = compact
            self.accessory = compact ? "" : accessory
        }

        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(bounds.origin.x)
            hasher.combine(bounds.origin.y)
            hasher.combine(bounds.width)
            hasher.combine(bounds.height)
            hasher.combine(compact)
            hasher.combine(accessory)
            return hasher.finalize()
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? Key else { return false }
            return bounds == other.bounds && compact == other.compact && accessory == other.accessory
        }
    }

    private static let cache: NSCache<Key, Paths> = {
        let cache = NSCache<Key, Paths>()
        cache.countLimit = 64
        return cache
    }()

    static func paths(in bounds: CGRect, compact: Bool, accessory: String) -> Paths {
        let key = Key(bounds: bounds, compact: compact, accessory: accessory)
        if let cached = cache.object(forKey: key) { return cached }
        let layout = FoxLetterTheme.layout(in: bounds, compact: compact)
        let paths = Paths(FoxLetterTheme.layers(accessory: accessory, compact: compact).map { definition in
            let path = KeyShapeArt.build(definition.ops,
                in: definition.space == .head ? layout.frame : layout.face,
                ends: definition.space == .head ? layout.ends : nil)
            // build 回傳可變路徑；先存不可變副本，避免各 CAShapeLayer 再各複製一份。
            return path.copy() ?? path
        })
        cache.setObject(paths, forKey: key)
        return paths
    }
}

/// 多色向量圖層重用。壓下只改插畫透明度，不重建路徑，字面由 KeyButton 繪製。
final class FoxLetterArtworkView: UIView {
    private let drawing = CALayer()
    private let paper = FoxLetterWatercolorKeyView(frame: .zero)
    private var artwork: [CAShapeLayer] = []
    private var definitions: [FoxLetterPrototype.ArtLayer] = []
    private var paletteIndex = -1
    private var decoration = ""
    private var isCompact = false
    private var geometryBounds = CGRect.null
    private(set) var textColor = FoxLetterPrototype.textColor
    private(set) var furColor = FoxLetterPrototype.layers[0].fill

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isUserInteractionEnabled = false
        layer.addSublayer(drawing)
        addSubview(paper)
        configure(index: 0, action: .text(""), personalSpaceArt: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 設計圖鑑做的主題：用它的圖集；nil 是小狐狸
    var look: ThemeLook?

    func configure(index: Int, action: KeyAction, personalSpaceArt: Bool, compact requestedCompact: Bool? = nil) {
        if let look = look {
            drawing.isHidden = true
            paper.isHidden = false
            textColor = action == .space ? look.spaceInk : (action.isCharacter ? look.ink : look.theme.specialText)
            furColor = look.theme.key
            paper.configure(look: look, index: index, action: action)
            return
        }
        let compact = requestedCompact ?? isCompact
        let position = index
        let index = FoxLetterTheme.variant(at: index, action: action)
        let palette = FoxLetterArtwork.palettes[index]
        let accessory: String
        switch action {
        case .space: accessory = personalSpaceArt ? "" : "letter"
        case .returnKey: accessory = "leaf"
        default: accessory = palette.accessory
        }
        textColor = palette.text
        furColor = palette.fur
        if FoxLetterWatercolor.keycaps != nil {
            drawing.isHidden = true
            paper.isHidden = false
            isCompact = compact
            paper.configure(index: position, action: action, personalSpaceArt: personalSpaceArt, compact: compact)
            return
        }
        paper.isHidden = true
        guard index != paletteIndex || accessory != decoration || compact != isCompact else { return }
        let geometryChanged = definitions.isEmpty || accessory != decoration || compact != isCompact
        paletteIndex = index
        decoration = accessory
        isCompact = compact
        if geometryChanged { definitions = FoxLetterTheme.layers(accessory: accessory, compact: compact) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        while artwork.count < definitions.count {
            let shape = CAShapeLayer()
            shape.lineJoin = .round
            shape.lineCap = .round
            drawing.addSublayer(shape)
            artwork.append(shape)
        }
        for (i, shape) in artwork.enumerated() {
            shape.isHidden = i >= definitions.count
            guard i < definitions.count else { continue }
            let definition = definitions[i]
            shape.fillColor = (i == 0 ? palette.fur : (i == 2 ? palette.cheek : definition.fill)).cgColor
            shape.strokeColor = definition.stroke?.cgColor
            shape.lineWidth = definition.lineWidth
        }
        CATransaction.commit()
        if geometryChanged {
            geometryBounds = .null
            setNeedsLayout()
        }
    }

    func setSurfaceOpacity(_ opacity: CGFloat, pressed: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        drawing.opacity = Float(min(1, max(0, opacity)) * (pressed ? 0.82 : 1))
        paper.layer.opacity = drawing.opacity
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !paper.isHidden {
            paper.frame = bounds
            paper.layoutIfNeeded()
            return
        }
        guard geometryBounds != bounds else { return }
        geometryBounds = bounds
        let layout = FoxLetterTheme.layout(in: bounds, compact: isCompact)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        drawing.frame = bounds
        guard !layout.frame.isEmpty else {
            artwork.forEach { $0.isHidden = true }
            CATransaction.commit()
            return
        }
        let paths = FoxLetterPathCache.paths(in: bounds, compact: isCompact, accessory: decoration)
        for i in definitions.indices {
            let shape = artwork[i]
            shape.isHidden = false
            shape.frame = bounds
            shape.path = paths.values[i]
        }
        CATransaction.commit()
    }
}
