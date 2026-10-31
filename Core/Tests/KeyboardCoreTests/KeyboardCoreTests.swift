import XCTest
@testable import KeyboardCore

final class ZhuyinComposerTests: XCTestCase {
    func testDisplayedReadingFollowsInputDeletionAndSelection() {
        var c = ZhuyinComposer()
        XCTAssertEqual(c.displayText, "")
        for ch in "ㄋㄧˇㄏㄠ" { c.input(ch) }
        XCTAssertEqual(c.displayText, "ㄋㄧˇ ㄏㄠ")
        c.backspace()
        XCTAssertEqual(c.displayText, "ㄋㄧˇ ㄏ")
        c.removeFirst(1)
        XCTAssertEqual(c.displayText, "ㄏ")
        c.clear()
        XCTAssertEqual(c.displayText, "")
        // 聲調比音節先到會先留著，但不會顯示，也不算正在組字。
        XCTAssertTrue(c.input("ˇ"))
        XCTAssertFalse(c.isComposing)
        XCTAssertEqual(c.displayText, "")
    }

    func testDisplayedAbbreviationKeepsTypedSoundsWithoutQueryMarkers() {
        var c = ZhuyinComposer()
        for ch in "ㄏㄎㄞ" { c.input(ch) }
        XCTAssertEqual(c.readings, ["ㄏ*", "ㄎㄞ*~"])
        XCTAssertEqual(c.displayText, "ㄏ ㄎㄞ")
        c.confirmSyllable()
        XCTAssertEqual(c.displayText, "ㄏ ㄎㄞ")
        c.removeFirst(1)
        XCTAssertEqual(c.displayText, "ㄎㄞ")
        c.clear()
        for ch in "ㄉㄜ˙" { c.input(ch) }
        XCTAssertEqual(c.displayText, "ㄉㄜ˙")
    }

    func testTonesFinishSyllables() {
        var c = ZhuyinComposer()
        for ch in "ㄋㄧˇㄏㄠˇ" { XCTAssertTrue(c.input(ch)) }
        XCTAssertEqual(c.readings, ["ㄋㄧˇ", "ㄏㄠˇ"])
        XCTAssertFalse(c.hasPendingSyllable)
    }

    func testSpaceIsFirstTone() {
        var c = ZhuyinComposer()
        c.input("ㄇ")
        c.input("ㄚ")
        XCTAssertTrue(c.confirmSyllable())
        XCTAssertEqual(c.readings, ["ㄇㄚ"])
    }

    func testNextSymbolStartsNewSyllable() {
        // 沒打聲調就打下一個字：前一個字自動結束，正在打的字也算進去
        var c = ZhuyinComposer()
        for ch in "ㄅㄆㄚˋ" { c.input(ch) }
        XCTAssertEqual(c.readings, ["ㄅ*", "ㄆㄚˋ"])
        var w = ZhuyinComposer()
        for ch in "ㄨㄛㄏㄓㄜㄧ" { w.input(ch) }
        // ㄨㄛ 後面接簡拼的 ㄏ、ㄓㄜ 前面是簡拼的 ㄏ：都可能是兩個字（ㄨ＋ㄛ、ㄓ＋ㄜ），加 ~ 記號
        XCTAssertEqual(w.readings, ["ㄨㄛ*~", "ㄏ*", "ㄓㄜ*~", "ㄧ*"])
        w.backspace()
        w.backspace()
        XCTAssertEqual(w.readings, ["ㄨㄛ*~", "ㄏ*", "ㄓ*"])
        w.removeFirst(3)
        XCTAssertFalse(w.isComposing)
    }

    func testOnlyRealSyllablesJoin() {
        // 組不出存在的音（ㄘㄧ）就自動換下一個字
        var c = ZhuyinComposer()
        c.validPrefixes = ["ㄘ", "ㄘㄜ", "ㄧ", "ㄧㄝ"]
        for ch in "ㄘㄧㄝ" { c.input(ch) }
        // ㄘ 自己算一個字（像簡拼），後面的 ㄧㄝ 也可能是 ㄧ＋ㄝ
        XCTAssertEqual(c.readings, ["ㄘ*", "ㄧㄝ*~"])
    }

    func testAbbreviationMarksPossibleSplit() {
        // 前一個字只打了聲母（ㄏ），這個 ㄎㄞ 也可能是 ㄎ＋ㄞ：加 ~，選了前面的字之後還記得
        var c = ZhuyinComposer()
        for ch in "ㄏㄎㄞ" { c.input(ch) }
        XCTAssertEqual(c.readings, ["ㄏ*", "ㄎㄞ*~"])
        c.removeFirst(1)
        XCTAssertEqual(c.readings, ["ㄎㄞ*~"])
        c.backspace()
        XCTAssertEqual(c.readings, ["ㄎ*"])
        // 前一個字打完整、或這個字打了聲調：不是簡拼
        var full = ZhuyinComposer()
        for ch in "ㄏㄠㄎㄞ" { full.input(ch) }
        XCTAssertEqual(full.readings, ["ㄏㄠ*", "ㄎㄞ*"])
        var toned = ZhuyinComposer()
        for ch in "ㄏㄎㄞˋ" { toned.input(ch) }
        XCTAssertEqual(toned.readings, ["ㄏ*", "ㄎㄞˋ"])
        // 後面接著簡拼也可能拆（ㄨㄞㄋ＝我愛你、ㄉㄧㄒ＝等一下）；單獨一個 ㄨㄞ 就是「外」，不拆
        var vowel = ZhuyinComposer()
        for ch in "ㄨㄞ" { vowel.input(ch) }
        XCTAssertEqual(vowel.readings, ["ㄨㄞ*"])
        vowel.input("ㄋ")
        XCTAssertEqual(vowel.readings, ["ㄨㄞ*~", "ㄋ*"])
        var three = ZhuyinComposer()
        for ch in "ㄇㄧㄢㄊ" { three.input(ch) }
        XCTAssertEqual(three.readings, ["ㄇㄧㄢ*", "ㄊ*"])
    }

