package com.startown.starkeyboard

import com.startown.starkeyboard.ime.DeleteChunk
import org.junit.Assert.assertEquals
import org.junit.Test

/** 長按刪除久了，一次刪一段：英文一個字、中文最多四個字、前面的空白一起刪 */
class DeleteChunkTest {
    @Test fun englishWord() = assertEquals(5, DeleteChunk.length("say hello"))
    @Test fun trailingSpacesGoWithWord() = assertEquals(7, DeleteChunk.length("say hello  "))
    @Test fun chineseUpToFour() = assertEquals(4, DeleteChunk.length("今天天氣很好"))
    @Test fun shortChinese() = assertEquals(2, DeleteChunk.length("ok 你好"))
    @Test fun punctuationOne() = assertEquals(1, DeleteChunk.length("你好！"))
    @Test fun emojiIsTwoUnits() = assertEquals(2, DeleteChunk.length("嗨😀"))
    @Test fun onlySpaces() = assertEquals(3, DeleteChunk.length("   "))
}
