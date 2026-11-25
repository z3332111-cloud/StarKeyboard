import Foundation

/// 韓文兩排式（두벌식）組字：子音、母音照規則自動拼成一個字
struct HangulComposer {
    struct Output: Equatable {
        var commit: String      // 已經拼完、不會再變的字
        var composing: String   // 正在拼的字（還會變）
    }

    static let choseong = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    static let jungseong = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
    static let jongseong: [Character?] = [nil] + Array("ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ").map { Optional($0) }

    static let compoundVowels: [String: Character] = [
        "ㅗㅏ": "ㅘ", "ㅗㅐ": "ㅙ", "ㅗㅣ": "ㅚ", "ㅜㅓ": "ㅝ", "ㅜㅔ": "ㅞ", "ㅜㅣ": "ㅟ", "ㅡㅣ": "ㅢ",
    ]
    static let compoundFinals: [String: Character] = [
        "ㄱㅅ": "ㄳ", "ㄴㅈ": "ㄵ", "ㄴㅎ": "ㄶ", "ㄹㄱ": "ㄺ", "ㄹㅁ": "ㄻ", "ㄹㅂ": "ㄼ",
        "ㄹㅅ": "ㄽ", "ㄹㅌ": "ㄾ", "ㄹㅍ": "ㄿ", "ㄹㅎ": "ㅀ", "ㅂㅅ": "ㅄ",
    ]

    static func isConsonant(_ c: Character) -> Bool { choseong.contains(c) }
    static func isVowel(_ c: Character) -> Bool { jungseong.contains(c) }

    private var cho: Character?
    private var v1: Character?
    private var v2: Character?
    private var j1: Character?
    private var j2: Character?

    var isEmpty: Bool { cho == nil && v1 == nil }

    var composing: String {
        let vowel = combinedVowel
        if let cho = cho, let vowel = vowel,
           let ci = Self.choseong.firstIndex(of: cho), let vi = Self.jungseong.firstIndex(of: vowel) {
            let ji = combinedFinal.flatMap { f in Self.jongseong.firstIndex(of: f) } ?? 0
            let scalar = 0xAC00 + (ci * 21 + vi) * 28 + ji
            return String(Character(Unicode.Scalar(UInt32(scalar))!))
        }
        if let cho = cho { return String(cho) }
        if let vowel = vowel { return String(vowel) }
        return ""
    }

    private var combinedVowel: Character? {
        guard let v1 = v1 else { return nil }
        guard let v2 = v2 else { return v1 }
        return Self.compoundVowels[String([v1, v2])]
    }

    private var combinedFinal: Character? {
        guard let j1 = j1 else { return nil }
        guard let j2 = j2 else { return j1 }
        return Self.compoundFinals[String([j1, j2])]
    }

    /// 打一個子音或母音
    mutating func input(_ c: Character) -> Output {
        if Self.isConsonant(c) { return consonant(c) }
        if Self.isVowel(c) { return vowel(c) }
        let done = composing
        reset()
        return Output(commit: done + String(c), composing: "")
    }

    private mutating func consonant(_ c: Character) -> Output {
        if v1 == nil {
            // 還沒有母音：前一個子音單獨送出
            let done = composing
            reset()
            cho = c
            return Output(commit: done, composing: composing)
        }
        if cho != nil {
            if j1 == nil, Self.jongseong.contains(c) {
                j1 = c
                return Output(commit: "", composing: composing)
            }
            if let j = j1, j2 == nil, Self.compoundFinals[String([j, c])] != nil {
                j2 = c
                return Output(commit: "", composing: composing)
            }
        }
        let done = composing
        reset()
        cho = c
        return Output(commit: done, composing: composing)
    }

    private mutating func vowel(_ c: Character) -> Output {
        if v1 == nil {
            v1 = c
            return Output(commit: "", composing: composing)
        }
        if j1 == nil {
            if v2 == nil, let first = v1, Self.compoundVowels[String([first, c])] != nil {
                v2 = c
                return Output(commit: "", composing: composing)
            }
            let done = composing
            reset()
            v1 = c
            return Output(commit: done, composing: composing)
        }
        // 有收尾子音時打母音：最後一個子音搬到下一個字當開頭（닭 + ㅏ → 달가）
        let moving: Character
        if let j = j2 {
            moving = j
            j2 = nil
        } else {
            moving = j1!
            j1 = nil
        }
        let done = composing
        reset()
        cho = moving
        v1 = c
        return Output(commit: done, composing: composing)
    }

    /// 刪掉最後一個字母；回傳 false 表示本來就沒在拼
    @discardableResult
    mutating func backspace() -> Bool {
        if j2 != nil { j2 = nil }
        else if j1 != nil { j1 = nil }
        else if v2 != nil { v2 = nil }
        else if v1 != nil { v1 = nil }
        else if cho != nil { cho = nil }
        else { return false }
        return true
    }

    mutating func reset() {
        cho = nil
        v1 = nil
        v2 = nil
        j1 = nil
        j2 = nil
    }
}
