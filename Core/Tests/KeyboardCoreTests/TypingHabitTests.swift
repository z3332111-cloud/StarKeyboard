import XCTest
@testable import KeyboardCore

/// 使用者回報過的打字情境（要有打包流程產生的 zhuyin.sqlite 才會跑）。
final class TypingHabitTests: XCTestCase {
    private func engine() throws -> ZhuyinEngine {
        guard let url = Self.dictionaryURL(), let db = SQLiteDB(path: url.path) else {
            throw XCTSkip("沒有 zhuyin.sqlite，略過打字習慣測試")
        }
        return ZhuyinEngine(db: db, userModel: UserPhraseModel(fileURL: nil))
    }

    private func session(_ e: ZhuyinEngine, _ keys: String, context: String = "") -> ZhuyinSession {
        let s = ZhuyinSession()
        s.engine = e
        s.composer.validPrefixes = e.syllablePrefixes()
        s.composer.validSyllables = e.completeSyllables()
        for ch in keys { _ = s.type(ch) }
        s.refresh(context: context)
        return s
    }

    /// 單獨打的韻母（ㄢ）是完整的字「安」，前面的 ㄨㄢ 不能被當成兩個字的簡拼
    func testBareRhymeIsAWholeSyllable() throws {
        let e = try engine()
        let s = session(e, "ㄨㄢㄢ")
        XCTAssertEqual(s.composer.readings, ["ㄨㄢ*", "ㄢ*"])
        XCTAssertEqual(s.candidates.first?.text, "晚安")
        // 候選列不會再出現只吃掉 ㄨㄢ 的「晚安」（選了它再選「按」就會學成「晚安按」）
        let trap = s.candidates.filter { $0.span < 2 && $0.text.count > $0.span }.map { $0.text }
        XCTAssertTrue(trap.isEmpty, "\(trap)")
    }

    /// 同一個音連打好幾次是故意重複：晚安安安安不會被換成晚安按
    func testRepeatedSyllablesStayRepeated() throws {
        let e = try engine()
        let s = session(e, "ㄨㄢㄢㄢㄢㄢ")
        XCTAssertEqual(s.candidates.first?.text, "晚安安安安", "\(s.candidates.prefix(5).map { $0.text })")
    }

    /// 常選的單字（ㄏ 選「會」）不會把一長串的「哈哈哈」拆成「會會會」；只打一個 ㄏ 時「會」還是第一個
    func testFrequentSingleCharDoesNotBreakLongRuns() throws {
        let e = try engine()
        for _ in 0..<5 {
            e.learn(readings: ["ㄏ*"], text: "會")
            e.learn(readings: ["ㄏㄨㄟˋ"], text: "會")
        }
        for n in [2, 3, 6, 12, 13] {
            let s = session(e, String(repeating: "ㄏ", count: n))
            XCTAssertEqual(s.candidates.first?.text, String(repeating: "哈", count: n), "\(n): \(s.candidates.prefix(4).map { $0.text })")
        }
        XCTAssertEqual(session(e, "ㄏ").candidates.first?.text, "會")
    }

    /// 學過的單字在同音字裡還是會勝出（常選「妳」就是「妳」）
    func testLearnedSingleCharStillWinsAmongHomophones() throws {
        let e = try engine()
        for _ in 0..<3 { e.learn(readings: ["ㄋㄧˇ"], text: "妳") }
        XCTAssertEqual(session(e, "ㄋㄧˇ").candidates.first?.text, "妳")
        let best = e.bestSegments(["ㄋㄧˇ"]).map { $0.text }.joined()
        XCTAssertEqual(best, "妳")
    }

