import XCTest
@testable import KeyboardCore

final class SymbolPageTests: XCTestCase {
    func testMarkdownSymbolsAreASCII() {
        let required = SymbolPages.markdown
        XCTAssertEqual(required, Array("`*_~|#\\^+=[]{}<>%"))
        for ch in required {
            XCTAssertTrue(SymbolPages.isASCII(ch), "\(ch) 必須是半形 ASCII")
        }
        let zhuyin = SymbolPages.zhuyinSymbolRow1 + SymbolPages.zhuyinSymbolRow2
        let english = SymbolPages.englishSymbolRow1 + SymbolPages.englishSymbolRow2
        let numbers = SymbolPages.zhuyinNumberRow2 + SymbolPages.zhuyinNumberRow3
        for ch in required {
            XCTAssertTrue(zhuyin.contains(ch), "注音 #+= 缺少 \(ch)")
            XCTAssertTrue(english.contains(ch) || numbers.contains(ch), "英文符號頁或 123 頁缺少 \(ch)")
        }
        for ch in Array("-/$@.") {
            XCTAssertTrue(SymbolPages.isASCII(ch))
            XCTAssertTrue(numbers.contains(ch), "注音 123 頁的 \(ch) 必須是半形")
        }
        for ch in Array("，。、？！：；「」") {
            XCTAssertFalse(SymbolPages.isASCII(ch))
            XCTAssertTrue((SymbolPages.zhuyinNumberRow2 + SymbolPages.zhuyinNumberRow3).contains(ch))
        }
        XCTAssertEqual(SymbolPages.zhuyinSymbolRow1.count, 10)
        XCTAssertEqual(SymbolPages.zhuyinSymbolRow2.count, 10)
        XCTAssertEqual(SymbolPages.zhuyinNumberRow2.count, 10)
        XCTAssertEqual(SymbolPages.englishSymbolRow2.count, 10)
        XCTAssertFalse(zhuyin.contains("＊"))
        XCTAssertFalse(zhuyin.contains("＃"))
        XCTAssertFalse(zhuyin.contains("｜"))
    }
}
