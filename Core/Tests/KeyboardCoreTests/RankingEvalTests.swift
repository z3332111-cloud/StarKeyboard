import XCTest
@testable import KeyboardCore

/// 用詞頻表裡的常見 1～4 字詞，量測排名：完整讀音與只打聲母。
final class RankingEvalTests: XCTestCase {
    private struct Word {
        var syllables: [String]
        var text: String
        var score: Double
    }

    private struct Stats {
        var n = 0
        var top1 = 0
        var top3 = 0
        var longer = 0
        var rare = 0
        var missing = 0

        mutating func add(_ list: [String], target: String, syllables: Int, scores: [String: Double]) {
            n += 1
            if list.first == target { top1 += 1 }
            if list.prefix(3).contains(target) { top3 += 1 }
            guard let idx = list.firstIndex(of: target) else {
                missing += 1
                longer += 1
                rare += 1
                return
            }
            let targetScore = scores[target] ?? 0
            var sawLonger = false
            var sawRare = false
            for earlier in list[..<idx] {
                if earlier.count > syllables { sawLonger = true }
                let score = scores[earlier] ?? -99
                if score < -5 && score < targetScore { sawRare = true }
            }
            if sawLonger { longer += 1 }
            if sawRare { rare += 1 }
        }
    }

    func testCandidateRankingOnCommonWords() throws {
        guard let dbURL = Self.dictionaryURL() else {
            throw XCTSkip("沒有 zhuyin.sqlite，略過選字排名評測")
        }
        let db = try XCTUnwrap(SQLiteDB(path: dbURL.path))
        var byLength: [Int: [Word]] = [:]
        var scores: [String: Double] = [:]
        db.run("SELECT reading, phrase, score FROM phrases") { stmt in
            let reading = SQLiteDB.text(stmt, 0)
            let phrase = SQLiteDB.text(stmt, 1)
            let score = SQLiteDB.double(stmt, 2)
            guard !phrase.isEmpty, !PhoneticText.containsPhonetic(phrase) else { return }
            if let old = scores[phrase] {
                if score > old { scores[phrase] = score }
            } else {
                scores[phrase] = score
            }
            let syllables = reading.split(separator: "-").map(String.init)
            guard (1...4).contains(syllables.count), syllables.count == phrase.count else { return }
            byLength[syllables.count, default: []].append(Word(syllables: syllables, text: phrase, score: score))
        }
        var words: [Word] = []
        for length in 1...4 {
            let ranked = (byLength[length] ?? []).sorted { $0.score != $1.score ? $0.score > $1.score : $0.text < $1.text }
            var seen = Set<String>()
            for word in ranked where seen.insert(word.syllables.joined(separator: "-") + "\t" + word.text).inserted {
                words.append(word)
                if seen.count == 250 { break }
            }
        }
        XCTAssertGreaterThanOrEqual(words.count, 800, "詞頻表裡 1～4 字的常見詞不夠")

        let engine = ZhuyinEngine(db: db, userModel: UserPhraseModel(fileURL: nil))
        var beforeFull = Stats(), afterFull = Stats()
        var beforeAbbr = Stats(), afterAbbr = Stats()
        for word in words {
            let full = word.syllables
            beforeFull.add(engine.legacyCandidates(for: full).map { $0.text }, target: word.text, syllables: full.count, scores: scores)
            afterFull.add(engine.candidates(for: full).map { $0.text }, target: word.text, syllables: full.count, scores: scores)
            let abbr = full.map { syllable -> String in
                let body = syllable.filter { !Bopomofo.tones.contains($0) }
                return String(body.prefix(1)) + "*"
            }
            beforeAbbr.add(engine.legacyCandidates(for: abbr).map { $0.text }, target: word.text, syllables: abbr.count, scores: scores)
            afterAbbr.add(engine.candidates(for: abbr).map { $0.text }, target: word.text, syllables: abbr.count, scores: scores)
        }
        func line(_ name: String, _ before: Stats, _ after: Stats) -> String {
            func rate(_ hit: Int, _ n: Int) -> String { String(format: "%.4f", Double(hit) / Double(max(n, 1))) }
            return "RANKING \(name) n=\(before.n) before_top1=\(rate(before.top1, before.n)) after_top1=\(rate(after.top1, after.n)) before_top3=\(rate(before.top3, before.n)) after_top3=\(rate(after.top3, after.n)) before_longer=\(before.longer) after_longer=\(after.longer) before_rare=\(before.rare) after_rare=\(after.rare) before_missing=\(before.missing) after_missing=\(after.missing)"
        }
        let fullLine = line("full", beforeFull, afterFull)
        let abbrLine = line("abbr", beforeAbbr, afterAbbr)
        print(fullLine)
        print(abbrLine)
        print("RANKING words=\(words.count) lengths=\((1...4).map { "\($0):\((byLength[$0] ?? []).count)" }.joined(separator: ","))")

        XCTAssertGreaterThanOrEqual(afterFull.top1, beforeFull.top1)
        XCTAssertGreaterThanOrEqual(afterFull.top3, beforeFull.top3)
        XCTAssertLessThanOrEqual(afterFull.longer, beforeFull.longer)
        XCTAssertLessThanOrEqual(afterFull.rare, beforeFull.rare)
        XCTAssertGreaterThanOrEqual(afterAbbr.top3, beforeAbbr.top3)
        XCTAssertLessThanOrEqual(afterAbbr.longer, beforeAbbr.longer)
        XCTAssertLessThanOrEqual(afterAbbr.rare, beforeAbbr.rare)

        let recommend = engine.candidates(for: ["ㄊㄨㄟ*", "ㄐㄧㄢ*"])
        XCTAssertEqual(recommend.first?.text, "推薦")
        XCTAssertTrue(recommend.prefix(3).allSatisfy { $0.text.count <= 2 })
        let youAre = engine.candidates(for: ["ㄋㄧ*", "ㄕ*"])
        XCTAssertEqual(youAre.first?.text, "你是")
        XCTAssertTrue(youAre.prefix(3).allSatisfy { $0.text.count <= 2 })
        XCTAssertNotEqual(engine.candidates(for: ["ㄐㄧㄡˋ", "ㄕˋ", "ㄕˋ"]).first?.text, "就是是")

        let learning = try learningPromotion(template: engine, words: words)
        print("RANKING learning picked=\(learning.tried) promoted=\(learning.promoted) abbr_promoted=\(learning.abbr)")
        XCTAssertGreaterThanOrEqual(learning.tried, 20)
        XCTAssertEqual(learning.promoted, learning.tried)
        XCTAssertEqual(learning.abbr, learning.tried)
    }

