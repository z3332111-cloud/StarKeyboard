import UIKit

enum ToolbarItem: CaseIterable {
    case clipboard, emoji, kaomoji, symbols, fancy, translate, handwriting, voice, settings, dismiss
}

/// 鍵盤最上面那一條：沒在打字時是工具列，打注音時是候選字，新增表符或翻譯時是編輯框
final class TopBarView: UIView {
    enum Trailing { case expand, close }

    enum Content {
        case toolbar
        case candidates(composition: String, items: [String], trailing: Trailing)
        // source：翻譯時的「原文語言」按鈕（其他編輯框不用就是 nil）
        case editor(prompt: String, text: String, extra: String, confirm: String, source: String? = nil)
    }

    var onScriptToggle: (() -> Void)?
    var scriptTitle: String? {
        didSet {
            scriptButton.setTitle(scriptTitle, for: .normal)
            scriptButton.accessibilityLabel = scriptTitle == "繁" ? "目前繁體，點一下切換簡體" : "目前簡體，點一下切換繁體"
        }
    }
    private let scriptButton = UIButton(type: .system)
    var onToolbar: ((ToolbarItem) -> Void)?
    var onCandidate: ((Int) -> Void)?
    var onTrailing: ((Trailing) -> Void)?
    var onEditor: ((Bool) -> Void)?
    var onEditorExtra: (() -> Void)?
    var onEditorSource: (() -> Void)?
    var style: KeyboardStyle {
        didSet { applyStyle() }
    }

    private var content: Content = .toolbar
    private var hasSource = false
    private var trailing: Trailing = .expand
    private let toolbar = UIStackView()
    private var toolbarButtons: [UIButton] = []
    private let compositionScroll = UIScrollView()
    private let compositionLabel = UILabel()
    private var scrollCompositionToEnd = false
    private let candidateScroll = UIScrollView()
    private var candidateButtons: [UIButton] = []
    private let trailingButton = UIButton(type: .system)
    private let editorLabel = UILabel()
    private let editorSave = UIButton(type: .system)
    private let editorCancel = UIButton(type: .system)
    private let editorExtra = UIButton(type: .system)
    private let editorSource = UIButton(type: .system)
    private let separator = UIView()

