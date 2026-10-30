import Foundation

struct Candidate: Equatable {
    enum Kind: Equatable {
        case sentence   // 整串自動組好的句子
        case phrase     // 字典裡的詞或單字
        case literal    // 查不到，直接用注音符號
    }

    let text: String
    let span: Int       // 用掉前面幾個音節
    let kind: Kind
    var reading: String? = nil   // 預測的詞：完整讀音（選了要記成這個，不是只打的那幾個字）
}

/// 注音選字：查小麥注音的字典（SQLite），整串用動態規劃找分數最高的斷詞
final class ZhuyinEngine {
    struct Scored {
        let text: String
        let score: Double
    }

    static let maxPhraseLength = 6
    /// 查不到的音節的分數（字典分數是 log10 機率，大約 -2 到 -8）
    static let unknownPenalty: Double = -30
    /// 使用者自己學到、字典沒有的詞
    static let userPhraseBase: Double = -6

    private let db: SQLiteDB
    /// 用哪一欄查：注音用 reading（有聲調），拼音用 plain（沒聲調）
    private let column: String
    private var cache: [String: [Scored]] = [:]
    private var fuzzyCache: [String: [Scored]] = [:]
    private var alternativeCache: [String: [(reading: String, penalty: Double)]] = [:]

    /// 容錯：打錯鍵、聲調錯、ㄣㄥ這類模糊音也猜得到
    struct FuzzyOptions: Equatable {
        var keyNeighbors = true   // 打出來的音不存在時，試試旁邊的鍵
        var tones = true          // 聲調打錯或忘了打
        var phonetic = false      // ㄣㄥ、ㄓㄗ、ㄔㄘ、ㄕㄙ 分不清
    }

    var fuzzy = FuzzyOptions() {
        didSet {
            if fuzzy != oldValue {
                fuzzyCache.removeAll()
                alternativeCache.removeAll()
            }
        }
    }

    static let tonePenalty: Double = -2.5
    static let phoneticPenalty: Double = -1.2
    static let neighborPenalty: Double = -2.5
    /// 只打了開頭（ㄋ 當 ㄋㄧ），比打完整的排後面一點
    static let prefixPenalty: Double = -1.0
    /// 簡拼裡的 ㄎㄞ 拆成 ㄎ＋ㄞ 兩個字的讀法加分（前一個字只打了聲母，多半整串都是簡拼）
    static let splitBonus: Double = 2.5
    /// 單獨一個音節（ㄨㄢ）拆開的詞，分數和最好的單字差多少以內才列出來（ㄋㄧ 的「難以」差太多就不列）
    static let loneSplitRange: Double = 1.5
    let userModel: UserPhraseModel

    init(db: SQLiteDB, userModel: UserPhraseModel, column: String = "reading") {
        self.db = db
        self.userModel = userModel
        self.column = column
    }

    convenience init?(path: String, userModel: UserPhraseModel, column: String = "reading") {
        guard let db = SQLiteDB(path: path) else { return nil }
        self.init(db: db, userModel: userModel, column: column)
    }

    // MARK: 字典格式（tools/build_dict.py 也是用這個）

    static func createSchema(in db: SQLiteDB) {
        db.execute("CREATE TABLE IF NOT EXISTS phrases(reading TEXT NOT NULL, plain TEXT NOT NULL, abbr TEXT NOT NULL, phrase TEXT NOT NULL, score REAL NOT NULL)")
        db.execute("CREATE INDEX IF NOT EXISTS idx_reading ON phrases(reading, score DESC)")
        db.execute("CREATE INDEX IF NOT EXISTS idx_plain ON phrases(plain, score DESC)")
        db.execute("CREATE INDEX IF NOT EXISTS idx_abbr ON phrases(abbr, score DESC)")
        db.execute("CREATE INDEX IF NOT EXISTS idx_phrase ON phrases(phrase)")
    }

