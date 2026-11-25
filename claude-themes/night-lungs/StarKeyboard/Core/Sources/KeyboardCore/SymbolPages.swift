import Foundation

/// 符號頁要送出的字。程式／Markdown 用的符號一律半形，中文標點維持全形。
enum SymbolPages {
    /// 這些字在注音與英文符號頁都必須是 ASCII，全形切換不能改掉。
    static let markdown: [Character] = Array("`*_~|#\\^+=[]{}<>%")

    static let zhuyinSymbolRow1 = "`*_~|#\\^+="
    static let zhuyinSymbolRow2 = "{[]<>%}～—…"
    static let zhuyinNumberRow2 = "-/：；（）$@「」"
    static let zhuyinNumberRow3 = "。，、？！."
    /// 切成「半形」時：括號、冒號、分號、問號、驚嘆號改用半形（寫程式、英文混打用）
    static let zhuyinNumberRow2Half = "-/:;()$@「」"
    static let zhuyinNumberRow3Half = "。，、?!."
    /// 123 頁的第三排（像三星鍵盤三排標點）
    static let zhuyinNumberExtra = "+×÷=%&*#_~"
    static let englishNumberExtra = "+×÷=%_<>#*"
    static let englishSymbolRow1 = "[]{}#%^*+="
    static let englishSymbolRow2 = "_\\|~<>€£¥`"

    static func isASCII(_ c: Character) -> Bool {
        c.unicodeScalars.count == 1 && (c.unicodeScalars.first?.value ?? 128) < 128
    }
}
