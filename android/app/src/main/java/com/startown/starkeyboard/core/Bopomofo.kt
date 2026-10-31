package com.startown.starkeyboard.core

enum class BopomofoKind { INITIAL, MEDIAL, RHYME, TONE }

object Bopomofo {
    const val INITIALS = "ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙ"
    const val MEDIALS = "ㄧㄨㄩ"
    const val RHYMES = "ㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦ"
    const val TONES = "ˊˇˋ˙"

    fun kind(c: Char): BopomofoKind? = when {
        INITIALS.indexOf(c) >= 0 -> BopomofoKind.INITIAL
        MEDIALS.indexOf(c) >= 0 -> BopomofoKind.MEDIAL
        RHYMES.indexOf(c) >= 0 -> BopomofoKind.RHYME
        TONES.indexOf(c) >= 0 -> BopomofoKind.TONE
        else -> null
    }

    /** 大千排列：和電腦鍵盤的 1qaz、2wsx… 直排一樣 */
    val dachenRows = listOf(
        "ㄅㄉˇˋㄓˊ˙ㄚㄞㄢㄦ",
        "ㄆㄊㄍㄐㄔㄗㄧㄛㄟㄣ",
        "ㄇㄋㄎㄑㄕㄘㄨㄜㄠㄤ",
        "ㄈㄌㄏㄒㄖㄙㄩㄝㄡㄥ",
    )

    /** 所有音節（沒聲調）的開頭，例如 ㄋㄧㄠ → ㄋ、ㄋㄧ、ㄋㄧㄠ */
    fun prefixes(syllables: Collection<String>): Set<String> =
        syllables.flatMapTo(HashSet()) { s -> (1..s.length).map { s.substring(0, it) } }

    /** 常分不清的音（模糊音） */
    val similar = mapOf(
        'ㄣ' to 'ㄥ', 'ㄥ' to 'ㄣ', 'ㄓ' to 'ㄗ', 'ㄗ' to 'ㄓ',
        'ㄔ' to 'ㄘ', 'ㄘ' to 'ㄔ', 'ㄕ' to 'ㄙ', 'ㄙ' to 'ㄕ',
    )

    /** 鍵盤上相鄰的鍵（左右、上下） */
    val neighbors: Map<Char, List<Char>> by lazy {
        val map = HashMap<Char, List<Char>>()
        for ((r, row) in dachenRows.withIndex()) {
            for ((c, ch) in row.withIndex()) {
                val list = ArrayList<Char>()
                for ((dr, dc) in listOf(0 to -1, 0 to 1, -1 to 0, 1 to 0)) {
                    val rr = r + dr
                    val cc = c + dc
                    if (rr in dachenRows.indices && cc >= 0 && cc < dachenRows[rr].length) {
                        list.add(dachenRows[rr][cc])
                    }
                }
                map[ch] = list
            }
        }
        map
    }
}

/** 一個字的注音：聲母＋介音＋韻母＋聲調（一聲不標） */
data class Syllable(
    var initial: Char? = null,
    var medial: Char? = null,
    var rhyme: Char? = null,
    var tone: Char? = null,
) {
    val isEmpty get() = initial == null && medial == null && rhyme == null && tone == null
    val hasSound get() = initial != null || medial != null || rhyme != null

    /** 沒打聲調就換下一個字（或只打了開頭）：查字典時當成「以這些注音開頭、聲調不限」 */
    var open = false

    /** 查字典用的寫法：沒打完的音節後面加 *，例如「ㄋ*」「ㄋㄧ*」 */
    val key get() = if (open) "$reading*" else reading

    /** 再打這一類的符號時，算是開始打下一個字（例如已經有韻母又打韻母、已經有音又打聲母） */
    fun startsNewWith(kind: BopomofoKind) = when (kind) {
        BopomofoKind.INITIAL -> hasSound
        BopomofoKind.MEDIAL -> medial != null || rhyme != null
        BopomofoKind.RHYME -> rhyme != null
        BopomofoKind.TONE -> false
    }

    /** 和字典一樣的寫法，例如「ㄋㄧˇ」「ㄇㄚ」「ㄉㄜ˙」 */
    val reading: String
        get() = buildString { listOf(initial, medial, rhyme, tone).forEach { if (it != null) append(it) } }

    /** 大千的打法：同一類的符號再打一次就取代 */
    fun put(c: Char) {
        when (Bopomofo.kind(c)) {
            BopomofoKind.INITIAL -> initial = c
            BopomofoKind.MEDIAL -> medial = c
            BopomofoKind.RHYME -> rhyme = c
            BopomofoKind.TONE -> tone = c
            null -> {}
        }
    }

    fun removeLast() {
        when {
            tone != null -> tone = null
            rhyme != null -> rhyme = null
            medial != null -> medial = null
            else -> initial = null
        }
    }

    companion object {
        fun parse(reading: String) = Syllable().also { s -> reading.forEach { s.put(it) } }
    }
}

