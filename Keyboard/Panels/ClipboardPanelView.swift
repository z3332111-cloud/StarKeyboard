import UIKit

/// 剪貼簿紀錄：點一下貼上、釘選常用的、左右滑動刪除或釘選
final class ClipboardPanelView: UIView, UITableViewDataSource, UITableViewDelegate {
    var onInsert: ((String) -> Void)?
    var onTransfer: (() -> Void)?
    var onAddCurrent: (() -> Void)?
    var onSearch: (() -> Void)?
    var onEditCategory: ((String?) -> Void)?
    var onEdit: ((ClipItem) -> Void)?
    var onError: ((String) -> Void)?
    var onBack: (() -> Void)?
    var onBackspace: (() -> Void)?
    var style: KeyboardStyle {
        didSet {
            bar.style = style
            applyStyle()
            table.reloadData()
        }
    }

    private let store: ClipboardStore
    private let hasFullAccess: Bool
    private let table = UITableView(frame: .zero, style: .plain)
    private let header = UIView()
    private let titleLabel = UILabel()
    private let categoryButton = UIButton(type: .system)
    private let transferButton = UIButton(type: .system)
    private let addButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private let searchButton = UIButton(type: .system)
    private let emptyLabel = UILabel()
    private let bar: PanelBottomBar
    private var selected = 0
    private var tabTitles: [String] = []
    private var rows: [ClipItem] = []
    private var confirmingClear = false

