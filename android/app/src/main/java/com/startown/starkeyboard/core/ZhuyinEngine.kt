package com.startown.starkeyboard.core

import java.io.File

data class Candidate(val text: String, val span: Int, val kind: Kind) {
    enum class Kind { SENTENCE, PHRASE, LITERAL }
}

data class Scored(val text: String, val score: Double)

/** 字典：讀音 → 字詞（SQLite 或測試用的記憶體版本） */
interface PhraseSource {
    /** 一個讀音（例如「ㄋㄧˇ-ㄏㄠˇ」）的所有字詞，分數高的在前面 */
    fun lookup(reading: String): List<Scored>

    /** 以某個字開頭的詞（聯想詞用），分數高的在前面 */
    fun startingWith(head: String, limit: Int): List<String>

    /** 每個音節第一個注音接起來是 abbr 的所有字詞（讀音、字詞、分數），例如「ㄋㄏ」→ ㄋㄧˇ-ㄏㄠˇ 你好 */
    fun byAbbreviation(abbr: String, pattern: String? = null): List<Triple<String, String, Double>>

    /** 字典裡所有單字的讀音（沒聲調），例如 ㄋㄧ、ㄏㄠ */
    fun syllables(): List<String>

    /** 前後文。沒有語料時是空的，選字就只看詞頻。 */
    fun contextModel(): ContextModel = ContextModel.EMPTY
}

/** 字組出現次數。注音送出時用來在同音詞裡挑比較像前後文的那個。 */
class ContextModel(private val ngrams: Map<String, Int>) {
    fun bonus(tail: String, phrase: String): Double {
        if (phrase.isEmpty() || ngrams.isEmpty()) return 0.0
        var best = 0.0
        if (tail.isNotEmpty()) {
            val ts = tail.takeLast(2)
            val ps = phrase.take(3)
            for (a in 1..ts.length) {
                for (b in 1..minOf(3, ps.length)) {
                    val gram = ts.takeLast(a) + ps.take(b)
                    val count = ngrams[gram] ?: continue
                    if (count <= 0) continue
                    val weight = if (gram.length >= 3) 0.62 else 0.28
                    best = maxOf(best, weight * kotlin.math.log10(count + 1.0))
                }
            }
        }
        if (phrase.length >= 2) {
            val count = ngrams[phrase]
            if (count != null && count > 0) best = maxOf(best, 0.42 * kotlin.math.log10(count + 1.0))
        }
        return minOf(best, 1.8)
    }

    companion object {
        val EMPTY = ContextModel(emptyMap())

        fun fromPhrases(phrases: Collection<String>): ContextModel {
            val map = HashMap<String, Int>()
            for (phrase in phrases.toSet()) {
                if (phrase.length < 2 || phrase.any { Bopomofo.kind(it) != null }) continue
                if (phrase.length <= 4) map[phrase] = (map[phrase] ?: 0) + 1
                for (i in 0 until phrase.length - 1) {
                    val bi = phrase.substring(i, i + 2)
                    map[bi] = (map[bi] ?: 0) + 1
                    if (i + 2 < phrase.length) {
                        val tri = phrase.substring(i, i + 3)
                        map[tri] = (map[tri] ?: 0) + 1
                    }
                }
            }
            return ContextModel(map)
        }
    }
}

class MemoryPhraseSource(private val rows: List<Triple<String, String, Double>>) : PhraseSource {
    private val byReading = rows.groupBy({ it.first }, { Scored(it.second, it.third) })
        .mapValues { (_, v) -> v.sortedByDescending { it.score } }
    private val all = rows.map { Scored(it.second, it.third) }
    private val byAbbr = rows.groupBy { r -> r.first.split('-').joinToString("") { it.take(1) } }

    override fun lookup(reading: String) = byReading[reading] ?: emptyList()

    override fun byAbbreviation(abbr: String, pattern: String?) = byAbbr[abbr] ?: emptyList()

    override fun syllables() = rows.filter { '-' !in it.first }
        .map { r -> r.first.filter { Bopomofo.TONES.indexOf(it) < 0 } }.distinct()

    override fun startingWith(head: String, limit: Int): List<String> =
        all.filter { it.text.length > head.length && it.text.startsWith(head) }
            .groupBy { it.text }.map { (k, v) -> Scored(k, v.maxOf { it.score }) }
            .sortedByDescending { it.score }.take(limit).map { it.text }

    private val context = ContextModel.fromPhrases(rows.map { it.second })
    override fun contextModel() = context
}

