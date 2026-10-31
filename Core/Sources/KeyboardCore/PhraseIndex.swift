import Foundation

/// 注音字典的索引。
///
/// 字詞來自小麥注音 McBopomofo（MIT，https://github.com/openvanilla/McBopomofo）。
/// 以前鍵盤打開時把整個字典（十七萬多筆）讀進記憶體，iPhone 的鍵盤只能用大約 50～70MB，
/// 加上背景照片和字體就會超過、被系統強制關掉（閃退）。
/// 現在改成要用時才去 SQLite 查（都有索引，一次不到 1 毫秒），只留最近查過的一小部分在記憶體。
/// 對外的用法（byReading[key]、rows[id]…）和以前一樣，選字引擎不用改。
/// 兩個引擎（注音、拼音）共用同一個索引。
final class PhraseIndex {
    struct Row {
        let reading: String
        let phrase: String
        let score: Double
    }

    /// 用 key 查出一串 row id（查不到是 nil）
    struct Lookup<Key: Hashable> {
        fileprivate let fetch: (Key) -> [Int]?
        subscript(key: Key) -> [Int]? { fetch(key) }
    }

    /// 用 row id 拿到那一筆
    struct Rows {
        fileprivate let fetch: (Int) -> Row
        subscript(id: Int) -> Row { fetch(id) }
    }

    private let db: SQLiteDB
    private let lock = NSLock()
    private var rowCache: [Int: Row] = [:]
    private var lookupCache: [String: [Int]] = [:]
    private var ngramCache: [String: Int] = [:]
    private let hasNgrams: Bool

    /// 單音節（沒聲調）的所有開頭，組字時用來判斷注音能不能接在一起（只有一千多筆，留在記憶體）
    let prefixes: Set<String>

    // 暫存上限：超過就整個清掉重來，記憶體不會一直長
    private static let maxRows = 6000
    private static let maxLookups = 800
    private static let maxNgrams = 4000

    private init(db: SQLiteDB, prefixes: Set<String>, hasNgrams: Bool) {
        self.db = db
        self.prefixes = prefixes
        self.hasNgrams = hasNgrams
    }

    static func load(from db: SQLiteDB) -> PhraseIndex {
        var prefixes = Set<String>()
        db.run("SELECT DISTINCT plain FROM phrases WHERE plain NOT LIKE '%-%'") { stmt in
            var prefix = ""
            for ch in SQLiteDB.text(stmt, 0) {
                prefix.append(ch)
                prefixes.insert(prefix)
            }
        }
        var hasNgrams = false
        db.run("SELECT 1 FROM ngrams LIMIT 1") { _ in hasNgrams = true }
        return PhraseIndex(db: db, prefixes: prefixes, hasNgrams: hasNgrams)
    }

    // MARK: 對外的查法（和以前的記憶體版本一樣）

    var rows: Rows { Rows { [unowned self] id in self.row(id) } }

    /// 有聲調的完整讀音 → 分數最高的 80 筆
    var byReading: Lookup<String> {
        Lookup { [unowned self] key in
            self.query("r|" + key, "WHERE reading = ?1 ORDER BY score DESC, phrase ASC LIMIT 80", [.text(key)])
        }
    }

    /// 拿掉聲調的讀音（拼音）
    var byPlain: Lookup<String> {
        Lookup { [unowned self] key in
            self.query("p|" + key, "WHERE plain = ?1 ORDER BY score DESC, phrase ASC LIMIT 80", [.text(key)])
        }
    }

    /// 每個音節的第一個注音（簡拼）。後面還要一筆一筆比，所以拿多一點
    var byAbbr: Lookup<String> {
        Lookup { [unowned self] key in
            self.query("a|" + key, "WHERE abbr = ?1 ORDER BY score DESC, phrase ASC LIMIT 2000", [.text(key)])
        }
    }

    /// 以這個完整音節開頭、而且更長的詞
    var longerByFirst: Lookup<String> {
        Lookup { [unowned self] first in
            self.query("f|" + first, "WHERE reading > ?1 AND reading < ?2 ORDER BY score DESC, phrase ASC LIMIT 160",
                       [.text(first + "-"), .text(first + "-\u{10FFFF}")])
        }
    }

