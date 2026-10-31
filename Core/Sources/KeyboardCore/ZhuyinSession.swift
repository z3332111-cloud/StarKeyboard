import Foundation

/// 注音符號與聲調。這些只能留在組字區，不能進文章，除非使用者在符號鍵上自己選。
enum PhoneticText {
    static func isPhonetic(_ c: Character) -> Bool {
        Bopomofo.kind(of: c) != nil
    }

    static func containsPhonetic(_ s: String) -> Bool {
        s.contains(where: isPhonetic)
    }

    /// 注音路徑要送出的字。聲調與注音一律拿掉。
    static func commit(_ s: String) -> String {
        String(s.filter { !isPhonetic($0) })
    }
}

/// 注音組字到送出的規則。鍵盤與測試走同一條，避免聲調從某條捷徑漏進文章。
final class ZhuyinSession {
    var composer = ZhuyinComposer()
    var candidates: [Candidate] = []
    var engine: ZhuyinEngine?
    private var picks: [(readings: [String], text: String)] = []

    /// 很長的句子仍整段留著。超過這個音節數才把前面已經能決定的部分送出，新按的鍵不會被丟掉。
    static let overflowSyllables = 180
    static let keepTail = 8

    func refresh(context: String) {
        guard !composer.readings.isEmpty else {
            candidates = []
            return
        }
        guard let engine = engine else {
            candidates = []
            return
        }
        candidates = engine.candidates(for: composer.readings, before: context).compactMap { candidate in
            let text = PhoneticText.commit(candidate.text)
            guard !text.isEmpty else { return nil }
            return Candidate(text: text, span: candidate.span, kind: candidate.kind, reading: candidate.reading)
        }
    }

    /// 注音鍵。回傳這次要送進文章的字（通常是空的；緩衝區太長時是前面那段中文）。
    func type(_ c: Character) -> String {
        guard Bopomofo.kind(of: c) != nil else { return "" }
        if !composer.isComposing { picks = [] }
        _ = composer.input(c)
        if composer.syllables.count > Self.overflowSyllables {
            return commitOverflow()
        }
        return ""
    }

    /// 組字區或還沒用到的聲調處理掉了就回傳 true。
    func backspace() -> Bool {
        if composer.isComposing {
            composer.backspace()
            if !composer.isComposing { picks = [] }
            return true
        }
        return composer.consumeStrayTone()
    }

    enum Space {
        /// 沒有注音組字，呼叫端自己決定要不要送空白。
        case passthrough
        /// 組字區有變，但這次不送出文字。
        case stay
        case commit(String)
    }

    func space() -> Space {
        if composer.hasPendingSyllable {
            composer.confirmSyllable()
            return .stay
        }
        if composer.isComposing {
            let unfinished = composer.syllables.contains { $0.open }
            let top = candidates.first
            let covers = top.map {
                $0.span == composer.readings.count && $0.kind != .literal && !PhoneticText.containsPhonetic($0.text)
            } ?? false
            if unfinished || !covers { return .stay }
            return .commit(pick(0, learn: false))
        }
        _ = composer.consumeStrayTone()
        return .passthrough
    }

    func enter() -> String { commitAll() }

    /// 換鍵盤、或必須先把組字區清掉時。
    func commitAll() -> String {
        let text = committedSentence()
        composer.clear()
        picks = []
        candidates = []
        return text
    }

    func pick(_ index: Int, learn: Bool) -> String {
        guard composer.isComposing, index >= 0, index < candidates.count else { return "" }
        let c = candidates[index]
        let text = PhoneticText.commit(c.text)
        let used = c.reading.map { $0.components(separatedBy: "-") } ?? Array(composer.readings.prefix(c.span))
        if c.kind != .literal && (learn || c.kind == .phrase), !text.isEmpty {
            engine?.learn(readings: used, text: text)
            picks.append((used, text))
        } else {
            picks = []
        }
        composer.removeFirst(c.span)
        if !composer.isComposing {
            if picks.count > 1 {
                let all = picks.flatMap { $0.readings }
                engine?.learn(readings: all, text: picks.map { $0.text }.joined())
            }
            picks = []
            candidates = []
        }
        return text
    }

    /// 符號鍵盤上使用者自己點的字，可以是聲調。
    func insertSymbol(_ s: String) -> String { s }

    private func committedSentence() -> String {
        guard !composer.readings.isEmpty else { return "" }
        if let first = candidates.first, first.span == composer.readings.count, !PhoneticText.containsPhonetic(first.text) {
            return first.text
        }
        let raw = engine?.bestSegments(composer.readings).map { $0.text }.joined() ?? ""
        return PhoneticText.commit(raw)
    }

    private func commitOverflow() -> String {
        let count = composer.syllables.count - Self.keepTail
        guard count > 0 else { return "" }
        let readings = Array(composer.readings.prefix(count))
        let text = PhoneticText.commit(engine?.bestSegments(readings).map { $0.text }.joined() ?? "")
        composer.removeFirst(count)
        picks = []
        return text
    }
}

/// 選字列高度。拖曳和設定滑桿都用同一組上下限。
enum CandidateBarMetrics {
    static let minHeight: Double = 44
    static let maxHeight: Double = 96
    static let defaultHeight: Double = 64

    static func clamp(_ height: Double) -> Double {
        min(maxHeight, max(minHeight, height))
    }

    static func fontSize(barHeight: Double) -> Double {
        24 * (clamp(barHeight) / defaultHeight)
    }
}
