import UIKit
import CoreText
import ImageIO

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension UIFont {
    /// 圓體，看起來比較可愛
    static func rounded(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let d = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: d, size: size)
    }
}

struct KeyboardTheme {
    let id: String
    let name: String
    let backgroundTop: UIColor
    let backgroundBottom: UIColor
    let key: UIColor
    let keyText: UIColor
    let specialKey: UIColor
    let specialText: UIColor
    let accent: UIColor
    let accentText: UIColor
    let shadow: UIColor
    let decoration: String
    let isDark: Bool

    static let all: [KeyboardTheme] = [
        KeyboardTheme(id: "strawberry", name: "草莓牛奶",
                      backgroundTop: UIColor(hex: 0xFFE4EC), backgroundBottom: UIColor(hex: 0xFFD0DE),
                      key: .white, keyText: UIColor(hex: 0x8A4B5C),
                      specialKey: UIColor(hex: 0xFFC2D4), specialText: UIColor(hex: 0x7A3045),
                      accent: UIColor(hex: 0xFF7FA6), accentText: .white,
                      shadow: UIColor(hex: 0xE8A2B6), decoration: "🍓", isDark: false),
        KeyboardTheme(id: "mint", name: "薄荷蘇打",
                      backgroundTop: UIColor(hex: 0xDDF7EF), backgroundBottom: UIColor(hex: 0xC5EFE3),
                      key: .white, keyText: UIColor(hex: 0x2F6B5E),
                      specialKey: UIColor(hex: 0xA7E3D2), specialText: UIColor(hex: 0x2F6B5E),
                      accent: UIColor(hex: 0x3CC5A0), accentText: .white,
                      shadow: UIColor(hex: 0x9FD8C7), decoration: "🌿", isDark: false),
        KeyboardTheme(id: "milktea", name: "奶茶布丁",
                      backgroundTop: UIColor(hex: 0xF3E6D6), backgroundBottom: UIColor(hex: 0xE9D5BD),
                      key: UIColor(hex: 0xFFF8EE), keyText: UIColor(hex: 0x6B4A33),
                      specialKey: UIColor(hex: 0xD9B994), specialText: UIColor(hex: 0x5A3B24),
                      accent: UIColor(hex: 0xB9835A), accentText: .white,
                      shadow: UIColor(hex: 0xCBAE8C), decoration: "🍮", isDark: false),
        KeyboardTheme(id: "lavender", name: "薰衣草",
                      backgroundTop: UIColor(hex: 0xECE4FF), backgroundBottom: UIColor(hex: 0xDCD0FF),
                      key: .white, keyText: UIColor(hex: 0x5B4B8A),
                      specialKey: UIColor(hex: 0xC7B8F5), specialText: UIColor(hex: 0x4A3B78),
                      accent: UIColor(hex: 0x8D74E8), accentText: .white,
                      shadow: UIColor(hex: 0xB9A9EC), decoration: "💜", isDark: false),
        KeyboardTheme(id: "lemon", name: "檸檬小雞",
                      backgroundTop: UIColor(hex: 0xFFF6CC), backgroundBottom: UIColor(hex: 0xFFEC9E),
                      key: .white, keyText: UIColor(hex: 0x7A5B12),
                      specialKey: UIColor(hex: 0xFFDD6B), specialText: UIColor(hex: 0x6B4E0A),
                      accent: UIColor(hex: 0xFFA928), accentText: .white,
                      shadow: UIColor(hex: 0xE9CB6A), decoration: "🐥", isDark: false),
        KeyboardTheme(id: "night", name: "星空夜",
                      backgroundTop: UIColor(hex: 0x1E2245), backgroundBottom: UIColor(hex: 0x2B2F63),
                      key: UIColor(hex: 0x3A3F7A), keyText: UIColor(hex: 0xF3F0FF),
                      specialKey: UIColor(hex: 0x2A2E5E), specialText: UIColor(hex: 0xCFCBFF),
                      accent: UIColor(hex: 0xFFD65C), accentText: UIColor(hex: 0x2B2F63),
                      shadow: UIColor(hex: 0x14173A), decoration: "⭐", isDark: true),
        KeyboardTheme(id: "sakura", name: "櫻花",
                      backgroundTop: UIColor(hex: 0xFDE8EF), backgroundBottom: UIColor(hex: 0xF9D5E2),
                      key: .white, keyText: UIColor(hex: 0x9B4D6B),
                      specialKey: UIColor(hex: 0xF6C1D4), specialText: UIColor(hex: 0x8A3A5A),
                      accent: UIColor(hex: 0xF08BB0), accentText: .white,
                      shadow: UIColor(hex: 0xE8B0C4), decoration: "🌸", isDark: false),
        KeyboardTheme(id: "peach", name: "蜜桃",
                      backgroundTop: UIColor(hex: 0xFFE9DC), backgroundBottom: UIColor(hex: 0xFFD8C4),
                      key: .white, keyText: UIColor(hex: 0x8A5040),
                      specialKey: UIColor(hex: 0xFFC8AD), specialText: UIColor(hex: 0x7A4030),
                      accent: UIColor(hex: 0xFF9A76), accentText: .white,
                      shadow: UIColor(hex: 0xECB59C), decoration: "🍑", isDark: false),
        KeyboardTheme(id: "cream", name: "奶油",
                      backgroundTop: UIColor(hex: 0xFFFAF0), backgroundBottom: UIColor(hex: 0xFFF1D9),
                      key: .white, keyText: UIColor(hex: 0x7A6340),
                      specialKey: UIColor(hex: 0xF7E2B8), specialText: UIColor(hex: 0x6B5430),
                      accent: UIColor(hex: 0xF2B94B), accentText: .white,
                      shadow: UIColor(hex: 0xE6D2A6), decoration: "🧈", isDark: false),
        KeyboardTheme(id: "matcha", name: "抹茶",
                      backgroundTop: UIColor(hex: 0xE9F3DC), backgroundBottom: UIColor(hex: 0xD8EAC4),
                      key: UIColor(hex: 0xFFFEF8), keyText: UIColor(hex: 0x4A6332),
                      specialKey: UIColor(hex: 0xC6DFA9), specialText: UIColor(hex: 0x3E5629),
                      accent: UIColor(hex: 0x8CBF5A), accentText: .white,
                      shadow: UIColor(hex: 0xB4CF98), decoration: "🍵", isDark: false),
        KeyboardTheme(id: "sky", name: "天空",
                      backgroundTop: UIColor(hex: 0xE2F1FF), backgroundBottom: UIColor(hex: 0xCFE6FF),
                      key: .white, keyText: UIColor(hex: 0x3D5F8A),
                      specialKey: UIColor(hex: 0xB9D8FB), specialText: UIColor(hex: 0x2F4F78),
                      accent: UIColor(hex: 0x5AA9F0), accentText: .white,
                      shadow: UIColor(hex: 0xA9C8EA), decoration: "☁️", isDark: false),
        KeyboardTheme(id: "ocean", name: "海洋",
                      backgroundTop: UIColor(hex: 0xD8F0FB), backgroundBottom: UIColor(hex: 0xBFE4F6),
                      key: UIColor(hex: 0xF7FDFF), keyText: UIColor(hex: 0x2D5F7A),
                      specialKey: UIColor(hex: 0xA6D8EF), specialText: UIColor(hex: 0x245570),
                      accent: UIColor(hex: 0x3FB2D8), accentText: .white,
                      shadow: UIColor(hex: 0x96C8DE), decoration: "🐟", isDark: false),
        KeyboardTheme(id: "grape", name: "葡萄",
                      backgroundTop: UIColor(hex: 0xEFE2F7), backgroundBottom: UIColor(hex: 0xE2CDF2),
                      key: .white, keyText: UIColor(hex: 0x6A3F86),
                      specialKey: UIColor(hex: 0xD6B8EC), specialText: UIColor(hex: 0x5A2F78),
                      accent: UIColor(hex: 0xA86AD6), accentText: .white,
                      shadow: UIColor(hex: 0xC8A8E0), decoration: "🍇", isDark: false),
        KeyboardTheme(id: "aurora", name: "夢幻極光",
                      backgroundTop: UIColor(hex: 0xFFE7EF), backgroundBottom: UIColor(hex: 0xE5E0FF),
                      key: .white, keyText: UIColor(hex: 0x5D4F8A),
                      specialKey: UIColor(hex: 0xE3D6FF), specialText: UIColor(hex: 0x4A3B78),
                      accent: UIColor(hex: 0xFF9EC4), accentText: .white,
                      shadow: UIColor(hex: 0xCBBFEB), decoration: "🌈", isDark: false),
        KeyboardTheme(id: "cocoa", name: "可可",
                      backgroundTop: UIColor(hex: 0x3A2A26), backgroundBottom: UIColor(hex: 0x2E211E),
                      key: UIColor(hex: 0x5A443D), keyText: UIColor(hex: 0xF8EBE2),
                      specialKey: UIColor(hex: 0x46342F), specialText: UIColor(hex: 0xE8D5C8),
                      accent: UIColor(hex: 0xF0A77A), accentText: UIColor(hex: 0x3A2A26),
                      shadow: UIColor(hex: 0x1F1513), decoration: "🍫", isDark: true),
        KeyboardTheme(id: "neon", name: "電玩霓虹",
                      backgroundTop: UIColor(hex: 0x1C1640), backgroundBottom: UIColor(hex: 0x251C52),
                      key: UIColor(hex: 0x362A73), keyText: UIColor(hex: 0xF0EAFF),
                      specialKey: UIColor(hex: 0x2A2160), specialText: UIColor(hex: 0xCFC4FF),
                      accent: UIColor(hex: 0xFF7AD9), accentText: UIColor(hex: 0x1C1640),
                      shadow: UIColor(hex: 0x120D2E), decoration: "🎮", isDark: true),
        KeyboardTheme(id: "light", name: "經典淺色",
                      backgroundTop: UIColor(hex: 0xD3D6DC), backgroundBottom: UIColor(hex: 0xCDD0D6),
                      key: .white, keyText: .black,
                      specialKey: UIColor(hex: 0xABB0BA), specialText: .black,
                      accent: UIColor(hex: 0x2F7BF6), accentText: .white,
                      shadow: UIColor(hex: 0x8E9196), decoration: "", isDark: false),
        KeyboardTheme(id: "dark", name: "經典深色",
                      backgroundTop: UIColor(hex: 0x2B2B2D), backgroundBottom: UIColor(hex: 0x232325),
                      key: UIColor(hex: 0x6B6B6E), keyText: .white,
                      specialKey: UIColor(hex: 0x474749), specialText: .white,
                      accent: UIColor(hex: 0x2F7BF6), accentText: .white,
                      shadow: UIColor(hex: 0x111111), decoration: "", isDark: true),
        FoxLetterArtwork.theme,
    ]

