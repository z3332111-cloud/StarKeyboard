import UIKit

/// 邊看鍵盤邊調大小：放在選字列的位置，下面的鍵盤照常顯示、可以直接試打
final class SizeAdjustBar: UIView {
    var onChange: (() -> Void)?
    var onDone: (() -> Void)?

    private struct Item {
        let title: String
        let range: ClosedRange<Float>
        let get: () -> CGFloat
        let set: (CGFloat) -> Void
    }

    private let style: KeyboardStyle
    private var items: [Item] = []
    private var current = 0
    private var tabs: [UIButton] = []
    private let slider = UISlider()
    private let done = UIButton(type: .system)

    init(style: KeyboardStyle, settings: KeyboardSettings) {
        self.style = style
        super.init(frame: .zero)
        items = [
            Item(title: "高度", range: 0.8...1.3, get: { settings.heightScale }, set: { settings.heightScale = $0 }),
            Item(title: "字", range: 0.8...1.4, get: { settings.fontScale }, set: { settings.fontScale = $0 }),
            Item(title: "間距", range: 0.3...1.6, get: { settings.gapScale }, set: { settings.gapScale = $0 }),
            Item(title: "造型", range: 0.9...1.6, get: { settings.shapeScale }, set: { settings.shapeScale = $0 }),
        ]
        let t = style.theme
        backgroundColor = t.isDark ? UIColor.black.withAlphaComponent(0.35) : UIColor.white.withAlphaComponent(0.55)
        for (i, item) in items.enumerated() {
            let b = UIButton(type: .system)
            b.setTitle(item.title, for: .normal)
            b.titleLabel?.font = .rounded(13, .bold)
            b.layer.cornerRadius = 9
            b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
            b.addAction(UIAction { [weak self] _ in self?.select(i) }, for: .touchUpInside)
            tabs.append(b)
            addSubview(b)
        }
        slider.minimumTrackTintColor = t.accent
        slider.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            self.items[self.current].set(CGFloat(self.slider.value))
            self.onChange?()
        }, for: .valueChanged)
        addSubview(slider)
        done.setTitle("完成", for: .normal)
        done.titleLabel?.font = .rounded(14, .bold)
        done.setTitleColor(t.accentText, for: .normal)
        done.backgroundColor = t.accent
        done.layer.cornerRadius = 10
        done.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        done.addAction(UIAction { [weak self] _ in self?.onDone?() }, for: .touchUpInside)
        addSubview(done)
        select(0)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h: CGFloat = 30
        let y = (bounds.height - h) / 2
        var x: CGFloat = 6
        for b in tabs {
            let w = b.sizeThatFits(CGSize(width: 100, height: h)).width
            b.frame = CGRect(x: x, y: y, width: w, height: h)
            x += w + 3
        }
        let dw = done.sizeThatFits(CGSize(width: 100, height: h)).width
        done.frame = CGRect(x: bounds.width - 6 - dw, y: y, width: dw, height: h)
        slider.frame = CGRect(x: x + 4, y: 0, width: max(40, done.frame.minX - x - 10), height: bounds.height)
    }

    private func select(_ i: Int) {
        current = i
        let t = style.theme
        for (j, b) in tabs.enumerated() {
            let on = j == i
            b.backgroundColor = on ? t.accent : t.key.withAlphaComponent(0.8)
            b.setTitleColor(on ? t.accentText : t.keyText, for: .normal)
        }
        let item = items[i]
        slider.minimumValue = item.range.lowerBound
        slider.maximumValue = item.range.upperBound
        slider.value = Float(item.get())
    }
}
