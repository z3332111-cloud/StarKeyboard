import UIKit

/// 設計圖鑑做成的主題。有圖集的要下載才能用，不用可以移除；App 裡不內建圖，才不會越來越大。
struct ThemeLook {
    let theme: KeyboardTheme
    let emoji: String
    let subtitle: String
    /// 有水彩／版畫圖集（docs/theme-packs/theme-<id>.png）
    let hasArt: Bool
    let shape: KeyShape
    let finish: KeyFinish
    /// 鍵帽、寬鍵上的字，和按鍵角落的小字
    let ink: UIColor
    let spaceInk: UIColor
    let hint: UIColor

    private static func make(_ id: String, _ name: String, emoji: String, subtitle: String, bed: UInt32, bedBottom: UInt32? = nil, bar: UInt32, text: UInt32,
                             accent: UInt32, accentText: UInt32, shadow: UInt32, dark: Bool, art: Bool = true,
                             shape: KeyShape = .rounded, finish: KeyFinish = .flat, key: UInt32? = nil, special: UInt32? = nil, specialText: UInt32? = nil,
                             ink: UInt32, spaceInk: UInt32? = nil, hint: UInt32? = nil) -> ThemeLook {
        ThemeLook(theme: KeyboardTheme(id: id, name: name, backgroundTop: UIColor(hex: bed), backgroundBottom: UIColor(hex: bedBottom ?? bed),
                                       key: UIColor(hex: key ?? bar), keyText: UIColor(hex: text),
                                       specialKey: UIColor(hex: special ?? bar), specialText: UIColor(hex: specialText ?? text),
                                       accent: UIColor(hex: accent), accentText: UIColor(hex: accentText), shadow: UIColor(hex: shadow),
                                       decoration: "", isDark: dark),
                  emoji: emoji, subtitle: subtitle, hasArt: art, shape: shape, finish: finish,
                  ink: UIColor(hex: ink), spaceInk: UIColor(hex: spaceInk ?? ink), hint: UIColor(hex: hint ?? text))
    }

    static let all: [ThemeLook] = [
        make("persimmon", "柿子貓的茶屋", emoji: "🍊", subtitle: "秋日水彩", bed: 0xF8E6C6, bar: 0xE9CB9C, text: 0x51351F,
             accent: 0xD9793A, accentText: 0xFFFFFF, shadow: 0xC9A878, dark: false, ink: 0x412C20, spaceInk: 0x302E1D),
        make("observatory", "小梟的月相室", emoji: "🦉", subtitle: "秋日水彩", bed: 0x18243B, bar: 0x293850, text: 0xF5E9CD,
             accent: 0xE3B566, accentText: 0x171B31, shadow: 0x0F1728, dark: true, ink: 0x171B31, spaceInk: 0xFFF4D9),
        make("railway", "稻雀的末班車", emoji: "🌾", subtitle: "秋日水彩", bed: 0x294544, bar: 0x365851, text: 0xFFF0CF,
             accent: 0xE0A64B, accentText: 0x332817, shadow: 0x1C302F, dark: true, ink: 0x332817, spaceInk: 0x4C3323),
        make("pool", "動物泳隊", emoji: "🏊", subtitle: "孔版印刷", bed: 0xACE1DC, bar: 0x1C5975, text: 0xFFF3CE,
             accent: 0xF2743B, accentText: 0xFFFFFF, shadow: 0x115875, dark: true, ink: 0x282335, hint: 0x203735),
        make("fern", "蕨影暗房", emoji: "🌿", subtitle: "植物藍曬", bed: 0x0C3553, bar: 0x0C3352, text: 0xE6F2FA,
             accent: 0x8FC1E3, accentText: 0x0C3352, shadow: 0x061F33, dark: true, ink: 0xFFFFFF),
        make("cat-outline", "貓咪描邊", emoji: "🐈", subtitle: "線稿＋你的照片", bed: 0x2A2622, bedBottom: 0x1D1A17, bar: 0x2A2622, text: 0xFFFFFF,
             accent: 0xFFD48A, accentText: 0x2A2622, shadow: 0x000000, dark: true, art: false, shape: .catLine, finish: .outline, ink: 0xFFFFFF),
        make("scope", "磷光示波器", emoji: "📟", subtitle: "電子儀器", bed: 0x101E1B, bar: 0x142B25, text: 0xCCF7D8,
             accent: 0x86EBAC, accentText: 0x101E1B, shadow: 0x0A1513, dark: true, art: false, shape: .chamfer, finish: .flat,
             key: 0x132C27, specialText: 0xF0C36D, ink: 0xCCF7D8),
    ]

    static func named(_ id: String) -> ThemeLook? { all.first { $0.theme.id == id } }
}

extension KeyboardStyle {
    /// 按鍵是插畫（小狐狸和有圖集的主題）
    var isIllustrated: Bool { isFoxLetter || ThemeLook.named(theme.id)?.hasArt == true }
    var themeLook: ThemeLook? { ThemeLook.named(theme.id) }
}

/// 主題圖要用才下載（和字體一樣，放在 GitHub Pages），不用可以移除
enum ThemePacks {
    private static let base = "https://z3332111-cloud.github.io/StarKeyboard/theme-packs/"

    private static var dir: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = root.appendingPathComponent("ThemePacks", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func files(_ id: String) -> [String] {
        if id == FoxLetterTheme.id { return ["keycaps-watercolor-v2", "wide-keycaps-watercolor-v2", "background-watercolor-v2"] }
        return ThemeLook.named(id)?.hasArt == true ? ["theme-\(id)"] : []
    }

    static func localURL(_ name: String) -> URL? {
        let url = dir.appendingPathComponent(name + ".png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// 不用下載，或已經下載好了
    static func isReady(_ id: String) -> Bool {
        files(id).allSatisfy { localURL($0) != nil }
    }

    /// 在背景下載，完成後在主執行緒回報
    static func download(_ id: String, done: @escaping (Bool) -> Void) {
        let names = files(id)
        var remaining = names.count
        var failed = false
        guard remaining > 0 else { done(true); return }
        for name in names {
            guard let url = URL(string: base + name + ".png") else { continue }
            URLSession.shared.dataTask(with: url) { data, response, _ in
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                // PNG 開頭八個位元組固定，順便擋掉伺服器回的錯誤頁
                let png = data.map { $0.starts(with: [0x89, 0x50, 0x4E, 0x47]) } ?? false
                var ok = code == 200 && png
                if ok, let data = data {
                    ok = (try? data.write(to: dir.appendingPathComponent(name + ".png"), options: .atomic)) != nil
                }
                DispatchQueue.main.async {
                    if !ok { failed = true }
                    remaining -= 1
                    if remaining == 0 { done(!failed) }
                }
            }.resume()
        }
    }

    static func remove(_ id: String) {
        for name in files(id) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name + ".png"))
        }
    }
}
