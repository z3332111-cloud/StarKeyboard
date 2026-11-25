import XCTest
import UIKit

final class KeyboardLayoutDiagnosticsTests: XCTestCase {
    @MainActor
    func testDisabledAndStoppedRecordingDoNotSampleViews() async {
        let diagnostics = KeyboardLayoutDiagnostics()
        XCTAssertNil(diagnostics.report())
        var samples = 0
        diagnostics.start { samples += 1; return "geometry" }
        diagnostics.stop()
        let afterStop = samples
        diagnostics.record("layout", force: true)
        XCTAssertNotNil(diagnostics.report())
        XCTAssertEqual(samples, afterStop)
    }

    @MainActor
    func testRepeatedLayoutIsDeduplicatedButLifecycleEventsAreKept() async {
        let diagnostics = KeyboardLayoutDiagnostics()
        diagnostics.start { "unchanged geometry" }
        for _ in 0..<100 { diagnostics.record("layout") }
        diagnostics.record("appear", force: true)
        diagnostics.stop()
        let report = diagnostics.report() ?? ""
        XCTAssertFalse(report.contains(" layout\n"))
        XCTAssertTrue(report.contains(" appear\n"))
        XCTAssertTrue(report.contains(" stop\n"))
    }

    @MainActor
    func testHistoryIsBoundedWhileBaselineIsRetainedAndRestartClearsIt() async {
        let diagnostics = KeyboardLayoutDiagnostics()
        var state = "original-baseline"
        diagnostics.start { state }
        for index in 0..<200 {
            state = "geometry-\(index)"
            diagnostics.record("layout")
        }
        diagnostics.stop()
        let report = diagnostics.report() ?? ""
        XCTAssertTrue(report.contains("original-baseline"))
        XCTAssertFalse(report.contains("\ngeometry-0\n"))
        XCTAssertTrue(report.contains("geometry-199"))
        XCTAssertEqual(report.components(separatedBy: "\n+").count - 1, 160)
        diagnostics.start { "new-baseline" }
        diagnostics.stop()
        XCTAssertFalse((diagnostics.report() ?? "").contains("original-baseline"))
    }
}
