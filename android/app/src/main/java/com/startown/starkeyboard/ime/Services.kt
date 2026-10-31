package com.startown.starkeyboard.ime

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.os.Handler
import android.os.Looper
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.TranslatorOptions
import com.startown.starkeyboard.core.PhraseSource
import com.startown.starkeyboard.core.ReleaseChecker
import com.startown.starkeyboard.core.ReleaseInfo
import com.startown.starkeyboard.core.Scored
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/** 注音字典：打包時放在 assets，第一次用時複製到手機裡才能用 SQLite 開 */
/// column：注音用 reading（有聲調），拼音用 plain（沒聲調）
class SQLitePhraseSource private constructor(private val db: SQLiteDatabase, private val column: String) : PhraseSource {
    private var exact: Map<String, List<Scored>> = emptyMap()
    private var abbrs: Map<String, List<Triple<String, String, Double>>> = emptyMap()
    private var syllableList: List<String> = emptyList()
    private var byChar: Map<Char, List<String>> = emptyMap()
    private var ready = false

    companion object {
        fun open(context: Context, column: String = "reading"): SQLitePhraseSource? = runCatching {
            val file = File(context.filesDir, "zhuyin.sqlite")
            val stamp = File(context.filesDir, "zhuyin.version")
            val version = BuildInfo.current(context).toString()
            synchronized(this) {
                if (!file.exists() || !stamp.exists() || stamp.readText() != version) {
                    context.assets.open("zhuyin.sqlite").use { input -> file.outputStream().use { input.copyTo(it) } }
                    stamp.writeText(version)
                }
            }
            SQLitePhraseSource(SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READONLY), column).also { it.preload() }
        }.getOrNull()
    }

    /** 整表讀進記憶體。之後每個按鍵不再查 SQLite。字典是小麥注音（MIT）。 */
    fun preload() {
        if (ready) return
        val exactMap = HashMap<String, MutableList<Scored>>()
        val abbrMap = HashMap<String, MutableList<Triple<String, String, Double>>>()
        val plains = HashSet<String>()
        val chars = HashMap<Char, MutableList<String>>()
        db.rawQuery("SELECT reading, plain, abbr, phrase, score FROM phrases ORDER BY score DESC, phrase ASC", null).use { c ->
            while (c.moveToNext()) {
                val reading = c.getString(0) ?: continue
                val plain = c.getString(1) ?: continue
                val abbr = c.getString(2) ?: continue
                val phrase = c.getString(3) ?: continue
                val score = c.getDouble(4)
                val key = if (column == "plain") plain else reading
                val list = exactMap.getOrPut(key) { ArrayList() }
                if (list.size < 80) list.add(Scored(phrase, score))
                abbrMap.getOrPut(abbr) { ArrayList() }.add(Triple(reading, phrase, score))
                if ('-' !in plain) plains.add(plain)
                val head = phrase.firstOrNull()
                if (head != null) {
                    val bucket = chars.getOrPut(head) { ArrayList() }
                    if (bucket.size < 500) bucket.add(phrase)
                }
            }
        }
        exact = exactMap
        abbrs = abbrMap
        syllableList = plains.toList()
        byChar = chars
        ready = true
    }

    override fun lookup(reading: String): List<Scored> {
        if (ready) return exact[reading] ?: emptyList()
        val out = ArrayList<Scored>()
        db.rawQuery("SELECT phrase, score FROM phrases WHERE $column = ? ORDER BY score DESC LIMIT 80", arrayOf(reading)).use { c ->
            while (c.moveToNext()) out.add(Scored(c.getString(0), c.getDouble(1)))
        }
        return out
    }

    override fun byAbbreviation(abbr: String, pattern: String?): List<Triple<String, String, Double>> {
        if (ready) return abbrs[abbr] ?: emptyList()
        val out = ArrayList<Triple<String, String, Double>>()
        runCatching {
            db.rawQuery("SELECT reading, phrase, score FROM phrases WHERE abbr = ? AND $column GLOB ? ORDER BY score DESC LIMIT 400", arrayOf(abbr, pattern ?: "*")).use { c ->
                while (c.moveToNext()) out.add(Triple(c.getString(0), c.getString(1), c.getDouble(2)))
            }
        }
        return out
    }

    override fun syllables(): List<String> {
        if (ready) return syllableList
        val out = ArrayList<String>()
        runCatching {
            db.rawQuery("SELECT DISTINCT plain FROM phrases WHERE plain NOT LIKE '%-%'", null).use { c ->
                while (c.moveToNext()) out.add(c.getString(0))
            }
        }
        return out
    }

    /** 拼音音節 → 沒聲調的注音 */
    fun pinyinTable(): Map<String, String> {
        val map = HashMap<String, String>()
        runCatching {
            db.rawQuery("SELECT py, bpmf FROM pinyin", null).use { c -> while (c.moveToNext()) map[c.getString(0)] = c.getString(1) }
        }
        return map
    }

    /** 繁體 → 簡體（沒有對照就回傳 null） */
    fun simplified(trad: String): String? = runCatching {
        db.rawQuery("SELECT simp FROM t2s WHERE trad = ?", arrayOf(trad)).use { c -> if (c.moveToFirst()) c.getString(0) else null }
    }.getOrNull()

    override fun startingWith(head: String, limit: Int): List<String> {
        if (ready && head.isNotEmpty()) {
            return (byChar[head[0]] ?: emptyList()).filter { it.length > head.length && it.startsWith(head) }.distinct().take(limit)
        }
        val out = ArrayList<String>()
        db.rawQuery(
            "SELECT phrase, MAX(score) AS s FROM phrases WHERE phrase > ? AND phrase < ? GROUP BY phrase ORDER BY s DESC LIMIT ?",
            arrayOf(head, head + "􏿿", limit.toString()),
        ).use { c ->
            while (c.moveToNext()) {
                val p = c.getString(0)
                if (p.length > head.length && p.startsWith(head)) out.add(p)
            }
        }
        return out
    }
}

