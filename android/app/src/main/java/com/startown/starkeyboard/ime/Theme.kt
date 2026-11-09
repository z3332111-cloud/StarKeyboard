package com.startown.starkeyboard.ime

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.Path
import android.graphics.RectF
import java.io.File

/** 和 iPhone 版 Keyboard/Theme.swift 一樣的主題 */
data class KeyboardTheme(
    val id: String,
    val name: String,
    val top: Int,
    val bottom: Int,
    val key: Int,
    val keyText: Int,
    val special: Int,
    val specialText: Int,
    val accent: Int,
    val accentText: Int,
    val shadow: Int,
    val decoration: String,
    val dark: Boolean,
) {
    companion object {
        private fun c(hex: String) = Color.parseColor(hex)

        val all = listOf(
            KeyboardTheme("strawberry", "草莓牛奶", c("#FFE4EC"), c("#FFD0DE"), c("#FFFFFF"), c("#8A4B5C"), c("#FFC2D4"), c("#7A3045"), c("#FF7FA6"), c("#FFFFFF"), c("#E8A2B6"), "🍓", false),
            KeyboardTheme("mint", "薄荷蘇打", c("#DDF7EF"), c("#C5EFE3"), c("#FFFFFF"), c("#2F6B5E"), c("#A7E3D2"), c("#2F6B5E"), c("#3CC5A0"), c("#FFFFFF"), c("#9FD8C7"), "🌿", false),
            KeyboardTheme("milktea", "奶茶布丁", c("#F3E6D6"), c("#E9D5BD"), c("#FFF8EE"), c("#6B4A33"), c("#D9B994"), c("#5A3B24"), c("#B9835A"), c("#FFFFFF"), c("#CBAE8C"), "🍮", false),
            KeyboardTheme("lavender", "薰衣草", c("#ECE4FF"), c("#DCD0FF"), c("#FFFFFF"), c("#5B4B8A"), c("#C7B8F5"), c("#4A3B78"), c("#8D74E8"), c("#FFFFFF"), c("#B9A9EC"), "💜", false),
            KeyboardTheme("lemon", "檸檬小雞", c("#FFF6CC"), c("#FFEC9E"), c("#FFFFFF"), c("#7A5B12"), c("#FFDD6B"), c("#6B4E0A"), c("#FFA928"), c("#FFFFFF"), c("#E9CB6A"), "🐥", false),
            KeyboardTheme("night", "星空夜", c("#1E2245"), c("#2B2F63"), c("#3A3F7A"), c("#F3F0FF"), c("#2A2E5E"), c("#CFCBFF"), c("#FFD65C"), c("#2B2F63"), c("#14173A"), "⭐", true),
            KeyboardTheme("sakura", "櫻花", c("#FDE8EF"), c("#F9D5E2"), c("#FFFFFF"), c("#9B4D6B"), c("#F6C1D4"), c("#8A3A5A"), c("#F08BB0"), c("#FFFFFF"), c("#E8B0C4"), "🌸", false),
            KeyboardTheme("peach", "蜜桃", c("#FFE9DC"), c("#FFD8C4"), c("#FFFFFF"), c("#8A5040"), c("#FFC8AD"), c("#7A4030"), c("#FF9A76"), c("#FFFFFF"), c("#ECB59C"), "🍑", false),
            KeyboardTheme("cream", "奶油", c("#FFFAF0"), c("#FFF1D9"), c("#FFFFFF"), c("#7A6340"), c("#F7E2B8"), c("#6B5430"), c("#F2B94B"), c("#FFFFFF"), c("#E6D2A6"), "🧈", false),
            KeyboardTheme("matcha", "抹茶", c("#E9F3DC"), c("#D8EAC4"), c("#FFFEF8"), c("#4A6332"), c("#C6DFA9"), c("#3E5629"), c("#8CBF5A"), c("#FFFFFF"), c("#B4CF98"), "🍵", false),
            KeyboardTheme("sky", "天空", c("#E2F1FF"), c("#CFE6FF"), c("#FFFFFF"), c("#3D5F8A"), c("#B9D8FB"), c("#2F4F78"), c("#5AA9F0"), c("#FFFFFF"), c("#A9C8EA"), "☁️", false),
            KeyboardTheme("ocean", "海洋", c("#D8F0FB"), c("#BFE4F6"), c("#F7FDFF"), c("#2D5F7A"), c("#A6D8EF"), c("#245570"), c("#3FB2D8"), c("#FFFFFF"), c("#96C8DE"), "🐟", false),
            KeyboardTheme("grape", "葡萄", c("#EFE2F7"), c("#E2CDF2"), c("#FFFFFF"), c("#6A3F86"), c("#D6B8EC"), c("#5A2F78"), c("#A86AD6"), c("#FFFFFF"), c("#C8A8E0"), "🍇", false),
            KeyboardTheme("aurora", "夢幻極光", c("#FFE7EF"), c("#E5E0FF"), c("#FFFFFF"), c("#5D4F8A"), c("#E3D6FF"), c("#4A3B78"), c("#FF9EC4"), c("#FFFFFF"), c("#CBBFEB"), "🌈", false),
            KeyboardTheme("cocoa", "可可", c("#3A2A26"), c("#2E211E"), c("#5A443D"), c("#F8EBE2"), c("#46342F"), c("#E8D5C8"), c("#F0A77A"), c("#3A2A26"), c("#1F1513"), "🍫", true),
            KeyboardTheme("neon", "電玩霓虹", c("#1C1640"), c("#251C52"), c("#362A73"), c("#F0EAFF"), c("#2A2160"), c("#CFC4FF"), c("#FF7AD9"), c("#1C1640"), c("#120D2E"), "🎮", true),
            KeyboardTheme("light", "經典淺色", c("#D3D6DC"), c("#CDD0D6"), c("#FFFFFF"), c("#000000"), c("#ABB0BA"), c("#000000"), c("#2F7BF6"), c("#FFFFFF"), c("#8E9196"), "", false),
            KeyboardTheme("dark", "經典深色", c("#2B2B2D"), c("#232325"), c("#6B6B6E"), c("#FFFFFF"), c("#474749"), c("#FFFFFF"), c("#2F7BF6"), c("#FFFFFF"), c("#111111"), "", true),
        )

        fun named(id: String): KeyboardTheme = if (id == FoxLetter.ID) FoxLetter.theme
            else ThemeLooks.named(id)?.theme ?: all.firstOrNull { it.id == id } ?: all[0]

        /** 自訂配色用的色票：(色相, 濃淡)，和 iPhone 版一樣 */
        val swatches = listOf(
            0.95f to 0.45f, 0.97f to 0.65f, 0.0f to 0.7f, 0.03f to 0.5f, 0.08f to 0.7f, 0.07f to 0.35f, 0.13f to 0.7f,
            0.12f to 0.3f, 0.24f to 0.55f, 0.36f to 0.6f, 0.42f to 0.45f, 0.49f to 0.6f, 0.56f to 0.5f, 0.61f to 0.65f,
            0.65f to 0.8f, 0.72f to 0.38f, 0.75f to 0.6f, 0.83f to 0.4f, 0.88f to 0.6f, 0.0f to 0.25f, 0.6f to 0.06f,
        )

        /** 色票上看到的顏色 */
        fun swatchColor(hue: Float, saturation: Float) = Color.HSVToColor(floatArrayOf(hue.coerceIn(0f, 1f) * 360f, saturation.coerceIn(0f, 1f), 0.95f))

        /** 自訂配色：主色（按鍵的字、背景上半）＋第二色（功能鍵、強調色、背景下半），hue2 < 0 就全部用主色 */
        fun custom(hue: Float, saturation: Float, dark: Boolean, hue2: Float = -1f, saturation2: Float = 0.55f): KeyboardTheme {
            val h = hue.coerceIn(0f, 1f) * 360f
            val s = saturation.coerceIn(0.05f, 1f)
            val h2 = if (hue2 < 0) h else hue2.coerceIn(0f, 1f) * 360f
            val s2 = if (hue2 < 0) s else saturation2.coerceIn(0.05f, 1f)
            fun hsb(sat: Float, bri: Float) = Color.HSVToColor(floatArrayOf(h, sat.coerceIn(0f, 1f), bri.coerceIn(0f, 1f)))
            fun hsb2(sat: Float, bri: Float) = Color.HSVToColor(floatArrayOf(h2, sat.coerceIn(0f, 1f), bri.coerceIn(0f, 1f)))
            return if (dark) KeyboardTheme("custom", "自訂", hsb(s * 0.5f, 0.22f), hsb2(s2 * 0.5f, 0.28f), hsb(s * 0.45f, 0.40f), hsb(0.06f, 0.98f),
                hsb2(s2 * 0.5f, 0.30f), hsb2(0.2f, 0.88f), hsb2(s2 * 0.55f, 0.95f), hsb2(s2 * 0.5f, 0.22f), hsb(s * 0.5f, 0.12f), "🎨", true)
            else KeyboardTheme("custom", "自訂", hsb(s * 0.15f, 1f), hsb2(s2 * 0.25f, 0.97f), Color.WHITE, hsb(s * 0.6f + 0.2f, 0.45f),
                hsb2(s2 * 0.35f, 0.95f), hsb2(s2 * 0.7f, 0.38f), hsb2(s2 * 0.6f, 0.9f), Color.WHITE, hsb(s * 0.4f, 0.82f), "🎨", false)
        }
    }
}

