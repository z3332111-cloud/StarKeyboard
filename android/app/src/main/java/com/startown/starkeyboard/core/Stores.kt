package com.startown.starkeyboard.core

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

data class ClipItem(val id: String, val text: String, var pinned: Boolean, var date: Long, var category: String? = null)

/** 剪貼簿紀錄：新的在前面，釘選的不會被自動刪掉 */
class ClipboardStore(private val file: File?, limit: Int = 200) {
    companion object {
        const val MAX_TEXT = 20000
    }

    val items = ArrayList<ClipItem>()
    val categories = ArrayList<String>()
    var limit = limit
        set(value) {
            field = value
            trim()
            save()
        }

    init {
        load()
    }

    fun load() {
        items.clear(); categories.clear()
        val f = file?.takeIf { it.exists() } ?: return
        runCatching {
            val raw = f.readText().trim()
            val doc = if (raw.startsWith("[")) null else JSONObject(raw)
            val arr = doc?.getJSONArray("items") ?: JSONArray(raw)
            doc?.optJSONArray("categories")?.let { names ->
                categories.addAll(ClipboardArchive.validateCategories((0 until names.length()).map { names.getString(it) }))
            }
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                items.add(ClipItem(o.getString("id"), o.getString("text"), o.optBoolean("pinned"), o.optLong("date"), if (o.isNull("category")) null else o.getString("category")))
            }
        }
    }

    /** 釘選的在最上面，其餘照時間 */
    val ordered get() = items.filter { it.pinned } + items.filter { !it.pinned }

    fun add(text: String, date: Long = System.currentTimeMillis()): Boolean {
        if (text.isBlank()) return false
        val stored = if (text.length > MAX_TEXT) text.substring(0, MAX_TEXT) else text
        val i = items.indexOfFirst { it.text == stored }
        if (i >= 0) {
            val item = items.removeAt(i)
            item.date = date
            items.add(0, item)
        } else {
            items.add(0, ClipItem(UUID.randomUUID().toString(), stored, false, date))
        }
        trim()
        save()
        return true
    }

    data class ImportResult(val added: Int, val duplicates: Int, val skipped: Int)

    fun importEntries(entries: List<ClipboardArchive.Entry>, incomingCategories: List<String> = emptyList()): ImportResult {
        val names = ClipboardArchive.validateCategories(categories + incomingCategories + entries.mapNotNull { it.category })
        require(entries.size <= ClipboardArchive.MAX_ENTRIES) { "最多一次匯入 1,000 筆。" }
        require(entries.all { it.text.codePointCount(0, it.text.length) <= MAX_TEXT }) { "單筆文字太長。" }
        val existing = items.map { it.copy() }
        val unique = LinkedHashMap<String, ClipboardArchive.Entry>()
        var duplicates = 0
        for (entry in entries.filter { it.text.isNotBlank() }) {
            val old = existing.find { it.text == entry.text }
            val pending = unique[entry.text]
            if (old != null) {
                old.pinned = old.pinned || entry.pinned
                if (old.category == null) old.category = entry.category
                duplicates++
            } else if (pending != null) {
                unique[entry.text] = pending.copy(pinned = pending.pinned || entry.pinned, category = pending.category ?: entry.category)
                duplicates++
            } else unique[entry.text] = entry
        }
        var capacity = maxOf(0, limit - existing.count { !it.pinned && it.category == null })
        var skipped = 0
        val added = ArrayList<ClipItem>()
        for (entry in unique.values) {
            if (!entry.pinned && entry.category == null && capacity <= 0) { skipped++; continue }
            if (!entry.pinned && entry.category == null) capacity--
            added.add(ClipItem(UUID.randomUUID().toString(), entry.text, entry.pinned, System.currentTimeMillis(), entry.category))
        }
        val merged = added + existing
        commitFolders(merged, names)
        return ImportResult(added.size, duplicates, skipped)
    }

    /** 改已存的文字。取消編輯時不要呼叫。空白不會覆蓋原本的內容。 */
    fun updateText(id: String, text: String): Boolean {
        val stored = if (text.length > MAX_TEXT) text.substring(0, MAX_TEXT) else text
        if (stored.isBlank()) return false
        val i = items.indexOfFirst { it.id == id }
        if (i < 0) return false
        items[i] = items[i].copy(text = stored)
        save()
        return true
    }

    fun togglePin(id: String) {
        items.find { it.id == id }?.let { it.pinned = !it.pinned }
        save()
    }

    fun remove(id: String) {
        items.removeAll { it.id == id }
        save()
    }

    fun clearUnpinned() {
        items.removeAll { !it.pinned && it.category == null }
        save()
    }

    private fun trim() {
        var unpinned = 0
        items.retainAll { it.pinned || it.category != null || ++unpinned <= limit }
    }

    fun addCategory(raw: String) {
        val name = raw.trim()
        require(name !in categories) { "已有同名分類，請換個名稱。" }
        commitFolders(items, ClipboardArchive.validateCategories(categories + name))
    }
    fun renameCategory(old: String, raw: String) {
        val name = raw.trim()
        require(old in categories && (name == old || name !in categories)) { "分類不存在或名稱重複。" }
        commitFolders(items.map { if (it.category == old) it.copy(category = name) else it },
            ClipboardArchive.validateCategories(categories.map { if (it == old) name else it }))
    }
    fun deleteCategory(name: String) {
        commitFolders(items.map { if (it.category == name) it.copy(category = null) else it }, categories.filter { it != name })
    }
    fun assign(id: String, category: String?) {
        require(category == null || category in categories) { "分類不存在。" }
        commitFolders(items.map { if (it.id == id) it.copy(category = category) else it }, categories)
    }
    private fun commitFolders(changed: List<ClipItem>, names: List<String>) {
        // Copy before clearing: callers may pass the live lists.
        val next = changed.toList(); val folders = names.toList()
        persist(next, folders)
        items.clear(); items.addAll(next)
        categories.clear(); categories.addAll(folders)
    }
    private fun persist(changed: List<ClipItem>, names: List<String>) {
        val target = file ?: return
        val arr = JSONArray()
        changed.forEach { arr.put(JSONObject().put("id", it.id).put("text", it.text).put("pinned", it.pinned)
            .put("date", it.date).put("category", it.category ?: JSONObject.NULL)) }
        val document = JSONObject().put("items", arr).put("categories", JSONArray(names))
        val temp = File.createTempFile("clipboard-", ".tmp", target.absoluteFile.parentFile)
        try {
            temp.writeText(document.toString())
            java.nio.file.Files.move(temp.toPath(), target.toPath(), java.nio.file.StandardCopyOption.ATOMIC_MOVE,
                java.nio.file.StandardCopyOption.REPLACE_EXISTING)
        } finally { temp.delete() }
    }
    private fun save() { persist(items, categories) }

}

