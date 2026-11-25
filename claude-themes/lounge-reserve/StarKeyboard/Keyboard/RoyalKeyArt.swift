import UIKit

/// The PNG files contain only painted keycaps. KeyButton draws the active legend.
struct RoyalKeyArt {
    let anchors: [CGPoint]
    let functionCap: Int
    let spaceY: CGFloat
    let enterY: CGFloat
    var hasChocolateNumberKey = false

    var cupKeys: [String: (name: String, anchor: CGPoint)] = [:]

    static let themes: [String: RoyalKeyArt] = [
        "midnight-wine": RoyalKeyArt(anchors: Array(repeating: CGPoint(x: 0.57, y: 0.39), count: 6),
                                    functionCap: 2, spaceY: 0.45, enterY: 0.38),
        "midnight-cocoa": RoyalKeyArt(anchors: Array(repeating: CGPoint(x: 0.57, y: 0.39), count: 6),
                                    functionCap: 2, spaceY: 0.45, enterY: 0.38),
        "lounge-reserve": RoyalKeyArt(anchors: Array(repeating: CGPoint(x: 0.57, y: 0.39), count: 6),
                                    functionCap: 2, spaceY: 0.45, enterY: 0.38, hasChocolateNumberKey: true,
                                    cupKeys: ["5": ("whisky", CGPoint(x: 0.5, y: 0.48)),
                                              "m": ("wine", CGPoint(x: 0.5, y: 0.35)),
                                              "s": ("champagne", CGPoint(x: 0.5, y: 0.32))]),
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
        if !cupKeys.isEmpty {
            let key: String?
            switch action {
            case .text(let letter): key = letter.lowercased()
            case .zhuyin("ㄓ"): key = "5"
            case .zhuyin("ㄩ"): key = "m"
            case .zhuyin("ㄋ"): key = "s"
            default: key = nil
            }
            if let key = key, let cup = cupKeys[key] { return cup }
        }
        switch action {
        case .layer(.numbers) where hasChocolateNumberKey: return ("numbers", CGPoint(x: 0.5, y: 0.46))
        case .space: return ("space", CGPoint(x: 0.5, y: spaceY))
        case .returnKey: return ("enter", CGPoint(x: 0.5, y: enterY))
        default:
            let cap = action.isCharacter ? Self.order[max(0, index) % Self.order.count] : functionCap
            return ("cap-\(cap + 1)", anchors[cap])
        }
    }
}