fun Int.withAlpha(a: Float): Int = Color.argb((Color.alpha(this) * a.coerceIn(0f, 1f)).toInt(), Color.red(this), Color.green(this), Color.blue(this))

/** 按鍵造型（和 iPhone 版 KeyShape 一樣的算法，單位是 dp 換成的像素） */
enum class KeyShape(val title: String, private val artId: String? = null) {
    ROUNDED("圓角"), JELLY("果凍"), CAT_EAR("貓耳"), CLOUD("雲朵"), BUNNY("兔兔"), PUPPY("狗狗"), PUDDING("布丁"), JELLYFISH("水母"), FLAME("火焰"), DROPLET("水滴"), DUCK("鴨鴨"),
    // 下面這些用線條資料畫（tools/key_shapes.txt → KeyShapeArt.kt）
    CAT_FACE("貓咪", "catFace"), BEAR("熊熊", "bear"), PAW("肉球", "paw"), CLOUD_PUFF("棉花雲", "cloudPuff"), PIXEL("像素", "pixel"), PIXEL_HEART("像素心", "pixelHeart"),
    PUZZLE("拼圖", "puzzle"), BOOK("書本", "book"), BUTTERFLY("蝴蝶", "butterfly"),
    STRAWBERRY("草莓", "strawberry"), FLOWER("櫻花", "flower"), MOON("月亮", "moon"), STAR("星星", "star"), HEART("愛心", "heart"), LATTE("拉花咖啡", "latte"), CAT_LINE("貓咪探頭", "catLine"), CIRCLE("圓形", "circle");

    val art: KeyShapeArt? get() = artId?.let { KeyShapeArt.shapes[it] }

    /** 小裝飾的不透明度（寬鍵左邊的小圖示一定看得到） */
    fun detailOpacity(r: RectF? = null): Float {
        val a = art ?: return if (this == PUDDING || this == DUCK) 0.85f else 0.4f
        return if (r != null && isWide(r)) maxOf(a.detailAlpha, 0.6f) else a.detailAlpha
    }

    val isSoftShape: Boolean get() = when (this) {
        BUNNY, PUPPY, PUDDING, JELLYFISH, FLAME, DROPLET, DUCK -> true
        else -> art != null
    }

    // 會自己拉長的造型（貓咪探頭）寬鍵也畫原本的樣子，不換成膠囊
    /** 程式畫的造型本來的高÷寬；圓角就是長方形的鍵，線條造型自己有比例 */
    private val naturalAspect: Float?
        get() = when (this) {
            JELLY -> 1f
            CAT_EAR -> 1.1f
            CLOUD -> 0.95f
            BUNNY -> 1.25f
            PUPPY -> 1.1f
            PUDDING -> 1.1f
            JELLYFISH -> 1.15f
            FLAME -> 1.2f
            DROPLET -> 1.2f
            DUCK -> 1.05f
            else -> null
        }

    /** 造型畫在按鍵的哪裡：保持比例置中，按鍵再瘦也不拉長（空白鍵這種寬鍵照舊）；scale 是「造型大小」 */
    fun naturalRect(r: RectF, scale: Float): RectF {
        val a = naturalAspect
        if (a == null || r.width() > r.height() * 1.35f) return RectF(r)
        var w = r.width()
        var h = minOf(r.height(), w * a)
        if (w * a > r.height()) { h = r.height(); w = h / a }
        w *= scale
        h *= scale
        return RectF(r.centerX() - w / 2, r.centerY() - h / 2, r.centerX() + w / 2, r.centerY() + h / 2)
    }

    private fun isWide(r: RectF) = isSoftShape && art?.stretch != true && r.width() > r.height() * 1.65f

    /** 只畫線的部分（尾巴、鬍鬚） */
    fun linesPath(r: RectF): Path? = if (isWide(r)) null else art?.linesPath(r)
    private fun wideBody(r: RectF) = RectF(r).apply { inset(0f, r.height() * 0.08f) }
    private fun badgeRect(r: RectF): RectF {
        val size = r.height() * 0.54f
        val left = r.left + r.height() * 0.17f
        return RectF(left, r.centerY() - size / 2, left + size, r.centerY() + size / 2)
    }

    private fun earSize(r: RectF, dp: Float) = minOf(r.width() * 0.24f, r.height() * 0.24f, 9 * dp)
    private fun bumpSize(r: RectF, dp: Float) = minOf(r.height() * 0.16f, 6 * dp)