    func testNeutralToneAtEnd() {
        var c = ZhuyinComposer()
        for ch in "ㄉㄜ˙" { c.input(ch) }
        XCTAssertEqual(c.readings, ["ㄉㄜ˙"])
    }

    func testToneWithoutSoundIsNotUsed() {
        var c = ZhuyinComposer()
        // 聲調先到：先留著，不組成一個音節，也不會被當成要送出的文字。
        XCTAssertTrue(c.input("ˇ"))
        XCTAssertFalse(c.isComposing)
        XCTAssertEqual(c.displayText, "")
        XCTAssertTrue(c.input("ㄨ"))
        XCTAssertTrue(c.input("ㄛ"))
        XCTAssertEqual(c.displayText, "ㄨㄛˇ")
        XCTAssertEqual(c.readings, ["ㄨㄛˇ"])
        XCTAssertTrue(c.input("ㄕ"))
        XCTAssertEqual(c.readings, ["ㄨㄛˇ", "ㄕ*"])
    }

    func testLateToneReattachesToOpenSyllable() {
        var c = ZhuyinComposer()
        c.input("ㄕ")
        c.input("ㄋ")
        XCTAssertTrue(c.backspace())
        XCTAssertTrue(c.input("ˋ"))
        XCTAssertEqual(c.readings, ["ㄕˋ"])
        XCTAssertEqual(c.displayText, "ㄕˋ")
    }

    func testBackspaceRemovesPendingToneBeforeSymbols() {
        var c = ZhuyinComposer()
        XCTAssertTrue(c.input("ˇ"))
        c.input("ㄨ")
        c.input("ㄛ")
        XCTAssertTrue(c.backspace())
        XCTAssertEqual(c.displayText, "ㄨㄛ")
        XCTAssertEqual(c.readings, ["ㄨㄛ*"])
    }

    func testWholeBufferKeepsEverySyllable() {
        var c = ZhuyinComposer()
        for ch in "ㄨㄛˇㄕˋㄕˋㄎㄢˋ" { XCTAssertTrue(c.input(ch)) }
        XCTAssertEqual(c.readings, ["ㄨㄛˇ", "ㄕˋ", "ㄕˋ", "ㄎㄢˋ"])
        XCTAssertFalse(c.hasPendingSyllable)
        XCTAssertTrue(c.isComposing)
        // 空白是一聲，不會把已經打完的句子清掉。
        c.input("ㄎ")
        c.input("ㄚ")
        XCTAssertTrue(c.confirmSyllable())
        XCTAssertEqual(c.readings, ["ㄨㄛˇ", "ㄕˋ", "ㄕˋ", "ㄎㄢˋ", "ㄎㄚ"])
        XCTAssertTrue(c.isComposing)
    }

    func testBackspace() {
        var c = ZhuyinComposer()
        for ch in "ㄋㄧˇㄏㄠ" { c.input(ch) }
        XCTAssertTrue(c.backspace())          // 刪 ㄠ
        XCTAssertEqual(c.current.reading, "ㄏ")
        XCTAssertTrue(c.backspace())          // 刪 ㄏ
        XCTAssertTrue(c.backspace())          // 刪整個 ㄋㄧˇ
        XCTAssertFalse(c.isComposing)
        XCTAssertFalse(c.backspace())
    }
}

final class ZhuyinEngineTests: XCTestCase {
    private func makeEngine(extra: [(String, String, Double)] = []) -> ZhuyinEngine {
        let db = SQLiteDB.inMemory()!
        ZhuyinEngine.createSchema(in: db)
        let rows: [(String, String, Double)] = [
            ("ㄋㄧˇ", "你", -3.0), ("ㄋㄧˇ", "妳", -4.0), ("ㄏㄠˇ", "好", -3.0),
            ("ㄋㄧˇ-ㄏㄠˇ", "你好", -4.0), ("ㄋㄧˇ-ㄇㄣ˙", "你們", -4.1),
            ("ㄕˋ", "是", -2.5), ("ㄕˋ", "事", -3.2), ("ㄕˋ", "世", -3.6),
            ("ㄐㄧㄝˋ", "界", -4.2), ("ㄕˋ-ㄐㄧㄝˋ", "世界", -4.5),
        ]
        for r in rows + extra { ZhuyinEngine.insert(into: db, reading: r.0, phrase: r.1, score: r.2) }
        return ZhuyinEngine(db: db, userModel: UserPhraseModel(fileURL: nil))
    }