    static func insert(into db: SQLiteDB, reading: String, phrase: String, score: Double) {
        let plain = String(reading.filter { !Bopomofo.tones.contains($0) })
        let abbr = String(reading.split(separator: "-").compactMap { $0.first })
        db.run("INSERT INTO phrases(reading, plain, abbr, phrase, score) VALUES (?1, ?2, ?3, ?4, ?5)",
               [.text(reading), .text(plain), .text(abbr), .text(phrase), .double(score)])
    }

    /// 畫面上顯示的注音（拿掉查字典用的 * 和 ~）
    static func display(_ reading: String) -> String {
        reading.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "~", with: "")
    }

    /// 可能是兩個字的音節（ㄎㄞ*~、ㄨㄞ*~）拆成兩個只打開頭的字（ㄎ*、ㄞ*）；拆不了回傳 nil
    static func splitAbbreviation(_ reading: String) -> [String]? {
        guard reading.hasSuffix("*~") else { return nil }
        let body = Array(reading.dropLast(2))
        guard body.count == 2, let first = Bopomofo.kind(of: body[0]), first == .initial || first == .medial,
              let next = Bopomofo.kind(of: body[1]), next == .medial || next == .rhyme else { return nil }
        return [String(body[0]) + "*", String(body[1]) + "*"]
    }

    /// 後面接的是打完整的音節（不是只打聲母）：使用者回到完整打法，前面那個就不拆（ㄏ ㄎㄞ ㄒㄧㄣ 是好開心，不是好可愛心）
    static func settleSplits(_ readings: [String]) -> [String] {
        var out = readings
        for j in out.indices.dropLast() where out[j].hasSuffix("~") {
            let next = out[j + 1]   // 只打一個注音的寫法是「ㄏ*」「ㄧ*」
            let nextIsBare = next.count == 2 && next.hasSuffix("*")
            if !nextIsBare { out[j].removeLast() }
        }
        return out
    }

    /// 讀音合不合 pattern：有 * 的音節只要開頭一樣（聲調不限），其他要完全一樣。合的話回傳要扣的分數
    static func matchPenalty(_ pattern: [Substring], _ reading: [Substring], ignoreTones: Bool = false) -> Double? {
        guard pattern.count == reading.count else { return nil }
        var penalty: Double = 0
        for (want, have) in zip(pattern, reading) {
            guard want.hasSuffix("*") else {
                let h = ignoreTones ? Substring(have.filter { !Bopomofo.tones.contains($0) }) : have
                if want != h { return nil }
                continue
            }
            let head = want.dropLast()
            let plain = String(have.filter { !Bopomofo.tones.contains($0) })
            guard plain.hasPrefix(head) else { return nil }
            if plain.count != head.count { penalty += prefixPenalty }
        }
        return penalty
    }

    /// 查字典：讀音裡有沒打完的音節（*）就用開頭注音查，再一個一個比
    private func lookup(_ key: String) -> [(phrase: String, score: Double)] {
        var out: [(phrase: String, score: Double)] = []
        guard key.contains("*") else {
            db.run("SELECT phrase, score FROM phrases WHERE \(column) = ?1 ORDER BY score DESC LIMIT 80", [.text(key)]) { stmt in
                out.append((SQLiteDB.text(stmt, 0), SQLiteDB.double(stmt, 1)))
            }
            return out
        }
        let pattern = key.split(separator: "-")
        let abbr = String(pattern.compactMap { $0.first })
        var best: [String: Double] = [:]
        let toneless = column == "plain"
        // 先按完整的輸入條件過濾，再限制筆數，避免常見但不符合的字把要找的字擠掉。
        db.run("SELECT reading, phrase, score FROM phrases WHERE abbr = ?1 AND \(column) GLOB ?2 ORDER BY score DESC LIMIT 400", [.text(abbr), .text(key)]) { stmt in
            guard let penalty = Self.matchPenalty(pattern, SQLiteDB.text(stmt, 0).split(separator: "-"), ignoreTones: toneless) else { return }
            let phrase = SQLiteDB.text(stmt, 1)
            let s = SQLiteDB.double(stmt, 2) + penalty
            if let old = best[phrase], old >= s { return }
            best[phrase] = s
        }
        for (phrase, score) in best.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }).prefix(80) {
            out.append((phrase, score))
        }
        return out
    }

    // MARK: 查詢

    /// 一段注音（例如 ["ㄋㄧˇ", "ㄏㄠˇ"]）對應的所有詞，分數高的在前面
    func phrases(_ readings: ArraySlice<String>) -> [Scored] {
        let key = readings.joined(separator: "-")
        if let cached = cache[key] { return cached }

        var best: [String: Double] = [:]
        var order: [String] = []
        for (phrase, score) in lookup(key) where best[phrase] == nil {
            best[phrase] = score
            order.append(phrase)
        }
        for phrase in userModel.phrases(for: key) where best[phrase] == nil {
            best[phrase] = Self.userPhraseBase
            order.append(phrase)
        }

        var list = order.enumerated().map { (i, phrase) in
            (i, Scored(text: phrase, score: best[phrase]! + userModel.boost(reading: key, phrase: phrase)))
        }
        list.sort { $0.1.score != $1.1.score ? $0.1.score > $1.1.score : $0.0 < $1.0 }
        let result = list.map { $0.1 }
        cache[key] = result
        return result
    }

    /// 和 phrases 一樣，但也算進打錯的可能（每個詞最多猜錯一個音節，分數扣一點）
    func fuzzyPhrases(_ readings: ArraySlice<String>) -> [Scored] {
        let key = readings.joined(separator: "-")
        if let cached = fuzzyCache[key] { return cached }
        var best: [String: Double] = [:]
        var order: [String] = []
        func merge(_ list: [Scored], _ penalty: Double) {
            for p in list {
                let s = p.score + penalty
                if let old = best[p.text] {
                    if s > old { best[p.text] = s }
                } else {
                    best[p.text] = s
                    order.append(p.text)
                }
            }
        }
        // ~ 只是「可能是兩個字」的記號，查字典時拿掉
        let syllables = readings.map { $0.hasSuffix("~") ? String($0.dropLast()) : $0 }
        merge(phrases(syllables[...]), 0)
        for j in syllables.indices {
            for alt in alternatives(for: syllables[j]) {
                var variant = syllables
                variant[j] = alt.reading
                merge(phrases(variant[...]), alt.penalty)
            }
        }
        // 簡拼的 ㄎㄞ 也當成 ㄎ＋ㄞ 兩個字試試（第一個組合是都不拆，上面已經查過）
        var variants: [[String]] = [[]]
        for (r, plain) in zip(readings, syllables) {
            let unsplit = variants.map { $0 + [plain] }
            variants = unsplit + (Self.splitAbbreviation(r).map { parts in variants.map { $0 + parts } } ?? [])
        }
        for variant in variants.dropFirst() where variant.count <= Self.maxPhraseLength {
            merge(phrases(variant[...]), Self.splitBonus)
        }
        var list = order.enumerated().map { (i, text) in (i, Scored(text: text, score: best[text]!)) }
        list.sort { $0.1.score != $1.1.score ? $0.1.score > $1.1.score : $0.0 < $1.0 }
        let result = list.map { $0.1 }
        fuzzyCache[key] = result
        return result
    }

    /// 一個音節可能是哪些音打錯了（只留字典裡真的有的）
    func alternatives(for reading: String) -> [(reading: String, penalty: Double)] {
        if let cached = alternativeCache[reading] { return cached }
        if reading.hasSuffix("*") { return [] }   // 沒打完的音節本來就聲調不限，不用再猜
        var syllable = Syllable()
        for c in reading { syllable.put(c) }
        var out: [(reading: String, penalty: Double)] = []
        var seen: Set<String> = [reading]
        func add(_ s: Syllable, _ penalty: Double) {
            let r = s.reading
            guard s.hasSound, !seen.contains(r) else { return }
            seen.insert(r)
            if !phrases([r][...]).isEmpty { out.append((r, penalty)) }
        }

        if fuzzy.tones {
            for tone in [nil, "ˊ", "ˇ", "ˋ", "˙"] as [Character?] where tone != syllable.tone {
                var s = syllable
                s.tone = tone
                add(s, Self.tonePenalty)
            }
        }
        if fuzzy.phonetic {
            if let i = syllable.initial, let swap = Bopomofo.similar[i] {
                var s = syllable
                s.initial = swap
                add(s, Self.phoneticPenalty)
            }
            if let f = syllable.rhyme, let swap = Bopomofo.similar[f] {
                var s = syllable
                s.rhyme = swap
                add(s, Self.phoneticPenalty)
            }
        }
        // 打出來的音根本不存在：多半是按到旁邊的鍵
        if fuzzy.keyNeighbors && phrases([reading][...]).isEmpty {
            for c in reading {
                for n in Bopomofo.neighbors[c] ?? [] {
                    var s = syllable
                    switch Bopomofo.kind(of: c) {
                    case .initial: s.initial = nil
                    case .medial: s.medial = nil
                    case .rhyme: s.rhyme = nil
                    case .tone: s.tone = nil
                    case nil: continue
                    }
                    s.put(n)
                    add(s, Self.neighborPenalty)
                }
            }
        }
        alternativeCache[reading] = out
        return out
    }

    /// 整串注音分數最高的斷法
    func bestSegments(_ readings: [String]) -> [Scored] {
        let readings = Self.settleSplits(readings)
        let n = readings.count
        guard n > 0 else { return [] }
        var best = [Double](repeating: -.infinity, count: n + 1)
        var back = [(start: Int, text: String, score: Double)](repeating: (0, "", 0), count: n + 1)
        best[0] = 0
        for i in 1...n {
            for k in 1...min(Self.maxPhraseLength, i) {
                let start = i - k
                guard best[start] > -.infinity else { continue }
                if let top = fuzzyPhrases(readings[start..<i]).first {
                    let s = best[start] + top.score
                    if s > best[i] {
                        best[i] = s
                        back[i] = (start, top.text, top.score)
                    }
                } else if k == 1 {
                    let s = best[start] + Self.unknownPenalty
                    if s > best[i] {
                        best[i] = s
                        back[i] = (start, Self.display(readings[start]), Self.unknownPenalty)
                    }
                }
            }
        }
        var segments: [Scored] = []
        var i = n
        while i > 0 {
            let b = back[i]
            segments.append(Scored(text: b.text, score: b.score))
            i = b.start
        }
        return segments.reversed()
    }

    /// 候選字：第一個是整句，接著是預測的詞，再來是從開頭算起最長到最短的詞
    func candidates(for readings: [String]) -> [Candidate] {
        guard !readings.isEmpty else { return [] }
        let readings = Self.settleSplits(readings)
        var out: [Candidate] = []
        var seen = Set<String>()
        if readings.count > 1 {
            let sentence = bestSegments(readings).map { $0.text }.joined()
            out.append(Candidate(text: sentence, span: readings.count, kind: .sentence))
            seen.insert(sentence)
        }
        var hasSingle = false
        for k in stride(from: min(Self.maxPhraseLength, readings.count), through: 1, by: -1) {
            for p in fuzzyPhrases(readings[0..<k]) where !seen.contains(p.text) {
                seen.insert(p.text)
                out.append(Candidate(text: p.text, span: k, kind: .phrase))
                if k == 1 { hasSingle = true }
            }
        }
        if !hasSingle {
            out.append(Candidate(text: Self.display(readings[0]), span: 1, kind: .literal))
        }
        // 單獨一個 ㄨㄢ 也可能是簡拼的兩個字（晚安）：拆開最好的詞放第二個，學過、分數比單字高就放第一個
        if readings.count == 1, let parts = Self.splitAbbreviation(readings[0] + "~"),
           let best = phrases(parts[...]).first, !seen.contains(best.text) {
            let top = fuzzyPhrases(readings[...]).first?.score ?? -.infinity
            if best.score > top - Self.loneSplitRange {
                seen.insert(best.text)
                out.insert(Candidate(text: best.text, span: 1, kind: .phrase), at: best.score > top ? 0 : min(1, out.count))
            }
        }
        // 第一個（按空白送出的）還是照打的字，預測的詞接在它後面
        let predicted = predictions(for: readings).filter { !seen.contains($0.text) }
        out.insert(contentsOf: predicted.map { Candidate(text: $0.text, span: readings.count, kind: .phrase, reading: $0.reading) },
                   at: min(1, out.count))
        return out
    }

    /// 預測：打完整的字（有聲調）就先列出以它們開頭的詞，例如 ㄏㄠˇ → 好像、好的；學過的詞排最前面
    func predictions(for readings: [String], limit: Int = 8) -> [(text: String, reading: String)] {
        guard column == "reading", !readings.isEmpty, readings.allSatisfy({ !$0.contains("*") }) else { return [] }
        let head = readings.joined(separator: "-") + "-"
        var out: [(text: String, reading: String)] = []
        var seen = Set<String>()
        for learned in userModel.learned(startingWith: head) where seen.insert(learned.phrase).inserted {
            out.append((learned.phrase, learned.reading))
        }
        db.run("SELECT phrase, reading, MAX(score) AS s FROM phrases WHERE reading > ?1 AND reading < ?2 GROUP BY phrase ORDER BY s DESC LIMIT ?3",
               [.text(head), .text(head + "\u{10FFFF}"), .int(limit)]) { stmt in
            let phrase = SQLiteDB.text(stmt, 0)
            if seen.insert(phrase).inserted { out.append((phrase, SQLiteDB.text(stmt, 1))) }
        }
        return Array(out.prefix(limit))
    }

    /// 所有音節（沒聲調）的開頭，例如 ㄋㄧㄠ → ㄋ、ㄋㄧ、ㄋㄧㄠ（給組字用，判斷注音能不能接在一起）
    func syllablePrefixes() -> Set<String> {
        var out = Set<String>()
        db.run("SELECT DISTINCT plain FROM phrases WHERE plain NOT LIKE '%-%'") { stmt in
            let s = SQLiteDB.text(stmt, 0)
            var prefix = ""
            for c in s {
                prefix.append(c)
                out.insert(prefix)
            }
        }
        return out
    }

    /// 聯想詞：打完一個字後，接在它後面常見的字詞
    func associations(after text: String, limit: Int = 30) -> [String] {
        guard let last = text.last else { return [] }
        let head = String(last)
        var out: [String] = []
        db.run("SELECT phrase, MAX(score) AS s FROM phrases WHERE phrase > ?1 AND phrase < ?2 GROUP BY phrase ORDER BY s DESC LIMIT ?3",
               [.text(head), .text(head + "\u{10FFFF}"), .int(limit)]) { stmt in
            let phrase = SQLiteDB.text(stmt, 0)
            guard phrase.count > 1, phrase.hasPrefix(head) else { return }
            out.append(String(phrase.dropFirst()))
        }
        return out
    }

    /// 使用者選了某個詞：之後這個詞會排更前面
    func learn(readings: [String], text: String) {
        // 簡拼拆開選到的詞（ㄎㄞ*~ 選了「可愛」、單獨的 ㄨㄢ* 選了「晚安」）記成拆開的讀音（ㄎ*-ㄞ*）；
        // 字數對不上就是沒拆（選了「開」）
        func parts(_ r: String) -> [String]? { Self.splitAbbreviation(r.hasSuffix("*") ? r + "~" : r) }
        let splits = readings.compactMap(parts)
        let split = !splits.isEmpty && text.count == readings.count + splits.count
        let used = readings.flatMap { r -> [String] in
            if split, let parts = parts(r) { return parts }
            return [r.hasSuffix("~") ? String(r.dropLast()) : r]
        }
        guard !used.isEmpty, used.count <= Self.maxPhraseLength else { return }
        userModel.record(reading: used.joined(separator: "-"), phrase: text)
        cache.removeAll()
        fuzzyCache.removeAll()
        alternativeCache.removeAll()
    }

    func resetLearning() {
        userModel.reset()
        cache.removeAll()
        fuzzyCache.removeAll()
        alternativeCache.removeAll()
    }
}

