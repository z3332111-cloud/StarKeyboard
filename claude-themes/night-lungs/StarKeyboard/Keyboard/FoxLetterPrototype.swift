// 由 node tools/build_fox_letter_prototype.js 產生，請修改 tools/fox_letter_prototype.json。
import UIKit

/// 共用狐狸臉形幾何，供單顆原型與正式角色主題使用。
/// 與離線預覽使用相同幾何資料；文字由各自的視圖疊上。
enum FoxLetterPrototype {
    enum Space { case head, face }
    struct ArtLayer {
        let space: Space
        let fill: UIColor
        let stroke: UIColor?
        let lineWidth: CGFloat
        let ops: [CGFloat]
    }
    struct Layout {
        let frame: CGRect
        let face: CGRect
        let label: CGRect
        let hint: CGRect
        let ends: CGFloat
    }
    static let textColor = UIColor(hex: 0xFFFAF1)
    static let hintColor = UIColor(hex: 0xF8E6CE)
    static let layers: [ArtLayer] = [
        ArtLayer(space: .head, fill: UIColor(hex: 0xC87843), stroke: UIColor(hex: 0x825138), lineWidth: 0.65,
                 ops: [0, 5, 34, 2, 5, 23, 8, 9, 12, 3, 3, 13, 0, 17, 4, 1, 32, 20, 3, 50, 15, 68, 20, 1, 83, 4, 3, 87, 0, 89, 4, 2, 94, 14, 96, 26, 95, 37, 2, 101, 55, 99, 75, 91, 89, 2, 83, 98, 67, 99, 50, 99, 2, 29, 99, 14, 97, 7, 87, 2, 0, 74, 0, 53, 5, 34, 4]),
        ArtLayer(space: .head, fill: UIColor(hex: 0xF6D9B5), stroke: nil, lineWidth: 0,
                 ops: [0, 11, 29, 3, 12, 16, 15, 10, 1, 27, 24, 3, 18, 24, 11, 29, 4, 0, 73, 24, 1, 85, 10, 3, 89, 18, 90, 31, 3, 83, 26, 73, 24, 4]),
        ArtLayer(space: .head, fill: UIColor(hex: 0xF6E2C6), stroke: nil, lineWidth: 0,
                 ops: [0, 3, 69, 2, 15, 68, 31, 79, 50, 84, 2, 69, 79, 85, 68, 97, 69, 2, 97, 83, 88, 93, 74, 96, 2, 59, 100, 39, 100, 25, 96, 2, 10, 93, 3, 83, 3, 69, 4]),
        ArtLayer(space: .face, fill: UIColor(hex: 0x56382C), stroke: nil, lineWidth: 0,
                 ops: [0, 24, 32, 2, 24, 39.3637965, 21.3137085, 45.333333, 18, 45.333333, 2, 14.6862915, 45.333333, 12, 39.3637965, 12, 32, 2, 12, 24.6362035, 14.6862915, 18.666667, 18, 18.666667, 2, 21.3137085, 18.666667, 24, 24.6362035, 24, 32, 4, 0, 88, 32, 2, 88, 39.3637965, 85.3137085, 45.333333, 82, 45.333333, 2, 78.6862915, 45.333333, 76, 39.3637965, 76, 32, 2, 76, 24.6362035, 78.6862915, 18.666667, 82, 18.666667, 2, 85.3137085, 18.666667, 88, 24.6362035, 88, 32, 4, 0, 43, 57, 3, 50, 52, 57, 57, 3, 59, 60, 56, 65, 1, 51, 72, 3, 50, 73, 49, 72, 1, 44, 65, 3, 41, 61, 43, 57, 4])
    ]

    static func layout(in bounds: CGRect) -> Layout {
        let frame = bounds.insetBy(dx: 2, dy: 2)
        guard frame.width > 0, frame.height > 0 else {
            return Layout(frame: .zero, face: .zero, label: .zero, hint: .zero, ends: 0)
        }
        let faceWidth = min(frame.width * 0.58, frame.height * 0.5)
        let face = CGRect(x: frame.midX - faceWidth / 2,
                          y: frame.maxY - frame.height * 0.05 - faceWidth * 0.45,
                          width: faceWidth, height: faceWidth * 0.45)
        func place(_ r: CGRect) -> CGRect {
            CGRect(x: frame.minX + frame.width * r.minX, y: frame.minY + frame.height * r.minY,
                   width: frame.width * r.width, height: frame.height * r.height)
        }
        return Layout(frame: frame, face: face,
                      label: place(CGRect(x: 0.14, y: 0.26, width: 0.72, height: 0.44)),
                      hint: place(CGRect(x: 0.34, y: 0, width: 0.32, height: 0.2)),
                      ends: min(frame.width, frame.height * 0.85))
    }
}

/// 圖層只建立一次，調整尺寸時更新路徑，文字與插畫分開。
final class FoxLetterPrototypeView: UIView {
    var text = "A" { didSet { label.text = text; setNeedsLayout() } }
    var hint = "" { didSet { hintLabel.text = hint; setNeedsLayout() } }
    var fontScale: CGFloat = 1 { didSet { setNeedsLayout() } }
    var isPressed = false {
        didSet { drawing.opacity = isPressed ? 0.82 : 1 }
    }
    private let drawing = CALayer()
    private let label = UILabel()
    private let hintLabel = UILabel()
    private var artwork: [CAShapeLayer] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = false
        layer.addSublayer(drawing)
        for definition in FoxLetterPrototype.layers {
            let shape = CAShapeLayer()
            shape.fillColor = definition.fill.cgColor
            shape.strokeColor = definition.stroke?.cgColor
            shape.lineWidth = definition.lineWidth
            shape.lineJoin = .round
            shape.lineCap = .round
            drawing.addSublayer(shape)
            artwork.append(shape)
        }
        label.text = text
        label.textColor = FoxLetterPrototype.textColor
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        label.baselineAdjustment = .alignCenters
        addSubview(label)
        hintLabel.textColor = FoxLetterPrototype.hintColor
        hintLabel.textAlignment = .right
        hintLabel.adjustsFontSizeToFitWidth = true
        addSubview(hintLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let layout = FoxLetterPrototype.layout(in: bounds)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        drawing.frame = bounds
        for (shape, definition) in zip(artwork, FoxLetterPrototype.layers) {
            shape.isHidden = layout.frame.isEmpty
            shape.frame = bounds
            shape.path = KeyShapeArt.build(definition.ops,
                in: definition.space == .head ? layout.frame : layout.face,
                ends: definition.space == .head ? layout.ends : nil)
        }
        CATransaction.commit()
        label.isHidden = layout.frame.isEmpty
        hintLabel.isHidden = layout.frame.isEmpty || hint.isEmpty
        guard !layout.frame.isEmpty else { return }
        label.frame = layout.label
        let mainFont = UIFont.rounded(min(23 * fontScale, layout.label.height), .bold)
        label.font = mainFont.withSize(mainFont.pointSize * min(1, layout.label.height / mainFont.lineHeight))
        hintLabel.frame = layout.hint
        let hintFont = UIFont.rounded(min(9 * fontScale, layout.hint.height), .medium)
        hintLabel.font = hintFont.withSize(hintFont.pointSize * min(1, layout.hint.height / hintFont.lineHeight))
    }
}
