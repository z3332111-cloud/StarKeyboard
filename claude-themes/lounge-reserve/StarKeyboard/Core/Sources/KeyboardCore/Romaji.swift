import Foundation

/// 日文羅馬拼音轉假名（sakura → さくら → サクラ）
enum Romaji {
    static let table: [String: String] = build()

    /// 還沒打完的拼音（k、ky、sh、ts…）
    static let prefixes: Set<String> = {
        var set = Set<String>()
        for key in table.keys {
            for len in 1..<max(1, key.count) {
                set.insert(String(key.prefix(len)))
            }
        }
        set.insert("n")
        return set
    }()

    private static func build() -> [String: String] {
        var t: [String: String] = [:]
        let vowels = ["a", "i", "u", "e", "o"]
        func row(_ head: String, _ kana: String) {
            for (v, k) in zip(vowels, kana) { t[head + v] = String(k) }
        }
        row("", "あいうえお")
        row("k", "かきくけこ"); row("s", "さしすせそ"); row("t", "たちつてと")
        row("n", "なにぬねの"); row("h", "はひふへほ"); row("m", "まみむめも")
        row("r", "らりるれろ"); row("g", "がぎぐげご"); row("z", "ざじずぜぞ")
        row("d", "だぢづでど"); row("b", "ばびぶべぼ"); row("p", "ぱぴぷぺぽ")
        row("x", "ぁぃぅぇぉ"); row("l", "ぁぃぅぇぉ")
        t["ya"] = "や"; t["yu"] = "ゆ"; t["yo"] = "よ"; t["ye"] = "いぇ"
        t["wa"] = "わ"; t["wo"] = "を"; t["wi"] = "うぃ"; t["we"] = "うぇ"
        t["shi"] = "し"; t["chi"] = "ち"; t["tsu"] = "つ"; t["fu"] = "ふ"; t["ji"] = "じ"

        // 拗音：きゃ、しゅ、ちょ…
        let youon: [(String, String)] = [
            ("ky", "き"), ("sh", "し"), ("sy", "し"), ("ch", "ち"), ("ty", "ち"), ("cy", "ち"),
            ("ny", "に"), ("hy", "ひ"), ("my", "み"), ("ry", "り"), ("gy", "ぎ"), ("j", "じ"),
            ("jy", "じ"), ("zy", "じ"), ("by", "び"), ("py", "ぴ"), ("dy", "ぢ"),
        ]
        for (head, kana) in youon {
            t[head + "a"] = kana + "ゃ"
            t[head + "u"] = kana + "ゅ"
            t[head + "o"] = kana + "ょ"
            t[head + "e"] = kana + "ぇ"
        }
        t["fa"] = "ふぁ"; t["fi"] = "ふぃ"; t["fe"] = "ふぇ"; t["fo"] = "ふぉ"
        t["va"] = "ゔぁ"; t["vi"] = "ゔぃ"; t["vu"] = "ゔ"; t["ve"] = "ゔぇ"; t["vo"] = "ゔぉ"
        t["tsa"] = "つぁ"; t["thi"] = "てぃ"; t["dhi"] = "でぃ"; t["dhu"] = "でゅ"
        t["xtu"] = "っ"; t["ltu"] = "っ"; t["xtsu"] = "っ"; t["ltsu"] = "っ"
        t["xya"] = "ゃ"; t["xyu"] = "ゅ"; t["xyo"] = "ょ"; t["lya"] = "ゃ"; t["lyu"] = "ゅ"; t["lyo"] = "ょ"
        t["xwa"] = "ゎ"; t["xn"] = "ん"; t["n'"] = "ん"
        t["-"] = "ー"; t[","] = "、"; t["."] = "。"; t["?"] = "？"; t["!"] = "！"
        return t
    }

    /// 轉成假名；最後還沒打完的拼音放在 rest
    static func convert(_ input: String) -> (kana: String, rest: String) {
        let chars = Array(input.lowercased())
        var out = ""
        var i = 0
        while i < chars.count {
            var matched = false
            for len in stride(from: min(4, chars.count - i), through: 1, by: -1) {
                if let kana = table[String(chars[i..<(i + len)])] {
                    out += kana
                    i += len
                    matched = true
                    break
                }
            }
            if matched { continue }

            let c = chars[i]
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            if c == "n", let n = next {
                if n == "n" {
                    // nn：後面接母音或 y 時（konnichiha），第二個 n 留給下一個字
                    let after: Character? = i + 2 < chars.count ? chars[i + 2] : nil
                    out += "ん"
                    if let a = after, "aiueoy".contains(a) { i += 1 } else { i += 2 }
                    continue
                }
                if !"aiueoy".contains(n) {
                    out += "ん"
                    i += 1
                    continue
                }
            }
            // 促音：kka → っか
            if let n = next, n == c, c.isLetter, !"aiueon".contains(c) {
                out += "っ"
                i += 1
                continue
            }
            let rest = String(chars[i...])
            if prefixes.contains(rest) { return (out, rest) }
            out.append(c)
            i += 1
        }
        return (out, "")
    }

    /// 送出時：最後單獨的 n 當成ん，其他沒打完的照原樣
    static func finalize(_ input: String) -> String {
        let (kana, rest) = convert(input)
        return kana + (rest == "n" ? "ん" : rest)
    }

    static func katakana(_ hiragana: String) -> String {
        var out = String.UnicodeScalarView()
        for s in hiragana.unicodeScalars {
            if (0x3041...0x3096).contains(s.value), let k = Unicode.Scalar(s.value + 0x60) {
                out.append(k)
            } else {
                out.append(s)
            }
        }
        return String(out)
    }
}
