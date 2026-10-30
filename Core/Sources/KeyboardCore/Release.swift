import Foundation

/// GitHub 上最新的一版
struct ReleaseInfo: Equatable {
    let build: Int
    let title: String
    let notes: String
    let url: URL
}

/// 檢查有沒有新版（App 和鍵盤都會用）
enum ReleaseChecker {
    static let apiURL = URL(string: "https://api.github.com/repos/z3332111-cloud/StarKeyboard/releases/latest")!
    static let downloadPage = URL(string: "https://github.com/z3332111-cloud/StarKeyboard/releases/latest")!

    /// 雲端打包時把第幾版寫進 CFBundleVersion；自己在電腦上編的是 1
    static var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0" }

    static var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    /// 版本標籤長這樣：build-12
    static func buildNumber(fromTag tag: String) -> Int? {
        guard tag.hasPrefix("build-") else { return nil }
        return Int(tag.dropFirst("build-".count))
    }

    static func parse(_ data: Data) -> ReleaseInfo? {
        struct Reply: Decodable {
            let tag_name: String
            let name: String?
            let body: String?
            let html_url: String
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data),
              let build = buildNumber(fromTag: reply.tag_name),
              let url = URL(string: reply.html_url) else { return nil }
        return ReleaseInfo(build: build, title: reply.name ?? "糯糯鍵盤更新", notes: reply.body ?? "", url: url)
    }

    static func fetchLatest(completion: @escaping (ReleaseInfo?) -> Void) {
        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let info = data.flatMap { parse($0) }
            DispatchQueue.main.async { completion(info) }
        }.resume()
    }
}