    func testAppleSentencesAreTheTopCandidate() {
        // 是比試常見。整段一起斷詞時，「試試看」仍要贏過把前面音節丟掉之後的「是看」。
        let e = makeEngine(extra: [
            ("ㄨㄛˇ", "我", -2.2),
            ("ㄕˋ", "是", -1.6),
            ("ㄕˋ", "試", -3.4),
            ("ㄎㄢˋ", "看", -2.5),
            ("ㄕˋ-ㄎㄢˋ", "試看", -4.5),
            ("ㄕˋ-ㄕˋ-ㄎㄢˋ", "試試看", -4.0),
            ("ㄎㄚˇ", "卡", -3.0),
            ("ㄉㄜ˙", "的", -1.2),
            ("ㄒㄩㄢˇ", "選", -3.5),
            ("ㄗˋ", "字", -2.8),
            ("ㄒㄩㄢˇ-ㄗˋ", "選字", -3.2),
            ("ㄉㄡ", "都", -2.0),
            ("ㄇㄟˊ", "沒", -2.4),
            ("ㄧㄡˇ", "有", -2.1),
            ("ㄇㄟˊ-ㄧㄡˇ", "沒有", -2.6),
            ("ㄉㄡ-ㄇㄟˊ", "都沒", -3.4),
            ("ㄍㄟˇ", "給", -2.7),
            ("ㄉㄧˋ", "第", -3.0),
            ("ㄧ", "一", -1.8),
            ("ㄍㄜ˙", "個", -2.2),
            ("ㄉㄧˋ-ㄧ-ㄍㄜ˙", "第一個", -3.1),
            ("ㄏㄨㄟˋ", "會", -2.3),
            ("ㄏㄨㄟˋ-ㄕˋ", "會是", -3.0),
            ("ㄉㄨㄟˋ", "對", -2.4),
            ("ㄉㄨㄟˋ-ㄉㄜ˙", "對的", -3.0),
        ])
        let tryIt = ["ㄨㄛˇ", "ㄕˋ", "ㄕˋ", "ㄎㄢˋ"]
        XCTAssertEqual(e.candidates(for: tryIt).first?.text, "我試試看")
        XCTAssertEqual(e.candidates(for: tryIt).first?.span, tryIt.count)
        XCTAssertEqual(e.bestSegments(tryIt).map { $0.text }.joined(), "我試試看")
        let long = ["ㄎㄚˇ", "ㄎㄚˇ", "ㄉㄜ˙", "ㄒㄩㄢˇ", "ㄗˋ", "ㄉㄡ", "ㄇㄟˊ", "ㄧㄡˇ",
                    "ㄍㄟˇ", "ㄉㄧˋ", "ㄧ", "ㄍㄜ˙", "ㄏㄨㄟˋ", "ㄕˋ", "ㄉㄨㄟˋ", "ㄉㄜ˙"]
        XCTAssertEqual(e.candidates(for: long).first?.text, "卡卡的選字都沒有給第一個會是對的")
        XCTAssertEqual(e.candidates(for: long).first?.span, long.count)
        // 只剩最後兩個音節時，不該被當成整句已經選完。
        XCTAssertNotEqual(e.candidates(for: ["ㄕˋ", "ㄎㄢˋ"]).first?.text, "我試試看")
    }

    func testPhraseBeatsSingles() {
        let e = makeEngine()
        XCTAssertEqual(e.bestSegments(["ㄋㄧˇ", "ㄏㄠˇ"]).map { $0.text }.joined(), "你好")
    }

    func testSentence() {
        let e = makeEngine()
        let s = e.bestSegments(["ㄋㄧˇ", "ㄏㄠˇ", "ㄕˋ", "ㄐㄧㄝˋ"]).map { $0.text }.joined()
        XCTAssertEqual(s, "你好世界")
    }

    func testCandidates() {
        let e = makeEngine()
        let c = e.candidates(for: ["ㄋㄧˇ", "ㄏㄠˇ"])
        XCTAssertEqual(c.first, Candidate(text: "你好", span: 2, kind: .sentence))
        XCTAssertTrue(c.contains(Candidate(text: "妳", span: 1, kind: .phrase)))
        // 打完整的字：同長度的同音字先排完，更長的預測（世界）接在後面。
        let single = e.candidates(for: ["ㄕˋ"])
        XCTAssertEqual(single.map { $0.text }, ["是", "事", "世", "世界"])
    }

    func testUnknownSyllableStaysAsSymbols() {
        let e = makeEngine()
        XCTAssertFalse(e.bestSegments(["ㄅㄧㄤ"]).contains { PhoneticText.containsPhonetic($0.text) })
        XCTAssertFalse(e.candidates(for: ["ㄅㄧㄤ"]).contains { PhoneticText.containsPhonetic($0.text) })
    }

    func testLearning() {
        let e = makeEngine()
        XCTAssertEqual(e.phrases(["ㄋㄧˇ"]).first?.text, "你")
        e.learn(readings: ["ㄋㄧˇ"], text: "妳")
        e.learn(readings: ["ㄋㄧˇ"], text: "妳")
        XCTAssertEqual(e.phrases(["ㄋㄧˇ"]).first?.text, "妳")
        e.resetLearning()
        XCTAssertEqual(e.phrases(["ㄋㄧˇ"]).first?.text, "你")
    }

    func testLearnedNewPhrase() {
        let e = makeEngine()
        e.learn(readings: ["ㄏㄠˇ", "ㄕˋ"], text: "好事")
        XCTAssertEqual(e.phrases(["ㄏㄠˇ", "ㄕˋ"]).first?.text, "好事")
    }

