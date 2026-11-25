import Foundation

enum ClipboardPrivacy {
    // These are voluntary producer hints; unmarked secrets cannot be identified reliably.
    static func mayRecord(types: [String]) -> Bool {
        let blocked: Set<String> = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"]
        return blocked.isDisjoint(with: types)
    }
}
