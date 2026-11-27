import UIKit

enum InputMode: String, CaseIterable {
    case zhuyin, english, handwriting, korean, japanese, pinyin

    var title: String {
        switch self {
        case .zhuyin: return "注音"
        case .english: return "English"
        case .handwriting: return "手寫"
        case .korean: return "한국어"
        case .japanese: return "日本語"
        case .pinyin: return "拼音"
        }
    }

    var shortTitle: String {
        switch self {
        case .zhuyin: return "中"
        case .english: return "英"
        case .handwriting: return "寫"
        case .korean: return "한"
        case .japanese: return "あ"
        case .pinyin: return "拼"
        }
    }
}

enum KeyboardLayer { case letters, numbers, symbols, numpad }
enum ShiftState { case off, on, locked }
enum PanelKind: String { case emoji, kaomoji, stickers, symbols, clipboard, settings }

enum KeyAction: Equatable {
    case text(String)
    case zhuyin(Character)
    case jamo(Character)     // 韓文字母
    case romaji(Character)   // 日文羅馬拼音
    case pinyin(Character)   // 漢語拼音
    case backspace, space, returnKey, shift, globe, nextMode, clearCanvas
    case toggleWidth   // 中文符號頁切換全形／半形
    case layer(KeyboardLayer)
    case panel(PanelKind)

    /// 一般打字的鍵：可以滑動修正、快速連打
    var isCharacter: Bool {
        switch self {
        case .text, .zhuyin, .jamo, .romaji, .pinyin: return true
        default: return false
        }
    }

    /// 大鍵：機械鍵盤上有衛星軸的那幾顆，按鍵聲比較低沉
    var isBig: Bool {
        switch self {
        case .space, .returnKey, .backspace, .shift: return true
        default: return false
        }
    }
}

enum KeyFace: Equatable {
    case text(String)
    case symbol(String)   // SF Symbols 圖示
}

enum KeyKind { case normal, special, accent }

struct KeySpec {
    /// 空白鍵的字以這個開頭＝畫自己的圖片（SpaceArt）
    static let spaceArtMark = "\u{2060}🖼"
    var face: KeyFace
    var action: KeyAction
    /// 以「一個字母鍵」為單位；0 = 填滿剩下的寬度
    var width: CGFloat = 1
    var kind: KeyKind = .normal
    var fontSize: CGFloat = 23
    /// 右上角的小字：長按這顆鍵會打出它（Gboard 式注音的數字、字母）
    var hint: String = ""
    /// 按住會跳出一排字，手指滑過去放開就打出那個（逗號、句號的標點清單）
    var popup: [String] = []

    static let punctuationPopup = ["，", "。", "？", "！", "、", "：", "；", "…", "「", "」", "～", "@", "#", "%"]
}

struct KeyboardLayout {
    var rows: [[KeySpec]]
    var columns: CGFloat
}

enum KeyLayouts {
    struct Context {
        var mode: InputMode
        var layer: KeyboardLayer
        var shift: ShiftState
        var needsGlobe: Bool
        var returnTitle: String
        var spaceTitle: String
        var nextModeTitle: String
        var fullWidthSymbols = false
        var zhuyinTenColumns = false
        var zhuyinAligned = false
    }

    static func layout(_ c: Context) -> KeyboardLayout {
        // 韓文用半形標點，中文、日文用全形
        let chinese = c.mode != .english && c.mode != .korean
        switch c.layer {
        case .letters:
            switch c.mode {
            case .zhuyin: return zhuyin(c)
            case .korean: return korean(c)
            case .japanese: return japanese(c)
            case .pinyin: return pinyin(c)
            default: return english(c)
            }
        case .numbers: return chinese ? chineseNumbers(c) : englishNumbers(c)
        case .symbols: return chinese ? chineseSymbols(c) : englishSymbols(c)
        case .numpad: return numpad(c)
        }
    }

