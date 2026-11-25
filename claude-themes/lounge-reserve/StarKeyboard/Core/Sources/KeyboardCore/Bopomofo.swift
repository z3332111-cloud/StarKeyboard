import Foundation

enum BopomofoKind {
    case initial, medial, rhyme, tone
}

enum Bopomofo {
    static let initials: Set<Character> = Set("ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙ")
    static let medials: Set<Character> = Set("ㄧㄨㄩ")
    static let finals: Set<Character> = Set("ㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦ")
    static let tones: Set<Character> = Set("ˊˇˋ˙")

    static func kind(of c: Character) -> BopomofoKind? {
        if initials.contains(c) { return .initial }
        if medials.contains(c) { return .medial }
        if finals.contains(c) { return .rhyme }
        if tones.contains(c) { return .tone }
        return nil
    }

    /// 大千排列：和電腦鍵盤的 1qaz、2wsx… 直排一樣
    static let dachenRows: [String] = [
        "ㄅㄉˇˋㄓˊ˙ㄚㄞㄢㄦ",
        "ㄆㄊㄍㄐㄔㄗㄧㄛㄟㄣ",
        "ㄇㄋㄎㄑㄕㄘㄨㄜㄠㄤ",
        "ㄈㄌㄏㄒㄖㄙㄩㄝㄡㄥ",
    ]

    /// 常分不清的音（模糊音）
    static let similar: [Character: Character] = [
        "ㄣ": "ㄥ", "ㄥ": "ㄣ", "ㄓ": "ㄗ", "ㄗ": "ㄓ",
        "ㄔ": "ㄘ", "ㄘ": "ㄔ", "ㄕ": "ㄙ", "ㄙ": "ㄕ",
    ]

    /// 鍵盤上相鄰的鍵（左右、上下）
    static let neighbors: [Character: [Character]] = {
        let grid = dachenRows.map { Array($0) }
        var map: [Character: [Character]] = [:]
        for (r, row) in grid.enumerated() {
            for (c, ch) in row.enumerated() {
                var list: [Character] = []
                for (dr, dc) in [(0, -1), (0, 1), (-1, 0), (1, 0)] {
                    let rr = r + dr, cc = c + dc
                    if rr >= 0, rr < grid.count, cc >= 0, cc < grid[rr].count {
                        list.append(grid[rr][cc])
                    }
                }
                map[ch] = list
            }
        }
        return map
    }()
}

/// 一個字的注音：聲母＋介音＋韻母＋聲調（一聲不標）
struct Syllable: Equatable {
    var initial: Character?
    var medial: Character?
    var rhyme: Character?   // 韻母
    var tone: Character?

    var isEmpty: Bool { initial == nil && medial == nil && rhyme == nil && tone == nil }
    var hasSound: Bool { initial != nil || medial != nil || rhyme != nil }
    /// 只打了一個注音、沒聲調（簡拼的打法，例如 ㄏ、ㄧ）
    var isSingleSymbol: Bool { [initial, medial, rhyme].filter { $0 != nil }.count == 1 && tone == nil }
    /// 只打了聲母或介音（ㄏ、ㄧ）：這才是簡拼。只打韻母（ㄢ、ㄚ）本身就是一個完整的字（安、啊），不是簡拼
    var isBareLead: Bool { isSingleSymbol && rhyme == nil }

    /// 沒打聲調就換下一個字（或只打了開頭）：查字典時當成「以這些注音開頭、聲調不限」
    var open = false

    /// 簡拼時可能是兩個字的開頭：只打了一個注音又接了一個（ㄎㄞ 也可能是 ㄎ＋ㄞ、ㄨㄞ 也可能是 ㄨ＋ㄞ）
    var maySplit = false
    /// 打這個字的時候，前一個字是簡拼（只打了一個注音）
    var afterAbbreviation = false

    /// 再打這一類的符號時，算是開始打下一個字（例如已經有韻母又打韻母、已經有音又打聲母）
    func startsNew(with kind: BopomofoKind) -> Bool {
        switch kind {
        case .initial: return hasSound
        case .medial: return medial != nil || rhyme != nil
        case .rhyme: return rhyme != nil
        case .tone: return false
        }
    }

    /// 和字典一樣的寫法，例如「ㄋㄧˇ」「ㄇㄚ」「ㄉㄜ˙」
    var reading: String {
        var s = ""
        for c in [initial, medial, rhyme, tone] {
            if let c = c { s.append(c) }
        }
        return s
    }

    /// 大千的打法：同一類的符號再打一次就取代
    mutating func put(_ c: Character) {
        switch Bopomofo.kind(of: c) {
        case .initial: initial = c
        case .medial: medial = c
        case .rhyme: rhyme = c
        case .tone: tone = c
        case nil: break
        }
    }

    mutating func removeLast() {
        if tone != nil { tone = nil }
        else if rhyme != nil { rhyme = nil }
        else if medial != nil { medial = nil }
        else { initial = nil }
        maySplit = false
    }
}

