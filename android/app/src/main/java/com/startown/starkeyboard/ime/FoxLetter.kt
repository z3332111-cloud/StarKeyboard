package com.startown.starkeyboard.ime

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.drawable.Drawable
import android.view.View
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/** 小狐狸的楓葉信（和 iPhone 版 Keyboard/FoxLetter*.swift 一樣的主題）：只提供外觀，按鍵動作和個人設定不變 */
object FoxLetter {
    const val ID = "fox-letter"

    private fun c(hex: String) = Color.parseColor(hex)

    val theme = KeyboardTheme(ID, "小狐狸的楓葉信", c("#51424D"), c("#392F3D"), c("#6C5050"), c("#FFF5E4"),
        c("#59434A"), c("#FFF5E4"), c("#E9AE78"), c("#3F2C27"), c("#271D27"), "", true)

    class Palette(val fur: Int, val text: Int)
    private val palettes = listOf(
        Palette(c("#A95B30"), c("#FFF9EF")), Palette(c("#DCBC8E"), c("#543B2F")), Palette(c("#71514C"), c("#FFF9EF")),
        Palette(c("#A85747"), c("#FFF9EF")), Palette(c("#737344"), c("#FFF9EF")),
    )
    private val paperPalettes = listOf(listOf(0, 3, 6), listOf(1, 5), listOf(2, 7), listOf(4), listOf(8))
    private val paperCuts = floatArrayOf(0f, 0.15f, 0.425f, 0.575f, 0.85f, 1f)
    // 寬鍵圖集的兩格：x, y, 寬, 高（0～1）
    private val wideCells = listOf(floatArrayOf(0.02f, 0.065f, 0.96f, 0.4f), floatArrayOf(0.02f, 0.54f, 0.96f, 0.4f))

    /** 保留原本的造型和質感設定，離開這個主題就恢復 */
    fun resolved(style: KeyboardStyle) =
        if (style.theme.id == ID) style.copy(shape = KeyShape.ROUNDED, finish = KeyFinish.FLAT) else style

    // ===== 圖集：只解一次，每顆鍵共用 =====

    private val images = HashMap<String, Bitmap?>()

    private fun image(context: Context, name: String): Bitmap? = images.getOrPut(name) {
        runCatching {
            context.applicationContext.assets.open("$name.png").use { BitmapFactory.decodeStream(it) }
        }.getOrNull()
    }

    fun keycaps(context: Context) = image(context, "keycaps-watercolor-v2")
    fun wideKeycaps(context: Context) = image(context, "wide-keycaps-watercolor-v2")
    fun backdrop(context: Context) = image(context, "background-watercolor-v2")

    // ===== 每顆鍵的樣子 =====

    private fun sprite(index: Int, action: KeyAction, personalSpaceArt: Boolean): Int = when (action) {
        KeyAction.Space -> if (personalSpaceArt) 3 else 0
        KeyAction.Return -> 7
        else -> {
            val position = max(0, index)
            val choices = paperPalettes[position % 5]
            choices[(position / 5) % choices.size]
        }
    }

    private fun palette(index: Int, action: KeyAction) = palettes[when (action) {
        KeyAction.Return -> 2
        KeyAction.Space -> 0
        else -> max(0, index) % palettes.size
    }]

    /** 插畫放在按鍵的哪裡（gap、scale 是使用者調的間距和造型大小） */
    fun frame(key: RectF, gapScale: Float, shapeScale: Float, dp: Float): RectF {
        val w = key.width() / dp
        val h = key.height() / dp
        if (w <= 6 || h <= 6) return RectF()
        val gap = gapScale.coerceIn(0.3f, 1.8f)
        val factor = (shapeScale / 1.15f).coerceIn(0.8f, 1.12f)
        val width = min(w - 1.4f, max(5f, w - 2 * gap) * factor) * dp
        val height = min(h - 1.4f, max(5f, h - 4 * gap) * factor) * dp
        return RectF(key.centerX() - width / 2, key.centerY() - height / 2, key.centerX() + width / 2, key.centerY() + height / 2)
    }

    /** 畫一顆鍵的插畫。寬鍵只拉長五官兩側的毛，中央五官和兩端耳朵不變形 */
    fun drawKey(context: Context, canvas: Canvas, frame: RectF, index: Int, action: KeyAction,
                personalSpaceArt: Boolean, compact: Boolean, paint: Paint) {
        val wide = frame.width() > frame.height() * 1.35f
        val image = (if (wide) wideKeycaps(context) else keycaps(context)) ?: return
        val iw = image.width.toFloat()
        val ih = image.height.toFloat()
        val heightPart = if (compact) 0.78f else 1f
        if (!wide) {
            val s = sprite(index, action, personalSpaceArt)
            val x = (s % 3) / 3f
            val y = (s / 3) / 3f
            canvas.drawBitmap(image, Rect((x * iw).toInt(), (y * ih).toInt(), ((x + 1 / 3f) * iw).toInt(), ((y + heightPart / 3f) * ih).toInt()), frame, paint)
            return
        }
        val cell = wideCells[if (action == KeyAction.Space && !personalSpaceArt) 0 else 1]
        val natural = frame.height() * 2.9f
        val stretch = (frame.width() - natural * 0.45f) / 2
        var x = frame.left
        for (i in 0 until 5) {
            val fraction = paperCuts[i + 1] - paperCuts[i]
            val width = if (i == 1 || i == 3) stretch else natural * fraction
            val sx = cell[0] + cell[2] * paperCuts[i]
            val src = Rect((sx * iw).toInt(), (cell[1] * ih).toInt(), ((sx + cell[2] * fraction) * iw).toInt(), ((cell[1] + cell[3] * heightPart) * ih).toInt())
            // 多蓋半個像素，接縫才不會露出一條線
            canvas.drawBitmap(image, src, RectF(x, frame.top, x + width + 0.5f, frame.bottom), paint)
            x += width
        }
    }

