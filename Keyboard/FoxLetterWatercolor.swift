import UIKit

/// 圖集只解碼一次且先縮圖；每顆按鍵的圖層共用同一個 CGImage。
@MainActor
enum FoxLetterWatercolor {
    // 不用 NSCache：記憶體一緊它就清掉，每顆鍵又各讀一次，反而把鍵盤撐爆（卡死、閃退）
    private static var images: [String: UIImage] = [:]

    static func image(_ name: String) -> UIImage? {
        if let image = images[name] { return image }
        let bundle = Bundle(for: FoxLetterArtworkView.self)
        guard let url = ThemePacks.localURL(name) ?? bundle.url(forResource: name, withExtension: "png", subdirectory: "FoxLetter") else { return nil }
        // 換主題就放掉前一款的圖，記憶體裡只留正在用的
        if name.hasPrefix("theme-") || images.keys.contains(where: { $0.hasPrefix("theme-") }) { images.removeAll() }
        // 讀圖的暫存馬上放掉，不要等到這一輪結束才一起放
        let image = autoreleasepool { UIImage.downsampled(url: url, maxSide: 768) }
        images[name] = image
        return image
    }

    static var keycaps: CGImage? { image("keycaps-watercolor-v2")?.cgImage }
    static var wideKeycaps: CGImage? { image("wide-keycaps-watercolor-v2")?.cgImage }
    static var backdrop: CGImage? { image("background-watercolor-v2")?.cgImage }

    static func sprite(index: Int, action: KeyAction, personalSpaceArt: Bool) -> Int {
        switch action {
        case .space: return personalSpaceArt ? 3 : 0
        case .returnKey: return 7
        default:
            let position = max(0, index)
            let choices = FoxLetterArtwork.paperPalettes[position % 5]
            return choices[(position / 5) % choices.count]
        }
    }
}

/// 寬鍵在五官兩側延展安靜的毛色；中央五官、兩端耳朵不跟著水平拉長。
final class FoxLetterWatercolorKeyView: UIView {
    private let pieces = (0..<5).map { _ in CALayer() }
    private var sprite = -1
    private var compact = false
    private var wideRow = 0
    private var laidOutBounds = CGRect.null

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isUserInteractionEnabled = false
        for piece in pieces {
            piece.contents = FoxLetterWatercolor.keycaps
            piece.magnificationFilter = .linear
            piece.minificationFilter = .linear
            layer.addSublayer(piece)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // 設計圖鑑的主題：圖集上面一排三顆鍵帽、下面一條寬鍵；功能鍵是素色的圓角方塊
    private var packImage: CGImage?
    private var packCap = 0
    private var packKind = 0   // 0 鍵帽、1 寬鍵、2 功能鍵
    private let chip = CALayer()

    func configure(look: ThemeLook, index: Int, action: KeyAction) {
        packImage = FoxLetterWatercolor.image("theme-" + look.theme.id)?.cgImage
        let position = max(0, index)
        packCap = (position + position / 4) % 3
        packKind = action == .space ? 1 : (action.isCharacter ? 0 : 2)
        chip.backgroundColor = look.theme.specialKey.cgColor
        chip.borderColor = look.theme.specialText.withAlphaComponent(0.25).cgColor
        chip.borderWidth = 0.5
        if chip.superlayer == nil { layer.insertSublayer(chip, at: 0) }
        sprite = -1
        laidOutBounds = .null
        setNeedsLayout()
    }

    private func layoutPack() {
        let capH: CGFloat = 256.0 / 448.0
        let frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        chip.isHidden = packKind != 2
        chip.frame = frame
        chip.cornerRadius = min(8, frame.height * 0.22)
        for piece in pieces {
            piece.contents = packImage
            piece.isHidden = packKind == 2
        }
        guard packKind != 2 else { return }
        if packKind == 0 {
            for (i, piece) in pieces.enumerated() { piece.isHidden = i > 0 }
            pieces[0].frame = frame
            pieces[0].contentsRect = CGRect(x: CGFloat(packCap) / 3, y: 0, width: 1.0 / 3, height: capH)
            return
        }
        // 寬鍵：兩端的圖案不變形，中間延展
        let natural = min(frame.height * 4, frame.width / 0.45)
        let stretch = (frame.width - natural * 0.45) / 2
        let cuts = FoxLetterArtwork.paperCuts
        var x = frame.minX
        for (i, piece) in pieces.enumerated() {
            let fraction = cuts[i + 1] - cuts[i]
            let width = i == 1 || i == 3 ? stretch : natural * fraction
            piece.frame = CGRect(x: x, y: frame.minY, width: width, height: frame.height)
            piece.contentsRect = CGRect(x: cuts[i], y: capH, width: fraction, height: 1 - capH)
            x += width
        }
    }

    func configure(index: Int, action: KeyAction, personalSpaceArt: Bool, compact: Bool) {
        packImage = nil
        chip.isHidden = true
        let next = FoxLetterWatercolor.sprite(index: index, action: action, personalSpaceArt: personalSpaceArt)
        let nextRow = action == .space && !personalSpaceArt ? 0 : 1
        guard next != sprite || compact != self.compact || nextRow != wideRow else { return }
        sprite = next
        self.compact = compact
        wideRow = nextRow
        laidOutBounds = .null
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if packImage != nil {
            guard bounds != laidOutBounds else { return }
            laidOutBounds = bounds
            layoutPack()
            return
        }
        guard bounds != laidOutBounds, sprite >= 0 else { return }
        laidOutBounds = bounds
        let frame = bounds
        var cell = CGRect(x: CGFloat(sprite % 3) / 3, y: CGFloat(sprite / 3) / 3,
                          width: 1 / 3, height: (compact ? 0.78 : 1) / 3)
        let wide = frame.width > frame.height * 1.35
        if wide {
            let rect = FoxLetterArtwork.paperWideCells[wideRow]
            cell = CGRect(x: rect[0], y: rect[1], width: rect[2], height: rect[3] * (compact ? 0.78 : 1))
        }
        let image = wide ? FoxLetterWatercolor.wideKeycaps : FoxLetterWatercolor.keycaps
        let naturalWidth = frame.height * 2.9
        let stretch = (frame.width - naturalWidth * 0.45) / 2
        let cuts = FoxLetterArtwork.paperCuts
        var x = frame.minX
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, piece) in pieces.enumerated() {
            piece.contents = image
            piece.isHidden = frame.isEmpty || (!wide && i > 0)
            guard !piece.isHidden else { continue }
            if !wide {
                piece.frame = frame
                piece.contentsRect = cell
            } else {
                let fraction = cuts[i + 1] - cuts[i]
                let width = i == 1 || i == 3 ? stretch : naturalWidth * fraction
                piece.frame = CGRect(x: x, y: frame.minY, width: width, height: frame.height)
                piece.contentsRect = CGRect(x: cell.minX + cell.width * cuts[i], y: cell.minY,
                    width: cell.width * fraction, height: cell.height)
                x += width
            }
        }
        CATransaction.commit()
    }
}
