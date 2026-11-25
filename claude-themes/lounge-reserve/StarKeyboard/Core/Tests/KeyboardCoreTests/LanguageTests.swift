import XCTest
@testable import KeyboardCore

final class HangulTests: XCTestCase {
    /// 模擬輸入框：每次刪掉上次還在拼的字，換成新的（和鍵盤的做法一樣）
    private func type(_ jamo: String) -> String {
        var h = HangulComposer()
        var doc = ""
        var shown = ""
        for c in jamo {
            let out = h.input(c)
            doc.removeLast(shown.count)
            doc += out.commit + out.composing
            shown = out.composing
        }
        return doc
    }

    func testBasicWords() {
        XCTAssertEqual(type("ㅎㅏㄴㄱㅡㄹ"), "한글")
        XCTAssertEqual(type("ㅇㅏㄴㄴㅕㅇ"), "안녕")
        XCTAssertEqual(type("ㅅㅏㄹㅏㅇㅎㅐ"), "사랑해")
    }

    func testCompoundVowelAndFinal() {
        XCTAssertEqual(type("ㅇㅘ"), "와")
        XCTAssertEqual(type("ㄷㅏㄹㄱ"), "닭")
        XCTAssertEqual(type("ㄷㅏㄹㄱㅏ"), "달가")
        XCTAssertEqual(type("ㅇㅣㄹㄱㅇㅓ"), "읽어")
    }

    func testLoneJamo() {
        XCTAssertEqual(type("ㅋㅋㅋ"), "ㅋㅋㅋ")
        XCTAssertEqual(type("ㅏㅏ"), "ㅏㅏ")
    }

    func testBackspace() {
        var h = HangulComposer()
        for c in "ㅎㅏㄴ" { _ = h.input(c) }
        XCTAssertEqual(h.composing, "한")
        h.backspace()
        XCTAssertEqual(h.composing, "하")
        h.backspace()
        XCTAssertEqual(h.composing, "ㅎ")
        h.backspace()
        XCTAssertTrue(h.isEmpty)
        XCTAssertFalse(h.backspace())
    }
}

final class RomajiTests: XCTestCase {
    func testWords() {
        XCTAssertEqual(Romaji.finalize("sakura"), "さくら")
        XCTAssertEqual(Romaji.finalize("konnichiha"), "こんにちは")
        XCTAssertEqual(Romaji.finalize("arigatou"), "ありがとう")
        XCTAssertEqual(Romaji.finalize("kitte"), "きって")
        XCTAssertEqual(Romaji.finalize("kyou"), "きょう")
        XCTAssertEqual(Romaji.finalize("shinbun"), "しんぶん")
        XCTAssertEqual(Romaji.finalize("onna"), "おんな")
        XCTAssertEqual(Romaji.finalize("ra-men"), "らーめん")
        XCTAssertEqual(Romaji.finalize("tsukue"), "つくえ")
        XCTAssertEqual(Romaji.finalize("jaa"), "じゃあ")
    }

    func testUnfinished() {
        XCTAssertEqual(Romaji.convert("sak").kana, "さ")
        XCTAssertEqual(Romaji.convert("sak").rest, "k")
        XCTAssertEqual(Romaji.convert("ky").rest, "ky")
        XCTAssertEqual(Romaji.convert("kan").rest, "n")
    }

    func testKatakana() {
        XCTAssertEqual(Romaji.katakana("さくら"), "サクラ")
        XCTAssertEqual(Romaji.katakana(Romaji.finalize("ko-hi-")), "コーヒー")
    }
}

final class ReleaseTests: XCTestCase {
    func testBuildNumber() {
        XCTAssertEqual(ReleaseChecker.buildNumber(fromTag: "build-12"), 12)
        XCTAssertNil(ReleaseChecker.buildNumber(fromTag: "v1.0"))
    }

    func testParse() {
        let json = #"{"tag_name":"build-7","name":"糯糯鍵盤 第 7 版","body":"這次更新：\n- 修好按鍵","html_url":"https://github.com/z3332111-cloud/StarKeyboard/releases/tag/build-7"}"#
        let info = ReleaseChecker.parse(Data(json.utf8))
        XCTAssertEqual(info?.build, 7)
        XCTAssertEqual(info?.title, "糯糯鍵盤 第 7 版")
        XCTAssertTrue(info?.notes.contains("修好按鍵") ?? false)
    }
}