/// 記住使用者選過的字詞
final class UserPhraseModel {
    private var counts: [String: [String: Int]] = [:]
    private let fileURL: URL?
    private var matchingCache: [String: [String: Int]] = [:]

    init(fileURL: URL?) {
        self.fileURL = fileURL
        if let url = fileURL, let saved = JSONFile.load([String: [String: Int]].self, from: url) {
            counts = saved
        }
    }

    /// 只記字、不管怎麼拼的那一欄（key 是空字串）
    private static let anyReading = ""

    /// 同樣的打法選過：每次加 0.8（log10，大約變成 6 倍常用），最多算 5 次；
    /// 不管用什麼打法，這個字詞選過就再加一點（每次 0.4，最多 5 次）
    func boost(reading: String, phrase: String) -> Double {
        let same = min(Double(matchingCounts(for: reading)[phrase] ?? 0), 5) * 0.8
        let any = min(Double(counts[Self.anyReading]?[phrase] ?? 0), 5) * 0.4
        return same + any
    }

    func phrases(for reading: String) -> [String] {
        guard !reading.isEmpty else { return [] }
        return matchingCounts(for: reading).keys.sorted()
    }

    /// 學過、完整讀音以 prefix 開頭的詞（選越多次越前面），給預測用
    func learned(startingWith prefix: String) -> [(reading: String, phrase: String)] {
        var out: [(reading: String, phrase: String, count: Int)] = []
        for (saved, phrases) in counts where saved.hasPrefix(prefix) && !saved.contains("*") {
            for (phrase, count) in phrases { out.append((saved, phrase, count)) }
        }
        out.sort { $0.count != $1.count ? $0.count > $1.count : $0.phrase < $1.phrase }
        return out.map { ($0.reading, $0.phrase) }
    }

