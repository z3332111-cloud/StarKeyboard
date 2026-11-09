package com.startown.starkeyboard.ime

import com.startown.starkeyboard.core.Pt
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.LinearGradient
import android.graphics.Shader
import android.graphics.Color
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.View
import kotlin.math.abs

/** 一整片按鍵：自己畫、自己處理觸控（多指連打、滑動修正、刪除鍵連續刪、空白鍵拖曳移動游標） */
@SuppressLint("ViewConstructor")
class KeyboardView(context: Context, style: KeyboardStyle) : View(context) {
    var onKey: ((KeySpec) -> Unit)? = null
    var onLongPress: ((KeySpec) -> Unit)? = null
    var onCursorMove: ((Int) -> Unit)? = null
    /** 按下去時上面跳出放大的字（看得到自己按到哪一顆） */
    var showsPreview = false
    private var previewKey: Key? = null
    private val previewPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val previewText = Paint(Paint.ANTI_ALIAS_FLAG).also { it.textAlign = Paint.Align.CENTER }

    private fun previewFor(k: Key?): Key? =
        if (showsPreview && k != null && k.spec.action.isCharacter && k.spec.label.length in 1..2) k else null
    /** 按住空白鍵上下滑：游標換到上一行（-1）或下一行（1） */
    var onCursorLine: ((Int) -> Unit)? = null
    /** 開始／結束用空白鍵移動游標（整片鍵盤變淡，看得出來現在是觸控板） */
    var onCursorMode: ((Boolean) -> Unit)? = null

    private fun updateCursorLook() {
        val on = tracks.values.any { it.cursorMode }
        val target = if (on) 0.45f else 1f
        if (alpha != target) {
            alpha = target
            onCursorMode?.invoke(on)
        }
    }
    /** 手指按下去的那一刻（震動、按鍵聲） */
    var onPress: (() -> Unit)? = null
    /** 英文滑行輸入：手指滑過三個以上字母鍵才放開時，把畫的線交出去 */
    var glideEnabled = false
    var onGlide: ((List<Pt>, Map<Char, Pt>, Float) -> Unit)? = null

    var style: KeyboardStyle = style
        set(value) {
            field = value
            rebuildPaths()
            invalidate()
        }

    private val dp = resources.displayMetrics.density
    private var layout = KeyboardLayout(emptyList(), 10f)

    private class Key(val spec: KeySpec, val frame: RectF) {
        var path: Path = Path()
        var shadow: Path = Path()
        var detail: Path = Path()
        var lines: Path? = null   // 只畫線的部分（尾巴、鬍鬚）
        var lineWidth = 1f
        var shading: LinearGradient? = null
        var rim: LinearGradient? = null   // 液態玻璃、金屬：亮亮的邊
        var sheen: LinearGradient? = null // 上半部一大片由亮到透明的反光（看起來鼓鼓的）
        var sheenRect = RectF()
        var outer = RectF()
        var metal: LinearGradient? = null // 液態金屬：一條一條明暗的金屬反光（跟著按鍵顏色）
        var metalFor = 0
        var index = 0               // 第幾顆鍵（小狐狸主題照這個換臉）
        var foxInk: FoxLetter.Ink? = null
        var foxPressedInk: FoxLetter.Ink? = null
        var padDown: Path? = null   // 液態系列：肉球（細節）往下移一點（影子、上緣亮邊）
        var padUp: Path? = null     // 往上移一點（下緣暗邊）
        var body: RectF = RectF()
        var detailAlpha = 0.4f
        var depth = 0f   // 立體：按鍵側面的厚度
        var releaseAt = 0L   // 放開的時間（果凍、跳跳、搖搖放開後還會動一下）
        var scale = 1f
        var pressed = false
        var animator: ValueAnimator? = null
    }

    private var keys: List<Key> = emptyList()

    private class Track(var key: Key, val action: KeyAction, val startX: Float, val startY: Float = 0f) {
        var cursorY = 0f
        var fired = false
        val points = ArrayList<Pt>()   // 滑行輸入：手指經過的點
        var visited = 1                // 經過幾個不同的鍵
        var gliding = false
        var cursorMode = false
        var cursorX = 0f
    }

    private val tracks = HashMap<Int, Track>()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var repeatRunnable: Runnable? = null
    private var longPressRunnable: Runnable? = null

