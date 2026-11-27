import UIKit

/// 表情符號、顏文字、特殊符號共用的面板（含「我的表符」）；自製貼圖是獨立的一個（kind = .stickers）
final class EmojiPanelView: UIView {
    enum Kind: String {
        case emoji, kaomoji, symbols, stickers
    }

    enum AddOption { case type, clipboardText, clipboardImage, clipboardImageCutout }

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
    /// 點了貼圖：交出貼圖的檔案，照設定的大小複製
    var onCopySticker: ((URL) -> Void)?
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
            tabs = [(title: "最近", content: TabContent.recent), (title: "我的", content: TabContent.mine)]
            categories = SymbolData.symbols
        case .stickers:
            tabs = [(title: "🖼 我的貼圖", content: TabContent.mine)]
            categories = []
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
        select(tab: kind == .stickers ? 0 : (hasRecent ? 0 : 2))
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
            switch kind {
            case .symbols:
                refs = [.add] + store.customSymbols.map { .custom($0) }
                grid.cellStyle = .square
            case .stickers:
                refs = [.add] + store.stickers.map { .sticker($0) }
                grid.cellStyle = .square
            default:
                // 貼圖搬到獨立的「我的貼圖」，這裡只放自己的表符
                refs = [.add] + store.custom.map { .custom($0) }
                grid.cellStyle = .chip
            }
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
        // 貼圖只顯示成小格子：讀成小圖，太多張時先清掉（整張 512 的貼圖一張就 1MB）
        guard let url = store.stickerURL(ref), let img = UIImage.downsampled(url: url, maxSide: 180) else { return nil }
        if imageCache.count >= 80 { imageCache.removeAll() }
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
            if let url = store.stickerURL(r) { onCopySticker?(url) }
        case .add:
            addMenu.isHidden = false
        }
    }

    private func delete(_ i: Int) {
        guard i < refs.count else { return }
        switch refs[i] {
        case .custom(let s): if kind == .symbols { store.removeSymbol(s) } else { store.removeCustom(s) }
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
        let options: [(String, AddOption?)]
        switch kind {
        case .symbols:
            options = [
                ("⌨️  用鍵盤打新的符號（空白隔開可以加好幾個）", .type),
                ("📋  把剪貼簿的文字加進來", .clipboardText),
                ("取消", nil),
            ]
        case .stickers:
            options = [
                ("🖼  貼上剛複製的圖片", .clipboardImage),
                ("✂️  貼上並去掉純色背景（白底、黑底）", .clipboardImageCutout),
                ("取消", nil),
            ]
        default:
            options = [
                ("⌨️  用鍵盤打一個新的表符", .type),
                ("📋  把剪貼簿的文字加進來", .clipboardText),
                ("取消", nil),
            ]
        }
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
        if kind == .stickers {
            // 貼出去的大小：小是以前的大小，中、大比較清楚
            let size = UISegmentedControl(items: StickerTools.sizes.map { "貼出去：\($0.title)" })
            size.selectedSegmentIndex = KeyboardSettings.shared.stickerSize
            size.addAction(UIAction { [weak size] _ in
                guard let size = size else { return }
                KeyboardSettings.shared.stickerSize = size.selectedSegmentIndex
            }, for: .valueChanged)
            addStack.insertArrangedSubview(size, at: addStack.arrangedSubviews.count - 1)
            // Discord 會把貼上的 PNG 壓成白底，選 GIF 就能保留透明背景
            let format = UISegmentedControl(items: ["PNG（一般）", "GIF（DC 透明背景）"])
            format.selectedSegmentIndex = KeyboardSettings.shared.stickerGif ? 1 : 0
            format.addAction(UIAction { [weak format] _ in
                guard let format = format else { return }
                KeyboardSettings.shared.stickerGif = format.selectedSegmentIndex == 1
            }, for: .valueChanged)
            addStack.insertArrangedSubview(format, at: addStack.arrangedSubviews.count - 1)
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
    /// 查一個字的部首；有的話上面會出現一排部首可以篩選
    var radicalOf: ((Character) -> String?)?
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
    // 部首篩選：上面一排部首，點了只留那個部首的單字
    private let radicalScroll = UIScrollView()
    private var radicalFilter: String?
    private var shownIndex: [Int] = []

    init(style: KeyboardStyle) {
        self.style = style
        grid = ChipGridView(style: style)
        bar = PanelBottomBar(style: style, backTitle: "▲")
        super.init(frame: .zero)
        backgroundColor = style.theme.backgroundBottom.withAlphaComponent(1)
        grid.cellStyle = .chip
        grid.onSelect = { [weak self] i in
            guard let self = self, i < self.shownIndex.count else { return }
            self.onSelect?(self.shownIndex[i])
        }
        bar.onBack = { [weak self] in self?.onBack?() }
        bar.onBackspace = { [weak self] in self?.onBackspace?() }
        radicalScroll.showsHorizontalScrollIndicator = false
        addSubview(radicalScroll)
        addSubview(grid)
        addSubview(bar)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setCandidates(_ texts: [String]) {
        guard texts != displayedCandidates else { return }
        displayedCandidates = texts
        radicalFilter = nil
        applyFilter()
    }

    /// 候選裡單字的部首，出現越多次的排越前面
    private var radicalList: [String] {
        guard let of = radicalOf else { return [] }
        var count: [String: Int] = [:]
        var order: [String] = []
        for t in displayedCandidates where t.count == 1 {
            guard let r = of(t.first!) else { continue }
            if count[r] == nil { order.append(r) }
            count[r, default: 0] += 1
        }
        return order.sorted { count[$0]! > count[$1]! }
    }

    private func applyFilter() {
        shownIndex = displayedCandidates.indices.filter { i in
            guard let f = radicalFilter else { return true }
            let t = displayedCandidates[i]
            return t.count == 1 && radicalOf?(t.first!) == f
        }
        grid.items = shownIndex.map { .text(displayedCandidates[$0]) }
        grid.scrollToTop()
        buildRadicalRow()
        setNeedsLayout()
    }

    private func buildRadicalRow() {
        radicalScroll.subviews.forEach { $0.removeFromSuperview() }
        let list = radicalList
        radicalScroll.isHidden = list.count < 2
        guard list.count >= 2 else { return }
        var x: CGFloat = 8
        for (title, value) in [("全部", nil as String?)] + list.map { ("部首 " + $0, Optional($0)) } {
            let b = UIButton(type: .custom)
            let on = radicalFilter == value
            b.setTitle(value == nil ? title : value!, for: .normal)
            b.titleLabel?.font = KeyFonts.font(style.fontID, size: value == nil ? 14 : 17, weight: on ? .bold : .regular)
            b.setTitleColor(on ? style.theme.accentText : style.theme.keyText, for: .normal)
            b.backgroundColor = on ? style.theme.accent : style.theme.key.withAlphaComponent(0.7)
            b.layer.cornerRadius = 12
            let w: CGFloat = value == nil ? 52 : 40
            b.frame = CGRect(x: x, y: 4, width: w, height: 30)
            b.addAction(UIAction { [weak self] _ in
                self?.radicalFilter = value
                self?.applyFilter()
            }, for: .touchUpInside)
            radicalScroll.addSubview(b)
            x += w + 6
        }
        radicalScroll.contentSize = CGSize(width: x + 2, height: 38)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let barH: CGFloat = 40
        let top: CGFloat = radicalScroll.isHidden ? 0 : 38
        radicalScroll.frame = CGRect(x: 0, y: 0, width: bounds.width, height: top)
        grid.frame = CGRect(x: 0, y: top, width: bounds.width, height: bounds.height - barH - top)
        bar.frame = CGRect(x: 0, y: bounds.height - barH, width: bounds.width, height: barH)
    }
}
