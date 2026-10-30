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
}