    /** 按鍵本體（字畫在這裡面） */
    fun bodyRect(r: RectF, dp: Float): RectF {
        if (isWide(r)) return RectF(r.left + r.height() * 0.82f, r.top + r.height() * 0.15f,
            r.right - r.height() * 0.14f, r.top + r.height() * 0.85f)
        art?.let { return it.bodyRect(r) }
        return when (this) {
        CAT_EAR -> RectF(r.left, r.top + earSize(r, dp) * 0.6f, r.right, r.bottom)
        CLOUD -> RectF(r.left, r.top + bumpSize(r, dp), r.right, r.bottom)
        BUNNY -> RectF(r.left + r.width() * 0.08f, r.top + r.height() * 0.32f, r.left + r.width() * 0.92f, r.top + r.height() * 0.9f)
        PUPPY -> RectF(r.left + r.width() * 0.2f, r.top + r.height() * 0.24f, r.left + r.width() * 0.8f, r.top + r.height() * 0.88f)
        PUDDING -> RectF(r.left + r.width() * 0.12f, r.top + r.height() * 0.32f, r.left + r.width() * 0.88f, r.top + r.height() * 0.87f)
        JELLYFISH -> RectF(r.left + r.width() * 0.09f, r.top + r.height() * 0.19f, r.left + r.width() * 0.91f, r.top + r.height() * 0.73f)
        FLAME -> RectF(r.left + r.width() * 0.13f, r.top + r.height() * 0.35f, r.left + r.width() * 0.87f, r.top + r.height() * 0.9f)
        DROPLET -> RectF(r.left + r.width() * 0.13f, r.top + r.height() * 0.34f, r.left + r.width() * 0.87f, r.top + r.height() * 0.87f)
        DUCK -> RectF(r.left + r.width() * 0.14f, r.top + r.height() * 0.40f, r.left + r.width() * 0.84f, r.top + r.height() * 0.90f)
        else -> RectF(r)
        }
    }

    fun detailPath(r: RectF, dp: Float): Path {
        if (isWide(r)) return path(badgeRect(r), dp)
        art?.let { return it.detailPath(r) }
        return Path().apply {
            when (this@KeyShape) {
            BUNNY -> {
                fun x(v: Float) = r.left + r.width() * v
                fun y(v: Float) = r.top + r.height() * v
                moveTo(x(0.22f), y(0.11f))
                cubicTo(x(0.18f), y(0.14f), x(0.24f), y(0.29f), x(0.28f), y(0.3f))
                cubicTo(x(0.32f), y(0.3f), x(0.27f), y(0.1f), x(0.22f), y(0.11f))
                close()
                moveTo(x(0.78f), y(0.11f))
                cubicTo(x(0.73f), y(0.1f), x(0.68f), y(0.3f), x(0.72f), y(0.3f))
                cubicTo(x(0.76f), y(0.29f), x(0.82f), y(0.14f), x(0.78f), y(0.11f))
                close()
            }
            PUPPY -> {
                fun x(v: Float) = r.left + r.width() * v
                fun y(v: Float) = r.top + r.height() * v
                moveTo(x(0.17f), y(0.27f))
                cubicTo(x(0.1f), y(0.28f), x(0.06f), y(0.49f), x(0.12f), y(0.57f))
                cubicTo(x(0.17f), y(0.61f), x(0.21f), y(0.48f), x(0.22f), y(0.37f))
                quadTo(x(0.23f), y(0.25f), x(0.17f), y(0.27f))
                close()
                moveTo(x(0.83f), y(0.27f))
                quadTo(x(0.77f), y(0.25f), x(0.78f), y(0.37f))
                cubicTo(x(0.79f), y(0.48f), x(0.83f), y(0.61f), x(0.88f), y(0.57f))
                cubicTo(x(0.94f), y(0.49f), x(0.9f), y(0.28f), x(0.83f), y(0.27f))
                close()
            }
            PUDDING -> {
                fun x(v: Float) = r.left + r.width() * v
                fun y(v: Float) = r.top + r.height() * v
                moveTo(x(0.24f), y(0.14f))
                quadTo(x(0.5f), y(0.08f), x(0.76f), y(0.14f))
                quadTo(x(0.83f), y(0.16f), x(0.85f), y(0.29f))
                cubicTo(x(0.77f), y(0.35f), x(0.69f), y(0.24f), x(0.6f), y(0.29f))
                cubicTo(x(0.43f), y(0.38f), x(0.34f), y(0.27f), x(0.15f), y(0.3f))
                quadTo(x(0.17f), y(0.16f), x(0.24f), y(0.14f))
                close()
            }
            JELLYFISH -> {
                fun x(v: Float) = r.left + r.width() * v
                fun y(v: Float) = r.top + r.height() * v
                moveTo(x(0.22f), y(0.26f))
                cubicTo(x(0.32f), y(0.11f), x(0.65f), y(0.1f), x(0.78f), y(0.26f))
                cubicTo(x(0.56f), y(0.2f), x(0.43f), y(0.2f), x(0.22f), y(0.26f))
                close()
            }
            FLAME -> {
                fun x(v: Float) = r.left + r.width() * v
                fun y(v: Float) = r.top + r.height() * v
                moveTo(x(0.18f), y(0.59f))
                cubicTo(x(0.11f), y(0.67f), x(0.14f), y(0.8f), x(0.23f), y(0.84f))
                quadTo(x(0.27f), y(0.84f), x(0.23f), y(0.78f))
                quadTo(x(0.17f), y(0.7f), x(0.18f), y(0.59f))
                close()
                moveTo(x(0.84f), y(0.61f))
                quadTo(x(0.85f), y(0.73f), x(0.78f), y(0.81f))
                quadTo(x(0.75f), y(0.86f), x(0.8f), y(0.84f))
                cubicTo(x(0.9f), y(0.79f), x(0.9f), y(0.67f), x(0.84f), y(0.61f))
                close()
            }
            DROPLET -> {
                fun x(v: Float) = r.left + r.width() * v
                fun y(v: Float) = r.top + r.height() * v
                moveTo(x(0.24f), y(0.4f))
                cubicTo(x(0.13f), y(0.47f), x(0.13f), y(0.66f), x(0.21f), y(0.72f))
                quadTo(x(0.25f), y(0.74f), x(0.23f), y(0.67f))
                cubicTo(x(0.19f), y(0.55f), x(0.22f), y(0.47f), x(0.27f), y(0.42f))
                quadTo(x(0.29f), y(0.38f), x(0.24f), y(0.4f))
                close()
            }
            DUCK -> {
                fun x(v: Float) = r.left + r.width() * v
                fun y(v: Float) = r.top + r.height() * v
                moveTo(x(0.78f), y(0.26f))
                quadTo(x(0.96f), y(0.25f), x(0.97f), y(0.31f))
                quadTo(x(0.96f), y(0.36f), x(0.79f), y(0.36f))
                quadTo(x(0.74f), y(0.31f), x(0.78f), y(0.26f))
                close()
                moveTo(x(0.64f), y(0.22f))
                cubicTo(x(0.64f), y(0.19f), x(0.7f), y(0.19f), x(0.7f), y(0.22f))
                cubicTo(x(0.7f), y(0.25f), x(0.64f), y(0.25f), x(0.64f), y(0.22f))
                close()
            }
            else -> Unit
            }
        }
    }

    fun detailColor(theme: KeyboardTheme): Int = art?.detailColor(theme) ?: when (this) {
        PUDDING -> Color.rgb(if (theme.dark) 215 else 168, if (theme.dark) 161 else 102, if (theme.dark) 95 else 53)
        FLAME -> if (theme.dark) Color.rgb(255, 212, 107) else Color.rgb(237, 145, 74)
        DROPLET -> if (theme.dark) Color.rgb(184, 239, 255) else Color.rgb(74, 173, 213)
        DUCK -> if (theme.dark) Color.rgb(255, 210, 118) else Color.rgb(215, 138, 50)
        else -> theme.accent
    }

