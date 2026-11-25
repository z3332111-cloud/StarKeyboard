import Foundation

enum PunctuationSuggestions {
    static let marks: Set<String> = ["，", "。", "？", "！", "、", "～"]

    static func after(_ text: String) -> [String] {
        let boundaries: Set<Character> = Set("，。？！!?；;\n")
        let clause = String(text.suffix(40).reversed().prefix { !boundaries.contains($0) }.reversed())
            .trimmingCharacters(in: .whitespaces)
        guard !clause.isEmpty else { return [] }
        let endings = ["嗎", "呢", "麼", "嘛", "誰", "哪", "幾", "啥", "否", "吗", "么", "谁", "几"]
        let questions = ["什麼", "怎麼", "為什麼", "多少", "是不是", "對不對", "好不好", "要不要", "可不可以", "有沒有", "哪裡", "幾點", "什么", "怎么", "为什么", "对不对", "有没有", "哪里", "几点"]
        let isQuestion = endings.contains { clause.hasSuffix($0) } || questions.contains { clause.contains($0) }
        return isQuestion ? ["？", "，", "。", "！"] : ["，", "。", "？", "！"]
    }
}