    static func named(_ id: String) -> KeyboardTheme {
        if id == "custom" {
            let s = KeyboardSettings.shared
            return custom(hue: s.customHue, saturation: s.customSaturation, dark: s.customDark,
                          hue2: s.customHue2 < 0 ? nil : s.customHue2, saturation2: s.customSaturation2)
        }
        return all.first { $0.id == id } ?? all[0]
    }

    /// 自訂配色用的色票：(色相, 濃淡)
    static let swatches: [(Double, Double)] = [
        (0.95, 0.45), (0.97, 0.65), (0.0, 0.7), (0.03, 0.5), (0.08, 0.7), (0.07, 0.35), (0.13, 0.7),
        (0.12, 0.3), (0.24, 0.55), (0.36, 0.6), (0.42, 0.45), (0.49, 0.6), (0.56, 0.5), (0.61, 0.65),
        (0.65, 0.8), (0.72, 0.38), (0.75, 0.6), (0.83, 0.4), (0.88, 0.6), (0.0, 0.25), (0.6, 0.06),
    ]

    /// 色票上看到的顏色
    static func swatchColor(_ hue: Double, _ saturation: Double) -> UIColor {
        UIColor(hue: CGFloat(hue), saturation: CGFloat(saturation), brightness: 0.95, alpha: 1)
    }

    /// 自訂配色：主色（按鍵的字、背景上半）＋第二色（功能鍵、強調色、背景下半），沒選第二色就全部用主色
    static func custom(hue: Double, saturation: Double, dark: Bool, hue2: Double? = nil, saturation2: Double = 0.55) -> KeyboardTheme {
        let h = CGFloat(hue), s = CGFloat(min(max(saturation, 0.05), 1))
        let h2 = hue2.map { CGFloat($0) } ?? h, s2 = hue2 == nil ? s : CGFloat(min(max(saturation2, 0.05), 1))
        func c(_ sat: CGFloat, _ bri: CGFloat) -> UIColor { UIColor(hue: h, saturation: min(1, sat), brightness: min(1, bri), alpha: 1) }
        func d(_ sat: CGFloat, _ bri: CGFloat) -> UIColor { UIColor(hue: h2, saturation: min(1, sat), brightness: min(1, bri), alpha: 1) }
        if dark {
            return KeyboardTheme(id: "custom", name: "自訂",
                                 backgroundTop: c(s * 0.5, 0.22), backgroundBottom: d(s2 * 0.5, 0.28),
                                 key: c(s * 0.45, 0.40), keyText: c(0.06, 0.98),
                                 specialKey: d(s2 * 0.5, 0.30), specialText: d(0.2, 0.88),
                                 accent: d(s2 * 0.55, 0.95), accentText: d(s2 * 0.5, 0.22),
                                 shadow: c(s * 0.5, 0.12), decoration: "🎨", isDark: true)
        }
        return KeyboardTheme(id: "custom", name: "自訂",
                             backgroundTop: c(s * 0.15, 1), backgroundBottom: d(s2 * 0.25, 0.97),
                             key: .white, keyText: c(s * 0.6 + 0.2, 0.45),
                             specialKey: d(s2 * 0.35, 0.95), specialText: d(s2 * 0.7, 0.38),
                             accent: d(s2 * 0.6, 0.9), accentText: .white,
                             shadow: c(s * 0.4, 0.82), decoration: "🎨", isDark: false)
    }
}

/// 按鍵造型
enum KeyShape: String, CaseIterable {
    case rounded, jelly, catEar, cloud, bunny, puppy, pudding, jellyfish, flame, droplet, duck
    // 下面這些用線條資料畫（tools/key_shapes.txt → KeyShapeArt.swift）
    case catFace, bear, paw, cloudPuff, pixel, pixelHeart, puzzle, book, butterfly, strawberry, flower, moon, star, heart, latte, catLine

    var art: KeyShapeArt? { KeyShapeArt.shapes[rawValue] }

    /// 小裝飾的不透明度（寬鍵左邊的小圖示一定看得到）
    func detailOpacity(in r: CGRect? = nil) -> CGFloat {
        if let a = art { return r.map { isWide($0) } == true ? max(a.detailAlpha, 0.6) : a.detailAlpha }
        return self == .pudding || self == .duck ? 0.85 : 0.4
    }

    var title: String {
        if let a = art { return a.title }
        switch self {
        case .rounded: return "圓角"
        case .jelly: return "果凍"
        case .catEar: return "貓耳"
        case .cloud: return "雲朵"
        case .bunny: return "兔兔"
        case .puppy: return "狗狗"
        case .pudding: return "布丁"
        case .jellyfish: return "水母"
        case .flame: return "火焰"
        case .droplet: return "水滴"
        case .duck: return "鴨鴨"
        default: return ""
        }
    }

    var isSoftShape: Bool {
        switch self {
        case .bunny, .puppy, .pudding, .jellyfish, .flame, .droplet, .duck: return true
        default: return art != nil
        }
    }

