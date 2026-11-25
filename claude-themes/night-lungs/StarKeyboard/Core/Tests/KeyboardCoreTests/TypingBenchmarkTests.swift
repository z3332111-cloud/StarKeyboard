import XCTest
@testable import KeyboardCore

final class TypingBenchmarkTests: XCTestCase {
    // 使用公開字典產生歷史資料，絕不讀使用者的學習紀錄。相同測試也可放在舊版比較。
    func testDictionaryTypingLatency() throws {
        guard let path = ProcessInfo.processInfo.environment["TYPING_DICTIONARY"] else {
            throw XCTSkip("Set TYPING_DICTIONARY to benchmark a release dictionary")
        }
        let db = try XCTUnwrap(SQLiteDB(path: path))
        var history: [String: [String: Int]] = [:]
        db.run("SELECT reading, phrase FROM phrases ORDER BY score DESC LIMIT 2000") { stmt in
            history[SQLiteDB.text(stmt, 0), default: [:]][SQLiteDB.text(stmt, 1)] = 3
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("synthetic-learning.json")
        JSONFile.save(history, to: url)
        let e = ZhuyinEngine(db: db, userModel: UserPhraseModel(fileURL: url))
        var timings: [Double] = []
        let prefixes = e.syllablePrefixes()
        for input in ["ㄋㄧˇㄏㄠˇ", "ㄨㄛˇㄐㄧㄣㄊㄧㄢㄏㄣˇㄎㄞㄒㄧㄣ", "ㄏㄎㄞ", "ㄋㄠˇ"] {
            var composer = ZhuyinComposer()
            composer.validPrefixes = prefixes
            for symbol in input {
                composer.input(symbol)
                let start = ProcessInfo.processInfo.systemUptime
                let candidates = e.candidates(for: composer.readings, before: "今天")
                timings.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                XCTAssertFalse(candidates.isEmpty)
            }
            let choices = e.candidates(for: composer.readings)
            if let pick = choices.first {
                e.learn(readings: composer.readings, text: pick.text)
            }
        }
        timings.sort()
        print("TYPING_BENCH samples=\(timings.count) history=\(history.count) p50_ms=\(timings[timings.count / 2]) p95_ms=\(timings[Int(Double(timings.count - 1) * 0.95)]) max_ms=\(timings.last!)")
    }
}