    init(style: KeyboardStyle) {
        self.style = style
        super.init(frame: .zero)

        toolbar.axis = .horizontal
        toolbar.distribution = .fillEqually
        for item in ToolbarItem.allCases {
            let b = UIButton(type: .system)
            switch item {
            case .clipboard: b.setImage(Self.icon("doc.on.clipboard"), for: .normal)
            case .emoji: b.setImage(Self.icon("face.smiling"), for: .normal)
            case .kaomoji: b.setTitle("(•ᴗ•)", for: .normal)
            case .symbols: b.setTitle("※", for: .normal)
            case .fancy: b.setTitle("𝒜", for: .normal)
            case .translate: b.setImage(Self.icon("translate"), for: .normal)
            case .handwriting: b.setImage(Self.icon("hand.draw"), for: .normal)
            case .voice: b.setImage(Self.icon("mic"), for: .normal); b.accessibilityLabel = "語音輸入說明"
            case .settings: b.setImage(Self.icon("gearshape"), for: .normal)
            case .dismiss: b.setImage(Self.icon("keyboard.chevron.compact.down"), for: .normal)
            }
            b.titleLabel?.font = .rounded(15, .semibold)
            b.addAction(UIAction { [weak self] _ in self?.onToolbar?(item) }, for: .touchUpInside)
            toolbar.addArrangedSubview(b)
            toolbarButtons.append(b)
        }
        addSubview(toolbar)
        scriptButton.titleLabel?.font = .rounded(15, .bold)
        scriptButton.addAction(UIAction { [weak self] _ in self?.onScriptToggle?() }, for: .touchUpInside)
        addSubview(scriptButton)

        compositionLabel.font = .rounded(15, .bold)
        compositionScroll.showsHorizontalScrollIndicator = false
        compositionScroll.addSubview(compositionLabel)
        addSubview(compositionScroll)
        candidateScroll.showsHorizontalScrollIndicator = false
        candidateScroll.alwaysBounceHorizontal = true
        addSubview(candidateScroll)
        trailingButton.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            self.onTrailing?(self.trailing)
        }, for: .touchUpInside)
        addSubview(trailingButton)

        editorLabel.font = .rounded(17)
        editorLabel.lineBreakMode = .byTruncatingHead
        addSubview(editorLabel)
        editorCancel.setTitle("取消", for: .normal)
        editorSave.setTitle("儲存", for: .normal)
        editorCancel.titleLabel?.font = .rounded(16)
        editorSave.titleLabel?.font = .rounded(16, .bold)
        editorCancel.addAction(UIAction { [weak self] _ in self?.onEditor?(false) }, for: .touchUpInside)
        editorSave.addAction(UIAction { [weak self] _ in self?.onEditor?(true) }, for: .touchUpInside)
        editorExtra.setTitle("(•ᴗ•)", for: .normal)
        editorExtra.titleLabel?.font = .rounded(14, .semibold)
        editorExtra.titleLabel?.adjustsFontSizeToFitWidth = true
        editorExtra.titleLabel?.minimumScaleFactor = 0.6
        editorExtra.addAction(UIAction { [weak self] _ in self?.onEditorExtra?() }, for: .touchUpInside)
        addSubview(editorExtra)
        editorSource.titleLabel?.font = .rounded(14, .semibold)
        editorSource.titleLabel?.adjustsFontSizeToFitWidth = true
        editorSource.titleLabel?.minimumScaleFactor = 0.6
        editorSource.addAction(UIAction { [weak self] _ in self?.onEditorSource?() }, for: .touchUpInside)
        addSubview(editorSource)
        addSubview(editorCancel)
        addSubview(editorSave)

        addSubview(separator)
        applyStyle()
        show(.toolbar)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func icon(_ name: String) -> UIImage? {
        UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
    }

    func show(_ newContent: Content) {
        // 同一次更新完成文字與版面，避免快速輸入時按鈕標題淡出再出現。
        UIView.performWithoutAnimation {
            applyContent(newContent)
            layoutIfNeeded()
        }
    }

    private func applyContent(_ newContent: Content) {
        content = newContent
        var isToolbar = false, isCandidates = false, isEditor = false
        switch newContent {
        case .toolbar:
            isToolbar = true
        case let .candidates(composition, items, trailing):
            isCandidates = true
            if compositionLabel.text != composition {
                compositionLabel.text = composition
                scrollCompositionToEnd = true
            }
            self.trailing = trailing
            trailingButton.setImage(Self.icon(trailing == .expand ? "chevron.down" : "xmark"), for: .normal)
            trailingButton.isHidden = items.isEmpty && trailing == .expand
            rebuildCandidates(Array(items.prefix(40)))
        case let .editor(prompt, text, extra, confirm, source):
            isEditor = true
            editorSource.setTitle(source, for: .normal)
            hasSource = source != nil
            editorLabel.text = prompt + text + "▏"
            editorExtra.setTitle(extra, for: .normal)
            editorSave.setTitle(confirm, for: .normal)
        }
        // 整條（工具列、選字區、編輯框）都墊一層半透明的底，放背景照片時圖示和字才看得清楚（深色主題墊深色）
        backgroundColor = (style.theme.isDark ? UIColor.black.withAlphaComponent(0.35) : UIColor.white.withAlphaComponent(0.6))
        scriptButton.isHidden = scriptTitle == nil || isEditor
        toolbar.isHidden = !isToolbar
        compositionScroll.isHidden = !isCandidates || (compositionLabel.text ?? "").isEmpty
        candidateScroll.isHidden = !isCandidates
        trailingButton.isHidden = trailingButton.isHidden || !isCandidates
        editorLabel.isHidden = !isEditor
        editorSave.isHidden = !isEditor
        editorCancel.isHidden = !isEditor
        editorExtra.isHidden = !isEditor
        editorSource.isHidden = !isEditor || !hasSource
        setNeedsLayout()
    }

    private func rebuildCandidates(_ items: [String]) {
        let changed = candidateButtons.map { $0.title(for: .normal) ?? "" } != items
        while candidateButtons.count > items.count {
            candidateButtons.removeLast().removeFromSuperview()
        }
        while candidateButtons.count < items.count {
            let i = candidateButtons.count
            // system 按鈕換標題會有轉場；候選字改用 custom，直接顯示新文字。
            let b = UIButton(type: .custom)
            b.tag = i
            b.addAction(UIAction { [weak self] _ in self?.onCandidate?(i) }, for: .touchUpInside)
            candidateScroll.addSubview(b)
            candidateButtons.append(b)
        }
        // Reuse existing buttons while typing instead of allocating up to 40 per refresh.
        for (i, text) in items.enumerated() {
            let b = candidateButtons[i]
            if b.title(for: .normal) != text { b.setTitle(text, for: .normal) }
            // 字加粗；第一個（按空白會送出的）放在主題色的膠囊裡，一眼就看得到
            b.titleLabel?.font = KeyFonts.font(style.fontID, size: 24, weight: i == 0 ? .heavy : .semibold)
            if i == 0 {
                b.backgroundColor = style.theme.accent
                b.setTitleColor(style.theme.accentText, for: .normal)
                b.layer.shadowColor = style.theme.shadow.cgColor
                b.layer.shadowOpacity = 0.6
                b.layer.shadowRadius = 2
                b.layer.shadowOffset = CGSize(width: 0, height: 1.5)
            } else {
                b.setTitleColor(style.theme.keyText, for: .normal)
            }
        }
        if changed { candidateScroll.contentOffset = .zero }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        let scriptW: CGFloat = scriptButton.isHidden ? 0 : 44
        toolbar.frame = CGRect(x: 4, y: 0, width: w - 8 - scriptW, height: h)
        separator.frame = CGRect(x: 0, y: h - 0.5, width: w, height: 0.5)

        let hasComposition = !compositionScroll.isHidden
        let top: CGFloat = hasComposition ? 18 : 0
        compositionScroll.frame = CGRect(x: 12, y: 1, width: max(0, w - 60 - scriptW), height: 17)
        let readingWidth = ceil(compositionLabel.intrinsicContentSize.width)
        compositionLabel.frame = CGRect(x: 0, y: 0, width: max(compositionScroll.bounds.width, readingWidth), height: 17)
        compositionScroll.contentSize = compositionLabel.bounds.size
        let lastOffset = max(0, compositionScroll.contentSize.width - compositionScroll.bounds.width)
        if scrollCompositionToEnd {
            // 新輸入保持最後按的音可見，也能往回滑查看整段未送出的注音。
            compositionScroll.setContentOffset(CGPoint(x: lastOffset, y: 0), animated: false)
            scrollCompositionToEnd = false
        } else if compositionScroll.contentOffset.x > lastOffset && !compositionScroll.isDragging && !compositionScroll.isDecelerating {
            compositionScroll.setContentOffset(CGPoint(x: lastOffset, y: 0), animated: false)
        }
        let trailingW: CGFloat = trailingButton.isHidden ? 0 : 44
        trailingButton.frame = CGRect(x: w - 44, y: 0, width: 44, height: h)
        scriptButton.frame = CGRect(x: w - trailingW - scriptW, y: 0, width: scriptW, height: h)
        candidateScroll.frame = CGRect(x: 0, y: top, width: w - trailingW - scriptW, height: h - top)
        var x: CGFloat = 6
        let ch = candidateScroll.bounds.height
        for (i, b) in candidateButtons.enumerated() {
            let textW = ((b.title(for: .normal) ?? "") as NSString)
                .size(withAttributes: [.font: b.titleLabel?.font ?? UIFont.systemFont(ofSize: 20)]).width
            let bw = max(40, ceil(textW) + 22)
            if i == 0 {
                // 膠囊：上下留一點空，左右也留一點才不會跟下一個字黏在一起
                let pill = CGRect(x: x, y: 4, width: bw, height: max(20, ch - 8))
                b.frame = pill
                b.layer.cornerRadius = pill.height / 2
                // 給陰影現成的形狀，iPhone 才不用每一幀從按鈕內容重算陰影（打字時會卡）
                b.layer.shadowPath = UIBezierPath(roundedRect: b.bounds, cornerRadius: pill.height / 2).cgPath
                x += bw + 4
            } else {
                b.frame = CGRect(x: x, y: 0, width: bw, height: ch)
                x += bw
            }
        }
        candidateScroll.contentSize = CGSize(width: x + 6, height: candidateScroll.bounds.height)

        // 翻譯時多一顆「從：原文語言」，打的字區域變窄一點
        let sourceW: CGFloat = hasSource ? 70 : 0
        editorLabel.frame = CGRect(x: 12, y: 0, width: w - 222 - sourceW, height: h)
        editorSource.frame = CGRect(x: w - 208 - sourceW, y: 0, width: sourceW, height: h)
        editorExtra.frame = CGRect(x: w - 208, y: 0, width: 72, height: h)
        editorCancel.frame = CGRect(x: w - 136, y: 0, width: 64, height: h)
        editorSave.frame = CGRect(x: w - 70, y: 0, width: 64, height: h)
    }

    private func applyStyle() {
        let t = style.theme
        let tint = t.isDark ? t.keyText : t.specialText
        for b in toolbarButtons {
            b.tintColor = tint
            b.setTitleColor(tint, for: .normal)
        }
        compositionLabel.textColor = t.keyText
        scriptButton.tintColor = tint
        trailingButton.tintColor = tint
        editorLabel.textColor = t.keyText
        editorCancel.tintColor = tint
        editorExtra.tintColor = tint
        editorSource.tintColor = tint
        editorSave.tintColor = t.isDark ? t.accent : t.specialText
        separator.backgroundColor = t.shadow.withAlphaComponent(0.4)
        if case .candidates = content { show(content) }
    }
}

