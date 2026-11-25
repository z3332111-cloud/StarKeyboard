import XCTest
@testable import KeyboardCore

final class TypingRegressionTests: XCTestCase {
    private func engine() -> ZhuyinEngine {
        let db = SQLiteDB.inMemory()!
        ZhuyinEngine.createSchema(in: db)
        for (reading, phrase, score) in [
            ("ㄋㄧˇ", "你", -2.0), ("ㄋㄠˇ", "腦", -5.0),
            ("ㄕ", "詩", -7.0), ("ㄕˋ", "是", -2.0),
            ("ㄏㄠˇ", "好", -3.0), ("ㄋㄧˇ-ㄏㄠˇ", "你好", -4.0),
            ("ㄋㄠˇ-ㄌㄧˋ", "腦力", -5.0)
        ] { ZhuyinEngine.insert(into: db, reading: reading, phrase: phrase, score: score) }
        return ZhuyinEngine(db: db, userModel: UserPhraseModel(fileURL: nil))
    }

    func testNarrowingReadingDoesNotReuseIncompatibleLearnedCandidate() {
        let e = engine()
        for _ in 0..<5 { e.learn(readings: ["ㄋ*"], text: "你") }
        XCTAssertEqual(e.candidates(for: ["ㄋ*"]).first?.text, "你")
        XCTAssertEqual(e.candidates(for: ["ㄋㄠ*"]).first?.text, "腦")
        XCTAssertFalse(e.phrases(["ㄋㄠ*"]).contains { $0.text == "你" })
        XCTAssertFalse(e.candidates(for: ["ㄋㄠ*"]).contains { $0.text == "你好" })
        // 刪回較寬的注音，原本的選字偏好仍在。
        XCTAssertEqual(e.candidates(for: ["ㄋ*"]).first?.text, "你")
    }

    func testExactToneStaysAheadOfFrequentLearnedCorrection() {
        let e = engine()
        for _ in 0..<5 { e.learn(readings: ["ㄕˋ"], text: "是") }
        let choices = e.candidates(for: ["ㄕ"])
        XCTAssertEqual(choices.first?.text, "詩")
        XCTAssertTrue(choices.contains { $0.text == "是" })
        XCTAssertEqual(e.candidates(for: ["ㄕˋ"]).first?.text, "是")
        XCTAssertEqual(e.candidates(for: ["ㄕ", "ㄏㄠˇ"]).first?.text, "詩好")
    }

    func testIndexedLearningMatchesAcrossPrefixesAndResets() {
        let model = UserPhraseModel(fileURL: nil)
        model.record(reading: "ㄋㄧˇ", phrase: "妳")
        model.record(reading: "ㄋ*", phrase: "妳")
        model.record(reading: "ㄋㄠˇ", phrase: "腦")
        XCTAssertEqual(model.phrases(for: "ㄋㄧ*"), ["妳"])
        XCTAssertEqual(model.phrases(for: "ㄋㄠ*"), ["腦"])
        XCTAssertEqual(model.phrases(for: "ㄋㄧˋ"), [])
        XCTAssertGreaterThan(model.boost(reading: "ㄋㄧˇ", phrase: "妳"), 0)
        _ = model.learnedPhrases()
        model.reset()
        XCTAssertTrue(model.phrases(for: "ㄋ*").isEmpty)
        XCTAssertTrue(model.learnedPhrases().isEmpty)
        XCTAssertEqual(model.boost(reading: "ㄋㄧˇ", phrase: "妳"), 0)
    }

