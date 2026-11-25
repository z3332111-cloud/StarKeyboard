import UIKit

/// 一張圖一顆鍵的插畫主題（宮廷四款、私藏酒廊、月煙琉璃、夜肺）：只畫鍵帽，字由 KeyButton 畫。
/// 圖放在 GitHub Pages 的 theme-packs（要用才下載），anchors 是每顆鍵帽上放字的位置（0～1）。
/// 和安卓 FoxLetter.kt 的 RoyalKeyArt 是同一份資料。
struct RoyalKeyArt {
    /// 空白鍵的圖怎麼拉長：threeSlice 兩端不變形、中間延展；whole 整張拉滿（飛毯）；band 左邊的圖不變形、右邊延展（吉他放左邊，字在右邊）
    enum SpaceArt { case threeSlice, whole, band }

    /// 這款要下載的圖（不含 .png）
    static func files(_ id: String) -> [String] {
        guard let art = themes[id] else { return [] }
        var names = (1...6).map { "cap-\($0)" } + ["space", "enter"]
        if let number = art.numberFace { names.append(number) }
        names += Set(art.specialKeys.values.map { $0.name }).sorted()
        return names.map { "\(id)-\($0)" }
    }

    let anchors: [CGPoint]
    let functionCap: Int
    let spaceY: CGFloat
    let enterY: CGFloat
    var spaceX: CGFloat = 0.5
    var spaceArt = SpaceArt.threeSlice
    /// 123 鍵用自己的圖（巧克力、神燈、效果器）
    var numberFace: String? = nil
    var numberAnchor = CGPoint(x: 0.5, y: 0.46)
    /// 特定的鍵用特別的圖（酒杯、黑膠、麥克風）：鍵用英文字母或數字表示
    var specialKeys: [String: (name: String, anchor: CGPoint)] = [:]

    /// 注音鍵對應到大千鍵盤上的哪個英文字母／數字（特別的圖照位置放，注音和英文都在同一顆）
    private static let zhuyinKey: [Character: String] = [
        "ㄅ": "1", "ㄉ": "2", "ˇ": "3", "ˋ": "4", "ㄓ": "5", "ˊ": "6", "˙": "7", "ㄚ": "8", "ㄞ": "9", "ㄢ": "0",
        "ㄆ": "q", "ㄊ": "w", "ㄍ": "e", "ㄐ": "r", "ㄔ": "t", "ㄗ": "y", "ㄧ": "u", "ㄛ": "i", "ㄟ": "o", "ㄣ": "p",
        "ㄇ": "a", "ㄋ": "s", "ㄎ": "d", "ㄑ": "f", "ㄕ": "g", "ㄘ": "h", "ㄨ": "j", "ㄜ": "k", "ㄠ": "l", "ㄤ": ";",
        "ㄈ": "z", "ㄌ": "x", "ㄏ": "c", "ㄒ": "v", "ㄖ": "b", "ㄙ": "n", "ㄩ": "m", "ㄝ": ",", "ㄡ": ".", "ㄥ": "/",
    ]

    private static func caps(_ ys: [CGFloat], x: CGFloat = 0.5) -> [CGPoint] { ys.map { CGPoint(x: x, y: $0) } }

