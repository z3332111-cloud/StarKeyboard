import Foundation
import Darwin

/// 當掉紀錄：鍵盤被 iOS 關掉（通常是記憶體超過）時沒有機會留下訊息，所以平常就記幾個小足跡
/// （做了什麼、當時用了多少記憶體），下次打開時發現上次沒有正常收起來，就把那串足跡留著給使用者複製。
/// 只記動作名稱和記憶體，不記打的字。
enum CrashTrail {
    private static let trailKey = "crashTrail"
    private static let aliveKey = "crashTrailAlive"
    private static let lastKey = "crashTrailLast"
    private static let d = UserDefaults.standard

    /// 現在鍵盤用了多少記憶體（MB）；iPhone 給鍵盤的上限大約 60～70MB
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    /// 記一個足跡（最多留 40 筆）
    static func mark(_ event: String) {
        let time = Date()
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        let line = "\(f.string(from: time)) \(String(format: "%.1f", footprintMB()))MB \(event)"
        var list = d.stringArray(forKey: trailKey) ?? []
        list.append(line)
        if list.count > 40 { list.removeFirst(list.count - 40) }
        d.set(list, forKey: trailKey)
    }

    /// 鍵盤一開始：上次沒有正常收起來，就把上次的足跡存成「當掉紀錄」，回傳 true
    @discardableResult
    static func start() -> Bool {
        let crashed = d.bool(forKey: aliveKey)
        if crashed, let list = d.stringArray(forKey: trailKey), !list.isEmpty {
            d.set(list, forKey: lastKey)
        }
        d.set([String](), forKey: trailKey)
        d.set(true, forKey: aliveKey)
        mark("開啟")
        return crashed
    }

    /// 鍵盤正常收起來
    static func finish() {
        mark("收起")
        d.set(false, forKey: aliveKey)
    }

    /// 給使用者複製的當掉紀錄（沒有就是 nil）
    static var lastReport: String? {
        guard let list = d.stringArray(forKey: lastKey), !list.isEmpty else { return nil }
        return list.joined(separator: "\n")
    }
}