    func testLearningSurvivesPartialReadings() {
        let e = makeEngine()
        // Populate the caches before selecting a different word.
        _ = e.candidates(for: ["ㄋㄧ*"])
        e.learn(readings: ["ㄋㄧˇ"], text: "妳")
        XCTAssertEqual(e.candidates(for: ["ㄋㄧ*"]).first?.text, "妳")
        e.learn(readings: ["ㄋ*", "ㄏ*"], text: "妳好")
        // 簡拼仍記得偏好，但不能把未知完整讀音推測成確定的候選。
        XCTAssertGreaterThan(e.userModel.boost(reading: "ㄋㄧˇ-ㄏㄠˇ", phrase: "妳好"), 0)
        XCTAssertFalse(e.phrases(["ㄋㄧˇ", "ㄏㄠˇ"]).contains { $0.text == "妳好" })
        XCTAssertFalse(e.phrases(["ㄕˋ", "ㄏㄠˇ"]).contains { $0.text == "妳好" })
        e.resetLearning()
        XCTAssertEqual(e.candidates(for: ["ㄋㄧ*"]).first?.text, "你")
    }

    func testSpecificPrefixIsFilteredBeforeRowLimit() {
        let common = (0..<450).map { ("ㄋㄚˋ", "那\($0)", -2.0) }
        let e = makeEngine(extra: common)
        XCTAssertEqual(e.phrases(["ㄋㄧ*"]).first?.text, "你")
    }

