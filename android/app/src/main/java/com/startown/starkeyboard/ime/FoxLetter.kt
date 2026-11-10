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
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/** 設計圖鑑做成的主題（和 iPhone 版 Keyboard/ThemePacks.swift 一樣）。有圖集的要下載才能用，不用可以移除 */
class ThemeLook(
    val theme: KeyboardTheme, val emoji: String, val subtitle: String, val hasArt: Boolean,
    val shape: KeyShape, val finish: KeyFinish, val ink: Int, val spaceInk: Int, val hint: Int,
)

object ThemeLooks {
    private fun c(hex: String) = Color.parseColor(hex)

    private fun make(id: String, name: String, emoji: String, subtitle: String, bed: String, bar: String, text: String, accent: String, accentText: String,
                     shadow: String, dark: Boolean, ink: String, art: Boolean = true, shape: KeyShape = KeyShape.ROUNDED, finish: KeyFinish = KeyFinish.FLAT,
                     bedBottom: String = bed, key: String = bar, specialText: String = text, spaceInk: String = ink, hint: String = text) = ThemeLook(
        KeyboardTheme(id, name, c(bed), c(bedBottom), c(key), c(text), c(bar), c(specialText), c(accent), c(accentText), c(shadow), "", dark),
        emoji, subtitle, art, shape, finish, c(ink), c(spaceInk), c(hint))

    val all = listOf(
        make("persimmon", "柿子貓的茶屋", "🍊", "秋日水彩", "#F8E6C6", "#E9CB9C", "#51351F", "#D9793A", "#FFFFFF", "#C9A878", false, "#412C20", spaceInk = "#302E1D"),
        make("observatory", "小梟的月相室", "🦉", "秋日水彩", "#18243B", "#293850", "#F5E9CD", "#E3B566", "#171B31", "#0F1728", true, "#171B31", spaceInk = "#FFF4D9"),
        make("railway", "稻雀的末班車", "🌾", "秋日水彩", "#294544", "#365851", "#FFF0CF", "#E0A64B", "#332817", "#1C302F", true, "#332817", spaceInk = "#4C3323"),
        make("pool", "動物泳隊", "🏊", "孔版印刷", "#ACE1DC", "#1C5975", "#FFF3CE", "#F2743B", "#FFFFFF", "#115875", true, "#282335", hint = "#203735"),
        make("fern", "蕨影暗房", "🌿", "植物藍曬", "#0C3553", "#0C3352", "#E6F2FA", "#8FC1E3", "#0C3352", "#061F33", true, "#FFFFFF"),
        make("cat-outline", "貓咪描邊", "🐈", "線稿＋你的照片", "#2A2622", "#2A2622", "#FFFFFF", "#FFD48A", "#2A2622", "#000000", true, "#FFFFFF",
            art = false, shape = KeyShape.CAT_LINE, finish = KeyFinish.OUTLINE, bedBottom = "#1D1A17"),
    )

    fun named(id: String) = all.firstOrNull { it.theme.id == id }
}

val KeyboardStyle.themeLook get() = ThemeLooks.named(theme.id)
/** 按鍵是插畫（小狐狸和有圖集的主題） */
val KeyboardStyle.isIllustrated get() = isFoxLetter || themeLook?.hasArt == true

/** 主題圖要用才下載（和字體一樣，放在 GitHub Pages），不用可以移除 */
object ThemePacks {
    private const val BASE = "https://z3332111-cloud.github.io/StarKeyboard/theme-packs/"

    fun files(id: String): List<String> = when {
        id == FoxLetter.ID -> listOf("keycaps-watercolor-v2", "wide-keycaps-watercolor-v2", "background-watercolor-v2")
        ThemeLooks.named(id)?.hasArt == true -> listOf("theme-$id")
        else -> emptyList()
    }

    fun file(context: Context, name: String) = java.io.File(java.io.File(context.filesDir, "themepacks").apply { mkdirs() }, "$name.png")

    /** 不用下載，或已經下載好了 */
    fun isReady(context: Context, id: String) = files(id).all { file(context, it).exists() }

    /** 在背景下載，完成後在主執行緒回報 */
    fun download(context: Context, id: String, done: (Boolean) -> Unit) {
        val main = android.os.Handler(android.os.Looper.getMainLooper())
        Thread {
            val ok = runCatching {
                for (name in files(id)) {
                    val conn = java.net.URL("$BASE$name.png").openConnection() as java.net.HttpURLConnection
                    conn.connectTimeout = 15000; conn.readTimeout = 30000; conn.instanceFollowRedirects = true
                    require(conn.responseCode == 200)
                    val tmp = java.io.File(context.cacheDir, "$name.part")
                    conn.inputStream.use { input -> tmp.outputStream().use { input.copyTo(it) } }
                    val size = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeFile(tmp.path, size)
                    require(size.outWidth > 0)
                    val target = file(context, name)
                    target.delete()
                    require(tmp.renameTo(target))
                }
            }.isSuccess
            main.post { done(ok) }
        }.start()
    }

