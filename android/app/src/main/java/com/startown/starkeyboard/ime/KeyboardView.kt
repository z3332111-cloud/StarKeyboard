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
        var shading: LinearGradient? = null
        var body: RectF = RectF()
        var scale = 1f
        var pressed = false
        var animator: ValueAnimator? = null
    }

    private var keys: List<Key> = emptyList()

    private class Track(var key: Key, val action: KeyAction, val startX: Float) {
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
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER }

    fun setLayout(newLayout: KeyboardLayout) {
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
                    list.add(Key(spec, RectF(x, y, x + kw, y + rowH)))
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
            val outer = RectF(k.frame).apply { inset(3 * dp * style.gapScale, 4.5f * dp * style.gapScale) }
            if (outer.width() < 4 || outer.height() < 4) continue
            k.path = style.shape.path(outer, dp)
            k.detail = style.shape.detailPath(outer, dp)
            k.shading = if (style.shape.isSoftShape) LinearGradient(0f, outer.top, 0f, outer.bottom,
                intArrayOf(Color.WHITE.withAlpha(style.keyAlpha * 0.30f), Color.TRANSPARENT, Color.BLACK.withAlpha(style.keyAlpha * 0.04f)),
                floatArrayOf(0f, 0.55f, 1f), Shader.TileMode.CLAMP) else null
            k.shadow = Path(k.path).apply { offset(0f, 1.5f * dp) }
            k.body = style.shape.bodyRect(outer, dp)
        }
    }

    override fun onDraw(canvas: Canvas) {
        val t = style.theme
        for (k in keys) {
            val fill: Int
            val text: Int
            when (k.spec.kind) {
                KeyKind.NORMAL -> { fill = if (k.pressed) t.special else t.key; text = t.keyText }
                KeyKind.SPECIAL -> { fill = if (k.pressed) t.key else t.special; text = t.specialText }
                KeyKind.ACCENT -> { fill = if (k.pressed) t.key else t.accent; text = if (k.pressed) t.keyText else t.accentText }
            }
            canvas.save()
            if (k.scale != 1f) canvas.scale(k.scale, k.scale, k.frame.centerX(), k.frame.centerY())
            fillPaint.color = t.shadow.withAlpha(if (style.shape.isSoftShape) style.keyAlpha * 0.32f else minOf(1f, style.keyAlpha + 0.1f))
            canvas.drawPath(k.shadow, fillPaint)
            fillPaint.color = fill.withAlpha(style.keyAlpha)
            canvas.drawPath(k.path, fillPaint)
            if (style.shape == KeyShape.JELLY) {
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
            fillPaint.color = style.shape.detailColor(t).withAlpha(style.keyAlpha * (if (style.shape == KeyShape.PUDDING || style.shape == KeyShape.DUCK) 0.85f else 0.4f))
            canvas.drawPath(k.detail, fillPaint)
            drawLabel(canvas, k, text)
            canvas.restore()
        }
        drawTrail(canvas)
        drawParticles(canvas)
    }

    private fun drawLabel(canvas: Canvas, k: Key, color: Int) {
        textPaint.color = color
        textPaint.typeface = KeyFonts.get(context, style.fontId)
            ?: if (k.spec.kind == KeyKind.NORMAL) Typeface.DEFAULT else Typeface.DEFAULT_BOLD
        var size = k.spec.fontSize * dp * style.fontScale
        if (style.shape.isSoftShape) {
            size = minOf(size, k.body.height() * 0.85f)
        }
        textPaint.textSize = size
        val maxW = k.body.width() - 4 * dp
        val w = textPaint.measureText(k.spec.label)
        if (w > maxW && w > 0) {
            size *= maxW / w
            textPaint.textSize = size
        }
        val fm = textPaint.fontMetrics
        val baseline = k.body.centerY() - (fm.ascent + fm.descent) / 2
        canvas.drawText(k.spec.label, k.body.centerX(), baseline, textPaint)
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
        if (glyphs.isEmpty() || particles.size > 60) return
        val now = android.os.SystemClock.uptimeMillis()
        val t = style.theme
        repeat(3) { i ->
            particles.add(Particle(
                glyphs.random(), k.frame.centerX(), k.frame.centerY(),
                (Math.random().toFloat() - 0.5f) * 44 * dp, -(26 + Math.random().toFloat() * 22) * dp,
                (Math.random().toFloat() - 0.5f) * 70f, (11 + Math.random().toFloat() * 7) * dp,
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
            val t = (now - p.start) / 240f
            if (t >= 1f) { it.remove(); continue }
            val ease = 1 - (1 - t) * (1 - t)
            val x = p.x + p.dx * ease
            val y = p.y + p.dy * ease
            particlePaint.color = p.color.withAlpha(1 - t)
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
        if (pressed) spawnEffect(k)
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

    private fun fire(k: Key) {
        onKey?.invoke(k.spec)
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                // 打很快時，新的手指按下就先送出前一個還沒放開的字
                for (t in tracks.values) {
                    if (!t.fired && !t.cursorMode && !t.gliding && (t.action.isCharacter || t.action == KeyAction.Space)) {
                        t.fired = true
                        setPressed(t.key, false)
                        fire(t.key)
                    }
                }
                val i = e.actionIndex
                val key = keyAt(e.getX(i), e.getY(i)) ?: return true
                val track = Track(key, key.spec.action, e.getX(i))
                if (glideEnabled && key.isLetter) track.points.add(Pt(e.getX(i), e.getY(i)))
                tracks[e.getPointerId(i)] = track
                setPressed(key, true)
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
                    else -> {}
                }
            }
            MotionEvent.ACTION_MOVE -> {
                for (i in 0 until e.pointerCount) {
                    val t = tracks[e.getPointerId(i)] ?: continue
                    if (t.fired) continue
                    val x = e.getX(i)
                    if (t.action == KeyAction.Space) {
                        if (!t.cursorMode && abs(x - t.startX) > 16 * dp) {
                            t.cursorMode = true
                            t.cursorX = x
                        }
                        if (t.cursorMode) {
                            val steps = ((x - t.cursorX) / (9 * dp)).toInt()
                            if (steps != 0) {
                                onCursorMove?.invoke(steps)
                                t.cursorX += steps * 9 * dp
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
                            if (t.points.isNotEmpty() && ++t.visited >= 3) t.gliding = true
                        }
                    }
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                val t = tracks.remove(e.getPointerId(e.actionIndex)) ?: return true
                setPressed(t.key, false)
                if (t.action == KeyAction.Backspace) stopRepeat()
                if (t.action == KeyAction.NextMode) longPressRunnable?.let { mainHandler.removeCallbacks(it) }
                if (t.gliding) {
                    t.points.add(Pt(e.getX(e.actionIndex), e.getY(e.actionIndex)))
                    val kw = keys.firstOrNull { it.isLetter }?.frame?.width() ?: (30 * dp)
                    onGlide?.invoke(t.points, letterCenters(), kw)
                    invalidate()
                } else if (!t.fired && !t.cursorMode && t.action != KeyAction.Backspace && t.action != KeyAction.Shift) fire(t.key)
            }
            MotionEvent.ACTION_CANCEL -> {
                val pending = tracks.values.filter { !it.fired && !it.cursorMode && !it.gliding && it.action.isCharacter }
                for (t in tracks.values) setPressed(t.key, false)
                tracks.clear()
                stopRepeat()
                longPressRunnable?.let { mainHandler.removeCallbacks(it) }
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
