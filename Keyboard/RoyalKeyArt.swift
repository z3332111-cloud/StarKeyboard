import UIKit

/// 宮廷主題（金獅、天鵝宮、加冕廳、橙花房）：每款六顆鍵帽＋空白鍵＋換行鍵，一張圖一顆，只畫鍵帽，字由 KeyButton 畫。
/// 圖放在 GitHub Pages 的 theme-packs（要用才下載），anchors 是每顆鍵帽上放字的位置（0～1）。
struct RoyalKeyArt {
    /// 這款要下載的圖（不含 .png）
    static func files(_ id: String) -> [String] {
        guard themes[id] != nil else { return [] }
        return (1...6).map { "\(id)-cap-\($0)" } + ["\(id)-space", "\(id)-enter"]
    }

    let anchors: [CGPoint]
    let functionCap: Int
    let spaceY: CGFloat
    let enterY: CGFloat

    static let themes: [String: RoyalKeyArt] = [
        "royal-lion": RoyalKeyArt(anchors: [CGPoint(x: 0.5, y: 0.4), CGPoint(x: 0.5, y: 0.41), CGPoint(x: 0.5, y: 0.45), CGPoint(x: 0.5, y: 0.44), CGPoint(x: 0.5, y: 0.46), CGPoint(x: 0.5, y: 0.42)], functionCap: 3, spaceY: 0.49, enterY: 0.56),
        "royal-swan": RoyalKeyArt(anchors: [CGPoint(x: 0.5, y: 0.4), CGPoint(x: 0.5, y: 0.45), CGPoint(x: 0.5, y: 0.43), CGPoint(x: 0.57, y: 0.43), CGPoint(x: 0.43, y: 0.53), CGPoint(x: 0.5, y: 0.36)], functionCap: 1, spaceY: 0.49, enterY: 0.46),
        "royal-chapel": RoyalKeyArt(anchors: [CGPoint(x: 0.5, y: 0.53), CGPoint(x: 0.5, y: 0.44), CGPoint(x: 0.5, y: 0.51), CGPoint(x: 0.5, y: 0.45), CGPoint(x: 0.5, y: 0.44), CGPoint(x: 0.5, y: 0.44)], functionCap: 3, spaceY: 0.51, enterY: 0.5),
        "royal-orangery": RoyalKeyArt(anchors: [CGPoint(x: 0.5, y: 0.53), CGPoint(x: 0.5, y: 0.45), CGPoint(x: 0.49, y: 0.49), CGPoint(x: 0.43, y: 0.49), CGPoint(x: 0.5, y: 0.65), CGPoint(x: 0.5, y: 0.47)], functionCap: 1, spaceY: 0.6, enterY: 0.65)
    ]

    private static let order = [
        0,2,1,3,5,4,0,3,2,5, 4,1,3,5,2,0,4,5,1,3,
        2,5,4,1,0,3,5,2,4,0, 3,0,2,4,1,5,2,4,0,1
    ]

    func face(index: Int, action: KeyAction) -> (name: String, anchor: CGPoint) {
        switch action {
        case .space: return ("space", CGPoint(x: 0.5, y: spaceY))
        case .returnKey: return ("enter", CGPoint(x: 0.5, y: enterY))
        default:
            let cap = action.isCharacter ? Self.order[max(0, index) % Self.order.count] : functionCap
            return ("cap-\(cap + 1)", anchors[cap])
        }
    }
}