final class GlideTests: XCTestCase {
    func testGlide() {
        // 假的 QWERTY：一個鍵寬 1，第二排往右半格，第三排往右一格半
        var centers: [Character: CGPoint] = [:]
        for (r, row) in ["qwertyuiop", "asdfghjkl", "zxcvbnm"].enumerated() {
            for (c, ch) in row.enumerated() {
                centers[ch] = CGPoint(x: CGFloat(c) + CGFloat(r) * 0.5 + (r == 2 ? 0.5 : 0), y: CGFloat(r))
            }
        }
        let g = GlideDecoder(words: [("hello", 1_000_000), ("help", 500_000), ("hell", 100_000), ("the", 10_000_000), ("tie", 100_000)])
        func swipe(_ word: String) -> [CGPoint] {
            let keys = GlideDecoder.squeeze(word).map { centers[$0]! }
            var out: [CGPoint] = []
            for i in 0..<(keys.count - 1) {
                for k in 0..<10 {
                    let t = CGFloat(k) / 10
                    out.append(CGPoint(x: keys[i].x + (keys[i + 1].x - keys[i].x) * t + 0.1, y: keys[i].y + (keys[i + 1].y - keys[i].y) * t - 0.1))
                }
            }
            out.append(keys.last!)
            return out
        }
        XCTAssertEqual(g.decode(path: swipe("hello"), centers: centers, keyWidth: 1).first, "hello")
        XCTAssertEqual(g.decode(path: swipe("help"), centers: centers, keyWidth: 1).first, "help")
        XCTAssertEqual(g.decode(path: swipe("the"), centers: centers, keyWidth: 1).first, "the")
    }
}

final class PinyinTests: XCTestCase {
    private func makePinyin() -> PinyinEngine {
        let db = SQLiteDB.inMemory()!
        ZhuyinEngine.createSchema(in: db)
        let rows: [(String, String, Double)] = [
            ("ㄋㄧˇ", "你", -3.0), ("ㄏㄠˇ", "好", -3.0), ("ㄋㄧˇ-ㄏㄠˇ", "你好", -4.0),
            ("ㄏㄞˊ", "還", -3.2), ("ㄏㄜˊ", "和", -3.0), ("ㄒㄧ", "西", -3.5), ("ㄢ", "安", -3.6),
            ("ㄒㄧ-ㄢ", "西安", -5.0), ("ㄒㄧㄢ", "先", -3.4), ("ㄓㄨㄥ-ㄍㄨㄛˊ", "中國", -3.5),
            ("ㄌㄩˋ-ㄙㄜˋ", "綠色", -4.5), ("ㄊㄞˊ-ㄨㄢ", "臺灣", -4.0),
            ("ㄏㄨㄟˋ", "會", -2.5), ("ㄌㄞˊ", "來", -3.0), ("ㄌㄚ˙", "啦", -3.5),
            ("ㄏㄨㄟˊ-ㄌㄞˊ", "回來", -4.0), ("ㄏㄠˇ-ㄌㄚ˙", "好啦", -4.5),
            ("ㄎㄜˇ-ㄋㄥˊ", "可能", -3.0), ("ㄎㄣˇ", "肯", -4.0), ("ㄥ", "鞥", -6.0),
            ("ㄕㄣˊ-ㄇㄜ˙", "什麼", -2.9), ("ㄕˋ-ㄇㄚ˙", "是嗎", -3.5), ("ㄙㄨㄛˇ-ㄧˇ", "所以", -3.0), ("ㄕˊ-ㄧ", "十一", -3.6),
        ]
        for r in rows { ZhuyinEngine.insert(into: db, reading: r.0, phrase: r.1, score: r.2) }
        let table = ["ni": "ㄋㄧ", "hao": "ㄏㄠ", "hai": "ㄏㄞ", "he": "ㄏㄜ", "xi": "ㄒㄧ", "an": "ㄢ",
                     "xian": "ㄒㄧㄢ", "zhong": "ㄓㄨㄥ", "guo": "ㄍㄨㄛ", "lv": "ㄌㄩ", "se": "ㄙㄜ",
                     "tai": "ㄊㄞ", "wan": "ㄨㄢ", "hui": "ㄏㄨㄟ", "lai": "ㄌㄞ", "la": "ㄌㄚ",
                     "ke": "ㄎㄜ", "neng": "ㄋㄥ", "ken": "ㄎㄣ", "eng": "ㄥ", "shen": "ㄕㄣ", "me": "ㄇㄜ",
                     "shi": "ㄕ", "ma": "ㄇㄚ", "suo": "ㄙㄨㄛ", "yi": "ㄧ"]
        let engine = ZhuyinEngine(db: db, userModel: UserPhraseModel(fileURL: nil), column: "plain")
        return PinyinEngine(engine: engine, table: table)
    }