    // 會自己拉長的造型（貓咪探頭）寬鍵也畫原本的樣子，不換成膠囊
    private func isWide(_ r: CGRect) -> Bool { isSoftShape && art?.stretch != true && r.width > r.height * 1.65 }

    /// 只畫線的部分（尾巴、鬍鬚）
    func linesPath(in r: CGRect) -> CGPath? { isWide(r) ? nil : art?.linesPath(in: r) }

    private func wideBody(in r: CGRect) -> CGRect { r.insetBy(dx: 0, dy: r.height * 0.08) }

    private func badgeRect(in r: CGRect) -> CGRect {
        let size = r.height * 0.54
        return CGRect(x: r.minX + r.height * 0.17, y: r.midY - size / 2, width: size, height: size)
    }

    private func earSize(_ r: CGRect) -> CGFloat { min(r.width * 0.24, r.height * 0.24, 9) }
    private func bumpSize(_ r: CGRect) -> CGFloat { min(r.height * 0.16, 6) }

    /// 按鍵本體（文字畫在這裡面）
    func bodyRect(in r: CGRect) -> CGRect {
        if isWide(r) {
            return CGRect(x: r.minX + r.height * 0.82, y: r.minY + r.height * 0.15,
                          width: r.width - r.height * 0.96, height: r.height * 0.70)
        }
        if let a = art { return a.bodyRect(in: r) }
        switch self {
        case .catEar:
            let ear = earSize(r) * 0.6
            return CGRect(x: r.minX, y: r.minY + ear, width: r.width, height: r.height - ear)
        case .cloud:
            let b = bumpSize(r)
            return CGRect(x: r.minX, y: r.minY + b, width: r.width, height: r.height - b)
        case .bunny:
            return CGRect(x: r.minX + r.width * 0.08, y: r.minY + r.height * 0.32, width: r.width * 0.84, height: r.height * 0.58)
        case .puppy:
            return CGRect(x: r.minX + r.width * 0.2, y: r.minY + r.height * 0.24, width: r.width * 0.6, height: r.height * 0.64)
        case .pudding:
            return CGRect(x: r.minX + r.width * 0.12, y: r.minY + r.height * 0.32, width: r.width * 0.76, height: r.height * 0.55)
        case .jellyfish:
            return CGRect(x: r.minX + r.width * 0.09, y: r.minY + r.height * 0.19, width: r.width * 0.82, height: r.height * 0.54)
        case .flame:
            return CGRect(x: r.minX + r.width * 0.13, y: r.minY + r.height * 0.35, width: r.width * 0.74, height: r.height * 0.55)
        case .droplet:
            return CGRect(x: r.minX + r.width * 0.13, y: r.minY + r.height * 0.34, width: r.width * 0.74, height: r.height * 0.53)
        case .duck:
            return CGRect(x: r.minX + r.width * 0.14, y: r.minY + r.height * 0.40, width: r.width * 0.70, height: r.height * 0.50)
        default:
            return r
        }
    }

