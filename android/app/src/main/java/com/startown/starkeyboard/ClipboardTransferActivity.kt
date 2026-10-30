package com.startown.starkeyboard

import android.app.Activity
import android.app.AlertDialog
import android.content.ClipboardManager
import android.content.Intent
import android.os.Bundle
import android.widget.*
import com.startown.starkeyboard.core.ClipboardArchive
import com.startown.starkeyboard.core.ClipboardStore
import com.startown.starkeyboard.ime.KeyboardSettings
import java.io.ByteArrayOutputStream
import java.io.File

class ClipboardTransferActivity : Activity() {
    private lateinit var store: ClipboardStore
    private lateinit var count: TextView
    private var exportData: ByteArray? = null
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        store = ClipboardStore(File(filesDir, "clipboard.json"), KeyboardSettings(this).clipLimit)
        val col = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(32, 40, 32, 32) }
        fun text(value: String) { col.addView(TextView(this).apply { text = value; textSize = 16f; setPadding(0, 12, 0, 12) }) }
        fun button(label: String, action: () -> Unit) { col.addView(Button(this).apply { text = label; setOnClickListener { action() } }) }
        text("剪貼簿搬家")
        count = TextView(this); col.addView(count); updateCount()
        text("JSON 保留多行文字與釘選，兩個平台共用。TXT 每行一筆。匯出檔是明文，請選自己信任的儲存位置。")
        button("匯出全部為 JSON 檔案") {
            safely {
                store.load()
                exportData = ClipboardArchive.encode(store.items)
                startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE); type = "application/json"
                    putExtra(Intent.EXTRA_TITLE, "糯糯剪貼簿.json")
                }, 1)
            }
        }
        button("匯入 JSON／TXT 檔案") {
            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE); type = "*/*"
                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/json", "text/plain"))
            }, 2)
        }
        button("匯入目前複製的文字") {
            val clip = (getSystemService(CLIPBOARD_SERVICE) as ClipboardManager).primaryClip
            if (clip?.description?.extras?.getBoolean("android.content.extra.IS_SENSITIVE", false) == true) {
                message("已跳過標示為敏感的內容。")
            } else {
                val text = clip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.text?.toString()
                if (text.isNullOrBlank()) message("目前沒有複製的文字。")
                else AlertDialog.Builder(this).setTitle("文字怎麼分筆？")
                    .setItems(arrayOf("每行一筆", "整段一筆（保留換行）")) { _, index ->
                        safely { confirm(ClipboardArchive.textEntries(text, index == 0)) }
                    }.show()
            }
        }
        text("從其他鍵盤搬家：先在原鍵盤找「匯出／備份」或「全選複製」。支援 JSON 文字陣列、items 清單，以及 text／content 欄位。若對方沒有匯出功能，先複製想保留的內容；這裡不能直接讀取其他鍵盤的私人紀錄。")
        button("返回") { finish() }
        setContentView(ScrollView(this).apply { addView(col) })
    }
    @Deprecated("Activity result compatibility")
    override fun onActivityResult(request: Int, result: Int, data: Intent?) {
        super.onActivityResult(request, result, data)
        if (result != RESULT_OK) { exportData = null; return }
        val uri = data?.data ?: return
        safely {
            if (request == 1) {
                val bytes = exportData ?: error("請重新按匯出；畫面切換後未保留待匯出的內容。")
                contentResolver.openOutputStream(uri, "wt")?.use { it.write(bytes) } ?: error("無法寫入選定位置。")
                exportData = null
                message("已匯出檔案。請妥善保存這份明文備份。")
            } else if (request == 2) {
                val bytes = contentResolver.openInputStream(uri)?.use { input ->
                    val out = ByteArrayOutputStream()
                    val buffer = ByteArray(8192)
                    while (true) {
                        val size = input.read(buffer)
                        if (size < 0) break
                        require(out.size() + size <= ClipboardArchive.MAX_BYTES) { "檔案超過 2 MB。" }
                        out.write(buffer, 0, size)
                    }
                    out.toByteArray()
                } ?: error("無法讀取檔案。")
                val name = contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                    if (it.moveToFirst()) it.getString(0) else ""
                } ?: ""
                val plain = when {
                    name.endsWith(".json", true) -> false
                    name.endsWith(".txt", true) -> true
                    else -> contentResolver.getType(uri) == "text/plain"
                }
                confirm(ClipboardArchive.decode(bytes, plainText = plain))
            }
        }
    }
    private fun confirm(entries: List<ClipboardArchive.Entry>) {
        val preview = entries.take(3).joinToString("\n\n") { it.text.take(60) }
        AlertDialog.Builder(this).setTitle("匯入 " + entries.size + " 筆？")
            .setMessage(preview + "\n\n重複內容合併。原本紀錄會保留；超過未釘選上限的新內容會跳過。")
            .setNegativeButton("取消", null)
            .setPositiveButton("匯入") { _, _ ->
                safely {
                    store.load()
                    val r = store.importEntries(entries)
                    updateCount()
                    message("新增 " + r.added + " 筆，重複 " + r.duplicates + " 筆，容量不足跳過 " + r.skipped + " 筆。")
                }
            }.show()
    }
    private fun updateCount() { count.text = "目前 " + store.items.size + " 筆" }
    private fun message(text: String) { AlertDialog.Builder(this).setTitle("剪貼簿搬家").setMessage(text).setPositiveButton("好", null).show() }
    private fun safely(block: () -> Unit) { try { block() } catch (e: Exception) { message(e.message ?: "沒有完成，請檢查檔案格式與儲存位置。") } }
}
