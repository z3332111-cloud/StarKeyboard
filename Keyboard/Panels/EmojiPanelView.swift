import UIKit

/// 表情符號、顏文字、特殊符號共用的面板（含「我的表符」和自製貼圖）
final class EmojiPanelView: UIView {
    enum Kind: String {
        case emoji, kaomoji, symbols
    }

    enum AddOption { case type, clipboardText, clipboardImage }

    private enum TabContent {
        case recent
        case mine
        case list([String])
    }

    private enum ItemRef {
        case text(String)
        case custom(String)
        case sticker(StickerRef)
        case add
    }

    var onInsert: ((String) -> Void)?
    var onCopyImage: ((UIImage) -> Void)?
    var onAdd: ((AddOption) -> Void)?
    var onBack: (() -> Void)?
    var onBackspace: (() -> Void)?
    var style: KeyboardStyle {
        didSet {
            grid.style = style
            bar.style = style
            styleAddMenu()
        }
    }

    let kind: Kind
    private let store: EmoticonStore
    private let grid: ChipGridView
    private let bar: PanelBottomBar
    private var tabs: [(title: String, content: TabContent)] = []
    private var refs: [ItemRef] = []
    private var current = 0
    private var imageCache: [UUID: UIImage] = [:]
    private let addMenu = UIView()
    private let addStack = UIStackView()

    init(kind: Kind, store: EmoticonStore, style: KeyboardStyle) {
        self.kind = kind
        self.store = store
        self.style = style
        grid = ChipGridView(style: style)
        bar = PanelBottomBar(style: style)
        super.init(frame: .zero)

        let categories: [SymbolCategory]
        switch kind {
        case .emoji:
            tabs = [(title: "🕘", content: TabContent.recent), (title: "⭐", content: TabContent.mine)]
            categories = SymbolData.emoji
        case .kaomoji:
            tabs = [(title: "最近", content: TabContent.recent), (title: "我的", content: TabContent.mine)]
            categories = SymbolData.kaomoji
        case .symbols:
            tabs = [(title: "最近", content: TabContent.recent)]
            categories = SymbolData.symbols
        }
        for cat in categories {
            tabs.append((title: cat.title, content: TabContent.list(cat.items)))
        }

        addSubview(grid)
        addSubview(bar)
        bar.setTabs(tabs.map { $0.title })
        bar.onTab = { [weak self] i in self?.select(tab: i) }
        bar.onBack = { [weak self] in self?.onBack?() }
        bar.onBackspace = { [weak self] in self?.onBackspace?() }

        grid.onSelect = { [weak self] i in self?.tapped(i) }
        grid.canDelete = { [weak self] i in
            guard let self = self, i < self.refs.count else { return false }
            switch self.refs[i] {
            case .custom, .sticker: return true
            default: return false
            }
        }
        grid.onDelete = { [weak self] i in self?.delete(i) }
        grid.onLongPress = { [weak self] _ in
            guard let self = self, case .mine = self.tabs[self.current].content else { return }
            self.grid.isEditingItems.toggle()
        }

        buildAddMenu()
        let hasRecent = !store.recents(kind.rawValue).isEmpty
        select(tab: hasRecent ? 0 : (kind == .symbols ? 1 : 2))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let barH: CGFloat = 40
        grid.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - barH)
        bar.frame = CGRect(x: 0, y: bounds.height - barH, width: bounds.width, height: barH)
        addMenu.frame = bounds
        addStack.frame = CGRect(x: 24, y: 10, width: bounds.width - 48, height: bounds.height - 20)
    }

    func reload() {
        select(tab: current)
    }

    private func select(tab i: Int) {
        current = i
        bar.selectedTab = i
        grid.isEditingItems = false
        switch tabs[i].content {
        case .recent:
            refs = store.recents(kind.rawValue).map { .text($0) }
            grid.cellStyle = kind == .kaomoji ? .chip : .square
        case .mine:
            refs = [.add] + store.custom.map { .custom($0) } + store.stickers.map { .sticker($0) }
            grid.cellStyle = .chip
        case .list(let items):
            refs = items.map { .text($0) }
            grid.cellStyle = kind == .kaomoji ? .chip : .square
        }
        var items: [ChipGridView.Item] = []
        var kept: [ItemRef] = []
        for ref in refs {
            switch ref {
            case .text(let s), .custom(let s):
                items.append(.text(s))
                kept.append(ref)
            case .sticker(let r):
                if let img = image(for: r) {
                    items.append(.image(img))
                    kept.append(ref)
                }
            case .add:
                items.append(.add)
                kept.append(ref)
            }
        }
        refs = kept
        grid.items = items
        grid.scrollToTop()
    }

    private func image(for ref: StickerRef) -> UIImage? {
        if let img = imageCache[ref.id] { return img }
        guard let url = store.stickerURL(ref), let img = UIImage(contentsOfFile: url.path) else { return nil }
        imageCache[ref.id] = img
        return img
    }

    private func tapped(_ i: Int) {
        guard i < refs.count else { return }
        switch refs[i] {
        case .text(let s), .custom(let s):
            onInsert?(s)
            store.pushRecent(s, kind: kind.rawValue)
        case .sticker(let r):
            if let img = image(for: r) { onCopyImage?(img) }
        case .add:
            addMenu.isHidden = false
        }
    }

    private func delete(_ i: Int) {
        guard i < refs.count else { return }
        switch refs[i] {
        case .custom(let s): store.removeCustom(s)
        case .sticker(let r):
            store.removeSticker(r)
            imageCache[r.id] = nil
        default: return
        }
        let editing = grid.isEditingItems
        select(tab: current)
        grid.isEditingItems = editing
    }

    // MARK: 新增選單

    private func buildAddMenu() {
        addMenu.isHidden = true
        addStack.axis = .vertical
        addStack.spacing = 6
        addStack.distribution = .fillEqually
        let options: [(String, AddOption?)] = [
            ("⌨️  用鍵盤打一個新的表符", .type),
            ("📋  把剪貼簿的文字加進來", .clipboardText),
            ("🖼  把剪貼簿的圖片做成貼圖", .clipboardImage),
            ("取消", nil),
        ]
        for (title, option) in options {
            let b = UIButton(type: .system)
            b.setTitle(title, for: .normal)
            b.titleLabel?.font = .rounded(16, option == nil ? .regular : .semibold)
            b.layer.cornerRadius = 12
            b.addAction(UIAction { [weak self] _ in
                self?.addMenu.isHidden = true
                if let option = option { self?.onAdd?(option) }
            }, for: .touchUpInside)
            addStack.addArrangedSubview(b)
        }
        addMenu.addSubview(addStack)
        addSubview(addMenu)
        styleAddMenu()
    }

    private func styleAddMenu() {
        let t = style.theme
        addMenu.backgroundColor = t.backgroundTop.withAlphaComponent(0.92)
        for case let b as UIButton in addStack.arrangedSubviews {
            b.backgroundColor = t.key
            b.setTitleColor(t.keyText, for: .normal)
        }
    }
}