    func detailPath(in r: CGRect) -> CGPath? {
        if isWide(r) { return path(in: badgeRect(in: r)) }
        if let a = art { return a.detailPath(in: r) }
        let p = UIBezierPath()
        switch self {
        case .bunny:
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y)
            }
            p.move(to: point(0.22, 0.11))
            p.addCurve(to: point(0.28, 0.3), controlPoint1: point(0.18, 0.14), controlPoint2: point(0.24, 0.29))
            p.addCurve(to: point(0.22, 0.11), controlPoint1: point(0.32, 0.3), controlPoint2: point(0.27, 0.1))
            p.close()
            p.move(to: point(0.78, 0.11))
            p.addCurve(to: point(0.72, 0.3), controlPoint1: point(0.73, 0.1), controlPoint2: point(0.68, 0.3))
            p.addCurve(to: point(0.78, 0.11), controlPoint1: point(0.76, 0.29), controlPoint2: point(0.82, 0.14))
            p.close()
        case .puppy:
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y)
            }
            p.move(to: point(0.17, 0.27))
            p.addCurve(to: point(0.12, 0.57), controlPoint1: point(0.1, 0.28), controlPoint2: point(0.06, 0.49))
            p.addCurve(to: point(0.22, 0.37), controlPoint1: point(0.17, 0.61), controlPoint2: point(0.21, 0.48))
            p.addQuadCurve(to: point(0.17, 0.27), controlPoint: point(0.23, 0.25))
            p.close()
            p.move(to: point(0.83, 0.27))
            p.addQuadCurve(to: point(0.78, 0.37), controlPoint: point(0.77, 0.25))
            p.addCurve(to: point(0.88, 0.57), controlPoint1: point(0.79, 0.48), controlPoint2: point(0.83, 0.61))
            p.addCurve(to: point(0.83, 0.27), controlPoint1: point(0.94, 0.49), controlPoint2: point(0.9, 0.28))
            p.close()
        case .pudding:
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y)
            }
            p.move(to: point(0.24, 0.14))
            p.addQuadCurve(to: point(0.76, 0.14), controlPoint: point(0.5, 0.08))
            p.addQuadCurve(to: point(0.85, 0.29), controlPoint: point(0.83, 0.16))
            p.addCurve(to: point(0.6, 0.29), controlPoint1: point(0.77, 0.35), controlPoint2: point(0.69, 0.24))
            p.addCurve(to: point(0.15, 0.3), controlPoint1: point(0.43, 0.38), controlPoint2: point(0.34, 0.27))
            p.addQuadCurve(to: point(0.24, 0.14), controlPoint: point(0.17, 0.16))
            p.close()
        case .jellyfish:
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y)
            }
            p.move(to: point(0.22, 0.26))
            p.addCurve(to: point(0.78, 0.26), controlPoint1: point(0.32, 0.11), controlPoint2: point(0.65, 0.1))
            p.addCurve(to: point(0.22, 0.26), controlPoint1: point(0.56, 0.2), controlPoint2: point(0.43, 0.2))
            p.close()
        case .flame:
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y)
            }
            p.move(to: point(0.18, 0.59))
            p.addCurve(to: point(0.23, 0.84), controlPoint1: point(0.11, 0.67), controlPoint2: point(0.14, 0.8))
            p.addQuadCurve(to: point(0.23, 0.78), controlPoint: point(0.27, 0.84))
            p.addQuadCurve(to: point(0.18, 0.59), controlPoint: point(0.17, 0.7))
            p.close()
            p.move(to: point(0.84, 0.61))
            p.addQuadCurve(to: point(0.78, 0.81), controlPoint: point(0.85, 0.73))
            p.addQuadCurve(to: point(0.8, 0.84), controlPoint: point(0.75, 0.86))
            p.addCurve(to: point(0.84, 0.61), controlPoint1: point(0.9, 0.79), controlPoint2: point(0.9, 0.67))
            p.close()
        case .droplet:
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y)
            }
            p.move(to: point(0.24, 0.4))
            p.addCurve(to: point(0.21, 0.72), controlPoint1: point(0.13, 0.47), controlPoint2: point(0.13, 0.66))
            p.addQuadCurve(to: point(0.23, 0.67), controlPoint: point(0.25, 0.74))
            p.addCurve(to: point(0.27, 0.42), controlPoint1: point(0.19, 0.55), controlPoint2: point(0.22, 0.47))
            p.addQuadCurve(to: point(0.24, 0.4), controlPoint: point(0.29, 0.38))
            p.close()
        case .duck:
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y)
            }
            p.move(to: point(0.78, 0.26))
            p.addQuadCurve(to: point(0.97, 0.31), controlPoint: point(0.96, 0.25))
            p.addQuadCurve(to: point(0.79, 0.36), controlPoint: point(0.96, 0.36))
            p.addQuadCurve(to: point(0.78, 0.26), controlPoint: point(0.74, 0.31))
            p.close()
            p.move(to: point(0.64, 0.22))
            p.addCurve(to: point(0.7, 0.22), controlPoint1: point(0.64, 0.19), controlPoint2: point(0.7, 0.19))
            p.addCurve(to: point(0.64, 0.22), controlPoint1: point(0.7, 0.25), controlPoint2: point(0.64, 0.25))
            p.close()
        default: return nil
        }
        return p.cgPath
    }

    func detailColor(theme: KeyboardTheme) -> UIColor {
        if let a = art { return a.detailColor(theme: theme) }
        switch self {
        case .pudding: return UIColor(hex: theme.isDark ? 0xD7A15F : 0xA86635)
        case .flame: return UIColor(hex: theme.isDark ? 0xFFD46B : 0xED914A)
        case .droplet: return UIColor(hex: theme.isDark ? 0xB8EFFF : 0x4AADD5)
        case .duck: return UIColor(hex: theme.isDark ? 0xFFD276 : 0xD78A32)
        default: return theme.accent
        }
    }

    func path(in r: CGRect) -> CGPath {
        if isWide(r) {
            let body = wideBody(in: r)
            return UIBezierPath(roundedRect: body, cornerRadius: body.height * 0.36).cgPath
        }
        if let a = art { return a.path(in: r) }
        let body = bodyRect(in: r)
        switch self {
        case .rounded:
            return UIBezierPath(roundedRect: body, cornerRadius: min(7, body.height * 0.22)).cgPath
        case .jelly:
            return UIBezierPath(roundedRect: body, cornerRadius: min(body.width, body.height) * 0.42).cgPath
        case .catEar:
            let ear = earSize(r)
            let path = UIBezierPath(roundedRect: body, cornerRadius: min(body.width, body.height) * 0.34)
            let left = UIBezierPath()
            left.move(to: CGPoint(x: body.minX + ear * 0.2, y: body.minY + ear * 1.1))
            left.addLine(to: CGPoint(x: body.minX + ear * 0.45, y: r.minY))
            left.addLine(to: CGPoint(x: body.minX + ear * 1.7, y: body.minY + ear * 0.35))
            left.close()
            let right = UIBezierPath()
            right.move(to: CGPoint(x: body.maxX - ear * 1.7, y: body.minY + ear * 0.35))
            right.addLine(to: CGPoint(x: body.maxX - ear * 0.45, y: r.minY))
            right.addLine(to: CGPoint(x: body.maxX - ear * 0.2, y: body.minY + ear * 1.1))
            right.close()
            path.append(left)
            path.append(right)
            return path.cgPath
        case .cloud:
            let b = bumpSize(r)
            let path = UIBezierPath(roundedRect: body, cornerRadius: min(body.width, body.height) * 0.38)
            let count = max(2, Int(body.width / 20))
            let step = body.width / CGFloat(count + 1)
            for i in 1...count {
                let c = CGPoint(x: body.minX + step * CGFloat(i), y: body.minY + b * 0.5)
                let circle = UIBezierPath(arcCenter: c, radius: b * 1.5, startAngle: 0, endAngle: .pi * 2, clockwise: true)
                path.append(circle)
            }
            return path.cgPath
        case .bunny:
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y)
            }
            let p = UIBezierPath()
            p.move(to: point(0.2, 0.32))
            p.addCurve(to: point(0.23, 0.03), controlPoint1: point(0.13, 0.15), controlPoint2: point(0.13, 0.03))
            p.addCurve(to: point(0.37, 0.28), controlPoint1: point(0.33, 0.03), controlPoint2: point(0.34, 0.19))
            p.addQuadCurve(to: point(0.63, 0.28), controlPoint: point(0.5, 0.24))
            p.addCurve(to: point(0.77, 0.03), controlPoint1: point(0.66, 0.19), controlPoint2: point(0.67, 0.03))
            p.addCurve(to: point(0.8, 0.32), controlPoint1: point(0.87, 0.03), controlPoint2: point(0.87, 0.15))
            p.addCurve(to: point(0.97, 0.67), controlPoint1: point(0.96, 0.37), controlPoint2: point(0.98, 0.51))
            p.addCurve(to: point(0.5, 0.97), controlPoint1: point(0.97, 0.91), controlPoint2: point(0.83, 0.97))
            p.addCurve(to: point(0.03, 0.67), controlPoint1: point(0.17, 0.97), controlPoint2: point(0.03, 0.91))
            p.addCurve(to: point(0.2, 0.32), controlPoint1: point(0.02, 0.51), controlPoint2: point(0.04, 0.37))
            p.close()
            return p.cgPath
        case .puppy:
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y)
            }
            let p = UIBezierPath()
            p.move(to: point(0.24, 0.21))
            p.addCurve(to: point(0.77, 0.21), controlPoint1: point(0.35, 0.09), controlPoint2: point(0.66, 0.09))
            p.addCurve(to: point(0.98, 0.39), controlPoint1: point(0.9, 0.16), controlPoint2: point(0.96, 0.25))
            p.addCurve(to: point(0.86, 0.67), controlPoint1: point(1, 0.55), controlPoint2: point(0.95, 0.69))
            p.addLine(to: point(0.83, 0.66))
            p.addCurve(to: point(0.5, 0.96), controlPoint1: point(0.82, 0.88), controlPoint2: point(0.73, 0.96))
            p.addCurve(to: point(0.17, 0.66), controlPoint1: point(0.27, 0.96), controlPoint2: point(0.18, 0.88))
            p.addLine(to: point(0.14, 0.67))
            p.addCurve(to: point(0.02, 0.39), controlPoint1: point(0.05, 0.69), controlPoint2: point(0, 0.55))
            p.addCurve(to: point(0.24, 0.21), controlPoint1: point(0.04, 0.25), controlPoint2: point(0.1, 0.16))
            p.close()
            return p.cgPath
        case .pudding:
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y)
            }
            let p = UIBezierPath()
            p.move(to: point(0.24, 0.13))
            p.addQuadCurve(to: point(0.76, 0.13), controlPoint: point(0.5, 0.06))
            p.addCurve(to: point(0.89, 0.45), controlPoint1: point(0.86, 0.16), controlPoint2: point(0.86, 0.28))
            p.addLine(to: point(0.96, 0.77))
            p.addCurve(to: point(0.5, 0.97), controlPoint1: point(1, 0.94), controlPoint2: point(0.79, 0.97))
            p.addCurve(to: point(0.04, 0.77), controlPoint1: point(0.21, 0.97), controlPoint2: point(0, 0.94))
            p.addLine(to: point(0.11, 0.45))
            p.addCurve(to: point(0.24, 0.13), controlPoint1: point(0.14, 0.28), controlPoint2: point(0.14, 0.16))
            p.close()
            return p.cgPath
        case .jellyfish:
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y)
            }
            let p = UIBezierPath()
            p.move(to: point(0.07, 0.67))
            p.addCurve(to: point(0.5, 0.08), controlPoint1: point(0.03, 0.35), controlPoint2: point(0.19, 0.08))
            p.addCurve(to: point(0.93, 0.67), controlPoint1: point(0.81, 0.08), controlPoint2: point(0.97, 0.35))
            p.addQuadCurve(to: point(0.82, 0.77), controlPoint: point(0.94, 0.77))
            p.addCurve(to: point(0.83, 0.94), controlPoint1: point(0.82, 0.83), controlPoint2: point(0.89, 0.89))
            p.addCurve(to: point(0.69, 0.79), controlPoint1: point(0.74, 1), controlPoint2: point(0.69, 0.88))
            p.addLine(to: point(0.58, 0.8))
            p.addCurve(to: point(0.5, 0.98), controlPoint1: point(0.57, 0.88), controlPoint2: point(0.6, 0.98))
            p.addCurve(to: point(0.42, 0.8), controlPoint1: point(0.4, 0.98), controlPoint2: point(0.43, 0.88))
            p.addLine(to: point(0.31, 0.79))
            p.addCurve(to: point(0.17, 0.94), controlPoint1: point(0.31, 0.88), controlPoint2: point(0.26, 1))
            p.addCurve(to: point(0.18, 0.77), controlPoint1: point(0.11, 0.89), controlPoint2: point(0.18, 0.83))
            p.addQuadCurve(to: point(0.07, 0.67), controlPoint: point(0.06, 0.77))
            p.close()
            return p.cgPath
        case .flame:
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y)
            }
            let p = UIBezierPath()
            p.move(to: point(0.6, 0.05))
            p.addCurve(to: point(0.7, 0.23), controlPoint1: point(0.65, 0.04), controlPoint2: point(0.63, 0.17))
            p.addCurve(to: point(0.82, 0.43), controlPoint1: point(0.77, 0.31), controlPoint2: point(0.81, 0.34))
            p.addQuadCurve(to: point(0.92, 0.41), controlPoint: point(0.9, 0.32))
            p.addCurve(to: point(0.83, 0.9), controlPoint1: point(1, 0.63), controlPoint2: point(0.97, 0.81))
            p.addCurve(to: point(0.16, 0.9), controlPoint1: point(0.68, 1), controlPoint2: point(0.31, 1))
            p.addCurve(to: point(0.09, 0.43), controlPoint1: point(0.02, 0.81), controlPoint2: point(0, 0.63))
            p.addQuadCurve(to: point(0.16, 0.43), controlPoint: point(0.13, 0.35))
            p.addQuadCurve(to: point(0.24, 0.48), controlPoint: point(0.19, 0.48))
            p.addCurve(to: point(0.47, 0.16), controlPoint1: point(0.37, 0.47), controlPoint2: point(0.35, 0.21))
            p.addQuadCurve(to: point(0.6, 0.05), controlPoint: point(0.54, 0.13))
            p.close()
            return p.cgPath
        case .droplet:
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y)
            }
            let p = UIBezierPath()
            p.move(to: point(0.58, 0.06))
            p.addCurve(to: point(0.7, 0.24), controlPoint1: point(0.63, 0.03), controlPoint2: point(0.6, 0.14))
            p.addCurve(to: point(0.95, 0.63), controlPoint1: point(0.79, 0.33), controlPoint2: point(0.95, 0.42))
            p.addCurve(to: point(0.5, 0.97), controlPoint1: point(0.98, 0.88), controlPoint2: point(0.78, 0.97))
            p.addCurve(to: point(0.05, 0.63), controlPoint1: point(0.22, 0.97), controlPoint2: point(0.02, 0.88))
            p.addCurve(to: point(0.38, 0.22), controlPoint1: point(0.06, 0.41), controlPoint2: point(0.24, 0.3))
            p.addQuadCurve(to: point(0.58, 0.06), controlPoint: point(0.5, 0.16))
            p.close()
            return p.cgPath
        case .duck:
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y)
            }
            let p = UIBezierPath()
            p.move(to: point(0.32, 0.43))
            p.addCurve(to: point(0.44, 0.1), controlPoint1: point(0.26, 0.32), controlPoint2: point(0.3, 0.14))
            p.addCurve(to: point(0.8, 0.25), controlPoint1: point(0.59, 0.04), controlPoint2: point(0.79, 0.12))
            p.addQuadCurve(to: point(0.98, 0.31), controlPoint: point(0.98, 0.25))
            p.addQuadCurve(to: point(0.8, 0.38), controlPoint: point(0.98, 0.38))
            p.addLine(to: point(0.78, 0.47))
            p.addCurve(to: point(0.91, 0.82), controlPoint1: point(0.93, 0.53), controlPoint2: point(0.98, 0.68))
            p.addCurve(to: point(0.45, 0.97), controlPoint1: point(0.84, 0.97), controlPoint2: point(0.64, 0.98))
            p.addCurve(to: point(0.04, 0.66), controlPoint1: point(0.19, 0.97), controlPoint2: point(0.05, 0.84))
            p.addQuadCurve(to: point(0.1, 0.57), controlPoint: point(0.02, 0.54))
            p.addQuadCurve(to: point(0.32, 0.43), controlPoint: point(0.23, 0.64))
            p.close()
            return p.cgPath
        default:
            return UIBezierPath(roundedRect: body, cornerRadius: min(body.width, body.height) * 0.3).cgPath
        }
    }
}

