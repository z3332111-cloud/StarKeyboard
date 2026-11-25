import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// App 裡「邊調邊看」：App 和鍵盤的設定分開存（沒有 App Group），
/// 所以用只有自己 App 和鍵盤看得到的具名剪貼簿互相傳大小和透明度。
public struct LiveLook: Equatable {
    public var heightScale: Double = 1
    public var fontScale: Double = 1
    public var gapScale: Double = 1
    public var shapeScale: Double = 1.15
    public var keyAlpha: Double = 1
    public var backgroundFade: Double = 0.25

    public init() {}

    static let pasteboardName = "tw.nuonuo.livelook"
    static let type = "tw.nuonuo.livelook"

    var dictionary: [String: Double] {
        ["heightScale": heightScale, "fontScale": fontScale, "gapScale": gapScale,
         "shapeScale": shapeScale, "keyAlpha": keyAlpha, "backgroundFade": backgroundFade]
    }

    init(_ d: [String: Any]) {
        heightScale = d["heightScale"] as? Double ?? 1
        fontScale = d["fontScale"] as? Double ?? 1
        gapScale = d["gapScale"] as? Double ?? 1
        shapeScale = d["shapeScale"] as? Double ?? 1.15
        keyAlpha = d["keyAlpha"] as? Double ?? 1
        backgroundFade = d["backgroundFade"] as? Double ?? 0.25
    }

    #if canImport(UIKit)
    // 只拿一次：每次都重新拿具名剪貼簿，鍵盤一直開著時會越吃越多記憶體
    private static let board: UIPasteboard? = UIPasteboard(name: UIPasteboard.Name(pasteboardName), create: true)

    /// 剪貼簿目前的版本號（有人寫進新的值就會變）
    public static var changeCount: Int { board?.changeCount ?? -1 }

    /// 寫進去；from 是 "app" 或 "keyboard"。回傳寫完後的版本號
    @discardableResult
    public func publish(from: String) -> Int {
        guard let b = Self.board else { return -1 }
        var d: [String: Any] = dictionary
        d["from"] = from
        if let data = try? JSONSerialization.data(withJSONObject: d) {
            b.setData(data, forPasteboardType: Self.type)
        }
        return b.changeCount
    }

    /// 讀出最新的值和是誰寫的
    public static func read() -> (look: LiveLook, from: String)? {
        guard let b = board, let data = b.data(forPasteboardType: type),
              let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (LiveLook(d), d["from"] as? String ?? "")
    }
    #endif
}