/// 面板最下面那條：返回鍵盤、分頁、刪除
final class PanelBottomBar: UIView {
    var onBack: (() -> Void)?
    var onBackspace: (() -> Void)?
    var onTab: ((Int) -> Void)?
    var style: KeyboardStyle {
        didSet { applyStyle() }
    }
    var selectedTab = 0 {
        didSet { applyStyle() }
    }
    var showsBackspace = true {
        didSet { deleteButton.isHidden = !showsBackspace }
    }

    private let backButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private let scroll = UIScrollView()
    private var tabButtons: [UIButton] = []
    private var repeatTimer: Timer?

    init(style: KeyboardStyle, backTitle: String = "ABC") {
        self.style = style
        super.init(frame: .zero)
        backButton.setTitle(backTitle, for: .normal)
        backButton.titleLabel?.font = .rounded(15, .bold)
        backButton.layer.cornerRadius = 8
        backButton.addAction(UIAction { [weak self] _ in self?.onBack?() }, for: .touchUpInside)
        addSubview(backButton)

        deleteButton.setImage(UIImage(systemName: "delete.left"), for: .normal)
        deleteButton.layer.cornerRadius = 8
        deleteButton.addAction(UIAction { [weak self] _ in self?.startDeleting() }, for: .touchDown)
        for event: UIControl.Event in [.touchUpInside, .touchUpOutside, .touchCancel] {
            deleteButton.addAction(UIAction { [weak self] _ in self?.stopDeleting() }, for: event)
        }
        addSubview(deleteButton)

        scroll.showsHorizontalScrollIndicator = false
        addSubview(scroll)
        applyStyle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setTabs(_ titles: [String]) {
        tabButtons.forEach { $0.removeFromSuperview() }
        tabButtons = titles.enumerated().map { (i, title) in
            let b = UIButton(type: .system)
            b.setTitle(title, for: .normal)
            b.titleLabel?.font = .rounded(title.count <= 2 ? 19 : 14, .semibold)
            b.layer.cornerRadius = 8
            b.addAction(UIAction { [weak self] _ in
                self?.selectedTab = i
                self?.onTab?(i)
            }, for: .touchUpInside)
            scroll.addSubview(b)
            return b
        }
        applyStyle()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = bounds.height
        backButton.frame = CGRect(x: 4, y: 3, width: 56, height: h - 6)
        deleteButton.frame = CGRect(x: bounds.width - 56, y: 3, width: 52, height: h - 6)
        let right = showsBackspace ? deleteButton.frame.minX - 4 : bounds.width - 4
        scroll.frame = CGRect(x: 64, y: 0, width: right - 64, height: h)
        var x: CGFloat = 0
        for b in tabButtons {
            let title = b.title(for: .normal) ?? ""
            let w = max(40, (title as NSString).size(withAttributes: [.font: b.titleLabel?.font ?? UIFont.systemFont(ofSize: 15)]).width + 20)
            b.frame = CGRect(x: x, y: 3, width: w, height: h - 6)
            x += w + 2
        }
        scroll.contentSize = CGSize(width: x, height: h)
    }

    private func applyStyle() {
        let t = style.theme
        backButton.backgroundColor = t.specialKey.withAlphaComponent(style.keyAlpha)
        backButton.setTitleColor(t.specialText, for: .normal)
        deleteButton.backgroundColor = t.specialKey.withAlphaComponent(style.keyAlpha)
        deleteButton.tintColor = t.specialText
        for (i, b) in tabButtons.enumerated() {
            let selected = i == selectedTab
            b.backgroundColor = selected ? t.key.withAlphaComponent(style.keyAlpha) : .clear
            b.setTitleColor(selected ? t.keyText : t.keyText.withAlphaComponent(0.6), for: .normal)
        }
    }

    private func startDeleting() {
        onBackspace?()
        repeatTimer?.invalidate()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                self?.onBackspace?()
            }
        }
    }

    private func stopDeleting() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }
}