struct KeyboardStyle {
    var theme: KeyboardTheme
    var shape: KeyShape
    var keyAlpha: CGFloat
    var fontScale: CGFloat = 1   // 按鍵上的字放大縮小
    var gapScale: CGFloat = 1    // 按鍵之間的空隙（越小按鍵越大）
    var fontID = KeyFont.system.rawValue
    var keyEffect = KeyEffect.none.rawValue
    var finish = KeyFinish.flat
    /// 線條造型（貓咪、熊熊…）放大幾倍；可以超出按鍵一點點，看起來比較大顆
    var shapeScale: CGFloat = 1.15
    /// 按下去的動作：jelly 果凍彈彈、hop 跳跳、wiggle 搖搖、pop 放大、none 無（只有字的按鍵會動）
    var motion = KeyMotion.jelly.rawValue

    /// 線條的顏色：線稿質感的外框、貓咪的尾巴鬍鬚眼睛肉球
    var lineColor: UIColor {
        if finish == .outline {
            return theme.isDark ? UIColor(hex: 0xFAFBFF).withAlphaComponent(0.94) : UIColor(hex: 0x292B2C).withAlphaComponent(0.84)
        }
        return theme.keyText.withAlphaComponent(0.8)
    }
}

/// 按鍵質感：平面、胖胖（圓滾滾、按下去會壓扁）、立體（有厚度、按下去往下沉）
/// 立體的存檔名沿用舊的 "glass"，以前選玻璃的人會直接變成立體
enum KeyFinish: String, CaseIterable {
    case flat, puffy, raised = "glass", outline, liquid, metal

    var title: String {
        switch self {
        case .flat: return "平面"
        case .puffy: return "胖胖"
        case .raised: return "立體"
        case .outline: return "線稿"
        case .liquid: return "液態玻璃"
        case .metal: return "液態金屬"
        }
    }
}

/// 液態玻璃：模糊過的背景照片，和它在按鍵那片（grid）上的位置；每顆鍵從這裡透出自己後面那一塊
enum GlassBackdrop {
    static var image: CGImage?
    static var rect: CGRect = .zero
    /// 照片或位置變了就加一；按鍵看到一樣的號碼就不用重新對準
    static var version = 0
}

/// 按下去的動作
enum KeyMotion: String, CaseIterable {
    case jelly, hop, wiggle, pop, none

    var title: String {
        switch self {
        case .jelly: return "🍮 果凍彈彈"
        case .hop: return "🐰 跳跳"
        case .wiggle: return "🎵 搖搖"
        case .pop: return "⭐ 放大"
        case .none: return "無"
        }
    }
}

/// 按下按鍵時冒出來的小圖案
enum KeyEffect: String, CaseIterable {
    case none, stars, hearts, sparkles, flowers, bubbles

    var title: String {
        switch self {
        case .none: return "無"
        case .stars: return "星星"
        case .hearts: return "愛心"
        case .sparkles: return "閃亮"
        case .flowers: return "花花"
        case .bubbles: return "泡泡"
        }
    }

    var glyphs: [String] {
        switch self {
        case .none: return []
        case .stars: return ["★", "☆", "✦"]
        case .hearts: return ["♥\u{FE0E}", "♡", "❤\u{FE0E}"]
        case .sparkles: return ["✧", "✦", "⋆"]
        case .flowers: return ["✿", "❀", "❁"]
        case .bubbles: return ["○", "◦", "°"]
        }
    }
}

/// 系統鍵盤聲與短促柔和的叮叮聲；舊音效選項會回到系統聲。
enum KeySound: String, CaseIterable {
    case system, tink

    var title: String {
        switch self {
        case .system: return "iPhone 原本"
        case .tink: return "叮叮"
        }
    }
}

