import XCTest
@testable import KeyboardCore

final class ClipboardArchiveTests: XCTestCase {
    func testRoundTripPreservesMultilinePinsAndOrder() throws {
        let items = [ClipItem(id: UUID(), text: "第一行\n第二行😀", pinned: true, date: Date()),
                     ClipItem(id: UUID(), text: "  保留空白  ", pinned: false, date: Date())]
        let decoded = try ClipboardArchive.decode(ClipboardArchive.encode(items))
        XCTAssertEqual(decoded.map { $0.text }, items.map { $0.text })
        XCTAssertEqual(decoded.map { $0.pinned }, [true, false])
    }
    func testCompatibleImportsAndStrictJSONErrors() throws {
        XCTAssertEqual(try ClipboardArchive.decode(Data(#"["你好", {"content":"世界","pinned":true}]"#.utf8)).count, 2)
        XCTAssertEqual(try ClipboardArchive.decode(Data("甲\r\n乙\n\n".utf8), plainText: true).map { $0.text }, ["甲", "乙"])
        XCTAssertEqual(try ClipboardArchive.textEntries("甲\n乙", splitLines: false).map { $0.text }, ["甲\n乙"])
        for input in [#"{"format":"nuonuo-clipboard","version":2,"items":[]}"#, #"[{"secret":"x"}]"#, "broken"] {
            XCTAssertThrowsError(try ClipboardArchive.decode(Data(input.utf8)))
        }
        XCTAssertThrowsError(try ClipboardArchive.decode(Data(repeating: 65, count: ClipboardArchive.maxBytes + 1)))
        XCTAssertThrowsError(try ClipboardArchive.textEntries(String(repeating: "字", count: 20001), splitLines: false))
    }
    func testImportDoesNotEvictExistingAndDeduplicates() throws {
        let store = ClipboardStore(fileURL: nil, limit: 2)
        store.add("原本")
        let result = try store.importEntries([.init(text: "新增"), .init(text: "新增"), .init(text: "超額"), .init(text: "原本")])
        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.duplicates, 2)
        XCTAssertEqual(result.skipped, 1)
        XCTAssertEqual(store.items.map { $0.text }, ["新增", "原本"])
        _ = try store.importEntries([.init(text: "原本", pinned: true)])
        XCTAssertTrue(store.items.first { $0.text == "原本" }!.pinned)
    }
    func testImportPersistsAndFailedWriteDoesNotChangeMemory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("clipboard.json")
        let store = ClipboardStore(fileURL: file)
        _ = try store.importEntries([.init(text: "第一"), .init(text: "第二", pinned: true)])
        XCTAssertEqual(ClipboardStore(fileURL: file).items.map { $0.text }, ["第一", "第二"])
        let bad = ClipboardStore(fileURL: directory)
        XCTAssertThrowsError(try bad.importEntries([.init(text: "不應存入")]))
        XCTAssertTrue(bad.items.isEmpty)
    }
}