    init(store: ClipboardStore, hasFullAccess: Bool, style: KeyboardStyle) {
        self.store = store
        self.hasFullAccess = hasFullAccess
        self.style = style
        bar = PanelBottomBar(style: style)
        super.init(frame: .zero)

        titleLabel.text = "剪貼簿"
        titleLabel.font = .rounded(15, .bold)
        header.addSubview(titleLabel)
        // 左上角原本只寫「剪貼簿」，改成搜尋按鈕
        titleLabel.isHidden = true
        searchButton.setTitle("🔍 搜尋", for: .normal)
        searchButton.titleLabel?.font = .rounded(15, .bold)
        searchButton.contentHorizontalAlignment = .left
        searchButton.accessibilityLabel = "搜尋剪貼簿"
        searchButton.addAction(UIAction { [weak self] _ in self?.onSearch?() }, for: .touchUpInside)
        header.addSubview(searchButton)
        addButton.setTitle("＋ 加入目前複製的", for: .normal)
        addButton.titleLabel?.font = .rounded(14, .semibold)
        addButton.addAction(UIAction { [weak self] _ in self?.onAddCurrent?() }, for: .touchUpInside)
        header.addSubview(addButton)
        clearButton.setTitle("清暫存", for: .normal)
        clearButton.titleLabel?.font = .rounded(14)
        clearButton.addAction(UIAction { [weak self] _ in self?.clearTapped() }, for: .touchUpInside)
        header.addSubview(clearButton)
        transferButton.setTitle("匯入／匯出", for: .normal)
        transferButton.titleLabel?.font = .rounded(14, .semibold)
        transferButton.addAction(UIAction { [weak self] _ in self?.onTransfer?() }, for: .touchUpInside)
        header.addSubview(transferButton)
        categoryButton.setTitle("資料夾管理", for: .normal)
        categoryButton.titleLabel?.font = .rounded(14, .semibold)
        categoryButton.showsMenuAsPrimaryAction = true
        header.addSubview(categoryButton)
        addSubview(header)

        table.backgroundColor = .clear
        table.dataSource = self
        table.delegate = self
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 48
        table.separatorInset = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        table.register(UITableViewCell.self, forCellReuseIdentifier: "clip")
        addSubview(table)

        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.font = .rounded(14)
        addSubview(emptyLabel)


        bar.onTab = { [weak self] i in
            guard let self = self else { return }
            self.selected = i; self.reload()
        }
        bar.showsAdd = true
        bar.onAdd = { [weak self] in self?.onEditCategory?(nil) }
        bar.onBack = { [weak self] in self?.onBack?() }
        bar.onBackspace = { [weak self] in self?.onBackspace?() }
        addSubview(bar)

        applyStyle()
        reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func selectCategory(_ name: String) {
        selected = store.categories.firstIndex(of: name).map { $0 + 2 } ?? 0
        reload(); setNeedsLayout(); layoutIfNeeded(); bar.revealSelectedTab()
    }

    func reload() {
        let titles = ["全部", "📌 釘選"] + store.categories
        if titles != tabTitles { tabTitles = titles; bar.setTabs(titles) }
        if selected >= titles.count { selected = 0 }
        bar.selectedTab = selected
        if selected == 1 { rows = store.ordered.filter { $0.pinned } }
        else if selected >= 2 { rows = store.ordered.filter { $0.category == store.categories[selected - 2] } }
        else { rows = store.ordered }
        categoryButton.isHidden = store.categories.isEmpty
        updateCategoryMenu()
        table.reloadData()
        if !hasFullAccess {
            emptyLabel.text = "要記錄剪貼簿，請到\n設定 › 一般 › 鍵盤 › 鍵盤 › 糯糯鍵盤\n打開「允許完整取用」"
        } else if selected == 1 {
            emptyLabel.text = "還沒有釘選的內容\n在項目上往右滑，或點 📌 就能釘選"
        } else if selected >= 2 {
            emptyLabel.text = "這個分類還沒有內容\n點每筆右側的資料夾圖示來歸類"
        } else {
            emptyLabel.text = "點上方「加入目前複製的」儲存文字\n或到 ⚙ 隱私與安全開啟自動記錄"
        }
        emptyLabel.isHidden = !rows.isEmpty
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        let headerH: CGFloat = 68, barH: CGFloat = 40
        header.frame = CGRect(x: 0, y: 0, width: w, height: headerH)
        titleLabel.frame = CGRect(x: 12, y: 0, width: 80, height: 34)
        searchButton.frame = CGRect(x: 12, y: 0, width: max(70, w - 96 - 150 - 16), height: 34)
        clearButton.frame = CGRect(x: w - 96, y: 0, width: 88, height: 34)
        addButton.frame = CGRect(x: w - 96 - 150, y: 0, width: 150, height: 34)
        transferButton.frame = CGRect(x: 12, y: 34, width: w / 2 - 12, height: 34)
        categoryButton.frame = CGRect(x: w / 2, y: 34, width: w / 2 - 12, height: 34)
        table.frame = CGRect(x: 0, y: headerH, width: w, height: bounds.height - headerH - barH)
        emptyLabel.frame = table.frame.insetBy(dx: 20, dy: 10)
        bar.frame = CGRect(x: 0, y: bounds.height - barH, width: w, height: barH)
    }

    private func applyStyle() {
        let t = style.theme
        titleLabel.textColor = t.keyText
        categoryButton.tintColor = t.isDark ? t.accent : t.specialText
        transferButton.tintColor = t.isDark ? t.accent : t.specialText
        addButton.tintColor = t.isDark ? t.accent : t.specialText
        searchButton.tintColor = t.keyText
        clearButton.tintColor = t.keyText.withAlphaComponent(0.7)
        emptyLabel.textColor = t.keyText.withAlphaComponent(0.7)
        table.separatorColor = t.shadow.withAlphaComponent(0.5)
    }

    private func perform(_ action: () throws -> Void) {
        do { try action(); reload() } catch { onError?(error.localizedDescription) }
    }
    private func updateCategoryMenu() {
        let groups: [UIMenuElement] = store.categories.map { name in
            UIMenu(title: name, children: [
                UIAction(title: "重新命名") { [weak self] _ in self?.onEditCategory?(name) },
                UIAction(title: "移除分類（內容留在未分類）", attributes: .destructive) { [weak self] _ in
                    self?.perform { try self?.store.deleteCategory(name) }
                }
            ])
        }
        categoryButton.menu = UIMenu(title: "清暫存只清未分類且未釘選內容", children:
            [UIAction(title: "＋新增分類") { [weak self] _ in self?.onEditCategory?(nil) }] + groups)
    }

    private func clearTapped() {
        if confirmingClear {
            store.clearUnpinned()
            confirmingClear = false
            clearButton.setTitle("清暫存", for: .normal)
            reload()
            return
        }
        confirmingClear = true
        clearButton.setTitle("確定清除？", for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self, self.confirmingClear else { return }
            self.confirmingClear = false
            self.clearButton.setTitle("清暫存", for: .normal)
        }
    }

    // MARK: 表格

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "clip", for: indexPath)
        let item = rows[indexPath.row]
        let t = style.theme
        cell.backgroundColor = .clear
        cell.selectionStyle = .default
        let bg = UIView()
        bg.backgroundColor = t.key.withAlphaComponent(0.5)
        cell.selectedBackgroundView = bg
        cell.textLabel?.text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        cell.textLabel?.numberOfLines = 2
        cell.textLabel?.font = .systemFont(ofSize: 16)
        cell.textLabel?.textColor = t.keyText