/// 按鍵和候選字用的字體（App 裡附的免費字體，SIL OFL 1.1）
enum KeyFont: String, CaseIterable {
    case system, huninn, iansui, wenkai, gensen, naikai, cubic

    var title: String {
        switch self {
        case .system: return "系統"
        case .huninn: return "粉圓"
        case .iansui: return "芫荽"
        case .wenkai: return "文楷"
        case .gensen: return "源泉圓體"
        case .naikai: return "內海"
        case .cubic: return "像素"
        }
    }

    /// 放在 App 裡的字體；其他的要用時才下載（FontPacks）
    var bundled: Bool { self == .system || self == .huninn }
}

/// 要用再下載的字體：放在 GitHub 的 font-pack 發佈，下載後存在鍵盤自己的空間，可以移除、之後再下載
enum FontPacks {
    static func remote(_ id: String) -> URL {
        URL(string: "https://github.com/z3332111-cloud/StarKeyboard/releases/download/font-pack/\(id).ttf")!
    }

    private static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("FontPack", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private static func file(_ id: String) -> URL { dir.appendingPathComponent(id + ".ttf") }

    /// 已經下載好的字體檔
    static func url(_ id: String) -> URL? {
        guard let f = KeyFont(rawValue: id), !f.bundled else { return nil }
        let u = file(id)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    /// 可以直接用（內建、已下載、或使用者自己匯入的）
    static func isReady(_ id: String) -> Bool {
        if id.hasPrefix("user:") { return UserFonts.url(id) != nil }
        guard let f = KeyFont(rawValue: id) else { return false }
        return f.bundled || url(id) != nil
    }

    static func download(_ id: String, done: @escaping (Bool) -> Void) {
        URLSession.shared.downloadTask(with: remote(id)) { tmp, response, _ in
            var ok = false
            if let tmp = tmp, (response as? HTTPURLResponse)?.statusCode == 200,
               let provider = CGDataProvider(url: tmp as CFURL), CGFont(provider) != nil {
                try? FileManager.default.removeItem(at: file(id))
                ok = (try? FileManager.default.moveItem(at: tmp, to: file(id))) != nil
            }
            DispatchQueue.main.async { done(ok) }
        }.resume()
    }

    static func remove(_ id: String) {
        try? FileManager.default.removeItem(at: file(id))
    }
}

enum KeyFonts {
    private static var names: [String: String] = [:]

    /// 選的字體；系統字體或讀不到時用圓體
    static func font(_ id: String, size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        guard id != KeyFont.system.rawValue, !id.isEmpty, let name = postScriptName(id), let f = UIFont(name: name, size: size) else {
            return .rounded(size, weight)
        }
        return f
    }

    /// 第一次用時把字體檔註冊給系統，記住它的名字
    private static func postScriptName(_ id: String) -> String? {
        if let n = names[id] { return n }
        guard let url = UserFonts.url(id) ?? FontPacks.url(id) ?? Bundle.main.url(forResource: id, withExtension: "ttf")
                ?? Bundle.main.url(forResource: id, withExtension: "ttf", subdirectory: "Fonts"),
              let provider = CGDataProvider(url: url as CFURL),
              let cg = CGFont(provider),
              let name = cg.postScriptName as String? else { return nil }
        CTFontManagerRegisterGraphicsFont(cg, nil)
        names[id] = name
        return name
    }
}

/// 空白鍵上的小圖：自己的圖片（PNG，去背後的透明底）或 GIF 動圖，存在鍵盤自己的空間
enum SpaceArt {
    private static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    private static var png: URL { dir.appendingPathComponent("space.png") }
    private static var gif: URL { dir.appendingPathComponent("space.gif") }
    static let maxBytes = 3 * 1024 * 1024
    private static var cache: (String, UIImage?)?

    static var hasImage: Bool { FileManager.default.fileExists(atPath: png.path) || FileManager.default.fileExists(atPath: gif.path) }

    /// 換圖時會變，用來讓按鍵重畫
    static var version: String {
        let url = FileManager.default.fileExists(atPath: gif.path) ? gif : png
        let date = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? nil
        return String(Int(date?.timeIntervalSince1970 ?? 0))
    }

    static func save(gifData: Data) throws {
        clear()
        try gifData.write(to: gif, options: .atomic)
    }

    static func save(image: UIImage) throws {
        clear()
        guard let data = image.resized(maxSide: 200).pngData() else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: png, options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: png)
        try? FileManager.default.removeItem(at: gif)
        cache = nil
    }

    /// 讀圖（GIF 會變成會動的圖，每格縮小到 160 像素，記憶體才不會爆）
    static func image() -> UIImage? {
        let v = version
        if let c = cache, c.0 == v { return c.1 }
        var result: UIImage?
        if FileManager.default.fileExists(atPath: gif.path), let src = CGImageSourceCreateWithURL(gif as CFURL, nil) {
            let count = min(CGImageSourceGetCount(src), 80)
            var frames: [UIImage] = []
            var total = 0.0
            let opts = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 160,
                        kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
            for i in 0..<count {
                guard let cg = CGImageSourceCreateThumbnailAtIndex(src, i, opts) else { continue }
                frames.append(UIImage(cgImage: cg))
                let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
                let g = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
                let d = (g?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (g?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
                total += d < 0.02 ? 0.1 : d
            }
            result = frames.count > 1 ? UIImage.animatedImage(with: frames, duration: total) : frames.first
        } else if FileManager.default.fileExists(atPath: png.path) {
            result = UIImage(contentsOfFile: png.path)
        }
        cache = (v, result)
        return result
    }
}

/// 使用者自己匯入的字體（自己買的、自己用）：檔案存在鍵盤自己的空間，id 是 "user:" 開頭
enum UserFonts {
    struct Item: Codable { let id: String; let name: String }
    static let maxBytes = 40 * 1024 * 1024
    private static let key = "userFonts"

    private static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("UserFonts", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static var all: [Item] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([Item].self, from: data) else { return [] }
        return list.filter { FileManager.default.fileExists(atPath: file($0.id).path) }
    }

    private static func save(_ list: [Item]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: key)
    }

    private static func file(_ id: String) -> URL {
        dir.appendingPathComponent(String(id.dropFirst(5)) + ".font")
    }

    static func url(_ id: String) -> URL? {
        guard id.hasPrefix("user:") else { return nil }
        let f = file(id)
        return FileManager.default.fileExists(atPath: f.path) ? f : nil
    }

    enum ImportError: Error { case tooBig, notFont }

    /// 存一個字體檔；不是字體或太大就丟錯
    static func add(_ data: Data, name: String?) throws -> Item {
        guard data.count <= maxBytes else { throw ImportError.tooBig }
        guard let provider = CGDataProvider(data: data as CFData), let cg = CGFont(provider) else { throw ImportError.notFont }
        let fontName = (cg.fullName as String?) ?? (cg.postScriptName as String?) ?? "我的字體"
        let display = name.flatMap { $0.isEmpty ? nil : $0 } ?? fontName
        let item = Item(id: "user:" + UUID().uuidString, name: String(display.prefix(12)))
        try data.write(to: file(item.id), options: .atomic)
        save(all + [item])
        return item
    }

    static func remove(_ id: String) {
        try? FileManager.default.removeItem(at: file(id))
        save(all.filter { $0.id != id })
    }
}

/// 鍵盤自己的設定（存在鍵盤擴充功能自己的空間，不需要 App Group）
final class KeyboardSettings {
    static let shared = KeyboardSettings()
    private let d = UserDefaults.standard

    private func bool(_ key: String, _ fallback: Bool) -> Bool { d.object(forKey: key) as? Bool ?? fallback }
    private func double(_ key: String, _ fallback: Double) -> Double { d.object(forKey: key) as? Double ?? fallback }

    var themeID: String {
        get { d.string(forKey: "themeID") ?? "strawberry" }
        set { d.set(newValue, forKey: "themeID") }
    }
    var fontID: String {
        get { d.string(forKey: "fontID") ?? KeyFont.system.rawValue }
        set { d.set(newValue, forKey: "fontID") }
    }
    var keyShape: KeyShape {
        get { KeyShape(rawValue: d.string(forKey: "keyShape") ?? "") ?? .jelly }
        set { d.set(newValue.rawValue, forKey: "keyShape") }
    }
    var keyAlpha: CGFloat {
        get { CGFloat(double("keyAlpha", 1)) }
        set { d.set(Double(newValue), forKey: "keyAlpha") }
    }
    /// 背景圖片上蓋一層主題色，0 = 完全看得到圖
    var backgroundFade: CGFloat {
        get { CGFloat(double("backgroundFade", 0.25)) }
        set { d.set(Double(newValue), forKey: "backgroundFade") }
    }
    // MARK: 背景照片（可以放好幾張輪流換，每張記住自己的位置和大小）

    /// 照片裁切時盡量放在中間的點（0～1，貼上時有找到臉就是臉的位置）、放大倍數（1 = 剛好蓋滿鍵盤）
    struct BgPhoto: Codable, Equatable {
        var file: String
        var fx: Double = 0.5
        var fy: Double = 0.3
        var zoom: Double = 1
    }

    static let photoDirectory: URL = {
        let dir = Storage.directory.appendingPathComponent("backgrounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    var photos: [BgPhoto] {
        get {
            guard let data = d.data(forKey: "photos") else { return migrateOldBackground() }
            return (try? JSONDecoder().decode([BgPhoto].self, from: data)) ?? []
        }
        set { d.set(try? JSONEncoder().encode(newValue), forKey: "photos") }
    }

    /// 舊版只有一張 background.jpg：搬進照片清單
    private func migrateOldBackground() -> [BgPhoto] {
        var list: [BgPhoto] = []
        let old = Storage.url("background.jpg")
        if bool("hasBackground", false), FileManager.default.fileExists(atPath: old.path) {
            let name = "bg-old.jpg"
            if (try? FileManager.default.moveItem(at: old, to: Self.photoDirectory.appendingPathComponent(name))) != nil {
                list.append(BgPhoto(file: name, fx: double("backgroundFocusX", 0.5), fy: double("backgroundFocusY", 0.3),
                                    zoom: double("backgroundZoom", 1)))
            }
        }
        photos = list
        return list
    }

    var photoIndex: Int {
        get { d.integer(forKey: "photoIndex") }
        set { d.set(newValue, forKey: "photoIndex") }
    }

    /// 照片怎麼換：fixed 固定、open 每次打開鍵盤換、daily 每天換
    var photoRotation: String {
        get { d.string(forKey: "photoRotation") ?? "fixed" }
        set { d.set(newValue, forKey: "photoRotation") }
    }

    private func wrapped(_ i: Int, _ n: Int) -> Int { ((i % n) + n) % n }

    var currentPhoto: BgPhoto? {
        let list = photos
        return list.isEmpty ? nil : list[wrapped(photoIndex, list.count)]
    }

    var currentPhotoURL: URL? { currentPhoto.map { Self.photoDirectory.appendingPathComponent($0.file) } }
    var hasBackground: Bool { currentPhotoURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }

    private func updateCurrent(_ change: (inout BgPhoto) -> Void) {
        var list = photos
        guard !list.isEmpty else { return }
        change(&list[wrapped(photoIndex, list.count)])
        photos = list
    }

    var backgroundFocusX: Double {
        get { currentPhoto?.fx ?? 0.5 }
        set { updateCurrent { $0.fx = newValue } }
    }
    var backgroundFocusY: Double {
        get { currentPhoto?.fy ?? 0.3 }
        set { updateCurrent { $0.fy = newValue } }
    }
    var backgroundZoom: Double {
        get { currentPhoto?.zoom ?? 1 }
        set { updateCurrent { $0.zoom = min(max(newValue, 1), 5) } }
    }

    /// 新增一張照片，並換成這張
    func addPhoto(_ data: Data, fx: Double, fy: Double) throws {
        let name = "bg-\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
        try data.write(to: Self.photoDirectory.appendingPathComponent(name), options: .atomic)
        let list = photos + [BgPhoto(file: name, fx: fx, fy: fy, zoom: 1)]
        photos = list
        photoIndex = list.count - 1
    }

    func removePhoto(at index: Int) {
        var list = photos
        guard list.indices.contains(index) else { return }
        try? FileManager.default.removeItem(at: Self.photoDirectory.appendingPathComponent(list.remove(at: index).file))
        photos = list
        photoIndex = list.isEmpty ? 0 : min(wrapped(photoIndex, list.count), list.count - 1)
    }

    func clearPhotos() {
        for p in photos { try? FileManager.default.removeItem(at: Self.photoDirectory.appendingPathComponent(p.file)) }
        photos = []
        photoIndex = 0
    }

    /// 打開鍵盤時依設定換照片
    func rotatePhoto() {
        let n = photos.count
        guard n >= 2 else { return }
        switch photoRotation {
        case "open": photoIndex = (wrapped(photoIndex, n) + 1) % n
        case "daily":
            let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
            photoIndex = day % n
        default: break
        }
    }

    /// 照片的小縮圖（設定面板用）
    func thumbnail(_ p: BgPhoto) -> UIImage? {
        // 直接讀小圖，不先把整張照片解開（省記憶體）
        let url = Self.photoDirectory.appendingPathComponent(p.file)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 240,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
    var keyEffect: String {
        get { d.string(forKey: "keyEffect") ?? KeyEffect.none.rawValue }
        set { d.set(newValue, forKey: "keyEffect") }
    }
    // 自訂配色：色相 0～1、濃淡 0～1、深色
    var customHue: Double {
        get { double("customHue", 0.92) }
        set { d.set(newValue, forKey: "customHue") }
    }
    var customSaturation: Double {
        get { double("customSaturation", 0.55) }
        set { d.set(newValue, forKey: "customSaturation") }
    }
    /// 第二色：-1 = 單色（不用第二色）
    var customHue2: Double {
        get { double("customHue2", -1) }
        set { d.set(newValue, forKey: "customHue2") }
    }
    var customSaturation2: Double {
        get { double("customSaturation2", 0.55) }
        set { d.set(newValue, forKey: "customSaturation2") }
    }
    /// 空白鍵：theme 主題符號＋輸入法名字、image 自己的圖片／GIF、emoji 表符、text 只有字
    var spaceStyle: String {
        get { d.string(forKey: "spaceStyle") ?? "theme" }
        set { d.set(newValue, forKey: "spaceStyle") }
    }
    var spaceEmoji: String {
        get { d.string(forKey: "spaceEmoji") ?? "🐰" }
        set { d.set(newValue, forKey: "spaceEmoji") }
    }
    var customDark: Bool {
        get { bool("customDark", false) }
        set { d.set(newValue, forKey: "customDark") }
    }
    var keyFinish: KeyFinish {
        get { KeyFinish(rawValue: d.string(forKey: "keyFinish") ?? "") ?? .flat }
        set { d.set(newValue.rawValue, forKey: "keyFinish") }
    }
    var keySoundStyle: String {
        get { d.string(forKey: "keySoundStyle") ?? KeySound.system.rawValue }
        set { d.set(newValue, forKey: "keySoundStyle") }
    }
    /// 按下去的動作（KeyMotion）
    var keyMotion: String {
        get { d.string(forKey: "keyMotion") ?? KeyMotion.jelly.rawValue }
        set { d.set(newValue, forKey: "keyMotion") }
    }
    var keySound: Bool {
        get { bool("keySound", true) }
        set { d.set(newValue, forKey: "keySound") }
    }
    var haptics: Bool {
        get { bool("haptics", true) }
        set { d.set(newValue, forKey: "haptics") }
    }
    var associations: Bool {
        get { bool("associations", true) }
        set { d.set(newValue, forKey: "associations") }
    }
    /// 上面那一排關掉的按鈕
    var hiddenToolbarItems: Set<ToolbarItem> {
        get { Set((d.stringArray(forKey: "hiddenTools") ?? []).compactMap { ToolbarItem(rawValue: $0) }) }
        set { d.set(newValue.map { $0.rawValue }, forKey: "hiddenTools") }
    }
    var enabledModes: [InputMode] {
        get {
            let raw = d.stringArray(forKey: "modes") ?? [InputMode.zhuyin, .english, .handwriting].map { $0.rawValue }
            let modes = InputMode.allCases.filter { raw.contains($0.rawValue) }
            return modes.isEmpty ? [.zhuyin] : modes
        }
        set { d.set(newValue.map { $0.rawValue }, forKey: "modes") }
    }
    var lastMode: InputMode {
        get { InputMode(rawValue: d.string(forKey: "lastMode") ?? "") ?? .zhuyin }
        set { d.set(newValue.rawValue, forKey: "lastMode") }
    }
    var glideTyping: Bool {
        get { bool("glideTyping", true) }
        set { d.set(newValue, forKey: "glideTyping") }
    }
    var autocorrect: Bool {
        get { bool("autocorrect", true) }
        set { d.set(newValue, forKey: "autocorrect") }
    }
    var fuzzyKeys: Bool {
        get { bool("fuzzyKeys", true) }
        set { d.set(newValue, forKey: "fuzzyKeys") }
    }
    var fuzzyTones: Bool {
        get { bool("fuzzyTones", true) }
        set { d.set(newValue, forKey: "fuzzyTones") }
    }
    var fuzzyPhonetic: Bool {
        get { bool("fuzzyPhonetic", false) }
        set { d.set(newValue, forKey: "fuzzyPhonetic") }
    }
    /// 鍵盤高度倍率（0.8～1.3）
    var heightScale: CGFloat {
        get { CGFloat(double("heightScale", 1)) }
        set { d.set(Double(newValue), forKey: "heightScale") }
    }
    /// 按鍵字的大小倍率（0.8～1.4）
    var fontScale: CGFloat {
        get { CGFloat(double("fontScale", 1)) }
        set { d.set(Double(newValue), forKey: "fontScale") }
    }
    /// 按鍵間距倍率（0.3～1.6）
    var gapScale: CGFloat {
        get { CGFloat(double("gapScale", 1)) }
        set { d.set(Double(newValue), forKey: "gapScale") }
    }
    /// 貓咪、熊熊這類造型的大小（1 = 剛好放進按鍵，大於 1 會超出一點）
    var shapeScale: CGFloat {
        get { CGFloat(double("shapeScale", 1.15)) }
        set { d.set(Double(newValue), forKey: "shapeScale") }
    }
    // 新版提醒
    var lastUpdateCheck: Double {
        get { d.double(forKey: "lastUpdateCheck") }
        set { d.set(newValue, forKey: "lastUpdateCheck") }
    }
    var latestBuild: Int {
        get { d.integer(forKey: "latestBuild") }
        set { d.set(newValue, forKey: "latestBuild") }
    }
    var notifiedBuild: Int {
        get { d.integer(forKey: "notifiedBuild") }
        set { d.set(newValue, forKey: "notifiedBuild") }
    }
    /// 注音十欄排法（像 Gboard）
    var zhuyinTenColumns: Bool {
        get { bool("zhuyinTenColumns", false) }
        set { d.set(newValue, forKey: "zhuyinTenColumns") }
    }
    /// 拼音模式輸出簡體字（馬來西亞、中國用簡體）
    var pinyinSimplified: Bool {
        get { bool("pinyinSimplified", false) }
        set { d.set(newValue, forKey: "pinyinSimplified") }
    }
    /// 舊的全形開關。程式／Markdown 符號一律半形，不受這個值影響。
    var fullWidthSymbols: Bool {
        get { bool("fullWidthSymbols", true) }
        set { d.set(newValue, forKey: "fullWidthSymbols") }
    }
    /// 翻譯的原文語言："auto" 是自己猜
    var translateSource: String {
        get { d.string(forKey: "translateSource") ?? "auto" }
        set { d.set(newValue, forKey: "translateSource") }
    }
    var translateTarget: String {
        get { d.string(forKey: "translateTarget") ?? "en" }
        set { d.set(newValue, forKey: "translateTarget") }
    }
    var clipboardHistoryEnabled: Bool {
        get { bool("clipboardHistoryEnabled", false) }
        set { d.set(newValue, forKey: "clipboardHistoryEnabled") }
    }
    var allowOnlineTranslation: Bool {
        get { bool("allowOnlineTranslation", false) }
        set { d.set(newValue, forKey: "allowOnlineTranslation") }
    }
    /// 選字列高度（點）。拖曳或設定裡的滑桿都會記下來。
    var candidateBarHeight: Double {
        get {
            let stored = d.object(forKey: "candidateBarHeight") as? Double ?? CandidateBarMetrics.defaultHeight
            return CandidateBarMetrics.clamp(stored)
        }
        set { d.set(CandidateBarMetrics.clamp(newValue), forKey: "candidateBarHeight") }
    }
    var clipLimit: Int {
        get { d.object(forKey: "clipLimit") as? Int ?? 200 }
        set { d.set(newValue, forKey: "clipLimit") }
    }
    var lastPasteboardChange: Int {
        get { d.integer(forKey: "lastPasteboardChange") }
        set { d.set(newValue, forKey: "lastPasteboardChange") }
    }
}

enum Storage {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StarKeyboard", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true,
                                                  attributes: [.protectionKey: FileProtectionType.complete])
        // Migrate existing data too; this does not delete older backups or existing history.
        var directory = base
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: base.path)
        if let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) {
            for case let file as URL in files {
                try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: file.path)
            }
        }
        return directory
    }()

    static func url(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }
}