    /// 手寫畫面右邊那一排
    static func handwritingSide(returnTitle: String, nextModeTitle: String) -> KeyboardLayout {
        KeyboardLayout(rows: [
            [KeySpec(face: .symbol("delete.left"), action: .backspace, kind: .special)],
            [KeySpec(face: .text("重寫"), action: .clearCanvas, kind: .special, fontSize: 15)],
            [KeySpec(face: .text("123"), action: .layer(.numbers), kind: .special, fontSize: 15)],
            [KeySpec(face: .text("空白"), action: .space, fontSize: 15)],
            [KeySpec(face: .text(nextModeTitle), action: .nextMode, kind: .special, fontSize: 17)],
            [KeySpec(face: .symbol("return"), action: .returnKey, kind: .accent, fontSize: 15)],
        ], columns: 1)
    }

    private static func keys(_ chars: String, size: CGFloat = 23, width: CGFloat = 1) -> [KeySpec] {
        chars.map { KeySpec(face: .text(String($0)), action: .text(String($0)), width: width, fontSize: size) }
    }

    private static func backspace(_ width: CGFloat = 1.4) -> KeySpec {
        KeySpec(face: .symbol("delete.left"), action: .backspace, width: width, kind: .special)
    }

    private static func bottomRow(_ c: Context, columns: CGFloat) -> [KeySpec] {
        let k = columns / 10
        let layerKey: KeySpec
        if c.layer == .letters && c.mode == .pinyin {
            layerKey = KeySpec(face: .text("!#1"), action: .layer(.numbers), width: 1.3 * k, kind: .special, fontSize: 16)
        } else if c.layer == .letters {
            layerKey = KeySpec(face: .text("123"), action: .layer(.numbers), width: 1.3 * k, kind: .special, fontSize: 16)
        } else {
            let title: String
            switch c.mode {
            case .zhuyin: title = "ㄅㄆㄇ"
            case .english: title = "ABC"
            case .handwriting: title = "手寫"
            case .korean: title = "한글"
            case .japanese: title = "かな"
            case .pinyin: title = "拼音"
            }
            layerKey = KeySpec(face: .text(title), action: .layer(.letters), width: 1.3 * k, kind: .special, fontSize: 14)
        }
        var row = [layerKey]
        if c.needsGlobe {
            row.append(KeySpec(face: .symbol("globe"), action: .globe, width: 1.1 * k, kind: .special))
        }
        if c.layer == .letters {
            row.append(KeySpec(face: .text(c.nextModeTitle), action: .nextMode, width: 1.1 * k, kind: .special, fontSize: 17))
        } else {
            // 123 和符號頁：這格換成大顆的數字鍵盤
            row.append(KeySpec(face: .text("數字"), action: .layer(.numpad), width: 1.1 * k, kind: .special, fontSize: 15))
        }
        if c.layer == .letters && c.mode == .pinyin {
            // 拼音照三星的排法：空白鍵兩邊是逗號、句號，右邊是數字鍵盤
            row.append(KeySpec(face: .text("，"), action: .text("，"), width: 0.9 * k, fontSize: 20, popup: KeySpec.punctuationPopup))
            row.append(KeySpec(face: .text(c.spaceTitle), action: .space, width: 0, fontSize: 15))
            row.append(KeySpec(face: .text("。"), action: .text("。"), width: 0.9 * k, fontSize: 20, popup: KeySpec.punctuationPopup))
            row.append(KeySpec(face: .text("123"), action: .layer(.numpad), width: 1.1 * k, kind: .special, fontSize: 16))
            row.append(KeySpec(face: .symbol("return"), action: .returnKey, width: 1.6 * k, kind: .accent, fontSize: 16))
            return row
        }
        if !c.needsGlobe {
            row.append(KeySpec(face: .symbol("face.smiling"), action: .panel(.emoji), width: 1.1 * k, kind: .special))
        }
        if c.layer == .letters && c.mode == .zhuyin {
            // 注音：空白鍵旁邊放逗號鍵，點一下「，」，按住滑過去選「。？！、…」（和十欄排法一樣）
            row.append(KeySpec(face: .text("，"), action: .text("，"), width: 1.0 * k, fontSize: 20, hint: "。", popup: KeySpec.punctuationPopup))
        }
        row.append(KeySpec(face: .text(c.spaceTitle), action: .space, width: 0, fontSize: 15))
        row.append(KeySpec(face: .symbol("return"), action: .returnKey, width: 2.0 * k, kind: .accent, fontSize: 16))
        return row
    }

