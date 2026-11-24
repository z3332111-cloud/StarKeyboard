package com.startown.starkeyboard.ime

import com.startown.starkeyboard.core.Bopomofo
import com.startown.starkeyboard.core.SymbolPages

enum class KeyboardLayer { LETTERS, NUMBERS, SYMBOLS, NUMPAD }
enum class ShiftState { OFF, ON, LOCKED }
enum class PanelKind { EMOJI, KAOMOJI, SYMBOLS, CLIPBOARD, SETTINGS }

sealed class KeyAction {
    data class Text(val s: String) : KeyAction()
    data class Zhuyin(val c: Char) : KeyAction()
    data class Jamo(val c: Char) : KeyAction()      // 韓文字母
    data class Romaji(val c: Char) : KeyAction()    // 日文羅馬拼音
    data class Pinyin(val c: Char) : KeyAction()    // 漢語拼音
    data class Layer(val layer: KeyboardLayer) : KeyAction()
    data class Panel(val kind: PanelKind) : KeyAction()
    object Backspace : KeyAction()
    object Space : KeyAction()
    object Return : KeyAction()
    object Shift : KeyAction()
    object NextMode : KeyAction()
    object ClearCanvas : KeyAction()
    object ToggleWidth : KeyAction()   // 中文符號頁切換全形／半形

    /** 一般打字的鍵：可以滑動修正、快速連打 */
    val isCharacter get() = this is Text || this is Zhuyin || this is Jamo || this is Romaji || this is Pinyin

    /** 大鍵：機械鍵盤上有衛星軸的那幾顆，按鍵聲比較低沉 */
    val isBig get() = this == Space || this == Return || this == Backspace || this == Shift
}

enum class KeyKind { NORMAL, SPECIAL, ACCENT }

data class KeySpec(
    val label: String,
    val action: KeyAction,
    val width: Float = 1f,          // 以「一個字母鍵」為單位；0 = 填滿剩下的寬度
    val kind: KeyKind = KeyKind.NORMAL,
    val fontSize: Float = 23f,
    val hint: String = "",          // 右上角的小字：長按這顆鍵會打出它（Gboard 式注音的數字、字母）
    val popup: List<String> = emptyList(),   // 按住會跳出一排字，手指滑過去放開就打出那個
) {
    companion object {
        val PUNCTUATION_POPUP = listOf("，", "。", "？", "！", "、", "：", "；", "…", "「", "」", "～", "@", "#", "%")
    }
}

data class KeyboardLayout(val rows: List<List<KeySpec>>, val columns: Float)

/** 和 iPhone 版 KeyLayouts.swift 一樣的排法 */
object KeyLayouts {
    data class Context(
        val mode: InputMode,
        val layer: KeyboardLayer,
        val shift: ShiftState,
        val returnTitle: String,
        val spaceTitle: String,
        val nextModeTitle: String,
        val fullWidthSymbols: Boolean = false,
        val zhuyinTenColumns: Boolean = false,
    )

    fun layout(c: Context): KeyboardLayout {
        val chinese = c.mode != InputMode.ENGLISH && c.mode != InputMode.KOREAN
        return when (c.layer) {
            KeyboardLayer.LETTERS -> when (c.mode) {
                InputMode.ZHUYIN -> zhuyin(c)
                InputMode.KOREAN -> korean(c)
                InputMode.JAPANESE -> japanese(c)
                InputMode.PINYIN -> pinyin(c)
                else -> english(c)
            }
            KeyboardLayer.NUMBERS -> if (chinese) chineseNumbers(c) else englishNumbers(c)
            KeyboardLayer.SYMBOLS -> if (chinese) chineseSymbols(c) else englishSymbols(c)
            KeyboardLayer.NUMPAD -> numpad(c)
        }
    }

    /** 手寫畫面右邊那一排 */
    fun handwritingSide(returnTitle: String, nextModeTitle: String) = KeyboardLayout(listOf(
        listOf(KeySpec("⌫", KeyAction.Backspace, kind = KeyKind.SPECIAL, fontSize = 20f)),
        listOf(KeySpec("重寫", KeyAction.ClearCanvas, kind = KeyKind.SPECIAL, fontSize = 15f)),
        listOf(KeySpec("123", KeyAction.Layer(KeyboardLayer.NUMBERS), kind = KeyKind.SPECIAL, fontSize = 15f)),
        listOf(KeySpec("空白", KeyAction.Space, fontSize = 15f)),
        listOf(KeySpec(nextModeTitle, KeyAction.NextMode, kind = KeyKind.SPECIAL, fontSize = 17f)),
        listOf(KeySpec("↵", KeyAction.Return, kind = KeyKind.ACCENT, fontSize = 22f)),
    ), 1f)