    static let themes: [String: RoyalKeyArt] = [
        "royal-lion": RoyalKeyArt(anchors: [CGPoint(x: 0.5, y: 0.4), CGPoint(x: 0.5, y: 0.41), CGPoint(x: 0.5, y: 0.45), CGPoint(x: 0.5, y: 0.44), CGPoint(x: 0.5, y: 0.46), CGPoint(x: 0.5, y: 0.42)], functionCap: 3, spaceY: 0.49, enterY: 0.56),
        "royal-swan": RoyalKeyArt(anchors: [CGPoint(x: 0.5, y: 0.4), CGPoint(x: 0.5, y: 0.45), CGPoint(x: 0.5, y: 0.43), CGPoint(x: 0.57, y: 0.43), CGPoint(x: 0.43, y: 0.53), CGPoint(x: 0.5, y: 0.36)], functionCap: 1, spaceY: 0.49, enterY: 0.46),
        "royal-chapel": RoyalKeyArt(anchors: [CGPoint(x: 0.5, y: 0.53), CGPoint(x: 0.5, y: 0.44), CGPoint(x: 0.5, y: 0.51), CGPoint(x: 0.5, y: 0.45), CGPoint(x: 0.5, y: 0.44), CGPoint(x: 0.5, y: 0.44)], functionCap: 3, spaceY: 0.51, enterY: 0.5),
        "royal-orangery": RoyalKeyArt(anchors: [CGPoint(x: 0.5, y: 0.53), CGPoint(x: 0.5, y: 0.45), CGPoint(x: 0.49, y: 0.49), CGPoint(x: 0.43, y: 0.49), CGPoint(x: 0.5, y: 0.65), CGPoint(x: 0.5, y: 0.47)], functionCap: 1, spaceY: 0.6, enterY: 0.65),
        // 私藏酒廊：5／ㄓ 威士忌杯、M／ㄩ 紅酒杯、S／ㄋ 香檳杯，123 是黑巧克力
        "lounge-reserve": RoyalKeyArt(anchors: caps(Array(repeating: 0.39, count: 6), x: 0.57), functionCap: 2, spaceY: 0.45, enterY: 0.38,
                                      numberFace: "numbers", numberAnchor: CGPoint(x: 0.5, y: 0.46),
                                      specialKeys: ["5": ("whisky", CGPoint(x: 0.5, y: 0.48)),
                                                    "m": ("wine", CGPoint(x: 0.5, y: 0.35)),
                                                    "s": ("champagne", CGPoint(x: 0.5, y: 0.32))]),
        // 月煙琉璃：空白鍵是整張飛毯，123 是神燈
        "sapphire-mist": RoyalKeyArt(anchors: caps([0.54, 0.56, 0.47, 0.59, 0.5, 0.52]), functionCap: 1, spaceY: 0.5, enterY: 0.52,
                                     spaceArt: .whole, numberFace: "numbers", numberAnchor: CGPoint(x: 0.56, y: 0.6)),
        // 夜肺：V／ㄒ 黑膠、A／ㄇ 音箱、D／ㄎ CD、M／ㄩ 麥克風，123 是效果器，空白鍵左邊是貝斯
        "night-lungs": RoyalKeyArt(anchors: caps([0.42, 0.47, 0.47, 0.51, 0.6, 0.44]), functionCap: 1, spaceY: 0.5, enterY: 0.44,
                                   spaceX: 0.71, spaceArt: .band, numberFace: "pedal", numberAnchor: CGPoint(x: 0.5, y: 0.51),
                                   specialKeys: ["v": ("vinyl", CGPoint(x: 0.5, y: 0.62)),
                                                 "a": ("amp", CGPoint(x: 0.5, y: 0.58)),
                                                 "d": ("cd", CGPoint(x: 0.5, y: 0.61)),
                                                 "m": ("mic", CGPoint(x: 0.5, y: 0.46))]),
    ]

    private static let order = [
        0,2,1,3,5,4,0,3,2,5, 4,1,3,5,2,0,4,5,1,3,
        2,5,4,1,0,3,5,2,4,0, 3,0,2,4,1,5,2,4,0,1
    ]

    func face(index: Int, action: KeyAction) -> (name: String, anchor: CGPoint) {
        if !specialKeys.isEmpty {
            let key: String?
            switch action {
            case .text(let s): key = s.lowercased()
            case .zhuyin(let c): key = Self.zhuyinKey[c]
            default: key = nil
            }
            if let key = key, let special = specialKeys[key] { return special }
        }
        switch action {
        case .layer(.numbers) where numberFace != nil: return (numberFace ?? "numbers", numberAnchor)
        case .space: return ("space", CGPoint(x: spaceX, y: spaceY))
        case .returnKey: return ("enter", CGPoint(x: 0.5, y: enterY))
        default:
            let cap = action.isCharacter ? Self.order[max(0, index) % Self.order.count] : functionCap
            return ("cap-\(cap + 1)", anchors[cap])
        }
    }
}