    private static func zhuyin(_ c: Context) -> KeyboardLayout {
        if c.zhuyinAligned { return zhuyinAligned(c) }
        if c.zhuyinTenColumns { return zhuyinTen(c) }
        var rows: [[KeySpec]] = Bopomofo.dachenRows.map { line in
            line.map { ch in KeySpec(face: .text(String(ch)), action: .zhuyin(ch), fontSize: 20) }
        }
        rows[3].append(backspace(1))
        rows.append(bottomRow(c, columns: 11))
        return KeyboardLayout(rows: rows, columns: 11)
    }

    /// 注音對齊（像 iPhone 內建注音）：四排都是 10 顆、上下對齊；ㄦ 和 ㄢ 同一顆，按住 ㄢ 打出 ㄦ
    private static func zhuyinAligned(_ c: Context) -> KeyboardLayout {
        var rows: [[KeySpec]] = Bopomofo.dachenRows.map { line in
            line.filter { $0 != "ㄦ" }.map { ch in
                KeySpec(face: .text(String(ch)), action: .zhuyin(ch), fontSize: 21, hint: ch == "ㄢ" ? "ㄦ" : "")
            }
        }
        var bottom = [KeySpec(face: .text("123"), action: .layer(.numbers), width: 1.2, kind: .special, fontSize: 16)]
        if c.needsGlobe {
            bottom.append(KeySpec(face: .symbol("globe"), action: .globe, width: 1, kind: .special))
        }
        bottom.append(KeySpec(face: .text(c.nextModeTitle), action: .nextMode, width: 1, kind: .special, fontSize: 17))
        bottom.append(KeySpec(face: .text("，"), action: .text("，"), width: 1, fontSize: 20, hint: "。", popup: KeySpec.punctuationPopup))
        bottom.append(KeySpec(face: .text(c.spaceTitle), action: .space, width: 0, fontSize: 15))
        bottom.append(backspace(1.3))
        bottom.append(KeySpec(face: .symbol("return"), action: .returnKey, width: 1.6, kind: .accent, fontSize: 16))
        rows.append(bottom)
        return KeyboardLayout(rows: rows, columns: 10)
    }

    /// 注音十欄（像 Gboard）：ㄦ 搬到空白鍵旁邊，每顆鍵右上角有數字／字母，長按就打出來
    private static func zhuyinTen(_ c: Context) -> KeyboardLayout {
        let hints: [[String]] = [
            "1234567890".map { String($0) },
            "qwertyuiop".map { String($0) },
            "asdfghjkl".map { String($0) } + ["："],
            "zxcvbnm".map { String($0) } + ["……", "！", "？"],
        ]
        var rows: [[KeySpec]] = Bopomofo.dachenRows.enumerated().map { r, line in
            line.filter { $0 != "ㄦ" }.enumerated().map { i, ch in
                KeySpec(face: .text(String(ch)), action: .zhuyin(ch), fontSize: 21, hint: hints[r][i])
            }
        }
        var bottom = [KeySpec(face: .text("123"), action: .layer(.numbers), width: 1.2, kind: .special, fontSize: 16)]
        if c.needsGlobe {
            bottom.append(KeySpec(face: .symbol("globe"), action: .globe, width: 1, kind: .special))
        }
        bottom.append(KeySpec(face: .text(c.nextModeTitle), action: .nextMode, width: 1, kind: .special, fontSize: 17))
        bottom.append(KeySpec(face: .text("，"), action: .text("，"), width: 1, fontSize: 20, hint: "。", popup: KeySpec.punctuationPopup))
        bottom.append(KeySpec(face: .text(c.spaceTitle), action: .space, width: 0, fontSize: 15))
        bottom.append(KeySpec(face: .text("ㄦ"), action: .zhuyin("ㄦ"), width: 1, fontSize: 21))
        bottom.append(backspace(1.2))
        bottom.append(KeySpec(face: .symbol("return"), action: .returnKey, width: 1.5, kind: .accent, fontSize: 16))
        rows.append(bottom)
        return KeyboardLayout(rows: rows, columns: 10)
    }

