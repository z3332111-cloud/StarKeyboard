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
            let split = s.maySplit && (next.map { $0.open && $0.isSingleSymbol } ?? s.afterAbbreviation)
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
    mutating func input(_ c: Character) -> Bool {
        guard let kind = Bopomofo.kind(of: c) else { return false }
        if kind == .tone {
            return putTone(c)
        }
        // 不打聲調直接打下一個字：前一個字自動結束（ㄋㄏ → 你好）
        if current.hasSound && (current.startsNew(with: kind) || !fits(c)) { closeCurrent() }
        if kind != .initial {
            current.maySplit = current.isSingleSymbol
            current.afterAbbreviation = current.maySplit && syllables.last.map { $0.open && $0.isSingleSymbol } == true
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
    mutating func confirmSyllable() -> Bool {
        guard current.hasSound else { return false }
        // 聲調先到、人又按了空白：那個聲調已經算在這個音上，空白不再把它改成一聲。
        if current.tone == nil, let tone = pendingTone {
            current.tone = tone
        }
        pendingTone = nil
        finishSyllable(open: false)
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
