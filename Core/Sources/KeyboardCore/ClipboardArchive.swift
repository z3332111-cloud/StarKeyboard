import Foundation

/// 可攜格式不包含裝置路徑或內部 ID；兩個平台共用 text / pinned。
enum ClipboardArchive {
    static let maxBytes = 2 * 1024 * 1024
    static let maxEntries = 1000
    struct Entry: Codable, Equatable {
        let text: String
        var pinned: Bool = false
    }
    private struct Document: Encodable {
        let format = "nuonuo-clipboard"
        let version = 1
        let items: [Entry]
    }
    enum Failure: String, LocalizedError {
        case tooLarge = "檔案超過 2 MB，請先分成較小的檔案。"
        case invalid = "無法辨識格式。請選 JSON 備份或 UTF-8 TXT 文字清單。"
        case unsupported = "這份備份的版本較新，請先更新糯糯鍵盤。"
        case tooMany = "一次最多匯入 1,000 筆。"
        case tooLong = "有一筆文字超過 20,000 字，請先縮短或分開。"
        case empty = "沒有可匯入的文字。"
        var errorDescription: String? { rawValue }
    }
    static func encode(_ items: [ClipItem]) throws -> Data {
        let entries = items.map { Entry(text: $0.text, pinned: $0.pinned) }
        _ = try validate(entries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Document(items: entries))
        guard data.count <= maxBytes else { throw Failure.tooLarge }
        return data
    }
    static func decode(_ data: Data, plainText: Bool = false) throws -> [Entry] {
        guard data.count <= maxBytes else { throw Failure.tooLarge }
        if plainText {
            guard let string = String(data: data, encoding: .utf8) else { throw Failure.invalid }
            return try textEntries(string, splitLines: true)
        }
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) }
        catch { throw Failure.invalid }
        let rows: [Any]
        if let array = object as? [Any] { rows = array }
        else if let document = object as? [String: Any], let array = document["items"] as? [Any] {
            if let format = document["format"] as? String {
                guard format == "nuonuo-clipboard" else { throw Failure.invalid }
                guard (document["version"] as? Int) == 1 else { throw Failure.unsupported }
            }
            rows = array
        } else { throw Failure.invalid }
        guard rows.count <= maxEntries else { throw Failure.tooMany }
        let entries = try rows.map { row -> Entry in
            if let text = row as? String { return Entry(text: text) }
            guard let row = row as? [String: Any],
                  let text = (row["text"] as? String) ?? (row["content"] as? String) else { throw Failure.invalid }
            return Entry(text: text, pinned: row["pinned"] as? Bool ?? false)
        }
        return try validate(entries)
    }
    static func textEntries(_ text: String, splitLines: Bool) throws -> [Entry] {
        guard text.utf8.count <= maxBytes else { throw Failure.tooLarge }
        let cleaned = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        let rows = splitLines ? cleaned.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: .newlines) : [cleaned]
        return try validate(rows.map { Entry(text: $0) })
    }
    private static func validate(_ entries: [Entry]) throws -> [Entry] {
        guard entries.count <= maxEntries else { throw Failure.tooMany }
        guard entries.allSatisfy({ $0.text.unicodeScalars.count <= ClipboardStore.maxTextLength }) else { throw Failure.tooLong }
        let nonempty = entries.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !nonempty.isEmpty else { throw Failure.empty }
        return nonempty
    }
}
