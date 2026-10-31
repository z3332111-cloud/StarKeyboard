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
        var corrections: Int = 0
    }

    static let maxPhraseLength = 6
    /// 查不到的音節的分數（字典分數是 log10 機率，大約 -2 到 -8）
    static let unknownPenalty: Double = -30
    /// 使用者自己學到、字典沒有的詞
    static let userPhraseBase: Double = -6

    /// 整份字典。注音和拼音各有一個引擎，但可以共用同一個索引。
    private let index: PhraseIndex
    /// 用哪一欄查：注音用 reading（有聲調），拼音用 plain（沒聲調）
    private let column: String
    private var cache: [String: [Scored]] = [:]
    private var lookupCache: [String: [(phrase: String, score: Double)]] = [:]
    private var fuzzyCache: [String: [Scored]] = [:]
    private struct Completion {
        let text: String
        let reading: String
        let score: Double
    }
    // 只快取本機查詢；同一句話打不同注音時不重查前文，避免每按一鍵掃字典。
    private var predictionRows: [String: [Completion]] = [:]
    private var contextCache: [String: [Completion]] = [:]
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
    /// 選字可能在背景跑，和主執行緒的學習、送出共用同一把鎖。
    private let queryLock = NSRecursiveLock()

    init(db: SQLiteDB, userModel: UserPhraseModel, column: String = "reading", sharedIndex: PhraseIndex? = nil) {
        // 建索引只發生在鍵盤打開時（或測試建立引擎時），不發生在每個按鍵。
        self.index = sharedIndex ?? PhraseIndex.load(from: db)
        self.userModel = userModel
        self.column = column
    }

    convenience init?(path: String, userModel: UserPhraseModel, column: String = "reading") {
        guard let db = SQLiteDB(path: path) else { return nil }
        self.init(db: db, userModel: userModel, column: column)
    }

    /// 同一份字典、另一份學習紀錄。評測重載學習檔時不必再讀一次字典。
    init(index: PhraseIndex, userModel: UserPhraseModel, column: String = "reading") {
        self.index = index
        self.userModel = userModel
        self.column = column
    }

    func sharingIndex(userModel: UserPhraseModel) -> ZhuyinEngine {
        ZhuyinEngine(index: index, userModel: userModel, column: column)
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
        if let cached = lookupCache[key] { return cached }
        var out: [(phrase: String, score: Double)] = []
        defer {
            if lookupCache.count >= 512 { lookupCache.removeAll() }
            lookupCache[key] = out
        }
        guard key.contains("*") else {
            let ids = column == "plain" ? index.byPlain[key] : index.byReading[key]
            for id in ids ?? [] {
                let row = index.rows[id]
                out.append((row.phrase, row.score))
            }
            return out
        }
        let pattern = key.split(separator: "-")
        let abbr = String(pattern.compactMap { $0.first })
        var best: [String: Double] = [:]
        let toneless = column == "plain"
        // 索引已按分數由高到低。罰分只會更低，所以後面的列不可能再擠進前 80 名時就可以停。
        var floor = -Double.greatestFiniteMagnitude
        for id in index.byAbbr[abbr] ?? [] {
            let row = index.rows[id]
            if best.count >= 80 && row.score <= floor { break }
            guard let penalty = Self.matchPenalty(pattern, row.reading.split(separator: "-"), ignoreTones: toneless) else { continue }
            let s = row.score + penalty
            if let old = best[row.phrase], old >= s { continue }
            best[row.phrase] = s
            if best.count >= 80 {
                floor = best.values.sorted(by: >)[79]
            }
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
        // 選過一次就排在沒選過的前面；次數一樣再看最近一次，然後才是詞頻。
        list.sort { a, b in
            let pa = userModel.preference(reading: key, phrase: a.1.text)
            let pb = userModel.preference(reading: key, phrase: b.1.text)
            if pa.count != pb.count { return pa.count > pb.count }
            if pa.recency != pb.recency { return pa.recency > pb.recency }
            if a.1.score != b.1.score { return a.1.score > b.1.score }
            return a.0 < b.0
        }
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
        var corrections: [String: Int] = [:]
        func merge(_ list: [Scored], _ penalty: Double, corrected: Bool = false) {
            for p in list {
                let s = p.score + penalty
                let errors = corrected ? 1 : 0
                if let old = best[p.text] {
                    if errors < corrections[p.text]! || (errors == corrections[p.text]! && s > old) {
                        best[p.text] = s
                        corrections[p.text] = errors
                    }
                } else {
                    best[p.text] = s
                    corrections[p.text] = errors
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
                merge(phrases(variant[...]), alt.penalty, corrected: true)
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
        var list = order.enumerated().map { (i, text) in (i, Scored(text: text, score: best[text]!, corrections: corrections[text]!)) }
        // 容錯只排在符合輸入的候選後面，學習分數不能蓋過已輸入的音。
        list.sort {
            if $0.1.corrections != $1.1.corrections { return $0.1.corrections < $1.1.corrections }
            return $0.1.score != $1.1.score ? $0.1.score > $1.1.score : $0.0 < $1.0
        }
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

    /// 整串注音分數最高的斷法。contextual 用前後文在同音詞裡挑；關掉就是只看詞頻的對照。
    func bestSegments(_ readings: [String], contextual: Bool = true) -> [Scored] {
        queryLock.lock()
        defer { queryLock.unlock() }
        return segmentation(of: Self.settleSplits(readings), contextual: contextual).map {
            Scored(text: $0.text, score: $0.score)
        }
    }

    /// 斷詞，附上每一段用掉的起始音節。呼叫端要已持有 queryLock。
    private func segmentation(of readings: [String], contextual: Bool) -> [(start: Int, text: String, score: Double)] {
        let n = readings.count
        guard n > 0 else { return [] }
        var best = [Double](repeating: -.infinity, count: n + 1)
        var errors = [Int](repeating: Int.max, count: n + 1)
        var back = [(start: Int, text: String, score: Double)](repeating: (0, "", 0), count: n + 1)
        var tail = [String](repeating: "", count: n + 1)
        best[0] = 0
        errors[0] = 0
        for i in 1...n {
            for k in 1...min(Self.maxPhraseLength, i) {
                let start = i - k
                guard best[start] > -.infinity else { continue }
                let pool = fuzzyPhrases(readings[start..<i]).filter { !PhoneticText.containsPhonetic($0.text) }
                if let floor = pool.first?.corrections {
                    let options = contextual
                        ? Array(pool.prefix(6).filter { $0.corrections == floor })
                        : Array(pool.prefix(1))
                    // 詞頻最高的那個維持原分。前後文只幫忙分很接近的同音詞，避免把本來對的句子改錯。
                    let leaderBonus = contextual && !options.isEmpty
                        ? index.contextBonus(tail: tail[start], phrase: options[0].text) : 0
                    for opt in options {
                        let raw = contextual ? index.contextBonus(tail: tail[start], phrase: opt.text) : 0
                        let extra = min(0.55, max(0, raw - leaderBonus))
                        let s = best[start] + opt.score + extra
                        let count = errors[start] + opt.corrections
                        if count < errors[i] || (count == errors[i] && s > best[i]) {
                            errors[i] = count
                            best[i] = s
                            back[i] = (start, opt.text, opt.score + extra)
                            tail[i] = String((tail[start] + opt.text).suffix(2))
                        }
                    }
                } else if k == 1 {
                    let s = best[start] + Self.unknownPenalty
                    let count = errors[start] + 1
                    if count < errors[i] || (count == errors[i] && s > best[i]) {
                        errors[i] = count
                        best[i] = s
                        // 查不到就留空，不要把注音或聲調送進文章。
                        back[i] = (start, "", Self.unknownPenalty)
                        tail[i] = tail[start]
                    }
                }
            }
        }
        var parts: [(start: Int, text: String, score: Double)] = []
        var i = n
        while i > 0 {
            let b = back[i]
            parts.append((b.start, b.text, b.score))
            if b.start >= i { break }
            i = b.start
        }
        return parts.reversed()
    }

    /// 送出整句時要記住的每一段（讀音、字）。
    func segmentSpans(_ readings: [String]) -> [(readings: [String], text: String)] {
        queryLock.lock()
        defer { queryLock.unlock() }
        let readings = Self.settleSplits(readings)
        let parts = segmentation(of: readings, contextual: true)
        return parts.enumerated().map { index, part in
            let end = index + 1 < parts.count ? parts[index + 1].start : readings.count
            return (Array(readings[part.start..<end]), part.text)
        }
    }

    /// 只打了聲母（每個音節最多一個注音）。這時罕見詞要讓給常見詞。
    static func isInitialsQuery(_ readings: [String]) -> Bool {
        !readings.isEmpty && readings.allSatisfy { reading in
            reading.filter { $0 != "*" && $0 != "~" && !Bopomofo.tones.contains($0) }.count <= 1
        }
    }

    /// 只打聲母時，調整後分數低於這條線、又沒學過的詞，排在常見詞後面。
    /// 聲母查詢每個音節約扣 1，所以線畫在完整讀音罕見線（約 -5）再往下。
    static let initialsRareScore = -6.2

    private struct Ranked {
        var text: String
        var span: Int
        var score: Double
        var corrections: Int
        var order: Int
    }

    /// 候選字：和打進去的音節一樣長的詞在最前面（學過的優先，然後詞頻；完整讀音優先於簡拼）。
    /// 比輸入更長的預測最多兩個，而且不能排在同長度的詞前面。
    func candidates(for readings: [String], before context: String = "") -> [Candidate] {
        queryLock.lock()
        defer { queryLock.unlock() }
        return rankedCandidates(for: readings, before: context)
    }

    /// 改排名之前的舊順序，只給對照評測用。
    func legacyCandidates(for readings: [String], before context: String = "") -> [Candidate] {
        queryLock.lock()
        defer { queryLock.unlock() }
        guard !readings.isEmpty else { return [] }
        let readings = Self.settleSplits(readings)
        var out: [Candidate] = []
        var seen = Set<String>()
        if readings.count > 1 {
            let sentence = segmentation(of: readings, contextual: true).map { $0.text }.joined()
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
        if readings.count == 1, let parts = Self.splitAbbreviation(readings[0] + "~"),
           let best = phrases(parts[...]).first, !seen.contains(best.text) {
            let top = fuzzyPhrases(readings[...]).first?.score ?? -.infinity
            if best.score > top - Self.loneSplitRange {
                seen.insert(best.text)
                out.insert(Candidate(text: best.text, span: 1, kind: .phrase), at: best.score > top ? 0 : min(1, out.count))
            }
        }
        let related = completions(after: context)
        if readings.count == 1, !related.isEmpty {
            let scores = Dictionary(fuzzyPhrases(readings[...]).filter { $0.corrections == 0 }.map { ($0.text, $0.score) },
                                    uniquingKeysWith: max)
            let ranked = out.enumerated().filter { $0.element.text.count == 1 && scores[$0.element.text] != nil }
                .map { index, candidate -> (Int, Double) in
                    let support = related.filter {
                        $0.text.hasPrefix(candidate.text) &&
                        Self.matchPenalty([Substring(Self.displayQuery(readings[0]))],
                                          Array($0.reading.split(separator: "-").prefix(1))) != nil
                    }.map { max(0, min(1.8, 5 + $0.score)) }.max() ?? 0
                    return (index, (scores[candidate.text] ?? Self.userPhraseBase) + support)
                }.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
            if out.first?.text.count == 1, let winner = ranked.first, winner.0 != 0 {
                out.insert(out.remove(at: winner.0), at: 0)
            }
        }
        let pattern = readings.map { Substring(Self.displayQuery($0)) }
        let contextual = related.filter {
            let full = $0.reading.split(separator: "-")
            return full.count > readings.count &&
                Self.matchPenalty(pattern, Array(full.prefix(readings.count))) != nil
        }
        var ordinary = predictions(for: readings)
        if readings.contains(where: { $0.contains("*") }), let leading = out.first, leading.kind != .literal {
            ordinary = ordinary.filter { $0.text.hasPrefix(leading.text) } +
                ordinary.filter { !$0.text.hasPrefix(leading.text) }
        }
        let predicted = contextual.map { (text: $0.text, reading: $0.reading) } + ordinary.map { (text: $0.text, reading: $0.reading) }
        var extras: [Candidate] = []
        for p in predicted where seen.insert(p.text).inserted {
            extras.append(Candidate(text: p.text, span: readings.count, kind: .phrase, reading: p.reading))
            if extras.count == 3 { break }
        }
        out.insert(contentsOf: extras, at: min(1, out.count))
        return out.filter { !$0.text.isEmpty && !PhoneticText.containsPhonetic($0.text) }
    }

    private func rankedCandidates(for readings: [String], before context: String) -> [Candidate] {
        guard !readings.isEmpty else { return [] }
        let readings = Self.settleSplits(readings)
        let n = readings.count
        let initials = Self.isInitialsQuery(readings)
        var exact: [Ranked] = []
        var shorter: [Ranked] = []
        var seen = Set<String>()
        var order = 0
        for k in 1...min(Self.maxPhraseLength, n) {
            for p in fuzzyPhrases(readings[0..<k]) {
                guard !p.text.isEmpty, !PhoneticText.containsPhonetic(p.text), seen.insert(p.text).inserted else { continue }
                let item = Ranked(text: p.text, span: k, score: p.score, corrections: p.corrections, order: order)
                order += 1
                if k == n { exact.append(item) } else { shorter.append(item) }
            }
        }
        exact = sorted(exact, readings: readings, initials: initials)
        shorter = sorted(shorter, readings: readings, initials: initials)
        if n == 1 { exact = promoteContext(exact, readings: readings, context: context) }

        var sentence = ""
        if let cover = exact.first(where: { $0.corrections == 0 && $0.text.count == n }) {
            sentence = cover.text
        } else if n > 1 {
            sentence = composedSentence(readings)
        }
        var out: [Candidate] = []
        var listed = Set<String>()
        if n > 1, !sentence.isEmpty, !PhoneticText.containsPhonetic(sentence) {
            out.append(Candidate(text: sentence, span: n, kind: .sentence))
            listed.insert(sentence)
        }
        for item in exact where listed.insert(item.text).inserted {
            out.append(Candidate(text: item.text, span: item.span, kind: .phrase))
        }
        for item in shorter where listed.insert(item.text).inserted {
            out.append(Candidate(text: item.text, span: item.span, kind: .phrase))
        }
        for extra in longerSuggestions(readings: readings, context: context, initials: initials, leading: out.first?.text, seen: &listed) {
            out.append(extra)
        }
        // 單獨一個 ㄨㄢ 也可能是簡拼的兩個字。學過、分數比單字高就放第一個，否則放第二個。
        if readings.count == 1, let parts = Self.splitAbbreviation(readings[0] + "~"),
           let best = phrases(parts[...]).first {
            let top = fuzzyPhrases(readings[...]).first?.score ?? -.infinity
            if best.score > top - Self.loneSplitRange {
                let at = best.score > top ? 0 : min(1, out.count)
                if let existing = out.firstIndex(where: { $0.text == best.text }) {
                    let item = out.remove(at: existing)
                    out.insert(item, at: min(at, out.count))
                } else {
                    out.insert(Candidate(text: best.text, span: 1, kind: .phrase), at: at)
                }
            }
        }
        if !out.contains(where: { $0.span == 1 && $0.kind == .phrase }) {
            out.append(Candidate(text: Self.display(readings[0]), span: 1, kind: .literal))
        }
        return out.filter { !$0.text.isEmpty && !PhoneticText.containsPhonetic($0.text) }
    }

    private func sorted(_ items: [Ranked], readings: [String], initials: Bool) -> [Ranked] {
        items.sorted { a, b in
            let keyA = readings.prefix(a.span).joined(separator: "-")
            let keyB = readings.prefix(b.span).joined(separator: "-")
            let pa = userModel.preference(reading: keyA, phrase: a.text)
            let pb = userModel.preference(reading: keyB, phrase: b.text)
            // 帶 ~ 的音節本來就可能是兩個字（ㄎㄞ → 可愛），這種拆法要照分數排，不能當成「比較長的預測」。
            if !readings.contains(where: { $0.contains("~") }) {
                let fitA = a.text.count == a.span
                let fitB = b.text.count == b.span
                if fitA != fitB { return fitA }
            }
            // 打對的音優先於聲調猜錯。學過的字只在同樣準的候選裡往前排。
            if a.corrections != b.corrections { return a.corrections < b.corrections }
            if pa.count != pb.count { return pa.count > pb.count }
            if pa.recency != pb.recency { return pa.recency > pb.recency }
            if initials {
                let rareA = pa.count == 0 && a.score < Self.initialsRareScore
                let rareB = pb.count == 0 && b.score < Self.initialsRareScore
                if rareA != rareB { return rareB }
            }
            if a.score != b.score { return a.score > b.score }
            return a.order < b.order
        }
    }

    /// 前文只在沒學過的單字之間把最合適的那個移到前面，不蓋過已經選過的字。
    private func promoteContext(_ items: [Ranked], readings: [String], context: String) -> [Ranked] {
        guard readings.count == 1 else { return items }
        let related = completions(after: context)
        guard !related.isEmpty else { return items }
        let scores = Dictionary(fuzzyPhrases(readings[...]).filter { $0.corrections == 0 }.map { ($0.text, $0.score) },
                                uniquingKeysWith: max)
        let key = readings.joined(separator: "-")
        let learned = items.filter { $0.corrections == 0 && userModel.preference(reading: key, phrase: $0.text).count > 0 }
        var rest = items.filter { item in !learned.contains { $0.text == item.text && $0.span == item.span } }
        func support(_ text: String) -> Double {
            guard text.count == 1 else { return 0 }
            return related.filter {
                $0.text.hasPrefix(text) &&
                Self.matchPenalty([Substring(Self.displayQuery(readings[0]))],
                                  Array($0.reading.split(separator: "-").prefix(1))) != nil
            }.map { max(0, min(1.8, 5 + $0.score)) }.max() ?? 0
        }
        guard let best = rest.indices.max(by: { i, j in
            let si = (scores[rest[i].text] ?? rest[i].score) + support(rest[i].text)
            let sj = (scores[rest[j].text] ?? rest[j].score) + support(rest[j].text)
            if si != sj { return si < sj }
            return rest[i].order > rest[j].order
        }), rest[best].text.count == 1, best != 0 else { return learned + rest }
        let winner = rest.remove(at: best)
        rest.insert(winner, at: 0)
        return learned + rest
    }

    /// 字典詞蓋不住整段時，用斷詞。若多字詞後面又接了同一個字（就是＋是），改成下一個同音字。
    private func composedSentence(_ readings: [String]) -> String {
        let parts = segmentation(of: readings, contextual: true)
        let joined = parts.map { $0.text }.joined()
        var chars = Array(joined)
        guard chars.count == readings.count else { return joined }
        var singleton = Set<Int>()
        var cursor = 0
        for part in parts {
            if part.text.count == 1 { singleton.insert(cursor) }
            cursor += max(part.text.count, 1)
        }
        let n = readings.count
        for k in stride(from: min(Self.maxPhraseLength, n - 1), through: 2, by: -1) {
            guard let word = fuzzyPhrases(readings[0..<k]).first(where: { $0.corrections == 0 && $0.text.count == k }) else { continue }
            let w = Array(word.text)
            guard w.count == k, chars.starts(with: w), chars[k] == w[k - 1], singleton.contains(k) else { continue }
            let banned = String(w[k - 1])
            if let alt = phrases(readings[k...k]).first(where: { $0.text.count == 1 && $0.text != banned }) {
                chars[k] = Array(alt.text)[0]
                return String(chars)
            }
        }
        return joined
    }

    private func longerSuggestions(readings: [String], context: String, initials: Bool, leading: String?, seen: inout Set<String>) -> [Candidate] {
        let related = completions(after: context)
        let pattern = readings.map { Substring(Self.displayQuery($0)) }
        let contextual = related.filter {
            let full = $0.reading.split(separator: "-")
            return full.count > readings.count &&
                Self.matchPenalty(pattern, Array(full.prefix(readings.count))) != nil
        }.map { (text: $0.text, reading: $0.reading, score: $0.score) }
        var ordinary = predictions(for: readings)
        if readings.contains(where: { $0.contains("*") }), let leading, !leading.isEmpty {
            ordinary = ordinary.filter { $0.text.hasPrefix(leading) } + ordinary.filter { !$0.text.hasPrefix(leading) }
        }
        var pool: [(text: String, reading: String, score: Double, order: Int)] = []
        for (i, item) in (contextual + ordinary).enumerated() where item.text.count > readings.count {
            pool.append((item.text, item.reading, item.score, i))
        }
        pool.sort { a, b in
            let pa = userModel.preference(reading: a.reading, phrase: a.text)
            let pb = userModel.preference(reading: b.reading, phrase: b.text)
            if pa.count != pb.count { return pa.count > pb.count }
            if pa.recency != pb.recency { return pa.recency > pb.recency }
            if a.score != b.score { return a.score > b.score }
            return a.order < b.order
        }
        var extras: [Candidate] = []
        for item in pool {
            let picked = userModel.preference(reading: item.reading, phrase: item.text).count
            if initials && picked == 0 && item.score < Self.initialsRareScore { continue }
            guard seen.insert(item.text).inserted else { continue }
            extras.append(Candidate(text: item.text, span: readings.count, kind: .phrase, reading: item.reading))
            if extras.count == 2 { break }
        }
        return extras
    }

    private static func displayQuery(_ reading: String) -> String {
        reading.hasSuffix("~") ? String(reading.dropLast()) : reading
    }

    /// 沒打聲調也先預測詞；保留完整讀音，選取後才能正確學習。
    func predictions(for readings: [String], limit: Int = 8) -> [(text: String, reading: String, score: Double)] {
        guard column == "reading", !readings.isEmpty, readings.count < Self.maxPhraseLength, limit > 0 else { return [] }
        let input = readings.map { Self.displayQuery($0) }
        let pattern = input.map { Substring($0) }
        let key = input.joined(separator: "-")
        let rows: [Completion]
        if let cached = predictionRows[key] {
            rows = cached
        } else {
            var found: [Completion] = []
            let first = input[0]
            let ids: [Int]
            if first.contains("*") {
                let plain = String(first.filter { !Bopomofo.tones.contains($0) && $0 != "*" && $0 != "~" })
                ids = index.longerByFirstPlain[plain] ?? []
            } else {
                ids = index.longerByFirst[String(first)] ?? []
            }
            for id in ids {
                let row = index.rows[id]
                found.append(Completion(text: row.phrase, reading: row.reading, score: row.score))
            }
            if predictionRows.count >= 64 { predictionRows.removeAll() }
            predictionRows[key] = found
            rows = found
        }
        let learned = userModel.learnedPhrases().map {
            Completion(text: $0.phrase, reading: $0.reading, score: Self.userPhraseBase)
        }
        var best: [String: Completion] = [:]
        for row in rows + learned {
            let full = row.reading.split(separator: "-")
            guard full.count > input.count, full.count <= Self.maxPhraseLength,
                  let penalty = Self.matchPenalty(pattern, Array(full.prefix(input.count))) else { continue }
            let score = row.score + penalty + userModel.boost(reading: row.reading, phrase: row.text)
            if let old = best[row.text], old.score >= score { continue }
            best[row.text] = Completion(text: row.text, reading: row.reading, score: score)
        }
        return best.values.sorted {
            $0.score != $1.score ? $0.score > $1.score : $0.text < $1.text
        }.prefix(limit).map { (text: $0.text, reading: $0.reading, score: $0.score) }
    }

    /// 只取游標前連續中文的末三字；標點、空格、換行會中斷前文。
    private static func contextTail(_ text: String) -> String {
        String(text.suffix(3).reversed().prefix { ch in
            ch.unicodeScalars.allSatisfy {
                (0x3400...0x9FFF).contains($0.value) || (0x20000...0x323AF).contains($0.value)
            }
        }.reversed())
    }

    private func completions(after text: String) -> [Completion] {
        let tail = Self.contextTail(text)
        guard !tail.isEmpty else { return [] }
        if let cached = contextCache[tail] { return cached }
        var best: [String: Completion] = [:]
        let learned = userModel.learnedPhrases()
        for length in stride(from: tail.count, through: 1, by: -1) {
            let head = String(tail.suffix(length))
            var rows: [Completion] = []
            if let ch = head.first {
                for id in index.byFirstChar[ch] ?? [] {
                    let row = index.rows[id]
                    guard row.phrase.hasPrefix(head) else { continue }
                    rows.append(Completion(text: row.phrase, reading: row.reading, score: row.score))
                    if rows.count == 80 { break }
                }
            }
            rows += learned.filter { $0.phrase.hasPrefix(head) && $0.phrase.count > length }.map {
                Completion(text: $0.phrase, reading: $0.reading, score: Self.userPhraseBase)
            }
            for row in rows where row.text.hasPrefix(head) {
                let sounds = row.reading.split(separator: "-")
                guard sounds.count == row.text.count, sounds.count > length else { continue }
                let rest = String(row.text.dropFirst(length))
                let score = row.score + Double(length - 1) * 1.5 +
                    userModel.boost(reading: row.reading, phrase: row.text)
                if let old = best[rest], old.score >= score { continue }
                best[rest] = Completion(text: rest, reading: sounds.dropFirst(length).joined(separator: "-"), score: score)
            }
        }
        let result = best.values.sorted { $0.score != $1.score ? $0.score > $1.score : $0.text < $1.text }
        if contextCache.count >= 64 { contextCache.removeAll() }
        contextCache[tail] = result
        return result
    }

    /// 所有音節（沒聲調）的開頭，例如 ㄋㄧㄠ → ㄋ、ㄋㄧ、ㄋㄧㄠ（給組字用，判斷注音能不能接在一起）
    func syllablePrefixes() -> Set<String> {
        index.prefixes
    }

    /// 聯想整段前文的後續詞，較長的吻合與常用詞優先，也包含已學會的片語。
    func associations(after text: String, limit: Int = 30) -> [String] {
        queryLock.lock()
        defer { queryLock.unlock() }
        guard limit > 0 else { return [] }
        return completions(after: text).prefix(limit).map { $0.text }
    }

    /// 使用者選了某個詞：之後這個詞會排更前面
    func learn(readings: [String], text: String) {
        queryLock.lock()
        defer { queryLock.unlock() }
        // 簡拼拆開選到的詞（ㄎㄞ*~ 選了「可愛」、單獨的 ㄨㄢ* 選了「晚安」）記成拆開的讀音（ㄎ*-ㄞ*）；
        // 字數對不上就是沒拆（選了「開」）
        func parts(_ r: String) -> [String]? {
            // 只有單獨一個音節可額外嘗試拆開；多音節時尊重組字器的 ~，
            // 避免把 ㄋㄧ* ㄏ* ㄎㄞ*~ 的「你」也拆開，破壞「你好可愛」的學習。
            Self.splitAbbreviation(readings.count == 1 && r.hasSuffix("*") ? r + "~" : r)
        }
        let splits = readings.compactMap(parts)
        let split = !splits.isEmpty && text.count == readings.count + splits.count
        let used = readings.flatMap { r -> [String] in
            if split, let parts = parts(r) { return parts }
            return [r.hasSuffix("~") ? String(r.dropLast()) : r]
        }
        guard !used.isEmpty, used.count == text.count, used.count <= Self.maxPhraseLength else { return }
        userModel.record(reading: used.joined(separator: "-"), phrase: text)
        contextCache.removeAll()
        cache.removeAll()
        fuzzyCache.removeAll()
        alternativeCache.removeAll()
    }

    /// 記憶體快不夠時：丟掉查過的暫存（之後要用再重查，不會壞）
    func trimCaches() {
        queryLock.lock()
        defer { queryLock.unlock() }
        contextCache.removeAll()
        cache.removeAll()
        fuzzyCache.removeAll()
        alternativeCache.removeAll()
    }

    func resetLearning() {
        queryLock.lock()
        defer { queryLock.unlock() }
        userModel.reset()
        contextCache.removeAll()
        cache.removeAll()
        fuzzyCache.removeAll()
        alternativeCache.removeAll()
    }
}

/// 記住使用者選過的字詞
final class UserPhraseModel {
    struct Preference {
        var count: Int
        var recency: Int
    }

    private struct Snapshot: Codable {
        var counts: [String: [String: Int]]
        var recency: [String: [String: Int]]
        var clock: Int
    }

    /// 學習紀錄上限。超過就丟掉選得少、又比較久沒選的。
    static let entryCap = 2000

    private var counts: [String: [String: Int]] = [:]
    private var recency: [String: [String: Int]] = [:]
    private var clock = 0
    private let fileURL: URL?
    private var prefCache: [String: [String: Preference]] = [:]
    private var readingBuckets: [String: Set<String>] = [:]
    private var wildcardBuckets: [String: Set<String>] = [:]
    private var readingParts: [String: [Substring]] = [:]
    private var learnedCache: [(reading: String, phrase: String)]?
    private let saveQueue = DispatchQueue(label: "keyboard.learning.save", qos: .utility)
    private let asynchronousWrites: Bool

    init(fileURL: URL?, asynchronousWrites: Bool = false) {
        self.asynchronousWrites = asynchronousWrites
        self.fileURL = fileURL
        if let url = fileURL, let data = try? Data(contentsOf: url) {
            if let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
                counts = snap.counts
                recency = snap.recency
                clock = snap.clock
            } else if let saved = try? JSONDecoder().decode([String: [String: Int]].self, from: data) {
                counts = saved
            }
        }
        for reading in counts.keys where !reading.isEmpty { index(reading) }
    }

    private static func bucket(_ parts: [Substring]) -> String {
        String(parts.compactMap { $0.first })
    }

    private func index(_ reading: String) {
        guard readingParts[reading] == nil else { return }
        let parts = reading.split(separator: "-")
        readingParts[reading] = parts
        let key = Self.bucket(parts)
        readingBuckets[key, default: []].insert(reading)
        if reading.contains("*") { wildcardBuckets[key, default: []].insert(reading) }
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
        let query = reading.split(separator: "-")
        // 模糊的舊記錄只能在相同或更寬的輸入下新增候選；不能用 ㄋ* 推斷 ㄋㄠ 的字。
        let eligible = (readingBuckets[Self.bucket(query)] ?? []).filter { saved in
            ZhuyinEngine.matchPenalty(query, readingParts[saved]!) != nil
        }
        return Set(eligible.flatMap { Array(counts[$0, default: [:]].keys) }).sorted()
    }

    /// 可用於詞語補全的完整讀音；不把只記了簡拼的資料當成確定的聲調。
    func learnedPhrases() -> [(reading: String, phrase: String)] {
        if let cached = learnedCache { return cached }
        var out: [(reading: String, phrase: String)] = []
        for (reading, phrases) in counts where !reading.isEmpty && !reading.contains("*") {
            for phrase in phrases.keys { out.append((reading: reading, phrase: phrase)) }
        }
        learnedCache = out
        return out
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

    /// 這個打法（含簡拼、省略聲調）選過幾次、最近一次是何時。沒選過是 (0, 0)。
    func preference(reading: String, phrase: String) -> Preference {
        preferences(for: reading)[phrase] ?? Preference(count: 0, recency: 0)
    }

    func pickCount(reading: String, phrase: String) -> Int {
        preference(reading: reading, phrase: phrase).count
    }

    // 完整讀音和省略聲調／只打開頭的讀音也共用已選字詞；不混用不同的聲調。
    private func matchingCounts(for reading: String) -> [String: Int] {
        preferences(for: reading).mapValues { $0.count }
    }

    private func preferences(for reading: String) -> [String: Preference] {
        if let cached = prefCache[reading] { return cached }
        let query = reading.split(separator: "-")
        var result: [String: Preference] = [:]
        func merge(_ phrases: [String: Int], _ times: [String: Int]) {
            for (phrase, count) in phrases {
                let when = times[phrase] ?? 0
                if let old = result[phrase] {
                    result[phrase] = Preference(count: max(old.count, count), recency: max(old.recency, when))
                } else {
                    result[phrase] = Preference(count: count, recency: when)
                }
            }
        }
        merge(counts[reading] ?? [:], recency[reading] ?? [:])
        let key = Self.bucket(query)
        let possible = reading.contains("*") ? readingBuckets[key] : wildcardBuckets[key]
        for saved in possible ?? [] where saved != reading {
            let parts = readingParts[saved]!
            guard parts.count == query.count else { continue }
            let matches = zip(query, parts).allSatisfy { want, have in
                want == have ||
                ZhuyinEngine.matchPenalty([want], [have]) != nil ||
                ZhuyinEngine.matchPenalty([have], [want]) != nil
            }
            if matches { merge(counts[saved] ?? [:], recency[saved] ?? [:]) }
        }
        if prefCache.count >= 512 { prefCache.removeAll() }
        prefCache[reading] = result
        return result
    }

    /// 每個音節只留第一個注音，讓「選過的完整讀音」在簡拼時也排前面。
    private static func abbreviation(of reading: String) -> String? {
        let parts = reading.split(separator: "-")
        guard !parts.isEmpty else { return nil }
        let abbr = parts.map { part -> String in
            let body = part.filter { $0 != "*" && $0 != "~" && !Bopomofo.tones.contains($0) }
            guard let first = body.first else { return String(part) }
            return String(first) + "*"
        }.joined(separator: "-")
        return abbr == reading ? nil : abbr
    }

    func record(reading: String, phrase: String) {
        guard !reading.isEmpty, !phrase.isEmpty else { return }
        prefCache.removeAll()
        learnedCache = nil
        index(reading)
        clock += 1
        counts[reading, default: [:]][phrase, default: 0] += 1
        recency[reading, default: [:]][phrase] = clock
        counts[Self.anyReading, default: [:]][phrase, default: 0] += 1
        if let abbr = Self.abbreviation(of: reading) {
            index(abbr)
            let count = counts[reading]![phrase]!
            counts[abbr, default: [:]][phrase] = max(counts[abbr]?[phrase] ?? 0, count)
            recency[abbr, default: [:]][phrase] = clock
        }
        trim()
        save()
    }

    private func trim() {
        var entries: [(reading: String, phrase: String, count: Int, when: Int)] = []
        for (reading, phrases) in counts where !reading.isEmpty {
            for (phrase, count) in phrases {
                entries.append((reading, phrase, count, recency[reading]?[phrase] ?? 0))
            }
        }
        guard entries.count > Self.entryCap else { return }
        entries.sort { a, b in
            if a.count != b.count { return a.count < b.count }
            return a.when < b.when
        }
        for item in entries.prefix(entries.count - Self.entryCap) {
            counts[item.reading]?[item.phrase] = nil
            recency[item.reading]?[item.phrase] = nil
            if counts[item.reading]?.isEmpty != false {
                counts[item.reading] = nil
                recency[item.reading] = nil
            }
        }
        var live = Set<String>()
        for (reading, phrases) in counts where !reading.isEmpty { live.formUnion(phrases.keys) }
        if var any = counts[Self.anyReading] {
            for phrase in Array(any.keys) where !live.contains(phrase) { any[phrase] = nil }
            counts[Self.anyReading] = any.isEmpty ? nil : any
        }
    }

    func reset() {
        counts = [:]
        recency = [:]
        clock = 0
        readingBuckets.removeAll()
        wildcardBuckets.removeAll()
        readingParts.removeAll()
        learnedCache = nil
        prefCache.removeAll()
        save()
    }

    func flushPendingWrites() {
        if asynchronousWrites { saveQueue.sync {} }
    }

    private func save() {
        guard let url = fileURL else { return }
        let snapshot = Snapshot(counts: counts, recency: recency, clock: clock)
        if asynchronousWrites {
            // 串行寫入不可亂序；鍵盤收起前會等最後一筆落盤。
            saveQueue.async { JSONFile.save(snapshot, to: url) }
        } else {
            JSONFile.save(snapshot, to: url)
        }
    }
}
