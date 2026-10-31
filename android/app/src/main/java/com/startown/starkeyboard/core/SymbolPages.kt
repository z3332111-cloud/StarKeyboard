package com.startown.starkeyboard.core

/** 符號頁要送出的字。程式／Markdown 用的符號一律半形，中文標點維持全形。和 iOS SymbolPages 同一套字。 */
object SymbolPages {
    const val MARKDOWN = "`*_~|#\\^+=[]{}<>%"
    const val ZHUYIN_SYMBOL_ROW1 = "`*_~|#\\^+="
    const val ZHUYIN_SYMBOL_ROW2 = "{[]<>%}～—…"
    const val ZHUYIN_NUMBER_ROW2 = "-/：；（）$@「」"
    const val ZHUYIN_NUMBER_ROW3 = "。，、？！."
    const val ENGLISH_SYMBOL_ROW1 = "[]{}#%^*+="
    const val ENGLISH_SYMBOL_ROW2 = "_\\|~<>€£¥`"

    fun isAscii(c: Char) = c.code < 128
}
