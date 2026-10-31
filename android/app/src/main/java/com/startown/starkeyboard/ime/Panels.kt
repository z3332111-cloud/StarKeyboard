package com.startown.starkeyboard.ime

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
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
    private val kind: PanelKind,
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
                tabs.add(Tab.Recent("最近"))
                SymbolData.symbols.forEach { tabs.add(Tab.Items(it.title, it.items)) }
            }
        }
        val start = if (store.recents(key).isNotEmpty()) 0 else if (kind == PanelKind.SYMBOLS) 1 else 2
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
            is Tab.Mine -> listOf(Ref.Add) + store.custom.map { Ref.Custom(it) } + store.stickers.map { Ref.Sticker(it) }
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
        val square = kind != PanelKind.KAOMOJI && tab !is Tab.Mine
        grid.setItems(items, square)
    }

    private fun bitmap(name: String): Bitmap? = bitmaps.getOrPut(name) {
        store.stickerFile(name)?.takeIf { it.exists() }?.let { BitmapFactory.decodeFile(it.path) }
    }

    private fun tapped(i: Int) {
        val ref = refs.getOrNull(i) ?: return
        if (grid.editing) {
            when (ref) {
                is Ref.Custom -> store.removeCustom(ref.s)
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
        val options = listOf(
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
class CandidatePanel(context: Context, style: KeyboardStyle, onSelect: (Int) -> Unit, onBack: () -> Unit, onBackspace: () -> Unit) : LinearLayout(context) {
    private val grid = ChipGrid(context, style)

    init {
        orientation = VERTICAL
        grid.onSelect = onSelect
        addView(grid, LayoutParams(LayoutParams.MATCH_PARENT, 0, 1f))
        addView(PanelBottomBar(context, style, emptyList(), -1, "▲", onBack = onBack, onTab = {}, onBackspace = onBackspace),
            LayoutParams(LayoutParams.MATCH_PARENT, dpi(40f)))
    }

    fun setCandidates(texts: List<String>) = grid.setItems(texts.map { ChipGrid.Item.Text(it) }, false)
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
        header.addView(TextView(context).apply { text = "剪貼簿"; textSize = 15f; setTextColor(t.keyText); paint.isFakeBoldText = true },
            LayoutParams(0, LayoutParams.MATCH_PARENT, 1f).apply { leftMargin = dpi(12f) })
        header.addView(Tap(context, "＋ 加入目前複製的", 13f, if (t.dark) t.accent else t.specialText, true) { onAddCurrent() }.apply {
            setPadding(dpi(8f), 0, dpi(8f), 0)
        }, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.MATCH_PARENT))
        clearButton = Tap(context, "清暫存", 13f, t.keyText.withAlpha(0.7f)) { clearTapped() }.apply { setPadding(dpi(10f), 0, dpi(12f), 0) }
        header.addView(clearButton, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.MATCH_PARENT))
        addView(header, LayoutParams(LayoutParams.MATCH_PARENT, dpi(34f)))
        val tools = LinearLayout(context)
        tools.addView(Tap(context, "匯入／匯出", 14f, t.specialText, true) { onTransfer() }, LayoutParams(0, dpi(34f), 1f))
        manage = Tap(context, "資料夾管理", 14f, t.specialText, true) {}
        manage.setOnClickListener {
            val menu = PopupMenu(context, manage)
            menu.menu.add("＋新增分類").setOnMenuItemClickListener { onEditCategory(null); true }
            store.categories.toList().forEach { name ->
                val sub = menu.menu.addSubMenu(name)
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
                text = if (selected >= 2) "分類還沒有內容，點每筆右側的 📁 來歸類" else if (selected == 1) "還沒有釘選的內容\n點項目右邊的 📌 就能釘選" else "按上方「加入目前複製的」儲存，或到 ⚙ 隱私與安全開啟自動記錄\n請勿保存密碼或驗證碼"
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
            list.addView(row)
            list.addView(View(context).apply { setBackgroundColor(t.shadow.withAlpha(0.4f)) }, LayoutParams(LayoutParams.MATCH_PARENT, maxOf(1, dpi(0.5f))))
        }
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
    onBack: () -> Unit,
) : LinearLayout(context) {
    private val col = LinearLayout(context).apply { orientation = VERTICAL; setPadding(dpi(12f), dpi(8f), dpi(12f), dpi(12f)) }
    private val t = style.theme

    init {
        orientation = VERTICAL
        val scroll = ScrollView(context)
        scroll.addView(col)
        addView(scroll, LayoutParams(LayoutParams.MATCH_PARENT, 0, 1f))
        addView(PanelBottomBar(context, style, listOf("設定"), 0, showBackspace = false, onBack = onBack, onTab = {}, onBackspace = {}),
            LayoutParams(LayoutParams.MATCH_PARENT, dpi(40f)))
        build()
    }

    private fun header(s: String) = col.addView(TextView(context).apply {
        text = s; textSize = 13f; setTextColor(t.keyText.withAlpha(0.8f)); paint.isFakeBoldText = true
        setPadding(0, dpi(12f), 0, dpi(4f))
    })

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

    private fun toggle(title: String, on: Boolean, set: (Boolean) -> Unit) {
        col.addView(Switch(context).apply {
            text = title; textSize = 14f; setTextColor(t.keyText); isChecked = on
            setOnCheckedChangeListener { _: CompoundButton, v: Boolean -> set(v) }
        }, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply { topMargin = dpi(4f) })
    }

    private fun build() {
        header("主題")
        val themes = LinearLayout(context).apply { orientation = HORIZONTAL }
        for (theme in KeyboardTheme.all) {
            val selected = theme.id == settings.themeId
            val cell = LinearLayout(context).apply { orientation = VERTICAL; gravity = Gravity.CENTER_HORIZONTAL; setPadding(dpi(4f), 0, dpi(4f), 0) }
            cell.addView(View(context).apply {
                background = android.graphics.drawable.GradientDrawable().apply {
                    shape = android.graphics.drawable.GradientDrawable.OVAL
                    setColor(theme.top)
                    setStroke(if (selected) dpi(3f) else dpi(1f), if (selected) theme.accent else theme.shadow)
                }
            }, LayoutParams(dpi(46f), dpi(46f)))
            cell.addView(TextView(context).apply { text = theme.name; textSize = 11f; setTextColor(t.keyText); gravity = Gravity.CENTER })
            cell.setOnClickListener { settings.themeId = theme.id; onChange() }
            themes.addView(cell)
        }
        col.addView(HorizontalScrollView(context).apply { isHorizontalScrollBarEnabled = false; addView(themes) })

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

        header("按鍵特效（按下去冒出小圖案）")
        choices(KeyEffect.values().map { it.title }, KeyEffect.values().indexOfFirst { it.id == settings.keyEffect }) {
            settings.keyEffect = KeyEffect.values()[it].id; onChange()
        }

        header("字體（按鍵和候選字）")
        val fonts = LinearLayout(context).apply { orientation = HORIZONTAL }
        for (font in KeyFont.values()) {
            val selected = font.id == settings.fontId
            fonts.addView(Tap(context, font.title, 16f, if (selected) t.accentText else t.keyText, selected) {
                settings.fontId = font.id; onChange()
            }.apply {
                background = roundRect(if (selected) t.accent else t.key.withAlpha(0.6f), dp(12f))
                KeyFonts.get(context, font.id)?.let { typeface = it }
            }, LayoutParams(0, dpi(40f), 1f).apply { rightMargin = dpi(6f) })
        }
        col.addView(fonts)
        note("字體只改變鍵盤上看到的樣子；傳出去的字由對方的 App 決定。想讓別人也看到特別的字，用工具列的「𝒜 花式文字」。")

        header("大小（邊拖邊看）")
        slider("鍵盤高度", settings.heightScale, 0.8f, 1.3f) { settings.heightScale = it }
        slider("字的大小", settings.fontScale, 0.8f, 1.4f) { settings.fontScale = it }
        slider("按鍵間距", settings.gapScale, 0.3f, 1.6f) { settings.gapScale = it }
        note("間距越小，按鍵越大、越好按。")
        button("大小恢復預設") {
            settings.heightScale = 1f; settings.fontScale = 1f; settings.gapScale = 1f; onChange()
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

        header("輸入法（按「中／英」鍵輪流切換，長按可換別的鍵盤）")
        for (mode in InputMode.values()) {
            toggle(mode.settingName, mode in settings.enabledModes) { on ->
                val modes = settings.enabledModes.toMutableList()
                if (on) { if (mode !in modes) modes.add(mode) } else modes.remove(mode)
                settings.enabledModes = InputMode.values().filter { it in modes }
                onChange()
            }
        }
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
            note("🎉 有新版：打開「糯糯鍵盤」App 更新")
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