    private fun keys(chars: String, size: Float = 23f, width: Float = 1f) =
        chars.map { KeySpec(it.toString(), KeyAction.Text(it.toString()), width, KeyKind.NORMAL, size) }

    private fun backspace(width: Float = 1.4f) = KeySpec("⌫", KeyAction.Backspace, width, KeyKind.SPECIAL, 20f)

    private fun shiftKey(shift: ShiftState) =
        KeySpec(if (shift == ShiftState.LOCKED) "⇪" else if (shift == ShiftState.ON) "⬆" else "⇧", KeyAction.Shift, 1.4f, KeyKind.SPECIAL, 21f)

    private fun bottomRow(c: Context, columns: Float): List<KeySpec> {
        val k = columns / 10f
        val letters = c.layer == KeyboardLayer.LETTERS
        if (letters && c.mode == InputMode.PINYIN) {
            // 拼音照三星的排法：!#1 開符號、空白鍵兩邊是逗號句號、123 開數字鍵盤
            return listOf(
                KeySpec("!#1", KeyAction.Layer(KeyboardLayer.NUMBERS), 1.3f * k, KeyKind.SPECIAL, 16f),
                KeySpec(c.nextModeTitle, KeyAction.NextMode, 1.1f * k, KeyKind.SPECIAL, 17f),
                KeySpec("，", KeyAction.Text("，"), 0.9f * k, KeyKind.NORMAL, 20f, popup = KeySpec.PUNCTUATION_POPUP),
                KeySpec(c.spaceTitle, KeyAction.Space, 0f, KeyKind.NORMAL, 15f),
                KeySpec("。", KeyAction.Text("。"), 0.9f * k, KeyKind.NORMAL, 20f, popup = KeySpec.PUNCTUATION_POPUP),
                KeySpec("123", KeyAction.Layer(KeyboardLayer.NUMPAD), 1.1f * k, KeyKind.SPECIAL, 16f),
                KeySpec("↵", KeyAction.Return, 1.6f * k, KeyKind.ACCENT, 22f),
            )
        }
        val layerKey = if (letters) {
            KeySpec("123", KeyAction.Layer(KeyboardLayer.NUMBERS), 1.3f * k, KeyKind.SPECIAL, 16f)
        } else {
            val title = when (c.mode) {
                InputMode.ZHUYIN -> "ㄅㄆㄇ"
                InputMode.ENGLISH -> "ABC"
                InputMode.HANDWRITING -> "手寫"
                InputMode.KOREAN -> "한글"
                InputMode.JAPANESE -> "かな"
                InputMode.PINYIN -> "拼音"
            }
            KeySpec(title, KeyAction.Layer(KeyboardLayer.LETTERS), 1.3f * k, KeyKind.SPECIAL, 14f)
        }
        return listOf(
            layerKey,
            // 123 和符號頁：這格換成大顆的數字鍵盤
            if (letters) KeySpec(c.nextModeTitle, KeyAction.NextMode, 1.1f * k, KeyKind.SPECIAL, 17f)
            else KeySpec("數字", KeyAction.Layer(KeyboardLayer.NUMPAD), 1.1f * k, KeyKind.SPECIAL, 15f),
            KeySpec("☺︎", KeyAction.Panel(PanelKind.EMOJI), 1.1f * k, KeyKind.SPECIAL, 21f),
            KeySpec(c.spaceTitle, KeyAction.Space, 0f, KeyKind.NORMAL, 15f),
            KeySpec("↵", KeyAction.Return, 2f * k, KeyKind.ACCENT, 22f),
        )
    }

    private fun zhuyin(c: Context): KeyboardLayout {
        if (c.zhuyinTenColumns) return zhuyinTen(c)
        val rows = Bopomofo.dachenRows.map { line -> line.map { KeySpec(it.toString(), KeyAction.Zhuyin(it), fontSize = 20f) } }.toMutableList()
        rows[3] = rows[3] + backspace(1f)
        rows.add(bottomRow(c, 11f))
        return KeyboardLayout(rows, 11f)
    }

