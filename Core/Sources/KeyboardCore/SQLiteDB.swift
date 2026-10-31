import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// 很小的 SQLite 包裝：只做查詢和插入，查詢語句會快取起來重複用
final class SQLiteDB {
    enum Value {
        case text(String)
        case double(Double)
        case int(Int)
    }

    private var db: OpaquePointer?
    private var statements: [String: OpaquePointer] = [:]
    /// 同一個連線不能兩個執行緒同時用（選字在背景、繁簡轉換在畫面上）：一次只讓一個查
    private let lock = NSRecursiveLock()

    init?(path: String, readOnly: Bool = true) {
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        if sqlite3_open_v2(path, &db, flags, nil) != SQLITE_OK {
            sqlite3_close(db)
            return nil
        }
        // SQLite 自己的暫存最多 1MB（預設會更大，鍵盤記憶體很少）
        sqlite3_exec(db, "PRAGMA cache_size = -1024", nil, nil, nil)
    }

    static func inMemory() -> SQLiteDB? {
        SQLiteDB(path: ":memory:", readOnly: false)
    }

    deinit {
        for (_, stmt) in statements { sqlite3_finalize(stmt) }
        sqlite3_close(db)
    }

    @discardableResult
    func execute(_ sql: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    func run(_ sql: String, _ args: [Value] = [], row: ((OpaquePointer) -> Void)? = nil) {
        lock.lock()
        defer { lock.unlock() }
        guard let stmt = prepare(sql) else { return }
        defer {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
        }
        for (i, arg) in args.enumerated() {
            let index = Int32(i + 1)
            switch arg {
            case .text(let s): sqlite3_bind_text(stmt, index, s, -1, SQLITE_TRANSIENT)
            case .double(let d): sqlite3_bind_double(stmt, index, d)
            case .int(let n): sqlite3_bind_int64(stmt, index, Int64(n))
            }
        }
        while sqlite3_step(stmt) == SQLITE_ROW {
            row?(stmt)
        }
    }

    static func text(_ stmt: OpaquePointer, _ column: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, column) else { return "" }
        return String(cString: c)
    }

    static func double(_ stmt: OpaquePointer, _ column: Int32) -> Double {
        sqlite3_column_double(stmt, column)
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        if let stmt = statements[sql] { return stmt }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else { return nil }
        statements[sql] = s
        return s
    }
}
