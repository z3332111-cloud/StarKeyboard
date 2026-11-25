import UIKit

/// 剪貼簿搬家：全部在鍵盤畫面上完成（鍵盤裡跳出系統選單或檔案視窗會閃退）。
/// 匯出＝把全部紀錄複製成一段 JSON 文字，貼到備忘錄保存；匯入＝讀「剛剛複製的內容」，JSON 備份或一般文字都可以。
/// 不要求 App Group，也不讀取其他鍵盤的私人資料。
final class ClipboardTransferController: NSObject {
    private weak var host: UIViewController?
    private let store: ClipboardStore
    private let style: () -> KeyboardStyle
    private let changed: () -> Void
    private var overlay: UIView?

    init(presenter: UIViewController, store: ClipboardStore, style: @escaping () -> KeyboardStyle, changed: @escaping () -> Void) {
        self.host = presenter; self.store = store; self.style = style; self.changed = changed
    }

    func show() {
        page(title: "剪貼簿搬家",
             text: "匯出會把全部紀錄（含釘選、分類）複製成一段文字，貼到「備忘錄」或傳給自己保存。要搬回來時，先複製那段文字，再按「匯入」。",
             buttons: [
                ("📤 匯出：複製全部紀錄", { [weak self] in self?.exportText() }),
                ("📥 匯入剛剛複製的內容", { [weak self] in self?.importPasteboard() }),
                ("從其他鍵盤搬家：怎麼做？", { [weak self] in
                    self?.message("先在原鍵盤找「匯出／備份」或「全選複製」，複製後回來按「匯入剛剛複製的內容」。可以是糯糯的備份文字、JSON 文字陣列，或一般文字（可選每行一筆）。這裡無法直接讀取其他鍵盤的私人紀錄。")
                }),
             ])
    }

    private func exportText() {
        do {
            let data = try ClipboardArchive.encode(store.items, categories: store.categories)
            guard let text = String(data: data, encoding: .utf8) else { throw ClipboardArchive.Failure.invalid }
            UIPasteboard.general.string = text
            message("已複製 \(store.items.count) 筆！\n現在打開「備忘錄」新增一則，長按貼上保存。\n（這段是明文，不要貼到公開的地方）")
        } catch {
            message(error.localizedDescription)
        }
    }

    private func importPasteboard() {
        let pb = UIPasteboard.general
        guard !pb.types.contains("org.nspasteboard.ConcealedType"),
              !pb.types.contains("org.nspasteboard.TransientType") else {
            message("這份剪貼簿被標示為敏感或暫存內容，已跳過。"); return
        }
        guard let text = pb.string, !text.isEmpty else { message("目前沒有複製的文字。先複製備份那段文字，再按一次。"); return }
        // 看起來是 JSON 備份就直接照備份匯入（保留釘選和分類）
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("["),
           let contents = try? ClipboardArchive.decodeContents(Data(trimmed.utf8)) {
            confirm(contents.entries, categories: contents.categories)
            return
        }
        page(title: "文字怎麼分筆？", text: "多行片語選「整段」；從別的鍵盤複製的清單選「每行一筆」。", buttons: [
            ("每行一筆", { [weak self] in self?.importText(text, split: true) }),
            ("整段一筆（保留換行）", { [weak self] in self?.importText(text, split: false) }),
        ])
    }

    private func importText(_ text: String, split: Bool) {
        do { confirm(try ClipboardArchive.textEntries(text, splitLines: split)) }
        catch { message(error.localizedDescription) }
    }

    private func confirm(_ entries: [ClipboardArchive.Entry], categories: [String] = []) {
        let preview = entries.prefix(2).map { String($0.text.prefix(40)) }.joined(separator: "\n")
        page(title: "匯入 \(entries.count) 筆？", text: preview + "\n\n重複的會合併，原本的紀錄會保留。", buttons: [
            ("匯入", { [weak self] in
                guard let self = self else { return }
                do {
                    let result = try self.store.importEntries(entries, categories: categories)
                    self.changed()
                    self.message("新增 \(result.added) 筆，重複 \(result.duplicates) 筆，容量不足跳過 \(result.skipped) 筆。")
                } catch { self.message("沒有完成匯入：\(error.localizedDescription)") }
            }),
        ])
    }

    private func message(_ text: String) {
        page(title: "剪貼簿搬家", text: text, buttons: [])
    }

    /// 蓋在鍵盤上的一頁：標題、說明、幾個按鈕，最下面一定有「關閉」
    private func page(title: String, text: String, buttons: [(String, () -> Void)]) {
        guard let root = host?.view else { return }
        overlay?.removeFromSuperview()
        let t = style().theme
        let box = UIView(frame: root.bounds)
        box.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        box.backgroundColor = t.backgroundBottom
        let scroll = UIScrollView(frame: box.bounds)
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        box.addSubview(scroll)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -14),
        ])
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .rounded(17, .bold)
        titleLabel.textColor = t.keyText
        stack.addArrangedSubview(titleLabel)
        let body = UILabel()
        body.text = text
        body.numberOfLines = 0
        body.font = .rounded(13)
        body.textColor = t.keyText.withAlphaComponent(0.8)
        stack.addArrangedSubview(body)
        for (name, action) in buttons + [("關閉", { [weak self] in self?.close() })] {
            let b = UIButton(type: .system)
            b.setTitle(name, for: .normal)
            b.titleLabel?.font = .rounded(15, .semibold)
            let primary = name != "關閉"
            b.backgroundColor = primary ? t.accent : t.specialKey
            b.setTitleColor(primary ? t.accentText : t.specialText, for: .normal)
            b.layer.cornerRadius = 12
            b.heightAnchor.constraint(equalToConstant: 40).isActive = true
            b.addAction(UIAction { _ in action() }, for: .touchUpInside)
            stack.addArrangedSubview(b)
        }
        root.addSubview(box)
        overlay = box
    }

    func close() {
        overlay?.removeFromSuperview()
        overlay = nil
    }
}
