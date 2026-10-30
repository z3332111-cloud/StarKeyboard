import Foundation

/// 可攜格式不包含裝置路徑或內部 ID；兩個平台共用 text / pinned。
enum ClipboardArchive {
    static let maxBytes = 2 * 1024 * 1024
    static let maxEntries = 1000
    struct Entry: Codable, Equatable {
        let text: String
        var pinned: Bool = false
        var category: String? = nil
    }
    private struct Document: Encodable {
        let format = "nuonuo-clipboard"
        let version = 2
        let categories: [String]
        let items: [Entry]
    }
    struct Contents { let entries: [Entry]; let categories: [String] }
    enum Failure: String, LocalizedError {
        case duplicateCategory = "已有同名分類，請換個名稱。"
        case category = "分類名稱需為 1～40 字，最多 50 個分類。"
        case tooLarge = "檔案超過 2 MB，請先分成較小的檔案。"
        case invalid = "無法辨識格式。請選 JSON 備份或 UTF-8 TXT 文字清單。"
        case unsupported = "這份備份的版本較新，請先更新糯糯鍵盤。"
        case tooMany = "一次最多匯入 1,000 筆。"
        case tooLong = "有一筆文字超過 20,000 字，請先縮短或分開。"
        case empty = "沒有可匯入的文字。"
        var errorDescription: String? { rawValue }
    }
    static func encode(_ items: [ClipItem], categories: [String] = []) throws -> Data {
        let entries = items.map { Entry(text: $0.text, pinned: $0.pinned, category: $0.category) }
        let names = try validateCategories(categories + entries.compactMap { $0.category })
        if !entries.isEmpty { _ = try validate(entries) }
        guard !entries.isEmpty || !names.isEmpty else { throw Failure.empty }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Document(categories: names, items: entries))
        guard data.count <= maxBytes else { throw Failure.tooLarge }
        return data
    }
    static func decode(_ data: Data, plainText: Bool = false) throws -> [Entry] {
        try decodeContents(data, plainText: plainText).entries
    }
    static func decodeContents(_ data: Data, plainText: Bool = false) throws -> Contents {
        guard data.count <= maxBytes else { throw Failure.tooLarge }
        if plainText {
            guard let string = String(data: data, encoding: .utf8) else { throw Failure.invalid }
            return Contents(entries: try textEntries(string, splitLines: true), categories: [])
        }
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) }
        catch { throw Failure.invalid }
        let rows: [Any]
        var categories: [String] = []
        if let array = object as? [Any] { rows = array }
        else if let document = object as? [String: Any], let array = document["items"] as? [Any] {
            if let format = document["format"] as? String {
                guard format == "nuonuo-clipboard" else { throw Failure.invalid }
                guard [1, 2].contains(document["version"] as? Int ?? 0) else { throw Failure.unsupported }
            }
            if let value = document["categories"] {
                guard let names = value as? [String] else { throw Failure.invalid }
                categories = try validateCategories(names)
            }
            rows = array
        } else { throw Failure.invalid }
        guard rows.count <= maxEntries else { throw Failure.tooMany }
        let entries = try rows.map { row -> Entry in
            if let text = row as? String { return Entry(text: text) }
            guard let row = row as? [String: Any],
                  let text = (row["text"] as? String) ?? (row["content"] as? String) else { throw Failure.invalid }
            let category = row["category"] as? String
            if let value = row["category"], !(value is NSNull), category == nil { throw Failure.invalid }
            return Entry(text: text, pinned: row["pinned"] as? Bool ?? false, category: category)
        }
        categories = try validateCategories(categories + entries.compactMap { $0.category })
        if entries.isEmpty && !categories.isEmpty { return Contents(entries: [], categories: categories) }
        return Contents(entries: try validate(entries), categories: categories)
    }
    static func textEntries(_ text: String, splitLines: Bool) throws -> [Entry] {
        guard text.utf8.count <= maxBytes else { throw Failure.tooLarge }
        let cleaned = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        let rows = splitLines ? cleaned.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: .newlines) : [cleaned]
        return try validate(rows.map { Entry(text: $0) })
    }
    static func validateCategories(_ names: [String]) throws -> [String] {
        var unique: [String] = []
        for name in names {
            guard name == name.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  name.unicodeScalars.count <= 40, !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw Failure.category }
            if !unique.contains(name) { unique.append(name) }
        }
        guard unique.count <= 50 else { throw Failure.category }
        return unique
    }
    private static func validate(_ entries: [Entry]) throws -> [Entry] {
        _ = try validateCategories(entries.compactMap { $0.category })
        guard entries.count <= maxEntries else { throw Failure.tooMany }
        guard entries.allSatisfy({ $0.text.unicodeScalars.count <= ClipboardStore.maxTextLength }) else { throw Failure.tooLong }
        let nonempty = entries.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !nonempty.isEmpty else { throw Failure.empty }
        return nonempty
    }
}
