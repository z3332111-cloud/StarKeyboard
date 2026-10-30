import UIKit
import UniformTypeIdentifiers

/// 在鍵盤自己的容器匯出／匯入，不要求 App Group，也不讀取其他鍵盤的私人資料。
final class ClipboardTransferController: NSObject, UIDocumentPickerDelegate {
    private weak var presenter: UIViewController?
    private let store: ClipboardStore
    private let changed: () -> Void
    private var exportDirectory: URL?
    private var exporting = false

    init(presenter: UIViewController, store: ClipboardStore, changed: @escaping () -> Void) {
        self.presenter = presenter; self.store = store; self.changed = changed
    }
    func show() {
        let menu = UIAlertController(title: "剪貼簿搬家", message: "JSON 保留多行文字與釘選；TXT 每行一筆。匯出檔是明文，請選自己信任的儲存位置。", preferredStyle: .actionSheet)
        menu.addAction(UIAlertAction(title: "匯出全部為 JSON 檔案", style: .default) { [weak self] _ in self?.exportFile() })
        menu.addAction(UIAlertAction(title: "匯入 JSON／TXT 檔案", style: .default) { [weak self] _ in self?.importFile() })
        menu.addAction(UIAlertAction(title: "匯入目前複製的文字", style: .default) { [weak self] _ in self?.importPasteboard() })
        menu.addAction(UIAlertAction(title: "從其他鍵盤搬家：怎麼做？", style: .default) { [weak self] _ in
            self?.message("先在原鍵盤找「匯出／備份」或「全選複製」。可匯入 JSON 的文字陣列、items 清單，或有 text／content 欄位的項目；TXT 每行一筆。若原鍵盤沒有匯出功能，要先把想保留的內容複製出來，這裡無法直接讀取其他鍵盤的私人紀錄。")
        })
        menu.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(menu)
    }
    private func present(_ controller: UIViewController) {
        guard let presenter = presenter else { return }
        if let current = presenter.presentedViewController {
            guard current is UIAlertController else { return }
            current.dismiss(animated: true) { [weak self] in self?.present(controller) }
            return
        }
        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: 0, width: 1, height: 1)
        }
        presenter.present(controller, animated: true)
    }
    private func message(_ text: String) {
        let alert = UIAlertController(title: "剪貼簿搬家", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert)
    }
    private func exportFile() {
        do {
            cleanup()
            let data = try ClipboardArchive.encode(store.items)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("clipboard-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            exportDirectory = directory
            let url = directory.appendingPathComponent("糯糯剪貼簿.json")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            var protected = directory
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try protected.setResourceValues(values)
            let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
            exporting = true; picker.delegate = self
            present(picker)
        } catch { cleanup(); message(error.localizedDescription) }
    }
    private func importFile() {
        exporting = false
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json, .plainText], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = self
        present(picker)
    }
    private func importPasteboard() {
        let pb = UIPasteboard.general
        guard !pb.types.contains("org.nspasteboard.ConcealedType"),
              !pb.types.contains("org.nspasteboard.TransientType") else {
            message("這份剪貼簿被標示為敏感或暫存內容，已跳過。"); return
        }
        guard let text = pb.string, !text.isEmpty else { message("目前沒有複製的文字。"); return }
        let menu = UIAlertController(title: "文字怎麼分筆？", message: "多行片語請選整段；從別的鍵盤複製清單時可選每行一筆。", preferredStyle: .actionSheet)
        for (title, split) in [("每行一筆", true), ("整段一筆（保留換行）", false)] {
            menu.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                do { self?.confirm(try ClipboardArchive.textEntries(text, splitLines: split)) }
                catch { self?.message(error.localizedDescription) }
            })
        }
        menu.addAction(UIAlertAction(title: "取消", style: .cancel)); present(menu)
    }
    private func confirm(_ entries: [ClipboardArchive.Entry]) {
        let preview = entries.prefix(3).map { String($0.text.prefix(60)) }.joined(separator: "\n\n")
        let alert = UIAlertController(title: "匯入 \(entries.count) 筆？", message: preview + "\n\n重複內容合併。原本紀錄會保留；超過未釘選上限的新內容會跳過。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "匯入", style: .default) { [weak self] _ in
            guard let self = self else { return }
            do {
                let result = try self.store.importEntries(entries)
                self.changed()
                self.message("新增 \(result.added) 筆，重複 \(result.duplicates) 筆，容量不足跳過 \(result.skipped) 筆。")
            } catch { self.message("沒有完成匯入：\(error.localizedDescription)") }
        })
        present(alert)
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if exporting { cleanup(); return }
        guard let url = urls.first else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: ClipboardArchive.maxBytes + 1) ?? Data()
            let entries = try ClipboardArchive.decode(data, plainText: url.pathExtension.lowercased() == "txt")
            controller.dismiss(animated: true) { [weak self] in self?.confirm(entries) }
        } catch {
            controller.dismiss(animated: true) { [weak self] in self?.message(error.localizedDescription) }
        }
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { cleanup() }
    private func cleanup() {
        if let directory = exportDirectory { try? FileManager.default.removeItem(at: directory) }
        exportDirectory = nil
    }
    deinit { cleanup() }
}