    /// 以這個沒聲調的音節開頭（或只開了頭）的更長詞
    var longerByFirstPlain: Lookup<String> {
        Lookup { [unowned self] head in
            self.query("h|" + head,
                       "WHERE plain > ?1 AND plain < ?2 AND plain LIKE '%-%' ORDER BY score DESC, phrase ASC LIMIT 160",
                       [.text(head), .text(head + "\u{10FFFF}")])
        }
    }

    /// 以這個字開頭的詞，給聯想詞用
    var byFirstChar: Lookup<Character> {
        Lookup { [unowned self] ch in
            let s = String(ch)
            return self.query("c|" + s, "WHERE phrase >= ?1 AND phrase < ?2 ORDER BY score DESC, phrase ASC LIMIT 500",
                              [.text(s), .text(s + "\u{10FFFF}")])
        }
    }

    /// 候選詞接在已經決定的字後面時，語料裡看過的接法加分。上限避免蓋過差很多的詞頻。
    /// 前後文用的字組出現次數來自字典詞與 Tatoeba 中文句子（CC BY 2.0）。
    func contextBonus(tail: String, phrase: String) -> Double {
        guard !phrase.isEmpty, hasNgrams else { return 0 }
        var best = 0.0
        if !tail.isEmpty {
            let ts = Array(tail.suffix(2))
            let ps = Array(phrase.prefix(3))
            for a in 1...ts.count {
                for b in 1...min(3, ps.count) {
                    let gram = String(ts.suffix(a)) + String(ps.prefix(b))
                    let count = ngramCount(gram)
                    guard count > 0 else { continue }
                    let weight = gram.count >= 3 ? 0.62 : 0.28
                    best = max(best, weight * log10(Double(count) + 1))
                }
            }
        }
        return min(best, 1.8)
    }

    /// 記憶體快不夠時：丟掉暫存
    func trimCaches() {
        lock.lock()
        defer { lock.unlock() }
        rowCache.removeAll()
        lookupCache.removeAll()
        ngramCache.removeAll()
    }

    // MARK: 實際去 SQLite 查

    private func query(_ cacheKey: String, _ whereClause: String, _ args: [SQLiteDB.Value]) -> [Int]? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = lookupCache[cacheKey] { return cached.isEmpty ? nil : cached }
        if lookupCache.count > Self.maxLookups { lookupCache.removeAll() }
        if rowCache.count > Self.maxRows { rowCache.removeAll() }
        var ids: [Int] = []
        db.run("SELECT rowid, reading, phrase, score FROM phrases " + whereClause, args) { stmt in
            let id = Int(SQLiteDB.double(stmt, 0))
            ids.append(id)
            if self.rowCache[id] == nil {
                self.rowCache[id] = Row(reading: SQLiteDB.text(stmt, 1), phrase: SQLiteDB.text(stmt, 2),
                                   score: SQLiteDB.double(stmt, 3))
            }
        }
        lookupCache[cacheKey] = ids
        return ids.isEmpty ? nil : ids
    }

    private func row(_ id: Int) -> Row {
        lock.lock()
        defer { lock.unlock() }
        if let r = rowCache[id] { return r }
        var found = Row(reading: "", phrase: "", score: -99)
        db.run("SELECT reading, phrase, score FROM phrases WHERE rowid = ?1", [.int(id)]) { stmt in
            found = Row(reading: SQLiteDB.text(stmt, 0), phrase: SQLiteDB.text(stmt, 1), score: SQLiteDB.double(stmt, 2))
        }
        rowCache[id] = found
        return found
    }

    private func ngramCount(_ gram: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        if let n = ngramCache[gram] { return n }
        if ngramCache.count > Self.maxNgrams { ngramCache.removeAll() }
        var n = 0
        db.run("SELECT n FROM ngrams WHERE gram = ?1", [.text(gram)]) { stmt in n = Int(SQLiteDB.double(stmt, 0)) }
        ngramCache[gram] = n
        return n
    }
}
