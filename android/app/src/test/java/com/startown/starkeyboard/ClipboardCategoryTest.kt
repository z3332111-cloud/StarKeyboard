package com.startown.starkeyboard
import com.startown.starkeyboard.core.*
import org.junit.Assert.*
import org.junit.Test
import java.io.File

class ClipboardCategoryTest {
    @Test fun migrationRetentionRenameAndDelete() {
        val dir = java.nio.file.Files.createTempDirectory("folders-test").toFile()
        try {
            val file = File(dir, "clipboard.json")
            file.writeText("""[{"id":"old","text":"舊內容","pinned":false,"date":0}]""")
            val store = ClipboardStore(file, 1)
            store.addCategory("工作"); store.assign("old", "工作")
            store.add("暫存一"); store.add("暫存二"); store.clearUnpinned()
            assertEquals(listOf("舊內容"), store.items.map { it.text })
            store.renameCategory("工作", "靈感")
            val loaded = ClipboardStore(file)
            assertEquals(listOf("靈感"), loaded.categories)
            assertEquals("靈感", loaded.items.single().category)
            loaded.deleteCategory("靈感")
            assertEquals(1, loaded.items.size); assertNull(loaded.items.single().category)
        } finally { dir.deleteRecursively() }
    }
    @Test fun portableArchiveAndDuplicateKeepsLocalAssignment() {
        val source = ClipboardStore(null)
        source.addCategory("空資料夾"); source.addCategory("工作")
        source.add("甲"); source.assign(source.items[0].id, "工作")
        val backup = ClipboardArchive.decodeContents(ClipboardArchive.encode(source.items, source.categories))
        val dest = ClipboardStore(null)
        dest.addCategory("自己的"); dest.add("甲"); dest.assign(dest.items[0].id, "自己的")
        dest.importEntries(backup.entries, backup.categories)
        assertEquals(listOf("自己的", "空資料夾", "工作"), dest.categories)
        assertEquals("自己的", dest.items[0].category)
        val empty = ClipboardArchive.decodeContents(ClipboardArchive.encode(emptyList(), listOf("只有分類")))
        assertEquals(listOf("只有分類"), empty.categories)
        assertNull(ClipboardArchive.decode("""{"format":"nuonuo-clipboard","version":1,"items":[{"text":"舊備份"}]}""".toByteArray())[0].category)
    }
    @Test fun invalidAndFailedWritesAreAtomic() {
        val store = ClipboardStore(null); store.addCategory("好")
        for (name in listOf("好", "  ", "換\n行", "字".repeat(41))) assertTrue(runCatching { store.addCategory(name) }.isFailure)
        assertEquals(listOf("好"), store.categories)
        assertTrue(runCatching { store.importEntries(listOf(ClipboardArchive.Entry("不可加入", category = ""))) }.isFailure)
        assertTrue(store.items.isEmpty())
        val dir = java.nio.file.Files.createTempDirectory("bad-folder").toFile()
        try {
            val bad = ClipboardStore(dir)
            assertTrue(runCatching { bad.addCategory("不能儲存") }.isFailure)
            assertTrue(bad.categories.isEmpty())
        } finally { dir.deleteRecursively() }
    }
}