/** 注音選字：整串用動態規劃找分數最高的斷詞，也會猜打錯的字 */
/** toneless：字典用沒聲調的讀音查（拼音用） */
class ZhuyinEngine(private val source: PhraseSource, val userModel: UserPhraseModel, private val toneless: Boolean = false) {
    /** 容錯：打錯鍵、聲調錯、ㄣㄥ這類模糊音也猜得到 */
    data class FuzzyOptions(
        val keyNeighbors: Boolean = true,   // 打出來的音不存在時，試試旁邊的鍵
        val tones: Boolean = true,          // 聲調打錯或忘了打
        val phonetic: Boolean = false,      // ㄣㄥ、ㄓㄗ、ㄔㄘ、ㄕㄙ 分不清
    )

    var fuzzy = FuzzyOptions()
        set(value) {
            if (value != field) {
                field = value
                fuzzyCache.clear()
                alternativeCache.clear()
            }
        }

    private val cache = HashMap<String, List<Scored>>()
    private val fuzzyCache = HashMap<String, List<Scored>>()
    private val alternativeCache = HashMap<String, List<Pair<String, Double>>>()

    companion object {
        const val MAX_PHRASE = 6
        const val UNKNOWN_PENALTY = -30.0
        const val USER_PHRASE_BASE = -6.0
        const val TONE_PENALTY = -2.5
        const val PHONETIC_PENALTY = -1.2
        const val NEIGHBOR_PENALTY = -2.5
        const val PREFIX_PENALTY = -1.0      // 只打了開頭（ㄋ 當 ㄋㄧ），比打完整的排後面一點

        /** 畫面上顯示的注音（拿掉查字典用的 *） */
        fun display(reading: String) = reading.replace("*", "")

        fun commit(text: String) = text.filter { Bopomofo.kind(it) == null }.toString()

        /**
         * 讀音合不合 pattern：有 * 的音節只要開頭一樣（聲調不限），其他要完全一樣。
         * 合的話回傳要扣的分數，不合回傳 null
         */
        fun matchPenalty(pattern: List<String>, reading: List<String>, ignoreTones: Boolean = false): Double? {
            if (pattern.size != reading.size) return null
            var penalty = 0.0
            for (i in pattern.indices) {
                val want = pattern[i]
                val have = reading[i]
                if (!want.endsWith('*')) {
                    val h = if (ignoreTones) have.filter { Bopomofo.TONES.indexOf(it) < 0 } else have
                    if (want != h) return null
                    continue
                }
                val head = want.dropLast(1)
                val plain = have.filter { Bopomofo.TONES.indexOf(it) < 0 }
                if (!plain.startsWith(head)) return null
                if (plain != head) penalty += PREFIX_PENALTY
            }
            return penalty
        }
    }

    /** 查字典：讀音裡有沒打完的音節（*）就用開頭注音查，再一個一個比 */
    private fun lookup(key: String): List<Scored> {
        if ('*' !in key) return source.lookup(key).take(80)
        val pattern = key.split('-')
        val best = HashMap<String, Double>()
        for ((reading, text, score) in source.byAbbreviation(pattern.joinToString("") { it.take(1) }, key)) {
            val penalty = matchPenalty(pattern, reading.split('-'), toneless) ?: continue
            val s = score + penalty
            val old = best[text]
            if (old == null || s > old) best[text] = s
        }
        return best.entries.map { Scored(it.key, it.value) }.sortedByDescending { it.score }.take(80)
    }

    fun phrases(readings: List<String>): List<Scored> {
        val key = readings.joinToString("-")
        cache[key]?.let { return it }
        val best = LinkedHashMap<String, Double>()
        for (p in lookup(key)) {
            if (p.text !in best) best[p.text] = p.score
        }
        for (p in userModel.phrases(key)) {
            if (p !in best) best[p] = USER_PHRASE_BASE
        }
        val result = best.entries.map { Scored(it.key, it.value + userModel.boost(key, it.key)) }
            .sortedByDescending { it.score }
        cache[key] = result
        return result
    }

    /** 和 phrases 一樣，但也算進打錯的可能（每個詞最多猜錯一個音節，分數扣一點） */
    fun fuzzyPhrases(readings: List<String>): List<Scored> {
        val key = readings.joinToString("-")
        fuzzyCache[key]?.let { return it }
        val best = LinkedHashMap<String, Double>()
        fun merge(list: List<Scored>, penalty: Double) {
            for (p in list) {
                val s = p.score + penalty
                val old = best[p.text]
                if (old == null || s > old) best[p.text] = s
            }
        }
        merge(phrases(readings), 0.0)
        for (j in readings.indices) {
            for ((alt, penalty) in alternatives(readings[j])) {
                val variant = readings.toMutableList()
                variant[j] = alt
                merge(phrases(variant), penalty)
            }
        }
        val result = best.entries.map { Scored(it.key, it.value) }.sortedByDescending { it.score }
        fuzzyCache[key] = result
        return result
    }

