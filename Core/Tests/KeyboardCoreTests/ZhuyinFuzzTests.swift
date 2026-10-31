import XCTest
@testable import KeyboardCore

/// 隨機按鍵、插隊、空白、換行、選字、換鍵盤。送出的字不能有聲調或注音，除非是符號鍵。
final class ZhuyinFuzzTests: XCTestCase {
    func testThousandsOfKeySequencesNeverCommitPhonetics() {
        let engine = Self.engine()
        let session = ZhuyinSession()
        session.engine = engine
        var document = ""
        var state: UInt64 = 0xC0FFEE
        let keys = Array("ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙㄧㄨㄩㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦˊˇˋ˙")
        func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1
            return state
        }
        for _ in 0..<4000 {
            switch next() % 14 {
            case 0:
                if !session.backspace(), !document.isEmpty { document.removeLast() }
            case 1:
                session.refresh(context: document)
                switch session.space() {
                case .passthrough: document.append(" ")
                case .stay: break
                case .commit(let text): document += text
                }
            case 2:
                document += session.enter()
            case 3:
                session.refresh(context: document)
                document += session.pick(0, learn: true)
            case 4:
                document += session.commitAll()
            case 5:
                // 聲調比字母先到，模擬觸控順序被打亂。
                document += session.type("ˋ")
                document += session.type(keys[Int(next() % UInt64(keys.count))])
            default:
                document += session.type(keys[Int(next() % UInt64(keys.count))])
            }
            XCTAssertFalse(PhoneticText.containsPhonetic(document), document)
        }
        document += session.enter()
        XCTAssertFalse(PhoneticText.containsPhonetic(document), document)
        XCTAssertEqual(session.insertSymbol("ˋ"), "ˋ")
        XCTAssertTrue(PhoneticText.containsPhonetic(session.insertSymbol("ㄅ")))
    }

    func testClipboardEditKeepsOriginalUntilSave() {
        let store = ClipboardStore(fileURL: nil)
        XCTAssertTrue(store.add("原來的文字"))
        let id = store.items[0].id
        XCTAssertFalse(store.updateText(id, "   "))
        XCTAssertEqual(store.items[0].text, "原來的文字")
        XCTAssertTrue(store.updateText(id, "改過了"))
        XCTAssertEqual(store.items[0].id, id)
        XCTAssertEqual(store.items[0].text, "改過了")
    }

    func testCandidateBarHeightClampsAndScalesFont() {
        XCTAssertEqual(CandidateBarMetrics.clamp(10), CandidateBarMetrics.minHeight)
        XCTAssertEqual(CandidateBarMetrics.clamp(200), CandidateBarMetrics.maxHeight)
        XCTAssertEqual(CandidateBarMetrics.clamp(64), 64)
        XCTAssertEqual(CandidateBarMetrics.fontSize(barHeight: 64), 24, accuracy: 0.001)
        XCTAssertGreaterThan(CandidateBarMetrics.fontSize(barHeight: 96), 24)
    }

    private static func engine() -> ZhuyinEngine {
        let db = SQLiteDB.inMemory()!
        ZhuyinEngine.createSchema(in: db)
        let rows = [
            ("ㄓㄜˋ", "這", -2.6), ("ㄧㄤˋ", "樣", -3.0), ("ㄓㄜˋ-ㄧㄤˋ", "這樣", -3.5),
            ("ㄉㄜ˙", "的", -1.8), ("ㄐㄩˋ", "句", -3.2), ("ㄗ˙", "子", -2.8),
            ("ㄐㄩˋ-ㄗ˙", "句子", -3.4), ("ㄨㄛˇ", "我", -2.2), ("ㄕˋ", "是", -1.6),
            ("ㄕˋ", "試", -3.4), ("ㄎㄢˋ", "看", -2.5),
        ]
        for row in rows { ZhuyinEngine.insert(into: db, reading: row.0, phrase: row.1, score: row.2) }
        return ZhuyinEngine(db: db, userModel: UserPhraseModel(fileURL: nil))
    }
}