    private fun place(f: RectF, x: Float, y: Float, w: Float, h: Float) =
        RectF(f.left + f.width() * x, f.top + f.height() * y, f.left + f.width() * (x + w), f.top + f.height() * (y + h))

    private fun inner(frame: RectF, dp: Float) = RectF(frame).apply { inset(2 * dp, 2 * dp) }

    /** 字放在這裡；很矮的功能鍵讓出五官的位置，字才不會太小 */
    fun labelRect(frame: RectF, compact: Boolean, dp: Float) =
        if (compact) place(inner(frame, dp), 0.16f, 0.24f, 0.68f, 0.64f) else place(inner(frame, dp), 0.14f, 0.26f, 0.72f, 0.44f)

    fun hintRect(frame: RectF, dp: Float) = place(inner(frame, dp), 0.34f, 0f, 0.32f, 0.2f)

    // ===== 字的顏色：對比不夠時加一圈細邊 =====

    class Ink(val color: Int, val outline: Int?)

    private fun channel(v: Int): Float {
        val x = v / 255f
        return if (x <= 0.04045f) x / 12.92f else ((x + 0.055f) / 1.055f).toDouble().pow(2.4).toFloat()
    }

    private fun luminance(r: Float, g: Float, b: Float) = r * 0.2126f + g * 0.7152f + b * 0.0722f

    private fun luminance(color: Int) =
        luminance(channel(Color.red(color)), channel(Color.green(color)), channel(Color.blue(color)))

    fun ink(index: Int, action: KeyAction, opacity: Float, keyTheme: KeyboardTheme): Ink {
        val p = palette(index, action)
        val alpha = opacity.coerceIn(0f, 1f)
        fun blend(a: Int, b: Int) = (a * alpha + b * (1 - alpha)).toInt()
        val backgrounds = listOf(keyTheme.top, keyTheme.bottom).map { bg ->
            luminance(Color.rgb(blend(Color.red(p.fur), Color.red(bg)), blend(Color.green(p.fur), Color.green(bg)), blend(Color.blue(p.fur), Color.blue(bg))))
        }
        fun score(color: Int): Float {
            val value = luminance(color)
            return backgrounds.minOf { (max(value, it) + 0.05f) / (min(value, it) + 0.05f) }
        }
        val best = if (score(p.text) >= 4.5f) p.text else listOf(p.text, c("#FFF9EF"), Color.BLACK).maxByOrNull { score(it) } ?: p.text
        // 對比夠的淺色字壓在水彩上：加一圈咖啡色細邊；對比不夠：加相反明暗的細邊
        val outline = when {
            score(best) < 4.5f -> if (luminance(best) > 0.5f) Color.BLACK else Color.WHITE
            Color.red(best) / 255f > 0.78f -> Color.argb(166, 0x68, 0x47, 0x2B)
            else -> null
        }
        return Ink(best, outline)
    }
}

val KeyboardStyle.isFoxLetter get() = theme.id == FoxLetter.ID

/** 整片鍵盤的底：深紫紙感（只用圖下面 80%，上面是山景） */
class FoxPaperDrawable(private val image: Bitmap) : Drawable() {
    private val paint = Paint(Paint.FILTER_BITMAP_FLAG)
    private val src = Rect(0, (image.height * 0.2f).toInt(), image.width, image.height)
    override fun draw(canvas: Canvas) = canvas.drawBitmap(image, src, bounds, paint)
    override fun setAlpha(alpha: Int) { paint.alpha = alpha }
    override fun setColorFilter(colorFilter: ColorFilter?) { paint.colorFilter = colorFilter }
    @Deprecated("Deprecated in Java")
    override fun getOpacity() = PixelFormat.OPAQUE
}

/** 工具列、選字列的底：深色膠囊，透一點紙的紋理 */
class FoxBarDrawable(private val image: Bitmap?, private val dp: Float, private val line: Int) : Drawable() {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    override fun draw(canvas: Canvas) {
        val r = RectF(bounds).apply { inset(4 * dp, 4 * dp) }
        if (r.width() <= 0 || r.height() <= 0) return
        val radius = r.height() / 2
        canvas.save()
        canvas.clipPath(Path().apply { addRoundRect(r, radius, radius, Path.Direction.CW) })
        paint.style = Paint.Style.FILL
        image?.let {
            canvas.drawBitmap(it, Rect((it.width * 0.2f).toInt(), (it.height * 0.3f).toInt(), (it.width * 0.8f).toInt(), (it.height * 0.9f).toInt()), r, paint)
        }
        paint.color = Color.argb(166, 0, 0, 0)
        canvas.drawRect(r, paint)
        canvas.restore()
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 0.65f * dp
        paint.color = Color.argb(77, Color.red(line), Color.green(line), Color.blue(line))
        canvas.drawRoundRect(r, radius, radius, paint)
    }
    override fun setAlpha(alpha: Int) {}
    override fun setColorFilter(colorFilter: ColorFilter?) {}
    @Deprecated("Deprecated in Java")
    override fun getOpacity() = PixelFormat.TRANSLUCENT
}

/** 設定裡的小預覽：一顆狐狸鍵帽 */
class FoxPreviewView(context: Context) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    override fun onDraw(canvas: Canvas) {
        FoxLetter.drawKey(context, canvas, RectF(0f, 0f, width.toFloat(), height.toFloat()), 0, KeyAction.Text(""), false, false, paint)
    }
}
