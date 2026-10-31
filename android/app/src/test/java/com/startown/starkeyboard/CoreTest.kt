package com.startown.starkeyboard

import com.startown.starkeyboard.core.Bopomofo
import com.startown.starkeyboard.core.Candidate
import com.startown.starkeyboard.core.ClipboardStore
import com.startown.starkeyboard.core.HangulComposer
import com.startown.starkeyboard.core.FancyText
import com.startown.starkeyboard.core.ShortcutStore
import com.startown.starkeyboard.core.MemoryPhraseSource
import com.startown.starkeyboard.core.ReleaseChecker
import com.startown.starkeyboard.core.Romaji
import com.startown.starkeyboard.core.Spelling
import com.startown.starkeyboard.core.SymbolData
import com.startown.starkeyboard.core.SymbolPages
import com.startown.starkeyboard.core.UserPhraseModel
import com.startown.starkeyboard.core.ZhuyinComposer
import com.startown.starkeyboard.core.ZhuyinEngine
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** 和 iPhone 版 Core/Tests 一樣的檢查 */
class CoreTest {
    private fun engine(extra: List<Triple<String, String, Double>> = emptyList()): ZhuyinEngine {
        val rows = listOf(
            Triple("ㄋㄧˇ", "你", -3.0), Triple("ㄋㄧˇ", "妳", -4.0), Triple("ㄏㄠˇ", "好", -3.0),
            Triple("ㄋㄧˇ-ㄏㄠˇ", "你好", -4.0), Triple("ㄋㄧˇ-ㄇㄣ˙", "你們", -4.1),
            Triple("ㄕˋ", "是", -2.5), Triple("ㄕˋ", "事", -3.2), Triple("ㄕˋ", "世", -3.6),
            Triple("ㄐㄧㄝˋ", "界", -4.2), Triple("ㄕˋ-ㄐㄧㄝˋ", "世界", -4.5),
        )
        return ZhuyinEngine(MemoryPhraseSource(rows + extra), UserPhraseModel(null))
    }

    private fun sentence(e: ZhuyinEngine, r: List<String>) = e.bestSegments(r).joinToString("") { it.text }

    @Test fun learnedWordsWorkWithPartialReadings() {
        val e = engine()
        e.candidates(listOf("ㄋㄧ*"))
        e.learn(listOf("ㄋㄧˇ"), "妳")
        assertEquals("妳", e.candidates(listOf("ㄋㄧ*")).first().text)
        e.learn(listOf("ㄋ*", "ㄏ*"), "妳好")
        assertTrue(e.phrases(listOf("ㄋㄧˇ", "ㄏㄠˇ")).any { it.text == "妳好" })
        assertFalse(e.phrases(listOf("ㄕˋ", "ㄏㄠˇ")).any { it.text == "妳好" })
        e.resetLearning()
        assertEquals("你", e.candidates(listOf("ㄋㄧ*")).first().text)
    }

    @Test fun composer() {
        val c = ZhuyinComposer()
        "ㄋㄧˇㄏㄠˇ".forEach { assertTrue(c.input(it)) }
        assertEquals(listOf("ㄋㄧˇ", "ㄏㄠˇ"), c.readings)
        c.input('ㄇ'); c.input('ㄚ')
        assertTrue(c.confirmSyllable())
        assertEquals("ㄇㄚ", c.readings.last())
        val bare = ZhuyinComposer()
        assertTrue(bare.input('ˇ'))
        assertFalse(bare.isComposing)
        bare.input('ㄨ'); bare.input('ㄛ')
        assertEquals(listOf("ㄨㄛˇ"), bare.readings)
        // 沒打聲調就打下一個字：前一個字自動結束，正在打的字也算進去
        val d = ZhuyinComposer()
        "ㄅㄆㄚˋ".forEach { d.input(it) }
        assertEquals(listOf("ㄅ*", "ㄆㄚˋ"), d.readings)
        val a = ZhuyinComposer()
        "ㄋㄧㄏ".forEach { a.input(it) }
        assertEquals(listOf("ㄋㄧ*", "ㄏ*"), a.readings)
        a.backspace(); a.backspace()
        assertEquals(listOf("ㄋ*"), a.readings)
        val w = ZhuyinComposer()
        "ㄨㄛㄏㄓㄜㄧ".forEach { w.input(it) }
        assertEquals(listOf("ㄨㄛ*", "ㄏ*", "ㄓㄜ*", "ㄧ*"), w.readings)
        // 組不出存在的音（ㄘㄧ）就自動換下一個字
        val v = ZhuyinComposer()
        v.validPrefixes = Bopomofo.prefixes(listOf("ㄘ", "ㄘㄜ", "ㄧ", "ㄧㄝ"))
        "ㄘㄧㄝ".forEach { v.input(it) }
        assertEquals(listOf("ㄘ*", "ㄧㄝ*"), v.readings)
        assertTrue(engine().syllablePrefixes().containsAll(listOf("ㄋ", "ㄋㄧ", "ㄐㄧㄝ")))
        a.removeFirst(1)
        assertFalse(a.isComposing)
    }

