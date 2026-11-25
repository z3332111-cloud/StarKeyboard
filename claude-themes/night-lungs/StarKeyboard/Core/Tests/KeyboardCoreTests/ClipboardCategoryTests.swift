import XCTest
@testable import KeyboardCore

final class ClipboardCategoryTests: XCTestCase {
    func testLegacyMigrationFoldersAndRetention() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let old = [ClipItem(id: UUID(), text: "舊內容", pinned: false, date: Date())]
        try JSONEncoder().encode(old).write(to: url)
        let store = ClipboardStore(fileURL: url, limit: 1)
        try store.addCategory("工作")
        try store.assign(old[0].id, to: "工作")
        store.add("暫存一"); store.add("暫存二"); store.clearUnpinned()
        XCTAssertEqual(store.items.map { $0.text }, ["舊內容"])
        try store.renameCategory("工作", to: "靈感")
        let loaded = ClipboardStore(fileURL: url)
        XCTAssertEqual(loaded.categories, ["靈感"])
        XCTAssertEqual(loaded.items[0].category, "靈感")
        try loaded.deleteCategory("靈感")
        XCTAssertEqual(loaded.items.count, 1)
        XCTAssertNil(loaded.items[0].category)
    }
    func testArchiveKeepsEmptyFoldersAndDuplicateAssignment() throws {
        let source = ClipboardStore(fileURL: nil)
        try source.addCategory("空資料夾"); try source.addCategory("工作")
        source.add("甲"); try source.assign(source.items[0].id, to: "工作")
        let backup = try ClipboardArchive.decodeContents(ClipboardArchive.encode(source.items, categories: source.categories))
        let dest = ClipboardStore(fileURL: nil)
        try dest.addCategory("自己的"); dest.add("甲"); try dest.assign(dest.items[0].id, to: "自己的")
        _ = try dest.importEntries(backup.entries, categories: backup.categories)
        XCTAssertEqual(dest.categories, ["自己的", "空資料夾", "工作"])
        XCTAssertEqual(dest.items[0].category, "自己的")
        let empty = try ClipboardArchive.decodeContents(ClipboardArchive.encode([], categories: ["只有分類"]))
        XCTAssertEqual(empty.categories, ["只有分類"])
        XCTAssertEqual(try ClipboardArchive.decode(Data(#"{"format":"nuonuo-clipboard","version":1,"items":[{"text":"舊備份"}]}"#.utf8))[0].category, nil)
    }
    func testInvalidNamesAndFailedWriteLeaveMemoryUntouched() throws {
        let store = ClipboardStore(fileURL: nil)
        try store.addCategory("好")
        for name in ["好", "  ", "換\n行", String(repeating: "字", count: 41)] {
            XCTAssertThrowsError(try store.addCategory(name))
        }
        XCTAssertEqual(store.categories, ["好"])
        XCTAssertThrowsError(try store.importEntries([.init(text: "不能加入", category: "")]))
        XCTAssertTrue(store.items.isEmpty)
        let bad = ClipboardStore(fileURL: FileManager.default.temporaryDirectory)
        XCTAssertThrowsError(try bad.addCategory("不能儲存"))
        XCTAssertTrue(bad.categories.isEmpty)
    }
}
