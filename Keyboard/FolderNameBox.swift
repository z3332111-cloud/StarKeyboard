import UIKit

/// A small naming card fed by our existing composition engine, so a keyboard
/// extension never has to summon a second keyboard over its own text field.
/// 也拿來改剪貼簿：變成三行高的小對話框，顯示整段文字和游標。
final class FolderNameBox: UIView {
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?
    private let title = UILabel()
    private let name = UILabel()
    private let cancel = UIButton(type: .system)
    private let save = UIButton(type: .system)
    private var isClip = false

    /// 改剪貼簿時對話框的高度（含上下留白）
    static let clipHeight: CGFloat = 136

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
            isClip = false
            name.numberOfLines = 1
            name.lineBreakMode = .byTruncatingHead
            name.font = .rounded(16, .semibold)
            name.accessibilityLabel = "資料夾名稱，用下方鍵盤輸入"
            title.text = (renaming ? "重新命名資料夾" : "新增資料夾") + " · 最多 40 字"
            name.text = text.isEmpty ? "例如：工作、常用回覆 ▏" : text + "▏"
            name.accessibilityValue = text.isEmpty ? "尚未輸入" : text
            save.setTitle(renaming ? "儲存" : "建立", for: .normal)
            applyColors(style, empty: text.isEmpty)
            setNeedsLayout()
        }
    }

    /// 改剪貼簿：整段文字最多顯示三行，游標附近一定看得到
    func updateClip(text: String, cursor: Int?, composing: String, style: KeyboardStyle) {
        UIView.performWithoutAnimation {
            isClip = true
            name.numberOfLines = 3
            name.lineBreakMode = .byTruncatingHead
            name.font = .rounded(15, .regular)
            name.accessibilityLabel = "剪貼簿內容，用下方鍵盤修改"
            title.text = "編輯剪貼簿 · 按住空白鍵左右滑移動游標"
            let chars = Array(text)
            let c = max(0, min(chars.count, cursor ?? chars.count))
            // 太長時只留游標前面 80 個字，後面 40 個字
            let before = String(chars[max(0, c - 80)..<c])
            let after = String(chars[c..<min(chars.count, c + 40)])
            let mid = composing.isEmpty ? "▏" : "［" + composing + "］"
            name.text = (c > 80 ? "…" : "") + before + mid + after + (chars.count - c > 40 ? "…" : "")
            name.accessibilityValue = text.isEmpty ? "空白" : text
            save.setTitle("儲存", for: .normal)
            applyColors(style, empty: false)
            setNeedsLayout()
        }
    }

    private func applyColors(_ style: KeyboardStyle, empty: Bool) {
        let theme = style.theme
        backgroundColor = theme.key
        layer.borderColor = theme.accent.withAlphaComponent(0.5).cgColor
        title.textColor = theme.keyText.withAlphaComponent(0.7)
        name.textColor = theme.keyText.withAlphaComponent(empty ? 0.5 : 1)
        cancel.tintColor = theme.keyText
        save.tintColor = theme.isDark ? theme.accent : theme.specialText
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if isClip {
            // 標題和按鈕在上面一排，下面整個寬度放文字
            title.frame = CGRect(x: 12, y: 4, width: max(0, bounds.width - 136), height: 36)
            title.numberOfLines = 2
            cancel.frame = CGRect(x: bounds.width - 112, y: 0, width: 52, height: 40)
            save.frame = CGRect(x: bounds.width - 60, y: 0, width: 52, height: 40)
            name.frame = CGRect(x: 12, y: 40, width: bounds.width - 24, height: max(0, bounds.height - 46))
            return
        }
        title.numberOfLines = 1
        title.frame = CGRect(x: 12, y: 5, width: bounds.width - 24, height: 22)
        name.frame = CGRect(x: 12, y: 27, width: max(0, bounds.width - 130), height: 44)
        cancel.frame = CGRect(x: bounds.width - 112, y: 27, width: 52, height: 44)
        save.frame = CGRect(x: bounds.width - 60, y: 27, width: 52, height: 44)
    }
}