    private static func english(_ c: Context) -> KeyboardLayout {
        let upper = c.shift != .off
        func letters(_ s: String) -> [KeySpec] { keys(upper ? s.uppercased() : s, size: 24) }
        let shiftIcon: String
        switch c.shift {
        case .off: shiftIcon = "shift"
        case .on: shiftIcon = "shift.fill"
        case .locked: shiftIcon = "capslock.fill"
        }
        var row3 = [KeySpec(face: .symbol(shiftIcon), action: .shift, width: 1.4, kind: .special)]
        row3 += letters("zxcvbnm")
        row3.append(backspace())
        return KeyboardLayout(rows: [letters("qwertyuiop"), letters("asdfghjkl"), row3, bottomRow(c, columns: 10)],
                              columns: 10)
    }

    private static func shiftKey(_ shift: ShiftState) -> KeySpec {
        let icon: String
        switch shift {
        case .off: icon = "shift"
        case .on: icon = "shift.fill"
        case .locked: icon = "capslock.fill"
        }
        return KeySpec(face: .symbol(icon), action: .shift, width: 1.4, kind: .special)
    }

    /// 韓文兩排式，Shift 打雙子音和 ㅒㅖ
    private static func korean(_ c: Context) -> KeyboardLayout {
        func jamo(_ s: String) -> [KeySpec] {
            s.map { KeySpec(face: .text(String($0)), action: .jamo($0), fontSize: 21) }
        }
        let top = c.shift == .off ? "ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔ" : "ㅃㅉㄸㄲㅆㅛㅕㅑㅒㅖ"
        var row3 = [shiftKey(c.shift)]
        row3 += jamo("ㅋㅌㅊㅍㅠㅜㅡ")
        row3.append(backspace())
        return KeyboardLayout(rows: [jamo(top), jamo("ㅁㄴㅇㄹㅎㅗㅓㅏㅣ"), row3, bottomRow(c, columns: 10)],
                              columns: 10)
    }

    /// 日文：打羅馬拼音，左下角是長音「ー」
    private static func japanese(_ c: Context) -> KeyboardLayout {
        func letters(_ s: String) -> [KeySpec] {
            s.map { KeySpec(face: .text(String($0)), action: .romaji($0), fontSize: 24) }
        }
        var row3 = [KeySpec(face: .text("ー"), action: .romaji("-"), width: 1.4, kind: .special, fontSize: 20)]
        row3 += letters("zxcvbnm")
        row3.append(backspace())
        return KeyboardLayout(rows: [letters("qwertyuiop"), letters("asdfghjkl"), row3, bottomRow(c, columns: 10)],
                              columns: 10)
    }

    /// 漢語拼音（照三星鍵盤）：最上面一排數字，左下角是分音節的「'」（例如 xi'an）
    private static func pinyin(_ c: Context) -> KeyboardLayout {
        func letters(_ s: String) -> [KeySpec] {
            s.map { KeySpec(face: .text(String($0)), action: .pinyin($0), fontSize: 24) }
        }
        var row3 = [KeySpec(face: .text("'"), action: .pinyin("'"), width: 1.4, kind: .special, fontSize: 22)]
        row3 += letters("zxcvbnm")
        row3.append(backspace())
        return KeyboardLayout(rows: [keys("1234567890", size: 20), letters("qwertyuiop"), letters("asdfghjkl"), row3, bottomRow(c, columns: 10)],
                              columns: 10)
    }