    fun path(r: RectF, dp: Float): Path {
        if (isWide(r)) {
            val body = wideBody(r)
            return Path().apply { addRoundRect(body, body.height() * 0.36f, body.height() * 0.36f, Path.Direction.CW) }
        }
        val body = bodyRect(r, dp)
        art?.let { return it.path(r) }
        val path = Path()
        val minSide = minOf(body.width(), body.height())
        when (this) {
            ROUNDED -> path.addRoundRect(body, minOf(7 * dp, body.height() * 0.22f), minOf(7 * dp, body.height() * 0.22f), Path.Direction.CW)
            JELLY -> path.addRoundRect(body, minSide * 0.42f, minSide * 0.42f, Path.Direction.CW)
            CAT_EAR -> {
                path.addRoundRect(body, minSide * 0.34f, minSide * 0.34f, Path.Direction.CW)
                val ear = earSize(r, dp)
                val left = Path().apply {
                    moveTo(body.left + ear * 0.2f, body.top + ear * 1.1f)
                    lineTo(body.left + ear * 0.45f, r.top)
                    lineTo(body.left + ear * 1.7f, body.top + ear * 0.35f)
                    close()
                }
                val right = Path().apply {
                    moveTo(body.right - ear * 1.7f, body.top + ear * 0.35f)
                    lineTo(body.right - ear * 0.45f, r.top)
                    lineTo(body.right - ear * 0.2f, body.top + ear * 1.1f)
                    close()
                }
                path.op(left, Path.Op.UNION)
                path.op(right, Path.Op.UNION)
            }
            CLOUD -> {
                path.addRoundRect(body, minSide * 0.38f, minSide * 0.38f, Path.Direction.CW)
                val b = bumpSize(r, dp)
                val count = maxOf(2, (body.width() / (20 * dp)).toInt())
                val step = body.width() / (count + 1)
                for (i in 1..count) {
                    val circle = Path().apply { addCircle(body.left + step * i, body.top + b * 0.5f, b * 1.5f, Path.Direction.CW) }
                    path.op(circle, Path.Op.UNION)
                }
            }
            BUNNY -> {
                fun x(v: Float) = r.left + r.width() * v
                fun y(v: Float) = r.top + r.height() * v
                path.moveTo(x(0.2f), y(0.32f))
                path.cubicTo(x(0.13f), y(0.15f), x(0.13f), y(0.03f), x(0.23f), y(0.03f))
                path.cubicTo(x(0.33f), y(0.03f), x(0.34f), y(0.19f), x(0.37f), y(0.28f))
                path.quadTo(x(0.5f), y(0.24f), x(0.63f), y(0.28f))
                path.cubicTo(x(0.66f), y(0.19f), x(0.67f), y(0.03f), x(0.77f), y(0.03f))
                path.cubicTo(x(0.87f), y(0.03f), x(0.87f), y(0.15f), x(0.8f), y(0.32f))
                path.cubicTo(x(0.96f), y(0.37f), x(0.98f), y(0.51f), x(0.97f), y(0.67f))
                path.cubicTo(x(0.97f), y(0.91f), x(0.83f), y(0.97f), x(0.5f), y(0.97f))
                path.cubicTo(x(0.17f), y(0.97f), x(0.03f), y(0.91f), x(0.03f), y(0.67f))
                path.cubicTo(x(0.02f), y(0.51f), x(0.04f), y(0.37f), x(0.2f), y(0.32f))
                path.close()
            }
            PUPPY -> {
                fun x(v: Float) = r.left + r.width() * v
                fun y(v: Float) = r.top + r.height() * v
                path.moveTo(x(0.24f), y(0.21f))
                path.cubicTo(x(0.35f), y(0.09f), x(0.66f), y(0.09f), x(0.77f), y(0.21f))
                path.cubicTo(x(0.9f), y(0.16f), x(0.96f), y(0.25f), x(0.98f), y(0.39f))
                path.cubicTo(x(1.0f), y(0.55f), x(0.95f), y(0.69f), x(0.86f), y(0.67f))
                path.lineTo(x(0.83f), y(0.66f))
                path.cubicTo(x(0.82f), y(0.88f), x(0.73f), y(0.96f), x(0.5f), y(0.96f))
                path.cubicTo(x(0.27f), y(0.96f), x(0.18f), y(0.88f), x(0.17f), y(0.66f))
                path.lineTo(x(0.14f), y(0.67f))
                path.cubicTo(x(0.05f), y(0.69f), x(0.0f), y(0.55f), x(0.02f), y(0.39f))
                path.cubicTo(x(0.04f), y(0.25f), x(0.1f), y(0.16f), x(0.24f), y(0.21f))
                path.close()
            }
            PUDDING -> {
                fun x(v: Float) = r.left + r.width() * v
                fun y(v: Float) = r.top + r.height() * v
                path.moveTo(x(0.24f), y(0.13f))
                path.quadTo(x(0.5f), y(0.06f), x(0.76f), y(0.13f))
                path.cubicTo(x(0.86f), y(0.16f), x(0.86f), y(0.28f), x(0.89f), y(0.45f))
                path.lineTo(x(0.96f), y(0.77f))
                path.cubicTo(x(1.0f), y(0.94f), x(0.79f), y(0.97f), x(0.5f), y(0.97f))
                path.cubicTo(x(0.21f), y(0.97f), x(0.0f), y(0.94f), x(0.04f), y(0.77f))
                path.lineTo(x(0.11f), y(0.45f))
                path.cubicTo(x(0.14f), y(0.28f), x(0.14f), y(0.16f), x(0.24f), y(0.13f))
                path.close()
            }
            JELLYFISH -> {
                fun x(v: Float) = r.left + r.width() * v
                fun y(v: Float) = r.top + r.height() * v
                path.moveTo(x(0.07f), y(0.67f))
                path.cubicTo(x(0.03f), y(0.35f), x(0.19f), y(0.08f), x(0.5f), y(0.08f))
                path.cubicTo(x(0.81f), y(0.08f), x(0.97f), y(0.35f), x(0.93f), y(0.67f))
                path.quadTo(x(0.94f), y(0.77f), x(0.82f), y(0.77f))
                path.cubicTo(x(0.82f), y(0.83f), x(0.89f), y(0.89f), x(0.83f), y(0.94f))
                path.cubicTo(x(0.74f), y(1.0f), x(0.69f), y(0.88f), x(0.69f), y(0.79f))
                path.lineTo(x(0.58f), y(0.8f))
                path.cubicTo(x(0.57f), y(0.88f), x(0.6f), y(0.98f), x(0.5f), y(0.98f))
                path.cubicTo(x(0.4f), y(0.98f), x(0.43f), y(0.88f), x(0.42f), y(0.8f))
                path.lineTo(x(0.31f), y(0.79f))
                path.cubicTo(x(0.31f), y(0.88f), x(0.26f), y(1.0f), x(0.17f), y(0.94f))
                path.cubicTo(x(0.11f), y(0.89f), x(0.18f), y(0.83f), x(0.18f), y(0.77f))
                path.quadTo(x(0.06f), y(0.77f), x(0.07f), y(0.67f))
                path.close()
            }
            FLAME -> {
                fun x(v: Float) = r.left + r.width() * v
                fun y(v: Float) = r.top + r.height() * v
                path.moveTo(x(0.6f), y(0.05f))
                path.cubicTo(x(0.65f), y(0.04f), x(0.63f), y(0.17f), x(0.7f), y(0.23f))
                path.cubicTo(x(0.77f), y(0.31f), x(0.81f), y(0.34f), x(0.82f), y(0.43f))
                path.quadTo(x(0.9f), y(0.32f), x(0.92f), y(0.41f))
                path.cubicTo(x(1.0f), y(0.63f), x(0.97f), y(0.81f), x(0.83f), y(0.9f))
                path.cubicTo(x(0.68f), y(1.0f), x(0.31f), y(1.0f), x(0.16f), y(0.9f))
                path.cubicTo(x(0.02f), y(0.81f), x(0.0f), y(0.63f), x(0.09f), y(0.43f))
                path.quadTo(x(0.13f), y(0.35f), x(0.16f), y(0.43f))
                path.quadTo(x(0.19f), y(0.48f), x(0.24f), y(0.48f))
                path.cubicTo(x(0.37f), y(0.47f), x(0.35f), y(0.21f), x(0.47f), y(0.16f))
                path.quadTo(x(0.54f), y(0.13f), x(0.6f), y(0.05f))
                path.close()
            }
            DROPLET -> {
                fun x(v: Float) = r.left + r.width() * v
                fun y(v: Float) = r.top + r.height() * v
                path.moveTo(x(0.58f), y(0.06f))
                path.cubicTo(x(0.63f), y(0.03f), x(0.6f), y(0.14f), x(0.7f), y(0.24f))
                path.cubicTo(x(0.79f), y(0.33f), x(0.95f), y(0.42f), x(0.95f), y(0.63f))
                path.cubicTo(x(0.98f), y(0.88f), x(0.78f), y(0.97f), x(0.5f), y(0.97f))
                path.cubicTo(x(0.22f), y(0.97f), x(0.02f), y(0.88f), x(0.05f), y(0.63f))
                path.cubicTo(x(0.06f), y(0.41f), x(0.24f), y(0.3f), x(0.38f), y(0.22f))
                path.quadTo(x(0.5f), y(0.16f), x(0.58f), y(0.06f))
                path.close()
            }
            DUCK -> {
                fun x(v: Float) = r.left + r.width() * v
                fun y(v: Float) = r.top + r.height() * v
                path.moveTo(x(0.32f), y(0.43f))
                path.cubicTo(x(0.26f), y(0.32f), x(0.3f), y(0.14f), x(0.44f), y(0.1f))
                path.cubicTo(x(0.59f), y(0.04f), x(0.79f), y(0.12f), x(0.8f), y(0.25f))
                path.quadTo(x(0.98f), y(0.25f), x(0.98f), y(0.31f))
                path.quadTo(x(0.98f), y(0.38f), x(0.8f), y(0.38f))
                path.lineTo(x(0.78f), y(0.47f))
                path.cubicTo(x(0.93f), y(0.53f), x(0.98f), y(0.68f), x(0.91f), y(0.82f))
                path.cubicTo(x(0.84f), y(0.97f), x(0.64f), y(0.98f), x(0.45f), y(0.97f))
                path.cubicTo(x(0.19f), y(0.97f), x(0.05f), y(0.84f), x(0.04f), y(0.66f))
                path.quadTo(x(0.02f), y(0.54f), x(0.1f), y(0.57f))
                path.quadTo(x(0.23f), y(0.64f), x(0.32f), y(0.43f))
                path.close()
            }
            else -> path.addRoundRect(body, minSide * 0.3f, minSide * 0.3f, Path.Direction.CW)
        }
        return path
    }
}