/** 我的表符、自製貼圖、最近使用 */
class EmoticonStore(private val directory: File?) {
    companion object {
        val DEFAULT_CUSTOM = listOf("(๑•̀ㅂ•́)و✧", "ʕ•ᴥ•ʔ", "✿♡✿", "(｡･ω･｡)ﾉ♡")
    }

    val custom = ArrayList<String>()
    val stickers = ArrayList<String>()   // stickers 資料夾裡的檔名
    private val recents = HashMap<String, MutableList<String>>()
    private val file get() = directory?.let { File(it, "emoticons.json") }
    val stickerDirectory get() = directory?.let { File(it, "stickers") }

    init {
        load()
    }

    fun load() {
        custom.clear(); stickers.clear(); recents.clear()
        val f = file?.takeIf { it.exists() }
        if (f == null) {
            custom.addAll(DEFAULT_CUSTOM)
            return
        }
        runCatching {
            val o = JSONObject(f.readText())
            o.optJSONArray("custom")?.let { a -> for (i in 0 until a.length()) custom.add(a.getString(i)) }
            o.optJSONArray("stickers")?.let { a -> for (i in 0 until a.length()) stickers.add(a.getString(i)) }
            o.optJSONObject("recents")?.let { r ->
                for (key in r.keys()) {
                    val a = r.getJSONArray(key)
                    recents[key] = MutableList(a.length()) { a.getString(it) }
                }
            }
        }
    }

    fun addCustom(text: String) {
        val t = text.trim()
        if (t.isEmpty()) return
        custom.remove(t)
        custom.add(0, t)
        save()
    }

    fun removeCustom(text: String) {
        custom.remove(text)
        save()
    }

    /** 存一張貼圖，回傳檔名 */
    fun addSticker(png: ByteArray): String? {
        val dir = stickerDirectory ?: return null
        dir.mkdirs()
        val name = UUID.randomUUID().toString() + ".png"
        runCatching { File(dir, name).writeBytes(png) }.onFailure { return null }
        stickers.add(0, name)
        save()
        return name
    }

    fun stickerFile(name: String) = stickerDirectory?.let { File(it, name) }

    fun removeSticker(name: String) {
        stickerFile(name)?.delete()
        stickers.remove(name)
        save()
    }

    fun recents(kind: String): List<String> = recents[kind] ?: emptyList()

    fun pushRecent(text: String, kind: String, limit: Int = 40) {
        val list = recents.getOrPut(kind) { ArrayList() }
        list.remove(text)
        list.add(0, text)
        while (list.size > limit) list.removeAt(list.size - 1)
        save()
    }

    private fun save() {
        val f = file ?: return
        val r = JSONObject()
        for ((k, v) in recents) r.put(k, JSONArray(v))
        f.writeText(JSONObject().put("custom", JSONArray(custom)).put("stickers", JSONArray(stickers)).put("recents", r).toString())
    }
}

/** GitHub 上的 Android 版（標籤 android-12） */
data class ReleaseInfo(val build: Int, val title: String, val notes: String, val apkUrl: String?, val pageUrl: String)

object ReleaseChecker {
    const val API = "https://api.github.com/repos/z3332111-cloud/StarKeyboard/releases?per_page=30"
    const val PAGE = "https://github.com/z3332111-cloud/StarKeyboard/releases"

    fun buildNumber(tag: String): Int? = if (tag.startsWith("android-")) tag.removePrefix("android-").toIntOrNull() else null

    /** 從發佈清單裡找最新的 Android 版 */
    fun parseLatest(json: String): ReleaseInfo? {
        val arr = runCatching { JSONArray(json) }.getOrNull() ?: return null
        var best: ReleaseInfo? = null
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            val build = buildNumber(o.optString("tag_name")) ?: continue
            if (best != null && best.build >= build) continue
            var apk: String? = null
            o.optJSONArray("assets")?.let { a ->
                for (j in 0 until a.length()) {
                    val asset = a.getJSONObject(j)
                    if (asset.optString("name").endsWith(".apk")) apk = asset.optString("browser_download_url")
                }
            }
            best = ReleaseInfo(build, o.optString("name", "糯糯鍵盤 Android 更新"), o.optString("body"), apk, o.optString("html_url", PAGE))
        }
        return best
    }
}