    @Test fun fancyTextAndShortcuts() {
        val v = FancyText.variants("Hi 1")
        assertTrue(v.contains("\uD835\uDCD7\uD835\uDCF2 1"))   // 草寫 𝓗𝓲
        assertTrue(v.contains("\u24BD\u24D8 \u2460"))           // 圈圈 Ⓗⓘ ①
        assertTrue(v.contains("H\u0336i\u0336 1\u0336"))        // 刪除線
        val zh = FancyText.variants("星光")
        assertTrue(zh.contains("♡ 星光 ♡"))
        assertFalse(zh.contains("星光"))
        val s = ShortcutStore(null)
        s.add("addr", "台北市")
        s.add("地址", "台北市")
        assertEquals(listOf("台北市"), s.matching("ADDR"))
        assertEquals(listOf("台北市"), s.matching("地址"))
        assertTrue(s.matching("add").isEmpty())
    }

    @Test fun previewAndAbbreviation() {
        val e = engine(listOf(Triple("ㄨㄛˇ", "我", -2.5), Triple("ㄏㄨㄟˋ", "會", -2.8), Triple("ㄓㄜˋ", "這", -2.6),
            Triple("ㄧㄤˋ", "樣", -3.0), Triple("ㄓㄜˋ-ㄧㄤˋ", "這樣", -3.5)))
        assertEquals("我會這樣", sentence(e, listOf("ㄨㄛ*", "ㄏ*", "ㄓㄜ*", "ㄧ*")))
        assertEquals("你好", sentence(e, listOf("ㄋ*", "ㄏ*")))
        assertEquals("你好", sentence(e, listOf("ㄋㄧ*", "ㄏㄠ*")))
        assertEquals("你好", sentence(e, listOf("ㄋㄧˇ", "ㄏ*")))
        assertEquals("你好世界", sentence(e, listOf("ㄋ*", "ㄏ*", "ㄕ*", "ㄐ*")))
        assertEquals(listOf("你", "妳"), e.candidates(listOf("ㄋㄧ*")).map { it.text })
        assertTrue(e.candidates(listOf("ㄅ*")).none { ZhuyinEngine.commit(it.text) != it.text })
    }

