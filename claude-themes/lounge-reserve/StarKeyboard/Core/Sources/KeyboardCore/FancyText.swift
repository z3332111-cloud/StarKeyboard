import Foundation

/// 花式文字：把字換成 Unicode 裡長得不一樣的字母，或加上線條、外框。
/// 傳出去對方也看得到（不是字體，是不同的字）。和 Android 版 FancyText.kt 一樣。
enum FancyText {
    private static let smallCaps = Array("ᴀʙᴄᴅᴇꜰɢʜɪᴊᴋʟᴍɴᴏᴘǫʀꜱᴛᴜᴠᴡxʏᴢ".unicodeScalars)
    private static let upsideDownLetters = Array("ɐqɔpǝɟƃɥᴉɾʞlɯuodbɹsʇnʌʍxʎz".unicodeScalars)

    struct Style {
        let name: String
        let convert: (String) -> String
    }

    static let styles: [Style] = [
        Style(name: "草寫") { FancyText.letters($0, upper: 0x1D4D0, lower: 0x1D4EA, digit: nil) },
        Style(name: "粗體") { FancyText.letters($0, upper: 0x1D5D4, lower: 0x1D5EE, digit: 0x1D7EC) },
        Style(name: "斜體") { FancyText.letters($0, upper: 0x1D608, lower: 0x1D622, digit: nil) },
        Style(name: "哥德") { FancyText.letters($0, upper: 0x1D56C, lower: 0x1D586, digit: nil) },
        Style(name: "打字機") { FancyText.letters($0, upper: 0x1D670, lower: 0x1D68A, digit: 0x1D7F6) },
        Style(name: "圈圈") { FancyText.circled($0) },
        Style(name: "黑圈") { FancyText.map($0) { FancyText.letterIndex($0).map { 0x1F150 + $0 } } },
        Style(name: "方塊") { FancyText.map($0) { FancyText.letterIndex($0).map { 0x1F170 + $0 } } },
        Style(name: "小型大寫") { FancyText.map($0) { FancyText.letterIndex($0).map { FancyText.smallCaps[Int($0)].value } } },
        Style(name: "全形") { FancyText.fullWidth($0) },
        Style(name: "倒過來") { FancyText.upsideDown($0) },
        Style(name: "刪除線") { FancyText.combine($0, "\u{0336}") },
        Style(name: "底線") { FancyText.combine($0, "\u{0332}") },
        Style(name: "波浪") { FancyText.combine($0, "\u{0330}") },
        Style(name: "愛心") { "♡ \($0) ♡" },
        Style(name: "閃亮") { "✧ \($0) ✧" },
        Style(name: "星星") { "⋆｡˚ \($0) ˚｡⋆" },
        Style(name: "花花") { "✿ \($0) ✿" },
        Style(name: "括號") { "꒰ \($0) ꒱" },
        Style(name: "標題") { "【\($0)】" },
        Style(name: "一字一星") { FancyText.spaced($0, " ✦ ") },
    ]

    /// 所有和原文不一樣的樣式（文字沒有英文字母時，英文樣式就不會出現）
    static func variants(_ text: String) -> [String] {
        var seen = Set<String>()
        return styles.map { $0.convert(text) }.filter { $0 != text && seen.insert($0).inserted }
    }

    /// a～z、A～Z → 0～25
    private static func letterIndex(_ s: Unicode.Scalar) -> UInt32? {
        switch s.value {
        case 0x41...0x5A: return s.value - 0x41
        case 0x61...0x7A: return s.value - 0x61
        default: return nil
        }
    }

    private static func map(_ text: String, _ f: (Unicode.Scalar) -> UInt32?) -> String {
        var out = String.UnicodeScalarView()
        for s in text.unicodeScalars {
            if let v = f(s), let m = Unicode.Scalar(v) { out.append(m) } else { out.append(s) }
        }
        return String(out)
    }

    private static func letters(_ text: String, upper: UInt32, lower: UInt32, digit: UInt32?) -> String {
        map(text) { s in
            switch s.value {
            case 0x41...0x5A: return upper + s.value - 0x41
            case 0x61...0x7A: return lower + s.value - 0x61
            case 0x30...0x39: return digit.map { $0 + s.value - 0x30 }
            default: return nil
            }
        }
    }

    private static func circled(_ text: String) -> String {
        map(text) { s in
            switch s.value {
            case 0x41...0x5A: return 0x24B6 + s.value - 0x41
            case 0x61...0x7A: return 0x24D0 + s.value - 0x61
            case 0x30: return 0x24EA
            case 0x31...0x39: return 0x2460 + s.value - 0x31
            default: return nil
            }
        }
    }

    private static func fullWidth(_ text: String) -> String {
        map(text) { s in
            switch s.value {
            case 0x20: return 0x3000
            case 0x21...0x7E: return 0xFF01 + s.value - 0x21
            default: return nil
            }
        }
    }

    private static func upsideDown(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { letterIndex($0) != nil }) else { return text }
        return map(String(text.reversed())) { letterIndex($0).map { upsideDownLetters[Int($0)].value } }
    }

    /// 每個字後面加一個組合符號（刪除線、底線…），中文也可以
    private static func combine(_ text: String, _ mark: Unicode.Scalar) -> String {
        var out = String.UnicodeScalarView()
        for s in text.unicodeScalars {
            out.append(s)
            if !s.properties.isWhitespace { out.append(mark) }
        }
        return String(out)
    }

    private static func spaced(_ text: String, _ sep: String) -> String {
        let chars = text.unicodeScalars.filter { !$0.properties.isWhitespace }.map { String($0) }
        return chars.count < 2 ? text : chars.joined(separator: sep)
    }
}

/// 快捷片語：打縮寫（中文、英文都可以）就跳出整段常用的話
final class ShortcutStore {
    struct Item: Codable, Equatable {
        var code: String
        var phrase: String
    }

    private(set) var items: [Item] = []
    private let fileURL: URL?

    init(fileURL: URL?) {
        self.fileURL = fileURL
        load()
    }

    func load() {
        if let url = fileURL, let saved = JSONFile.load([Item].self, from: url) { items = saved }
    }

    func add(code: String, phrase: String) {
        let c = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty, !phrase.isEmpty else { return }
        items.removeAll { $0.code == c && $0.phrase == phrase }
        items.insert(Item(code: c, phrase: phrase), at: 0)
        save()
    }

    func remove(_ item: Item) {
        items.removeAll { $0 == item }
        save()
    }

    /// 縮寫完全一樣的片語（英文不分大小寫）
    func matching(_ text: String) -> [String] {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return [] }
        return items.filter { $0.code.caseInsensitiveCompare(t) == .orderedSame }.map { $0.phrase }
    }

    private func save() {
        if let url = fileURL { JSONFile.save(items, to: url) }
    }
}
