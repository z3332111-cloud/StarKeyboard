import Foundation
#if canImport(Translation) && compiler(>=6.2)
import Translation
#endif

/// 翻譯：先試 iPhone 內建的翻譯（iOS 26 起、要先下載語言），不行就用網路翻譯（MyMemory，免費、不用帳號）
enum Translator {
    struct Language: Equatable {
        let code: String
        let name: String
    }

    static let targets: [Language] = [
        Language(code: "en", name: "英文"),
        Language(code: "ja", name: "日文"),
        Language(code: "ko", name: "韓文"),
        Language(code: "zh-TW", name: "繁中"),
        Language(code: "zh-CN", name: "簡中"),
        Language(code: "fr", name: "法文"),
        Language(code: "de", name: "德文"),
        Language(code: "es", name: "西班牙文"),
        Language(code: "it", name: "義大利文"),
        Language(code: "th", name: "泰文"),
        Language(code: "vi", name: "越南文"),
        Language(code: "id", name: "印尼文"),
    ]

    enum Failure: Error {
        case message(String)
    }

    /// 粗略判斷原文語言
    static func detectSource(_ text: String) -> String {
        var han = 0, kana = 0, hangul = 0, latin = 0
        for s in text.unicodeScalars {
            switch s.value {
            case 0x3040...0x30FF: kana += 1
            case 0xAC00...0xD7A3, 0x3131...0x318E: hangul += 1
            case 0x4E00...0x9FFF, 0x3400...0x4DBF: han += 1
            case 0x41...0x5A, 0x61...0x7A: latin += 1
            default: break
            }
        }
        if kana > 0 { return "ja" }
        if hangul > 0 { return "ko" }
        if han > 0 { return "zh-TW" }
        return latin > 0 ? "en" : "zh-TW"
    }

    /// from：原文語言；"auto" 或 nil 就自己猜
    static func translate(_ text: String, from chosen: String? = nil, to target: String, allowOnline: Bool = false, completion: @escaping (Result<String, Failure>) -> Void) {
        let picked = chosen.flatMap { $0 == "auto" ? nil : $0 }
        var source = picked ?? detectSource(text)
        if picked == nil && source == target {
            source = target == "en" ? "zh-TW" : "en"
        }
        Task {
            if let local = await translateOnDevice(text, from: source, to: target) {
                await MainActor.run { completion(.success(local)) }
                return
            }
            guard allowOnline else {
                await MainActor.run { completion(.failure(.message("本機翻譯目前不可用；如需外部服務，請先到 ⚙ 隱私與安全開啟網路翻譯"))) }
                return
            }
            translateOnline(text, from: source, to: target) { result in
                DispatchQueue.main.async { completion(result) }
            }
        }
    }

    private static func translateOnDevice(_ text: String, from source: String, to target: String) async -> String? {
        #if canImport(Translation) && compiler(>=6.2)
        if #available(iOS 26.0, *) {
            do {
                let session = TranslationSession(installedSource: Locale.Language(identifier: source),
                                                 target: Locale.Language(identifier: target))
                let response = try await session.translate(text)
                return response.targetText
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    private static func translateOnline(_ text: String, from source: String, to target: String,
                                        completion: @escaping (Result<String, Failure>) -> Void) {
        var components = URLComponents(string: "https://api.mymemory.translated.net/get")!
        components.queryItems = [
            URLQueryItem(name: "q", value: String(text.prefix(450))),
            URLQueryItem(name: "langpair", value: "\(source)|\(target)"),
        ]
        guard let url = components.url else {
            completion(.failure(.message("網址錯誤")))
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        URLSession.shared.dataTask(with: request) { data, _, error in
            if error != nil {
                completion(.failure(.message("連不上翻譯服務（要開「允許完整取用」和網路）")))
                return
            }
            // 這個服務有時把狀態碼給成數字、有時給成文字
            struct Status: Decodable {
                let code: Int
                init(from decoder: Decoder) throws {
                    let c = try decoder.singleValueContainer()
                    if let n = try? c.decode(Int.self) { code = n } else { code = Int(try c.decode(String.self)) ?? 0 }
                }
            }
            struct Reply: Decodable {
                struct DataPart: Decodable { let translatedText: String }
                let responseData: DataPart
                let responseStatus: Status
            }
            guard let data = data, let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
                completion(.failure(.message("翻譯服務回傳看不懂的資料")))
                return
            }
            guard reply.responseStatus.code == 200 else {
                completion(.failure(.message("翻譯失敗：\(reply.responseData.translatedText)")))
                return
            }
            completion(.success(reply.responseData.translatedText))
        }.resume()
    }
}