    func testQueuedLearningPersistsLatestStateIncludingReset() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("learned.json")
        let model = UserPhraseModel(fileURL: url, asynchronousWrites: true)
        for _ in 0..<20 { model.record(reading: "ㄋㄧˇ", phrase: "妳") }
        model.reset()
        model.record(reading: "ㄏㄠˇ", phrase: "好")
        model.flushPendingWrites()
        let reloaded = UserPhraseModel(fileURL: url)
        XCTAssertTrue(reloaded.phrases(for: "ㄋㄧˇ").isEmpty)
        XCTAssertEqual(reloaded.phrases(for: "ㄏㄠ*"), ["好"])
        XCTAssertTrue(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    /// 朋友回報：快速打字時拇指碰到空白鍵，ㄐ 被單獨收起來（我覺得 → 我居約得）
    func testAccidentalSpaceInsideSyllableIsUndone() {
        func composer() -> ZhuyinComposer {
            var c = ZhuyinComposer()
            c.validPrefixes = ["ㄐ", "ㄐㄩ", "ㄐㄩㄝ", "ㄩ", "ㄩㄝ", "ㄩㄢ", "ㄢ"]
            c.validSyllables = ["ㄐㄩ", "ㄐㄩㄝ", "ㄩ", "ㄩㄝ", "ㄩㄢ", "ㄢ"]
            return c
        }
        // ㄐ 不能單獨念：空白之後再打 ㄩㄝ，不管隔多久都接回去
        var a = composer()
        a.input("ㄐ", at: 0); a.confirmSyllable(at: 0.1); a.input("ㄩ", at: 5); a.input("ㄝ", at: 5.1)
        XCTAssertEqual(a.readings, ["ㄐㄩㄝ*"])
        // ㄩ 可以單獨念：空白後很快就打 ㄢ，是不小心碰到的
        var b = composer()
        b.input("ㄩ", at: 0); b.confirmSyllable(at: 0.1); b.input("ㄢ", at: 0.2)
        XCTAssertEqual(b.readings, ["ㄩㄢ*"])
        // 隔一陣子才打：使用者真的要一聲的 ㄩ
        var c = composer()
        c.input("ㄩ", at: 0); c.confirmSyllable(at: 0.1); c.input("ㄢ", at: 1.5)
        XCTAssertEqual(c.readings, ["ㄩ", "ㄢ*"])
    }

    /// 朋友的打字紀錄：ㄍㄞ ㄒ 按成 ㄝ，刪掉再打 ㄩㄝ，「學」被拆成「小月」
    func testRetypingAfterBackspaceJoinsPreviousSyllable() {
        var c = ZhuyinComposer()
        c.validPrefixes = ["ㄍ", "ㄍㄞ", "ㄒ", "ㄒㄩ", "ㄒㄩㄝ", "ㄝ", "ㄩ", "ㄩㄝ"]
        for k in "ㄍㄞㄒㄝ" { c.input(k) }
        XCTAssertEqual(c.readings.count, 3)   // ㄒ 和 ㄝ 拼不起來
        c.backspace()
        for k in "ㄩㄝ" { c.input(k) }
        XCTAssertEqual(c.readings.map { $0.replacingOccurrences(of: "~", with: "") }, ["ㄍㄞ*", "ㄒㄩㄝ*"])
    }

    /// ㄒ 後面不小心按到聲調，接著打的 ㄩㄝ 還是同一個字
    func testStrayToneOnImpossibleSyllableIsDropped() {
        var c = ZhuyinComposer()
        c.validPrefixes = ["ㄒ", "ㄒㄩ", "ㄒㄩㄝ"]
        c.validSyllables = ["ㄒㄩㄝ"]
        for k in "ㄒ˙ㄩㄝ" { c.input(k) }
        XCTAssertEqual(c.readings.map { $0.replacingOccurrences(of: "~", with: "") }, ["ㄒㄩㄝ*"])
    }
    func testTypedSoundsBeatNeighborKeyGuesses() {
        let db = SQLiteDB.inMemory()!
        ZhuyinEngine.createSchema(in: db)
        for (reading, phrase, score) in [
            ("ㄉㄨㄛ", "多", -3.0), ("ㄌㄜ˙", "了", -2.0), ("ㄉㄜˊ", "得", -3.0), ("ㄉㄜˊ-ㄌㄜ˙", "得了", -4.0),
            ("ㄉㄨㄟˋ-ㄌㄜ˙", "對了", -4.0), ("ㄉㄨㄛ-ㄌㄩˋ", "多氯", -6.0),
            ("ㄨㄛˇ", "我", -2.0), ("ㄐㄧㄤˋ", "降", -4.0), ("ㄧˇ", "以", -2.5), ("ㄧˇ-ㄐㄧㄤˋ", "以降", -5.0),
            ("ㄨㄚˇ-ㄐㄧㄤˋ", "瓦匠", -6.0)
        ] { ZhuyinEngine.insert(into: db, reading: reading, phrase: phrase, score: score) }
        let e = ZhuyinEngine(db: db, userModel: UserPhraseModel(fileURL: nil))
        // 每個音都打對了：照打的音湊句子，不換成猜按錯鍵的詞
        XCTAssertEqual(e.candidates(for: ["ㄉㄨㄛ*", "ㄌㄜ*"]).first?.text, "多了")
        XCTAssertEqual(e.candidates(for: ["ㄨㄛˇ", "ㄐㄧㄤˋ"]).first?.text, "我降")
        // 單字「多」「我」排在猜錯字的詞前面
        let list = e.candidates(for: ["ㄉㄨㄛ*", "ㄌㄜ*"]).map { $0.text }
        XCTAssertLessThan(list.firstIndex(of: "多")!, list.firstIndex(of: "得了") ?? Int.max)
        let list2 = e.candidates(for: ["ㄨㄛˇ", "ㄐㄧㄤˋ"]).map { $0.text }
        XCTAssertLessThan(list2.firstIndex(of: "我")!, list2.firstIndex(of: "以降") ?? Int.max)
    }
}
