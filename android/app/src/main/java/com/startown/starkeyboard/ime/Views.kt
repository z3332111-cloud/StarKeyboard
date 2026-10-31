package com.startown.starkeyboard.ime

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import android.graphics.drawable.Drawable
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

fun View.dp(v: Float) = v * resources.displayMetrics.density
fun View.dpi(v: Float) = (v * resources.displayMetrics.density).toInt()

fun roundRect(color: Int, radius: Float) = GradientDrawable().apply {
    setColor(color)
    cornerRadius = radius
}

/**
 * 鍵盤後面的照片和淡化層：量大小時當作 0，不會把鍵盤撐高；鍵盤量好之後才照鍵盤的大小填滿。
 * 照片放大到蓋滿鍵盤（再乘上 zoom），focusX／focusY（0～1，例如臉的位置）盡量放在中間，超出的部分裁掉
 */
class Backdrop(context: Context) : ImageView(context) {
    var focusX = 0.5f
        set(v) { field = v; fit() }
    var focusY = 0.5f
        set(v) { field = v; fit() }
    var zoom = 1f
        set(v) { field = v.coerceIn(1f, MAX_ZOOM); fit() }

    companion object {
        const val MAX_ZOOM = 5f
    }

    /** 手指拖了 (dx, dy) 像素：照片跟著手指走 */
    fun pan(dx: Float, dy: Float) {
        val s = scale() ?: return
        focusX = clampFocus(focusX - dx / (s.first * s.third), width / (s.first * s.third))
        focusY = clampFocus(focusY - dy / (s.second * s.third), height / (s.second * s.third))
    }

    /** 兩指縮放 */
    fun zoomBy(f: Float) {
        zoom *= f
        pan(0f, 0f)   // 縮小後對準點可能跑出照片外，拉回來
    }

    /** 照片寬、高、放大倍數 */
    private fun scale(): Triple<Float, Float, Float>? {
        val d = drawable ?: return null
        val iw = d.intrinsicWidth.toFloat()
        val ih = d.intrinsicHeight.toFloat()
        if (iw <= 0f || ih <= 0f || width == 0 || height == 0) return null
        return Triple(iw, ih, maxOf(width / iw, height / ih) * zoom)
    }

    /** 看得到的範圍佔照片的比例是 visible：對準點不能太靠邊，不然拖了沒反應 */
    private fun clampFocus(f: Float, visible: Float): Float {
        val half = visible / 2f
        return if (half >= 0.5f) 0.5f else f.coerceIn(half, 1f - half)
    }

    init { scaleType = ScaleType.MATRIX }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(resolveSize(0, widthMeasureSpec), resolveSize(0, heightMeasureSpec))
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        fit()
    }

    override fun setImageDrawable(drawable: Drawable?) {
        super.setImageDrawable(drawable)
        fit()
    }

    private fun fit() {
        val (iw, ih, s) = scale() ?: return
        val dx = (width / 2f - focusX * iw * s).coerceIn(width - iw * s, 0f)
        val dy = (height / 2f - focusY * ih * s).coerceIn(height - ih * s, 0f)
        imageMatrix = Matrix().apply { setScale(s, s); postTranslate(dx, dy) }
    }
}

