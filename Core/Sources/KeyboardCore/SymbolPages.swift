import Foundation

/// 符號頁要送出的字。程式／Markdown 用的符號一律半形，中文標點維持全形。
enum SymbolPages {
    /// 這些字在注音與英文符號頁都必須是 ASCII，全形切換不能改掉。
    static let markdown: [Character] = Array("`*_~|#\\^+=[]{}<>%")

    static let zhuyinSymbolRow1 = "`*_~|#\\^+="
    static let zhuyinSymbolRow2 = "{[]<>%}～—…"
    static let zhuyinNumberRow2 = "-/：；（）$@「」"
    static let zhuyinNumberRow3 = "。，、？！."
    static let englishSymbolRow1 = "[]{}#%^*+="
    static let englishSymbolRow2 = "_\\|~<>€£¥`"

    static func isASCII(_ c: Character) -> Bool {
        c.unicodeScalars.count == 1 && (c.unicodeScalars.first?.value ?? 128) < 128
    }
}