    @Test fun wholeSentenceIsTopCandidate() {
        val e = engine(listOf(
            Triple("ㄨㄛˇ", "我", -2.2),
            Triple("ㄕˋ", "是", -1.6),
            Triple("ㄕˋ", "試", -3.4),
            Triple("ㄎㄢˋ", "看", -2.5),
            Triple("ㄕˋ-ㄎㄢˋ", "試看", -4.5),
            Triple("ㄕˋ-ㄕˋ-ㄎㄢˋ", "試試看", -4.0),
            Triple("ㄎㄚˇ", "卡", -3.0),
            Triple("ㄉㄜ˙", "的", -1.2),
            Triple("ㄒㄩㄢˇ", "選", -3.5),
            Triple("ㄗˋ", "字", -2.8),
            Triple("ㄒㄩㄢˇ-ㄗˋ", "選字", -3.2),
            Triple("ㄉㄡ", "都", -2.0),
            Triple("ㄇㄟˊ", "沒", -2.4),
            Triple("ㄧㄡˇ", "有", -2.1),
            Triple("ㄇㄟˊ-ㄧㄡˇ", "沒有", -2.6),
            Triple("ㄉㄡ-ㄇㄟˊ", "都沒", -3.4),
            Triple("ㄍㄟˇ", "給", -2.7),
            Triple("ㄉㄧˋ", "第", -3.0),
            Triple("ㄧ", "一", -1.8),
            Triple("ㄍㄜ˙", "個", -2.2),
            Triple("ㄉㄧˋ-ㄧ-ㄍㄜ˙", "第一個", -3.1),
            Triple("ㄏㄨㄟˋ", "會", -2.3),
            Triple("ㄏㄨㄟˋ-ㄕˋ", "會是", -3.0),
            Triple("ㄉㄨㄟˋ", "對", -2.4),
            Triple("ㄉㄨㄟˋ-ㄉㄜ˙", "對的", -3.0),
        ))
        val tryIt = listOf("ㄨㄛˇ", "ㄕˋ", "ㄕˋ", "ㄎㄢˋ")
        assertEquals("我試試看", e.candidates(tryIt).first().text)
        assertEquals(tryIt.size, e.candidates(tryIt).first().span)
        val long = listOf(
            "ㄎㄚˇ", "ㄎㄚˇ", "ㄉㄜ˙", "ㄒㄩㄢˇ", "ㄗˋ", "ㄉㄡ", "ㄇㄟˊ", "ㄧㄡˇ",
            "ㄍㄟˇ", "ㄉㄧˋ", "ㄧ", "ㄍㄜ˙", "ㄏㄨㄟˋ", "ㄕˋ", "ㄉㄨㄟˋ", "ㄉㄜ˙",
        )
        assertEquals("卡卡的選字都沒有給第一個會是對的", e.candidates(long).first().text)
        assertEquals(long.size, e.candidates(long).first().span)
    }

    @Test fun sentences() {
        val e = engine()
        assertEquals("你好", sentence(e, listOf("ㄋㄧˇ", "ㄏㄠˇ")))
        assertEquals("你好世界", sentence(e, listOf("ㄋㄧˇ", "ㄏㄠˇ", "ㄕˋ", "ㄐㄧㄝˋ")))
        val c = e.candidates(listOf("ㄋㄧˇ", "ㄏㄠˇ"))
        assertEquals(Candidate("你好", 2, Candidate.Kind.SENTENCE), c.first())
        assertTrue(c.contains(Candidate("妳", 1, Candidate.Kind.PHRASE)))
        assertEquals(listOf("是", "事", "世"), e.candidates(listOf("ㄕˋ")).map { it.text })
        assertTrue(e.candidates(listOf("ㄅㄧㄤ")).none { ZhuyinEngine.commit(it.text) != it.text })
    }

    @Test fun learningAndAssociations() {
        val e = engine()
        e.learn(listOf("ㄋㄧˇ"), "妳"); e.learn(listOf("ㄋㄧˇ"), "妳")
        assertEquals("妳", e.phrases(listOf("ㄋㄧˇ")).first().text)
        e.resetLearning()
        assertEquals("你", e.phrases(listOf("ㄋㄧˇ")).first().text)
        assertTrue(e.associations("你").containsAll(listOf("好", "們")))
        assertEquals(listOf("界"), e.associations("世"))
    }

    @Test fun fuzzy() {
        val e = engine(listOf(Triple("ㄋㄧ", "妮", -5.5)))
        assertEquals("你好", sentence(e, listOf("ㄋㄧ", "ㄏㄠˇ")))
        e.fuzzy = e.fuzzy.copy(tones = false)
        assertEquals("妮好", sentence(e, listOf("ㄋㄧ", "ㄏㄠˇ")))
        val f = engine()
        assertEquals("你好", sentence(f, listOf("ㄋㄧˇ", "ㄏㄡˇ")))
        assertTrue(f.candidates(listOf("ㄙˋ")).none { ZhuyinEngine.commit(it.text) != it.text })
        f.fuzzy = f.fuzzy.copy(phonetic = true)
        assertEquals("是", f.candidates(listOf("ㄙˋ")).first().text)
        assertEquals(setOf('ㄝ', 'ㄥ', 'ㄠ'), Bopomofo.neighbors['ㄡ']!!.toSet())
        val g = engine(listOf(Triple("ㄕ", "詩", -4.0)))
        assertEquals("詩", g.candidates(listOf("ㄕ")).first().text)
    }