data class KeyboardStyle(
    val theme: KeyboardTheme,
    val shape: KeyShape,
    val keyAlpha: Float,
    val fontScale: Float,
    val gapScale: Float,
    val fontId: String = "system",
    val keyEffect: String = "none",
    val finish: KeyFinish = KeyFinish.FLAT,
    /** 線條造型（貓咪、熊熊…）放大幾倍；可以超出按鍵一點點，看起來比較大顆 */
    val shapeScale: Float = 1.15f,
    /** 按下去的動作：jelly 果凍彈彈、hop 跳跳、wiggle 搖搖、pop 放大、none 無（只有字的按鍵會動） */
    val motion: String = "jelly",
)

/** 按下去的動作 */
enum class KeyMotion(val id: String, val title: String) {
    JELLY("jelly", "🍮 果凍彈彈"), HOP("hop", "🐰 跳跳"), WIGGLE("wiggle", "🎵 搖搖"), POP("pop", "⭐ 放大"), NONE("none", "無");

    companion object {
        fun from(id: String) = values().firstOrNull { it.id == id } ?: NONE
    }
}

/** 按鍵質感：平面、胖胖（圓滾滾、按下去會壓扁）、立體（有厚度、按下去往下沉） */
enum class KeyFinish(val title: String) {
    FLAT("平面"), PUFFY("胖胖"), RAISED("立體"), OUTLINE("線稿"), LIQUID("液態玻璃"), METAL("液態金屬");
}

/** 按下按鍵時冒出來的小圖案 */
enum class KeyEffect(val id: String, val title: String, val glyphs: List<String>) {
    NONE("none", "無", emptyList()),
    STARS("stars", "星星", listOf("★", "☆", "✦")),
    HEARTS("hearts", "愛心", listOf("♥︎", "♡", "❤︎")),
    SPARKLES("sparkles", "閃亮", listOf("✧", "✦", "⋆")),
    FLOWERS("flowers", "花花", listOf("✿", "❀", "❁")),
    BUBBLES("bubbles", "泡泡", listOf("○", "◦", "°"));

    companion object {
        fun from(id: String) = values().firstOrNull { it.id == id } ?: NONE
    }
}

/** 按鍵音：系統的喀喀聲，或 App 附的合成音（tools/make_sounds.js） */
enum class KeySound(val id: String, val title: String) {
    SYSTEM("system", "系統"), BUBBLE("bubble", "泡泡"), MARIMBA("marimba", "木琴"), BELL("bell", "叮鈴"), POP("pop", "啵啵");

    companion object {
        fun from(id: String) = values().firstOrNull { it.id == id } ?: SYSTEM
    }
}

/** 按鍵和候選字用的字體（App 裡附的免費字體，SIL OFL 1.1） */
enum class KeyFont(val id: String, val title: String) {
    SYSTEM("system", "系統"), HUNINN("huninn", "粉圓"), IANSUI("iansui", "芫荽"), WENKAI("wenkai", "文楷"),
    GENSEN("gensen", "源泉圓體"), NAIKAI("naikai", "內海"), CUBIC("cubic", "像素");

    /** 放在 App 裡的字體；其他的要用時才下載（FontPacks） */
    val bundled get() = this == SYSTEM || this == HUNINN
}

/** 要用再下載的字體：放在 GitHub 的 font-pack 發佈，下載後存在 App 自己的空間，可以移除、之後再下載 */
object FontPacks {
    fun remote(id: String) = "https://github.com/z3332111-cloud/StarKeyboard/releases/download/font-pack/$id.ttf"
    fun file(context: Context, id: String) = java.io.File(java.io.File(context.filesDir, "fontpack").apply { mkdirs() }, "$id.ttf")

    /** 可以直接用（內建、已下載、或自己匯入的） */
    fun isReady(context: Context, id: String): Boolean {
        if (id.startsWith("user:")) return UserFonts.file(context, id).exists()
        val f = KeyFont.values().firstOrNull { it.id == id } ?: return false
        return f.bundled || file(context, id).exists()
    }

