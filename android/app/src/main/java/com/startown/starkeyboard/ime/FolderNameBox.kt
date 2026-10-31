package com.startown.starkeyboard.ime

import android.content.Context
import android.text.TextUtils
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.TextView

/** Naming uses the keyboard's own editor; no second IME or window token is needed. */
class FolderNameBox(context: Context, onSave: () -> Unit, onCancel: () -> Unit) : LinearLayout(context) {
    private val title = TextView(context)
    private val name = TextView(context)
    private val cancel = TextView(context)
    private val save = TextView(context)
    private val card = LinearLayout(context)
    private fun px(value: Int) = (value * resources.displayMetrics.density).toInt()
    init {
        orientation = VERTICAL
        setPadding(px(10), px(6), px(10), px(4))
        card.orientation = VERTICAL
        card.setPadding(px(12), px(2), px(8), px(2))
        title.textSize = 12f
        card.addView(title, LayoutParams(LayoutParams.MATCH_PARENT, px(24)))
        val row = LinearLayout(context).apply { gravity = Gravity.CENTER_VERTICAL }
        name.textSize = 16f; name.maxLines = 1; name.ellipsize = TextUtils.TruncateAt.START
        row.addView(name, LayoutParams(0, px(44), 1f))
        cancel.text = "取消"
        for (button in listOf(cancel, save)) {
            button.textSize = 15f; button.gravity = Gravity.CENTER; button.isClickable = true; button.isFocusable = true
            row.addView(button, LayoutParams(px(52), px(44)))
        }
        cancel.setOnClickListener { onCancel() }; save.setOnClickListener { onSave() }
        card.addView(row)
        addView(card, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
    }
    fun update(text: String, renaming: Boolean, style: KeyboardStyle) {
        setHeight(84)
        name.maxLines = 1; name.textSize = 16f; name.gravity = Gravity.CENTER_VERTICAL
        title.text = (if (renaming) "重新命名資料夾" else "新增資料夾") + " · 最多 40 字"
        name.text = if (text.isEmpty()) "例如：工作、常用回覆 ▏" else "$text▏"
        name.contentDescription = "資料夾名稱，用下方鍵盤輸入：" + text.ifEmpty { "尚未輸入" }
        save.text = if (renaming) "儲存" else "建立"
        card.background = roundRect(style.theme.key, px(14).toFloat())
        title.setTextColor(style.theme.keyText.withAlpha(0.7f))
        name.setTextColor(style.theme.keyText.withAlpha(if (text.isEmpty()) 0.5f else 1f))
        cancel.setTextColor(style.theme.keyText)
        save.setTextColor(if (style.theme.dark) style.theme.accent else style.theme.specialText)
    }

    /** 改剪貼簿：三行高的小對話框，整段文字和游標都看得到 */
    fun updateClip(text: String, cursor: Int?, composing: String, style: KeyboardStyle) {
        setHeight(CLIP_HEIGHT)
        name.maxLines = 3; name.textSize = 15f; name.gravity = Gravity.TOP
        title.text = "編輯剪貼簿 · 按住空白鍵左右滑移動游標"
        val c = (cursor ?: text.length).coerceIn(0, text.length)
        val before = text.substring(0, c).let { if (it.length > 80) "…" + it.takeLast(80) else it }
        val after = text.substring(c).let { if (it.length > 40) it.take(40) + "…" else it }
        name.text = before + (if (composing.isEmpty()) "▏" else "［$composing］") + after
        name.contentDescription = "剪貼簿內容，用下方鍵盤修改：" + text.ifEmpty { "空白" }
        save.text = "儲存"
        card.background = roundRect(style.theme.key, px(14).toFloat())
        title.setTextColor(style.theme.keyText.withAlpha(0.7f))
        name.setTextColor(style.theme.keyText)
        cancel.setTextColor(style.theme.keyText)
        save.setTextColor(if (style.theme.dark) style.theme.accent else style.theme.specialText)
    }

    private fun setHeight(dp: Int) {
        val lp = layoutParams ?: return
        if (lp.height != px(dp)) { lp.height = px(dp); layoutParams = lp }
        val row = name.parent as? LinearLayout ?: return
        val nlp = name.layoutParams
        val h = if (dp == CLIP_HEIGHT) px(dp - 42) else px(44)
        if (nlp.height != h) { nlp.height = h; name.layoutParams = nlp }
        row.gravity = if (dp == CLIP_HEIGHT) Gravity.TOP else Gravity.CENTER_VERTICAL
    }

    companion object { const val CLIP_HEIGHT = 136 }
}
