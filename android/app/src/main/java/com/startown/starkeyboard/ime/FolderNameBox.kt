package com.startown.starkeyboard.ime

import android.annotation.SuppressLint
import android.content.Context
import android.text.TextUtils
import android.view.Gravity
import android.view.MotionEvent
import android.widget.LinearLayout
import android.widget.TextView

/** Naming uses the keyboard's own editor; no second IME or window token is needed. */
@SuppressLint("ClickableViewAccessibility")
class FolderNameBox(context: Context, onSave: () -> Unit, onCancel: () -> Unit) : LinearLayout(context) {
    /** 改剪貼簿時點了文字：回傳要把游標放在第幾個字（字串索引）後面 */
    var onTapIndex: ((Int) -> Unit)? = null
    private val title = TextView(context)
    private val name = TextView(context)
    private val cancel = TextView(context)
    private val save = TextView(context)
    private val card = LinearLayout(context)
    /** 畫面上的字對回原文：第一個字是原文第幾個、前面「…」幾個字、游標前幾個字、游標記號幾個字 */
    private var tapMap: IntArray? = null
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
        // 點文字：算出點到第幾個字，換回原文的位置
        name.setOnTouchListener { _, e ->
            val map = tapMap ?: return@setOnTouchListener false
            if (e.action == MotionEvent.ACTION_UP) {
                val shown = name.getOffsetForPosition(e.x, e.y)
                val d = shown - map[1]
                val index = if (d <= map[2]) map[0] + maxOf(0, d) else map[0] + d - map[3]
                onTapIndex?.invoke(maxOf(0, index))
            }
            true
        }
    }
    fun update(text: String, renaming: Boolean, style: KeyboardStyle) {
        setHeight(84)
        tapMap = null
        name.maxLines = 1; name.textSize = 16f; name.gravity = Gravity.CENTER_VERTICAL; name.ellipsize = TextUtils.TruncateAt.START
        title.text = (if (renaming) "重新命名資料夾" else "新增資料夾") + " · 最多 40 字"
        name.text = if (text.isEmpty()) "例如：工作、常用回覆 ▏" else "$text▏"
        name.contentDescription = "資料夾名稱，用下方鍵盤輸入：" + text.ifEmpty { "尚未輸入" }
        save.text = if (renaming) "儲存" else "建立"
        applyColors(style, text.isEmpty())
    }

    /** 搜尋剪貼簿：一行關鍵字，找到的列在下面的候選列 */
    fun updateSearch(text: String, composing: String, style: KeyboardStyle) {
        setHeight(84)
        tapMap = null
        name.maxLines = 1; name.textSize = 16f; name.gravity = Gravity.CENTER_VERTICAL; name.ellipsize = TextUtils.TruncateAt.START
        title.text = "🔍 搜尋剪貼簿 · 找到的會列在下面，點一下貼上"
        val shown = text + (if (composing.isEmpty()) "" else "［$composing］")
        name.text = if (shown.isEmpty()) "打關鍵字，例如：地址、會議 ▏" else "$shown▏"
        name.contentDescription = "搜尋剪貼簿：" + text.ifEmpty { "尚未輸入" }
        save.text = "完成"
        applyColors(style, shown.isEmpty())
    }

    /** 改剪貼簿：三行高的小對話框，整段文字和游標都看得到 */
    fun updateClip(text: String, cursor: Int?, composing: String, style: KeyboardStyle) {
        setHeight(CLIP_HEIGHT)
        name.maxLines = 3; name.textSize = 15f; name.gravity = Gravity.TOP; name.ellipsize = null
        title.text = "編輯剪貼簿 · 點文字或按住空白鍵滑動，移動游標"
        val c = (cursor ?: text.length).coerceIn(0, text.length)
        // 太長時只留游標前面 44 個字，後面 26 個字（三行放得下）
        val start = maxOf(0, c - 44)
        val prefix = if (start > 0) "…" else ""
        val before = text.substring(start, c)
        val after = text.substring(c).let { if (it.length > 26) it.take(26) + "…" else it }
        val mid = if (composing.isEmpty()) "▏" else "［$composing］"
        name.text = prefix + before + mid + after
        tapMap = intArrayOf(start, prefix.length, before.length, mid.length)
        name.contentDescription = "剪貼簿內容，用下方鍵盤修改：" + text.ifEmpty { "空白" }
        save.text = "儲存"
        applyColors(style, false)
    }

    private fun applyColors(style: KeyboardStyle, empty: Boolean) {
        card.background = roundRect(style.theme.key, px(14).toFloat())
        title.setTextColor(style.theme.keyText.withAlpha(0.7f))
        name.setTextColor(style.theme.keyText.withAlpha(if (empty) 0.5f else 1f))
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
