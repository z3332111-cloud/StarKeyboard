// 由 node tools/build_fox_letter_theme.js 產生，請修改 tools/fox_letter_prototype.json。
import UIKit

enum FoxLetterArtwork {
    static let paperPalettes: [[Int]] = [[0,3,6],[1,5],[2,7],[4],[8]]
    static let paperCuts: [CGFloat] = [0,0.15,0.425,0.575,0.85,1]
    static let paperWideCells: [[CGFloat]] = [[0.02,0.065,0.96,0.4],[0.02,0.54,0.96,0.4]]
    static let theme = KeyboardTheme(id: "fox-letter", name: "小狐狸的楓葉信",
        backgroundTop: UIColor(hex: 0x51424D), backgroundBottom: UIColor(hex: 0x392F3D), key: UIColor(hex: 0x6C5050), keyText: UIColor(hex: 0xFFF5E4), specialKey: UIColor(hex: 0x59434A), specialText: UIColor(hex: 0xFFF5E4), accent: UIColor(hex: 0xE9AE78), accentText: UIColor(hex: 0x3F2C27), shadow: UIColor(hex: 0x271D27), decoration: "", isDark: true)
    struct Palette {
        let name: String
        let fur: UIColor
        let cheek: UIColor
        let text: UIColor
        let accessory: String
    }
    static let palettes: [Palette] = [
        Palette(name: "楓葉橘", fur: UIColor(hex: 0xA95B30), cheek: UIColor(hex: 0xF7DEC0), text: UIColor(hex: 0xFFF9EF), accessory: "leaf"),
        Palette(name: "奶油米", fur: UIColor(hex: 0xDCBC8E), cheek: UIColor(hex: 0xFAE8CF), text: UIColor(hex: 0x543B2F), accessory: "beret"),
        Palette(name: "栗子棕", fur: UIColor(hex: 0x71514C), cheek: UIColor(hex: 0xDDBA9D), text: UIColor(hex: 0xFFF9EF), accessory: "scarf"),
        Palette(name: "楓紅", fur: UIColor(hex: 0xA85747), cheek: UIColor(hex: 0xE8B99B), text: UIColor(hex: 0xFFF9EF), accessory: "letter"),
        Palette(name: "霧橄欖", fur: UIColor(hex: 0x737344), cheek: UIColor(hex: 0xE7D3AE), text: UIColor(hex: 0xFFF9EF), accessory: "leaf")
    ]
    static let accessories: [String: [FoxLetterPrototype.ArtLayer]] = [
        "leaf": [
            FoxLetterPrototype.ArtLayer(space: .head, fill: UIColor(hex: 0xE3A04F), stroke: UIColor(hex: 0x975634), lineWidth: 0.35,
                ops: [0, 80, 25, 1, 68, 22, 1, 73, 17, 1, 67, 11, 1, 77, 12, 1, 78, 3, 1, 84, 9, 1, 90, 4, 1, 91, 13, 1, 98, 12, 1, 94, 20, 1, 99, 24, 1, 87, 26, 1, 86, 31, 1, 82, 30, 4]),
            FoxLetterPrototype.ArtLayer(space: .head, fill: UIColor(hex: 0xB76A39), stroke: nil, lineWidth: 0,
                ops: [0, 80, 9, 1, 83, 20, 1, 87, 29, 1, 85, 30, 1, 81, 21, 1, 75, 16, 1, 77, 15, 1, 81, 18, 1, 79, 10, 4])
        ],
        "beret": [
            FoxLetterPrototype.ArtLayer(space: .head, fill: UIColor(hex: 0x8B4F42), stroke: UIColor(hex: 0x683F37), lineWidth: 0.4,
                ops: [0, 4, 19, 2, 0, 12, 8, 5, 20, 5, 2, 32, 1, 43, 5, 43, 13, 3, 46, 18, 40, 23, 3, 22, 24, 4, 19, 4, 0, 24, 6, 1, 23, 1, 3, 26, -1, 29, 1, 1, 28, 6, 4]),
            FoxLetterPrototype.ArtLayer(space: .head, fill: UIColor(hex: 0x6B413A), stroke: nil, lineWidth: 0,
                ops: [0, 5, 18, 3, 23, 22, 42, 18, 1, 40, 23, 3, 22, 25, 5, 21, 4])
        ],
        "letter": [
            FoxLetterPrototype.ArtLayer(space: .head, fill: UIColor(hex: 0xFFF0D9), stroke: UIColor(hex: 0x805543), lineWidth: 0.4,
                ops: [0, 67, 6, 1, 97, 9, 1, 95, 29, 1, 65, 26, 4]),
            FoxLetterPrototype.ArtLayer(space: .head, fill: UIColor(hex: 0xD4AF89), stroke: nil, lineWidth: 0,
                ops: [0, 67, 7, 1, 81, 18, 1, 97, 10, 1, 96, 12, 1, 81, 20, 1, 66, 9, 4, 0, 65, 25, 1, 76, 18, 1, 77, 20, 1, 67, 27, 4, 0, 85, 20, 1, 95, 27, 1, 95, 29, 1, 83, 21, 4]),
            FoxLetterPrototype.ArtLayer(space: .head, fill: UIColor(hex: 0xB95F44), stroke: nil, lineWidth: 0,
                ops: [0, 81, 16, 2, 76, 11, 73, 17, 78, 20, 1, 82, 24, 1, 86, 21, 2, 91, 17, 86, 12, 82, 16, 4])
        ],
        "scarf": [
            FoxLetterPrototype.ArtLayer(space: .head, fill: UIColor(hex: 0xB69454), stroke: UIColor(hex: 0x795D40), lineWidth: 0.3,
                ops: [0, 1, 80, 3, 12, 85, 25, 84, 1, 25, 95, 3, 12, 97, 2, 91, 4, 0, 19, 88, 1, 29, 88, 1, 32, 100, 1, 23, 100, 4]),
            FoxLetterPrototype.ArtLayer(space: .head, fill: UIColor(hex: 0x687748), stroke: nil, lineWidth: 0,
                ops: [0, 7, 83, 1, 11, 84, 1, 11, 94, 1, 7, 93, 4, 0, 17, 84, 1, 21, 84, 1, 21, 95, 1, 17, 95, 4, 0, 25, 90, 1, 29, 90, 1, 31, 100, 1, 27, 100, 4, 0, 2, 87, 1, 25, 89, 1, 25, 92, 1, 2, 90, 4])
        ]
    ]
}
