package com.startown.starkeyboard.ime

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.widget.CompoundButton
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.Switch
import android.widget.TextView
import android.widget.PopupMenu
import android.widget.Toast
import com.startown.starkeyboard.core.ClipItem
import com.startown.starkeyboard.core.ClipboardStore
import com.startown.starkeyboard.core.EmoticonStore
import com.startown.starkeyboard.core.ShortcutStore
import com.startown.starkeyboard.core.SymbolData

/** 表情符號、顏文字、特殊符號共用的面板（含「我的表符」和自製貼圖） */
@SuppressLint("ViewConstructor")
class EmojiPanel(
    context: Context,
    val kind: PanelKind,
    private val store: EmoticonStore,
    private val style: KeyboardStyle,
    private val onInsert: (String) -> Unit,
    private val onSticker: (String) -> Unit,
    private val onAdd: (AddOption) -> Unit,
    onBack: () -> Unit,
    onBackspace: () -> Unit,
) : LinearLayout(context) {
    enum class AddOption { TYPE, CLIPBOARD_TEXT, PICK_IMAGE }

    private sealed class Tab(val title: String) {
        class Recent(title: String) : Tab(title)
        class Mine(title: String) : Tab(title)
        class Items(title: String, val items: List<String>) : Tab(title)
    }

    private sealed class Ref {
        data class Text(val s: String) : Ref()
        data class Custom(val s: String) : Ref()
        data class Sticker(val name: String) : Ref()
        object Add : Ref()
    }

    private val key = kind.name
    private val tabs = ArrayList<Tab>()
    private val grid = ChipGrid(context, style)
    private var refs: List<Ref> = emptyList()
    private var current = 0
    private val bitmaps = HashMap<String, Bitmap?>()
    private val overlay = FrameLayout(context)
    private val bar: PanelBottomBar

    init {
        orientation = VERTICAL
        when (kind) {
            PanelKind.EMOJI -> {
                tabs.add(Tab.Recent("🕘")); tabs.add(Tab.Mine("⭐"))
                SymbolData.emoji.forEach { tabs.add(Tab.Items(it.title, it.items)) }
            }
            PanelKind.KAOMOJI -> {
                tabs.add(Tab.Recent("最近")); tabs.add(Tab.Mine("我的"))
                SymbolData.kaomoji.forEach { tabs.add(Tab.Items(it.title, it.items)) }
            }
            else -> {
                tabs.add(Tab.Recent("最近")); tabs.add(Tab.Mine("我的"))
                SymbolData.symbols.forEach { tabs.add(Tab.Items(it.title, it.items)) }
            }
        }
        val start = if (store.recents(key).isNotEmpty()) 0 else 2
        val frame = FrameLayout(context)
        frame.addView(grid, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        frame.addView(overlay, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        overlay.visibility = View.GONE
        addView(frame, LayoutParams(LayoutParams.MATCH_PARENT, 0, 1f))
        bar = PanelBottomBar(context, style, tabs.map { it.title }, start, onBack = onBack, onTab = { select(it) }, onBackspace = onBackspace)
        addView(bar, LayoutParams(LayoutParams.MATCH_PARENT, dpi(40f)))
        grid.onSelect = { tapped(it) }
        grid.canDelete = { i -> refs.getOrNull(i).let { it is Ref.Custom || it is Ref.Sticker } }
        grid.onLongPress = { if (tabs[current] is Tab.Mine) grid.editing = !grid.editing }
        buildOverlay()
        select(start)
    }

    fun reload() {
        store.load()
        select(current)
    }

    private fun select(i: Int) {
        current = i
        grid.editing = false
        val tab = tabs[i]
        refs = when (tab) {
            is Tab.Recent -> store.recents(key).map { Ref.Text(it) }
            is Tab.Mine -> if (kind == PanelKind.SYMBOLS) listOf(Ref.Add) + store.symbols.map { Ref.Custom(it) }
                else listOf(Ref.Add) + store.custom.map { Ref.Custom(it) } + store.stickers.map { Ref.Sticker(it) }
            is Tab.Items -> tab.items.map { Ref.Text(it) }
        }.filter { it !is Ref.Sticker || bitmap(it.name) != null }
        val items = refs.map {
            when (it) {
                is Ref.Text -> ChipGrid.Item.Text(it.s)
                is Ref.Custom -> ChipGrid.Item.Text(it.s)
                is Ref.Sticker -> ChipGrid.Item.Image(bitmap(it.name)!!)
                Ref.Add -> ChipGrid.Item.Add
            }
        }
        val square = kind != PanelKind.KAOMOJI && (tab !is Tab.Mine || kind == PanelKind.SYMBOLS)
        grid.setItems(items, square)
    }

    private fun bitmap(name: String): Bitmap? = bitmaps.getOrPut(name) {
        store.stickerFile(name)?.takeIf { it.exists() }?.let { decodeSmall(it.path, 180) }
    }

    private fun tapped(i: Int) {
        val ref = refs.getOrNull(i) ?: return
        if (grid.editing) {
            when (ref) {
                is Ref.Custom -> if (kind == PanelKind.SYMBOLS) store.removeSymbol(ref.s) else store.removeCustom(ref.s)
                is Ref.Sticker -> { store.removeSticker(ref.name); bitmaps.remove(ref.name) }
                else -> return
            }
            select(current)
            grid.editing = true
            return
        }
        when (ref) {
            is Ref.Text -> { onInsert(ref.s); store.pushRecent(ref.s, key) }
            is Ref.Custom -> { onInsert(ref.s); store.pushRecent(ref.s, key) }
            is Ref.Sticker -> onSticker(ref.name)
            Ref.Add -> overlay.visibility = View.VISIBLE
        }
    }

    private fun buildOverlay() {
        val t = style.theme
        overlay.setBackgroundColor(t.top.withAlpha(0.94f))
        val col = LinearLayout(context).apply { orientation = VERTICAL; setPadding(dpi(24f), dpi(10f), dpi(24f), dpi(10f)) }
        val options = if (kind == PanelKind.SYMBOLS) listOf(
            "⌨️  用鍵盤打新的符號（空白隔開可以加好幾個）" to AddOption.TYPE,
            "📋  把剪貼簿的文字加進來" to AddOption.CLIPBOARD_TEXT,
            "取消" to null,
        ) else listOf(
            "⌨️  用鍵盤打一個新的表符" to AddOption.TYPE,
            "📋  把剪貼簿的文字加進來" to AddOption.CLIPBOARD_TEXT,
            "🖼  挑一張照片做成貼圖" to AddOption.PICK_IMAGE,
            "取消" to null,
        )
        for ((title, option) in options) {
            col.addView(Tap(context, title, 15f, t.keyText, option != null) {
                overlay.visibility = View.GONE
                option?.let(onAdd)
            }.apply { background = roundRect(t.key, dp(12f)) },
                LayoutParams(LayoutParams.MATCH_PARENT, 0, 1f).apply { bottomMargin = dpi(6f) })
        }
        overlay.addView(col)
    }
}

/** 展開的候選字（全部列出來） */
@SuppressLint("ViewConstructor")
class CandidatePanel(context: Context, private val style: KeyboardStyle, onSelect: (Int) -> Unit, onBack: () -> Unit, onBackspace: () -> Unit,
                     private val radicalOf: (Char) -> String? = { null }) : LinearLayout(context) {
    private val grid = ChipGrid(context, style)
    // 部首篩選：上面一排部首，點了只留那個部首的單字
    private val radicalScroll = HorizontalScrollView(context).apply { isHorizontalScrollBarEnabled = false }
    private val radicalRow = LinearLayout(context).apply { orientation = HORIZONTAL; setPadding(dpi(8f), dpi(4f), dpi(8f), dpi(2f)) }
    private var all: List<String> = emptyList()
    private var shown: List<Int> = emptyList()
    private var filter: String? = null

    init {
        orientation = VERTICAL
        grid.onSelect = { i -> shown.getOrNull(i)?.let(onSelect) }
        radicalScroll.addView(radicalRow)
        addView(radicalScroll, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
        addView(grid, LayoutParams(LayoutParams.MATCH_PARENT, 0, 1f))
        addView(PanelBottomBar(context, style, emptyList(), -1, "▲", onBack = onBack, onTab = {}, onBackspace = onBackspace),
            LayoutParams(LayoutParams.MATCH_PARENT, dpi(40f)))
    }

    fun setCandidates(texts: List<String>) {
        if (texts == all) return
        all = texts
        filter = null
        apply()
    }

    private fun apply() {
        val f = filter
        shown = all.indices.filter { i -> f == null || (all[i].length == 1 && radicalOf(all[i][0]) == f) }
        grid.setItems(shown.map { ChipGrid.Item.Text(all[it]) }, false)
        buildRadicals()
    }

    /** 候選裡單字的部首，出現越多次的排越前面 */
    private fun buildRadicals() {
        radicalRow.removeAllViews()
        val counts = LinkedHashMap<String, Int>()
        for (t in all) if (t.length == 1) radicalOf(t[0])?.let { counts[it] = (counts[it] ?: 0) + 1 }
        val list = counts.entries.sortedByDescending { it.value }.map { it.key }
        radicalScroll.visibility = if (list.size >= 2) VISIBLE else GONE
        if (list.size < 2) return
        val t = style.theme
        for (value in listOf<String?>(null) + list) {
            val on = filter == value
            radicalRow.addView(Tap(context, value ?: "全部", if (value == null) 14f else 17f, if (on) t.accentText else t.keyText, on) {
                filter = value; apply()
            }.apply {
                background = roundRect(if (on) t.accent else t.key.withAlpha(0.7f), dp(12f))
                KeyFonts.get(context, style.fontId)?.let { typeface = it }
            }, LayoutParams(dpi(if (value == null) 52f else 40f), dpi(30f)).apply { rightMargin = dpi(6f) })
        }
    }
}

/** 剪貼簿紀錄：點一下貼上、📌 釘選、✕ 刪除 */
@SuppressLint("ViewConstructor")
class ClipboardPanel(
    context: Context,
    private val store: ClipboardStore,
    private val style: KeyboardStyle,
    private val onInsert: (String) -> Unit,
    private val onAddCurrent: () -> Unit,
    private val onTransfer: () -> Unit,
    private val onEdit: (ClipItem) -> Unit,
    private val onEditCategory: (String?) -> Unit,
    private val onSearch: () -> Unit = {},
    private var autoRecord: Boolean = false,
    private val onToggleAuto: (Boolean) -> Unit = {},
    onBack: () -> Unit,
    onBackspace: () -> Unit,
) : LinearLayout(context) {
    private val list = LinearLayout(context).apply { orientation = VERTICAL }
    private var selected = 0
    private var tabTitles = emptyList<String>()
    private var bar: PanelBottomBar? = null
    private val back = onBack
    private val backspace = onBackspace
    private var confirmClear = false
    private lateinit var clearButton: TextView
    private lateinit var manage: TextView

    init {
        orientation = VERTICAL
        val t = style.theme
        val header = LinearLayout(context).apply { orientation = HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        // 左上角原本只寫「剪貼簿」，改成搜尋按鈕
        header.addView(Tap(context, "🔍 搜尋", 15f, t.keyText, true) { onSearch() }.apply { gravity = Gravity.CENTER_VERTICAL or Gravity.START; contentDescription = "搜尋剪貼簿" },
            LayoutParams(0, LayoutParams.MATCH_PARENT, 1f).apply { leftMargin = dpi(12f) })
        header.addView(Tap(context, "＋ 加入目前複製的", 13f, if (t.dark) t.accent else t.specialText, true) { onAddCurrent() }.apply {
            setPadding(dpi(8f), 0, dpi(8f), 0)
        }, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.MATCH_PARENT))
        clearButton = Tap(context, "清暫存", 13f, t.keyText.withAlpha(0.7f)) { clearTapped() }.apply { setPadding(dpi(10f), 0, dpi(12f), 0) }
        header.addView(clearButton, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.MATCH_PARENT))
        addView(header, LayoutParams(LayoutParams.MATCH_PARENT, dpi(34f)))
        val tools = LinearLayout(context)
        tools.addView(Tap(context, "匯入／匯出", 14f, t.specialText, true) { onTransfer() }, LayoutParams(0, dpi(34f), 1f))
        // 自動記錄開關放在這裡：打開後連續複製的每一則都會自己存進來，不用一則一則按「加入」
        lateinit var auto: TextView
        fun autoLabel() = if (autoRecord) "自動記錄 ● 開" else "自動記錄 ○ 關"
        auto = Tap(context, autoLabel(), 14f, t.specialText, true) {
            autoRecord = !autoRecord
            auto.text = autoLabel()
            onToggleAuto(autoRecord)
        }
        auto.contentDescription = "自動記錄剪貼簿"
        tools.addView(auto, LayoutParams(0, dpi(34f), 1f))
        manage = Tap(context, "資料夾管理", 14f, t.specialText, true) {}
        manage.setOnClickListener {
            val menu = PopupMenu(context, manage)
            menu.menu.add("＋新增分類").setOnMenuItemClickListener { onEditCategory(null); true }
            store.categories.toList().forEach { name ->
                val sub = menu.menu.addSubMenu(name)
                // 點了直接跳到這個資料夾
                sub.add("📂 打開這個資料夾").setOnMenuItemClickListener { selectCategory(name); true }
                sub.add("重新命名").setOnMenuItemClickListener { onEditCategory(name); true }
                sub.add("移除分類（內容留在未分類）").setOnMenuItemClickListener { change { store.deleteCategory(name) }; true }
            }
            menu.show()
        }
        tools.addView(manage, LayoutParams(0, dpi(34f), 1f)); addView(tools)
        val scroll = ScrollView(context)
        scroll.addView(list)
        addView(scroll, LayoutParams(LayoutParams.MATCH_PARENT, 0, 1f))

        reload()
    }

    fun selectCategory(name: String) {
        selected = store.categories.indexOf(name).takeIf { it >= 0 }?.plus(2) ?: 0
        reload()
    }

    fun reload() {
        list.removeAllViews()
        val t = style.theme
        val titles = listOf("全部", "📌 釘選") + store.categories
        manage.visibility = if (store.categories.isEmpty()) View.GONE else View.VISIBLE
        if (selected >= titles.size) selected = 0
        if (tabTitles != titles) {
            bar?.let { removeView(it) }
            tabTitles = titles
            bar = PanelBottomBar(context, style, titles, selected, onBack = back, onTab = { index ->
                selected = index; reload()
            }, onBackspace = backspace, onAdd = { onEditCategory(null) })
            addView(bar, LayoutParams(LayoutParams.MATCH_PARENT, dpi(40f)))
        }
        bar?.select(selected)
        val rows = when (selected) {
            1 -> store.ordered.filter { it.pinned }
            in 2..Int.MAX_VALUE -> store.ordered.filter { it.category == store.categories[selected - 2] }
            else -> store.ordered
        }
        if (rows.isEmpty()) {
            list.addView(TextView(context).apply {
                text = if (selected >= 2) "分類還沒有內容，點每筆右側的 📁 來歸類" else if (selected == 1) "還沒有釘選的內容\n點項目右邊的 📌 就能釘選" else "按上方「加入目前複製的」儲存，或打開「自動記錄」\n連續複製的每一則都會自己存進來\n請勿保存密碼或驗證碼"
                textSize = 14f
                gravity = Gravity.CENTER
                setTextColor(t.keyText.withAlpha(0.7f))
                setPadding(dpi(20f), dpi(30f), dpi(20f), dpi(20f))
            })
            return
        }
        for (item in rows) {
            val row = LinearLayout(context).apply { orientation = HORIZONTAL; gravity = Gravity.CENTER_VERTICAL; setPadding(dpi(12f), dpi(6f), dpi(4f), dpi(6f)) }
            row.addView(TextView(context).apply {
                text = item.text.trim()
                textSize = 15f
                maxLines = 2
                ellipsize = TextUtils.TruncateAt.END
                setTextColor(t.keyText)
            }, LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f))
            row.addView(Tap(context, "✎", 16f, t.accent) { onEdit(item) }.apply {
                contentDescription = "編輯"
            }, LayoutParams(dpi(40f), dpi(40f)))
            row.addView(Tap(context, "📌", 15f, t.keyText) { store.togglePin(item.id); reload() }.apply {
                alpha = if (item.pinned) 1f else 0.3f
            }, LayoutParams(dpi(40f), dpi(40f)))
            val folder = Tap(context, "📁", 15f, t.keyText) {}
            folder.contentDescription = "移到分類：" + (item.category ?: "未分類")
            folder.setOnClickListener {
                val menu = PopupMenu(context, folder)
                (listOf<String?>(null) + store.categories).forEach { name ->
                    menu.menu.add(name ?: "未分類").setOnMenuItemClickListener { change { store.assign(item.id, name) }; true }
                }
                menu.show()
            }
            if (store.categories.isNotEmpty()) row.addView(folder, LayoutParams(dpi(40f), dpi(40f)))
            row.addView(Tap(context, "✕", 15f, t.keyText.withAlpha(0.5f)) { store.remove(item.id); reload() }, LayoutParams(dpi(40f), dpi(40f)))
            row.setOnClickListener { onInsert(item.text) }
            list.addView(swipeable(row, item))
            list.addView(View(context).apply { setBackgroundColor(t.shadow.withAlpha(0.4f)) }, LayoutParams(LayoutParams.MATCH_PARENT, maxOf(1, dpi(0.5f))))
        }
    }

    /** 和 iPhone 一樣：整列往左滑刪除、往右滑釘選（滑超過三成寬才算） */
    @SuppressLint("ClickableViewAccessibility")
    private fun swipeable(row: View, item: ClipItem): View {
        val t = style.theme
        val box = FrameLayout(context)
        val pinLabel = TextView(context).apply {
            text = if (item.pinned) "取消釘選" else "📌 釘選"
            textSize = 14f
            setTextColor(t.accentText)
            setBackgroundColor(t.accent)
            gravity = Gravity.CENTER_VERTICAL or Gravity.START
            setPadding(dpi(16f), 0, 0, 0)
            visibility = View.INVISIBLE
        }
        val deleteLabel = TextView(context).apply {
            text = "刪除"
            textSize = 14f
            setTextColor(android.graphics.Color.WHITE)
            setBackgroundColor(0xFFE5484D.toInt())
            gravity = Gravity.CENTER_VERTICAL or Gravity.END
            setPadding(0, 0, dpi(16f), 0)
            visibility = View.INVISIBLE
        }
        box.addView(pinLabel, FrameLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        box.addView(deleteLabel, FrameLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        box.addView(row, FrameLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))

        // 只露出被滑開的那一塊，字不會和下面的「刪除」「釘選」疊在一起
        fun reveal(dx: Float) {
            val w = box.width
            pinLabel.visibility = if (dx > 0) View.VISIBLE else View.INVISIBLE
            deleteLabel.visibility = if (dx < 0) View.VISIBLE else View.INVISIBLE
            if (dx > 0) pinLabel.clipBounds = android.graphics.Rect(0, 0, dx.toInt(), box.height)
            if (dx < 0) deleteLabel.clipBounds = android.graphics.Rect(w + dx.toInt(), 0, w, box.height)
        }

        val slop = android.view.ViewConfiguration.get(context).scaledTouchSlop
        var downX = 0f
        var downY = 0f
        var dragging = false
        row.setOnTouchListener { v, e ->
            when (e.actionMasked) {
                android.view.MotionEvent.ACTION_DOWN -> { downX = e.rawX; downY = e.rawY; dragging = false; false }
                android.view.MotionEvent.ACTION_MOVE -> {
                    val dx = e.rawX - downX
                    val dy = e.rawY - downY
                    if (!dragging && Math.abs(dx) > slop && Math.abs(dx) > Math.abs(dy) * 1.5f) {
                        dragging = true
                        v.parent?.requestDisallowInterceptTouchEvent(true)
                        // 取消這一列的點擊（滑動不是要貼上）
                        val cancel = android.view.MotionEvent.obtain(e).apply { action = android.view.MotionEvent.ACTION_CANCEL }
                        v.onTouchEvent(cancel)
                        cancel.recycle()
                    }
                    if (dragging) { v.translationX = dx; reveal(dx); true } else false
                }
                android.view.MotionEvent.ACTION_UP, android.view.MotionEvent.ACTION_CANCEL -> {
                    if (!dragging) return@setOnTouchListener false
                    dragging = false
                    val dx = v.translationX
                    val far = v.width * 0.3f
                    when {
                        dx < -far && e.actionMasked == android.view.MotionEvent.ACTION_UP ->
                            v.animate().translationX(-v.width.toFloat()).setDuration(150).withEndAction { store.remove(item.id); reload() }.start()
                        dx > far && e.actionMasked == android.view.MotionEvent.ACTION_UP ->
                            v.animate().translationX(0f).setDuration(150).withEndAction { store.togglePin(item.id); reload() }.start()
                        else -> v.animate().translationX(0f).setDuration(150).withEndAction { reveal(0f) }.start()
                    }
                    true
                }
                else -> dragging
            }
        }
        return box
    }

    private fun change(action: () -> Unit) {
        try { action(); reload() } catch (e: Exception) { Toast.makeText(context, e.message ?: "無法儲存分類", Toast.LENGTH_LONG).show() }
    }
    private fun clearTapped() {
        if (confirmClear) {
            store.clearUnpinned()
            confirmClear = false
            clearButton.text = "清暫存"
            reload()
            return
        }
        confirmClear = true
        clearButton.text = "確定清除？"
        postDelayed({ confirmClear = false; clearButton.text = "清暫存" }, 3000)
    }
}

/** 鍵盤裡的設定：主題、按鍵造型、大小、背景、輸入法、打錯字修正、聲音震動 */
@SuppressLint("ViewConstructor", "UseSwitchCompatOrMaterialCode")
class SettingsPanel(
    context: Context,
    private val settings: KeyboardSettings,
    private val style: KeyboardStyle,
    private val onChange: () -> Unit,
    private val onOpenApp: () -> Unit,
    private val onAdjustPhoto: () -> Unit,
    private val shortcuts: ShortcutStore,
    private val onAddShortcut: () -> Unit,
    private val onResetLearning: () -> Unit,
    private val onImportFont: () -> Unit,
    private val onDownloadFont: (String) -> Unit,
    private val onPickSpaceImage: () -> Unit,
    private val onPasteSpaceEmoji: () -> Unit,
    private val onCopyTypingLog: () -> Unit,
    private val onLiveSize: () -> Unit = {},
    private val onDownloadTheme: (String) -> Unit = {},
    onBack: () -> Unit,
) : LinearLayout(context) {
    private val col = LinearLayout(context).apply { orientation = VERTICAL; setPadding(dpi(12f), dpi(8f), dpi(12f), dpi(12f)) }
    private val scroll = ScrollView(context)
    // 每一段的標題（「跳到…」選單用）：短的名字和那一行
    private val sections = ArrayList<Pair<String, View>>()
    private lateinit var jump: TextView
    private var t = style.theme
    // 自訂配色：現在點色票是改主色還是第二色
    private var editingSecond = false

    /** 在原地重畫設定（捲動位置不變），用在點色票這種不換主題的改變 */
    private fun rebuildHere() {
        t = settings.theme
        col.removeAllViews()
        build()
    }

    init {
        orientation = VERTICAL
        // 最上面一排：「跳到…」選單（點了直接捲到那一段）＋「邊看邊調大小」
        val top = LinearLayout(context).apply { orientation = HORIZONTAL; gravity = Gravity.CENTER_VERTICAL; setPadding(dpi(8f), dpi(4f), dpi(8f), dpi(2f)) }
        jump = Tap(context, "📑 跳到：主題 ▾", 14f, t.keyText, true) { showJumpMenu() }.apply {
            background = roundRect(t.key.withAlpha(0.8f), dp(10f))
            gravity = Gravity.CENTER_VERTICAL or Gravity.START
            setPadding(dpi(12f), 0, dpi(8f), 0)
        }
        top.addView(jump, LayoutParams(0, dpi(34f), 1f))
        top.addView(Tap(context, "📏 邊看邊調大小", 14f, t.specialText, true) { onLiveSize() }.apply {
            background = roundRect(t.special, dp(10f))
            setPadding(dpi(10f), 0, dpi(10f), 0)
        }, LayoutParams(LayoutParams.WRAP_CONTENT, dpi(34f)).apply { leftMargin = dpi(6f) })
        addView(top, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
        scroll.addView(col)
        // 捲動時左上角跟著顯示現在在哪一段
        scroll.setOnScrollChangeListener { _, _, y, _, _ ->
            val cur = sections.lastOrNull { it.second.top <= y + dpi(12f) } ?: sections.firstOrNull()
            cur?.let { jump.text = "📑 跳到：${it.first} ▾" }
        }
        addView(scroll, LayoutParams(LayoutParams.MATCH_PARENT, 0, 1f))
        addView(PanelBottomBar(context, style, listOf("設定"), 0, showBackspace = false, onBack = onBack, onTab = {}, onBackspace = {}),
            LayoutParams(LayoutParams.MATCH_PARENT, dpi(40f)))
        build()
    }

    private fun header(s: String) {
        val v = TextView(context).apply {
            text = s; textSize = 13f; setTextColor(t.keyText.withAlpha(0.8f)); paint.isFakeBoldText = true
            setPadding(0, dpi(12f), 0, dpi(4f))
        }
        col.addView(v)
        sections.add(s.substringBefore("（").substringBefore("？") to v)
    }

    /** 「跳到…」：列出每一段，點了直接捲過去 */
    private fun showJumpMenu() {
        val menu = PopupMenu(context, jump)
        for ((i, s) in sections.withIndex()) menu.menu.add(0, i, i, s.first)
        menu.setOnMenuItemClickListener { item ->
            sections.getOrNull(item.itemId)?.let { (name, v) ->
                scroll.smoothScrollTo(0, maxOf(0, v.top))
                jump.text = "📑 跳到：$name ▾"
            }
            true
        }
        menu.show()
    }

    private fun note(s: String) = col.addView(TextView(context).apply {
        text = s; textSize = 12f; setTextColor(t.keyText.withAlpha(0.65f)); setPadding(0, dpi(2f), 0, dpi(2f))
    })

    private fun button(title: String, action: () -> Unit) = col.addView(Tap(context, title, 14f, t.specialText, true, action).apply {
        background = roundRect(t.special, dp(10f))
    }, LayoutParams(LayoutParams.MATCH_PARENT, dpi(40f)).apply { topMargin = dpi(4f) })

    /** 背景照片的縮圖：點一下換成那張，選中的有框；右邊的 ✕ 拿掉目前這張 */
    private fun photoRow() {
        val scroll = HorizontalScrollView(context).apply { isHorizontalScrollBarEnabled = false }
        val row = LinearLayout(context).apply { orientation = HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        val thumbs = ArrayList<android.widget.ImageView>()
        fun paint() {
            val list = settings.photos
            val cur = if (list.isEmpty()) -1 else Math.floorMod(settings.photoIndex, list.size)
            for ((i, v) in thumbs.withIndex()) {
                v.background = roundRect(if (i == cur) t.accent else t.key.withAlpha(0.6f), dp(12f))
            }
        }
        for (ph in settings.photos) {
            val v = android.widget.ImageView(context).apply {
                scaleType = android.widget.ImageView.ScaleType.CENTER_CROP
                setImageBitmap(settings.thumbnail(ph))
                setPadding(dpi(3f), dpi(3f), dpi(3f), dpi(3f))
                clipToOutline = true
            }
            v.setOnClickListener {
                settings.photoIndex = thumbs.indexOf(v)
                paint()
                onChange()
            }
            thumbs.add(v)
            row.addView(v, LayoutParams(dpi(58f), dpi(58f)).apply { rightMargin = dpi(6f) })
        }
        row.addView(Tap(context, "✕ 拿掉這張", 13f, t.specialText, true) {
            val list = settings.photos
            if (list.isNotEmpty()) {
                val cur = Math.floorMod(settings.photoIndex, list.size)
                settings.removePhoto(cur)
                row.removeView(thumbs.removeAt(cur))
                paint()
                onChange()
            }
        }.apply { background = roundRect(t.special, dp(12f)); setPadding(dpi(12f), 0, dpi(12f), 0) },
            LayoutParams(LayoutParams.WRAP_CONTENT, dpi(40f)))
        paint()
        scroll.addView(row)
        col.addView(scroll, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply { topMargin = dpi(6f) })
    }

    /** 雙色時選「現在要改哪個顏色」：兩顆按鈕，前面有目前的顏色 */
    private fun colorTargetRow() {
        val row = LinearLayout(context).apply { orientation = HORIZONTAL }
        val items = listOf(Triple("● 主色（按鍵的字）", KeyboardTheme.swatchColor(settings.customHue, settings.customSaturation), false),
            Triple("● 第二色（功能鍵）", KeyboardTheme.swatchColor(settings.customHue2, settings.customSaturation2), true))
        for ((title, color, second) in items) {
            val selected = editingSecond == second
            val label = android.text.SpannableString(title).apply {
                setSpan(android.text.style.ForegroundColorSpan(color), 0, 1, 0)
                setSpan(android.text.style.RelativeSizeSpan(1.6f), 0, 1, 0)
            }
            row.addView(Tap(context, "", 13f, if (selected) t.accentText else t.keyText, selected) {
                editingSecond = second; rebuildHere()
            }.apply {
                text = label
                background = roundRect(if (selected) t.accent else t.key.withAlpha(0.6f), dp(12f))
            }, LayoutParams(0, dpi(40f), 1f).apply { rightMargin = dpi(6f); topMargin = dpi(4f) })
        }
        col.addView(row)
    }

    /** 色票：一格一個圓點，點了就換顏色（選中的有粗框） */
    private fun swatchGrid() {
        val second = settings.customHue2 >= 0f && editingSecond
        val curH = if (second) settings.customHue2 else settings.customHue
        val curS = if (second) settings.customSaturation2 else settings.customSaturation
        for (group in KeyboardTheme.swatches.chunked(7)) {
            val row = LinearLayout(context).apply { orientation = HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
            for ((h, sat) in group) {
                val selected = kotlin.math.abs(h - curH) < 0.005f && kotlin.math.abs(sat - curS) < 0.02f
                val cell = FrameLayout(context)
                cell.addView(View(context).apply {
                    background = android.graphics.drawable.GradientDrawable().apply {
                        shape = android.graphics.drawable.GradientDrawable.OVAL
                        setColor(KeyboardTheme.swatchColor(h, sat))
                        setStroke(if (selected) dpi(3f) else dpi(1f), if (selected) t.keyText else android.graphics.Color.WHITE)
                    }
                }, FrameLayout.LayoutParams(dpi(30f), dpi(30f), Gravity.CENTER))
                cell.setOnClickListener {
                    if (second) { settings.customHue2 = h; settings.customSaturation2 = sat }
                    else { settings.customHue = h; settings.customSaturation = sat }
                    onChange(); rebuildHere()
                }
                row.addView(cell, LayoutParams(0, dpi(38f), 1f))
            }
            repeat(7 - group.size) { row.addView(View(context), LayoutParams(0, dpi(38f), 1f)) }
            col.addView(row)
        }
    }

    /** 一排選項，選中的那個是主題色 */
    private fun choices(titles: List<String>, selected: Int, onSelect: (Int) -> Unit) {
        val scroll = HorizontalScrollView(context).apply { isHorizontalScrollBarEnabled = false }
        val row = LinearLayout(context).apply { orientation = HORIZONTAL }
        for ((i, title) in titles.withIndex()) {
            val on = i == selected
            row.addView(Tap(context, title, 14f, if (on) t.accentText else t.keyText, on) {
                onSelect(i)
                for (j in 0 until row.childCount) {
                    val v = row.getChildAt(j) as TextView
                    val sel = j == i
                    v.setTextColor(if (sel) t.accentText else t.keyText)
                    v.typeface = if (sel) android.graphics.Typeface.DEFAULT_BOLD else android.graphics.Typeface.DEFAULT
                    v.background = roundRect(if (sel) t.accent else t.key.withAlpha(0.6f), dp(12f))
                }
            }.apply {
                background = roundRect(if (on) t.accent else t.key.withAlpha(0.6f), dp(12f))
                setPadding(dpi(14f), 0, dpi(14f), 0)
            }, LayoutParams(LayoutParams.WRAP_CONTENT, dpi(38f)).apply { rightMargin = dpi(6f) })
        }
        scroll.addView(row)
        col.addView(scroll, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply { topMargin = dpi(2f) })
    }

    private fun slider(title: String, value: Float, lo: Float, hi: Float, set: (Float) -> Unit) {
        val row = LinearLayout(context).apply { orientation = HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        row.addView(TextView(context).apply { text = title; textSize = 14f; setTextColor(t.keyText) }, LayoutParams(dpi(86f), LayoutParams.WRAP_CONTENT))
        row.addView(SeekBar(context).apply {
            this.max = 100
            progress = (((value - lo) / (hi - lo)) * 100).toInt().coerceIn(0, 100)
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(s: SeekBar, p: Int, fromUser: Boolean) {
                    if (fromUser) { set(lo + (hi - lo) * p / 100f); onChange() }
                }
                override fun onStartTrackingTouch(s: SeekBar) {}
                override fun onStopTrackingTouch(s: SeekBar) {}
            })
        }, LayoutParams(0, dpi(40f), 1f))
        col.addView(row)
    }

    /** 角色主題：一排小卡片，有 ⬇ 的按一下才下載，不用可以移除 */
    private fun packThemeRow() {
        class Card(val id: String, val name: String, val emoji: String, val subtitle: String, val color: Int, val text: Int)
        val cards = listOf(Card(FoxLetter.ID, FoxLetter.theme.name, "🦊", "秋日水彩", FoxLetter.theme.top, FoxLetter.theme.keyText)) +
            ThemeLooks.all.map { Card(it.theme.id, it.theme.name, it.emoji, it.subtitle, it.theme.top,
                if (it.theme.dark && it.theme.id != "pool") it.theme.keyText else android.graphics.Color.parseColor("#33291F")) }
        val row = LinearLayout(context).apply { orientation = HORIZONTAL }
        for (card in cards) {
            val selected = settings.themeId == card.id
            val ready = ThemePacks.isReady(context, card.id)
            row.addView(Tap(context, card.emoji + "\n" + card.name + (if (selected) " ✓" else "") + "\n" + (if (ready) card.subtitle else "⬇ 按一下下載"), 11f, card.text, true) {
                if (!ready) onDownloadTheme(card.id)
                else {
                    if (ThemeLooks.named(settings.themeId) == null && settings.themeId != FoxLetter.ID) settings.themeBeforeFox = settings.themeId
                    settings.themeId = card.id
                    onChange()
                }
            }.apply {
                maxLines = 3
                background = android.graphics.drawable.GradientDrawable().apply {
                    setColor(card.color)
                    cornerRadius = dp(14f)
                    setStroke(if (selected) dpi(2f) else dpi(1f), if (selected) t.accent else card.text.withAlpha(0.4f))
                }
                contentDescription = card.name + if (ready) "" else "，要下載"
            }, LayoutParams(dpi(112f), dpi(80f)).apply { rightMargin = dpi(8f) })
        }
        col.addView(HorizontalScrollView(context).apply { isHorizontalScrollBarEnabled = false; addView(row) },
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply { bottomMargin = dpi(6f) })
        val current = settings.themeId
        if (ThemePacks.files(current).isNotEmpty() && ThemePacks.isReady(context, current)) {
            button("移除「" + KeyboardTheme.named(current).name + "」的圖（之後可以再下載）") {
                settings.themeId = settings.themeBeforeFox
                ThemePacks.remove(context, current)
                onChange()
            }
        }
    }

    private fun toggle(title: String, on: Boolean, set: (Boolean) -> Unit) {
        col.addView(Switch(context).apply {
            text = title; textSize = 14f; setTextColor(t.keyText); isChecked = on
            setOnCheckedChangeListener { _: CompoundButton, v: Boolean -> set(v) }
        }, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply { topMargin = dpi(4f) })
    }

    private fun build() {
        sections.clear()
        header("主題")
        packThemeRow()
        val themes = LinearLayout(context).apply { orientation = HORIZONTAL }
        for (theme in KeyboardTheme.all + KeyboardTheme.custom(settings.customHue, settings.customSaturation, settings.customDark, settings.customHue2, settings.customSaturation2)) {
            val selected = theme.id == settings.themeId
            val cell = LinearLayout(context).apply { orientation = VERTICAL; gravity = Gravity.CENTER_HORIZONTAL; setPadding(dpi(4f), 0, dpi(4f), 0) }
            cell.addView(View(context).apply {
                background = android.graphics.drawable.GradientDrawable().apply {
                    shape = android.graphics.drawable.GradientDrawable.OVAL
                    setColor(theme.top)
                    setStroke(if (selected) dpi(3f) else dpi(1f), if (selected) theme.accent else theme.shadow)
                }
            }, LayoutParams(dpi(46f), dpi(46f)))
            cell.addView(TextView(context).apply { text = if (theme.id == "custom") "🎨 自訂" else theme.name; textSize = 11f; setTextColor(t.keyText); gravity = Gravity.CENTER })
            cell.setOnClickListener { settings.themeId = theme.id; onChange() }
            themes.addView(cell)
        }
        col.addView(HorizontalScrollView(context).apply { isHorizontalScrollBarEnabled = false; addView(themes) })
        if (settings.themeId == "custom") {
            // 自訂配色：點色票選顏色；雙色時可以分別選主色和第二色
            val two = settings.customHue2 >= 0f
            choices(listOf("單色", "雙色"), if (two) 1 else 0) {
                if (it == 1 && settings.customHue2 < 0f) {
                    // 第二色先配一個對比色（色相轉半圈）
                    settings.customHue2 = (settings.customHue + 0.5f) % 1f
                    settings.customSaturation2 = settings.customSaturation
                    editingSecond = true
                } else if (it == 0) {
                    settings.customHue2 = -1f
                    editingSecond = false
                }
                onChange(); rebuildHere()
            }
            if (two) colorTargetRow()
            swatchGrid()
            val second = two && editingSecond
            slider("濃淡", if (second) settings.customSaturation2 else settings.customSaturation, 0.05f, 1f) {
                if (second) { settings.customSaturation2 = it } else { settings.customSaturation = it }
            }
            choices(listOf("淺色", "深色"), if (settings.customDark) 1 else 0) { settings.customDark = it == 1; onChange() }
        }

        if (ThemeLooks.named(settings.themeId)?.hasArt == false) {
            note("這個主題已配好造型和質感；切回其他主題就恢復你原本選的。")
        } else if (settings.style.isIllustrated) {
            note("這個主題已搭配角色造型與插畫質感。原本的造型、質感和背景照片會保留，切回其他主題就恢復。")
        } else {
        header("按鍵造型")
        for (group in KeyShape.values().toList().chunked(4)) {
            val shapes = LinearLayout(context).apply { orientation = HORIZONTAL }
            for (shape in group) {
                val selected = shape == settings.shape
                shapes.addView(Tap(context, shape.title, 14f, if (selected) t.accentText else t.keyText, selected) {
                    settings.shape = shape; onChange()
                }.apply { background = roundRect(if (selected) t.accent else t.key.withAlpha(0.6f), dp(12f)) },
                    LayoutParams(0, dpi(44f), 1f).apply { rightMargin = dpi(6f); bottomMargin = dpi(6f) })
            }
            repeat(4 - group.size) { shapes.addView(View(context), LayoutParams(0, dpi(44f), 1f)) }
            col.addView(shapes)
        }

        header("按鍵質感")
        choices(KeyFinish.values().map { it.title }, settings.keyFinish.ordinal) {
            settings.keyFinish = KeyFinish.values()[it]; onChange()
        }
        note("胖胖：圓滾滾，按下去會壓扁。立體：按鍵有厚度，按下去會往下沉；按鍵調透明也看得出來。")
        }

        header("按下去的動作")
        choices(KeyMotion.values().map { it.title }, KeyMotion.values().indexOfFirst { it.id == settings.keyMotion }.coerceAtLeast(0)) {
            settings.keyMotion = KeyMotion.values()[it].id; onChange()
        }
        note("果凍彈彈：壓扁再 duang duang 抖回來。跳跳：放開時蹦一下。搖搖：左右扭一扭。")

        header("空白鍵")
        if (settings.style.isIllustrated) note("可繼續使用自己的空白鍵圖片／GIF或表符。使用圖片時會收起信封配件，保留中央圖案空間。")
        val spaceModes = listOf("theme" to "主題符號", "image" to "我的圖片", "emoji" to "表符", "text" to "只有字")
        choices(spaceModes.map { it.second }, spaceModes.indexOfFirst { it.first == settings.spaceStyle }.coerceAtLeast(0)) {
            if (spaceModes[it].first == "image" && !SpaceArt.hasImage(context)) onPickSpaceImage()
            else { settings.spaceStyle = spaceModes[it].first; onChange() }
        }
        button("🖼 挑圖片／GIF（可以自動去背）") { onPickSpaceImage() }
        button("😊 貼上剛複製的表符") { onPasteSpaceEmoji() }
        note("空白鍵只放一個小圖：照片可以自動去背，也可以用 GIF 動圖，或複製一個表情符號、顏文字再按「貼上」。")

        header("注音被拆開了？")
        button("📋 複製剛剛的打字紀錄") { onCopyTypingLog() }
        note("打字時注音被拆開（例如「我覺得」變「我居約得」），先不要刪，直接打開 ⚙ 按這個，再貼給開發的人。紀錄是最近 80 次按鍵的注音、時間和選過的字。")

        header("按鍵特效（按下去冒出小圖案）")
        choices(KeyEffect.values().map { it.title }, KeyEffect.values().indexOfFirst { it.id == settings.keyEffect }) {
            settings.keyEffect = KeyEffect.values()[it].id; onChange()
        }

        header("字體（按鍵和候選字）")
        val allFonts = KeyFont.values().map { it.id to it.title } + UserFonts.all(context).map { it.id to it.name }
        for (group in allFonts.chunked(4)) {
            val fonts = LinearLayout(context).apply { orientation = HORIZONTAL }
            for ((id, title) in group) {
            val ready = FontPacks.isReady(context, id)
            val selected = id == settings.fontId && ready
            fonts.addView(Tap(context, if (ready) title else "⬇ $title", if (ready) 16f else 15f, if (selected) t.accentText else t.keyText, selected) {
                if (ready) { settings.fontId = id; onChange() } else onDownloadFont(id)
            }.apply {
                background = roundRect(if (selected) t.accent else t.key.withAlpha(0.6f), dp(12f))
                if (ready) KeyFonts.get(context, id)?.let { typeface = it }
                maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.END
            }, LayoutParams(0, dpi(40f), 1f).apply { rightMargin = dpi(6f); bottomMargin = dpi(6f) })
            }
            repeat(4 - group.size) { fonts.addView(View(context), LayoutParams(0, dpi(40f), 1f)) }
            col.addView(fonts)
        }
        KeyFont.values().firstOrNull { it.id == settings.fontId && !it.bundled && FontPacks.isReady(context, it.id) }?.let { f ->
            button("移除「${f.title}」（之後可以再下載）") {
                FontPacks.remove(context, f.id)
                settings.fontId = KeyFont.SYSTEM.id; onChange()
            }
        }
        button("＋ 匯入我的字體（自己買的 .ttf／.otf）") { onImportFont() }
        if (settings.fontId.startsWith("user:")) button("刪掉這個字體") {
            UserFonts.remove(context, settings.fontId)
            settings.fontId = KeyFont.SYSTEM.id; onChange()
        }
        note("有 ⬇ 的字體按一下才下載（要有網路），不用的可以移除，鍵盤就不會越來越大。")
        note("字體只改變鍵盤上看到的樣子；傳出去的字由對方的 App 決定。想讓別人也看到特別的字，用工具列的「𝒜 花式文字」。")

        header("大小（邊拖邊看）")
        slider("鍵盤高度", settings.heightScale, 0.8f, 1.3f) { settings.heightScale = it }
        slider("字的大小", settings.fontScale, 0.8f, 1.4f) { settings.fontScale = it }
        slider("按鍵間距", settings.gapScale, 0.3f, 1.6f) { settings.gapScale = it }
        note("間距越小，按鍵越大、越好按。")
        slider("造型大小", settings.shapeScale, 0.9f, 1.6f) { settings.shapeScale = it }
        note("貓咪、熊熊、肉球這類造型的大小，往右拉會變大顆（可以超出按鍵一點點）。")
        button("大小恢復預設") {
            settings.heightScale = 1f; settings.fontScale = 1f; settings.gapScale = 1f; settings.shapeScale = 1.15f; onChange()
        }

        header("背景照片")
        button("＋ 新增照片（打開糯糯鍵盤 App 挑）") { onOpenApp() }
        if (settings.photos.isNotEmpty()) photoRow()
        if (settings.photos.size >= 2) {
            val modes = listOf("fixed" to "固定這張", "open" to "每次打開換", "daily" to "每天換")
            choices(modes.map { it.second }, modes.indexOfFirst { it.first == settings.photoRotation }) {
                settings.photoRotation = modes[it].first
            }
        }
        if (settings.hasBackground) {
            button("調整照片位置和大小（拖拉、兩指縮放）") { onAdjustPhoto() }
        }
        slider("照片淡化", settings.backgroundFade, 0f, 0.9f) { settings.backgroundFade = it }
        slider("按鍵透明度", settings.keyAlpha, 0.35f, 1f) { settings.keyAlpha = it }

        header("快捷片語（打縮寫就跳出整段話）")
        button("＋ 新增快捷片語") { onAddShortcut() }
        if (shortcuts.items.isEmpty()) {
            note("例如縮寫「地址」→ 你家的完整地址。打注音只打開頭（ㄉㄓ）也可以，英文打 addr 之類也行。")
        }
        for (item in shortcuts.items.toList()) {
            val row = LinearLayout(context).apply { orientation = HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
            row.addView(TextView(context).apply {
                text = "${item.code} → ${item.phrase}"; textSize = 14f; setTextColor(t.keyText); maxLines = 2
                ellipsize = android.text.TextUtils.TruncateAt.END
            }, LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f))
            row.addView(Tap(context, "刪除", 13f, t.specialText, true) {
                shortcuts.remove(item)
                (row.parent as? android.view.ViewGroup)?.removeView(row)
            }.apply { background = roundRect(t.special, dp(10f)); setPadding(dpi(12f), dpi(6f), dpi(12f), dpi(6f)) },
                LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT))
            col.addView(row, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply { topMargin = dpi(6f) })
        }

        header("上面那一排按鈕（不用的關掉，比較不擠）")
        for (item in ToolbarItem.values()) {
            if (item == ToolbarItem.SETTINGS) continue
            toggle(item.title, item !in settings.hiddenTools) { on ->
                settings.hiddenTools = if (on) settings.hiddenTools - item else settings.hiddenTools + item
                onChange()
            }
        }

        header("輸入法（按「中／英」鍵輪流切換，長按可換別的鍵盤）")
        for (mode in InputMode.values()) {
            toggle(mode.settingName, mode in settings.enabledModes) { on ->
                val modes = settings.enabledModes.toMutableList()
                if (on) { if (mode !in modes) modes.add(mode) } else modes.remove(mode)
                settings.enabledModes = InputMode.values().filter { it in modes }
                onChange()
            }
        }
        toggle("注音十欄排法（像 Gboard：ㄦ 在空白鍵旁，長按打數字）", settings.zhuyinTenColumns) { settings.zhuyinTenColumns = it; onChange() }
        toggle("拼音輸出簡體字", settings.pinyinSimplified) { settings.pinyinSimplified = it }
        toggle("聯想詞（打完字後推薦下一個字）", settings.associations) { settings.associations = it }

        header("打錯字修正")
        toggle("英文自動修正（按空白時修正，馬上按刪除可以復原）", settings.autocorrect) { settings.autocorrect = it }
        toggle("英文滑行輸入（手指不放開，滑過字母就打出整個字）", settings.glideTyping) { settings.glideTyping = it; onChange() }
        toggle("注音：按到旁邊的鍵也猜得到", settings.fuzzyKeys) { settings.fuzzyKeys = it; onChange() }
        toggle("注音：聲調打錯或忘了打", settings.fuzzyTones) { settings.fuzzyTones = it; onChange() }
        toggle("注音模糊音：ㄣㄥ、ㄓㄗ、ㄔㄘ、ㄕㄙ 分不清", settings.fuzzyPhonetic) { settings.fuzzyPhonetic = it; onChange() }

        header("翻譯")
        note("工具列的「譯」：先打要翻譯的話，選目標語言，按「翻譯」。會先用 Google 的離線翻譯（第一次要下載語言資料），只有開啟「允許外部網路翻譯」後，才會在本機翻譯失敗時使用 MyMemory。")

        header("聲音與震動")
        toggle("按鍵聲音", settings.keySound) { settings.keySound = it }
        choices(KeySound.values().map { it.title }, KeySound.values().indexOfFirst { it.id == settings.keySoundStyle }) {
            settings.keySoundStyle = KeySound.values()[it].id; settings.keySound = true; onChange()
        }
        note("點一下就會播放聽聽看。")
        toggle("按鍵震動", settings.haptics) { settings.haptics = it }

        header("選字列高度")
        note("字會跟著變高。也可以在設定裡拖這個滑桿。")
        val height = android.widget.SeekBar(context).apply {
            max = 48
            progress = (settings.candidateBarHeight - 40f).toInt().coerceIn(0, 48)
            setOnSeekBarChangeListener(object : android.widget.SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(bar: android.widget.SeekBar?, value: Int, fromUser: Boolean) {
                    if (!fromUser) return
                    settings.candidateBarHeight = 40f + value
                    onChange()
                }
                override fun onStartTrackingTouch(bar: android.widget.SeekBar?) {}
                override fun onStopTrackingTouch(bar: android.widget.SeekBar?) {}
            })
        }
        col.addView(height, LayoutParams(LayoutParams.MATCH_PARENT, dpi(40f)))
        header("隱私與安全")
        toggle("自動記錄剪貼簿", settings.clipboardHistoryEnabled) { settings.clipboardHistoryEnabled = it }
        note("預設關閉。開啟後會儲存複製的文字；會略過敏感標記，但無法辨識所有密碼。舊紀錄可在剪貼簿逐筆刪除。")
        toggle("允許外部網路翻譯", settings.allowOnlineTranslation) { settings.allowOnlineTranslation = it }
        note("預設關閉。開啟後，本機翻譯失敗時會將最多 450 字送到 MyMemory；文字在網址參數中，服務商可能保留紀錄。請勿翻譯私密資料。完整說明見 App 的「隱私與安全」。")
        header("未分類暫存上限（釘選另存）")
        val limits = LinearLayout(context).apply { orientation = HORIZONTAL }
        for (n in listOf(50, 100, 200, 500)) {
            val selected = settings.clipLimit == n
            limits.addView(Tap(context, "$n", 14f, if (selected) t.accentText else t.keyText, selected) {
                settings.clipLimit = n; onChange()
            }.apply { background = roundRect(if (selected) t.accent else t.key.withAlpha(0.6f), dp(10f)) },
                LayoutParams(0, dpi(36f), 1f).apply { rightMargin = dpi(6f) })
        }
        col.addView(limits)

        header("其他")
        button("清除選字學習紀錄") { onResetLearning() }
        if (settings.latestBuild > BuildInfo.current(context)) {
            note("🎉 有新版：打開「糯糯鍵盤」App 下載安裝，直接蓋過去就好")
        }
        note("糯糯鍵盤 Android v${BuildInfo.version(context)} ・ 注音字典來自小麥注音（MIT 授權）")
    }
}

object BuildInfo {
    fun version(context: Context): String = runCatching {
        context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "0.2.0"
    }.getOrDefault("0.2.0")

    fun current(context: Context): Int = runCatching {
        @Suppress("DEPRECATION")
        context.packageManager.getPackageInfo(context.packageName, 0).versionCode
    }.getOrDefault(0)
}
