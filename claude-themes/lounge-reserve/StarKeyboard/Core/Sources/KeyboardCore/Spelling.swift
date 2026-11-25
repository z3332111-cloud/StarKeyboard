import Foundation

/// 英文自動修正用的小工具（真正查字典的是 iOS 的 UITextChecker）
enum Spelling {
    /// 兩個字差幾個字母（插入、刪除、替換、相鄰兩個字母對調都算一步）
    static func editDistance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var d = [[Int]](repeating: [Int](repeating: 0, count: y.count + 1), count: x.count + 1)
        for i in 0...x.count { d[i][0] = i }
        for j in 0...y.count { d[0][j] = j }
        for i in 1...x.count {
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, x[i - 1] == y[j - 2], x[i - 2] == y[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[x.count][y.count]
    }

    /// 修正要夠接近才自動換（短字只能差 1 個字母）
    static func isCloseEnough(_ typed: String, _ fix: String) -> Bool {
        let limit = typed.count <= 4 ? 1 : 2
        return editDistance(typed.lowercased(), fix.lowercased()) <= limit
    }

    /// 照原本的大小寫：Hello → 修正也開頭大寫
    static func matchCase(_ fix: String, like typed: String) -> String {
        guard let first = typed.first, first.isUppercase, !fix.isEmpty else { return fix }
        return fix.prefix(1).uppercased() + fix.dropFirst()
    }
}
