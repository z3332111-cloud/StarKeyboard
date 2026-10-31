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
            KeyboardTheme("light", "經典淺色", c("#D3D6DC"), c("#CDD0D6"), c("#FFFFFF"), c("#000000"), c("#ABB0BA"), c("#000000"), c("#2F7BF6"), c("#FFFFFF"), c("#8E9196"), "", false),
            KeyboardTheme("dark", "經典深色", c("#2B2B2D"), c("#232325"), c("#6B6B6E"), c("#FFFFFF"), c("#474749"), c("#FFFFFF"), c("#2F7BF6"), c("#FFFFFF"), c("#111111"), "", true),
        )

        fun named(id: String) = all.firstOrNull { it.id == id } ?: all[0]
    }
}

fun Int.withAlpha(a: Float): Int = Color.argb((Color.alpha(this) * a.coerceIn(0f, 1f)).toInt(), Color.red(this), Color.green(this), Color.blue(this))

/** 按鍵造型（和 iPhone 版 KeyShape 一樣的算法，單位是 dp 換成的像素） */
enum class KeyShape(val title: String) {
    ROUNDED("圓角"), JELLY("果凍"), CAT_EAR("貓耳"), CLOUD("雲朵"), BUNNY("兔兔"), PUPPY("狗狗"), PUDDING("布丁"), JELLYFISH("水母"), FLAME("火焰"), DROPLET("水滴"), DUCK("鴨鴨"), MOCHI("麻糬"), BUBBLE("泡泡");

    val isSoftShape: Boolean get() = when (this) {
        BUNNY, PUPPY, PUDDING, JELLYFISH, FLAME, DROPLET, DUCK -> true
        else -> false
    }

    private fun isWide(r: RectF) = isSoftShape && r.width() > r.height() * 1.65f
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
        if (this == BUBBLE) {
            val b = bodyRect(r, dp)
            val s = minOf(b.width(), b.height()) * 0.16f
            val l = b.left + b.width() * 0.2f
            val tp = b.top + b.height() * 0.16f
            return Path().apply { addOval(RectF(l, tp, l + s, tp + s), Path.Direction.CW) }
        }
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

    fun detailColor(theme: KeyboardTheme): Int = when (this) {
        PUDDING -> Color.rgb(if (theme.dark) 215 else 168, if (theme.dark) 161 else 102, if (theme.dark) 95 else 53)
        FLAME -> if (theme.dark) Color.rgb(255, 212, 107) else Color.rgb(237, 145, 74)
        DROPLET -> if (theme.dark) Color.rgb(184, 239, 255) else Color.rgb(74, 173, 213)
        DUCK -> if (theme.dark) Color.rgb(255, 210, 118) else Color.rgb(215, 138, 50)
        BUBBLE -> Color.WHITE
        else -> theme.accent
    }

    fun path(r: RectF, dp: Float): Path {
        if (isWide(r)) {
            val body = wideBody(r)
            return Path().apply { addRoundRect(body, body.height() * 0.36f, body.height() * 0.36f, Path.Direction.CW) }
        }
        val body = bodyRect(r, dp)
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
            MOCHI -> {
                // 圓滾滾、下面比較胖的麻糬
                fun x(v: Float) = body.left + body.width() * v
                fun y(v: Float) = body.top + body.height() * v
                path.moveTo(x(0.5f), y(0.03f))
                path.cubicTo(x(0.86f), y(0.02f), x(0.985f), y(0.2f), x(0.985f), y(0.52f))
                path.cubicTo(x(0.99f), y(0.88f), x(0.84f), y(0.99f), x(0.5f), y(0.99f))
                path.cubicTo(x(0.16f), y(0.99f), x(0.01f), y(0.88f), x(0.015f), y(0.52f))
                path.cubicTo(x(0.015f), y(0.2f), x(0.14f), y(0.02f), x(0.5f), y(0.03f))
                path.close()
            }
            BUBBLE -> path.addRoundRect(body, minSide / 2, minSide / 2, Path.Direction.CW)
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
)

/** 按鍵質感：平面、胖胖（圓滾滾有立體感、按下去會壓扁）、玻璃（半透明、亮亮的邊） */
enum class KeyFinish(val title: String) {
    FLAT("平面"), PUFFY("胖胖"), GLASS("玻璃");
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
    GENSEN("gensen", "源泉圓體"), NAIKAI("naikai", "內海"), CUBIC("cubic", "像素"),
}

object KeyFonts {
    private val cache = HashMap<String, Typeface?>()

    /** 系統字體或讀不到時回傳 null（用內建字體） */
    fun get(context: Context, id: String): Typeface? = if (id == KeyFont.SYSTEM.id) null else cache.getOrPut(id) {
        runCatching { Typeface.createFromAsset(context.assets, "fonts/$id.ttf") }.getOrNull()
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
    var keyEffect: String
        get() = p.getString("keyEffect", KeyEffect.NONE.id) ?: KeyEffect.NONE.id
        set(v) = p.edit().putString("keyEffect", v).apply()
    var keyFinish: KeyFinish
        get() = runCatching { KeyFinish.valueOf(p.getString("keyFinish", "FLAT")!!) }.getOrDefault(KeyFinish.FLAT)
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

    val style get() = KeyboardStyle(KeyboardTheme.named(themeId), shape, keyAlpha, fontScale, gapScale, fontId, keyEffect, keyFinish)
}
