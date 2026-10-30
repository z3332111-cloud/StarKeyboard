import UIKit

/// 剪貼簿紀錄：點一下貼上、釘選常用的、左右滑動刪除或釘選
final class ClipboardPanelView: UIView, UITableViewDataSource, UITableViewDelegate {
    var onInsert: ((String) -> Void)?
    var onTransfer: (() -> Void)?
    var onAddCurrent: (() -> Void)?
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
    private let transferButton = UIButton(type: .system)
    private let addButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private let emptyLabel = UILabel()
    private let bar: PanelBottomBar
    private var showPinnedOnly = false
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
        addButton.setTitle("＋ 加入目前複製的", for: .normal)
        addButton.titleLabel?.font = .rounded(14, .semibold)
        addButton.addAction(UIAction { [weak self] _ in self?.onAddCurrent?() }, for: .touchUpInside)
        header.addSubview(addButton)
        clearButton.setTitle("清除", for: .normal)
        clearButton.titleLabel?.font = .rounded(14)
        clearButton.addAction(UIAction { [weak self] _ in self?.clearTapped() }, for: .touchUpInside)
        header.addSubview(clearButton)
        transferButton.setTitle("匯入／匯出・剪貼簿搬家", for: .normal)
        transferButton.titleLabel?.font = .rounded(14, .semibold)
        transferButton.addAction(UIAction { [weak self] _ in self?.onTransfer?() }, for: .touchUpInside)
        header.addSubview(transferButton)
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

        bar.setTabs(["全部", "📌 釘選"])
        bar.onTab = { [weak self] i in
            self?.showPinnedOnly = i == 1
            self?.reload()
        }
        bar.onBack = { [weak self] in self?.onBack?() }
        bar.onBackspace = { [weak self] in self?.onBackspace?() }
        addSubview(bar)

        applyStyle()
        reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func reload() {
        rows = showPinnedOnly ? store.ordered.filter { $0.pinned } : store.ordered
        table.reloadData()
        if !hasFullAccess {
            emptyLabel.text = "要記錄剪貼簿，請到\n設定 › 一般 › 鍵盤 › 鍵盤 › 糯糯鍵盤\n打開「允許完整取用」"
        } else if showPinnedOnly {
            emptyLabel.text = "還沒有釘選的內容\n在項目上往右滑，或點 📌 就能釘選"
        } else {
            emptyLabel.text = "點「＋」手動儲存複製的文字\n或到 ⚙ 隱私與安全開啟自動記錄"
        }
        emptyLabel.isHidden = !rows.isEmpty
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        let headerH: CGFloat = 68, barH: CGFloat = 40
        header.frame = CGRect(x: 0, y: 0, width: w, height: headerH)
        titleLabel.frame = CGRect(x: 12, y: 0, width: 80, height: 34)
        clearButton.frame = CGRect(x: w - 96, y: 0, width: 88, height: 34)
        addButton.frame = CGRect(x: w - 96 - 150, y: 0, width: 150, height: 34)
        transferButton.frame = CGRect(x: 12, y: 34, width: w - 24, height: 34)
        table.frame = CGRect(x: 0, y: headerH, width: w, height: bounds.height - headerH - barH)
        emptyLabel.frame = table.frame.insetBy(dx: 20, dy: 10)
        bar.frame = CGRect(x: 0, y: bounds.height - barH, width: w, height: barH)
    }

    private func applyStyle() {
        let t = style.theme
        titleLabel.textColor = t.keyText
        transferButton.tintColor = t.isDark ? t.accent : t.specialText
        addButton.tintColor = t.isDark ? t.accent : t.specialText
        clearButton.tintColor = t.keyText.withAlphaComponent(0.7)
        emptyLabel.textColor = t.keyText.withAlphaComponent(0.7)
        table.separatorColor = t.shadow.withAlphaComponent(0.5)
    }

    private func clearTapped() {
        if confirmingClear {
            store.clearUnpinned()
            confirmingClear = false
            clearButton.setTitle("清除", for: .normal)
            reload()
            return
        }
        confirmingClear = true
        clearButton.setTitle("確定清除？", for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self, self.confirmingClear else { return }
            self.confirmingClear = false
            self.clearButton.setTitle("清除", for: .normal)
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

        let pin = UIButton(type: .system)
        pin.setImage(UIImage(systemName: item.pinned ? "pin.fill" : "pin"), for: .normal)
        pin.tintColor = item.pinned ? t.accent : t.keyText.withAlphaComponent(0.35)
        pin.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
        let id = item.id
        pin.addAction(UIAction { [weak self] _ in
            self?.store.togglePin(id)
            self?.reload()
        }, for: .touchUpInside)
        cell.accessoryView = pin
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
