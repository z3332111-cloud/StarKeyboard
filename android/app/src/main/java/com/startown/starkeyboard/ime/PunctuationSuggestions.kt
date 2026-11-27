package com.startown.starkeyboard.ime

/** 打完字後選字列最前面放的標點（和 iPhone 版 Core/Sources/KeyboardCore/PunctuationSuggestions.swift 一樣） */
object PunctuationSuggestions {
    val marks = setOf("，", "。", "？", "！", "、", "～")

    private val boundaries = "，。？！!?；;\n".toSet()
    private val endings = listOf("嗎", "呢", "麼", "嘛", "誰", "哪", "幾", "啥", "否", "吗", "么", "谁", "几")
    private val questions = listOf("什麼", "怎麼", "為什麼", "多少", "是不是", "對不對", "好不好", "要不要", "可不可以", "有沒有", "哪裡", "幾點",
        "什么", "怎么", "为什么", "对不对", "有没有", "哪里", "几点")

    /** 看前面打的字決定標點的順序：問句「？」排第一個 */
    fun after(text: String): List<String> {
        val clause = text.takeLast(40).reversed().takeWhile { it !in boundaries }.reversed().trim()
        if (clause.isEmpty()) return emptyList()
        val isQuestion = endings.any { clause.endsWith(it) } || questions.any { clause.contains(it) }
        return if (isQuestion) listOf("？", "，", "。", "！", "、") else listOf("，", "。", "？", "！", "、")
    }
}
