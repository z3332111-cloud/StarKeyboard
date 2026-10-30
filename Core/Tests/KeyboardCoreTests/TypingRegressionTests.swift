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
}