/// 組字區：已經打完的音節＋正在打的音節
struct ZhuyinComposer {
    private(set) var syllables: [Syllable] = []
    private(set) var current = Syllable()
    /// 聲調比音節先到、或上一個音節已經被收進去時先留著。空白的聲調不會送進文章。
    private var pendingTone: Character?
    /// 字典裡所有音節的開頭（例如 ㄋ、ㄋㄧ、ㄋㄧㄠ）；有的話，組不出存在的音就自動換下一個字
    var validPrefixes: Set<String>?
    /// 可以自己成一個字的音節（沒聲調）；「ㄐ」這種不能單獨念的，按空白也不會把它當成一個字
    var validSyllables: Set<String>?
    /// 剛被空白鍵（一聲）收起來的音節和時間：下一個注音其實接得上的話，當成空白是不小心碰到的
    private var spaceClosed: (index: Int, time: Double?)?
    /// 空白之後多快接著打注音，算是不小心碰到空白（秒）
    static let accidentalSpaceWindow = 0.35

    /// 查字典用的讀音：打完的音節＋正在打的音節（沒打聲調也算，先拿來預覽）
    /// 沒打完的音節後面加 *，例如「ㄋ*」「ㄋㄧ*」；可能是兩個字的再加 ~，例如「ㄎㄞ*~」
    var readings: [String] {
        var all = syllables
        if current.hasSound {
            var pending = current
            if pending.tone == nil, let tone = pendingTone {
                pending.tone = tone
            }
            pending.open = pending.tone == nil
            all.append(pending)
        }
        return all.indices.map { (i: Int) -> String in
            let s = all[i]
            guard s.open else { return s.reading }
            // 前一個字是簡拼（ㄏㄎㄞ）或後面接著簡拼（ㄨㄞㄋ）才可能拆；後面接的是打完整的字就不拆
            let next = i + 1 < all.count ? all[i + 1] : nil
            let split = s.maySplit && (next.map { $0.open && $0.isBareLead } ?? s.afterAbbreviation)
            return s.reading + "*" + (split ? "~" : "")
        }
    }
    /// 給使用者核對實際輸入的注音；保留聲調與音節分隔，不顯示查詢用的 *／~。
    var displayText: String {
        var sounds = syllables.map { $0.reading }
        if current.hasSound {
            var shown = current.reading
            if current.tone == nil, let tone = pendingTone { shown.append(tone) }
            sounds.append(shown)
        }
        return sounds.joined(separator: " ")
    }

    var isComposing: Bool { !syllables.isEmpty || !current.isEmpty }
    var hasPendingSyllable: Bool { !current.isEmpty }

    /// 回傳 false 表示這個符號沒被組字用掉（例如還沒打音就先打聲調）
    @discardableResult
    mutating func input(_ c: Character, at time: Double? = nil) -> Bool {
        guard let kind = Bopomofo.kind(of: c) else { return false }
        let closedBySpace = spaceClosed
        spaceClosed = nil
        if kind == .tone {
            return putTone(c)
        }
        // 刪掉剛打錯的那個注音之後（ㄒ＋ㄝ 拼不起來，ㄝ 被當成下一個字；刪掉 ㄝ 再打 ㄩ）：
        // 前一個字是被自動收起來的（沒聲調），接得上就接回去，ㄒㄩㄝ 才是「學」，不是「小月」
        if current.isEmpty, kind != .initial, pendingTone == nil, let last = syllables.last,
           last.open, last.tone == nil, !last.startsNew(with: kind) {
            var merged = last
            merged.put(c)
            if validPrefixes?.contains(merged.reading) ?? true {
                current = syllables.removeLast()
                current.open = false
            }
        }
        // 不能單獨念的音（ㄒ、ㄐ）後面跟著聲調：那個聲調是按錯的，接下來的 ㄩㄝ 還是同一個字
        if current.isEmpty, kind != .initial, pendingTone == nil, let full = validSyllables, let last = syllables.last,
           last.tone != nil {
            var bare = last
            bare.tone = nil
            var merged = bare
            merged.put(c)
            if !full.contains(bare.reading), !bare.startsNew(with: kind), validPrefixes?.contains(merged.reading) ?? true {
                syllables.removeLast()
                current = bare
                current.open = false
            }
        }
        // 快速打字時拇指順便碰到空白鍵（ㄩ 就在空白鍵正上方）：ㄐ＋空白＋ㄩㄝ 還是「覺」，不是「居約」
        if current.isEmpty, kind != .initial, pendingTone == nil, let sc = closedBySpace, sc.index == syllables.count - 1 {
            let last = syllables[sc.index]
            var merged = last
            merged.put(c)
            let quick = time != nil && sc.time != nil && time! - sc.time! < Self.accidentalSpaceWindow
            let impossible = validSyllables.map { !$0.contains(last.reading) } ?? false
            let joins = validPrefixes?.contains(merged.reading) ?? true
            if (quick || impossible) && last.tone == nil && !last.startsNew(with: kind) && joins {
                current = syllables.removeLast()
                current.open = false
            }
        }
        // 不打聲調直接打下一個字：前一個字自動結束（ㄋㄏ → 你好）
        if current.hasSound && (current.startsNew(with: kind) || !fits(c)) { closeCurrent() }
        if kind != .initial {
            current.maySplit = current.isSingleSymbol
            current.afterAbbreviation = current.maySplit && syllables.last.map { $0.open && $0.isBareLead } == true
        }
        current.put(c)
        return true
    }