/** 調整背景照片：蓋在整個鍵盤上，一指拖拉移動、兩指縮放，下面有「重設」「完成」 */
@SuppressLint("ViewConstructor", "ClickableViewAccessibility")
class PhotoAdjustOverlay(
    context: Context,
    style: KeyboardStyle,
    private val onPan: (Float, Float) -> Unit,
    private val onScale: (Float) -> Unit,
    onReset: () -> Unit,
    onDone: () -> Unit,
) : FrameLayout(context) {
    private var lastX = 0f
    private var lastY = 0f
    private val scaler = android.view.ScaleGestureDetector(context, object : android.view.ScaleGestureDetector.SimpleOnScaleGestureListener() {
        override fun onScale(detector: android.view.ScaleGestureDetector): Boolean {
            onScale(detector.scaleFactor)
            return true
        }
    })

    init {
        val t = style.theme
        addView(TextView(context).apply {
            text = "拖拉移動照片・兩指縮放"
            textSize = 14f
            gravity = Gravity.CENTER
            setTextColor(t.accentText)
            background = roundRect(t.accent.withAlpha(0.92f), dp(16f))
            setPadding(dpi(14f), dpi(6f), dpi(14f), dpi(6f))
        }, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT, Gravity.CENTER_HORIZONTAL or Gravity.TOP).apply { topMargin = dpi(10f) })
        val bar = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL }
        bar.addView(Tap(context, "重設", 15f, t.specialText, true) { onReset() }.apply { background = roundRect(t.special, dp(14f)) },
            LinearLayout.LayoutParams(0, dpi(44f), 1f).apply { rightMargin = dpi(10f) })
        bar.addView(Tap(context, "完成", 15f, t.accentText, true) { onDone() }.apply { background = roundRect(t.accent, dp(14f)) },
            LinearLayout.LayoutParams(0, dpi(44f), 2f))
        addView(bar, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, Gravity.BOTTOM).apply {
            leftMargin = dpi(16f); rightMargin = dpi(16f); bottomMargin = dpi(12f)
        })
    }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        scaler.onTouchEvent(e)
        // 用所有手指的中心點算拖拉，兩指縮放時也能一起移動
        val lifted = if (e.actionMasked == MotionEvent.ACTION_POINTER_UP) e.actionIndex else -1
        var x = 0f
        var y = 0f
        var n = 0
        for (i in 0 until e.pointerCount) {
            if (i == lifted) continue
            x += e.getX(i); y += e.getY(i); n++
        }
        if (n == 0) return true
        x /= n; y /= n
        if (e.actionMasked == MotionEvent.ACTION_MOVE) onPan(x - lastX, y - lastY)
        lastX = x
        lastY = y
        return true
    }
}

/** 一個可以點的文字（工具列、候選字、按鈕都用這個） */
@SuppressLint("ViewConstructor")
class Tap(context: Context, text: String, sizeSp: Float, color: Int, bold: Boolean = false, onTap: () -> Unit) : TextView(context) {
    init {
        this.text = text
        textSize = sizeSp
        setTextColor(color)
        gravity = Gravity.CENTER
        maxLines = 1
        if (bold) typeface = Typeface.DEFAULT_BOLD
        setOnClickListener { onTap() }
    }
}

enum class Trailing { EXPAND, CLOSE }

enum class ToolbarItem(val label: String) {
    CLIPBOARD("剪貼"), EMOJI("☺︎"), KAOMOJI("(•ᴗ•)"), SYMBOLS("※"), FANCY("𝒜"), TRANSLATE("譯"),
    HANDWRITING("✍︎"), VOICE("🎙"), SETTINGS("⚙︎"), DISMISS("▾"),
}

/** 鍵盤最上面那一條：工具列／候選字／編輯框（新增表符、翻譯） */
@SuppressLint("ViewConstructor")
class TopBar(context: Context, style: KeyboardStyle) : FrameLayout(context) {
    var scriptTitle: String? = null
    var onScriptToggle: (() -> Unit)? = null
    var onToolbar: ((ToolbarItem) -> Unit)? = null
    var onCandidate: ((Int) -> Unit)? = null
    var onTrailing: ((Trailing) -> Unit)? = null
    var onEditor: ((Boolean) -> Unit)? = null
    var onEditorExtra: (() -> Unit)? = null
    var onEditorSource: (() -> Unit)? = null

    var candidateFontSp = 23f
    var style = style
        set(value) {
            field = value
            redraw()
        }

    private sealed class Content {
        object Toolbar : Content()
        data class Candidates(val composition: String, val items: List<String>, val trailing: Trailing) : Content()
        data class Editor(val prompt: String, val text: String, val extra: String, val confirm: String, val source: String? = null) : Content()
    }

    private var content: Content = Content.Toolbar

    fun showToolbar() { content = Content.Toolbar; redraw() }
    fun showCandidates(composition: String, items: List<String>, trailing: Trailing) {
        content = Content.Candidates(composition, items, trailing); redraw()
    }
    /** source：翻譯時的「原文語言」按鈕（其他編輯框不用就是 null） */
    fun showEditor(prompt: String, text: String, extra: String, confirm: String, source: String? = null) {
        content = Content.Editor(prompt, text, extra, confirm, source); redraw()
    }

    private val tint get() = if (style.theme.dark) style.theme.keyText else style.theme.specialText

