import UIKit

/// 圖集只解碼一次且先縮圖；每顆按鍵的圖層共用同一個 CGImage。
@MainActor
enum FoxLetterWatercolor {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()

    static func image(_ name: String) -> UIImage? {
        let key = name as NSString
        if let image = cache.object(forKey: key) { return image }
        let bundle = Bundle(for: FoxLetterArtworkView.self)
        guard let url = bundle.url(forResource: name, withExtension: "png", subdirectory: "FoxLetter"),
              let image = UIImage.downsampled(url: url, maxSide: 768), let cg = image.cgImage else { return nil }
        cache.setObject(image, forKey: key, cost: cg.bytesPerRow * cg.height)
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

    func configure(index: Int, action: KeyAction, personalSpaceArt: Bool, compact: Bool) {
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