    fun remove(context: Context, id: String) {
        for (name in files(id)) file(context, name).delete()
    }
}

/**
 * 角色主題（插畫按鍵）的質感：照圖案的透明邊緣算出凹凸，把亮面和陰影畫進圖裡。
 * 換質感時整張圖集算一次，每顆鍵共用。和 iPhone 版 Keyboard/ArtFinish.swift、網站 sim.js 同一套算法。
 */
object ArtFinish {
    /** 插畫可以選的質感（線稿是畫框線，插畫用不到） */
    val choices = listOf(KeyFinish.FLAT, KeyFinish.PUFFY, KeyFinish.RAISED, KeyFinish.LIQUID, KeyFinish.METAL)

    private fun radius(f: KeyFinish) = when (f) {
        KeyFinish.PUFFY -> 18f
        KeyFinish.RAISED -> 9f
        else -> 7f
    }

    fun apply(src: Bitmap, f: KeyFinish): Bitmap {
        if (f == KeyFinish.FLAT || f !in choices) return src
        val w = src.width
        val h = src.height
        if (w <= 2 || h <= 2) return src
        val px = IntArray(w * h)
        src.getPixels(px, 0, w, 0, 0, w, h)
        val alpha = FloatArray(w * h) { ((px[it] ushr 24) and 0xFF) / 255f }
        val s = w / 768f
        val r1 = max(1, Math.round(radius(f) * s))
        val h1 = blur(blur(alpha, w, h, r1), w, h, r1)
        val big = f != KeyFinish.RAISED
        val r2 = max(1, Math.round(40 * s))
        val h2 = if (big) blur(blur(alpha, w, h, r2), w, h, r2) else h1
        val c = FloatArray(3)
        for (y in 0 until h) for (x in 0 until w) {
            val i = y * w + x
            val a = (px[i] ushr 24) and 0xFF
            if (a == 0) continue
            c[0] = ((px[i] shr 16) and 0xFF) / 255f
            c[1] = ((px[i] shr 8) and 0xFF) / 255f
            c[2] = (px[i] and 0xFF) / 255f
            pixel(c, shade(h1, w, h, x, y, r1), if (big) shade(h2, w, h, x, y, r2) else 0f, f)
            px[i] = (a shl 24) or (Math.round(c[0] * 255) shl 16) or (Math.round(c[1] * 255) shl 8) or Math.round(c[2] * 255)
        }
        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        out.setPixels(px, 0, w, 0, 0, w, h)
        return out
    }

    /** 正數往白、負數往黑 */
    private fun light(v: Float, t: Float) = if (t >= 0) v + (1 - v) * t else v * (1 + t)

    private fun pixel(c: FloatArray, e1: Float, e2: Float, f: KeyFinish) {
        fun all(t: Float) { for (k in 0..2) c[k] = light(c[k], t) }
        fun lum() = 0.3f * c[0] + 0.59f * c[1] + 0.11f * c[2]
        when (f) {
            KeyFinish.RAISED -> all(if (e1 > 0) e1 * 0.6f else e1 * 0.55f)
            KeyFinish.PUFFY -> {
                all(if (e1 > 0) e1 * 0.5f else e1 * 0.45f)
                all(max(e2, 0f).pow(1.5f) * 0.25f)
            }
            KeyFinish.LIQUID -> {
                all(if (e1 > 0) e1 * 0.35f else e1 * 0.35f)
                all(max(e1, 0f).pow(2) * 0.9f)
                all(max(e2, 0f).pow(1.5f) * 0.55f)
                val l = lum()
                for (k in 0..2) c[k] = l + (c[k] - l) * 1.18f
            }
            KeyFinish.METAL -> {
                val l = lum()
                for (k in 0..2) c[k] += (l - c[k]) * 0.6f
                val env = 0.45f + 0.9f * (0.5f + 0.5f * kotlin.math.sin(e2 * 4 + 0.6f))
                for (k in 0..2) c[k] *= env
                if (e1 < 0) all(e1 * 0.5f)
                all(max(e1, 0f).pow(2) * 1f)
            }
            else -> {}
        }
        for (k in 0..2) c[k] = c[k].coerceIn(0f, 1f)
    }

    /** 光從左上來：邊緣朝光的一面是正（亮），背光是負（暗），約 -1～1 */
    private fun shade(m: FloatArray, w: Int, h: Int, x: Int, y: Int, r: Int): Float {
        val gx = (m[y * w + min(x + 1, w - 1)] - m[y * w + max(x - 1, 0)]) / 2
        val gy = (m[min(y + 1, h - 1) * w + x] - m[max(y - 1, 0) * w + x]) / 2
        return ((0.45f * gx + gy) * (3 * r)).coerceIn(-1f, 1f)
    }

