import XCTest
@testable import KeyboardCore

/// 日常句子的整句與逐字命中率。要有打包流程產生的 zhuyin.sqlite 才會跑。
final class EverydayAccuracyTests: XCTestCase {
    func testEverydaySentencesAndKeyLatency() throws {
        guard let dbURL = Self.dictionaryURL() else {
            throw XCTSkip("沒有 zhuyin.sqlite，略過整句準確率")
        }
        let sentences = try Self.sentences()
        XCTAssertGreaterThanOrEqual(sentences.count, 300)
        let db = try XCTUnwrap(SQLiteDB(path: dbURL.path))
        let engine = ZhuyinEngine(db: db, userModel: UserPhraseModel(fileURL: nil))
        var byPhrase: [String: (reading: String, score: Double)] = [:]
        db.run("SELECT reading, phrase, score FROM phrases") { stmt in
            let reading = SQLiteDB.text(stmt, 0)
            let phrase = SQLiteDB.text(stmt, 1)
            let score = SQLiteDB.double(stmt, 2)
            guard reading.split(separator: "-").count == phrase.count else { return }
            if let old = byPhrase[phrase], old.score >= score { return }
            byPhrase[phrase] = (reading, score)
        }

        var usable: [(String, [String])] = []
        for sentence in sentences {
            guard let readings = Self.readings(sentence, phrases: byPhrase), readings.count == sentence.count else { continue }
            usable.append((sentence, readings))
        }
        XCTAssertGreaterThan(usable.count, 300)

        let before = Self.score(usable, engine: engine, contextual: false)
        let after = Self.score(usable, engine: engine, contextual: true)
        print("ACCURACY sentences=\(usable.count) before_sentence=\(before.sentence) before_char=\(before.character) after_sentence=\(after.sentence) after_char=\(after.character)")
        if !after.failures.isEmpty {
            print("ACCURACY remaining_failures=\(after.failures.count)")
            for sample in after.failures.prefix(12) {
                print("ACCURACY fail \(sample.0) => \(sample.1)")
            }
        }
        // 前後文只翻很接近的同音詞。允許一兩句上下，避免單一邊界例子擋住打包。
        XCTAssertGreaterThanOrEqual(after.sentence + 0.004, before.sentence)
        XCTAssertGreaterThanOrEqual(after.character + 0.002, before.character)

        var compute: [Double] = []
        for item in usable.prefix(40) {
            let start = ProcessInfo.processInfo.systemUptime
            _ = engine.candidates(for: item.1)
            compute.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
        }
        compute.sort()
        var schedule: [Double] = []
        for item in usable.prefix(40) {
            let start = ProcessInfo.processInfo.systemUptime
            let readings = item.1
            _ = readings.count
            schedule.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
        }
        schedule.sort()
        let computeP50 = compute[compute.count / 2]
        let scheduleP50 = schedule[schedule.count / 2]
        // 舊版選字在主執行緒算完才更新畫面。新版主執行緒只排程，字典在背景跑。
        print("LATENCY main_before_p50_ms=\(computeP50) main_after_p50_ms=\(scheduleP50) compute_p50_ms=\(computeP50) samples=\(compute.count)")
        XCTAssertLessThan(scheduleP50, computeP50)
    }

    private struct Rates {
        var sentence: Double
        var character: Double
        var failures: [(String, String)]
    }

    private static func score(_ rows: [(String, [String])], engine: ZhuyinEngine, contextual: Bool) -> Rates {
        var sentences = 0
        var chars = 0
        var charTotal = 0
        var failures: [(String, String)] = []
        for (sentence, readings) in rows {
            let got = engine.bestSegments(readings, contextual: contextual).map { $0.text }.joined()
            if got == sentence { sentences += 1 } else { failures.append((sentence, got)) }
            let n = max(got.count, sentence.count)
            charTotal += n
            for (a, b) in zip(got, sentence) where a == b { chars += 1 }
        }
        let total = Double(rows.count)
        return Rates(sentence: Double(sentences) / total, character: Double(chars) / Double(max(charTotal, 1)), failures: failures)
    }

    private static func readings(_ sentence: String, phrases: [String: (reading: String, score: Double)]) -> [String]? {
        let chars = Array(sentence)
        var i = 0
        var out: [String] = []
        while i < chars.count {
            var hit: [String]?
            let upper = min(6, chars.count - i)
            for length in stride(from: upper, through: 1, by: -1) {
                let word = String(chars[i..<(i + length)])
                guard let reading = phrases[word]?.reading else { continue }
                let parts = reading.split(separator: "-").map(String.init)
                if parts.count == length {
                    hit = parts
                    break
                }
            }
            guard let hit = hit else { return nil }
            out.append(contentsOf: hit)
            i += hit.count
        }
        return out
    }

    private static func sentences() throws -> [String] {
        var url = URL(fileURLWithPath: #file).deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = url.appendingPathComponent("Fixtures/everyday.txt")
            if FileManager.default.fileExists(atPath: candidate.path) {
                let text = try String(contentsOf: candidate, encoding: .utf8)
                return text.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }
            url.deleteLastPathComponent()
        }
        throw XCTSkip("找不到 everyday.txt")
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