    /** 在背景下載，完成後在主執行緒回報 */
    fun download(context: Context, id: String, done: (Boolean) -> Unit) {
        val main = android.os.Handler(android.os.Looper.getMainLooper())
        Thread {
            val ok = runCatching {
                val conn = java.net.URL(remote(id)).openConnection() as java.net.HttpURLConnection
                conn.connectTimeout = 15000; conn.readTimeout = 30000; conn.instanceFollowRedirects = true
                require(conn.responseCode == 200)
                val tmp = java.io.File(context.cacheDir, "$id.part")
                conn.inputStream.use { input -> tmp.outputStream().use { input.copyTo(it) } }
                require(Typeface.Builder(tmp).build() != null)
                val target = file(context, id)
                target.delete()
                require(tmp.renameTo(target))
                KeyFonts.forget(id)
            }.isSuccess
            main.post { done(ok) }
        }.start()
    }

    fun remove(context: Context, id: String) {
        file(context, id).delete()
        KeyFonts.forget(id)
    }
}

object KeyFonts {
    private val cache = HashMap<String, Typeface?>()

    /** 系統字體或讀不到時回傳 null（用內建字體） */
    fun get(context: Context, id: String): Typeface? = if (id == KeyFont.SYSTEM.id) null else cache.getOrPut(id) {
        if (id.startsWith("user:")) UserFonts.file(context, id).takeIf { it.exists() }?.let { f ->
            runCatching { Typeface.Builder(f).build() }.getOrNull()
        }
        else FontPacks.file(context, id).takeIf { it.exists() }?.let { f -> runCatching { Typeface.Builder(f).build() }.getOrNull() }
            ?: runCatching { Typeface.createFromAsset(context.assets, "fonts/$id.ttf") }.getOrNull()
    }

    fun forget(id: String) { cache.remove(id) }
}

/** 空白鍵上的小圖：自己的圖片（PNG，去背後是透明底）或 GIF 動圖 */
object SpaceArt {
    /** 空白鍵的字以這個開頭＝畫自己的圖片 */
    const val MARK = "\u2060🖼"
    const val MAX_BYTES = 3 * 1024 * 1024
    private fun png(context: Context) = java.io.File(context.filesDir, "space.png")
    private fun gif(context: Context) = java.io.File(context.filesDir, "space.gif")

    fun hasImage(context: Context) = png(context).exists() || gif(context).exists()
    fun file(context: Context) = gif(context).takeIf { it.exists() } ?: png(context).takeIf { it.exists() }
    /** 換圖時會變，用來讓按鍵重畫 */
    fun version(context: Context) = file(context)?.lastModified()?.toString() ?: "0"

    fun saveGif(context: Context, bytes: ByteArray) {
        require(bytes.size <= MAX_BYTES) { "這個 GIF 太大了（超過 3MB），換小一點的" }
        clear(context)
        gif(context).writeBytes(bytes)
    }

    fun saveImage(context: Context, bitmap: android.graphics.Bitmap) {
        clear(context)
        val scale = minOf(1f, 200f / maxOf(bitmap.width, bitmap.height))
        val small = android.graphics.Bitmap.createScaledBitmap(bitmap, maxOf(1, (bitmap.width * scale).toInt()), maxOf(1, (bitmap.height * scale).toInt()), true)
        png(context).outputStream().use { small.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
    }

    fun clear(context: Context) { png(context).delete(); gif(context).delete() }

    /** 讀圖：Android 9 以上 GIF 會動，舊手機只顯示第一格 */
    fun load(context: Context): android.graphics.drawable.Drawable? {
        val f = file(context) ?: return null
        return runCatching {
            if (android.os.Build.VERSION.SDK_INT >= 28) android.graphics.ImageDecoder.decodeDrawable(android.graphics.ImageDecoder.createSource(f))
            else android.graphics.drawable.BitmapDrawable(context.resources, android.graphics.BitmapFactory.decodeFile(f.path))
        }.getOrNull()
    }
}

/** 使用者自己匯入的字體（自己買的、自己用）：檔案在 App 自己的空間，id 是 "user:" 開頭 */
object UserFonts {
    data class Item(val id: String, val name: String)
    const val MAX_BYTES = 40 * 1024 * 1024

    private fun dir(context: Context) = java.io.File(context.filesDir, "userfonts").apply { mkdirs() }
    fun file(context: Context, id: String) = java.io.File(dir(context), id.removePrefix("user:") + ".font")
    private fun prefs(context: Context) = context.getSharedPreferences("keyboard", Context.MODE_PRIVATE)

    fun all(context: Context): List<Item> {
        val raw = prefs(context).getString("userFonts", null) ?: return emptyList()
        return runCatching {
            val arr = org.json.JSONArray(raw)
            (0 until arr.length()).map { arr.getJSONObject(it) }.map { Item(it.getString("id"), it.getString("name")) }
        }.getOrDefault(emptyList()).filter { file(context, it.id).exists() }
    }

    private fun save(context: Context, list: List<Item>) {
        val arr = org.json.JSONArray()
        list.forEach { arr.put(org.json.JSONObject().put("id", it.id).put("name", it.name)) }
        prefs(context).edit().putString("userFonts", arr.toString()).apply()
    }

    /** 存一個字體檔；太大或不是字體就丟錯（訊息直接給使用者看） */
    fun add(context: Context, bytes: ByteArray, name: String): Item {
        require(bytes.size <= MAX_BYTES) { "字體檔超過 40MB，鍵盤裝不下" }
        val item = Item("user:" + java.util.UUID.randomUUID(), name.ifBlank { "我的字體" }.take(12))
        val f = file(context, item.id)
        f.writeBytes(bytes)
        if (runCatching { Typeface.Builder(f).build() }.getOrNull() == null) {
            f.delete()
            error("讀不到這個字體，請用 .ttf 或 .otf 檔")
        }
        save(context, all(context) + item)
        return item
    }

    fun remove(context: Context, id: String) {
        file(context, id).delete()
        KeyFonts.forget(id)
        save(context, all(context).filter { it.id != id })
    }
}

enum class InputMode(val title: String, val short: String, val settingName: String) {
    ZHUYIN("注音", "中", "注音"),
    ENGLISH("English", "英", "英文"),
    HANDWRITING("手寫", "寫", "手寫"),
    KOREAN("한국어", "한", "韓文（한국어）"),
    JAPANESE("日本語", "あ", "日文（羅馬拼音→假名）"),
    PINYIN("拼音", "拼", "拼音（馬來西亞、中國用，可出簡體）"),
}

/** 鍵盤設定（SharedPreferences） */
class KeyboardSettings(context: Context) {
    private val p = context.getSharedPreferences("keyboard", Context.MODE_PRIVATE)
    val dir: File = context.filesDir

