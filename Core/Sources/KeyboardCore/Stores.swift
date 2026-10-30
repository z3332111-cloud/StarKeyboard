import Foundation

enum JSONFile {
    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, to url: URL) {
        try? write(value, to: url)
    }

    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        var protectedURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? protectedURL.setResourceValues(values)
    }
}

// MARK: - 剪貼簿紀錄

struct ClipItem: Codable, Equatable {
    var id: UUID
    var text: String
    var pinned: Bool
    var date: Date
}

final class ClipboardStore {
    static let maxTextLength = 20000

    /// 新的在前面
    private(set) var items: [ClipItem] = []
    private let fileURL: URL?
    var limit: Int {
        didSet {
            trim()
            save()
        }
    }

    init(fileURL: URL?, limit: Int = 200) {
        self.fileURL = fileURL
        self.limit = limit
        if let url = fileURL, let saved = JSONFile.load([ClipItem].self, from: url) {
            items = saved
        }
    }

    /// 釘選的在最上面，其餘照時間
    var ordered: [ClipItem] {
        items.filter { $0.pinned } + items.filter { !$0.pinned }
    }

    @discardableResult
    func add(_ text: String, date: Date = Date()) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let stored = text.count > Self.maxTextLength ? String(text.prefix(Self.maxTextLength)) : text
        if let i = items.firstIndex(where: { $0.text == stored }) {
            var item = items.remove(at: i)
            item.date = date
            items.insert(item, at: 0)
        } else {
            items.insert(ClipItem(id: UUID(), text: stored, pinned: false, date: date), at: 0)
        }
        trim()
        save()
        return true
    }

    struct ImportResult { let added: Int; let duplicates: Int; let skipped: Int }

    /// Prepare and persist before changing memory. Imported entries never evict existing history.
    func importEntries(_ entries: [ClipboardArchive.Entry]) throws -> ImportResult {
        guard entries.count <= ClipboardArchive.maxEntries else { throw ClipboardArchive.Failure.tooMany }
        guard entries.allSatisfy({ $0.text.unicodeScalars.count <= Self.maxTextLength }) else { throw ClipboardArchive.Failure.tooLong }
        var existing = items
        var unique: [ClipboardArchive.Entry] = []
        var index: [String: Int] = [:]
        var duplicates = 0
        for entry in entries where !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let i = existing.firstIndex(where: { $0.text == entry.text }) {
                existing[i].pinned = existing[i].pinned || entry.pinned
                duplicates += 1
            } else if let i = index[entry.text] {
                unique[i].pinned = unique[i].pinned || entry.pinned
                duplicates += 1
            } else {
                index[entry.text] = unique.count
                unique.append(entry)
            }
        }
        var capacity = max(0, limit - existing.filter { !$0.pinned }.count)
        var added: [ClipItem] = []
        var skipped = 0
        for entry in unique {
            guard entry.pinned || capacity > 0 else { skipped += 1; continue }
            if !entry.pinned { capacity -= 1 }
            added.append(ClipItem(id: UUID(), text: entry.text, pinned: entry.pinned, date: Date()))
        }
        let merged = added + existing
        if let url = fileURL { try JSONFile.write(merged, to: url) }
        items = merged
        return ImportResult(added: added.count, duplicates: duplicates, skipped: skipped)
    }

    func togglePin(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].pinned.toggle()
        save()
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func clearUnpinned() {
        items.removeAll { !$0.pinned }
        save()
    }

    /// 超過上限就刪掉最舊、沒釘選的
    private func trim() {
        var unpinned = 0
        items = items.filter { item in
            if item.pinned { return true }
            unpinned += 1
            return unpinned <= limit
        }
    }

    private func save() {
        if let url = fileURL { JSONFile.save(items, to: url) }
    }
}

// MARK: - 我的表符、自製貼圖、最近使用

struct StickerRef: Codable, Equatable {
    var id: UUID
    var file: String
}

final class EmoticonStore {
    private struct Contents: Codable {
        var custom: [String]
        var stickers: [StickerRef]
        var recents: [String: [String]]
    }

    static let defaultCustom = ["(๑•̀ㅂ•́)و✧", "ʕ•ᴥ•ʔ", "✿♡✿", "(｡･ω･｡)ﾉ♡"]

    private var contents: Contents
    private let directory: URL?

    init(directory: URL?) {
        self.directory = directory
        if let url = directory?.appendingPathComponent("emoticons.json"),
           let saved = JSONFile.load(Contents.self, from: url) {
            contents = saved
        } else {
            contents = Contents(custom: Self.defaultCustom, stickers: [], recents: [:])
        }
    }

    var custom: [String] { contents.custom }
    var stickers: [StickerRef] { contents.stickers }
    var stickerDirectory: URL? { directory?.appendingPathComponent("stickers", isDirectory: true) }

    func addCustom(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        contents.custom.removeAll { $0 == t }
        contents.custom.insert(t, at: 0)
        save()
    }

    func removeCustom(_ text: String) {
        contents.custom.removeAll { $0 == text }
        save()
    }

    @discardableResult
    func addSticker(pngData: Data) -> StickerRef? {
        guard let dir = stickerDirectory else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ref = StickerRef(id: UUID(), file: UUID().uuidString + ".png")
        do {
            try pngData.write(to: dir.appendingPathComponent(ref.file))
        } catch {
            return nil
        }
        contents.stickers.insert(ref, at: 0)
        save()
        return ref
    }

    func stickerURL(_ ref: StickerRef) -> URL? {
        stickerDirectory?.appendingPathComponent(ref.file)
    }

    func removeSticker(_ ref: StickerRef) {
        if let url = stickerURL(ref) { try? FileManager.default.removeItem(at: url) }
        contents.stickers.removeAll { $0.id == ref.id }
        save()
    }

    func recents(_ kind: String) -> [String] {
        contents.recents[kind] ?? []
    }

    func pushRecent(_ text: String, kind: String, limit: Int = 40) {
        var list = recents(kind)
        list.removeAll { $0 == text }
        list.insert(text, at: 0)
        if list.count > limit { list.removeLast(list.count - limit) }
        contents.recents[kind] = list
        save()
    }

    private func save() {
        if let url = directory?.appendingPathComponent("emoticons.json") {
            JSONFile.save(contents, to: url)
        }
    }
}
