import Foundation

/// 漢語拼音輸入（馬來西亞、中國用）：把字母斷成音節，換成沒聲調的注音，再用同一份字典選字
final class PinyinEngine {
    /// 一個斷好的音節：拼音、對應的注音、在輸入裡用掉幾個字元（含 '）
    struct Piece: Equatable {
        let pinyin: String
        let bopomofo: String
        let length: Int
    }

    struct Segmentation: Equatable {
        var pieces: [Piece]
        /// 最後打到一半的字母（例如 nih 的 h）
        var partial: String
    }

    static let maxSyllable = 6

    /// 簡拼：只打聲母（nh → 你好）。y、w 當成 ㄧ、ㄨ 開頭
    static let abbreviations: [String: String] = [
        "zh": "ㄓ", "ch": "ㄔ", "sh": "ㄕ",
        "b": "ㄅ", "p": "ㄆ", "m": "ㄇ", "f": "ㄈ", "d": "ㄉ", "t": "ㄊ", "n": "ㄋ", "l": "ㄌ",
        "g": "ㄍ", "k": "ㄎ", "h": "ㄏ", "j": "ㄐ", "q": "ㄑ", "x": "ㄒ", "r": "ㄖ",
        // 只打 z／c／s 時很多人其實是 zh／ch／sh（sm＝什麼、zd＝知道）：兩種都查
        "z": "ㄗ|ㄓ", "c": "ㄘ|ㄔ", "s": "ㄙ|ㄕ", "y": "ㄧ", "w": "ㄨ",
    ]

    /// 拼音或簡拼 → 查字典用的注音（簡拼後面加 *，表示「這個聲母開頭的字」）
    private func bopomofo(_ py: String) -> String {
        table[py] ?? Self.abbreviations[py].map { $0 + "*" } ?? ""
    }

    let engine: ZhuyinEngine
    private let table: [String: String]       // 拼音 → 注音
    private let completions: [String: [String]]   // 拼音開頭 → 所有以它開頭的音節

    init(engine: ZhuyinEngine, table: [String: String]) {
        self.engine = engine
        self.table = table
        var map: [String: [String]] = [:]
        for py in table.keys {
            for len in 1..<max(1, py.count) {
                map[String(py.prefix(len)), default: []].append(py)
            }
        }
        completions = map.mapValues { $0.sorted() }
        engine.fuzzy = ZhuyinEngine.FuzzyOptions(keyNeighbors: false, tones: false, phonetic: false)
    }

    /// 從 SQLite 的 pinyin 表讀出對照
    static func loadTable(from db: SQLiteDB) -> [String: String] {
        var table: [String: String] = [:]
        db.run("SELECT py, bpmf FROM pinyin") { stmt in
            table[SQLiteDB.text(stmt, 0)] = SQLiteDB.text(stmt, 1)
        }
        return table
    }

    // MARK: 斷音節

    func segment(_ input: String) -> Segmentation {
        let chunks = input.lowercased().split(separator: "'", omittingEmptySubsequences: false).map { Array($0) }
        var pieces: [Piece] = []
        var partial = ""
        var pending = 0   // 還沒算進去的 '
        for (i, chunk) in chunks.enumerated() {
            let isLast = i == chunks.count - 1
            var (syllables, tail) = split(chunk)
            if !isLast && !tail.isEmpty {
                // 中間的段落打不完整：當成一個查不到的音節
                syllables.append(tail)
                tail = ""
            }
            for (j, py) in syllables.enumerated() {
                var len = py.count + pending
                pending = 0
                if !isLast && j == syllables.count - 1 { len += 1 }
                pieces.append(Piece(pinyin: py, bopomofo: bopomofo(py), length: len))
            }
            if !isLast && syllables.isEmpty { pending += 1 }
            if isLast { partial = tail }
        }
        return Segmentation(pieces: pieces, partial: partial)
    }

    /// 最後一段：盡量全部斷成音節，斷不完的尾巴（某些音節的開頭）放在 tail；都不行就當成簡拼
    private func split(_ s: [Character]) -> ([String], String) {
        for cut in stride(from: s.count, through: 0, by: -1) {
            let tail = String(s[cut...])
            guard tail.isEmpty || completions[tail] != nil else { continue }
            if let head = splitFull(Array(s[0..<cut]), abbreviate: false) { return (head, tail) }
        }
        if let all = splitFull(s, abbreviate: true) { return (all, "") }
        return ([], String(s))
    }