    private fun redraw() {
        removeAllViews()
        val t = style.theme
        // 整條（工具列、選字區、編輯框）都墊一層半透明的底，放背景照片時圖示和字才看得清楚（深色主題墊深色）
        setBackgroundColor(if (t.dark) android.graphics.Color.BLACK.withAlpha(0.35f) else android.graphics.Color.WHITE.withAlpha(0.6f))
        when (val c = content) {
            is Content.Toolbar -> {
                val row = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL }
                for (item in ToolbarItem.values()) {
                    val size = if (item == ToolbarItem.KAOMOJI || item == ToolbarItem.CLIPBOARD) 14f else 19f
                    row.addView(Tap(context, item.label, size, tint, true) { onToolbar?.invoke(item) },
                        LinearLayout.LayoutParams(0, LayoutParams.MATCH_PARENT, 1f))
                }
                scriptTitle?.let { title ->
                    row.addView(Tap(context, title, 15f, tint, true) { onScriptToggle?.invoke() },
                        LinearLayout.LayoutParams(dpi(44f), LayoutParams.MATCH_PARENT))
                }
                addView(row, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT).apply {
                    leftMargin = dpi(4f); rightMargin = dpi(4f)
                })
            }
            is Content.Candidates -> {
                val scriptWidth = if (scriptTitle != null) dpi(44f) else 0
                val top = if (c.composition.isNotEmpty()) dpi(18f) else 0
                if (c.composition.isNotEmpty()) {
                    addView(TextView(context).apply {
                        text = c.composition
                        textSize = 14f
                        setTextColor(t.keyText)
                        paint.isFakeBoldText = true
                        maxLines = 1
                        ellipsize = TextUtils.TruncateAt.START
                    }, LayoutParams(LayoutParams.MATCH_PARENT, dpi(18f)).apply { leftMargin = dpi(12f); rightMargin = dpi(48f) + scriptWidth })
                }
                val scroll = HorizontalScrollView(context).apply { isHorizontalScrollBarEnabled = false }
                val row = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL }
                // 字加粗；第一個（按空白會送出的）放在主題色的膠囊裡，一眼就看得到
                for ((i, s) in c.items.take(40).withIndex()) {
                    val first = i == 0
                    row.addView(Tap(context, s, candidateFontSp, if (first) t.accentText else t.keyText, true) { onCandidate?.invoke(i) }.apply {
                        setPadding(dpi(11f), 0, dpi(11f), 0)
                        val base = KeyFonts.get(context, style.fontId) ?: android.graphics.Typeface.DEFAULT
                        typeface = android.graphics.Typeface.create(base, android.graphics.Typeface.BOLD)
                        if (first) {
                            background = roundRect(t.accent, dp(999f))
                            elevation = dp(2f)
                        }
                    }, LinearLayout.LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.MATCH_PARENT).apply {
                        if (first) { topMargin = dpi(4f); bottomMargin = dpi(4f); rightMargin = dpi(4f) }
                    })
                }
                scroll.addView(row, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.MATCH_PARENT))
                addView(scroll, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT).apply {
                    topMargin = top; rightMargin = dpi(44f) + scriptWidth; leftMargin = dpi(4f)
                })
                scriptTitle?.let { title ->
                    addView(Tap(context, title, 15f, tint, true) { onScriptToggle?.invoke() }.apply {
                        contentDescription = if (title == "繁") "目前繁體，點一下切換簡體" else "目前簡體，點一下切換繁體"
                    }, LayoutParams(dpi(44f), LayoutParams.MATCH_PARENT, Gravity.END).apply { rightMargin = dpi(44f) })
                }
                if (c.items.isNotEmpty() || c.trailing == Trailing.CLOSE) {
                    addView(Tap(context, if (c.trailing == Trailing.EXPAND) "⌄" else "✕", 18f, tint, true) {
                        onTrailing?.invoke(c.trailing)
                    }, LayoutParams(dpi(44f), LayoutParams.MATCH_PARENT, Gravity.END))
                }
            }
            is Content.Editor -> {
                val row = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
                row.addView(TextView(context).apply {
                    text = c.prompt + c.text + "▏"
                    textSize = 16f
                    setTextColor(t.keyText)
                    maxLines = 1
                    ellipsize = TextUtils.TruncateAt.START
                    gravity = Gravity.CENTER_VERTICAL
                }, LinearLayout.LayoutParams(0, LayoutParams.MATCH_PARENT, 1f).apply { leftMargin = dpi(12f) })
                c.source?.let { src ->
                    row.addView(Tap(context, src, 14f, tint, true) { onEditorSource?.invoke() }.apply { setPadding(dpi(6f), 0, dpi(6f), 0) },
                        LinearLayout.LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.MATCH_PARENT))
                }
                row.addView(Tap(context, c.extra, 14f, tint, true) { onEditorExtra?.invoke() }.apply { setPadding(dpi(8f), 0, dpi(8f), 0) },
                    LinearLayout.LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.MATCH_PARENT))
                row.addView(Tap(context, "取消", 15f, tint) { onEditor?.invoke(false) }, LinearLayout.LayoutParams(dpi(56f), LayoutParams.MATCH_PARENT))
                row.addView(Tap(context, c.confirm, 15f, if (t.dark) t.accent else t.specialText, true) { onEditor?.invoke(true) },
                    LinearLayout.LayoutParams(dpi(60f), LayoutParams.MATCH_PARENT))
                addView(row, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
            }
        }
        addView(View(context).apply { setBackgroundColor(t.shadow.withAlpha(0.4f)) },
            LayoutParams(LayoutParams.MATCH_PARENT, maxOf(1, dpi(0.5f)), Gravity.BOTTOM))
    }

    init {
        redraw()
    }
}