    /** 注音十欄（像 Gboard）：ㄦ 搬到空白鍵旁邊，每顆鍵右上角有數字／字母，長按就打出來 */
    private fun zhuyinTen(c: Context): KeyboardLayout {
        val hints = listOf(
            "1234567890".map { it.toString() },
            "qwertyuiop".map { it.toString() },
            "asdfghjkl".map { it.toString() } + "：",
            "zxcvbnm".map { it.toString() } + listOf("……", "！", "？"),
        )
        val rows = Bopomofo.dachenRows.mapIndexed { r, line ->
            line.filter { it != 'ㄦ' }.mapIndexed { i, ch -> KeySpec(ch.toString(), KeyAction.Zhuyin(ch), fontSize = 21f, hint = hints[r][i]) }
        }
        val bottom = listOf(
            KeySpec("123", KeyAction.Layer(KeyboardLayer.NUMBERS), 1.2f, KeyKind.SPECIAL, 16f),
            KeySpec(c.nextModeTitle, KeyAction.NextMode, 1f, KeyKind.SPECIAL, 17f),
            KeySpec("，", KeyAction.Text("，"), 1f, KeyKind.NORMAL, 20f, hint = "。", popup = KeySpec.PUNCTUATION_POPUP),
            KeySpec(c.spaceTitle, KeyAction.Space, 0f, KeyKind.NORMAL, 15f),
            KeySpec("ㄦ", KeyAction.Zhuyin('ㄦ'), 1f, KeyKind.NORMAL, 21f),
            backspace(1.2f),
            KeySpec("↵", KeyAction.Return, 1.5f, KeyKind.ACCENT, 22f),
        )
        return KeyboardLayout(rows + listOf(bottom), 10f)
    }

    private fun english(c: Context): KeyboardLayout {
        val upper = c.shift != ShiftState.OFF
        fun letters(s: String) = keys(if (upper) s.uppercase() else s, 24f)
        val row3 = listOf(shiftKey(c.shift)) + letters("zxcvbnm") + backspace()
        return KeyboardLayout(listOf(letters("qwertyuiop"), letters("asdfghjkl"), row3, bottomRow(c, 10f)), 10f)
    }

    /** 韓文兩排式，Shift 打雙子音和 ㅒㅖ */
    private fun korean(c: Context): KeyboardLayout {
        fun jamo(s: String) = s.map { KeySpec(it.toString(), KeyAction.Jamo(it), fontSize = 21f) }
        val top = if (c.shift == ShiftState.OFF) "ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔ" else "ㅃㅉㄸㄲㅆㅛㅕㅑㅒㅖ"
        val row3 = listOf(shiftKey(c.shift)) + jamo("ㅋㅌㅊㅍㅠㅜㅡ") + backspace()
        return KeyboardLayout(listOf(jamo(top), jamo("ㅁㄴㅇㄹㅎㅗㅓㅏㅣ"), row3, bottomRow(c, 10f)), 10f)
    }

    /** 日文：打羅馬拼音，左下角是長音「ー」 */
    private fun japanese(c: Context): KeyboardLayout {
        fun letters(s: String) = s.map { KeySpec(it.toString(), KeyAction.Romaji(it), fontSize = 24f) }
        val row3 = listOf(KeySpec("ー", KeyAction.Romaji('-'), 1.4f, KeyKind.SPECIAL, 20f)) + letters("zxcvbnm") + backspace()
        return KeyboardLayout(listOf(letters("qwertyuiop"), letters("asdfghjkl"), row3, bottomRow(c, 10f)), 10f)
    }

    /** 漢語拼音（照三星鍵盤）：最上面一排數字，左下角是分音節的「'」（例如 xi'an） */
    private fun pinyin(c: Context): KeyboardLayout {
        fun letters(s: String) = s.map { KeySpec(it.toString(), KeyAction.Pinyin(it), fontSize = 24f) }
        val row3 = listOf(KeySpec("'", KeyAction.Pinyin('\''), 1.4f, KeyKind.SPECIAL, 22f)) + letters("zxcvbnm") + backspace()
        return KeyboardLayout(listOf(keys("1234567890", 20f), letters("qwertyuiop"), letters("asdfghjkl"), row3, bottomRow(c, 10f)), 10f)
    }