    /// 選過的字詞存成檔案，重新打開鍵盤（新的引擎讀同一個檔）還記得，而且排第一
    func testLearningSurvivesReopeningTheKeyboard() throws {
        guard let url = Self.dictionaryURL(), let db = SQLiteDB(path: url.path) else { throw XCTSkip("沒有字典") }
        let index = PhraseIndex.load(from: db)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("learned.json")

        let first = UserPhraseModel(fileURL: file, asynchronousWrites: true)
        let before = ZhuyinEngine(index: index, userModel: first)
        let s = session(before, "ㄌㄞˊㄕˋ")
        let pick = try XCTUnwrap(s.candidates.firstIndex { $0.text == "來" }, "\(s.candidates.prefix(8).map { $0.text })")
        _ = s.pick(pick, learn: true)
        s.refresh(context: "來")
        let next = try XCTUnwrap(s.candidates.firstIndex { $0.text == "是" })
        _ = s.pick(next, learn: true)
        first.flushPendingWrites()
        XCTAssertNil(first.summary().problem)
        XCTAssertGreaterThan(first.summary().count, 0)

        let reopened = ZhuyinEngine(index: index, userModel: UserPhraseModel(fileURL: file))
        XCTAssertEqual(session(reopened, "ㄌㄞˊㄕˋ").candidates.first?.text, "來是")
        XCTAssertEqual(session(reopened, "ㄌㄞㄕ").candidates.first?.text, "來是")
        XCTAssertTrue(reopened.userModel.summary().recent.contains("來是"))
    }

    /// 舊版學到的「晚安按」不會再蓋過晚安
    func testOldSplitLearningDoesNotWin() throws {
        let e = try engine()
        e.learn(readings: ["ㄨㄢ*~", "ㄢ*"], text: "晚安按")
        XCTAssertEqual(session(e, "ㄨㄢㄢ").candidates.first?.text, "晚安")
    }

    /// 沒打聲調時學過的詞要排前面（ㄌㄞ 後面接 ㄕ，組字器會標成可能是簡拼，以前因此對不上學習紀錄）
    func testLearnedPhraseWinsWhenTypingWithoutTones() throws {
        let e = try engine()
        e.learn(readings: ["ㄌㄞˊ", "ㄕˋ"], text: "來是")
        let s = session(e, "ㄌㄞㄕ")
        XCTAssertEqual(s.candidates.first?.text, "來是", "\(s.composer.readings) \(s.candidates.prefix(5).map { $0.text })")
    }

    /// 選過的單字、雙字詞排在第二個開始，完整符合的詞仍是第一個
    func testLearnedWordsComeRightAfterTheFullMatch() throws {
        let e = try engine()
        e.learn(readings: ["ㄨㄢˇ"], text: "晚")
        let s = session(e, "ㄨㄢˇㄢ")
        XCTAssertEqual(s.candidates.first?.text, "晚安")
        XCTAssertEqual(s.candidates.dropFirst().first?.text, "晚")
    }

    /// 聯想：不推薦地名（淡水、淡水河、淡江大學），自己打過的最前面
    func testAssociationsSkipPlacesAndPreferHabits() throws {
        let e = try engine()
        let plain = e.associations(after: "淡")
        for place in ["水", "水河", "江", "江大學", "水線"] {
            XCTAssertFalse(plain.contains(place), "\(place) in \(plain.prefix(10))")
        }
        XCTAssertTrue(plain.contains("淡"), "\(plain.prefix(10))")
        e.learn(readings: ["ㄉㄢˋ", "ㄉㄧㄥˋ"], text: "淡定")
        XCTAssertEqual(e.associations(after: "淡").first, "定")
        e.learn(readings: ["ㄉㄢˋ", "ㄕㄨㄟˇ"], text: "淡水")
        XCTAssertTrue(e.associations(after: "淡").contains("水"))
        XCTAssertTrue(PlaceNames.isPlace("淡江大學"))
        XCTAssertFalse(PlaceNames.isPlace("超市"))
        XCTAssertFalse(PlaceNames.isPlace("晚安"))
    }

    private static func dictionaryURL() -> URL? {
        if let env = ProcessInfo.processInfo.environment["TYPING_DICTIONARY"] {
            let url = URL(fileURLWithPath: env)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        var url = URL(fileURLWithPath: #file).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = url.appendingPathComponent("Keyboard/Resources/zhuyin.sqlite")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            url.deleteLastPathComponent()
        }
        return nil
    }
}