/** 面板最下面那條：返回鍵盤、分頁、刪除（按住會一直刪） */
@SuppressLint("ViewConstructor", "ClickableViewAccessibility")
class PanelBottomBar(context: Context, private val style: KeyboardStyle, tabs: List<String>, selected: Int,
                     backTitle: String = "ABC", showBackspace: Boolean = true,
                     onBack: () -> Unit, onTab: (Int) -> Unit, onBackspace: () -> Unit, onAdd: (() -> Unit)? = null) : LinearLayout(context) {
    private val tabViews = ArrayList<TextView>()
    private val tabScroll = HorizontalScrollView(context)
    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        orientation = HORIZONTAL
        val t = style.theme
        setPadding(dpi(4f), dpi(3f), dpi(4f), dpi(3f))
        addView(Tap(context, backTitle, 15f, t.specialText, true, onBack).apply {
            background = roundRect(t.special.withAlpha(style.keyAlpha), dp(8f))
        }, LayoutParams(dpi(56f), LayoutParams.MATCH_PARENT))
        val scroll = tabScroll.apply { isHorizontalScrollBarEnabled = false }
        val row = LinearLayout(context)
        for ((i, s) in tabs.withIndex()) {
            val v = Tap(context, s, if (s.codePointCount(0, s.length) <= 2) 18f else 14f, t.keyText, true) {
                select(i)
                onTab(i)
            }
            v.setPadding(dpi(10f), 0, dpi(10f), 0)
            v.minWidth = dpi(40f)
            tabViews.add(v)
            row.addView(v, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.MATCH_PARENT).apply { rightMargin = dpi(2f) })
        }
        scroll.addView(row)
        addView(scroll, LayoutParams(0, LayoutParams.MATCH_PARENT, 1f).apply { leftMargin = dpi(4f); rightMargin = dpi(4f) })
        if (onAdd != null) {
            addView(Tap(context, "＋", 22f, t.specialText, true, onAdd).apply {
                contentDescription = "新增剪貼簿資料夾"
            }, LayoutParams(dpi(44f), LayoutParams.MATCH_PARENT))
        }
        if (showBackspace) {
            val del = Tap(context, "⌫", 18f, t.specialText, true) {}.apply {
                background = roundRect(t.special.withAlpha(style.keyAlpha), dp(8f))
            }
            val repeat = object : Runnable {
                override fun run() {
                    onBackspace()
                    mainHandler.postDelayed(this, 80)
                }
            }
            del.setOnTouchListener { _, e ->
                when (e.actionMasked) {
                    MotionEvent.ACTION_DOWN -> { onBackspace(); mainHandler.postDelayed(repeat, 450) }
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> mainHandler.removeCallbacks(repeat)
                }
                true
            }
            addView(del, LayoutParams(dpi(52f), LayoutParams.MATCH_PARENT))
        }
        select(selected)
    }

    fun select(i: Int) {
        tabViews.getOrNull(i)?.let { selected ->
            tabScroll.post { selected.requestRectangleOnScreen(android.graphics.Rect(0, 0, selected.width, selected.height), true) }
        }
        val t = style.theme
        for ((j, v) in tabViews.withIndex()) {
            val on = j == i
            v.background = if (on) roundRect(t.key.withAlpha(style.keyAlpha), dp(8f)) else null
            v.setTextColor(if (on) t.keyText else t.keyText.withAlpha(0.6f))
        }
    }
}