    /** 大顆的數字鍵盤（打電話號碼、金額用）：中間 1–9、0，兩邊常用符號 */
    private fun numpad(c: Context): KeyboardLayout {
        val back = when (c.mode) {
            InputMode.ZHUYIN -> "ㄅㄆㄇ"
            InputMode.ENGLISH -> "ABC"
            InputMode.HANDWRITING -> "手寫"
            InputMode.KOREAN -> "한글"
            InputMode.JAPANESE -> "かな"
            InputMode.PINYIN -> "拼音"
        }
        fun side(s: String) = KeySpec(s, KeyAction.Text(s), 1f, KeyKind.SPECIAL, 22f)
        return KeyboardLayout(listOf(
            listOf(side("-")) + keys("123", 26f) + backspace(1f),
            listOf(side("@")) + keys("456", 26f) + side("."),
            listOf(side(":")) + keys("789", 26f) + side(","),
            listOf(
                KeySpec("!#1", KeyAction.Layer(KeyboardLayer.NUMBERS), 1f, KeyKind.SPECIAL, 16f),
                KeySpec(back, KeyAction.Layer(KeyboardLayer.LETTERS), 1f, KeyKind.SPECIAL, 14f),
            ) + keys("0", 26f) + listOf(
                KeySpec("␣", KeyAction.Space, 1f, KeyKind.SPECIAL, 20f),
                KeySpec("↵", KeyAction.Return, 1f, KeyKind.ACCENT, 22f),
            ),
        ), 5f)
    }

    private fun englishNumbers(c: Context): KeyboardLayout {
        val row3 = listOf(KeySpec("#+=", KeyAction.Layer(KeyboardLayer.SYMBOLS), 1.4f, KeyKind.SPECIAL, 16f)) + keys(".,?!'", width = 1.4f) + backspace()
        return KeyboardLayout(listOf(keys("1234567890"), keys("-/:;()\$&@\""), keys(SymbolPages.ENGLISH_NUMBER_EXTRA), row3, bottomRow(c, 10f)), 10f)
    }

    private fun englishSymbols(c: Context): KeyboardLayout {
        val row3 = listOf(KeySpec("123", KeyAction.Layer(KeyboardLayer.NUMBERS), 1.4f, KeyKind.SPECIAL, 16f)) + keys(".,?!'", width = 1.4f) + backspace()
        return KeyboardLayout(listOf(keys(SymbolPages.ENGLISH_SYMBOL_ROW1), keys(SymbolPages.ENGLISH_SYMBOL_ROW2), row3, bottomRow(c, 10f)), 10f)
    }

    /** 注音的 123 頁，和 iPhone 注音鍵盤同一排列。標點用全形，減號、斜線、錢號、小老鼠和句點用半形。 */
    private fun chineseNumbers(c: Context): KeyboardLayout {
        val full = c.fullWidthSymbols
        val toggle = KeySpec(if (full) "全形" else "半形", KeyAction.ToggleWidth, 1.1f, KeyKind.SPECIAL, 14f)
        val row3 = listOf(KeySpec("#+=", KeyAction.Layer(KeyboardLayer.SYMBOLS), 1.25f, KeyKind.SPECIAL, 16f)) +
            keys(if (full) SymbolPages.ZHUYIN_NUMBER_ROW3 else SymbolPages.ZHUYIN_NUMBER_ROW3_HALF, 20f, 1.05f) + toggle + backspace(1.35f)
        return KeyboardLayout(listOf(keys("1234567890"), keys(if (full) SymbolPages.ZHUYIN_NUMBER_ROW2 else SymbolPages.ZHUYIN_NUMBER_ROW2_HALF, 20f),
            keys(SymbolPages.ZHUYIN_NUMBER_EXTRA, 20f), row3, bottomRow(c, 10f)), 10f)
    }

    /** 注音的 #+= 頁。Markdown 用的符號永遠半形；中文標點維持全形。 */
    private fun chineseSymbols(c: Context): KeyboardLayout {
        val toggle = KeySpec(if (c.fullWidthSymbols) "全形" else "半形", KeyAction.ToggleWidth, 1.1f, KeyKind.SPECIAL, 14f)
        val row3 = listOf(KeySpec("123", KeyAction.Layer(KeyboardLayer.NUMBERS), 1.25f, KeyKind.SPECIAL, 16f)) +
            keys("『』♡☆‧→※", 18f, 0.9f) + toggle + backspace(1.35f)
        return KeyboardLayout(listOf(
            keys(SymbolPages.ZHUYIN_SYMBOL_ROW1, 18f),
            keys(SymbolPages.ZHUYIN_SYMBOL_ROW2, 18f),
            row3,
            bottomRow(c, 10f),
        ), 10f)
    }
}