    /** 按鍵特效：從按鍵往上飄、慢慢變透明的小圖案 */
    private class Particle(
        val glyph: String, val x: Float, val y: Float, val dx: Float, val dy: Float,
        val rotation: Float, val size: Float, val color: Int, val start: Long,
    )
    private val particles = ArrayList<Particle>()
    private val particlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER }

    private val trailPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        setStyle(Paint.Style.STROKE); strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
    }

    private val Key.isLetter get() = spec.action is KeyAction.Text && spec.label.length == 1 && spec.label[0].lowercaseChar() in 'a'..'z'

    /** 每個字母鍵的中心（滑行輸入用） */
    private fun letterCenters(): Map<Char, Pt> =
        keys.filter { it.isLetter }.associate { it.spec.label[0].lowercaseChar() to Pt(it.frame.centerX(), it.frame.centerY()) }

    private fun drawTrail(canvas: Canvas) {
        for (t in tracks.values) {
            if (!t.gliding || t.points.size < 2) continue
            val pts = t.points.takeLast(40)
            val path = Path()
            path.moveTo(pts[0].x, pts[0].y)
            for (p in pts.drop(1)) path.lineTo(p.x, p.y)
            trailPaint.color = style.theme.accent.withAlpha(0.55f)
            trailPaint.strokeWidth = 5 * dp
            canvas.drawPath(path, trailPaint)
        }
    }

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val foxPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private val glassPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    // 液態玻璃：模糊過的背景（整張）和它在這片鍵盤上的位置；沒有背景照片就是 null
    private var glassImage: android.graphics.Bitmap? = null
    private val glassRect = RectF()

    fun setGlass(image: android.graphics.Bitmap?, rect: RectF?) {
        glassImage = image
        if (rect != null) glassRect.set(rect)
        invalidate()
    }
    private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        this.style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val rimPaint = Paint(Paint.ANTI_ALIAS_FLAG).also { it.style = Paint.Style.STROKE }
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER }
    private val hintPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.RIGHT }

    fun setLayout(newLayout: KeyboardLayout) {
        popup = null
        layout = newLayout
        rebuildKeys()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        rebuildKeys()
    }

    private fun rebuildKeys() {
        val w = width.toFloat()
        val h = height.toFloat()
        // 換版面時手指還按著：記住哪個位置被按著
        val pressedIndex = keys.indices.filter { keys[it].pressed }.toSet()
        val list = ArrayList<Key>()
        if (layout.rows.isNotEmpty() && w > 0 && h > 0) {
            val padX = 2 * dp
            val padY = 3 * dp
            val rowH = (h - padY * 2) / layout.rows.size
            val unit = (w - padX * 2) / layout.columns
            for ((r, row) in layout.rows.withIndex()) {
                val fixed = row.sumOf { maxOf(it.width, 0f).toDouble() }.toFloat()
                val flexCount = row.count { it.width == 0f }
                val flexW = if (flexCount > 0) maxOf(1f, (layout.columns - fixed) / flexCount) else 0f
                val total = fixed + flexW * flexCount
                var x = padX + maxOf(0f, layout.columns - total) * unit / 2
                val y = padY + rowH * r
                for (spec in row) {
                    val kw = (if (spec.width > 0) spec.width else flexW) * unit
                    list.add(Key(spec, RectF(x, y, x + kw, y + rowH)).also { it.index = list.size })
                    x += kw
                }
            }
        }
        keys = list
        // 按著的鍵換成新版面的同一個位置
        for (track in tracks.values) {
            val i = keys.indexOfFirst { it.frame.contains(track.key.frame.centerX(), track.key.frame.centerY()) }
            if (i >= 0) track.key = keys[i]
        }
        pressedIndex.forEach { if (it < keys.size) keys[it].pressed = true }
        rebuildPaths()
        invalidate()
    }

    private fun rebuildPaths() {
        for (k in keys) {
            // 線條造型（貓咪、熊熊…）有自己的形狀，空隙留小一點，圖案才夠大
            val art = style.shape.art != null
            val outer = RectF(k.frame).apply { inset((if (art) 1.2f else 3f) * dp * style.gapScale, (if (art) 1.8f else 4.5f) * dp * style.gapScale) }
            // 「造型大小」：造型可以畫得比按鍵大一點（寬的空白鍵不放大，才不會蓋到上一排）
            if (art && outer.width() < outer.height() * 1.65f) {
                val grow = style.shapeScale - 1f
                outer.inset(-outer.width() * grow / 2, -outer.height() * grow / 2)
            }
            if (outer.width() < 4 || outer.height() < 4) continue
            // 立體：按鍵往上留出側面的厚度
            k.depth = if (style.finish == KeyFinish.RAISED) minOf(4.5f * dp, outer.height() * 0.12f) else 0f
            outer.bottom -= k.depth
            outer.set(style.shape.naturalRect(outer, style.shapeScale))
            k.path = style.shape.path(outer, dp)
            k.detail = style.shape.detailPath(outer, dp)
            if (style.isFoxLetter) {
                k.foxInk = FoxLetter.ink(k.index, k.spec.action, style.keyAlpha, style.theme)
                k.foxPressedInk = FoxLetter.ink(k.index, k.spec.action, style.keyAlpha * 0.82f, style.theme)
            }
            // 液態系列：肉球也做成立體（往下、往上各移一點，用來畫影子和亮邊、暗邊）
            if (style.finish == KeyFinish.LIQUID || style.finish == KeyFinish.METAL) {
                val d = maxOf(1f * dp, outer.height() * 0.035f)
                k.padDown = Path(k.detail).apply { offset(0f, d) }
                k.padUp = Path(k.detail).apply { offset(0f, -d) }
            } else {
                k.padDown = null; k.padUp = null
            }
            k.lines = style.shape.linesPath(outer)
            // 線稿：線的粗細跟著按鍵大小，細細的
            k.lineWidth = (outer.height() * 0.028f).coerceIn(0.9f * dp, 1.6f * dp)
            val a = style.keyAlpha
            val dark = style.theme.dark
            val shadeColors = when (style.finish) {
                KeyFinish.FLAT -> intArrayOf(Color.WHITE.withAlpha(a * 0.30f), Color.TRANSPARENT, Color.BLACK.withAlpha(a * 0.04f))
                KeyFinish.PUFFY -> intArrayOf(Color.WHITE.withAlpha(a * 0.5f), Color.TRANSPARENT, Color.BLACK.withAlpha(a * (if (dark) 0.22f else 0.10f)))
                // 立體：按鍵調得很透明也看得到上亮下暗
                KeyFinish.RAISED -> maxOf(a, 0.6f).let { v -> intArrayOf(Color.WHITE.withAlpha(v * (if (dark) 0.3f else 0.55f)), Color.TRANSPARENT, Color.BLACK.withAlpha(v * (if (dark) 0.25f else 0.12f))) }
                KeyFinish.OUTLINE -> intArrayOf(Color.TRANSPARENT, Color.TRANSPARENT, Color.TRANSPARENT)
                // 液態玻璃：上面亮、中間透、底部再亮一點（光在玻璃裡反射）
                KeyFinish.LIQUID -> intArrayOf(Color.WHITE.withAlpha(if (dark) 0.3f else 0.45f), Color.TRANSPARENT, Color.WHITE.withAlpha(if (dark) 0.3f else 0.5f))
                KeyFinish.METAL -> intArrayOf(Color.TRANSPARENT, Color.TRANSPARENT, Color.TRANSPARENT)
            }
            val shiny = style.finish == KeyFinish.LIQUID || style.finish == KeyFinish.METAL
            k.outer = RectF(outer)
            // 玻璃邊：上面最亮、中間淡、底部又亮起來；金屬邊：上亮下暗（像斜切的邊）
            k.rim = if (shiny) LinearGradient(0f, outer.top, 0f, outer.bottom,
                if (style.finish == KeyFinish.METAL) intArrayOf(Color.WHITE.withAlpha(0.95f), Color.WHITE.withAlpha(0.2f), Color.BLACK.withAlpha(0.45f))
                else intArrayOf(Color.WHITE, Color.WHITE.withAlpha(0.2f), Color.WHITE.withAlpha(0.85f)),
                floatArrayOf(0f, 0.5f, 1f), Shader.TileMode.CLAMP) else null
            // 上半部一大片反光：從很亮慢慢變透明
            k.sheenRect = RectF(outer.left + outer.width() * 0.07f, outer.top + outer.height() * 0.06f,
                outer.right - outer.width() * 0.07f, outer.top + outer.height() * 0.5f)
            k.sheen = if (shiny) LinearGradient(0f, k.sheenRect.top, 0f, k.sheenRect.bottom,
                intArrayOf(Color.WHITE.withAlpha(if (style.finish == KeyFinish.METAL) 0.75f else 0.7f), Color.WHITE.withAlpha(0f)),
                null, Shader.TileMode.CLAMP) else null
            k.metal = null
            k.shading = if (style.finish != KeyFinish.OUTLINE && (style.shape.isSoftShape || style.finish != KeyFinish.FLAT)) LinearGradient(0f, outer.top, 0f, outer.bottom,
                shadeColors, floatArrayOf(0f, 0.55f, 1f), Shader.TileMode.CLAMP) else null
            k.shadow = Path(k.path).apply { offset(0f, if (k.depth > 0) k.depth else (if (style.finish == KeyFinish.PUFFY) 3f else 1.5f) * dp) }
            k.body = style.shape.bodyRect(outer, dp)
            k.detailAlpha = style.shape.detailOpacity(outer)
        }
    }

    override fun onDraw(canvas: Canvas) {
        val t = style.theme
        val now = android.os.SystemClock.uptimeMillis()
        val motion = KeyMotion.from(style.motion)
        var moving = false
        // 正在動的鍵最後畫，才不會被旁邊的鍵蓋住
        for (k in if (motion != KeyMotion.NONE) keys.sortedBy { if (it.scale != 1f || now - it.releaseAt < 600) 1 else 0 } else keys) {
            val fill: Int
            val text: Int
            when (k.spec.kind) {
                KeyKind.NORMAL -> { fill = if (k.pressed) t.special else t.key; text = t.keyText }
                KeyKind.SPECIAL -> { fill = if (k.pressed) t.key else t.special; text = t.specialText }
                KeyKind.ACCENT -> { fill = if (k.pressed) t.key else t.accent; text = if (k.pressed) t.keyText else t.accentText }
            }
            canvas.save()
            val finish = style.finish
            // 按下去的程度 0～1
            val press = ((1f - k.scale) * 10f).coerceIn(0f, 1f)
            val m = if (k.spec.action.isCharacter) motion else KeyMotion.NONE
            if (m != KeyMotion.NONE && (k.pressed || now - k.releaseAt < 600)) {
                if (applyMotion(canvas, k, m, press, now)) moving = true
            } else if (k.scale != 1f) {
                val d = 1f - k.scale
                // 胖胖的鍵按下去會被壓扁；立體的鍵往下沉
                if (finish == KeyFinish.PUFFY) canvas.scale(1f + d * 0.6f, 1f - d * 1.4f, k.frame.centerX(), k.frame.centerY())
                else if (finish == KeyFinish.RAISED) canvas.translate(0f, k.depth * press * 0.85f)
                else canvas.scale(k.scale, k.scale, k.frame.centerX(), k.frame.centerY())
            }
            val a = style.keyAlpha
            if (style.isIllustrated) {
                drawFoxKey(canvas, k)
                canvas.restore()
                continue
            }
            fillPaint.color = when (finish) {
                KeyFinish.FLAT -> t.shadow.withAlpha(if (style.shape.isSoftShape) a * 0.32f else minOf(1f, a + 0.1f))
                KeyFinish.PUFFY -> t.shadow.withAlpha(minOf(1f, a * 0.75f))
                // 側面用按鍵本身的顏色調暗，透明的鍵也一定看得到
                KeyFinish.RAISED -> darker(fill, if (t.dark) 0.55f else 0.78f).withAlpha(maxOf(a, 0.85f) * (1f - press))
                KeyFinish.OUTLINE -> Color.TRANSPARENT
                KeyFinish.LIQUID -> t.shadow.withAlpha(0.32f)
                KeyFinish.METAL -> darker(fill, 0.35f).withAlpha(0.55f)
            }
            // 影子只畫在按鍵外面，按鍵調透明時才不會看到兩層疊在一起
            canvas.save()
            canvas.clipOutPath(k.path)
            canvas.drawPath(k.shadow, fillPaint)
            if (finish == KeyFinish.LIQUID || finish == KeyFinish.METAL) {
                // 再往下一點一層淡淡的影子：浮起來的感覺
                canvas.translate(0f, 2.5f * dp)
                fillPaint.color = Color.BLACK.withAlpha(0.12f)
                canvas.drawPath(k.shadow, fillPaint)
            }
            canvas.restore()
            val lineColor = style.lineColor
            if (finish == KeyFinish.OUTLINE) {
                // 線稿：只畫一條細線，裡面透明（背景照片完全露出來）；按下去時淡淡填一層
                if (k.pressed) {
                    fillPaint.color = lineColor.withAlpha(0.14f)
                    canvas.drawPath(k.path, fillPaint)
                }
                linePaint.color = lineColor
                linePaint.strokeWidth = k.lineWidth
                canvas.drawPath(k.path, linePaint)
            } else if (finish == KeyFinish.METAL) {
                // 液態金屬：按鍵的顏色做成一條一條明暗的金屬反光（像鉻、像水銀）
                if (k.metal == null || k.metalFor != fill) {
                    val o = k.outer
                    k.metal = LinearGradient(0f, o.top, 0f, o.bottom,
                        intArrayOf(lighter(fill, 0.8f), lighter(fill, 0.35f), darker(fill, 0.62f), lighter(fill, 0.45f), fill, darker(fill, 0.55f)),
                        floatArrayOf(0f, 0.3f, 0.5f, 0.62f, 0.82f, 1f), Shader.TileMode.CLAMP)
                    k.metalFor = fill
                }
                fillPaint.shader = k.metal
                fillPaint.color = Color.WHITE
                fillPaint.alpha = (maxOf(a, 0.9f) * 255).toInt()
                canvas.drawPath(k.path, fillPaint)
                fillPaint.shader = null
                fillPaint.alpha = 255
            } else if (finish == KeyFinish.LIQUID) {
                // 液態玻璃：後面的照片（模糊、稍微放大，像透過一滴水看）＋淡淡的顏色
                glassImage?.let { img ->
                    canvas.save()
                    canvas.clipPath(k.path)
                    canvas.scale(1.08f, 1.08f, k.body.centerX(), k.body.centerY())
                    canvas.drawBitmap(img, null, glassRect, glassPaint)
                    canvas.restore()
                }
                fillPaint.color = fill.withAlpha(a * (if (k.pressed) 0.55f else 0.28f))
                canvas.drawPath(k.path, fillPaint)
                fillPaint.color = Color.WHITE.withAlpha(if (t.dark) 0.05f else 0.12f)
                canvas.drawPath(k.path, fillPaint)
            } else {
                fillPaint.color = fill.withAlpha(a)
                canvas.drawPath(k.path, fillPaint)
            }
            if (finish == KeyFinish.PUFFY) {
                // 左上角一顆圓圓的反光，看起來鼓鼓的
                val b = k.body
                fillPaint.color = Color.WHITE.withAlpha(if (t.dark) 0.3f else 0.75f)
                canvas.drawOval(RectF(b.left + b.width() * 0.14f, b.top + b.height() * 0.1f, b.left + b.width() * 0.46f, b.top + b.height() * 0.3f), fillPaint)
            } else if (finish == KeyFinish.LIQUID || finish == KeyFinish.METAL) {
                canvas.save()
                canvas.clipPath(k.path)
                // 邊緣往內一圈暗一點：看得出玻璃／金屬的厚度
                linePaint.color = Color.BLACK.withAlpha(if (finish == KeyFinish.METAL) 0.22f else 0.13f)
                linePaint.strokeWidth = 5f * dp
                canvas.drawPath(k.path, linePaint)
                // 上半部一大片反光（鼓鼓的）
                k.sheen?.let { sh ->
                    fillPaint.shader = sh
                    fillPaint.color = Color.WHITE
                    val r = k.sheenRect
                    canvas.drawRoundRect(r, r.height() * 0.6f, r.height() * 0.6f, fillPaint)
                    fillPaint.shader = null
                }
                // 左上角一顆很亮的小光點
                val o = k.outer
                fillPaint.color = Color.WHITE.withAlpha(0.9f)
                val dot = minOf(o.height() * 0.13f, 6f * dp)
                canvas.drawOval(RectF(o.left + o.width() * 0.12f, o.top + o.height() * 0.12f,
                    o.left + o.width() * 0.12f + dot * 1.8f, o.top + o.height() * 0.12f + dot), fillPaint)
                canvas.restore()
            } else if (style.shape == KeyShape.JELLY && finish != KeyFinish.OUTLINE) {
                val b = k.body
                val gh = maxOf(2.5f * dp, b.height() * 0.16f)
                fillPaint.color = android.graphics.Color.WHITE.withAlpha(if (t.dark) 0.18f else 0.55f)
                val gloss = RectF(b.left + b.width() * 0.2f, b.top + 2.5f * dp, b.right - b.width() * 0.2f, b.top + 2.5f * dp + gh)
                canvas.drawRoundRect(gloss, gh / 2, gh / 2, fillPaint)
            }
            k.shading?.let { shader ->
                fillPaint.color = Color.WHITE
                fillPaint.shader = shader
                canvas.drawPath(k.path, fillPaint)
                fillPaint.shader = null
            }
            k.rim?.let { shader ->
                // 玻璃邊：上面亮、下面也微微亮
                linePaint.color = Color.WHITE
                linePaint.shader = shader
                linePaint.strokeWidth = 1.7f * dp
                canvas.drawPath(k.path, linePaint)
                linePaint.shader = null
            }
            val padColor = if (style.shape.art?.lineDetail == true) lineColor
                else style.shape.detailColor(t).withAlpha(style.keyAlpha * k.detailAlpha)
            val padDown = k.padDown
            val padUp = k.padUp
            if (padDown != null) {
                // 肉球底下一點影子（浮起來）
                canvas.save()
                canvas.clipOutPath(k.detail)
                fillPaint.color = darker(padColor, 0.55f).withAlpha(0.45f)
                canvas.drawPath(padDown, fillPaint)
                canvas.restore()
            }
            fillPaint.color = padColor
            canvas.drawPath(k.detail, fillPaint)
            if (padDown != null && padUp != null) {
                // 上緣一道亮邊、下緣一道暗邊：每顆肉球都鼓鼓的
                canvas.save()
                canvas.clipPath(k.detail)
                canvas.clipOutPath(padDown)
                canvas.drawColor(Color.WHITE.withAlpha(0.75f))
                canvas.restore()
                canvas.save()
                canvas.clipPath(k.detail)
                canvas.clipOutPath(padUp)
                canvas.drawColor(Color.BLACK.withAlpha(0.2f))
                canvas.restore()
            }
            k.lines?.let {
                linePaint.color = lineColor
                linePaint.strokeWidth = k.lineWidth * 0.9f
                canvas.drawPath(it, linePaint)
            }
            drawLabel(canvas, k, text)
            canvas.restore()
        }
        if (moving) postInvalidateOnAnimation()
        drawTrail(canvas)
        drawParticles(canvas)
    }

    /** 小狐狸主題：水彩鍵帽＋程式畫的字（字不烘在圖裡，換字型、大小都照常） */
    private fun drawFoxKey(canvas: Canvas, k: Key) {
        style.themeLook?.let { look ->
            drawPackKey(canvas, k, look)
            return
        }
        val compact = k.frame.height() < 40 * dp && !k.spec.action.isCharacter
        val frame = FoxLetter.frame(k.frame, style.gapScale, style.shapeScale, dp, compact)
        if (frame.isEmpty) return
        val personal = k.spec.label.startsWith(SpaceArt.MARK)
        foxPaint.alpha = (style.keyAlpha * (if (k.pressed) 0.82f else 1f) * 255).toInt().coerceIn(0, 255)
        FoxLetter.drawKey(context, canvas, frame, k.index, k.spec.action, personal, compact, foxPaint)
        if (drawSpaceArt(canvas, k)) return
        val ink = (if (k.pressed) k.foxPressedInk else k.foxInk) ?: return
        // 造型放大時字還是留在按鍵裡
        val rect = FoxLetter.labelRect(frame, compact, dp).also { it.intersect(k.frame) }
        textPaint.typeface = KeyFonts.get(context, style.fontId) ?: Typeface.DEFAULT_BOLD
        var size = minOf(k.spec.fontSize * dp * style.fontScale, rect.height())
        textPaint.textSize = size
        val w = textPaint.measureText(k.spec.label)
        if (w > rect.width() && w > 0) {
            size *= rect.width() / w
            textPaint.textSize = size
        }
        val fm = textPaint.fontMetrics
        val baseline = rect.centerY() - (fm.ascent + fm.descent) / 2
        ink.outline?.let { edge ->
            textPaint.style = Paint.Style.STROKE
            textPaint.strokeWidth = size * 0.03f
            textPaint.color = edge
            canvas.drawText(k.spec.label, rect.centerX(), baseline, textPaint)
            textPaint.style = Paint.Style.FILL
        }
        textPaint.color = ink.color
        canvas.drawText(k.spec.label, rect.centerX(), baseline, textPaint)
        if (k.spec.hint.isNotEmpty()) {
            val h = FoxLetter.hintRect(frame, dp)
            hintPaint.textAlign = Paint.Align.CENTER
            hintPaint.color = style.theme.keyText
            hintPaint.textSize = minOf(9 * dp * style.fontScale, h.height())
            canvas.drawText(k.spec.hint, h.centerX(), h.top + hintPaint.textSize, hintPaint)
            hintPaint.textAlign = Paint.Align.RIGHT
        }
    }

    /** 設計圖鑑的主題：字的鍵是鍵帽、空白鍵是寬圖、功能鍵是素色方塊 */
    private fun drawPackKey(canvas: Canvas, k: Key, look: ThemeLook) {
        val action = k.spec.action
        val opacity = style.keyAlpha * (if (k.pressed) 0.82f else 1f)
        val color: Int
        val rect: RectF
        if (action != KeyAction.Space && !action.isCharacter) {
            val chip = RectF(k.frame).apply { inset(2.5f * dp * style.gapScale, 4 * dp * style.gapScale) }
            if (chip.isEmpty) return
            val radius = minOf(8 * dp, chip.height() * 0.22f)
            fillPaint.color = look.theme.special.withAlpha(opacity)
            canvas.drawRoundRect(chip, radius, radius, fillPaint)
            color = look.theme.specialText
            rect = chip
        } else {
            val frame = FoxLetter.frame(k.frame, style.gapScale, style.shapeScale, dp)
            if (frame.isEmpty) return
            foxPaint.alpha = (opacity * 255).toInt().coerceIn(0, 255)
            if (action == KeyAction.Space) {
                FoxLetter.drawPackWide(context, canvas, frame, look, foxPaint)
                color = look.spaceInk
            } else {
                FoxLetter.drawPackCap(context, canvas, frame, k.index, look, foxPaint)
                color = look.ink
                if (k.spec.hint.isNotEmpty()) {
                    val h = FoxLetter.hintRect(frame, dp)
                    hintPaint.textAlign = Paint.Align.CENTER
                    hintPaint.color = look.hint
                    hintPaint.textSize = minOf(9 * dp * style.fontScale, h.height())
                    canvas.drawText(k.spec.hint, h.centerX(), h.top + hintPaint.textSize, hintPaint)
                    hintPaint.textAlign = Paint.Align.RIGHT
                }
            }
            rect = FoxLetter.labelRect(frame, false, dp).also { it.intersect(k.frame) }
        }
        if (drawSpaceArt(canvas, k)) return
        textPaint.typeface = KeyFonts.get(context, style.fontId) ?: Typeface.DEFAULT_BOLD
        textPaint.color = color
        var size = minOf(k.spec.fontSize * dp * style.fontScale, rect.height())
        textPaint.textSize = size
        val w = textPaint.measureText(k.spec.label)
        if (w > rect.width() && w > 0) {
            size *= rect.width() / w
            textPaint.textSize = size
        }
        val fm = textPaint.fontMetrics
        canvas.drawText(k.spec.label, rect.centerX(), rect.centerY() - (fm.ascent + fm.descent) / 2, textPaint)
    }

    /** 放大泡泡：在按鍵上方畫一個大大的字（最上排就往下一點，不要被切掉） */
    private fun drawPreview(canvas: Canvas, k: Key) {
        val t = style.theme
        val f = k.frame
        val w = maxOf(f.width() * 1.45f, 42 * dp)
        val h = f.height() * 1.2f
        val left = (f.centerX() - w / 2).coerceIn(2 * dp, maxOf(2 * dp, width - w - 2 * dp))
        val top = maxOf(0f, f.top - h + 4 * dp)
        val r = RectF(left, top, left + w, top + h)
        val radius = minOf(w, h) * 0.42f
        previewPaint.style = Paint.Style.FILL
        previewPaint.color = t.shadow.withAlpha(0.5f)
        canvas.drawRoundRect(RectF(r).apply { offset(0f, 2 * dp) }, radius, radius, previewPaint)
        previewPaint.color = t.key
        canvas.drawRoundRect(r, radius, radius, previewPaint)
        previewPaint.style = Paint.Style.STROKE
        previewPaint.strokeWidth = 1.5f * dp
        previewPaint.color = t.accent.withAlpha(0.6f)
        canvas.drawRoundRect(r, radius, radius, previewPaint)
        previewText.color = t.keyText
        previewText.textSize = h * 0.6f
        previewText.typeface = KeyFonts.get(context, style.fontId) ?: Typeface.DEFAULT_BOLD
        val fm = previewText.fontMetrics
        canvas.drawText(k.spec.label, r.centerX(), r.centerY() - (fm.ascent + fm.descent) / 2, previewText)
    }

    /** 可愛的按鍵動作；回傳 true 表示還在動（要繼續重畫） */
    private fun applyMotion(canvas: Canvas, k: Key, m: KeyMotion, press: Float, now: Long): Boolean {
        val f = k.frame
        val h = f.height()
        val cx = f.centerX()
        if (k.pressed) {
            when (m) {
                KeyMotion.POP -> { canvas.translate(0f, -h * 0.22f * press); canvas.scale(1f + 0.25f * press, 1f + 0.25f * press, cx, f.centerY()) }
                KeyMotion.JELLY -> canvas.scale(1f + 0.18f * press, 1f - 0.2f * press, cx, f.bottom)   // 貼著地板壓扁
                KeyMotion.HOP -> canvas.scale(1f + 0.06f * press, 1f - 0.1f * press, cx, f.bottom)
                KeyMotion.WIGGLE -> { canvas.rotate(9f * press, cx, f.centerY()); canvas.scale(1f + 0.08f * press, 1f + 0.08f * press, cx, f.centerY()) }
                KeyMotion.NONE -> {}
            }
            return false
        }
        val ms = (now - k.releaseAt).toFloat()
        when (m) {
            KeyMotion.JELLY -> {
                // 像果凍一樣 duang duang 抖回來：越抖越小
                val t = ms / 550f
                if (t >= 1f) return false
                val a = Math.exp(-4.5 * t).toFloat() * Math.cos(4.5 * Math.PI * t).toFloat()
                canvas.scale(1f + 0.18f * a, 1f - 0.2f * a, cx, f.bottom)
            }
            KeyMotion.HOP -> {
                // 蹦一下：往上跳（拉長）→ 落地壓扁 → 回來
                val t = ms / 420f
                if (t >= 1f) return false
                if (t < 0.65f) {
                    val u = t / 0.65f
                    canvas.translate(0f, -h * 0.45f * Math.sin(Math.PI * u).toFloat())
                    canvas.scale(0.92f, 1.12f, cx, f.centerY())
                } else {
                    val s = Math.sin(Math.PI * (t - 0.65f) / 0.35f).toFloat()
                    canvas.scale(1f + 0.15f * s, 1f - 0.15f * s, cx, f.bottom)
                }
            }
            KeyMotion.WIGGLE -> {
                // 左右扭一扭
                val t = ms / 400f
                if (t >= 1f) return false
                val angle = 12f * Math.exp(-3.5 * t).toFloat() * Math.sin(5 * Math.PI * t).toFloat()
                canvas.rotate(-angle, cx, f.centerY())
            }
            KeyMotion.POP -> {
                // 放大的那種很快縮回去
                val t = ms / 90f
                if (t >= 1f) return false
                val s = 1f + 0.25f * (1f - t)
                canvas.translate(0f, -h * 0.22f * (1f - t))
                canvas.scale(s, s, cx, f.centerY())
            }
            KeyMotion.NONE -> return false
        }
        return true
    }

    /** 調亮：往白色靠 f（0～1） */
    private fun lighter(c: Int, f: Float) = Color.rgb((Color.red(c) + (255 - Color.red(c)) * f).toInt(),
        (Color.green(c) + (255 - Color.green(c)) * f).toInt(), (Color.blue(c) + (255 - Color.blue(c)) * f).toInt())

    private fun darker(c: Int, f: Float) = Color.rgb((Color.red(c) * f).toInt(), (Color.green(c) * f).toInt(), (Color.blue(c) * f).toInt())

    // 空白鍵的圖（GIF 會動）：換圖時才重新讀
    private var spaceArt: android.graphics.drawable.Drawable? = null
    private var spaceArtKey = ""
    // Drawable 只記得 callback 的弱參照，要自己留著
    private val spaceArtCallback = object : android.graphics.drawable.Drawable.Callback {
        override fun invalidateDrawable(who: android.graphics.drawable.Drawable) { invalidate() }
        override fun scheduleDrawable(who: android.graphics.drawable.Drawable, what: Runnable, `when`: Long) { postDelayed(what, `when` - android.os.SystemClock.uptimeMillis()) }
        override fun unscheduleDrawable(who: android.graphics.drawable.Drawable, what: Runnable) { removeCallbacks(what) }
    }

    private fun drawSpaceArt(canvas: Canvas, k: Key): Boolean {
        if (!k.spec.label.startsWith(SpaceArt.MARK)) return false
        if (spaceArtKey != k.spec.label) {
            spaceArtKey = k.spec.label
            (spaceArt as? android.graphics.drawable.Animatable)?.stop()
            spaceArt = SpaceArt.load(context)?.also { d ->
                d.callback = spaceArtCallback
                (d as? android.graphics.drawable.Animatable)?.start()
            }
        }
        val d = spaceArt ?: return false
        // 小小的放在正中間，維持原本的比例
        val h = k.body.height() * 0.8f
        val iw = d.intrinsicWidth.coerceAtLeast(1).toFloat(); val ih = d.intrinsicHeight.coerceAtLeast(1).toFloat()
        val w = minOf(h * iw / ih, k.body.width() * 0.6f)
        val hh = w * ih / iw
        d.setBounds((k.body.centerX() - w / 2).toInt(), (k.body.centerY() - hh / 2).toInt(), (k.body.centerX() + w / 2).toInt(), (k.body.centerY() + hh / 2).toInt())
        d.draw(canvas)
        return true
    }

    private fun drawLabel(canvas: Canvas, k: Key, color: Int) {
        if (drawSpaceArt(canvas, k)) return
        textPaint.color = color
        textPaint.typeface = KeyFonts.get(context, style.fontId)
            ?: if (k.spec.kind == KeyKind.NORMAL) Typeface.DEFAULT else Typeface.DEFAULT_BOLD
        var size = k.spec.fontSize * dp * style.fontScale
        val art = style.shape.art != null
        if (style.shape.isSoftShape) {
            // 線條造型的字可以比身體框大一點，「字的大小」才調得動
            size = minOf(size, k.body.height() * (if (art) 1.4f else 0.85f))
        }
        textPaint.textSize = size
        val maxW = if (art) k.body.width() * 1.3f else k.body.width() - 4 * dp
        val w = textPaint.measureText(k.spec.label)
        if (w > maxW && w > 0) {
            size *= maxW / w
            textPaint.textSize = size
        }
        val fm = textPaint.fontMetrics
        val baseline = k.body.centerY() - (fm.ascent + fm.descent) / 2
        canvas.drawText(k.spec.label, k.body.centerX(), baseline, textPaint)
        if (k.spec.hint.isNotEmpty()) {
            hintPaint.color = color
            hintPaint.alpha = 150
            hintPaint.textSize = minOf(10 * dp * style.fontScale, k.body.height() * 0.3f)
            canvas.drawText(k.spec.hint, k.body.right - 3 * dp, k.body.top + hintPaint.textSize + 1 * dp, hintPaint)
        }
    }

    // ===== 觸控 =====

    private fun keyAt(x: Float, y: Float): Key? {
        keys.firstOrNull { it.frame.contains(x, y) }?.let { return it }
        return keys.minByOrNull { k ->
            val dx = maxOf(k.frame.left - x, 0f, x - k.frame.right)
            val dy = maxOf(k.frame.top - y, 0f, y - k.frame.bottom)
            dx * dx + dy * dy
        }
    }

    private fun spawnEffect(k: Key) {
        val glyphs = KeyEffect.from(style.keyEffect).glyphs
        if (glyphs.isEmpty() || particles.size > 90) return
        val now = android.os.SystemClock.uptimeMillis()
        val t = style.theme
        repeat(3) { i ->
            particles.add(Particle(
                glyphs.random(), k.frame.centerX(), k.frame.centerY(),
                (Math.random().toFloat() - 0.5f) * 60 * dp, -(45 + Math.random().toFloat() * 30) * dp,
                (Math.random().toFloat() - 0.5f) * 70f, (15 + Math.random().toFloat() * 9) * dp,
                if (i == 0) t.accent else t.keyText, now,
            ))
        }
        invalidate()
    }

    private fun drawParticles(canvas: Canvas) {
        if (particles.isEmpty()) return
        val now = android.os.SystemClock.uptimeMillis()
        val it = particles.iterator()
        while (it.hasNext()) {
            val p = it.next()
            // 飄久一點（0.8 秒），前半段清楚看得到，後半段才慢慢變透明
            val t = (now - p.start) / 800f
            if (t >= 1f) { it.remove(); continue }
            val ease = 1 - (1 - t) * (1 - t)
            val x = p.x + p.dx * ease
            val y = p.y + p.dy * ease
            particlePaint.color = p.color.withAlpha(if (t < 0.5f) 1f else 1f - (t - 0.5f) / 0.5f)
            particlePaint.textSize = p.size * (1 + 0.3f * ease)
            canvas.save()
            canvas.rotate(p.rotation * ease, x, y)
            canvas.drawText(p.glyph, x, y, particlePaint)
            canvas.restore()
        }
        if (particles.isNotEmpty()) postInvalidateOnAnimation()
    }

    private fun setPressed(k: Key, pressed: Boolean) {
        if (k.pressed == pressed) return
        k.pressed = pressed
        if (pressed) spawnEffect(k) else k.releaseAt = android.os.SystemClock.uptimeMillis()
        k.animator?.cancel()
        val anim = if (pressed) {
            ValueAnimator.ofFloat(k.scale, 0.9f).setDuration(50)
        } else {
            ValueAnimator.ofFloat(k.scale, 1f).setDuration(80)
        }
        anim.addUpdateListener { k.scale = it.animatedValue as Float; invalidate() }
        anim.start()
        k.animator = anim
        invalidate()
    }

    // ===== 按住跳出的標點清單 =====

    private class Popup(val pointer: Int, val items: List<String>, val box: RectF, val cells: List<RectF>) {
        var selected = -1
    }
    private var popup: Popup? = null
    private val popupPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val popupText = Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER }

    private fun showPopup(pointer: Int, key: Key, track: Track) {
        val items = key.spec.popup
        val perRow = minOf(items.size, 7)
        val rowCount = (items.size + perRow - 1) / perRow
        val cw = ((width - 12 * dp) / perRow).coerceIn(32 * dp, maxOf(32 * dp, 44 * dp))
        val ch = (key.frame.height() * 0.9f).coerceIn(36 * dp, 46 * dp)
        val w = cw * perRow + 8 * dp
        val h = ch * rowCount + 8 * dp
        val x = (key.frame.centerX() - w / 2).coerceIn(2 * dp, maxOf(2 * dp, width - w - 2 * dp))
        val y = maxOf(0f, key.frame.top - h - 4 * dp)
        val box = RectF(x, y, x + w, y + h)
        val cells = items.indices.map { i ->
            val cx = x + 4 * dp + (i % perRow) * cw
            val cy = y + 4 * dp + (i / perRow) * ch
            RectF(cx, cy, cx + cw, cy + ch)
        }
        popup = Popup(pointer, items, box, cells)
        onPress?.invoke()
        selectPopup(track.startX, track.startY)
        invalidate()
    }

    /** 手指在哪一格就選哪一格；離清單太遠就不選（放開等於取消） */
    private fun selectPopup(px: Float, py: Float) {
        val p = popup ?: return
        var best = -1
        val near = RectF(p.box).apply { inset(-24 * dp, -60 * dp) }
        if (near.contains(px, py)) {
            var bestD = Float.MAX_VALUE
            p.cells.forEachIndexed { i, c ->
                val d = Math.hypot((c.centerX() - px).toDouble(), (c.centerY() - py).toDouble()).toFloat()
                if (d < bestD) { bestD = d; best = i }
            }
        }
        if (best == p.selected) return
        p.selected = best
        if (best >= 0) onPress?.invoke()
        invalidate()
    }

    private fun closePopup(commit: Boolean) {
        val p = popup ?: return
        popup = null
        invalidate()
        if (commit && p.selected in p.items.indices) {
            val s = p.items[p.selected]
            onKey?.invoke(KeySpec(s, KeyAction.Text(s)))
        }
    }

    override fun onDrawForeground(canvas: Canvas) {
        super.onDrawForeground(canvas)
        val p = popup ?: return
        popupPaint.color = android.graphics.Color.argb(248, 43, 43, 43)
        canvas.drawRoundRect(p.box, 12 * dp, 12 * dp, popupPaint)
        popupText.textSize = 20 * dp
        val fm = popupText.fontMetrics
        p.cells.forEachIndexed { i, c ->
            if (i == p.selected) {
                popupPaint.color = style.theme.accent
                canvas.drawRoundRect(c, 8 * dp, 8 * dp, popupPaint)
            }
            popupText.color = if (i == p.selected) style.theme.accentText else android.graphics.Color.WHITE
            canvas.drawText(p.items[i], c.centerX(), c.centerY() - (fm.ascent + fm.descent) / 2, popupText)
        }
    }

    private fun fire(k: Key) {
        onKey?.invoke(k.spec)
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                val i = e.actionIndex
                val key = keyAt(e.getX(i), e.getY(i)) ?: return true
                // 先亮起這顆鍵，再送出上一拍還沒放開的字。選字不能擋住按鍵變色。
                setPressed(key, true)
                onPress?.invoke()
                val track = Track(key, key.spec.action, e.getX(i), e.getY(i))
                previewKey = previewFor(key)
                if (glideEnabled && key.isLetter) track.points.add(Pt(e.getX(i), e.getY(i)))
                tracks[e.getPointerId(i)] = track
                for (t in tracks.values) {
                    if (t !== track && !t.fired && !t.cursorMode && !t.gliding && (t.action.isCharacter || t.action == KeyAction.Space)) {
                        t.fired = true
                        setPressed(t.key, false)
                        fire(t.key)
                    }
                }
                when (key.spec.action) {
                    KeyAction.Backspace -> {
                        track.fired = true
                        fire(key)
                        startRepeat(key)
                    }
                    KeyAction.Shift -> {
                        track.fired = true
                        fire(key)
                    }
                    KeyAction.NextMode -> {
                        val r = Runnable {
                            if (!track.fired) {
                                track.fired = true
                                setPressed(track.key, false)
                                onLongPress?.invoke(key.spec)
                            }
                        }
                        longPressRunnable = r
                        mainHandler.postDelayed(r, 500)
                    }
                    else -> if (key.spec.hint.isNotEmpty() || key.spec.popup.isNotEmpty()) {
                        // 長按有小字的鍵：打出右上角那個字（數字、字母、句號）
                        val hint = key.spec.hint
                        val pid = e.getPointerId(i)   // MotionEvent 之後會被回收，先記下手指編號
                        mainHandler.postDelayed({
                            if (!track.fired && !track.cursorMode && !track.gliding && track.key === key && tracks.containsValue(track)) {
                                track.fired = true
                                setPressed(key, false)
                                previewKey = null
                                invalidate()
                                if (key.spec.popup.isNotEmpty()) showPopup(pid, key, track)
                                else onKey?.invoke(KeySpec(hint, KeyAction.Text(hint)))
                            }
                        }, 450)
                    }
                }
            }
            MotionEvent.ACTION_MOVE -> {
                for (i in 0 until e.pointerCount) {
                    if (popup?.pointer == e.getPointerId(i)) { selectPopup(e.getX(i), e.getY(i)); continue }
                    val t = tracks[e.getPointerId(i)] ?: continue
                    if (t.fired) continue
                    val x = e.getX(i)
                    if (t.action == KeyAction.Space) {
                        val y = e.getY(i)
                        if (!t.cursorMode && (abs(x - t.startX) > 16 * dp || abs(y - t.startY) > 18 * dp)) {
                            t.cursorMode = true
                            t.cursorX = x
                            // 上下從按下去的地方算起：空白鍵在最下面，往下能滑的距離很短
                            t.cursorY = t.startY
                            updateCursorLook()
                        }
                        if (t.cursorMode) {
                            // 左右：每 10dp 一個字，跟手、不加速，慢慢滑可以停在任何兩個字中間
                            val steps = ((x - t.cursorX) / (10 * dp)).toInt()
                            if (steps != 0) {
                                onCursorMove?.invoke(steps)
                                t.cursorX += steps * 10 * dp
                            }
                            // 上下：往上 24dp 換一行；往下 16dp（空白鍵在最下面，往下能滑的地方少）
                            val dy = y - t.cursorY
                            val step = (if (dy > 0) 16 else 24) * dp
                            if (abs(dy) >= step) {
                                val d = if (dy > 0) 1 else -1
                                onCursorLine?.invoke(d)
                                t.cursorY += d * step
                                // 換行時手指左右晃一點不算，游標留在原本的直排位置
                                t.cursorX = x - ((x - t.cursorX) % (10 * dp)).coerceIn(-4 * dp, 4 * dp)
                            }
                        }
                    } else if (t.action.isCharacter) {
                        if (t.points.isNotEmpty()) {
                            t.points.add(Pt(x, e.getY(i)))
                            if (t.gliding) invalidate()
                        }
                        val k = keyAt(x, e.getY(i))
                        if (k != null && k !== t.key && k.spec.action.isCharacter) {
                            setPressed(t.key, false)
                            setPressed(k, true)
                            t.key = k
                            previewKey = previewFor(k)
                            invalidate()
                            if (t.points.isNotEmpty() && ++t.visited >= 3) t.gliding = true
                        }
                    }
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                if (popup?.pointer == e.getPointerId(e.actionIndex)) {
                    tracks.remove(e.getPointerId(e.actionIndex))?.let { setPressed(it.key, false) }
                    closePopup(true)
                    return true
                }
                val t = tracks.remove(e.getPointerId(e.actionIndex)) ?: return true
                setPressed(t.key, false)
                if (tracks.isEmpty() || previewKey === t.key) { previewKey = null; invalidate() }
                if (t.action == KeyAction.Backspace) stopRepeat()
                if (t.action == KeyAction.NextMode) longPressRunnable?.let { mainHandler.removeCallbacks(it) }
                if (t.gliding) {
                    t.points.add(Pt(e.getX(e.actionIndex), e.getY(e.actionIndex)))
                    val kw = keys.firstOrNull { it.isLetter }?.frame?.width() ?: (30 * dp)
                    onGlide?.invoke(t.points, letterCenters(), kw)
                    invalidate()
                } else if (!t.fired && !t.cursorMode && t.action != KeyAction.Backspace && t.action != KeyAction.Shift) fire(t.key)
                updateCursorLook()
            }
            MotionEvent.ACTION_CANCEL -> {
                closePopup(false)
                val pending = tracks.values.filter { !it.fired && !it.cursorMode && !it.gliding && it.action.isCharacter }
                for (t in tracks.values) setPressed(t.key, false)
                tracks.clear()
                previewKey = null
                invalidate()
                stopRepeat()
                longPressRunnable?.let { mainHandler.removeCallbacks(it) }
                updateCursorLook()
                for (t in pending) fire(t.key)
            }
        }
        return true
    }

    private fun startRepeat(k: Key) {
        stopRepeat()
        val r = object : Runnable {
            override fun run() {
                fire(k)
                mainHandler.postDelayed(this, 80)
            }
        }
        repeatRunnable = r
        mainHandler.postDelayed(r, 450)
    }

    private fun stopRepeat() {
        repeatRunnable?.let { mainHandler.removeCallbacks(it) }
        repeatRunnable = null
    }
}