    /** 一個音節可能是哪些音打錯了（只留字典裡真的有的） */
    fun alternatives(reading: String): List<Pair<String, Double>> {
        alternativeCache[reading]?.let { return it }
        if (reading.endsWith('*')) return emptyList()   // 沒打完的音節本來就聲調不限，不用再猜
        val syllable = Syllable.parse(reading)
        val out = ArrayList<Pair<String, Double>>()
        val seen = hashSetOf(reading)
        fun add(s: Syllable, penalty: Double) {
            val r = s.reading
            if (!s.hasSound || !seen.add(r)) return
            if (phrases(listOf(r)).isNotEmpty()) out.add(r to penalty)
        }
        if (fuzzy.tones) {
            for (tone in listOf(null, 'ˊ', 'ˇ', 'ˋ', '˙')) {
                if (tone != syllable.tone) add(syllable.copy(tone = tone), TONE_PENALTY)
            }
        }
        if (fuzzy.phonetic) {
            syllable.initial?.let { i -> Bopomofo.similar[i]?.let { add(syllable.copy(initial = it), PHONETIC_PENALTY) } }
            syllable.rhyme?.let { f -> Bopomofo.similar[f]?.let { add(syllable.copy(rhyme = it), PHONETIC_PENALTY) } }
        }
        // 打出來的音根本不存在：多半是按到旁邊的鍵
        if (fuzzy.keyNeighbors && phrases(listOf(reading)).isEmpty()) {
            for (c in reading) {
                for (n in Bopomofo.neighbors[c] ?: emptyList()) {
                    val s = syllable.copy()
                    when (Bopomofo.kind(c)) {
                        BopomofoKind.INITIAL -> s.initial = null
                        BopomofoKind.MEDIAL -> s.medial = null
                        BopomofoKind.RHYME -> s.rhyme = null
                        BopomofoKind.TONE -> s.tone = null
                        null -> continue
                    }
                    s.put(n)
                    add(s, NEIGHBOR_PENALTY)
                }
            }
        }
        alternativeCache[reading] = out
        return out
    }

    /** 整串注音分數最高的斷法。contextual 用前後文在同音詞裡挑。 */
    fun bestSegments(readings: List<String>, contextual: Boolean = true): List<Scored> {
        val n = readings.size
        if (n == 0) return emptyList()
        val best = DoubleArray(n + 1) { Double.NEGATIVE_INFINITY }
        val backStart = IntArray(n + 1)
        val backText = arrayOfNulls<String>(n + 1)
        val backScore = DoubleArray(n + 1)
        val tail = Array(n + 1) { "" }
        val context = if (contextual) source.contextModel() else ContextModel.EMPTY
        best[0] = 0.0
        for (i in 1..n) {
            for (k in 1..minOf(MAX_PHRASE, i)) {
                val start = i - k
                if (best[start] == Double.NEGATIVE_INFINITY) continue
                val pool = fuzzyPhrases(readings.subList(start, i)).filter { commit(it.text) == it.text && it.text.isNotEmpty() }
                if (pool.isNotEmpty()) {
                    val options = if (contextual) pool.take(6) else pool.take(1)
                    for (opt in options) {
                        val bonus = context.bonus(tail[start], opt.text)
                        val s = best[start] + opt.score + bonus
                        if (s > best[i]) {
                            best[i] = s
                            backStart[i] = start
                            backText[i] = opt.text
                            backScore[i] = opt.score + bonus
                            tail[i] = (tail[start] + opt.text).takeLast(2)
                        }
                    }
                } else if (k == 1) {
                    val s = best[start] + UNKNOWN_PENALTY
                    if (s > best[i]) {
                        best[i] = s
                        backStart[i] = start
                        backText[i] = ""
                        backScore[i] = UNKNOWN_PENALTY
                        tail[i] = tail[start]
                    }
                }
            }
        }
        val segments = ArrayList<Scored>()
        var i = n
        while (i > 0) {
            segments.add(Scored(backText[i] ?: "", backScore[i]))
            i = backStart[i]
        }
        return segments.reversed()
    }