    // 完整讀音和省略聲調／只打開頭的讀音也共用已選字詞；不混用不同的聲調。
    private func matchingCounts(for reading: String) -> [String: Int] {
        if let cached = matchingCache[reading] { return cached }
        let query = reading.split(separator: "-")
        var result: [String: Int] = [:]
        for (saved, phrases) in counts where !saved.isEmpty {
            let parts = saved.split(separator: "-")
            guard parts.count == query.count else { continue }
            let matches = zip(query, parts).allSatisfy { want, have in
                want == have ||
                ZhuyinEngine.matchPenalty([want], [have]) != nil ||
                ZhuyinEngine.matchPenalty([have], [want]) != nil
            }
            if matches {
                for (phrase, count) in phrases { result[phrase] = max(result[phrase] ?? 0, count) }
            }
        }
        matchingCache[reading] = result
        return result
    }

    func record(reading: String, phrase: String) {
        guard !reading.isEmpty, !phrase.isEmpty else { return }
        matchingCache.removeAll()
        counts[reading, default: [:]][phrase, default: 0] += 1
        counts[Self.anyReading, default: [:]][phrase, default: 0] += 1
        save()
    }

    func reset() {
        counts = [:]
        matchingCache.removeAll()
        save()
    }

    private func save() {
        if let url = fileURL { JSONFile.save(counts, to: url) }
    }
}