/// 可以捲動的方塊格子（表情符號、顏文字、候選字都用這個）
final class ChipGridView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    enum Item {
        case text(String)
        case image(UIImage)
        case add
    }

    enum CellStyle { case square, chip }

    var items: [Item] = [] {
        didSet { collectionView.reloadData() }
    }
    var cellStyle: CellStyle = .square {
        didSet { collectionView.collectionViewLayout.invalidateLayout() }
    }
    var isEditingItems = false {
        didSet { collectionView.reloadData() }
    }
    var canDelete: (Int) -> Bool = { _ in false }
    var onSelect: ((Int) -> Void)?
    var onDelete: ((Int) -> Void)?
    var onLongPress: ((Int) -> Void)?
    var style: KeyboardStyle {
        didSet { collectionView.reloadData() }
    }

    private let collectionView: UICollectionView

    init(style: KeyboardStyle) {
        self.style = style
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 6
        layout.minimumLineSpacing = 6
        layout.sectionInset = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: .zero)
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.register(ChipCell.self, forCellWithReuseIdentifier: "chip")
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
        collectionView.addGestureRecognizer(lp)
        addSubview(collectionView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if collectionView.frame != bounds {
            collectionView.frame = bounds
            collectionView.collectionViewLayout.invalidateLayout()
        }
    }

    func scrollToTop() {
        collectionView.setContentOffset(.zero, animated: false)
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "chip", for: indexPath) as! ChipCell
        let i = indexPath.item
        cell.configure(items[i], cellStyle: cellStyle, style: style, showDelete: isEditingItems && canDelete(i))
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        let i = indexPath.item
        if isEditingItems && canDelete(i) {
            onDelete?(i)
        } else {
            onSelect?(i)
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        switch items[indexPath.item] {
        case .image:
            return CGSize(width: 70, height: 70)
        case .add:
            return cellStyle == .square ? CGSize(width: 42, height: 42) : CGSize(width: 64, height: 40)
        case .text(let s):
            if cellStyle == .square { return CGSize(width: 42, height: 42) }
            let w = (s as NSString).size(withAttributes: [.font: ChipCell.chipFont]).width
            return CGSize(width: min(max(44, ceil(w) + 24), max(44, collectionView.bounds.width - 16)), height: 40)
        }
    }

    @objc private func longPressed(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, let ip = collectionView.indexPathForItem(at: g.location(in: collectionView)) else { return }
        onLongPress?(ip.item)
    }
}

