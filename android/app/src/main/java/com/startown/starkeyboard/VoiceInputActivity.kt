package com.startown.starkeyboard

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.os.Bundle
import android.speech.RecognizerIntent
import android.widget.*

/** The installed system recognizer owns recording; results are never inserted into a stale editor. */
class VoiceInputActivity : Activity() {
    private lateinit var resultText: EditText
    private lateinit var status: TextView
    private lateinit var language: Spinner
    private val locales = arrayOf("zh-TW", "zh-CN", "en-US", "ms-MY")
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        val pad = (20 * resources.displayMetrics.density).toInt()
        val col = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(pad, pad, pad, pad) }
        fun note(value: String) { col.addView(TextView(this).apply { text = value; textSize = 16f; setPadding(0, pad / 2, 0, pad / 2) }) }
        fun button(label: String, action: () -> Unit) { col.addView(Button(this).apply { text = label; setOnClickListener { action() } }) }
        note("語音轉文字")
        note("使用手機已安裝的語音服務（例如 Google）。按開始後，該服務會處理錄音與權限，可能將語音傳到服務商；不受糯糯的外部翻譯開關控制。辨識後先確認文字，再複製回原 App 貼上。")
        language = Spinner(this).apply {
            adapter = ArrayAdapter(this@VoiceInputActivity, android.R.layout.simple_spinner_dropdown_item,
                arrayOf("中文（台灣）", "中文（普通話）", "English", "Bahasa Melayu"))
            setSelection(state?.getInt("language") ?: 0)
        }
        col.addView(language)
        button("開始說話（取代目前文字）") {
            try {
                startActivityForResult(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, locales[language.selectedItemPosition])
                    putExtra(RecognizerIntent.EXTRA_PROMPT, "說完後請確認辨識文字")
                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                }, 10)
            } catch (e: android.content.ActivityNotFoundException) {
                status.text = "找不到系統語音服務，請先安裝或啟用手機的語音辨識服務。"
            } catch (e: SecurityException) { status.text = "語音服務權限不足，請檢查系統設定。" }
        }
        status = TextView(this).apply { text = "按開始後才會啟動語音服務。" }; col.addView(status)
        resultText = EditText(this).apply {
            hint = "辨識結果，可手動修改"; minLines = 5; gravity = android.view.Gravity.TOP
            inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE
            setText(state?.getString("text") ?: "")
        }
        col.addView(resultText)
        button("複製文字，回原 App 貼上") {
            val text = resultText.text.toString()
            if (text.isBlank()) status.text = "先說話或輸入要複製的文字。"
            else {
                (getSystemService(CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("語音文字", text))
                status.text = "已複製！回原 App 長按輸入框 → 貼上。"
            }
        }
        note("糯糯不保存錄音，也不會自動傳送文字。按複製後會進系統剪貼簿；若鍵盤開了自動記錄，之後仍可能被保存。")
        button("返回") { finish() }
        setContentView(ScrollView(this).apply { addView(col) })
    }
    override fun onSaveInstanceState(out: Bundle) {
        out.putString("text", resultText.text.toString()); out.putInt("language", language.selectedItemPosition)
        super.onSaveInstanceState(out)
    }
    @Deprecated("Activity result compatibility")
    override fun onActivityResult(request: Int, result: Int, data: Intent?) {
        super.onActivityResult(request, result, data)
        if (request != 10) return
        if (result != RESULT_OK) { status.text = "已取消或未完成辨識，原本的文字保留。"; return }
        val text = data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()
        if (text.isNullOrBlank()) status.text = "沒有辨識到文字，請再試一次。"
        else { resultText.setText(text); status.text = "辨識完成，請確認文字再複製。" }
    }
}
