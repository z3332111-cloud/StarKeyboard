package com.startown.starkeyboard.ime

/** 打完「開心」「謝謝」這類詞，選字列順便推薦表情符號（和 iPhone 版 Core/Sources/KeyboardCore/EmojiSuggestions.swift 同一份表） */
object EmojiSuggestions {
    private val table = listOf(
        "生日快樂" to listOf("🎂", "🎉"), "新年快樂" to listOf("🧧", "🎊"), "聖誕快樂" to listOf("🎄", "🎅"), "恭喜" to listOf("🎉", "👏"),
        "哈哈" to listOf("😂", "🤣"), "好笑" to listOf("🤣", "😆"), "笑死" to listOf("🤣", "😂"), "開心" to listOf("😊", "🥰"), "快樂" to listOf("😄", "🎉"),
        "謝謝" to listOf("🙏", "🥰"), "感謝" to listOf("🙏", "🙇"), "對不起" to listOf("🙇", "🥺"), "抱歉" to listOf("🙇", "🥺"), "不好意思" to listOf("🙇", "😅"),
        "愛你" to listOf("❤️", "😘"), "喜歡" to listOf("😍", "❤️"), "想你" to listOf("🥺", "💕"), "抱抱" to listOf("🤗", "💕"), "親親" to listOf("😘", "💋"),
        "早安" to listOf("☀️", "😊"), "午安" to listOf("🌞", "😊"), "晚安" to listOf("🌙", "😴"), "睡覺" to listOf("😴", "💤"), "好累" to listOf("😩", "😪"),
        "難過" to listOf("😢", "🥺"), "傷心" to listOf("😭", "💔"), "哭" to listOf("😭", "🥲"), "生氣" to listOf("😡", "😤"), "好氣" to listOf("😤", "😡"),
        "可愛" to listOf("🥰", "😍"), "好吃" to listOf("😋", "🤤"), "餓" to listOf("🤤", "🍚"), "吃飯" to listOf("🍚", "😋"), "喝水" to listOf("💧", "🥤"),
        "加油" to listOf("💪", "🔥"), "讚" to listOf("👍", "✨"), "厲害" to listOf("👍", "😲"), "好棒" to listOf("👏", "✨"), "太棒" to listOf("🎉", "👏"),
        "拜拜" to listOf("👋", "😊"), "掰掰" to listOf("👋", "😊"), "再見" to listOf("👋", "😊"), "好的" to listOf("👌", "😊"), "好喔" to listOf("👌", "😊"),
        "真的假的" to listOf("😳", "🤯"), "天啊" to listOf("😱", "😳"), "嚇死" to listOf("😱", "😨"), "害羞" to listOf("😳", "☺️"), "尷尬" to listOf("😅", "🫠"),
        "下雨" to listOf("☔", "🌧️"), "好冷" to listOf("🥶", "❄️"), "好熱" to listOf("🥵", "☀️"), "貓" to listOf("🐱", "😺"), "狗" to listOf("🐶", "🐕"),
    )

    /** 前面打的字結尾符合表裡的詞就給表情（長的詞優先），最多兩個 */
    fun after(text: String): List<String> {
        val tail = text.trim()
        if (tail.isEmpty()) return emptyList()
        return table.filter { tail.endsWith(it.first) }.maxByOrNull { it.first.length }?.second ?: emptyList()
    }
}