    func testLearnedPhrasePersistsAcrossReloadAndAbbreviation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("learned.json")
        let model = UserPhraseModel(fileURL: url)
        model.record(reading: "ㄋㄧˇ-ㄏㄠˇ", phrase: "妳好")
        let reloaded = UserPhraseModel(fileURL: url)
        XCTAssertEqual(reloaded.phrases(for: "ㄋ*-ㄏ*"), ["妳好"])
        XCTAssertGreaterThan(reloaded.boost(reading: "ㄋ*-ㄏ*", phrase: "妳好"), 0)
        XCTAssertTrue(reloaded.phrases(for: "ㄋㄧˋ-ㄏㄠˇ").isEmpty)
    }

    func testPreviewAndAbbreviation() {
        let e = makeEngine(extra: [("ㄨㄛˇ", "我", -2.5), ("ㄏㄨㄟˋ", "會", -2.8), ("ㄓㄜˋ", "這", -2.6),
                                   ("ㄧㄤˋ", "樣", -3.0), ("ㄓㄜˋ-ㄧㄤˋ", "這樣", -3.5)])
        func sentence(_ r: [String]) -> String { e.bestSegments(r).map { $0.text }.joined() }
        XCTAssertEqual(sentence(["ㄋ*", "ㄏ*"]), "你好")
        XCTAssertEqual(sentence(["ㄋㄧ*", "ㄏㄠ*"]), "你好")
        XCTAssertEqual(sentence(["ㄋㄧˇ", "ㄏ*"]), "你好")
        XCTAssertEqual(sentence(["ㄋ*", "ㄏ*", "ㄕ*", "ㄐ*"]), "你好世界")
        XCTAssertEqual(sentence(["ㄨㄛ*", "ㄏ*", "ㄓㄜ*", "ㄧ*"]), "我會這樣")
        XCTAssertEqual(e.candidates(for: ["ㄋㄧ*"]).map { $0.text }, ["你", "妳", "你好", "你們"])
        XCTAssertFalse(e.candidates(for: ["ㄅ*"]).contains { PhoneticText.containsPhonetic($0.text) })
    }

    func testSplitAbbreviation() {
        // 簡拼 ㄏㄎㄞ：ㄎㄞ 也當成 ㄎ＋ㄞ（可愛）；後面接完整打的字就不拆（好開心）
        let e = makeEngine(extra: [("ㄎㄞ", "開", -3.0), ("ㄎㄜˇ-ㄞˋ", "可愛", -4.3), ("ㄒㄧㄣ", "心", -3.5),
                                   ("ㄎㄞ-ㄒㄧㄣ", "開心", -4.0)])
        func sentence(_ r: [String]) -> String { e.bestSegments(r).map { $0.text }.joined() }
        XCTAssertEqual(ZhuyinEngine.splitAbbreviation("ㄎㄞ*~"), ["ㄎ*", "ㄞ*"])
        XCTAssertNil(ZhuyinEngine.splitAbbreviation("ㄎㄞ*"))
        XCTAssertEqual(ZhuyinEngine.splitAbbreviation("ㄨㄞ*~"), ["ㄨ*", "ㄞ*"])
        XCTAssertNil(ZhuyinEngine.splitAbbreviation("ㄇㄧㄢ*~"))
        XCTAssertEqual(e.candidates(for: ["ㄎㄞ*~"]).first?.text, "可愛")
        XCTAssertEqual(e.candidates(for: ["ㄎㄞ*"]).first?.text, "開")
        XCTAssertEqual(sentence(["ㄏ*", "ㄎㄞ*~"]), "好可愛")
        XCTAssertEqual(sentence(["ㄏ*", "ㄎㄞ*~", "ㄒㄧㄣ*"]), "好開心")
        XCTAssertEqual(ZhuyinEngine.display("ㄎㄞ*~"), "ㄎㄞ")
    }

    func testLearnSplitAbbreviation() {
        let e = makeEngine(extra: [("ㄎㄞ", "開", -3.0), ("ㄎㄜˇ-ㄞˋ", "可愛", -4.3)])
        // ㄎㄞ*~ 選了三個字的「好可愛」：記成拆開的 ㄏ*-ㄎ*-ㄞ*；選了「開」就是沒拆，記成 ㄎㄞ*
        e.learn(readings: ["ㄏ*", "ㄎㄞ*~"], text: "好可愛")
        XCTAssertTrue(e.userModel.phrases(for: "ㄏ*-ㄎ*-ㄞ*").contains("好可愛"))
        e.learn(readings: ["ㄎㄞ*~"], text: "開")
        XCTAssertTrue(e.userModel.phrases(for: "ㄎㄞ*").contains("開"))
    }

    func testLoneSyllableSplit() {
        // 單獨的 ㄨㄢ：第一個還是單字，簡拼的「晚安」排第二；選過之後排第一
        let e = makeEngine(extra: [("ㄨㄢ", "灣", -3.2), ("ㄨㄢˇ-ㄢ", "晚安", -3.5)])
        XCTAssertEqual(e.candidates(for: ["ㄨㄢ*"]).prefix(2).map { $0.text }, ["灣", "晚安"])
        e.learn(readings: ["ㄨㄢ*"], text: "晚安")
        e.learn(readings: ["ㄨㄢ*"], text: "晚安")
        XCTAssertTrue(e.userModel.phrases(for: "ㄨ*-ㄢ*").contains("晚安"))
        XCTAssertEqual(e.candidates(for: ["ㄨㄢ*"]).first?.text, "晚安")
        // 拆開的詞分數差太多就不列（ㄋㄧ 不會冒出「那一」）
        let f = makeEngine(extra: [("ㄋㄚˋ-ㄧ", "那一", -6.0)])
        XCTAssertFalse(f.candidates(for: ["ㄋㄧ*"]).contains { $0.text == "那一" })
    }

    func testLearnMixedFullPrefixAndSplitAbbreviation() {
        let e = makeEngine()
        e.learn(readings: ["ㄋㄧ*", "ㄏ*", "ㄎㄞ*~"], text: "你好可愛")
        XCTAssertTrue(e.userModel.phrases(for: "ㄋㄧ*-ㄏ*-ㄎ*-ㄞ*").contains("你好可愛"))
        XCTAssertFalse(e.userModel.phrases(for: "ㄋㄧ*-ㄏ*-ㄎㄞ*").contains("你好可愛"))
        // 無法對應字數的讀音不應寫入學習資料。
        e.learn(readings: ["ㄋㄧ*", "ㄏ*"], text: "你好可愛")
        XCTAssertFalse(e.userModel.phrases(for: "ㄋㄧ*-ㄏ*").contains("你好可愛"))
    }

    func testPredictions() {
        let e = makeEngine()
        // 打完 ㄋㄧˇ：同長度的字先排完，接著才是預測詞，選了要記成完整讀音
        let c = e.candidates(for: ["ㄋㄧˇ"])
        XCTAssertEqual(c.map { $0.text }, ["你", "妳", "你好", "你們"])
        let hello = try XCTUnwrap(c.first { $0.text == "你好" })
        XCTAssertEqual(hello.reading, "ㄋㄧˇ-ㄏㄠˇ")
        XCTAssertEqual(hello.span, 1)
        // 不必先打聲調，也會出現相關詞；選取仍使用完整讀音。
        let partial = e.candidates(for: ["ㄋㄧ*"])
        XCTAssertEqual(partial.map { $0.text }, ["你", "妳", "你好", "你們"])
        XCTAssertEqual(partial.first { $0.text == "你好" }?.reading, "ㄋㄧˇ-ㄏㄠˇ")
        // 學過的詞排在預測的最前面，但仍在同長度的字之後
        e.learn(readings: ["ㄋㄧˇ", "ㄇㄣ˙"], text: "你們")
        XCTAssertEqual(e.candidates(for: ["ㄋㄧˇ"]).first { $0.reading != nil }?.text, "你們")
    }

    func testPartialPredictionsRespectTonesAndConsumption() {
        let e = makeEngine(extra: [("ㄋㄧˋ-ㄌㄧㄡˊ", "逆流", -2.0)])
        let partial = e.candidates(for: ["ㄋㄧ*"])
        XCTAssertEqual(partial.first?.text, "你")
        let phrase = try XCTUnwrap(partial.first { $0.text == "你好" })
        XCTAssertEqual(phrase.span, 1)
        XCTAssertEqual(phrase.reading, "ㄋㄧˇ-ㄏㄠˇ")
        e.learn(readings: phrase.reading!.components(separatedBy: "-"), text: phrase.text)
        XCTAssertTrue(e.userModel.phrases(for: "ㄋㄧˇ-ㄏㄠˇ").contains("你好"))
        XCTAssertFalse(e.predictions(for: ["ㄋㄧˇ"]).contains { $0.text == "逆流" })
        XCTAssertTrue(e.predictions(for: ["ㄋㄧ*"]).contains { $0.text == "逆流" })
        XCTAssertTrue(e.predictions(for: ["ㄋㄧ*"], limit: 0).isEmpty)
        var composer = ZhuyinComposer()
        for ch in "ㄋㄧ" { composer.input(ch) }
        composer.removeFirst(phrase.span)
        XCTAssertFalse(composer.isComposing)
    }

    func testContextRanksHomophonesWithoutOverridingStrongLearning() {
        let e = makeEngine(extra: [("ㄐㄧ", "雞", -3.0), ("ㄐㄧ", "機", -3.8),
                                   ("ㄕㄡˇ-ㄐㄧ", "手機", -3.0)])
        XCTAssertEqual(e.candidates(for: ["ㄐㄧ*"]).first?.text, "雞")
        XCTAssertEqual(e.candidates(for: ["ㄐㄧ*"], before: "手").first?.text, "機")
        XCTAssertEqual(e.candidates(for: ["ㄐㄧ*"], before: "手。").first?.text, "雞")
        XCTAssertEqual(e.candidates(for: ["ㄐㄧ*"], before: "手 ").first?.text, "雞")
        for _ in 0..<5 { e.learn(readings: ["ㄐㄧ"], text: "雞") }
        XCTAssertEqual(e.candidates(for: ["ㄐㄧ*"], before: "手").first?.text, "雞")
    }

    func testContextCompletionUsesOnlyUncommittedSuffix() {
        let e = makeEngine(extra: [("ㄒㄧㄣ-ㄎㄨˇ", "辛苦", -4.0),
                                   ("ㄒㄧㄣ-ㄎㄨˇ-ㄌㄜ˙", "辛苦了", -3.5),
                                   ("ㄎㄨˇ-ㄍㄨㄚ", "苦瓜", -3.0)])
        XCTAssertEqual(e.associations(after: "今天辛苦").first, "了")
        XCTAssertFalse(e.associations(after: "辛苦").contains("苦了"))
        XCTAssertTrue(e.associations(after: "辛苦！").isEmpty)
        let c = e.candidates(for: ["ㄎㄨ*"], before: "辛")
        let completion = c.first { $0.text == "苦了" }!
        XCTAssertEqual(completion.span, 1)
        XCTAssertEqual(completion.reading, "ㄎㄨˇ-ㄌㄜ˙")
        XCTAssertFalse(c.contains { $0.text == "辛苦了" && $0.reading != nil })
    }

    func testLearnedCompletionsRefreshCacheAndReset() {
        let e = makeEngine()
        _ = e.associations(after: "你好")
        _ = e.predictions(for: ["ㄋㄧ*"])
        e.learn(readings: ["ㄋㄧˇ", "ㄏㄠˇ", "ㄅㄠˇ", "ㄅㄠˇ"], text: "你好寶寶")
        XCTAssertTrue(e.associations(after: "你好").contains("寶寶"))
        XCTAssertTrue(e.predictions(for: ["ㄋㄧ*"]).contains { $0.text == "你好寶寶" })
        e.resetLearning()
        XCTAssertFalse(e.associations(after: "你好").contains("寶寶"))
        XCTAssertFalse(e.predictions(for: ["ㄋㄧ*"]).contains { $0.text == "你好寶寶" })
    }

    func testPredictionCountLeavesSingleCharacterAlternativesReachable() {
        let e = makeEngine(extra: [("ㄋㄧˇ-ㄇㄚ˙", "你嗎", -4.2), ("ㄋㄧˇ-ㄋㄜ˙", "你呢", -4.3),
                                   ("ㄋㄧˇ-ㄏㄠˇ-ㄇㄚ˙", "你好嗎", -4.4)])
        let c = e.candidates(for: ["ㄋㄧ*"])
        XCTAssertLessThanOrEqual(c.filter { $0.reading != nil }.count, 3)
        XCTAssertLessThanOrEqual(c.firstIndex { $0.text == "妳" }!, 4)
        XCTAssertEqual(Set(c.map { $0.text }).count, c.count)
    }

    func testSyllablePrefixes() {
        let p = makeEngine().syllablePrefixes()
        XCTAssertTrue(p.isSuperset(of: ["ㄋ", "ㄋㄧ", "ㄐㄧㄝ"]))
        XCTAssertFalse(p.contains("ㄘㄧ"))
    }

    func testAssociations() {
        let e = makeEngine()
        let a = e.associations(after: "你")
        XCTAssertTrue(a.contains("好"))
        XCTAssertTrue(a.contains("們"))
        XCTAssertEqual(e.associations(after: "世"), ["界"])
    }

    func testExactLengthComesBeforeLongerWords() {
        let e = makeEngine(extra: [
            ("ㄊㄨㄟ", "推", -3.5), ("ㄊㄨㄟˇ", "腿", -4.7), ("ㄐㄧㄢ", "間", -3.1),
            ("ㄊㄨㄟ-ㄐㄧㄢˋ", "推薦", -4.34),
            ("ㄊㄨㄟ-ㄐㄧㄢˋ-ㄒㄧㄣˋ", "推薦信", -5.44),
            ("ㄊㄨㄟ-ㄐㄧㄢˋ-ㄍㄟˇ", "推薦給", -5.46),
            ("ㄋㄧˇ-ㄕˋ", "你是", -4.32),
            ("ㄋㄧㄠˋ-ㄕ-ㄐㄧㄣˋ", "尿失禁", -5.51),
            ("ㄋㄧㄢˋ-ㄕˋ-ㄐㄧˋ", "廿世紀", -5.46),
        ])
        let recommend = e.candidates(for: ["ㄊㄨㄟ*", "ㄐㄧㄢ*"])
        XCTAssertEqual(recommend.first?.text, "推薦")
        let longer = recommend.filter { $0.text.count > 2 }.map { $0.text }
        if let firstLonger = recommend.firstIndex(where: { $0.text.count > 2 }) {
            XCTAssertTrue(recommend[..<firstLonger].allSatisfy { $0.text.count <= 2 })
        }
        XCTAssertLessThanOrEqual(longer.count, 2)
        let youAre = e.candidates(for: ["ㄋㄧ*", "ㄕ*"])
        XCTAssertEqual(youAre.first?.text, "你是")
        XCTAssertTrue(youAre.prefix(3).allSatisfy { $0.text.count <= 2 })
    }

    func testRepeatedCharacterIsNotTheSentence() {
        let e = makeEngine(extra: [
            ("ㄐㄧㄡˋ", "就", -2.7),
            ("ㄐㄧㄡˋ-ㄕˋ", "就是", -3.05),
            ("ㄕˋ", "是", -2.2),
            ("ㄕˋ", "事", -3.1),
        ])
        let c = e.candidates(for: ["ㄐㄧㄡˋ", "ㄕˋ", "ㄕˋ"])
        XCTAssertNotEqual(c.first?.text, "就是是")
        XCTAssertEqual(c.first?.text.count, 3)
        XCTAssertEqual(c.first?.span, 3)
    }

    func testOnePickPromotesWordAndAbbreviation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("learned.json")
        let rows: [(String, String, Double)] = [
            ("ㄕˋ", "是", -2.0), ("ㄕˋ", "試", -7.5),
            ("ㄋㄧˇ-ㄕˋ", "你是", -4.3), ("ㄋㄚˋ-ㄕˋ", "那是", -3.2),
        ]
        func engine(_ model: UserPhraseModel) -> ZhuyinEngine {
            let db = SQLiteDB.inMemory()!
            ZhuyinEngine.createSchema(in: db)
            for r in rows { ZhuyinEngine.insert(into: db, reading: r.0, phrase: r.1, score: r.2) }
            return ZhuyinEngine(db: db, userModel: model)
        }
        let model = UserPhraseModel(fileURL: url)
        let e = engine(model)
        XCTAssertEqual(e.candidates(for: ["ㄕˋ"]).first?.text, "是")
        e.learn(readings: ["ㄕˋ"], text: "試")
        XCTAssertEqual(e.candidates(for: ["ㄕˋ"]).first?.text, "試")
        XCTAssertEqual(e.candidates(for: ["ㄋ*", "ㄕ*"]).first?.text, "那是")
        e.learn(readings: ["ㄋㄧˇ", "ㄕˋ"], text: "你是")
        XCTAssertEqual(e.candidates(for: ["ㄋ*", "ㄕ*"]).first?.text, "你是")
        XCTAssertEqual(e.candidates(for: ["ㄋㄧˇ", "ㄕˋ"]).first?.text, "你是")
        let reloaded = engine(UserPhraseModel(fileURL: url))
        XCTAssertEqual(reloaded.candidates(for: ["ㄕˋ"]).first?.text, "試")
        XCTAssertEqual(reloaded.candidates(for: ["ㄋ*", "ㄕ*"]).first?.text, "你是")
    }

    func testLegacyLearningFileStillLoads() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("learned.json")
        let legacy = ["ㄋㄧˇ-ㄏㄠˇ": ["妳好": 2]]
        let data = try JSONEncoder().encode(legacy)
        try data.write(to: url)
        let model = UserPhraseModel(fileURL: url)
        XCTAssertEqual(model.pickCount(reading: "ㄋㄧˇ-ㄏㄠˇ", phrase: "妳好"), 2)
        XCTAssertEqual(model.phrases(for: "ㄋ*-ㄏ*"), ["妳好"])
    }

    func testCommitLearnsTheSentence() {
        let e = makeEngine()
        var session = ZhuyinSession()
        session.engine = e
        for ch in "ㄋㄧˇㄏㄠˇ" { _ = session.type(ch) }
        session.refresh(context: "")
        let text = session.commitAll()
        XCTAssertEqual(text, "你好")
        XCTAssertEqual(e.userModel.pickCount(reading: "ㄋㄧˇ-ㄏㄠˇ", phrase: "你好"), 1)
    }
}