    var themeId: String
        get() = p.getString("themeId", "strawberry")!!
        set(v) = p.edit().putString("themeId", v).apply()
    var shape: KeyShape
        get() = runCatching { KeyShape.valueOf(p.getString("shape", "JELLY")!!) }.getOrDefault(KeyShape.JELLY)
        set(v) = p.edit().putString("shape", v.name).apply()
    /** 角色主題也放背景照片（預設不放，用主題自己的底） */
    var themePhoto: Boolean
        get() = p.getBoolean("themePhoto", false)
        set(v) = p.edit().putBoolean("themePhoto", v).apply()
    /** 套用下載主題之前的主題：移除圖或圖不見時換回去 */
    var themeBeforeFox: String
        get() = p.getString("themeBeforeFox", null) ?: "strawberry"
        set(v) = p.edit().putString("themeBeforeFox", v).apply()
    var keyAlpha: Float
        get() = p.getFloat("keyAlpha", 1f)
        set(v) = p.edit().putFloat("keyAlpha", v).apply()
    var backgroundFade: Float
        get() = p.getFloat("backgroundFade", 0.25f)
        set(v) = p.edit().putFloat("backgroundFade", v).apply()
    // ===== 背景照片（可以放好幾張輪流換，每張記住自己的位置和大小） =====

    /** 照片裁切時盡量放在中間的點（0～1，挑照片時有找到臉就是臉的位置）、放大倍數（1 = 剛好蓋滿鍵盤） */
    data class BgPhoto(val file: String, var fx: Float = 0.5f, var fy: Float = 0.3f, var zoom: Float = 1f)

    val photoDir: File get() = File(dir, "backgrounds").also { it.mkdirs() }

    var photos: List<BgPhoto>
        get() {
            val raw = p.getString("photos", null) ?: return migrateOldBackground()
            return runCatching {
                val arr = org.json.JSONArray(raw)
                (0 until arr.length()).map { i ->
                    val o = arr.getJSONObject(i)
                    BgPhoto(o.getString("file"), o.optDouble("fx", 0.5).toFloat(), o.optDouble("fy", 0.3).toFloat(), o.optDouble("zoom", 1.0).toFloat())
                }
            }.getOrDefault(emptyList())
        }
        set(v) {
            val arr = org.json.JSONArray()
            for (ph in v) arr.put(org.json.JSONObject().put("file", ph.file).put("fx", ph.fx.toDouble()).put("fy", ph.fy.toDouble()).put("zoom", ph.zoom.toDouble()))
            p.edit().putString("photos", arr.toString()).apply()
        }

    /** 舊版只有一張 background.jpg：搬進照片清單 */
    private fun migrateOldBackground(): List<BgPhoto> {
        val old = File(dir, "background.jpg")
        val list = ArrayList<BgPhoto>()
        if (p.getBoolean("hasBackground", false) && old.exists()) {
            val name = "bg-old.jpg"
            if (old.renameTo(File(photoDir, name))) {
                list.add(BgPhoto(name, p.getFloat("backgroundFocusX", 0.5f), p.getFloat("backgroundFocusY", 0.3f), p.getFloat("backgroundZoom", 1f)))
            }
        }
        photos = list
        return list
    }

    var photoIndex: Int
        get() = p.getInt("photoIndex", 0)
        set(v) = p.edit().putInt("photoIndex", v).apply()

    /** 照片怎麼換：fixed 固定、open 每次打開鍵盤換、daily 每天換 */
    var photoRotation: String
        get() = p.getString("photoRotation", "fixed") ?: "fixed"
        set(v) = p.edit().putString("photoRotation", v).apply()

    val currentPhoto: BgPhoto?
        get() {
            val list = photos
            return if (list.isEmpty()) null else list[Math.floorMod(photoIndex, list.size)]
        }

    val backgroundFile: File get() = File(photoDir, currentPhoto?.file ?: "none.jpg")
    val hasBackground: Boolean get() = currentPhoto != null && backgroundFile.exists()

    private fun updateCurrent(change: (BgPhoto) -> Unit) {
        val list = photos
        if (list.isEmpty()) return
        change(list[Math.floorMod(photoIndex, list.size)])
        photos = list
    }

    var backgroundFocusX: Float
        get() = currentPhoto?.fx ?: 0.5f
        set(v) = updateCurrent { it.fx = v }
    var backgroundFocusY: Float
        get() = currentPhoto?.fy ?: 0.3f
        set(v) = updateCurrent { it.fy = v }
    var backgroundZoom: Float
        get() = currentPhoto?.zoom ?: 1f
        set(v) = updateCurrent { it.zoom = v }

    /** 新增一張照片（write 把圖片寫進檔案），並換成這張 */
    fun addPhoto(fx: Float, fy: Float, write: (File) -> Unit) {
        val name = "bg-" + System.currentTimeMillis() + ".jpg"
        write(File(photoDir, name))
        val list = photos + BgPhoto(name, fx, fy, 1f)
        photos = list
        photoIndex = list.size - 1
    }

    fun removePhoto(index: Int) {
        val list = photos.toMutableList()
        if (index !in list.indices) return
        File(photoDir, list.removeAt(index).file).delete()
        photos = list
        photoIndex = if (list.isEmpty()) 0 else Math.floorMod(minOf(photoIndex, list.size - 1), list.size)
    }

    fun clearPhotos() {
        photos.forEach { File(photoDir, it.file).delete() }
        photos = emptyList()
        photoIndex = 0
    }

    /** 打開鍵盤時依設定換照片 */
    fun rotatePhoto() {
        val n = photos.size
        if (n < 2) return
        when (photoRotation) {
            "open" -> photoIndex = (Math.floorMod(photoIndex, n) + 1) % n
            "daily" -> {
                val now = System.currentTimeMillis()
                val day = (now + java.util.TimeZone.getDefault().getOffset(now)) / 86_400_000L
                photoIndex = (day % n).toInt()
            }
        }
    }

