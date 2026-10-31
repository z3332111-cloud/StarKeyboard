import UIKit

/// A small naming card fed by our existing composition engine, so a keyboard
/// extension never has to summon a second keyboard over its own text field.
/// 也拿來改剪貼簿：變成三行高的小對話框，顯示整段文字和游標。
final class FolderNameBox: UIView {
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?
    /// 改剪貼簿時點了文字：回傳要把游標放在第幾個字後面
    var onTapIndex: ((Int) -> Void)?
    private let title = UILabel()
    private let name = UILabel()
    private let cancel = UIButton(type: .system)
    private let save = UIButton(type: .system)
    private var isClip = false
    /// 畫面上的字對回原文：第一個字是原文第幾個、前面有沒有「…」、游標前有幾個字、游標記號佔幾個字
    private var tapMap: (start: Int, prefix: Int, caret: Int, mid: Int)?

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
        name.isUserInteractionEnabled = true
        name.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tappedText(_:))))
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

    /// 搜尋剪貼簿：一行關鍵字，找到的列在下面的候選列
    func updateSearch(text: String, composing: String, style: KeyboardStyle) {
        UIView.performWithoutAnimation {
            isClip = false
            name.numberOfLines = 1
            name.lineBreakMode = .byTruncatingHead
            name.font = .rounded(16, .semibold)
            name.accessibilityLabel = "搜尋剪貼簿，用下方鍵盤輸入關鍵字"
            title.text = "🔍 搜尋剪貼簿 · 找到的會列在下面，點一下貼上"
            let shown = text + (composing.isEmpty ? "" : "［" + composing + "］")
            name.text = shown.isEmpty ? "打關鍵字，例如：地址、會議 ▏" : shown + "▏"
            name.accessibilityValue = text.isEmpty ? "尚未輸入" : text
            save.setTitle("完成", for: .normal)
            applyColors(style, empty: shown.isEmpty)
            setNeedsLayout()
        }
    }

    /// 改剪貼簿：整段文字最多顯示三行，游標附近一定看得到
    func updateClip(text: String, cursor: Int?, composing: String, style: KeyboardStyle) {
        UIView.performWithoutAnimation {
            isClip = true
            name.numberOfLines = 3
            name.lineBreakMode = .byCharWrapping
            name.font = .rounded(15, .regular)
            name.accessibilityLabel = "剪貼簿內容，用下方鍵盤修改"
            title.text = "編輯剪貼簿 · 點文字或按住空白鍵滑動，移動游標"
            let chars = Array(text)
            let c = max(0, min(chars.count, cursor ?? chars.count))
            // 太長時只留游標前面 44 個字，後面 26 個字（三行放得下）
            let start = max(0, c - 44)
            let before = String(chars[start..<c])
            let after = String(chars[c..<min(chars.count, c + 26)])
            let mid = composing.isEmpty ? "▏" : "［" + composing + "］"
            let prefix = start > 0 ? "…" : ""
            name.text = prefix + before + mid + after + (chars.count - c > 26 ? "…" : "")
            tapMap = (start, prefix.count, before.count, mid.count)
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

    /// 點在文字上：算出點到第幾個字，換回原文的位置
    @objc private func tappedText(_ g: UITapGestureRecognizer) {
        guard isClip, let map = tapMap, let text = name.text, let font = name.font else { return }
        let storage = NSTextStorage(string: text, attributes: [.font: font])
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: name.bounds.width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byCharWrapping
        layout.addTextContainer(container)
        let used = layout.usedRect(for: container)
        let p = g.location(in: name)
        let point = CGPoint(x: p.x, y: p.y - max(0, (name.bounds.height - used.height) / 2))
        var fraction: CGFloat = 0
        let i16 = layout.characterIndex(for: point, in: container, fractionOfDistanceBetweenInsertionPoints: &fraction)
        let end = min(text.utf16.count, i16 + (fraction > 0.5 ? 1 : 0))
        let shown = String(text.utf16.prefix(end))?.count ?? 0
        let d = shown - map.prefix
        let index = d <= map.caret ? map.start + max(0, d) : map.start + d - map.mid
        onTapIndex?(max(0, index))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if isClip {
            // 標題和按鈕在上面一排，下面整個寬度放文字
            title.frame = CGRect(x: 12, y: 4, width: max(0, bounds.width - 136), height: 36)
            title.numberOfLines = 2
            cancel.frame = CGRect(x: bounds.width - 112, y: 0, width: 52, height: 40)
            save.frame = CGRect(x: bounds.width - 60, y: 0, width: 52, height: 40)
            let w = bounds.width - 24
            let fit = name.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height
            name.frame = CGRect(x: 12, y: 40, width: w, height: max(0, min(bounds.height - 46, fit)))
            return
        }
        title.numberOfLines = 1
        title.frame = CGRect(x: 12, y: 5, width: bounds.width - 24, height: 22)
        name.frame = CGRect(x: 12, y: 27, width: max(0, bounds.width - 130), height: 44)
        cancel.frame = CGRect(x: bounds.width - 112, y: 27, width: 52, height: 44)
        save.frame = CGRect(x: bounds.width - 60, y: 27, width: 52, height: 44)
    }
}