/** 翻譯：先試 Google 的離線翻譯（ML Kit，第一次要下載語言），不行就用網路翻譯 MyMemory */
object Translator {
    data class Language(val code: String, val name: String)

    val targets = listOf(
        Language("en", "英文"), Language("ja", "日文"), Language("ko", "韓文"), Language("zh-TW", "繁中"),
        Language("zh-CN", "簡中"), Language("fr", "法文"), Language("de", "德文"), Language("es", "西班牙文"), Language("it", "義大利文"),
        Language("th", "泰文"), Language("vi", "越南文"), Language("id", "印尼文"),
    )

    private val main = Handler(Looper.getMainLooper())

    fun detectSource(text: String): String {
        var han = 0; var kana = 0; var hangul = 0; var latin = 0
        for (ch in text) {
            when (ch.code) {
                in 0x3040..0x30FF -> kana++
                in 0xAC00..0xD7A3, in 0x3131..0x318E -> hangul++
                in 0x4E00..0x9FFF, in 0x3400..0x4DBF -> han++
                in 0x41..0x5A, in 0x61..0x7A -> latin++
            }
        }
        return when {
            kana > 0 -> "ja"
            hangul > 0 -> "ko"
            han > 0 -> "zh-TW"
            latin > 0 -> "en"
            else -> "zh-TW"
        }
    }

    /** chosen：原文語言；"auto" 就自己猜 */
    fun translate(text: String, chosen: String, target: String, allowOnline: Boolean, status: (String) -> Unit, done: (Result<String>) -> Unit) {
        val picked = chosen.takeIf { it != "auto" }
        var source = picked ?: detectSource(text)
        if (picked == null && source == target) source = if (target == "en") "zh-TW" else "en"
        // ML Kit 的中文只有一種（簡體），要繁中就直接用網路翻譯
        val src = TranslateLanguage.fromLanguageTag(source.substringBefore('-'))
        val tgt = TranslateLanguage.fromLanguageTag(target.substringBefore('-'))
        if (src == null || tgt == null || target == "zh-TW") {
            online(text, source, target, allowOnline, done)
            return
        }
        val translator = Translation.getClient(TranslatorOptions.Builder().setSourceLanguage(src).setTargetLanguage(tgt).build())
        status("翻譯中…（第一次用這個語言要下載資料）")
        translator.downloadModelIfNeeded(DownloadConditions.Builder().build())
            .addOnSuccessListener {
                translator.translate(text)
                    .addOnSuccessListener { done(Result.success(it)); translator.close() }
                    .addOnFailureListener { translator.close(); online(text, source, target, allowOnline, done) }
            }
            .addOnFailureListener { translator.close(); online(text, source, target, allowOnline, done) }
    }

    private fun online(text: String, source: String, target: String, allowOnline: Boolean, done: (Result<String>) -> Unit) {
        if (!allowOnline) {
            done(Result.failure(IllegalStateException("本機翻譯目前不可用；如需外部服務，請先到 ⚙ 隱私與安全開啟網路翻譯")))
            return
        }
        Thread {
            val result = runCatching {
                val q = URLEncoder.encode(text.take(450), "UTF-8")
                val pair = URLEncoder.encode("$source|$target", "UTF-8")
                val conn = URL("https://api.mymemory.translated.net/get?q=$q&langpair=$pair").openConnection() as HttpURLConnection
                conn.connectTimeout = 10000
                conn.readTimeout = 12000
                val body = conn.inputStream.bufferedReader().use { it.readText() }
                val o = JSONObject(body)
                val status = o.opt("responseStatus").toString()
                val translated = o.getJSONObject("responseData").getString("translatedText")
                if (status != "200") error("翻譯失敗：$translated")
                translated
            }.recoverCatching { e ->
                throw IllegalStateException(if (e is IllegalStateException) e.message else "連不上翻譯服務，請確認網路")
            }
            main.post { done(result) }
        }.start()
    }
}

/** 到 GitHub 看有沒有新的 Android 版 */
object UpdateFetcher {
    private val main = Handler(Looper.getMainLooper())

    fun fetch(done: (ReleaseInfo?) -> Unit) {
        Thread {
            val info = runCatching {
                val conn = URL(ReleaseChecker.API).openConnection() as HttpURLConnection
                conn.setRequestProperty("Accept", "application/vnd.github+json")
                conn.connectTimeout = 10000
                conn.readTimeout = 10000
                ReleaseChecker.parseLatest(conn.inputStream.bufferedReader().use { it.readText() })
            }.getOrNull()
            main.post { done(info) }
        }.start()
    }
}
