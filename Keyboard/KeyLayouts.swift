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

enum KeyboardLayer { case letters, numbers, symbols }
enum ShiftState { case off, on, locked }
enum PanelKind: String { case emoji, kaomoji, symbols, clipboard, settings }

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
}

enum KeyFace: Equatable {
    case text(String)
    case symbol(String)   // SF Symbols 圖示
}

enum KeyKind { case normal, special, accent }

struct KeySpec {
    var face: KeyFace
    var action: KeyAction
    /// 以「一個字母鍵」為單位；0 = 填滿剩下的寬度
    var width: CGFloat = 1
    var kind: KeyKind = .normal
    var fontSize: CGFloat = 23
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
            [KeySpec(face: .text(returnTitle), action: .returnKey, kind: .accent, fontSize: 15)],
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
        if c.layer == .letters {
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
        row.append(KeySpec(face: .text(c.nextModeTitle), action: .nextMode, width: 1.1 * k, kind: .special, fontSize: 17))
        if !c.needsGlobe {
            row.append(KeySpec(face: .symbol("face.smiling"), action: .panel(.emoji), width: 1.1 * k, kind: .special))
        }
        row.append(KeySpec(face: .text(c.spaceTitle), action: .space, width: 0, fontSize: 15))
        row.append(KeySpec(face: .text(c.returnTitle), action: .returnKey, width: 2.0 * k, kind: .accent, fontSize: 16))
        return row
    }

    private static func zhuyin(_ c: Context) -> KeyboardLayout {
        var rows: [[KeySpec]] = Bopomofo.dachenRows.map { line in
            line.map { ch in KeySpec(face: .text(String(ch)), action: .zhuyin(ch), fontSize: 20) }
        }
        rows[3].append(backspace(1))
        rows.append(bottomRow(c, columns: 11))
        return KeyboardLayout(rows: rows, columns: 11)
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

    /// 漢語拼音：左下角是分音節的「'」（例如 xi'an）
    private static func pinyin(_ c: Context) -> KeyboardLayout {
        func letters(_ s: String) -> [KeySpec] {
            s.map { KeySpec(face: .text(String($0)), action: .pinyin($0), fontSize: 24) }
        }
        var row3 = [KeySpec(face: .text("'"), action: .pinyin("'"), width: 1.4, kind: .special, fontSize: 22)]
        row3 += letters("zxcvbnm")
        row3.append(backspace())
        return KeyboardLayout(rows: [letters("qwertyuiop"), letters("asdfghjkl"), row3, bottomRow(c, columns: 10)],
                              columns: 10)
    }

    private static func englishNumbers(_ c: Context) -> KeyboardLayout {
        var row3 = [KeySpec(face: .text("#+="), action: .layer(.symbols), width: 1.4, kind: .special, fontSize: 16)]
        row3 += keys(".,?!'", width: 1.4)
        row3.append(backspace())
        return KeyboardLayout(rows: [keys("1234567890"), keys("-/:;()$&@\""), row3, bottomRow(c, columns: 10)],
                              columns: 10)
    }

    private static func englishSymbols(_ c: Context) -> KeyboardLayout {
        var row3 = [KeySpec(face: .text("123"), action: .layer(.numbers), width: 1.4, kind: .special, fontSize: 16)]
        row3 += keys(".,?!'", width: 1.4)
        row3.append(backspace())
        return KeyboardLayout(rows: [keys(SymbolPages.englishSymbolRow1), keys(SymbolPages.englishSymbolRow2), row3, bottomRow(c, columns: 10)],
                              columns: 10)
    }

    /// 注音的 123 頁，和 iPhone 注音鍵盤同一排列。標點用全形，減號、斜線、錢號、小老鼠和句點用半形。
    private static func chineseNumbers(_ c: Context) -> KeyboardLayout {
        var row3 = [KeySpec(face: .text("#+="), action: .layer(.symbols), width: 1.4, kind: .special, fontSize: 16)]
        row3 += keys(SymbolPages.zhuyinNumberRow3, size: 20, width: 1.2)
        row3.append(backspace())
        return KeyboardLayout(rows: [keys("1234567890"), keys(SymbolPages.zhuyinNumberRow2, size: 20), row3, bottomRow(c, columns: 10)],
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