final class PunctuationSuggestionTests: XCTestCase {
    func testQuestionsAndStatements() {
        XCTAssertEqual(PunctuationSuggestions.after("你要去哪裡吃飯").first, "？")
        XCTAssertEqual(PunctuationSuggestions.after("你怎么知道的").first, "？")
        XCTAssertEqual(PunctuationSuggestions.after("你好嗎").first, "？")
        XCTAssertEqual(PunctuationSuggestions.after("我們走吧").first, "，")
        XCTAssertEqual(PunctuationSuggestions.after("你去哪裡？我回家").first, "，")
        XCTAssertTrue(PunctuationSuggestions.after("已經好了。").isEmpty)
        XCTAssertTrue(PunctuationSuggestions.after("").isEmpty)
    }
}

final class FancyTextTests: XCTestCase {
    func testStyles() {
        let v = FancyText.variants("Hi 1")
        XCTAssertTrue(v.contains("\u{1D4D7}\u{1D4F2} 1"))   // 草寫 𝓗𝓲
        XCTAssertTrue(v.contains("\u{24BD}\u{24D8} \u{2460}"))   // 圈圈 Ⓗⓘ ①
        XCTAssertTrue(v.contains("H\u{0336}i\u{0336} 1\u{0336}"))   // 刪除線
        let zh = FancyText.variants("星光")
        XCTAssertTrue(zh.contains("♡ 星光 ♡"))
        XCTAssertFalse(zh.contains("星光"))
    }

