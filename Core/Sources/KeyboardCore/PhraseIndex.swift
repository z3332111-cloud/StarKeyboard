import Foundation

/// 注音字典的記憶體索引。
///
/// 字詞來自小麥注音 McBopomofo（MIT，https://github.com/openvanilla/McBopomofo）。
/// 鍵盤打開時整表讀進記憶體，之後每個按鍵只查這份索引，不再打 SQLite。
/// 兩個引擎（注音、拼音）共用同一個索引，避免字典在記憶體裡放兩份。
final class PhraseIndex {
    struct Row {
        let reading: String
        let phrase: String
        let score: Double
    }

    let rows: [Row]
    /// 有聲調的完整讀音 → 分數最高的若干筆（整句斷詞用最高的那筆，候選列用同音字）
    let byReading: [String: [Int]]
    /// 拿掉聲調的讀音（拼音）
    let byPlain: [String: [Int]]
    /// 每個音節的第一個注音。簡拼比對前不能先砍筆數，所以這裡不設上限。
    let byAbbr: [String: [Int]]
    /// 單音節（沒聲調）的所有開頭，組字時用來判斷注音能不能接在一起
    let prefixes: Set<String>
    /// 以這個完整音節開頭、而且更長的詞
    let longerByFirst: [String: [Int]]
    /// 以這個沒聲調的音節開頭（或只開了頭）的更長詞
    let longerByFirstPlain: [String: [Int]]
    /// 以這個字開頭的詞，給聯想詞用
    let byFirstChar: [Character: [Int]]

    private init(rows: [Row], byReading: [String: [Int]], byPlain: [String: [Int]], byAbbr: [String: [Int]],
                 prefixes: Set<String>, longerByFirst: [String: [Int]], longerByFirstPlain: [String: [Int]],
                 byFirstChar: [Character: [Int]]) {
        self.rows = rows
        self.byReading = byReading
        self.byPlain = byPlain
        self.byAbbr = byAbbr
        self.prefixes = prefixes
        self.longerByFirst = longerByFirst
        self.longerByFirstPlain = longerByFirstPlain
        self.byFirstChar = byFirstChar
    }

    static func load(from db: SQLiteDB) -> PhraseIndex {
        var rows: [Row] = []
        var byReading: [String: [Int]] = [:]
        var byPlain: [String: [Int]] = [:]
        var byAbbr: [String: [Int]] = [:]
        var prefixes = Set<String>()
        var longerByFirst: [String: [Int]] = [:]
        var longerByFirstPlain: [String: [Int]] = [:]
        var byFirstChar: [Character: [Int]] = [:]

        func append(_ map: inout [String: [Int]], _ key: String, _ idx: Int, _ cap: Int) {
            guard !key.isEmpty else { return }
            if let existing = map[key] {
                guard existing.count < cap else { return }
                map[key]!.append(idx)
            } else {
                map[key] = [idx]
            }
        }

        // 分數高的先讀進來，每個上限才留得到最好的詞。
        db.run("SELECT reading, phrase, score FROM phrases ORDER BY score DESC, phrase ASC") { stmt in
            let reading = SQLiteDB.text(stmt, 0)
            let phrase = SQLiteDB.text(stmt, 1)
            guard !reading.isEmpty, !phrase.isEmpty else { return }
            let score = SQLiteDB.double(stmt, 2)
            let idx = rows.count
            rows.append(Row(reading: reading, phrase: phrase, score: score))
            append(&byReading, reading, idx, 80)

            let parts = reading.split(separator: "-")
            let plain = String(reading.filter { !Bopomofo.tones.contains($0) })
            let abbr = String(parts.compactMap { $0.first })
            append(&byPlain, plain, idx, 80)
            if !abbr.isEmpty {
                byAbbr[abbr, default: []].append(idx)
            }

            if parts.count == 1 {
                let syllable = String(parts[0].filter { !Bopomofo.tones.contains($0) })
                var prefix = ""
                for ch in syllable {
                    prefix.append(ch)
                    prefixes.insert(prefix)
                }
            } else if let first = parts.first {
                let firstReading = String(first)
                append(&longerByFirst, firstReading, idx, 160)
                var head = ""
                for ch in firstReading where !Bopomofo.tones.contains(ch) {
                    head.append(ch)
                    append(&longerByFirstPlain, head, idx, 160)
                }
            }

            if let ch = phrase.first {
                if byFirstChar[ch]?.count ?? 0 < 500 {
                    byFirstChar[ch, default: []].append(idx)
                }
            }
        }

        return PhraseIndex(rows: rows, byReading: byReading, byPlain: byPlain, byAbbr: byAbbr,
                           prefixes: prefixes, longerByFirst: longerByFirst,
                           longerByFirstPlain: longerByFirstPlain, byFirstChar: byFirstChar)
    }
}
