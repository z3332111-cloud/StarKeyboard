import CoreGraphics
import Foundation

/// 英文滑行輸入：手指不離開，滑過字母，認出是哪個字。和 Android 版 Glide.kt 一樣。
///
/// 做法：先用起點、終點附近的鍵挑出可能的字，再把每個字「理想的滑法」（依序連起字母鍵的中心）
/// 和手指實際畫的線各取 24 個等距的點比距離；距離越近、字越常用，分數越高。
final class GlideDecoder {
    private struct Entry {
        let word: String
        let squeezed: [Character]
        let logFreq: Double
    }

    static let samples = 24
    static let distanceWeight = 6.0
    static let maxDistance = 1.4   // 平均差超過 1.4 個鍵寬就不考慮

    private let byEnds: [String: [Entry]]

    var count: Int { byEnds.values.reduce(0) { $0 + $1.count } }

    init(words: [(String, Int)]) {
        var map: [String: [Entry]] = [:]
        for (w, n) in words where w.count >= 2 && w.allSatisfy({ ("a"..."z").contains($0) }) {
            let key = String([w.first!, w.last!])
            map[key, default: []].append(Entry(word: w, squeezed: Self.squeeze(w), logFreq: log10(Double(max(n, 1)))))
        }
        byEnds = map
    }

    /// 字表檔：每行「單字 次數」
    convenience init(text: String) {
        var words: [(String, Int)] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ")
            if parts.count >= 2, let n = Int(parts[1]) { words.append((String(parts[0]), n)) }
        }
        self.init(words: words)
    }

    /// 連續重複的字母只算一次（hello → helo），滑的時候不會在同一個鍵停兩次
    static func squeeze(_ w: String) -> [Character] {
        var out: [Character] = []
        for c in w where out.last != c { out.append(c) }
        return out
    }

    /// 沿著線等距取 n 個點
    static func resample(_ points: [CGPoint], _ n: Int) -> [CGPoint] {
        guard points.count > 1 else { return Array(repeating: points.first ?? .zero, count: n) }
        let seg = (0..<(points.count - 1)).map { hypot(points[$0 + 1].x - points[$0].x, points[$0 + 1].y - points[$0].y) }
        let total = seg.reduce(0, +)
        guard total > 0 else { return Array(repeating: points[0], count: n) }
        var out: [CGPoint] = []
        out.reserveCapacity(n)
        var j = 0
        var walked: CGFloat = 0
        for k in 0..<n {
            let target = total * CGFloat(k) / CGFloat(n - 1)
            while j < seg.count - 1 && walked + seg[j] < target {
                walked += seg[j]
                j += 1
            }
            let t = seg[j] > 0 ? min(max((target - walked) / seg[j], 0), 1) : 0
            let a = points[j], b = points[j + 1]
            out.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }
        return out
    }

    /// path：手指畫的線；centers：每個字母鍵的中心；keyWidth：一個鍵多寬。回傳最可能的幾個字
    func decode(path: [CGPoint], centers: [Character: CGPoint], keyWidth: CGFloat, limit: Int = 5) -> [String] {
        guard path.count >= 2, !centers.isEmpty, keyWidth > 0 else { return [] }
        func nearest(_ p: CGPoint) -> [Character] {
            centers.sorted { hypot($0.value.x - p.x, $0.value.y - p.y) < hypot($1.value.x - p.x, $1.value.y - p.y) }
                .prefix(2).map { $0.key }
        }
        let user = Self.resample(path, Self.samples)
        var scored: [(String, Double)] = []
        for s in nearest(path[0]) {
            for e in nearest(path[path.count - 1]) {
                for entry in byEnds[String([s, e])] ?? [] {
                    let ideal = entry.squeezed.compactMap { centers[$0] }
                    guard ideal.count == entry.squeezed.count else { continue }
                    let shape = Self.resample(ideal, Self.samples)
                    var d: CGFloat = 0
                    for k in 0..<Self.samples { d += hypot(user[k].x - shape[k].x, user[k].y - shape[k].y) }
                    let dist = Double(d / CGFloat(Self.samples) / keyWidth)
                    guard dist <= Self.maxDistance else { continue }
                    scored.append((entry.word, entry.logFreq - dist * Self.distanceWeight))
                }
            }
        }
        var seen = Set<String>()
        return scored.sorted { $0.1 > $1.1 }.map { $0.0 }.filter { seen.insert($0).inserted }.prefix(limit).map { $0 }
    }
}