    /** 方框模糊（先橫再直，超出邊界用邊上的值） */
    private fun blur(src: FloatArray, w: Int, h: Int, r: Int): FloatArray {
        val n = (2 * r + 1).toFloat()
        val tmp = FloatArray(w * h)
        for (y in 0 until h) {
            val row = y * w
            var sum = 0f
            for (k in -r..r) sum += src[row + k.coerceIn(0, w - 1)]
            for (x in 0 until w) {
                tmp[row + x] = sum / n
                sum += src[row + min(x + r + 1, w - 1)] - src[row + max(x - r, 0)]
            }
        }
        val out = FloatArray(w * h)
        for (x in 0 until w) {
            var sum = 0f
            for (k in -r..r) sum += tmp[k.coerceIn(0, h - 1) * w + x]
            for (y in 0 until h) {
                out[y * w + x] = sum / n
                sum += tmp[min(y + r + 1, h - 1) * w + x] - tmp[max(y - r, 0) * w + x]
            }
        }
        return out
    }
}

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
        ThemeLooks.named(style.theme.id)?.let { style.copy(shape = it.shape, finish = it.finish) }
            ?: if (style.theme.id == ID) style.copy(shape = KeyShape.ROUNDED, finish = KeyFinish.FLAT) else style

    // ===== 圖集：只解一次，每顆鍵共用 =====

    private val images = HashMap<String, Bitmap?>()

    /** 插畫按鍵的質感；換了就把按鍵圖重算（背景紙不加質感） */
    var finish: KeyFinish = KeyFinish.FLAT
        set(v) {
            if (v == field) return
            field = v
            images.keys.retainAll(setOf("background-watercolor-v2"))
        }

    private fun image(context: Context, name: String): Bitmap? {
        images[name]?.let { return it }
        // 換主題就放掉前一款的圖，記憶體裡只留正在用的
        if (name.startsWith("theme-") || images.keys.any { it.startsWith("theme-") }) images.clear()
        val file = ThemePacks.file(context, name)
        val plain = if (file.exists()) runCatching { BitmapFactory.decodeFile(file.path) }.getOrNull() else null
        val bitmap = if (plain != null && name != "background-watercolor-v2" && finish != KeyFinish.FLAT)
            runCatching { ArtFinish.apply(plain, finish) }.getOrDefault(plain) else plain
        if (bitmap != null) images[name] = bitmap
        return bitmap
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
    fun frame(key: RectF, gapScale: Float, shapeScale: Float, dp: Float, compact: Boolean = false): RectF {
        val w = key.width() / dp
        val h = key.height() / dp
        if (w <= 6 || h <= 6) return RectF()
        val gap = gapScale.coerceIn(0.3f, 1.8f)
        val baseW = max(5f, w - 2 * gap)
        val baseH = max(5f, h - 4 * gap)
        var width: Float
        var height: Float
        if (w > h * 1.35f) {
            // 寬鍵的中間會延展，不會變形；不超出按鍵，才不會蓋到旁邊
            val factor = (shapeScale / 1.15f).coerceIn(0.8f, 1.12f)
            width = min(w - 1.4f, baseW * factor)
            height = min(h - 1.4f, baseH * factor)
        } else {
            // 一般的鍵：照原圖的比例（圓的就是圓的），按鍵再瘦也不拉高；「造型大小」整顆等比放大縮小，可以超出按鍵一點
            val part = if (compact) 0.78f else 1f
            width = baseW
            height = min(baseH, width * part)
            if (width > height / part) width = height / part
            val factor = (shapeScale / 1.15f).coerceIn(0.75f, 1.4f)
            width *= factor
            height *= factor
        }
        width *= dp
        height *= dp
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

    // ===== 設計圖鑑的主題：圖集上面一排三顆鍵帽（256×256）、下面一條寬鍵（768×192） =====

    fun drawPackCap(context: Context, canvas: Canvas, frame: RectF, index: Int, look: ThemeLook, paint: Paint) {
        val image = image(context, "theme-" + look.theme.id) ?: return
        val position = max(0, index)
        val cap = (position + position / 4) % 3
        val cellW = image.width / 3
        canvas.drawBitmap(image, Rect(cap * cellW, 0, (cap + 1) * cellW, image.height * 256 / 448), frame, paint)
    }

    /** 寬鍵：兩端的圖案不變形，中間延展 */
    fun drawPackWide(context: Context, canvas: Canvas, frame: RectF, look: ThemeLook, paint: Paint) {
        val image = image(context, "theme-" + look.theme.id) ?: return
        val iw = image.width.toFloat()
        val top = image.height * 256 / 448
        val natural = min(frame.height() * 4, frame.width() / 0.45f)
        val stretch = (frame.width() - natural * 0.45f) / 2
        var x = frame.left
        for (i in 0 until 5) {
            val fraction = paperCuts[i + 1] - paperCuts[i]
            val width = if (i == 1 || i == 3) stretch else natural * fraction
            val src = Rect((paperCuts[i] * iw).toInt(), top, (paperCuts[i + 1] * iw).toInt(), image.height)
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
