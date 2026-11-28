import UIKit

/// App 的「主題、按鍵、字體、聲音」分頁選好的樣子，傳給鍵盤用。
/// App 和鍵盤的設定分開存（沒有 App Group），所以和「邊調邊看」一樣，用只有自己 App 和鍵盤看得到的具名剪貼簿傳。
/// 傳的就是 UserDefaults 裡的幾個設定（兩邊的名字一樣）；鍵盤收到照抄，主題、字體、聲音還沒下載的，鍵盤自己再下載一份。
enum AppPick {
    /// 會傳的設定（UserDefaults 的名字）
    static let keys = [
        "themeID", "fontID", "fontFallbackID", "keyShape", "keyFinish", "artFinish", "keyMotion", "keyEffect",
        "keySound", "keySoundStyle", "keyTextColor",
        "customHue", "customSaturation", "customHue2", "customSaturation2", "customDark",
    ]

    private static let type = "tw.nuonuo.apppick"
    // 只拿一次：每次都重新拿具名剪貼簿，鍵盤一直開著時會越吃越多記憶體
    private static let board: UIPasteboard? = UIPasteboard(name: UIPasteboard.Name("tw.nuonuo.apppick"), create: true)

    /// 剪貼簿目前的版本號（有人寫進新的值就會變）
    static var changeCount: Int { board?.changeCount ?? -1 }

    /// 把自己現在的這些設定寫進去；from 是 "app" 或 "keyboard"。回傳寫完後的版本號
    @discardableResult
    static func publish(from: String, defaults: UserDefaults = .standard) -> Int {
        guard let b = board else { return -1 }
        var values: [String: Any] = [:]
        for k in keys {
            guard let v = defaults.object(forKey: k), v is String || v is NSNumber else { continue }
            values[k] = v
        }
        let message: [String: Any] = ["from": from, "id": UUID().uuidString, "values": values]
        if let data = try? JSONSerialization.data(withJSONObject: message) {
            b.setData(data, forPasteboardType: type)
        }
        return b.changeCount
    }

    /// 讀出最新的一筆：誰寫的、這筆的編號、設定值
    static func read() -> (from: String, id: String, values: [String: Any])? {
        guard let b = board, let data = b.data(forPasteboardType: type),
              let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = d["values"] as? [String: Any] else { return nil }
        return (d["from"] as? String ?? "", d["id"] as? String ?? "", values)
    }

    /// 把收到的值寫進自己的設定（只認得的名字、只收字串和數字）；回傳真的有變的名字
    @discardableResult
    static func apply(_ values: [String: Any], defaults: UserDefaults = .standard) -> Set<String> {
        var changed = Set<String>()
        for k in keys {
            guard let v = values[k] as? NSObject, v is NSString || v is NSNumber else { continue }
            if let old = defaults.object(forKey: k) as? NSObject, old.isEqual(v) { continue }
            defaults.set(v, forKey: k)
            changed.insert(k)
        }
        return changed
    }
}
