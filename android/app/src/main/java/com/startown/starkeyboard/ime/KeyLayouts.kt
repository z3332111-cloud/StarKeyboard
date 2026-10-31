package com.startown.starkeyboard.ime

import com.startown.starkeyboard.core.Bopomofo

enum class KeyboardLayer { LETTERS, NUMBERS, SYMBOLS }
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
}

enum class KeyKind { NORMAL, SPECIAL, ACCENT }

data class KeySpec(
    val label: String,
    val action: KeyAction,
    val width: Float = 1f,          // 以「一個字母鍵」為單位；0 = 填滿剩下的寬度
    val kind: KeyKind = KeyKind.NORMAL,
    val fontSize: Float = 23f,
)

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
        }
    }

    /** 手寫畫面右邊那一排 */
    fun handwritingSide(returnTitle: String, nextModeTitle: String) = KeyboardLayout(listOf(
        listOf(KeySpec("⌫", KeyAction.Backspace, kind = KeyKind.SPECIAL, fontSize = 20f)),
        listOf(KeySpec("重寫", KeyAction.ClearCanvas, kind = KeyKind.SPECIAL, fontSize = 15f)),
        listOf(KeySpec("123", KeyAction.Layer(KeyboardLayer.NUMBERS), kind = KeyKind.SPECIAL, fontSize = 15f)),
        listOf(KeySpec("空白", KeyAction.Space, fontSize = 15f)),
        listOf(KeySpec(nextModeTitle, KeyAction.NextMode, kind = KeyKind.SPECIAL, fontSize = 17f)),
        listOf(KeySpec(returnTitle, KeyAction.Return, kind = KeyKind.ACCENT, fontSize = 15f)),
    ), 1f)

    private fun keys(chars: String, size: Float = 23f, width: Float = 1f) =
        chars.map { KeySpec(it.toString(), KeyAction.Text(it.toString()), width, KeyKind.NORMAL, size) }

    private fun backspace(width: Float = 1.4f) = KeySpec("⌫", KeyAction.Backspace, width, KeyKind.SPECIAL, 20f)

    private fun shiftKey(shift: ShiftState) =
        KeySpec(if (shift == ShiftState.LOCKED) "⇪" else if (shift == ShiftState.ON) "⬆" else "⇧", KeyAction.Shift, 1.4f, KeyKind.SPECIAL, 21f)

    private fun bottomRow(c: Context, columns: Float): List<KeySpec> {
        val k = columns / 10f
        val layerKey = if (c.layer == KeyboardLayer.LETTERS) {
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
            KeySpec(c.nextModeTitle, KeyAction.NextMode, 1.1f * k, KeyKind.SPECIAL, 17f),
            KeySpec("☺︎", KeyAction.Panel(PanelKind.EMOJI), 1.1f * k, KeyKind.SPECIAL, 21f),
            KeySpec(c.spaceTitle, KeyAction.Space, 0f, KeyKind.NORMAL, 15f),
            KeySpec(c.returnTitle, KeyAction.Return, 2f * k, KeyKind.ACCENT, 16f),
        )
    }

    private fun zhuyin(c: Context): KeyboardLayout {
        val rows = Bopomofo.dachenRows.map { line -> line.map { KeySpec(it.toString(), KeyAction.Zhuyin(it), fontSize = 20f) } }.toMutableList()
        rows[3] = rows[3] + backspace(1f)
        rows.add(bottomRow(c, 11f))
        return KeyboardLayout(rows, 11f)
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

    /** 漢語拼音：左下角是分音節的「'」（例如 xi'an） */
    private fun pinyin(c: Context): KeyboardLayout {
        fun letters(s: String) = s.map { KeySpec(it.toString(), KeyAction.Pinyin(it), fontSize = 24f) }
        val row3 = listOf(KeySpec("'", KeyAction.Pinyin('\''), 1.4f, KeyKind.SPECIAL, 22f)) + letters("zxcvbnm") + backspace()
        return KeyboardLayout(listOf(letters("qwertyuiop"), letters("asdfghjkl"), row3, bottomRow(c, 10f)), 10f)
    }

    private fun englishNumbers(c: Context): KeyboardLayout {
        val row3 = listOf(KeySpec("#+=", KeyAction.Layer(KeyboardLayer.SYMBOLS), 1.4f, KeyKind.SPECIAL, 16f)) + keys(".,?!'", width = 1.4f) + backspace()
        return KeyboardLayout(listOf(keys("1234567890"), keys("-/:;()\$&@\""), row3, bottomRow(c, 10f)), 10f)
    }

    private fun englishSymbols(c: Context): KeyboardLayout {
        val row3 = listOf(KeySpec("123", KeyAction.Layer(KeyboardLayer.NUMBERS), 1.4f, KeyKind.SPECIAL, 16f)) + keys(".,?!'", width = 1.4f) + backspace()
        return KeyboardLayout(listOf(keys("[]{}#%^*+="), keys("_\\|~<>€£¥•"), row3, bottomRow(c, 10f)), 10f)
    }

    /** 注音的 123 頁，和 iPhone 注音鍵盤同一排列。標點用全形，減號、斜線、錢號、小老鼠和句點用半形。 */
    private fun chineseNumbers(c: Context): KeyboardLayout {
        val row3 = listOf(KeySpec("#+=", KeyAction.Layer(KeyboardLayer.SYMBOLS), 1.4f, KeyKind.SPECIAL, 16f)) + keys("。，、？！.", 20f, 1.2f) + backspace()
        return KeyboardLayout(listOf(keys("1234567890"), keys("-/：；（）\$@「」", 20f), row3, bottomRow(c, 10f)), 10f)
    }

    /** 注音的 #+= 頁，對齊 iPhone 的第二頁；123 頁放不下的 ～ — 『』 … ♡ 等仍留在這裡。 */
    private fun chineseSymbols(c: Context): KeyboardLayout {
        val toggle = KeySpec(if (c.fullWidthSymbols) "全形" else "半形", KeyAction.ToggleWidth, 1.1f, KeyKind.SPECIAL, 14f)
        val row3 = listOf(KeySpec("123", KeyAction.Layer(KeyboardLayer.NUMBERS), 1.25f, KeyKind.SPECIAL, 16f)) +
            keys("『』♡☆‧→※", 18f, 0.9f) + toggle + backspace(1.35f)
        val rows = if (c.fullWidthSymbols) {
            listOf("【】｛｝＃％＾＊＋＝", "＿＼｜～〈〉《》…—")
        } else {
            listOf("[]{}#%^*+=", "_\\|~<>«»…—")
        }
        return KeyboardLayout(listOf(keys(rows[0], 18f), keys(rows[1], 18f), row3, bottomRow(c, 10f)), 10f)
    }
}