/// 展開的候選字（全部列出來）
final class CandidatePanelView: UIView {
    var onSelect: ((Int) -> Void)?
    var onBack: (() -> Void)?
    var onBackspace: (() -> Void)?
    var style: KeyboardStyle {
        didSet {
            grid.style = style
            bar.style = style
            backgroundColor = style.theme.backgroundBottom.withAlphaComponent(1)
        }
    }

    private let grid: ChipGridView
    private let bar: PanelBottomBar
    private var displayedCandidates: [String] = []

    init(style: KeyboardStyle) {
        self.style = style
        grid = ChipGridView(style: style)
        bar = PanelBottomBar(style: style, backTitle: "▲")
        super.init(frame: .zero)
        backgroundColor = style.theme.backgroundBottom.withAlphaComponent(1)
        grid.cellStyle = .chip
        grid.onSelect = { [weak self] i in self?.onSelect?(i) }
        bar.onBack = { [weak self] in self?.onBack?() }
        bar.onBackspace = { [weak self] in self?.onBackspace?() }
        addSubview(grid)
        addSubview(bar)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setCandidates(_ texts: [String]) {
        guard texts != displayedCandidates else { return }
        displayedCandidates = texts
        grid.items = texts.map { .text($0) }
        grid.scrollToTop()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let barH: CGFloat = 40
        grid.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - barH)
        bar.frame = CGRect(x: 0, y: bounds.height - barH, width: bounds.width, height: barH)
    }
}