        let edit = UIButton(type: .system)
        edit.setImage(UIImage(systemName: "pencil"), for: .normal)
        edit.tintColor = t.accent
        edit.accessibilityLabel = "編輯"
        edit.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
        edit.addAction(UIAction { [weak self] _ in self?.onEdit?(item) }, for: .touchUpInside)
        let pin = UIButton(type: .system)
        pin.setImage(UIImage(systemName: item.pinned ? "pin.fill" : "pin"), for: .normal)
        pin.tintColor = item.pinned ? t.accent : t.keyText.withAlphaComponent(0.35)
        pin.frame = CGRect(x: 36, y: 0, width: 36, height: 36)
        let id = item.id
        pin.addAction(UIAction { [weak self] _ in
            self?.store.togglePin(id)
            self?.reload()
        }, for: .touchUpInside)
        let folder = UIButton(type: .system)
        folder.setImage(UIImage(systemName: item.category == nil ? "folder" : "folder.fill"), for: .normal)
        folder.tintColor = t.accent
        folder.accessibilityLabel = "移到分類：" + (item.category ?? "未分類")
        folder.frame = CGRect(x: 72, y: 0, width: 36, height: 36)
        folder.showsMenuAsPrimaryAction = true
        folder.menu = UIMenu(title: "移到分類", children: ([nil] + store.categories.map { Optional($0) }).map { name in
            UIAction(title: name ?? "未分類", state: item.category == name ? .on : .off) { [weak self] _ in
                self?.perform { try self?.store.assign(id, to: name) }
            }
        } + [UIAction(title: "＋新增分類") { [weak self] _ in self?.onEditCategory?(nil) }])
        let actions = UIView(frame: CGRect(x: 0, y: 0, width: 108, height: 36))
        actions.addSubview(edit)
        actions.addSubview(pin)
        if !store.categories.isEmpty { actions.addSubview(folder) }
        else { actions.frame.size.width = 72 }
        cell.accessoryView = actions
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onInsert?(rows[indexPath.row].text)
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let id = rows[indexPath.row].id
        let delete = UIContextualAction(style: .destructive, title: "刪除") { [weak self] _, _, done in
            self?.store.remove(id)
            self?.reload()
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let item = rows[indexPath.row]
        let pin = UIContextualAction(style: .normal, title: item.pinned ? "取消釘選" : "釘選") { [weak self] _, _, done in
            self?.store.togglePin(item.id)
            self?.reload()
            done(true)
        }
        pin.backgroundColor = style.theme.accent
        return UISwipeActionsConfiguration(actions: [pin])
    }
}
