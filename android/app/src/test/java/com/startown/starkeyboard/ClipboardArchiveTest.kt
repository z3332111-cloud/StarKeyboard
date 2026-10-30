package com.startown.starkeyboard
import com.startown.starkeyboard.core.*
import org.junit.Assert.*
import org.junit.Test
class ClipboardArchiveTest {
    @Test fun roundTripAndCompatibleFormats() {
        val items = listOf(ClipItem("1", "甲\n乙😀", true, 0), ClipItem("2", "保留", false, 0))
        val rows = ClipboardArchive.decode(ClipboardArchive.encode(items))
        assertEquals(items.map { it.text }, rows.map { it.text })
        assertTrue(rows[0].pinned)
        assertEquals(2, ClipboardArchive.decode("""["你好",{"content":"世界"}]""".toByteArray()).size)
        assertEquals(listOf("甲", "乙"), ClipboardArchive.decode("甲\r\n乙\n".toByteArray(), true).map { it.text })
    }
    @Test fun rejectsInvalidAndOversizeData() {
        for (input in listOf("broken", """[{"password":"x"}]""", """{"format":"nuonuo-clipboard","version":2,"items":[]}""")) {
            assertTrue(runCatching { ClipboardArchive.decode(input.toByteArray()) }.isFailure)
        }
        assertTrue(runCatching { ClipboardArchive.decode(ByteArray(ClipboardArchive.MAX_BYTES + 1)) }.isFailure)
    }
    @Test fun persistenceAndFailedWriteLeaveOriginalMemory() {
        val dir = java.nio.file.Files.createTempDirectory("clipboard-test").toFile()
        try {
            val file = java.io.File(dir, "clipboard.json")
            val store = ClipboardStore(file)
            store.importEntries(listOf(ClipboardArchive.Entry("甲\n乙", true)))
            assertEquals("甲\n乙", ClipboardStore(file).items.single().text)
            val bad = ClipboardStore(dir)
            assertTrue(runCatching { bad.importEntries(listOf(ClipboardArchive.Entry("不可加入"))) }.isFailure)
            assertTrue(bad.items.isEmpty())
        } finally { dir.deleteRecursively() }
    }
    @Test fun mergeKeepsExistingAndCapacity() {
        val store = ClipboardStore(null, 2); store.add("原本")
        val r = store.importEntries(listOf(ClipboardArchive.Entry("新增"), ClipboardArchive.Entry("新增"), ClipboardArchive.Entry("超額"), ClipboardArchive.Entry("原本")))
        assertEquals(1, r.added); assertEquals(2, r.duplicates); assertEquals(1, r.skipped)
        assertEquals(listOf("新增", "原本"), store.items.map { it.text })
        store.importEntries(listOf(ClipboardArchive.Entry("原本", true)))
        assertTrue(store.items.first { it.text == "原本" }.pinned)
    }
}