    func testShortcuts() {
        let s = ShortcutStore(fileURL: nil)
        s.add(code: "addr", phrase: "台北市")
        s.add(code: "地址", phrase: "台北市")
        XCTAssertEqual(s.matching("ADDR"), ["台北市"])
        XCTAssertEqual(s.matching("地址"), ["台北市"])
        XCTAssertTrue(s.matching("add").isEmpty)
    }
}

final class StoreTests: XCTestCase {
    func testClipboardDedupeAndLimit() {
        let s = ClipboardStore(fileURL: nil, limit: 3)
        s.add("a"); s.add("b"); s.add("c")
        s.add("a")
        XCTAssertEqual(s.ordered.map { $0.text }, ["a", "c", "b"])
        s.togglePin(s.items.last!.id)       // 釘選 b
        s.add("d"); s.add("e"); s.add("f")
        XCTAssertEqual(s.ordered.map { $0.text }, ["b", "f", "e", "d"])
        XCTAssertFalse(s.add("   "))
        s.clearUnpinned()
        XCTAssertEqual(s.ordered.map { $0.text }, ["b"])
    }

    func testEmoticonStore() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let s = EmoticonStore(directory: dir)
        s.addCustom("(=^･ω･^=)")
        XCTAssertEqual(s.custom.first, "(=^･ω･^=)")
        let ref = s.addSticker(pngData: Data([1, 2, 3]))
        XCTAssertNotNil(ref)
        s.pushRecent("😀", kind: "emoji")
        s.pushRecent("😂", kind: "emoji")
        s.pushRecent("😀", kind: "emoji")
        XCTAssertEqual(s.recents("emoji"), ["😀", "😂"])