    /// 加上這個符號還是某個字的開頭嗎（例如 ㄘ＋ㄧ 不是，ㄘ 要自己算一個字）
    private func fits(_ c: Character) -> Bool {
        guard let set = validPrefixes else { return true }
        var next = current
        next.put(c)
        return set.contains(next.reading)
    }

    /// 聲調一定吃掉：貼在正在打的音節、補回剛剛被拆開的音節，或先留著等下一個音節。
    private mutating func putTone(_ c: Character) -> Bool {
        if current.hasSound {
            pendingTone = nil
            current.tone = c
            finishSyllable()
            return true
        }
        // 下一個鍵先被處理、這個音節已經收成「還沒聲調」：聲調補回來，不要單獨送出。
        if !syllables.isEmpty {
            var last = syllables[syllables.count - 1]
            if last.open && last.tone == nil {
                last.tone = c
                last.open = false
                syllables[syllables.count - 1] = last
                pendingTone = nil
                return true
            }
        }
        pendingTone = c
        return true
    }

    /// 換成下一個字。若聲調先到，它屬於現在這個音節，不是下一個字。
    private mutating func closeCurrent() {
        if current.tone == nil, let tone = pendingTone {
            current.tone = tone
            pendingTone = nil
            finishSyllable(open: false)
        } else {
            finishSyllable(open: current.tone == nil)
        }
    }

    /// 空白鍵＝一聲。組字區保持開著，不在這裡送出文字。
    @discardableResult
    mutating func confirmSyllable(at time: Double? = nil) -> Bool {
        guard current.hasSound else { return false }
        // 聲調先到、人又按了空白：那個聲調已經算在這個音上，空白不再把它改成一聲。
        if current.tone == nil, let tone = pendingTone {
            current.tone = tone
        }
        pendingTone = nil
        // 「ㄐ」這種不能單獨念的音按了空白：當成只打開頭的簡拼（ㄐ*），不是一聲的「ㄐ」
        let alone = current.tone != nil || (validSyllables.map { $0.contains(current.reading) } ?? true)
        finishSyllable(open: !alone)
        spaceClosed = (syllables.count - 1, time)
        return true
    }

    /// 還沒有音節時誤按的聲調。退格或真正的空白會把它清掉，避免黏到下一個字。
    mutating func consumeStrayTone() -> Bool {
        guard pendingTone != nil, current.isEmpty, syllables.isEmpty else { return false }
        pendingTone = nil
        return true
    }

    @discardableResult
    mutating func backspace() -> Bool {
        spaceClosed = nil
        if current.hasSound && current.tone == nil && pendingTone != nil {
            pendingTone = nil
            return true
        }
        if !current.isEmpty {
            current.removeLast()
            return true
        }
        if !syllables.isEmpty {
            var last = syllables.removeLast()
            if last.open {
                // 沒打聲調的字：拿回來繼續一個一個刪
                last.open = false
                last.removeLast()
                current = last
            }
            return true
        }
        return false
    }

    /// 選了字之後拿掉前 n 個音節（包含正在打的那個）
    mutating func removeFirst(_ n: Int) {
        let count = max(n, 0)
        if count > syllables.count {
            current = Syllable()
            pendingTone = nil
        }
        syllables.removeFirst(min(count, syllables.count))
    }

    // MARK: 游標在注音中間修改（像 iPhone 內建注音：打錯一個不用整串刪掉）

    /// 空白鍵打的一聲，在按鍵清單裡用這個記號
    static let firstTone: Character = "ˉ"

    /// 照順序列出按過的注音鍵；重新照這個順序打一次，會得到一樣的組字區
    var keys: [Character] {
        var out: [Character] = []
        for s in syllables {
            out += Array(s.reading)
            if !s.open && s.tone == nil { out.append(Self.firstTone) }
        }
        out += Array(current.reading)
        if let tone = pendingTone { out.append(tone) }
        return out
    }

    /// 給人看的按鍵清單：一聲顯示成空格
    static func display(_ keys: ArraySlice<Character>) -> String {
        String(keys.map { $0 == firstTone ? " " : $0 })
    }

    /// 改過按鍵清單之後，從頭重新打一次
    mutating func replay(_ keys: [Character]) {
        let prefixes = validPrefixes
        let full = validSyllables
        self = ZhuyinComposer()
        validPrefixes = prefixes
        validSyllables = full
        for k in keys {
            if k == Self.firstTone { confirmSyllable() } else { input(k) }
        }
    }

    mutating func clear() {
        syllables = []
        current = Syllable()
        pendingTone = nil
    }

    private mutating func finishSyllable(open: Bool = false) {
        current.open = open
        syllables.append(current)
        current = Syllable()
    }
}