/** 會自動換行的排列（顏文字、候選字用） */
class FlowLayout(context: Context) : ViewGroup(context) {
    private val gap = dpi(6f)

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val maxW = MeasureSpec.getSize(widthMeasureSpec) - paddingLeft - paddingRight
        var x = 0
        var y = 0
        var lineH = 0
        for (i in 0 until childCount) {
            val c = getChildAt(i)
            c.measure(MeasureSpec.makeMeasureSpec(maxW, MeasureSpec.AT_MOST), MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED))
            if (x > 0 && x + c.measuredWidth > maxW) {
                x = 0
                y += lineH + gap
                lineH = 0
            }
            x += c.measuredWidth + gap
            lineH = maxOf(lineH, c.measuredHeight)
        }
        setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), y + lineH + paddingTop + paddingBottom)
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        val maxW = r - l - paddingLeft - paddingRight
        var x = 0
        var y = 0
        var lineH = 0
        for (i in 0 until childCount) {
            val c = getChildAt(i)
            if (x > 0 && x + c.measuredWidth > maxW) {
                x = 0
                y += lineH + gap
                lineH = 0
            }
            c.layout(paddingLeft + x, paddingTop + y, paddingLeft + x + c.measuredWidth, paddingTop + y + c.measuredHeight)
            x += c.measuredWidth + gap
            lineH = maxOf(lineH, c.measuredHeight)
        }
    }
}

/** 可以捲動的方塊格子（表情符號、顏文字、候選字） */
class ChipGrid(context: Context, private val style: KeyboardStyle) : ScrollView(context) {
    sealed class Item {
        data class Text(val s: String) : Item()
        data class Image(val bitmap: Bitmap) : Item()
        object Add : Item()
    }

    var onSelect: ((Int) -> Unit)? = null
    var onLongPress: ((Int) -> Unit)? = null
    var canDelete: (Int) -> Boolean = { false }
    var editing = false
        set(value) {
            field = value
            render()
        }

    private val flow = FlowLayout(context).apply { setPadding(dpi(8f), dpi(6f), dpi(8f), dpi(6f)) }
    private var items: List<Item> = emptyList()
    private var square = true

    init {
        addView(flow, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
    }

    fun setItems(newItems: List<Item>, squareCells: Boolean) {
        items = newItems
        square = squareCells
        render()
        scrollTo(0, 0)
    }

    private fun render() {
        flow.removeAllViews()
        val t = style.theme
        for ((i, item) in items.withIndex()) {
            val deletable = editing && canDelete(i)
            val view: View = when (item) {
                is Item.Text -> TextView(context).apply {
                    text = if (deletable) "✕ " + item.s else item.s
                    gravity = Gravity.CENTER
                    maxLines = 1
                    setTextColor(if (deletable) android.graphics.Color.parseColor("#FF5A6E") else t.keyText)
                    if (square && !deletable) {
                        textSize = 26f
                        minWidth = dpi(42f); minHeight = dpi(42f)
                    } else {
                        textSize = 17f
                        minWidth = dpi(44f); minHeight = dpi(40f)
                        setPadding(dpi(12f), 0, dpi(12f), 0)
                        background = roundRect(t.key.withAlpha(style.keyAlpha * 0.9f), dp(10f))
                    }
                }
                is Item.Image -> FrameLayout(context).apply {
                    background = roundRect(t.key.withAlpha(style.keyAlpha * 0.6f), dp(10f))
                    addView(ImageView(context).apply {
                        setImageBitmap(item.bitmap)
                        scaleType = ImageView.ScaleType.FIT_CENTER
                        if (deletable) alpha = 0.4f
                    }, FrameLayout.LayoutParams(dpi(62f), dpi(62f), Gravity.CENTER))
                    if (deletable) addView(TextView(context).apply {
                        text = "✕"; textSize = 20f; setTextColor(android.graphics.Color.parseColor("#FF5A6E")); gravity = Gravity.CENTER
                    }, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
                    minimumWidth = dpi(70f); minimumHeight = dpi(70f)
                }
                is Item.Add -> TextView(context).apply {
                    text = "＋"
                    textSize = 22f
                    gravity = Gravity.CENTER
                    setTextColor(t.specialText)
                    minWidth = dpi(64f); minHeight = dpi(40f)
                    background = roundRect(t.special.withAlpha(style.keyAlpha), dp(10f))
                }
            }
            view.setOnClickListener { onSelect?.invoke(i) }
            view.setOnLongClickListener { onLongPress?.invoke(i); true }
            flow.addView(view, ViewGroup.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        }
    }
}