    /// 取最長的合法音節，後面斷不下去就往回退；abbreviate 時也可以只打聲母
    private func splitFull(_ s: [Character], abbreviate: Bool) -> [String]? {
        var memo: [Int: [String]?] = [:]
        func go(_ start: Int) -> [String]? {
            if start == s.count { return [] }
            if let cached = memo[start] { return cached }
            var result: [String]? = nil
            var cost = Int.max
            for len in stride(from: min(Self.maxSyllable, s.count - start), through: 1, by: -1) {
                let py = String(s[start..<(start + len)])
                guard table[py] != nil, let rest = go(start + len) else { continue }
                // 中間的音節用 a、o、e 開頭（ken＋eng）多半是斷錯了，有別的斷法（ke＋neng）就用別的；一樣的話取長的
                let vowelStart = { (p: String) in p.first.map { "aoe".contains($0) } ?? false }
                let c = rest.filter(vowelStart).count + (start > 0 && vowelStart(py) ? 1 : 0)
                if c < cost { cost = c; result = [py] + rest }
            }
            if result == nil && abbreviate {
                for len in stride(from: 2, through: 1, by: -1) where start + len <= s.count {
                    let py = String(s[start..<(start + len)])
                    guard Self.abbreviations[py] != nil, let rest = go(start + len) else { continue }
                    result = [py] + rest
                    break
                }
            }
            memo[start] = result
            return result
        }
        return go(0)
    }

    // MARK: 選字

    /// 拿去查字典的注音（打到一半的音節換成分數最高的補完）
    func readings(for seg: Segmentation) -> [String] {
        var base = seg.pieces.map { p -> String in
            if !p.bopomofo.isEmpty { return p.bopomofo }
            let b = bopomofo(p.pinyin)
            return b.isEmpty ? p.pinyin : b
        }
        guard !seg.partial.isEmpty, let options = completions[seg.partial] else { return base }
        var best: (score: Double, reading: String)? = nil
        for py in options {
            guard let bpmf = table[py] else { continue }
            let score = engine.bestSegments(base + [bpmf]).reduce(0) { $0 + $1.score }
            if best == nil || score > best!.score { best = (score, bpmf) }
        }
        if let b = best { base.append(b.reading) }
        return base
    }

    func candidates(for input: String) -> [Candidate] {
        engine.candidates(for: readings(for: segment(input)))
    }

    /// 選了用掉前 span 個音節的候選字後，輸入裡要拿掉幾個字元
    func consumedLength(_ input: String, span: Int) -> Int {
        let seg = segment(input)
        if span >= seg.pieces.count { return input.count }
        return seg.pieces.prefix(span).reduce(0) { $0 + $1.length }
    }

    /// 上面那條顯示的拼音，例如「ni hao」
    func display(_ input: String) -> String {
        let seg = segment(input)
        return (seg.pieces.map { $0.pinyin } + (seg.partial.isEmpty ? [] : [seg.partial])).joined(separator: " ")
    }
}

/// 繁體轉簡體（OpenCC 的對照表，字典裡的 t2s 表）
final class ChineseConverter {
    private let lookup: (String) -> String?
    private var cache: [String: String] = [:]
    static let maxPhrase = 6

    init(lookup: @escaping (String) -> String?) {
        self.lookup = lookup
    }

    convenience init(db: SQLiteDB) {
        self.init { key in
            var out: String? = nil
            db.run("SELECT simp FROM t2s WHERE trad = ?1", [.text(key)]) { stmt in out = SQLiteDB.text(stmt, 0) }
            return out
        }
    }

    /// 從左邊找最長有對照的詞，沒有就逐字轉
    func convert(_ text: String) -> String {
        if let cached = cache[text] { return cached }
        let chars = Array(text)
        var out = ""
        var i = 0
        while i < chars.count {
            var matched = false
            for len in stride(from: min(Self.maxPhrase, chars.count - i), through: 1, by: -1) {
                if let simp = lookup(String(chars[i..<(i + len)])) {
                    out += simp
                    i += len
                    matched = true
                    break
                }
            }
            if !matched {
                out.append(chars[i])
                i += 1
            }
        }
        if cache.count >= 512 { cache.removeAll() }
        cache[text] = out
        return out
    }
}
