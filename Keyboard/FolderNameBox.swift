import UIKit

/// A small naming card fed by our existing composition engine, so a keyboard
/// extension never has to summon a second keyboard over its own text field.
final class FolderNameBox: UIView {
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?
    private let title = UILabel()
    private let name = UILabel()
    private let cancel = UIButton(type: .system)
    private let save = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 14
        layer.borderWidth = 1
        title.font = .rounded(12, .semibold)
        name.font = .rounded(16, .semibold)
        name.lineBreakMode = .byTruncatingHead
        name.accessibilityLabel = "資料夾名稱，用下方鍵盤輸入"
        cancel.setTitle("取消", for: .normal)
        save.setTitle("建立", for: .normal)
        for button in [cancel, save] { button.titleLabel?.font = .rounded(15, .semibold) }
        cancel.addAction(UIAction { [weak self] _ in self?.onCancel?() }, for: .touchUpInside)
        save.addAction(UIAction { [weak self] _ in self?.onSave?() }, for: .touchUpInside)
        [title, name, cancel, save].forEach { addSubview($0) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(name text: String, renaming: Bool, style: KeyboardStyle) {
        UIView.performWithoutAnimation {
            title.text = (renaming ? "重新命名資料夾" : "新增資料夾") + " · 最多 40 字"
            name.text = text.isEmpty ? "例如：工作、常用回覆 ▏" : text + "▏"
            name.accessibilityValue = text.isEmpty ? "尚未輸入" : text
            save.setTitle(renaming ? "儲存" : "建立", for: .normal)
            let theme = style.theme
            backgroundColor = theme.key
            layer.borderColor = theme.accent.withAlphaComponent(0.5).cgColor
            title.textColor = theme.keyText.withAlphaComponent(0.7)
            name.textColor = theme.keyText.withAlphaComponent(text.isEmpty ? 0.5 : 1)
            cancel.tintColor = theme.keyText
            save.tintColor = theme.isDark ? theme.accent : theme.specialText
        }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        title.frame = CGRect(x: 12, y: 5, width: bounds.width - 24, height: 22)
        name.frame = CGRect(x: 12, y: 27, width: max(0, bounds.width - 130), height: 44)
        cancel.frame = CGRect(x: bounds.width - 112, y: 27, width: 52, height: 44)
        save.frame = CGRect(x: bounds.width - 60, y: 27, width: 52, height: 44)
    }
}
