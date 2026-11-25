import UIKit

/// 調整背景照片：蓋在整個鍵盤上，一指拖拉移動、兩指縮放，下面有「重設」「完成」
final class PhotoAdjustView: UIView {
    var onPan: ((CGPoint) -> Void)?
    var onPinch: ((CGFloat) -> Void)?
    var onReset: (() -> Void)?
    var onDone: (() -> Void)?

    private let hint = UILabel()
    private let resetButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)

    init(style: KeyboardStyle) {
        super.init(frame: .zero)
        let t = style.theme
        hint.text = "拖拉移動照片・兩指縮放"
        hint.font = .rounded(14, .semibold)
        hint.textAlignment = .center
        hint.textColor = t.accentText
        hint.backgroundColor = t.accent.withAlphaComponent(0.92)
        hint.layer.cornerRadius = 15
        hint.clipsToBounds = true
        addSubview(hint)

        for (button, title, bg, fg) in [(resetButton, "重設", t.specialKey, t.specialText), (doneButton, "完成", t.accent, t.accentText)] {
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .rounded(16, .bold)
            button.setTitleColor(fg, for: .normal)
            button.backgroundColor = bg
            button.layer.cornerRadius = 14
            addSubview(button)
        }
        resetButton.addAction(UIAction { [weak self] _ in self?.onReset?() }, for: .touchUpInside)
        doneButton.addAction(UIAction { [weak self] _ in self?.onDone?() }, for: .touchUpInside)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 2
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pan.delegate = self
        pinch.delegate = self
        addGestureRecognizer(pan)
        addGestureRecognizer(pinch)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds
        let hintW = min(b.width - 32, 230)
        hint.frame = CGRect(x: (b.width - hintW) / 2, y: 10, width: hintW, height: 30)
        let barY = b.height - 12 - 44
        let w = b.width - 32 - 10
        resetButton.frame = CGRect(x: 16, y: barY, width: w / 3, height: 44)
        doneButton.frame = CGRect(x: 16 + w / 3 + 10, y: barY, width: w * 2 / 3, height: 44)
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        let d = g.translation(in: self)
        g.setTranslation(.zero, in: self)
        onPan?(d)
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        onPinch?(g.scale)
        g.scale = 1
    }
}

extension PhotoAdjustView: UIGestureRecognizerDelegate {
    /// 拖拉和縮放可以同時進行
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    /// 按到按鈕時不要當成拖拉
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !(touch.view is UIButton)
    }
}
