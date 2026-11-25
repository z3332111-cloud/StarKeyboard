import Foundation

/// 每個字的部首（字典裡的 radicals 表，來自 Unicode Unihan）：打注音後用部首找字
enum Radicals {
    static func load(from db: SQLiteDB) -> [Character: String] {
        var map: [Character: String] = [:]
        db.run("SELECT ch, rad FROM radicals") { stmt in
            let ch = SQLiteDB.text(stmt, 0)
            if let c = ch.first, ch.count == 1 { map[c] = SQLiteDB.text(stmt, 1) }
        }
        return map
    }
}
