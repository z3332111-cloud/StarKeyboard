import UIKit

/// 使用者手動開啟的版面追蹤。只留在記憶體，最多 160 筆；不讀取輸入內容。
/// 只觀察公開的 UIView 幾何資料，不修改系統容器或重新設定高度。
final class KeyboardLayoutDiagnostics {
    private(set) var isRecording = false
    private var entries: [String] = []
    private var baseline = ""
    private var lastSnapshot = ""
    private var startedAt: TimeInterval = 0
    private var observers: [NSObjectProtocol] = []
    private var snapshot: (() -> String)?
    private var discarded = 0
    private let capacity = 160

    deinit { removeObservers() }

    func start(snapshot: @escaping () -> String) {
        removeObservers()
        self.snapshot = snapshot
        entries.removeAll(keepingCapacity: true)
        lastSnapshot = ""
        discarded = 0
        startedAt = ProcessInfo.processInfo.systemUptime
        isRecording = true
        baseline = snapshot()
        record("start", force: true)
        // Extension 不保證收到宿主 App 的前景通知；缺少事件不代表沒有切換 App。
        let events: [(Notification.Name, String)] = [
            (UIApplication.willEnterForegroundNotification, "application.willEnterForeground"),
            (UIApplication.didBecomeActiveNotification, "application.didBecomeActive"),
            (UIApplication.willResignActiveNotification, "application.willResignActive"),
            (UIApplication.didEnterBackgroundNotification, "application.didEnterBackground"),
            (UIScene.willEnterForegroundNotification, "scene.willEnterForeground"),
            (UIScene.didActivateNotification, "scene.didActivate"),
            (UIScene.willDeactivateNotification, "scene.willDeactivate"),
            (UIScene.didEnterBackgroundNotification, "scene.didEnterBackground"),
            (UIResponder.keyboardWillChangeFrameNotification, "keyboard.willChangeFrame"),
            (UIResponder.keyboardDidChangeFrameNotification, "keyboard.didChangeFrame"),
            (UIResponder.keyboardDidHideNotification, "keyboard.didHide"),
        ]
        for (name, label) in events {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                var event = label
                if let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
                    event += " endFrame(screen)=\(Self.rect(end.cgRectValue))"
                }
                self?.record(event, force: true)
            })
        }
    }

    func stop() {
        record("stop", force: true)
        isRecording = false
        snapshot = nil
        removeObservers()
    }

    func record(_ event: String, force: Bool = false) {
        guard isRecording, let snapshot else { return }
        let state = snapshot()
        guard force || state != lastSnapshot else { return }
        lastSnapshot = state
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        entries.append(String(format: "+%.3fs ", elapsed) + event + "\n" + state)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
            discarded += 1
        }
    }

    func report() -> String? {
        guard !entries.isEmpty else { return nil }
        record("export", force: true)
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return """
        Keyboard layout diagnostics v1
        Exported: \(ISO8601DateFormatter().string(from: Date()))
        iOS: \(UIDevice.current.systemVersion); app: \(version) (\(build))
        Recording: \(isRecording); older entries discarded: \(discarded)
        Geometry only. No typed text or clipboard contents.
        Ancestors are numbered public UIView geometry, not identified system keyboard parts.
        Missing lifecycle notifications do not prove the host app stayed active.
        Baseline (retained even if older entries are discarded):
        \(baseline)

        \(entries.joined(separator: "\n\n"))
        """
    }

    private func removeObservers() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
    }

    static func rect(_ value: CGRect) -> String {
        String(format: "(%.2f,%.2f,%.2f,%.2f)", Double(value.origin.x), Double(value.origin.y),
               Double(value.width), Double(value.height))
    }

    static func geometry(_ name: String, _ view: UIView) -> String {
        let insets = view.safeAreaInsets
        var result = "\(name) frame=\(rect(view.frame)) bounds=\(rect(view.bounds))"
        result += String(format: " safeArea=(%.2f,%.2f,%.2f,%.2f)",
                         Double(insets.top), Double(insets.left), Double(insets.bottom), Double(insets.right))
        if let window = view.window {
            let windowRect = view.convert(view.bounds, to: window)
            result += " inWindow=\(rect(windowRect))"
            result += " inScreen=\(rect(window.convert(windowRect, to: window.screen.coordinateSpace)))"
        }
        if let presentation = view.layer.presentation() {
            result += " presentationFrame=\(rect(presentation.frame))"
        }
        return result
    }
}
