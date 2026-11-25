import XCTest
@testable import KeyboardCore

/// 打注音打到一半，游標移到中間只改打錯的那一個（像 iPhone 內建注音）
final class ZhuyinCursorTests: XCTestCase {
    private func typed(_ s: String) -> ZhuyinSession {
        let session = ZhuyinSession()
        for c in s { if c == " " { _ = session.space() } else { _ = session.type(c) } }
        return session
    }

    func testReplayingKeysGivesSameComposer() {
        for s in ["ㄐㄧㄤˋㄕˋㄓㄜˋ ㄧㄤˋ", "ㄋㄏ", "ㄋㄧˇㄏㄠˇ", "ㄓㄜ ㄧㄤ", "ㄎㄞㄒ", "ˇ"] {
            let a = typed(s).composer
            var b = ZhuyinComposer()
            b.replay(a.keys)
            XCTAssertEqual(b.readings, a.readings, s)
            XCTAssertEqual(b.displayText, a.displayText, s)
        }
    }

    func testFixFirstSymbolInTheMiddle() {
        let session = typed("ㄐㄧㄤˋㄕˋ")
        let n = session.composer.keys.count
        session.moveCursor(-n)
        XCTAssertEqual(session.cursor, 0)
        session.moveCursor(1)                 // 游標移到 ㄐ 後面
        XCTAssertTrue(session.backspace())    // 刪掉 ㄐ
        _ = session.type("ㄒ")                // 改打 ㄒ
        XCTAssertEqual(session.composer.readings, ["ㄒㄧㄤˋ", "ㄕˋ"])
        XCTAssertEqual(session.cursor, 1)
        XCTAssertEqual(session.displayText, "ㄒ▏ㄧㄤˋㄕˋ")
    }

    func testCursorBackAtEndTypesNormally() {
        let session = typed("ㄋㄧˇ")
        session.moveCursor(-1)
        XCTAssertNotNil(session.cursor)
        session.moveCursor(5)
        XCTAssertNil(session.cursor)
        _ = session.type("ㄏ")
        XCTAssertEqual(session.composer.displayText, "ㄋㄧˇ ㄏ")
    }

    func testBackspaceAtStartDoesNothing() {
        let session = typed("ㄋㄧˇ")
        session.moveCursor(-10)
        XCTAssertTrue(session.backspace())
        XCTAssertEqual(session.composer.readings, ["ㄋㄧˇ"])
    }

    func testCursorClearsWhenCompositionEnds() {
        let session = typed("ㄋㄧˇ")
        session.moveCursor(-1)
        _ = session.commitAll()
        XCTAssertNil(session.cursor)
        XCTAssertFalse(session.moveCursor(-1))
    }
}