    private func pieces(_ p: PinyinEngine, _ s: String) -> [String] {
        p.segment(s).pieces.map { $0.pinyin }
    }

    func testAbbreviation() {
        let p = makePinyin()
        XCTAssertEqual(pieces(p, "nh"), ["n", "h"])
        XCTAssertEqual(p.candidates(for: "nh").first?.text, "你好")
        XCTAssertEqual(p.candidates(for: "nhao").first?.text, "你好")
        XCTAssertEqual(p.candidates(for: "zhg").first?.text, "中國")
        XCTAssertEqual(pieces(p, "zhong"), ["zhong"])
        XCTAssertEqual(p.segment("zhon").partial, "zhon")   // 打到一半還是用補完，不會變成簡拼
    }

    func testSegmentation() {
        let p = makePinyin()
        XCTAssertEqual(pieces(p, "nihao"), ["ni", "hao"])
        XCTAssertEqual(pieces(p, "xian"), ["xian"])
        XCTAssertEqual(pieces(p, "xi'an"), ["xi", "an"])
        XCTAssertEqual(pieces(p, "zhongguo"), ["zhong", "guo"])
        XCTAssertEqual(pieces(p, "lvse"), ["lv", "se"])
        let half = p.segment("nih")
        XCTAssertEqual(half.pieces.map { $0.pinyin }, ["ni"])
        XCTAssertEqual(half.partial, "h")
        XCTAssertEqual(p.display("nih"), "ni h")
    }

    /// 用簡拼（h、hl）選過的字，打完整拼音時不能搶到第一個（hao 是「好」不是「會」）
    func testAbbreviationPicksDoNotBeatFullPinyin() {
        let p = makePinyin()
        p.engine.learn(readings: ["ㄏ*"], text: "會")
        p.engine.learn(readings: ["ㄏ*", "ㄌ*"], text: "好啦")
        XCTAssertEqual(p.candidates(for: "hao").first?.text, "好")
        XCTAssertEqual(p.candidates(for: "huilai").first?.text, "回來")
        XCTAssertEqual(p.candidates(for: "hl").first?.text, "好啦")   // 簡拼還是記得選過的
    }

    /// keneng 斷成 ke＋neng（不是 ken＋eng）；只打 s 也找得到 sh 開頭的字，而且不會只因為 shi 剛好只有聲母就排前面
    func testSegmentationAndShorthandInitials() {
        let p = makePinyin()
        XCTAssertEqual(pieces(p, "keneng"), ["ke", "neng"])
        XCTAssertEqual(p.candidates(for: "keneng").first?.text, "可能")
        XCTAssertEqual(p.candidates(for: "sm").first?.text, "什麼")
        XCTAssertEqual(p.candidates(for: "sy").first?.text, "所以")
    }

    func testCandidates() {
        let p = makePinyin()
        XCTAssertEqual(p.candidates(for: "nihao").first?.text, "你好")
        XCTAssertEqual(p.candidates(for: "nih").first?.text, "你好")
        XCTAssertEqual(p.candidates(for: "zhongguo").first?.text, "中國")
        XCTAssertEqual(p.candidates(for: "taiwan").first?.text, "臺灣")
        XCTAssertEqual(p.consumedLength("nihao", span: 1), 2)
        XCTAssertEqual(p.consumedLength("xi'an", span: 1), 3)
        XCTAssertEqual(p.consumedLength("nihao", span: 2), 5)
    }

    func testSimplified() {
        let table = ["灣": "湾", "頭髮": "头发", "頭": "头", "髮": "发", "臺": "台", "國": "国"]
        let c = ChineseConverter { table[$0] }
        XCTAssertEqual(c.convert("臺灣"), "台湾")
        XCTAssertEqual(c.convert("頭髮好"), "头发好")
        XCTAssertEqual(c.convert("中國"), "中国")
        XCTAssertEqual(c.convert("你好"), "你好")
    }
}
