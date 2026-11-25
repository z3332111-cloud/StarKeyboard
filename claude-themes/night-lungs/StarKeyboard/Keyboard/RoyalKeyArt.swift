import UIKit

/// The PNG files contain only painted keycaps. KeyButton draws the active legend.
struct RoyalKeyArt {
    let anchors: [CGPoint]
    let functionCap: Int
    let spaceY: CGFloat
    let enterY: CGFloat
    var hasChocolateNumberKey = false

    var accentKeys: [String: (name: String, anchor: CGPoint)] = [:]

    var numberFace: String?
    var usesBandArtwork = false

    static let themes: [String: RoyalKeyArt] = [
        "night-lungs": RoyalKeyArt(anchors: [0.42, 0.47, 0.47, 0.51, 0.60, 0.44].map { CGPoint(x: 0.5, y: $0) },
                                  functionCap: 1, spaceY: 0.5, enterY: 0.44,
                                  accentKeys: ["v": ("vinyl", CGPoint(x: 0.50, y: 0.62)),
                                               "a": ("amp", CGPoint(x: 0.5, y: 0.58)),
                                               "d": ("cd", CGPoint(x: 0.50, y: 0.61)),
                                               "m": ("mic", CGPoint(x: 0.50, y: 0.46))],
                                  numberFace: "pedal", usesBandArtwork: true),
        "midnight-wine": RoyalKeyArt(anchors: Array(repeating: CGPoint(x: 0.57, y: 0.39), count: 6),
                                    functionCap: 2, spaceY: 0.45, enterY: 0.38),
        "midnight-cocoa": RoyalKeyArt(anchors: Array(repeating: CGPoint(x: 0.57, y: 0.39), count: 6),
                                    functionCap: 2, spaceY: 0.45, enterY: 0.38),
        "lounge-reserve": RoyalKeyArt(anchors: Array(repeating: CGPoint(x: 0.57, y: 0.39), count: 6),
                                    functionCap: 2, spaceY: 0.45, enterY: 0.38, hasChocolateNumberKey: true,
                                    accentKeys: ["z": ("whisky", CGPoint(x: 0.5, y: 0.48)),
                                              "y": ("wine", CGPoint(x: 0.5, y: 0.35)),
                                              "r": ("champagne", CGPoint(x: 0.5, y: 0.32))]),
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
        if !accentKeys.isEmpty {
            let key: String?
            switch action {
            case .text(let letter): key = letter.lowercased()
            case .zhuyin("ㄈ"): key = "z"
            case .zhuyin("ㄗ"): key = "y"
            case .zhuyin("ㄐ"): key = "r"
            case .zhuyin("ㄒ"): key = "v"
            case .zhuyin("ㄇ"): key = "a"
            case .zhuyin("ㄎ"): key = "d"
            case .zhuyin("ㄩ"): key = "m"
            default: key = nil
            }
            if let key = key, let face = accentKeys[key] { return face }
        }
        switch action {
        case .layer(.numbers) where numberFace != nil: return (numberFace ?? "numbers", CGPoint(x: 0.5, y: 0.51))
        case .layer(.numbers) where hasChocolateNumberKey: return ("numbers", CGPoint(x: 0.5, y: 0.46))
        case .space: return ("space", CGPoint(x: usesBandArtwork ? 0.71 : 0.5, y: spaceY))
        case .returnKey: return ("enter", CGPoint(x: 0.5, y: enterY))
        default:
            let cap = action.isCharacter ? Self.order[max(0, index) % Self.order.count] : functionCap
            return ("cap-\(cap + 1)", anchors[cap])
        }
    }
}