    private fun typeHangul(jamo: String): String {
        val h = HangulComposer()
        val doc = StringBuilder()
        var shown = ""
        for (c in jamo) {
            val out = h.input(c)
            doc.setLength(doc.length - shown.length)
            doc.append(out.commit).append(out.composing)
            shown = out.composing
        }
        return doc.toString()
    }

    @Test fun hangul() {
        assertEquals("한글", typeHangul("ㅎㅏㄴㄱㅡㄹ"))
        assertEquals("안녕", typeHangul("ㅇㅏㄴㄴㅕㅇ"))
        assertEquals("닭", typeHangul("ㄷㅏㄹㄱ"))
        assertEquals("달가", typeHangul("ㄷㅏㄹㄱㅏ"))
        assertEquals("와", typeHangul("ㅇㅘ"))
        assertEquals("ㅋㅋㅋ", typeHangul("ㅋㅋㅋ"))
    }

    @Test fun romaji() {
        assertEquals("こんにちは", Romaji.finalize("konnichiha"))
        assertEquals("きって", Romaji.finalize("kitte"))
        assertEquals("きょう", Romaji.finalize("kyou"))
        assertEquals("しんぶん", Romaji.finalize("shinbun"))
        assertEquals("らーめん", Romaji.finalize("ra-men"))
        assertEquals("k", Romaji.convert("sak").second)
        assertEquals("コーヒー", Romaji.katakana(Romaji.finalize("ko-hi-")))
    }

    @Test fun spelling() {
        assertEquals(1, Spelling.editDistance("teh", "the"))
        assertTrue(Spelling.isCloseEnough("recieve", "receive"))
        assertFalse(Spelling.isCloseEnough("cat", "dog"))
        assertEquals("Hello", Spelling.matchCase("hello", "Helo"))
    }

    @Test fun clipboard() {
        val s = ClipboardStore(null, 3)
        s.add("a"); s.add("b"); s.add("c"); s.add("a")
        assertEquals(listOf("a", "c", "b"), s.ordered.map { it.text })
        s.togglePin(s.items.last().id)
        s.add("d"); s.add("e"); s.add("f")
        assertEquals(listOf("b", "f", "e", "d"), s.ordered.map { it.text })
        assertFalse(s.add("   "))
    }

    @Test fun release() {
        assertEquals(12, ReleaseChecker.buildNumber("android-12"))
        assertNull(ReleaseChecker.buildNumber("build-12"))
        val json = """[{"tag_name":"build-9","name":"iOS","assets":[]},
            {"tag_name":"android-3","name":"Android 第 3 版","body":"這次更新","html_url":"https://x/3",
             "assets":[{"name":"StarKeyboard.apk","browser_download_url":"https://x/a.apk"}]},
            {"tag_name":"android-2","name":"舊的","assets":[]}]"""
        val info = ReleaseChecker.parseLatest(json)!!
        assertEquals(3, info.build)
        assertEquals("https://x/a.apk", info.apkUrl)
    }

    @Test fun clipboardEditKeepsOriginalUntilSave() {
        val store = ClipboardStore(null)
        assertTrue(store.add("原來的文字"))
        val id = store.items[0].id
        assertFalse(store.updateText(id, "   "))
        assertEquals("原來的文字", store.items[0].text)
        assertTrue(store.updateText(id, "改過了"))
        assertEquals(id, store.items[0].id)
        assertEquals("改過了", store.items[0].text)
    }

    @Test fun randomKeysNeverCommitToneMarks() {
        val e = engine()
        val keys = "ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙㄧㄨㄩㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦˊˇˋ˙".toList()
        var state = 0xC0FFEEL
        fun next(): Long {
            state = state * 6364136223846793005L + 1L
            return state
        }
        val doc = StringBuilder()
        repeat(2000) {
            val composer = ZhuyinComposer()
            val count = 1 + (next().ushr(33) % 8).toInt()
            repeat(count) {
                val roll = next().ushr(33) % 8
                if (roll == 0L) composer.backspace()
                else composer.input(keys[(next().ushr(33) % keys.size).toInt()])
            }
            val text = ZhuyinEngine.commit(e.bestSegments(composer.readings).joinToString("") { it.text })
            doc.append(text)
            assertEquals(text, ZhuyinEngine.commit(text))
            assertFalse(text.any { Bopomofo.kind(it) != null })
        }
        assertFalse(doc.any { Bopomofo.kind(it) != null })
    }