/** 組字區：已經打完的音節＋正在打的音節 */
class ZhuyinComposer {
    val syllables = ArrayList<Syllable>()
    var current = Syllable()
        private set

    /** 聲調比音節先到時先留著，不要單獨送進文章。 */
    private var pendingTone: Char? = null

    /** 查字典用的讀音：打完的音節＋正在打的音節（沒打聲調也算，先拿來預覽） */
    /** 字典裡所有音節的開頭（例如 ㄋ、ㄋㄧ、ㄋㄧㄠ）；有的話，組不出存在的音就自動換下一個字 */
    var validPrefixes: Set<String>? = null

    val readings: List<String>
        get() {
            val head = syllables.map { it.key }
            if (!current.hasSound) return head
            val tone = current.tone ?: pendingTone
            val body = if (current.tone == null && tone != null) current.reading + tone else current.reading
            return head + listOf(if (tone == null) "$body*" else body)
        }
    val isComposing get() = syllables.isNotEmpty() || !current.isEmpty
    val hasPendingSyllable get() = !current.isEmpty

    /** 回傳 false 表示這個符號沒被組字用掉（不是注音）。聲調一定回傳 true。 */
    fun input(c: Char): Boolean {
        val kind = Bopomofo.kind(c) ?: return false
        if (kind == BopomofoKind.TONE) return putTone(c)
        // 不打聲調直接打下一個字：前一個字自動結束（ㄋㄏ → 你好）
        if (current.hasSound && (current.startsNewWith(kind) || !fits(c))) closeCurrent()
        current.put(c)
        return true
    }

    private fun putTone(c: Char): Boolean {
        if (current.hasSound) {
            pendingTone = null
            current.tone = c
            finish(open = false)
            return true
        }
        val last = syllables.lastOrNull()
        if (last != null && last.open && last.tone == null) {
            last.tone = c
            last.open = false
            pendingTone = null
            return true
        }
        pendingTone = c
        return true
    }

    private fun closeCurrent() {
        val tone = pendingTone
        if (current.tone == null && tone != null) {
            current.tone = tone
            pendingTone = null
            finish(open = false)
        } else {
            finish(open = current.tone == null)
        }
    }

    /** 加上這個符號還是某個字的開頭嗎（例如 ㄘ＋ㄧ 不是，ㄘ 要自己算一個字） */
    private fun fits(c: Char): Boolean {
        val set = validPrefixes ?: return true
        return current.copy().also { it.put(c) }.reading in set
    }

    /** 空白鍵＝一聲。組字區保持開著。 */
    fun confirmSyllable(): Boolean {
        if (!current.hasSound) return false
        if (current.tone == null && pendingTone != null) current.tone = pendingTone
        pendingTone = null
        finish(open = false)
        return true
    }

    /** 還沒有音節時誤按的聲調。退格或真正的空白會把它清掉，避免黏到下一個字。 */
    fun consumeStrayTone(): Boolean {
        if (pendingTone == null || !current.isEmpty || syllables.isNotEmpty()) return false
        pendingTone = null
        return true
    }

    fun backspace(): Boolean {
        if (current.hasSound && current.tone == null && pendingTone != null) {
            pendingTone = null
            return true
        }
        if (!current.hasSound && pendingTone != null && syllables.isEmpty()) {
            pendingTone = null
            return true
        }
        if (!current.isEmpty) {
            current.removeLast()
            return true
        }
        if (syllables.isNotEmpty()) {
            val last = syllables.removeAt(syllables.size - 1)
            if (last.open) {
                // 沒打聲調的字：拿回來繼續一個一個刪
                last.open = false
                last.removeLast()
                current = last
            }
            return true
        }
        return false
    }

    /** 選了字之後拿掉前 n 個音節（包含正在打的那個） */
    fun removeFirst(n: Int) {
        val count = maxOf(n, 0)
        if (count > syllables.size) {
            current = Syllable()
            pendingTone = null
        }
        repeat(minOf(count, syllables.size)) { syllables.removeAt(0) }
    }

    fun clear() {
        syllables.clear()
        current = Syllable()
        pendingTone = null
    }

    private fun finish(open: Boolean = false) {
        current.open = open
        syllables.add(current)
        current = Syllable()
    }
}