    /// 大顆的數字鍵盤（打電話號碼、金額用）：中間 1–9、0，兩邊常用符號
    private static func numpad(_ c: Context) -> KeyboardLayout {
        let back: String
        switch c.mode {
        case .zhuyin: back = "ㄅㄆㄇ"
        case .english: back = "ABC"
        case .handwriting: back = "手寫"
        case .korean: back = "한글"
        case .japanese: back = "かな"
        case .pinyin: back = "拼音"
        }
        func side(_ s: String) -> KeySpec { KeySpec(face: .text(s), action: .text(s), kind: .special, fontSize: 22) }
        return KeyboardLayout(rows: [
            [side("-")] + keys("123", size: 26) + [backspace(1)],
            [side("@")] + keys("456", size: 26) + [side(".")],
            [side(":")] + keys("789", size: 26) + [side(",")],
            [KeySpec(face: .text("!#1"), action: .layer(.numbers), kind: .special, fontSize: 16),
             KeySpec(face: .text(back), action: .layer(.letters), kind: .special, fontSize: 14)]
                + keys("0", size: 26)
                + [KeySpec(face: .symbol("space"), action: .space, kind: .special),
                   KeySpec(face: .symbol("return"), action: .returnKey, kind: .accent, fontSize: 15)],
        ], columns: 5)
    }

    private static func englishNumbers(_ c: Context) -> KeyboardLayout {
        var row3 = [KeySpec(face: .text("#+="), action: .layer(.symbols), width: 1.4, kind: .special, fontSize: 16)]
        row3 += keys(".,?!'", width: 1.4)
        row3.append(backspace())
        return KeyboardLayout(rows: [keys("1234567890"), keys("-/:;()$&@\""), keys(SymbolPages.englishNumberExtra), row3, bottomRow(c, columns: 10)],
                              columns: 10)
    }

    private static func englishSymbols(_ c: Context) -> KeyboardLayout {
        var row3 = [KeySpec(face: .text("123"), action: .layer(.numbers), width: 1.4, kind: .special, fontSize: 16)]
        row3 += keys(".,?!'", width: 1.4)
        row3.append(backspace())
        return KeyboardLayout(rows: [keys(SymbolPages.englishSymbolRow1), keys(SymbolPages.englishSymbolRow2), row3, bottomRow(c, columns: 10)],
                              columns: 10)
    }

    /// 注音的 123 頁，和 iPhone 注音鍵盤同一排列。全形時標點用全形；切成半形時括號、冒號、問號這些改半形。
    private static func chineseNumbers(_ c: Context) -> KeyboardLayout {
        var row3 = [KeySpec(face: .text("#+="), action: .layer(.symbols), width: 1.25, kind: .special, fontSize: 16)]
        row3 += keys(c.fullWidthSymbols ? SymbolPages.zhuyinNumberRow3 : SymbolPages.zhuyinNumberRow3Half, size: 20, width: 1.05)
        row3.append(KeySpec(face: .text(c.fullWidthSymbols ? "全形" : "半形"), action: .toggleWidth, width: 1.1, kind: .special, fontSize: 14))
        row3.append(backspace(1.35))
        return KeyboardLayout(rows: [keys("1234567890"), keys(c.fullWidthSymbols ? SymbolPages.zhuyinNumberRow2 : SymbolPages.zhuyinNumberRow2Half, size: 20),
                                     keys(SymbolPages.zhuyinNumberExtra, size: 20), row3, bottomRow(c, columns: 10)],
                              columns: 10)
    }

    /// 注音的 #+= 頁。Markdown 用的符號永遠半形；中文標點維持全形。全形切換不改這些鍵。
    private static func chineseSymbols(_ c: Context) -> KeyboardLayout {
        var row3 = [KeySpec(face: .text("123"), action: .layer(.numbers), width: 1.25, kind: .special, fontSize: 16)]
        row3 += keys("『』♡☆‧→※", size: 18, width: 0.9)
        row3.append(KeySpec(face: .text(c.fullWidthSymbols ? "全形" : "半形"), action: .toggleWidth, width: 1.1, kind: .special, fontSize: 14))
        row3.append(backspace(1.35))
        return KeyboardLayout(rows: [keys(SymbolPages.zhuyinSymbolRow1, size: 18),
                                     keys(SymbolPages.zhuyinSymbolRow2, size: 18),
                                     row3, bottomRow(c, columns: 10)],
                              columns: 10)
    }
}