    @Test fun symbols() {
        for (group in listOf(SymbolData.emoji, SymbolData.kaomoji, SymbolData.symbols)) {
            for (cat in group) assertTrue(cat.title, cat.items.isNotEmpty() && "" !in cat.items)
        }
        assertEquals(8, SymbolData.emoji.size)
        assertTrue(SymbolData.symbols.first { it.title == "單位" }.items.contains("$"))
    }

    @Test fun markdownSymbolsAreAscii() {
        for (ch in SymbolPages.MARKDOWN) {
            assertTrue("$ch", SymbolPages.isAscii(ch))
        }
        val zhuyin = SymbolPages.ZHUYIN_SYMBOL_ROW1 + SymbolPages.ZHUYIN_SYMBOL_ROW2
        val numbers = SymbolPages.ZHUYIN_NUMBER_ROW2 + SymbolPages.ZHUYIN_NUMBER_ROW3
        for (ch in SymbolPages.MARKDOWN) {
            assertTrue(zhuyin.contains(ch))
        }
        for (ch in "-/$@.") assertTrue(numbers.contains(ch) && SymbolPages.isAscii(ch))
        assertFalse(zhuyin.contains('＊'))
        assertFalse(zhuyin.contains('＃'))
        assertEquals(10, SymbolPages.ZHUYIN_SYMBOL_ROW1.length)
        assertEquals(10, SymbolPages.ZHUYIN_NUMBER_ROW2.length)
    }

    @Test fun exactLengthAndLearning() {
        val e = engine(listOf(
            Triple("ㄊㄨㄟ", "推", -3.5), Triple("ㄊㄨㄟˇ", "腿", -4.7), Triple("ㄐㄧㄢ", "間", -3.1),
            Triple("ㄊㄨㄟ-ㄐㄧㄢˋ", "推薦", -4.34),
            Triple("ㄊㄨㄟ-ㄐㄧㄢˋ-ㄒㄧㄣˋ", "推薦信", -5.44),
            Triple("ㄋㄧˇ-ㄕˋ", "你是", -4.32),
            Triple("ㄋㄚˋ-ㄕˋ", "那是", -3.2),
            Triple("ㄋㄧㄠˋ-ㄕ-ㄐㄧㄣˋ", "尿失禁", -5.51),
            Triple("ㄐㄧㄡˋ", "就", -2.7), Triple("ㄐㄧㄡˋ-ㄕˋ", "就是", -3.05),
            Triple("ㄕˋ", "試", -7.5),
        ))
        val recommend = e.candidates(listOf("ㄊㄨㄟ*", "ㄐㄧㄢ*"))
        assertEquals("推薦", recommend.first().text)
        assertTrue(recommend.take(3).all { it.text.length <= 2 })
        val youAre = e.candidates(listOf("ㄋㄧ*", "ㄕ*"))
        assertEquals("你是", youAre.first().text)
        assertTrue(youAre.take(3).all { it.text.length <= 2 })
        assertFalse(e.candidates(listOf("ㄐㄧㄡˋ", "ㄕˋ", "ㄕˋ")).first().text == "就是是")
        assertEquals(3, e.candidates(listOf("ㄐㄧㄡˋ", "ㄕˋ", "ㄕˋ")).first().text.length)
        assertEquals("是", e.candidates(listOf("ㄕˋ")).first().text)
        e.learn(listOf("ㄕˋ"), "試")
        assertEquals("試", e.candidates(listOf("ㄕˋ")).first().text)
        assertEquals("那是", e.candidates(listOf("ㄋ*", "ㄕ*")).first().text)
        e.learn(listOf("ㄋㄧˇ", "ㄕˋ"), "你是")
        assertEquals("你是", e.candidates(listOf("ㄋ*", "ㄕ*")).first().text)
    }
}