final class ChipCell: UICollectionViewCell {
    static let chipFont = UIFont.systemFont(ofSize: 17)

    private let label = UILabel()
    private let imageView = UIImageView()
    private let badge = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 10
        contentView.clipsToBounds = true
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        contentView.addSubview(label)
        imageView.contentMode = .scaleAspectFit
        contentView.addSubview(imageView)
        badge.text = "✕"
        badge.font = .systemFont(ofSize: 11, weight: .bold)
        badge.textColor = .white
        badge.textAlignment = .center
        badge.backgroundColor = UIColor(hex: 0xFF5A6E)
        badge.layer.cornerRadius = 9
        badge.clipsToBounds = true
        addSubview(badge)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ item: ChipGridView.Item, cellStyle: ChipGridView.CellStyle, style: KeyboardStyle, showDelete: Bool) {
        let t = style.theme
        label.textColor = t.keyText
        label.isHidden = false
        imageView.isHidden = true
        switch item {
        case .text(let s):
            label.text = s
            label.font = cellStyle == .square ? .systemFont(ofSize: 28) : Self.chipFont
            contentView.backgroundColor = cellStyle == .square ? .clear : t.key.withAlphaComponent(style.keyAlpha * 0.9)
        case .image(let img):
            label.isHidden = true
            imageView.isHidden = false
            imageView.image = img
            contentView.backgroundColor = t.key.withAlphaComponent(style.keyAlpha * 0.6)
        case .add:
            label.text = "＋"
            label.font = .rounded(22, .bold)
            label.textColor = t.specialText
            contentView.backgroundColor = t.specialKey.withAlphaComponent(style.keyAlpha)
        }
        badge.isHidden = !showDelete
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds.insetBy(dx: 4, dy: 0)
        imageView.frame = contentView.bounds.insetBy(dx: 4, dy: 4)
        badge.frame = CGRect(x: bounds.width - 16, y: -2, width: 18, height: 18)
    }

    override var isHighlighted: Bool {
        didSet { contentView.alpha = isHighlighted ? 0.5 : 1 }
    }
}