    /** 候選字：第一個是整句，接著是從開頭算起最長到最短的詞 */
    fun candidates(readings: List<String>): List<Candidate> {
        if (readings.isEmpty()) return emptyList()
        val out = ArrayList<Candidate>()
        val seen = HashSet<String>()
        if (readings.size > 1) {
            val sentence = bestSegments(readings).joinToString("") { it.text }
            out.add(Candidate(sentence, readings.size, Candidate.Kind.SENTENCE))
            seen.add(sentence)
        }
        var hasSingle = false
        for (k in minOf(MAX_PHRASE, readings.size) downTo 1) {
            for (p in fuzzyPhrases(readings.subList(0, k))) {
                if (!seen.add(p.text)) continue
                out.add(Candidate(p.text, k, Candidate.Kind.PHRASE))
                if (k == 1) hasSingle = true
            }
        }
        if (!hasSingle) {
            val literal = commit(display(readings[0]))
            if (literal.isNotEmpty()) out.add(Candidate(literal, 1, Candidate.Kind.LITERAL))
        }
        return out.filter { it.text.isNotEmpty() && commit(it.text) == it.text }
    }

    /** 所有音節的開頭（給組字用，判斷注音能不能接在一起） */
    fun syllablePrefixes(): Set<String> = Bopomofo.prefixes(source.syllables())

    /** 聯想詞：打完一個字後，接在它後面常見的字詞 */
    fun associations(after: String, limit: Int = 30): List<String> {
        if (after.isEmpty()) return emptyList()
        val head = after.substring(after.offsetByCodePoints(after.length, -1))
        return source.startingWith(head, limit).map { it.substring(head.length) }.filter { it.isNotEmpty() }
    }

    fun learn(readings: List<String>, text: String) {
        if (readings.isEmpty() || readings.size > MAX_PHRASE) return
        userModel.record(readings.joinToString("-"), text)
        cache.clear()
        fuzzyCache.clear()
        alternativeCache.clear()
    }

    fun resetLearning() {
        userModel.reset()
        cache.clear()
        fuzzyCache.clear()
        alternativeCache.clear()
    }
}

/** 記住使用者選過的字詞（每行：讀音 TAB 字詞 TAB 次數） */
class UserPhraseModel(private val file: File?) {
    private val counts = HashMap<String, HashMap<String, Int>>()
    private val matchingCache = HashMap<String, Map<String, Int>>()

    init {
        file?.takeIf { it.exists() }?.forEachLine { line ->
            val parts = line.split('\t')
            if (parts.size == 3) {
                parts[2].toIntOrNull()?.let { counts.getOrPut(parts[0]) { HashMap() }[parts[1]] = it }
            }
        }
    }

    /**
     * 同樣的打法選過：每次加 0.8（log10，大約變成 6 倍常用），最多算 5 次；
     * 不管用什麼打法，這個字詞選過就再加一點（每次 0.4，最多 5 次）。只記字的那一欄 key 是空字串。
     */
    fun boost(reading: String, phrase: String): Double {
        val same = minOf(matchingCounts(reading)[phrase] ?: 0, 5) * 0.8
        val any = minOf(counts[""]?.get(phrase) ?: 0, 5) * 0.4
        return same + any
    }

    fun phrases(reading: String): List<String> =
        if (reading.isEmpty()) emptyList() else matchingCounts(reading).keys.sorted()

    private fun matchingCounts(reading: String): Map<String, Int> = matchingCache.getOrPut(reading) {
        val query = reading.split('-')
        val result = HashMap<String, Int>()
        for ((saved, phrases) in counts) {
            if (saved.isEmpty()) continue
            val parts = saved.split('-')
            if (parts.size != query.size) continue
            if (query.zip(parts).all { (want, have) ->
                    want == have || ZhuyinEngine.matchPenalty(listOf(want), listOf(have)) != null ||
                        ZhuyinEngine.matchPenalty(listOf(have), listOf(want)) != null
                }) {
                for ((phrase, count) in phrases) result[phrase] = maxOf(result[phrase] ?: 0, count)
            }
        }
        result
    }

    fun record(reading: String, phrase: String) {
        if (reading.isEmpty() || phrase.isEmpty()) return
        matchingCache.clear()
        for (key in listOf(reading, "")) {
            val m = counts.getOrPut(key) { HashMap() }
            m[phrase] = (m[phrase] ?: 0) + 1
        }
        save()
    }

    fun reset() {
        counts.clear()
        matchingCache.clear()
        save()
    }

    private fun save() {
        val f = file ?: return
        f.writeText(buildString {
            for ((r, m) in counts) for ((p, c) in m) append(r).append('\t').append(p).append('\t').append(c).append('\n')
        })
    }
}