        let reloaded = EmoticonStore(directory: dir)
        XCTAssertEqual(reloaded.custom.first, "(=^･ω･^=)")
        XCTAssertEqual(reloaded.stickers.count, 1)
        reloaded.removeSticker(ref!)
        XCTAssertEqual(reloaded.stickers.count, 0)
    }

    func testSymbolDataIsClean() {
        for group in [SymbolData.emoji, SymbolData.kaomoji, SymbolData.symbols] {
            for cat in group {
                XCTAssertFalse(cat.items.isEmpty, cat.title)
                XCTAssertFalse(cat.items.contains(""), cat.title)
            }
        }
    }
}

final class FuzzyTests: XCTestCase {
    private func makeEngine(extra: [(String, String, Double)] = []) -> ZhuyinEngine {
        let db = SQLiteDB.inMemory()!
        ZhuyinEngine.createSchema(in: db)
        let rows: [(String, String, Double)] = [
            ("ㄋㄧˇ", "你", -3.0), ("ㄏㄠˇ", "好", -3.0), ("ㄋㄧˇ-ㄏㄠˇ", "你好", -4.0),
            ("ㄕˋ", "是", -2.5), ("ㄕˋ", "事", -3.2),
        ]
        for r in rows + extra { ZhuyinEngine.insert(into: db, reading: r.0, phrase: r.1, score: r.2) }
        return ZhuyinEngine(db: db, userModel: UserPhraseModel(fileURL: nil))
    }

    private func sentence(_ e: ZhuyinEngine, _ r: [String]) -> String {
        e.bestSegments(r).map { $0.text }.joined()
    }

    func testForgotTone() {
        let e = makeEngine(extra: [("ㄋㄧ", "妮", -5.5)])
        // 有符合輸入的字時尊重原音；容錯的「你」仍可另選。
        XCTAssertEqual(sentence(e, ["ㄋㄧ", "ㄏㄠˇ"]), "妮好")
        XCTAssertTrue(e.candidates(for: ["ㄋㄧ"]).contains { $0.text == "你" })
        e.fuzzy.tones = false
        XCTAssertEqual(sentence(e, ["ㄋㄧ", "ㄏㄠˇ"]), "妮好")
    }

    func testCorrectInputStaysCorrect() {
        let e = makeEngine(extra: [("ㄕ", "詩", -4.0)])
        XCTAssertEqual(e.candidates(for: ["ㄕ"]).first?.text, "詩")
        XCTAssertEqual(e.candidates(for: ["ㄕˋ"]).first?.text, "是")
    }

    func testNeighborKey() {
        let e = makeEngine()
        // ㄡ 在 ㄠ 正下方，按錯了
        XCTAssertEqual(sentence(e, ["ㄋㄧˇ", "ㄏㄡˇ"]), "你好")
    }

    func testPhonetic() {
        let e = makeEngine()
        XCTAssertFalse(e.candidates(for: ["ㄙˋ"]).contains { PhoneticText.containsPhonetic($0.text) })
        e.fuzzy.phonetic = true
        XCTAssertEqual(e.candidates(for: ["ㄙˋ"]).first?.text, "是")
    }

    func testNeighborsMap() {
        XCTAssertEqual(Set(Bopomofo.neighbors["ㄡ"] ?? []), Set("ㄝㄥㄠ"))
    }
}

final class SpellingTests: XCTestCase {
    func testEditDistance() {
        XCTAssertEqual(Spelling.editDistance("teh", "the"), 1)
        XCTAssertTrue(Spelling.isCloseEnough("teh", "the"))
        XCTAssertEqual(Spelling.editDistance("helo", "hello"), 1)
        XCTAssertEqual(Spelling.editDistance("", "abc"), 3)
        XCTAssertTrue(Spelling.isCloseEnough("helo", "hello"))
        XCTAssertFalse(Spelling.isCloseEnough("cat", "dog"))
        XCTAssertTrue(Spelling.isCloseEnough("recieve", "receive"))
    }

    func testMatchCase() {
        XCTAssertEqual(Spelling.matchCase("hello", like: "Helo"), "Hello")
        XCTAssertEqual(Spelling.matchCase("hello", like: "helo"), "hello")
    }
}