    private struct LearningResult { var tried: Int; var promoted: Int; var abbr: Int }

    /// 每個長度挑幾個不是第一名的常見同音詞，選一次之後應該變第一，簡拼也一樣。
    private func learningPromotion(template: ZhuyinEngine, words: [Word]) throws -> LearningResult {
        var groups: [String: [Word]] = [:]
        for word in words {
            groups[word.syllables.joined(separator: "-"), default: []].append(word)
        }
        var samples: [Word] = []
        for length in 1...4 {
            let pairs = groups.filter { $0.value.count >= 2 && $0.value[0].syllables.count == length }
            for (_, list) in pairs.sorted(by: { $0.value[0].score > $1.value[0].score }).prefix(6) {
                let sorted = list.sorted { $0.score > $1.score }
                if sorted.count >= 2 { samples.append(sorted[1]) }
            }
        }
        var promoted = 0
        var abbrHit = 0
        for sample in samples {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("learned.json")
            let engine = template.sharingIndex(userModel: UserPhraseModel(fileURL: url))
            engine.learn(readings: sample.syllables, text: sample.text)
            if engine.candidates(for: sample.syllables).first?.text == sample.text { promoted += 1 }
            let abbr = sample.syllables.map { syllable -> String in
                let body = syllable.filter { !Bopomofo.tones.contains($0) }
                return String(body.prefix(1)) + "*"
            }
            let reloaded = template.sharingIndex(userModel: UserPhraseModel(fileURL: url))
            if reloaded.candidates(for: abbr).first?.text == sample.text { abbrHit += 1 }
            try? FileManager.default.removeItem(at: directory)
        }
        return LearningResult(tried: samples.count, promoted: promoted, abbr: abbrHit)
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