extension UIImage {
    func resized(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let scale = maxSide / longest
        let newSize = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// 直接讀成小圖，不先把整張解開。手機照片整張解開要 40～50MB，鍵盤只有 60MB 左右可以用，會直接閃退。
    static func downsampled(_ source: CGImageSource?, maxSide: CGFloat) -> UIImage? {
        guard let src = source else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    static func downsampled(url: URL, maxSide: CGFloat) -> UIImage? {
        downsampled(CGImageSourceCreateWithURL(url as CFURL, nil), maxSide: maxSide)
    }
}

extension UIPasteboard {
    /// 剪貼簿裡的圖片，讀成小圖（不用 .image，那會把整張大照片解開）
    /// 剪貼簿裡每一個項目各一張圖（App 一次挑好幾張照片時會放好幾個項目），一張一張縮小，不會一次吃光記憶體
    func downsampledImages(maxSide: CGFloat, limit: Int = 10) -> [UIImage] {
        guard numberOfItems > 1 else { return downsampledImage(maxSide: maxSide).map { [$0] } ?? [] }
        let imageTypes = ["public.jpeg", "public.png", "public.heic", "public.tiff", "public.image"]
        var out: [UIImage] = []
        for i in 0..<min(numberOfItems, limit) {
            autoreleasepool {
                let set = IndexSet(integer: i)
                for type in imageTypes {
                    if let data = data(forPasteboardType: type, inItemSet: set)?.first,
                       let img = UIImage.downsampled(CGImageSourceCreateWithData(data as CFData, nil), maxSide: maxSide) {
                        out.append(img)
                        break
                    }
                }
            }
        }
        return out
    }

    func downsampledImage(maxSide: CGFloat) -> UIImage? {
        let imageTypes = ["public.heic", "public.jpeg", "public.png", "com.compuserve.gif", "public.tiff", "public.image"]
        for type in types where imageTypes.contains(type) || type.hasPrefix("public.") && type.contains("image") {
            if let data = data(forPasteboardType: type),
               let img = UIImage.downsampled(CGImageSourceCreateWithData(data as CFData, nil), maxSide: maxSide) {
                return img
            }
        }
        return hasImages ? image?.resized(maxSide: maxSide) : nil
    }
}