    /** 照片的小縮圖（設定面板用） */
    fun thumbnail(ph: BgPhoto): android.graphics.Bitmap? = runCatching {
        android.graphics.BitmapFactory.decodeFile(File(photoDir, ph.file).path, android.graphics.BitmapFactory.Options().apply { inSampleSize = 8 })
    }.getOrNull()
    /** 剛在 App 挑了照片：下次打開鍵盤直接進入調整照片 */
    var adjustPhotoPending: Boolean
        get() = p.getBoolean("adjustPhotoPending", false)
        set(v) = p.edit().putBoolean("adjustPhotoPending", v).apply()
    var heightScale: Float
        get() = p.getFloat("heightScale", 1f)
        set(v) = p.edit().putFloat("heightScale", v).apply()
    var fontScale: Float
        get() = p.getFloat("fontScale", 1f)
        set(v) = p.edit().putFloat("fontScale", v).apply()
    var gapScale: Float
        get() = p.getFloat("gapScale", 1f)
        set(v) = p.edit().putFloat("gapScale", v).apply()
    /** 貓咪、熊熊這類造型的大小（1 = 剛好放進按鍵，大於 1 會超出一點） */
    var shapeScale: Float
        get() = p.getFloat("shapeScale", 1.15f)
        set(v) = p.edit().putFloat("shapeScale", v).apply()
    var keyEffect: String
        get() = p.getString("keyEffect", KeyEffect.NONE.id) ?: KeyEffect.NONE.id
        set(v) = p.edit().putString("keyEffect", v).apply()
    // 自訂配色：色相 0～1、濃淡 0～1、深色
    var customHue: Float
        get() = p.getFloat("customHue", 0.92f)
        set(v) = p.edit().putFloat("customHue", v).apply()
    var customSaturation: Float
        get() = p.getFloat("customSaturation", 0.55f)
        set(v) = p.edit().putFloat("customSaturation", v).apply()
    /** 第二色：-1 = 單色 */
    var customHue2: Float
        get() = p.getFloat("customHue2", -1f)
        set(v) = p.edit().putFloat("customHue2", v).apply()
    var customSaturation2: Float
        get() = p.getFloat("customSaturation2", 0.55f)
        set(v) = p.edit().putFloat("customSaturation2", v).apply()
    /** 空白鍵：theme 主題符號＋輸入法名字、image 自己的圖片／GIF、emoji 表符、text 只有字 */
    /** 按下去的動作（KeyMotion） */
    var keyMotion: String
        get() = p.getString("keyMotion", "jelly") ?: "jelly"
        set(v) = p.edit().putString("keyMotion", v).apply()
    var spaceStyle: String
        get() = p.getString("spaceStyle", "theme") ?: "theme"
        set(v) = p.edit().putString("spaceStyle", v).apply()
    var spaceEmoji: String
        get() = p.getString("spaceEmoji", "🐰") ?: "🐰"
        set(v) = p.edit().putString("spaceEmoji", v).apply()
    var customDark: Boolean
        get() = p.getBoolean("customDark", false)
        set(v) = p.edit().putBoolean("customDark", v).apply()
    val theme: KeyboardTheme
        get() = if (themeId == "custom") KeyboardTheme.custom(customHue, customSaturation, customDark, customHue2, customSaturation2) else KeyboardTheme.named(themeId)
    var keyFinish: KeyFinish
        get() = runCatching { KeyFinish.valueOf(p.getString("keyFinish", "FLAT")!!.replace("GLASS", "RAISED")) }.getOrDefault(KeyFinish.FLAT)
        set(v) = p.edit().putString("keyFinish", v.name).apply()
    var keySoundStyle: String
        get() = p.getString("keySoundStyle", KeySound.SYSTEM.id) ?: KeySound.SYSTEM.id
        set(v) = p.edit().putString("keySoundStyle", v).apply()
    var keySound: Boolean
        get() = p.getBoolean("keySound", true)
        set(v) = p.edit().putBoolean("keySound", v).apply()
    var haptics: Boolean
        get() = p.getBoolean("haptics", true)
        set(v) = p.edit().putBoolean("haptics", v).apply()
    var associations: Boolean
        get() = p.getBoolean("associations", true)
        set(v) = p.edit().putBoolean("associations", v).apply()
    var glideTyping: Boolean
        get() = p.getBoolean("glideTyping", true)
        set(v) = p.edit().putBoolean("glideTyping", v).apply()
    var autocorrect: Boolean
        get() = p.getBoolean("autocorrect", true)
        set(v) = p.edit().putBoolean("autocorrect", v).apply()
    var fuzzyKeys: Boolean
        get() = p.getBoolean("fuzzyKeys", true)
        set(v) = p.edit().putBoolean("fuzzyKeys", v).apply()
    var fuzzyTones: Boolean
        get() = p.getBoolean("fuzzyTones", true)
        set(v) = p.edit().putBoolean("fuzzyTones", v).apply()
    var fuzzyPhonetic: Boolean
        get() = p.getBoolean("fuzzyPhonetic", false)
        set(v) = p.edit().putBoolean("fuzzyPhonetic", v).apply()
    var enabledModes: List<InputMode>
        get() {
            val raw = p.getString("modes", "ZHUYIN,ENGLISH,HANDWRITING")!!.split(',')
            return InputMode.values().filter { it.name in raw }.ifEmpty { listOf(InputMode.ZHUYIN) }
        }
        set(v) = p.edit().putString("modes", v.joinToString(",") { it.name }).apply()
    var lastMode: InputMode
        get() = runCatching { InputMode.valueOf(p.getString("lastMode", "ZHUYIN")!!) }.getOrDefault(InputMode.ZHUYIN)
        set(v) = p.edit().putString("lastMode", v.name).apply()
    var clipboardHistoryEnabled: Boolean
        get() = p.getBoolean("clipboardHistoryEnabled", false)
        set(v) = p.edit().putBoolean("clipboardHistoryEnabled", v).apply()
    var allowOnlineTranslation: Boolean
        get() = p.getBoolean("allowOnlineTranslation", false)
        set(v) = p.edit().putBoolean("allowOnlineTranslation", v).apply()
    /** 選字列高度（dp）。設定滑桿會記下來，字跟著變大。 */
    var candidateBarHeight: Float
        get() = p.getFloat("candidateBarHeight", 50f).coerceIn(40f, 88f)
        set(v) = p.edit().putFloat("candidateBarHeight", v.coerceIn(40f, 88f)).apply()
    var clipLimit: Int
        get() = p.getInt("clipLimit", 200)
        set(v) = p.edit().putInt("clipLimit", v).apply()
    /** 上面那一排關掉的按鈕 */
    var hiddenTools: Set<ToolbarItem>
        get() = (p.getString("hiddenTools", "") ?: "").split(",").mapNotNull { n -> ToolbarItem.values().firstOrNull { it.name == n } }.toSet()
        set(v) = p.edit().putString("hiddenTools", v.joinToString(",") { it.name }).apply()
    /** 注音十欄排法（像 Gboard） */
    var zhuyinTenColumns: Boolean
        get() = p.getBoolean("zhuyinTenColumns", false)
        set(v) = p.edit().putBoolean("zhuyinTenColumns", v).apply()
    /** 拼音模式輸出簡體字（馬來西亞、中國用簡體） */
    var pinyinSimplified: Boolean
        get() = p.getBoolean("pinyinSimplified", false)
        set(v) = p.edit().putBoolean("pinyinSimplified", v).apply()
    /** 舊的全形開關。程式／Markdown 符號一律半形，不受這個值影響。 */
    var fullWidthSymbols: Boolean
        get() = p.getBoolean("fullWidthSymbols", true)
        set(v) = p.edit().putBoolean("fullWidthSymbols", v).apply()
    /** 翻譯的原文語言："auto" 是自己猜 */
    var translateSource: String
        get() = p.getString("translateSource", "auto")!!
        set(v) = p.edit().putString("translateSource", v).apply()
    var translateTarget: String
        get() = p.getString("translateTarget", "en")!!
        set(v) = p.edit().putString("translateTarget", v).apply()
    var lastUpdateCheck: Long
        get() = p.getLong("lastUpdateCheck", 0)
        set(v) = p.edit().putLong("lastUpdateCheck", v).apply()
    var latestBuild: Int
        get() = p.getInt("latestBuild", 0)
        set(v) = p.edit().putInt("latestBuild", v).apply()
    var notifiedBuild: Int
        get() = p.getInt("notifiedBuild", 0)
        set(v) = p.edit().putInt("notifiedBuild", v).apply()


    var fontId: String
        get() = p.getString("fontId", KeyFont.SYSTEM.id) ?: KeyFont.SYSTEM.id
        set(v) = p.edit().putString("fontId", v).apply()

    val style get() = FoxLetter.resolved(KeyboardStyle(theme, shape, keyAlpha, fontScale, gapScale, fontId, keyEffect, keyFinish, shapeScale, keyMotion))
}

/** 線條的顏色：線稿質感的外框、貓咪的尾巴鬍鬚眼睛肉球 */
val KeyboardStyle.lineColor: Int
    get() = if (finish == KeyFinish.OUTLINE) {
        if (theme.dark) Color.argb(240, 0xFA, 0xFB, 0xFF) else Color.argb(214, 0x29, 0x2B, 0x2C)
    } else theme.keyText.withAlpha(0.8f)
