package com.startown.starkeyboard.core
import org.json.JSONArray
import org.json.JSONObject

object ClipboardArchive {
    const val MAX_BYTES = 2 * 1024 * 1024
    const val MAX_ENTRIES = 1000
    data class Entry(val text: String, val pinned: Boolean = false)
    fun encode(items: List<ClipItem>): ByteArray {
        validate(items.map { Entry(it.text, it.pinned) })
        val array = JSONArray()
        items.forEach { array.put(JSONObject().put("text", it.text).put("pinned", it.pinned)) }
        return JSONObject().put("format", "nuonuo-clipboard").put("version", 1).put("items", array)
            .toString(2).toByteArray(Charsets.UTF_8).also { require(it.size <= MAX_BYTES) { "檔案超過 2 MB，請先分成較小的檔案。" } }
    }
    fun decode(data: ByteArray, plainText: Boolean = false): List<Entry> {
        require(data.size <= MAX_BYTES) { "檔案超過 2 MB。" }
        val text = Charsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(data)).toString().removePrefix("\uFEFF")
        if (plainText) return textEntries(text, true)
        val trimmed = text.trim()
        val array = if (trimmed.startsWith("[")) JSONArray(trimmed) else {
            val document = JSONObject(trimmed)
            if (document.has("format")) {
                require(document.getString("format") == "nuonuo-clipboard") { "無法辨識備份格式。" }
                require(document.optInt("version") == 1) { "請先更新糯糯鍵盤再匯入這份備份。" }
            }
            document.getJSONArray("items")
        }
        require(array.length() <= MAX_ENTRIES) { "一次最多匯入 1,000 筆。" }
        return validate((0 until array.length()).map {
            when (val row = array.get(it)) {
                is String -> Entry(row)
                is JSONObject -> {
                    val value = if (row.has("text")) row.get("text") else row.get("content")
                    require(value is String) { "文字欄位格式不正確。" }
                    Entry(value, row.opt("pinned") == true)
                }
                else -> error("無法辨識項目，請使用 text 或 content 文字欄位。")
            }
        })
    }
    fun textEntries(text: String, splitLines: Boolean): List<Entry> {
        require(text.toByteArray(Charsets.UTF_8).size <= MAX_BYTES) { "文字超過 2 MB。" }
        val clean = text.removePrefix("\uFEFF")
        return validate((if (splitLines) clean.lines() else listOf(clean)).map { Entry(it) })
    }
    private fun validate(items: List<Entry>): List<Entry> {
        require(items.size <= MAX_ENTRIES) { "一次最多匯入 1,000 筆。" }
        require(items.all { it.text.codePointCount(0, it.text.length) <= ClipboardStore.MAX_TEXT }) { "有一筆超過 20,000 字。" }
        return items.filter { it.text.isNotBlank() }.also { require(it.isNotEmpty()) { "沒有可匯入的文字。" } }
    }
}
