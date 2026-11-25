import XCTest
@testable import KeyboardCore

final class PrivacyTests: XCTestCase {
    func testSensitiveMarkerOverridesOrdinaryText() {
        XCTAssertFalse(ClipboardPrivacy.mayRecord(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        XCTAssertFalse(ClipboardPrivacy.mayRecord(types: ["org.nspasteboard.TransientType", "public.text"]))
        XCTAssertTrue(ClipboardPrivacy.mayRecord(types: ["public.utf8-plain-text"]))
    }

    func testProtectedJSONStillPersistsAndUpdates() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("clipboard.json")
        JSONFile.save(["first"], to: url)
        XCTAssertEqual(JSONFile.load([String].self, from: url), ["first"])
        JSONFile.save(["replacement"], to: url)
        XCTAssertEqual(JSONFile.load([String].self, from: url), ["replacement"])
        #if os(iOS)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual(attributes[.protectionKey] as? FileProtectionType, .complete)
        XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        #endif
    }
}
