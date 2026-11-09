package com.startown.starkeyboard.ime

import android.graphics.Color
import android.graphics.Path
import android.graphics.RectF

// 由 tools/key_shapes.txt 產生（node tools/build_shapes.js），不要直接改這個檔案

/** 用線條畫的按鍵造型（動物、像素、拼圖、書本、蝴蝶結…）。座標在 0～100 的方格裡，畫的時候拉伸成按鍵大小。 */
class KeyShapeArt(
    val title: String,
    /** 字放在這個方框（0～100）的中間：x, y, 寬, 高 */
    private val body: FloatArray,
    private val path: FloatArray,
    private val detail: FloatArray,
    /** 只畫線、不填色的部分（尾巴、鬍鬚） */
    private val lines: FloatArray,
    /** 小裝飾的顏色；null = 用主題的強調色 */
    private val detailLight: Int?,
    private val detailDark: Int?,
    val detailAlpha: Float,
    /** 高÷寬：畫的時候保持這個比例（按鍵太瘦時上下留白，太矮時左右留白），才不會被拉長 */
    private val aspect: Float,
    /** 寬的鍵（空白鍵）把中間拉長，左右兩端（頭、尾巴）保持原樣 */
    val stretch: Boolean,
    /** 小裝飾用線條的顏色（貓咪的眼睛、肉球） */
    val lineDetail: Boolean,
) {
    /** 按鍵裡實際畫圖案的方框：保持比例、置中 */
    fun fit(r: RectF): RectF {
        var w = r.width(); var h = minOf(r.height(), w * aspect)
        if (r.width() * aspect > r.height()) { h = r.height(); w = h / aspect }
        return RectF(r.centerX() - w / 2, r.centerY() - h / 2, r.centerX() + w / 2, r.centerY() + h / 2)
    }
    fun isStretched(r: RectF) = stretch && r.width() * aspect > r.height() * 1.05f
    private fun place(ops: FloatArray, r: RectF): Path = if (isStretched(r)) build(ops, r, r.height() / aspect) else build(ops, fit(r), null)
    fun path(r: RectF): Path = place(path, r)
    fun detailPath(r: RectF): Path = place(detail, r)
    fun linesPath(r: RectF): Path? = if (lines.isEmpty()) null else place(lines, r)
    fun bodyRect(rect: RectF): RectF {
        if (isStretched(rect)) {
            val u = rect.height() / aspect / 100
            return RectF(rect.left + body[0] * u, rect.top + rect.height() * body[1] / 100,
                rect.right - (100 - body[0] - body[2]) * u, rect.top + rect.height() * (body[1] + body[3]) / 100)
        }
        val r = fit(rect)
        return RectF(r.left + r.width() * body[0] / 100, r.top + r.height() * body[1] / 100,
            r.left + r.width() * (body[0] + body[2]) / 100, r.top + r.height() * (body[1] + body[3]) / 100)
    }
    fun detailColor(theme: KeyboardTheme): Int {
        val light = detailLight ?: return theme.accent
        val c = if (theme.dark) detailDark ?: light else light
        return Color.rgb(c shr 16 and 0xFF, c shr 8 and 0xFF, c and 0xFF)
    }

    companion object {
        val order = listOf("catFace", "bear", "paw", "cloudPuff", "pixel", "pixelHeart", "puzzle", "book", "butterfly", "strawberry", "flower", "moon", "star", "heart", "latte", "catLine", "circle", "chamfer")

        val shapes: Map<String, KeyShapeArt> = mapOf(
            "catFace" to KeyShapeArt(
                "貓咪", floatArrayOf(14f, 38f, 72f, 50f),
                floatArrayOf(0f, 14f, 34f, 2f, 12f, 24f, 12f, 14f, 14f, 7f, 2f, 15f, 3f, 19f, 2f, 22f, 4f, 2f, 28f, 8f, 34f, 12f, 39f, 16f, 2f, 46f, 14f, 54f, 14f, 61f, 16f, 2f, 66f, 12f, 72f, 8f, 78f, 4f, 2f, 81f, 2f, 85f, 3f, 86f, 7f, 2f, 88f, 14f, 88f, 24f, 86f, 34f, 2f, 94f, 40f, 99f, 50f, 99f, 62f, 2f, 99f, 84f, 80f, 98f, 50f, 98f, 2f, 20f, 98f, 1f, 84f, 1f, 62f, 2f, 1f, 50f, 6f, 40f, 14f, 34f, 4f),
                floatArrayOf(0f, 18f, 11f, 2f, 19f, 8f, 22f, 8f, 24f, 10f, 1f, 31f, 18f, 2f, 32f, 20f, 31f, 21f, 29f, 22f, 2f, 25f, 24f, 22f, 27f, 20f, 30f, 2f, 18f, 32f, 17f, 31f, 17f, 29f, 1f, 17f, 13f, 4f, 0f, 83f, 13f, 1f, 83f, 29f, 2f, 83f, 31f, 82f, 32f, 80f, 30f, 2f, 78f, 27f, 75f, 24f, 71f, 22f, 2f, 69f, 21f, 68f, 20f, 69f, 18f, 1f, 76f, 10f, 2f, 78f, 8f, 81f, 8f, 82f, 11f, 4f, 0f, 12.98f, 61.49f, 2f, 12.94f, 62.15f, 9.77f, 62.47f, 5.92f, 62.2f, 2f, 2.06f, 61.93f, -1.03f, 61.17f, -0.98f, 60.51f, 2f, -0.94f, 59.85f, 2.23f, 59.53f, 6.08f, 59.8f, 2f, 9.94f, 60.07f, 13.03f, 60.83f, 12.98f, 61.49f, 4f, 0f, 12.89f, 72.78f, 2f, 13.01f, 73.44f, 10.02f, 74.51f, 6.21f, 75.18f, 2f, 2.4f, 75.85f, -0.78f, 75.87f, -0.89f, 75.22f, 2f, -1.01f, 74.56f, 1.98f, 73.49f, 5.79f, 72.82f, 2f, 9.6f, 72.15f, 12.78f, 72.13f, 12.89f, 72.78f, 4f, 0f, 100.98f, 60.51f, 2f, 101.03f, 61.17f, 97.94f, 61.93f, 94.08f, 62.2f, 2f, 90.23f, 62.47f, 87.06f, 62.15f, 87.02f, 61.49f, 2f, 86.97f, 60.83f, 90.06f, 60.07f, 93.92f, 59.8f, 2f, 97.77f, 59.53f, 100.94f, 59.85f, 100.98f, 60.51f, 4f, 0f, 100.89f, 75.22f, 2f, 100.78f, 75.87f, 97.6f, 75.85f, 93.79f, 75.18f, 2f, 89.98f, 74.51f, 86.99f, 73.44f, 87.11f, 72.78f, 2f, 87.22f, 72.13f, 90.4f, 72.15f, 94.21f, 72.82f, 2f, 98.02f, 73.49f, 101.01f, 74.56f, 100.89f, 75.22f, 4f),
                floatArrayOf(),
                0xF2A0BC, 0xF2A0BC, 0.85f, 0.97f, false, false),
            "bear" to KeyShapeArt(
                "熊熊", floatArrayOf(12f, 34f, 76f, 44f),
                floatArrayOf(0f, 33f, 22f, 2f, 33f, 32.49f, 25.84f, 41f, 17f, 41f, 2f, 8.16f, 41f, 1f, 32.49f, 1f, 22f, 2f, 1f, 11.51f, 8.16f, 3f, 17f, 3f, 2f, 25.84f, 3f, 33f, 11.51f, 33f, 22f, 4f, 0f, 99f, 22f, 2f, 99f, 32.49f, 91.84f, 41f, 83f, 41f, 2f, 74.16f, 41f, 67f, 32.49f, 67f, 22f, 2f, 67f, 11.51f, 74.16f, 3f, 83f, 3f, 2f, 91.84f, 3f, 99f, 11.51f, 99f, 22f, 4f, 0f, 30f, 12f, 2f, 40f, 9f, 60f, 9f, 70f, 12f, 2f, 86f, 16f, 96f, 28f, 97f, 44f, 2f, 98f, 58f, 97f, 72f, 92f, 82f, 2f, 86f, 94f, 70f, 98f, 50f, 98f, 2f, 30f, 98f, 14f, 94f, 8f, 82f, 2f, 3f, 72f, 2f, 58f, 3f, 44f, 2f, 4f, 28f, 14f, 16f, 30f, 12f, 4f),
                floatArrayOf(0f, 26f, 22f, 2f, 26f, 26.69f, 22.87f, 30.5f, 19f, 30.5f, 2f, 15.13f, 30.5f, 12f, 26.69f, 12f, 22f, 2f, 12f, 17.31f, 15.13f, 13.5f, 19f, 13.5f, 2f, 22.87f, 13.5f, 26f, 17.31f, 26f, 22f, 4f, 0f, 88f, 22f, 2f, 88f, 26.69f, 84.87f, 30.5f, 81f, 30.5f, 2f, 77.13f, 30.5f, 74f, 26.69f, 74f, 22f, 2f, 74f, 17.31f, 77.13f, 13.5f, 81f, 13.5f, 2f, 84.87f, 13.5f, 88f, 17.31f, 88f, 22f, 4f, 0f, 47.89f, 88.78f, 2f, 48.47f, 92.05f, 45.85f, 95.24f, 42.04f, 95.91f, 2f, 38.23f, 96.58f, 34.68f, 94.48f, 34.11f, 91.22f, 2f, 33.53f, 87.95f, 36.15f, 84.76f, 39.96f, 84.09f, 2f, 43.77f, 83.42f, 47.32f, 85.52f, 47.89f, 88.78f, 4f, 0f, 65.89f, 91.22f, 2f, 65.32f, 94.48f, 61.77f, 96.58f, 57.96f, 95.91f, 2f, 54.15f, 95.24f, 51.53f, 92.05f, 52.11f, 88.78f, 2f, 52.68f, 85.52f, 56.23f, 83.42f, 60.04f, 84.09f, 2f, 63.85f, 84.76f, 66.47f, 87.95f, 65.89f, 91.22f, 4f, 0f, 54.5f, 89f, 2f, 54.5f, 91.49f, 52.49f, 93.5f, 50f, 93.5f, 2f, 47.51f, 93.5f, 45.5f, 91.49f, 45.5f, 89f, 2f, 45.5f, 86.51f, 47.51f, 84.5f, 50f, 84.5f, 2f, 52.49f, 84.5f, 54.5f, 86.51f, 54.5f, 89f, 4f),
                floatArrayOf(),
                0xC99579, 0xDDB096, 0.8f, 0.86f, false, false),
            "paw" to KeyShapeArt(
                "肉球", floatArrayOf(28f, 52f, 44f, 32f),
                floatArrayOf(0f, 50f, 9f, 2f, 56f, 4f, 66f, 3f, 74f, 8f, 2f, 79f, 12f, 80f, 20f, 80f, 27f, 2f, 88f, 27f, 96f, 32f, 98f, 42f, 2f, 100f, 52f, 97f, 62f, 92f, 70f, 2f, 96f, 80f, 92f, 92f, 80f, 96f, 2f, 70f, 99f, 60f, 99f, 50f, 99f, 2f, 40f, 99f, 30f, 99f, 20f, 96f, 2f, 8f, 92f, 4f, 80f, 8f, 70f, 2f, 3f, 62f, 0f, 52f, 2f, 42f, 2f, 4f, 32f, 12f, 27f, 20f, 27f, 2f, 20f, 20f, 21f, 12f, 26f, 8f, 2f, 34f, 3f, 44f, 4f, 50f, 9f, 4f),
                floatArrayOf(0f, 28f, 45f, 2f, 28f, 49.97f, 24.42f, 54f, 20f, 54f, 2f, 15.58f, 54f, 12f, 49.97f, 12f, 45f, 2f, 12f, 40.03f, 15.58f, 36f, 20f, 36f, 2f, 24.42f, 36f, 28f, 40.03f, 28f, 45f, 4f, 0f, 48f, 30f, 2f, 48f, 35.25f, 44.42f, 39.5f, 40f, 39.5f, 2f, 35.58f, 39.5f, 32f, 35.25f, 32f, 30f, 2f, 32f, 24.75f, 35.58f, 20.5f, 40f, 20.5f, 2f, 44.42f, 20.5f, 48f, 24.75f, 48f, 30f, 4f, 0f, 68f, 30f, 2f, 68f, 35.25f, 64.42f, 39.5f, 60f, 39.5f, 2f, 55.58f, 39.5f, 52f, 35.25f, 52f, 30f, 2f, 52f, 24.75f, 55.58f, 20.5f, 60f, 20.5f, 2f, 64.42f, 20.5f, 68f, 24.75f, 68f, 30f, 4f, 0f, 88f, 45f, 2f, 88f, 49.97f, 84.42f, 54f, 80f, 54f, 2f, 75.58f, 54f, 72f, 49.97f, 72f, 45f, 2f, 72f, 40.03f, 75.58f, 36f, 80f, 36f, 2f, 84.42f, 36f, 88f, 40.03f, 88f, 45f, 4f, 0f, 28f, 72f, 2f, 28f, 58f, 38f, 50f, 50f, 50f, 2f, 62f, 50f, 72f, 58f, 72f, 72f, 2f, 72f, 82f, 66f, 86f, 58f, 85f, 2f, 54f, 84f, 46f, 84f, 42f, 85f, 2f, 34f, 86f, 28f, 82f, 28f, 72f, 4f),
                floatArrayOf(),
                0xF4A3BC, 0xF4A3BC, 0.9f, 0.85f, false, false),
            "cloudPuff" to KeyShapeArt(
                "棉花雲", floatArrayOf(12f, 40f, 60f, 44f),
                floatArrayOf(0f, 74f, 34f, 2f, 74f, 50.57f, 61.46f, 64f, 46f, 64f, 2f, 30.54f, 64f, 18f, 50.57f, 18f, 34f, 2f, 18f, 17.43f, 30.54f, 4f, 46f, 4f, 2f, 61.46f, 4f, 74f, 17.43f, 74f, 34f, 4f, 0f, 95f, 36f, 2f, 95f, 45.94f, 87.84f, 54f, 79f, 54f, 2f, 70.16f, 54f, 63f, 45.94f, 63f, 36f, 2f, 63f, 26.06f, 70.16f, 18f, 79f, 18f, 2f, 87.84f, 18f, 95f, 26.06f, 95f, 36f, 4f, 0f, 100f, 63f, 2f, 100f, 74.05f, 94.63f, 83f, 88f, 83f, 2f, 81.37f, 83f, 76f, 74.05f, 76f, 63f, 2f, 76f, 51.95f, 81.37f, 43f, 88f, 43f, 2f, 94.63f, 43f, 100f, 51.95f, 100f, 63f, 4f, 0f, 28f, 63f, 2f, 28f, 75.15f, 22.18f, 85f, 15f, 85f, 2f, 7.82f, 85f, 2f, 75.15f, 2f, 63f, 2f, 2f, 50.85f, 7.82f, 41f, 15f, 41f, 2f, 22.18f, 41f, 28f, 50.85f, 28f, 63f, 4f, 0f, 40f, 48f, 2f, 40f, 56.84f, 32.84f, 64f, 24f, 64f, 2f, 15.16f, 64f, 8f, 56.84f, 8f, 48f, 2f, 8f, 39.16f, 15.16f, 32f, 24f, 32f, 2f, 32.84f, 32f, 40f, 39.16f, 40f, 48f, 4f, 0f, 92f, 72f, 2f, 92f, 86.36f, 73.2f, 98f, 50f, 98f, 2f, 26.8f, 98f, 8f, 86.36f, 8f, 72f, 2f, 8f, 57.64f, 26.8f, 46f, 50f, 46f, 2f, 73.2f, 46f, 92f, 57.64f, 92f, 72f, 4f, 0f, 36f, 86f, 2f, 36f, 92.63f, 29.73f, 98f, 22f, 98f, 2f, 14.27f, 98f, 8f, 92.63f, 8f, 86f, 2f, 8f, 79.37f, 14.27f, 74f, 22f, 74f, 2f, 29.73f, 74f, 36f, 79.37f, 36f, 86f, 4f, 0f, 92f, 86f, 2f, 92f, 92.63f, 85.73f, 98f, 78f, 98f, 2f, 70.27f, 98f, 64f, 92.63f, 64f, 86f, 2f, 64f, 79.37f, 70.27f, 74f, 78f, 74f, 2f, 85.73f, 74f, 92f, 79.37f, 92f, 86f, 4f),
                floatArrayOf(0f, 90.29f, 62.49f, 1f, 82.18f, 63.98f, 3f, 79.47f, 64.47f, 78.98f, 67.18f, 1f, 77.49f, 75.29f, 3f, 77f, 78f, 76.51f, 75.29f, 1f, 75.02f, 67.18f, 3f, 74.53f, 64.47f, 71.82f, 63.98f, 1f, 63.71f, 62.49f, 3f, 61f, 62f, 63.71f, 61.51f, 1f, 71.82f, 60.02f, 3f, 74.53f, 59.53f, 75.02f, 56.82f, 1f, 76.51f, 48.71f, 3f, 77f, 46f, 77.49f, 48.71f, 1f, 78.98f, 56.82f, 3f, 79.47f, 59.53f, 82.18f, 60.02f, 1f, 90.29f, 61.51f, 3f, 93f, 62f, 90.29f, 62.49f, 4f),
                floatArrayOf(),
                0xF2C46B, 0xF7D88A, 0.95f, 0.86f, false, false),
            "pixel" to KeyShapeArt(
                "像素", floatArrayOf(6f, 6f, 88f, 88f),
                floatArrayOf(0f, 12f, 0f, 1f, 88f, 0f, 1f, 88f, 6f, 1f, 94f, 6f, 1f, 94f, 12f, 1f, 100f, 12f, 1f, 100f, 88f, 1f, 94f, 88f, 1f, 94f, 94f, 1f, 88f, 94f, 1f, 88f, 100f, 1f, 12f, 100f, 1f, 12f, 94f, 1f, 6f, 94f, 1f, 6f, 88f, 1f, 0f, 88f, 1f, 0f, 12f, 1f, 6f, 12f, 1f, 6f, 6f, 1f, 12f, 6f, 4f),
                floatArrayOf(0f, 12f, 10f, 1f, 28f, 10f, 1f, 28f, 16f, 1f, 18f, 16f, 1f, 18f, 28f, 1f, 12f, 28f, 4f),
                floatArrayOf(),
                0xFFFFFF, 0xFFFFFF, 0.75f, 1f, false, false),
            "pixelHeart" to KeyShapeArt(
                "像素心", floatArrayOf(14f, 12f, 72f, 52f),
                floatArrayOf(0f, 10f, 0f, 1f, 40f, 0f, 1f, 40f, 10f, 1f, 60f, 10f, 1f, 60f, 0f, 1f, 90f, 0f, 1f, 90f, 10f, 1f, 100f, 10f, 1f, 100f, 50f, 1f, 90f, 50f, 1f, 90f, 60f, 1f, 80f, 60f, 1f, 80f, 70f, 1f, 70f, 70f, 1f, 70f, 80f, 1f, 60f, 80f, 1f, 60f, 100f, 1f, 40f, 100f, 1f, 40f, 80f, 1f, 30f, 80f, 1f, 30f, 70f, 1f, 20f, 70f, 1f, 20f, 60f, 1f, 10f, 60f, 1f, 10f, 50f, 1f, 0f, 50f, 1f, 0f, 10f, 1f, 10f, 10f, 4f),
                floatArrayOf(0f, 10f, 10f, 1f, 22f, 10f, 1f, 22f, 18f, 1f, 16f, 18f, 1f, 16f, 26f, 1f, 10f, 26f, 4f),
                floatArrayOf(),
                0xFFFFFF, 0xFFFFFF, 0.75f, 0.95f, false, false),
            "puzzle" to KeyShapeArt(
                "拼圖", floatArrayOf(6f, 26f, 72f, 68f),
                floatArrayOf(0f, 10f, 20f, 1f, 38f, 20f, 2f, 34f, 12f, 38f, 2f, 50f, 2f, 2f, 62f, 2f, 66f, 12f, 62f, 20f, 1f, 90f, 20f, 3f, 100f, 20f, 100f, 30f, 1f, 100f, 44f, 2f, 92f, 40f, 84f, 44f, 84f, 56f, 2f, 84f, 68f, 92f, 72f, 100f, 68f, 1f, 100f, 90f, 3f, 100f, 100f, 90f, 100f, 1f, 10f, 100f, 3f, 0f, 100f, 0f, 90f, 1f, 0f, 30f, 3f, 0f, 20f, 10f, 20f, 4f),
                floatArrayOf(),
                floatArrayOf(),
                null, null, 0f, 1f, false, false),
            "book" to KeyShapeArt(
                "書本", floatArrayOf(8f, 20f, 84f, 62f),
                floatArrayOf(0f, 6f, 14f, 3f, 27f, 4f, 50f, 14f, 3f, 73f, 4f, 94f, 14f, 3f, 100f, 16f, 100f, 22f, 1f, 100f, 86f, 3f, 100f, 92f, 94f, 91f, 3f, 73f, 82f, 50f, 92f, 3f, 27f, 82f, 6f, 91f, 3f, 0f, 92f, 0f, 86f, 1f, 0f, 22f, 3f, 0f, 16f, 6f, 14f, 4f),
                floatArrayOf(0f, 49f, 16f, 3f, 50f, 15f, 51f, 16f, 1f, 51f, 89f, 3f, 50f, 90f, 49f, 89f, 4f, 0f, 2f, 92f, 3f, 26f, 83f, 50f, 93f, 3f, 74f, 83f, 98f, 92f, 3f, 100f, 93f, 99f, 95f, 3f, 74f, 88f, 50f, 98f, 3f, 26f, 88f, 1f, 95f, 3f, 0f, 93f, 2f, 92f, 4f),
                floatArrayOf(),
                0xB98A6A, 0xD7A983, 0.85f, 0.8f, false, false),
            "butterfly" to KeyShapeArt(
                "蝴蝶", floatArrayOf(14f, 26f, 72f, 46f),
                floatArrayOf(0f, 50f, 40f, 2f, 54f, 28f, 60f, 18f, 70f, 12f, 2f, 78f, 6f, 90f, 3f, 95f, 6f, 2f, 99f, 9f, 99f, 20f, 97f, 32f, 2f, 95f, 44f, 90f, 54f, 82f, 60f, 2f, 90f, 68f, 92f, 82f, 88f, 92f, 2f, 85f, 98f, 74f, 99f, 64f, 96f, 2f, 56f, 93f, 52f, 86f, 50f, 78f, 2f, 48f, 86f, 44f, 93f, 36f, 96f, 2f, 26f, 99f, 15f, 98f, 12f, 92f, 2f, 8f, 82f, 10f, 68f, 18f, 60f, 2f, 10f, 54f, 5f, 44f, 3f, 32f, 2f, 1f, 20f, 1f, 9f, 5f, 6f, 2f, 10f, 3f, 22f, 6f, 30f, 12f, 2f, 40f, 18f, 46f, 28f, 50f, 40f, 4f),
                floatArrayOf(0f, 53.5f, 60f, 2f, 53.5f, 69.94f, 51.93f, 78f, 50f, 78f, 2f, 48.07f, 78f, 46.5f, 69.94f, 46.5f, 60f, 2f, 46.5f, 50.06f, 48.07f, 42f, 50f, 42f, 2f, 51.93f, 42f, 53.5f, 50.06f, 53.5f, 60f, 4f),
                floatArrayOf(),
                0xB79CF0, 0xCDB8FF, 0.85f, 0.87f, false, false),
            "strawberry" to KeyShapeArt(
                "草莓", floatArrayOf(16f, 40f, 70f, 42f),
                floatArrayOf(0f, 50f, 22f, 2f, 66f, 18f, 88f, 18f, 96f, 34f, 2f, 102f, 48f, 96f, 66f, 84f, 80f, 2f, 74f, 92f, 62f, 99f, 52f, 99f, 2f, 42f, 99f, 30f, 94f, 20f, 84f, 2f, 8f, 72f, 2f, 56f, 4f, 42f, 2f, 6f, 28f, 18f, 22f, 30f, 21f, 2f, 38f, 20f, 44f, 21f, 50f, 22f, 4f, 0f, 45.65f, 19.67f, 2f, 46.34f, 22.91f, 39.89f, 27.03f, 31.25f, 28.87f, 2f, 22.6f, 30.71f, 15.04f, 29.57f, 14.35f, 26.33f, 2f, 13.66f, 23.09f, 20.11f, 18.97f, 28.75f, 17.13f, 2f, 37.4f, 15.29f, 44.96f, 16.43f, 45.65f, 19.67f, 4f, 0f, 81.65f, 24.33f, 2f, 80.96f, 27.57f, 73.4f, 28.71f, 64.75f, 26.87f, 2f, 56.11f, 25.03f, 49.66f, 20.91f, 50.35f, 17.67f, 2f, 51.04f, 14.43f, 58.6f, 13.29f, 67.25f, 15.13f, 2f, 75.89f, 16.97f, 82.34f, 21.09f, 81.65f, 24.33f, 4f, 0f, 56f, 30f, 2f, 56f, 37.18f, 51.97f, 43f, 47f, 43f, 2f, 42.03f, 43f, 38f, 37.18f, 38f, 30f, 2f, 38f, 22.82f, 42.03f, 17f, 47f, 17f, 2f, 51.97f, 17f, 56f, 22.82f, 56f, 30f, 4f, 0f, 44f, 4f, 3f, 48f, 1f, 52f, 4f, 1f, 50f, 16f, 1f, 46f, 16f, 4f),
                floatArrayOf(0f, 45.65f, 19.67f, 2f, 46.34f, 22.91f, 39.89f, 27.03f, 31.25f, 28.87f, 2f, 22.6f, 30.71f, 15.04f, 29.57f, 14.35f, 26.33f, 2f, 13.66f, 23.09f, 20.11f, 18.97f, 28.75f, 17.13f, 2f, 37.4f, 15.29f, 44.96f, 16.43f, 45.65f, 19.67f, 4f, 0f, 81.65f, 24.33f, 2f, 80.96f, 27.57f, 73.4f, 28.71f, 64.75f, 26.87f, 2f, 56.11f, 25.03f, 49.66f, 20.91f, 50.35f, 17.67f, 2f, 51.04f, 14.43f, 58.6f, 13.29f, 67.25f, 15.13f, 2f, 75.89f, 16.97f, 82.34f, 21.09f, 81.65f, 24.33f, 4f, 0f, 56f, 30f, 2f, 56f, 37.18f, 51.97f, 43f, 47f, 43f, 2f, 42.03f, 43f, 38f, 37.18f, 38f, 30f, 2f, 38f, 22.82f, 42.03f, 17f, 47f, 17f, 2f, 51.97f, 17f, 56f, 22.82f, 56f, 30f, 4f, 0f, 44f, 4f, 3f, 48f, 1f, 52f, 4f, 1f, 50f, 16f, 1f, 46f, 16f, 4f),
                floatArrayOf(),
                0x8CBF7A, 0xA2D190, 0.95f, 1.08f, false, false),
            "flower" to KeyShapeArt(
                "櫻花", floatArrayOf(28f, 34f, 44f, 34f),
                floatArrayOf(0f, 50f, 54f, 2f, 38f, 48f, 26f, 38f, 26f, 24f, 2f, 26f, 11f, 36f, 3f, 45f, 3f, 2f, 48f, 3f, 49f, 6f, 50f, 10f, 2f, 51f, 6f, 52f, 3f, 55f, 3f, 2f, 64f, 3f, 74f, 11f, 74f, 24f, 2f, 74f, 38f, 62f, 48f, 50f, 54f, 4f, 0f, 48.1f, 52.6f, 2f, 50.1f, 39.4f, 55.9f, 24.8f, 69.2f, 20.5f, 2f, 81.6f, 16.5f, 92.3f, 23.5f, 95.1f, 32.1f, 2f, 96f, 35f, 93.4f, 36.8f, 89.9f, 39f, 2f, 94.1f, 38.7f, 97.2f, 38.8f, 98.1f, 41.6f, 2f, 100.9f, 50.2f, 96.4f, 62.2f, 84f, 66.2f, 2f, 70.7f, 70.5f, 57.5f, 62.2f, 48.1f, 52.6f, 4f, 0f, 48.8f, 50.4f, 2f, 62.1f, 48.2f, 77.6f, 49.2f, 85.9f, 60.5f, 2f, 93.5f, 71.1f, 90.1f, 83.4f, 82.8f, 88.7f, 2f, 80.4f, 90.5f, 77.8f, 88.6f, 74.7f, 86f, 2f, 76.2f, 89.8f, 77.2f, 92.8f, 74.8f, 94.6f, 2f, 67.5f, 99.9f, 54.7f, 99.3f, 47f, 88.8f, 2f, 38.8f, 77.4f, 42.6f, 62.3f, 48.8f, 50.4f, 4f, 0f, 51.2f, 50.4f, 2f, 57.4f, 62.3f, 61.2f, 77.4f, 53f, 88.8f, 2f, 45.3f, 99.3f, 32.5f, 99.9f, 25.2f, 94.6f, 2f, 22.8f, 92.8f, 23.8f, 89.8f, 25.3f, 86f, 2f, 22.2f, 88.6f, 19.6f, 90.5f, 17.2f, 88.7f, 2f, 9.9f, 83.4f, 6.5f, 71.1f, 14.1f, 60.5f, 2f, 22.4f, 49.2f, 37.9f, 48.2f, 51.2f, 50.4f, 4f, 0f, 51.9f, 52.6f, 2f, 42.5f, 62.2f, 29.3f, 70.5f, 16f, 66.2f, 2f, 3.6f, 62.2f, -0.9f, 50.2f, 1.9f, 41.6f, 2f, 2.8f, 38.8f, 5.9f, 38.7f, 10.1f, 39f, 2f, 6.6f, 36.8f, 4f, 35f, 4.9f, 32.1f, 2f, 7.7f, 23.5f, 18.4f, 16.5f, 30.8f, 20.5f, 2f, 44.1f, 24.8f, 49.9f, 39.4f, 51.9f, 52.6f, 4f, 0f, 64f, 52f, 2f, 64f, 59.73f, 57.73f, 66f, 50f, 66f, 2f, 42.27f, 66f, 36f, 59.73f, 36f, 52f, 2f, 36f, 44.27f, 42.27f, 38f, 50f, 38f, 2f, 57.73f, 38f, 64f, 44.27f, 64f, 52f, 4f),
                floatArrayOf(0f, 56f, 52f, 2f, 56f, 55.31f, 53.31f, 58f, 50f, 58f, 2f, 46.69f, 58f, 44f, 55.31f, 44f, 52f, 2f, 44f, 48.69f, 46.69f, 46f, 50f, 46f, 2f, 53.31f, 46f, 56f, 48.69f, 56f, 52f, 4f),
                floatArrayOf(),
                0xF6CD5B, 0xF6D877, 0.95f, 0.86f, false, false),
            "moon" to KeyShapeArt(
                "月亮", floatArrayOf(14f, 26f, 60f, 48f),
                floatArrayOf(0f, 98f, 50f, 2f, 98f, 76.51f, 76.51f, 98f, 50f, 98f, 2f, 23.49f, 98f, 2f, 76.51f, 2f, 50f, 2f, 2f, 23.49f, 23.49f, 2f, 50f, 2f, 2f, 76.51f, 2f, 98f, 23.49f, 98f, 50f, 4f),
                floatArrayOf(0f, 62f, 6f, 2f, 84f, 12f, 98f, 30f, 98f, 50f, 2f, 98f, 74f, 80f, 94f, 56f, 98f, 2f, 72f, 86f, 80f, 70f, 80f, 50f, 2f, 80f, 32f, 74f, 16f, 62f, 6f, 4f, 0f, 26.79f, 16.61f, 1f, 27.85f, 18.75f, 3f, 28.65f, 20.36f, 30.42f, 20.62f, 1f, 32.79f, 20.96f, 3f, 34.56f, 21.22f, 33.28f, 22.47f, 1f, 31.56f, 24.14f, 3f, 30.28f, 25.39f, 30.58f, 27.16f, 1f, 30.99f, 29.51f, 3f, 31.29f, 31.28f, 29.7f, 30.45f, 1f, 27.59f, 29.33f, 3f, 26f, 28.5f, 24.41f, 29.33f, 1f, 22.3f, 30.45f, 3f, 20.71f, 31.28f, 21.01f, 29.51f, 1f, 21.42f, 27.16f, 3f, 21.72f, 25.39f, 20.44f, 24.14f, 1f, 18.72f, 22.47f, 3f, 17.44f, 21.22f, 19.21f, 20.96f, 1f, 21.58f, 20.62f, 3f, 23.35f, 20.36f, 24.15f, 18.75f, 1f, 25.21f, 16.61f, 3f, 26f, 15f, 26.79f, 16.61f, 4f),
                floatArrayOf(),
                null, null, 0.45f, 1f, false, false),
            "star" to KeyShapeArt(
                "星星", floatArrayOf(26f, 40f, 46f, 38f),
                floatArrayOf(0f, 58.73f, 14.49f, 1f, 60.67f, 16.82f, 3f, 69.4f, 27.3f, 82.07f, 32.36f, 1f, 84.88f, 33.49f, 3f, 97.55f, 38.55f, 90.28f, 50.09f, 1f, 88.66f, 52.66f, 3f, 81.38f, 64.2f, 80.49f, 77.81f, 1f, 80.29f, 80.84f, 3f, 79.39f, 94.45f, 66.16f, 91.1f, 1f, 63.23f, 90.35f, 3f, 50f, 87f, 36.77f, 90.35f, 1f, 33.84f, 91.1f, 3f, 20.61f, 94.45f, 19.71f, 80.84f, 1f, 19.51f, 77.81f, 3f, 18.62f, 64.2f, 11.34f, 52.66f, 1f, 9.72f, 50.09f, 3f, 2.45f, 38.55f, 15.12f, 33.49f, 1f, 17.93f, 32.36f, 3f, 30.6f, 27.3f, 39.33f, 16.82f, 1f, 41.27f, 14.49f, 3f, 50f, 4f, 58.73f, 14.49f, 4f, 0f, 84.06f, 64.47f, 1f, 85.82f, 67.44f, 3f, 87.88f, 70.91f, 91.81f, 71.79f, 1f, 95.18f, 72.55f, 3f, 99.12f, 73.44f, 96.46f, 76.47f, 1f, 94.17f, 79.06f, 3f, 91.51f, 82.09f, 91.88f, 86.11f, 1f, 92.21f, 89.55f, 3f, 92.58f, 93.56f, 88.88f, 91.97f, 1f, 85.7f, 90.6f, 3f, 82f, 89f, 78.3f, 90.6f, 1f, 75.12f, 91.97f, 3f, 71.42f, 93.56f, 71.79f, 89.55f, 1f, 72.12f, 86.11f, 3f, 72.49f, 82.09f, 69.83f, 79.06f, 1f, 67.54f, 76.47f, 3f, 64.88f, 73.44f, 68.82f, 72.55f, 1f, 72.19f, 71.79f, 3f, 76.12f, 70.91f, 78.18f, 67.44f, 1f, 79.94f, 64.47f, 3f, 82f, 61f, 84.06f, 64.47f, 4f),
                floatArrayOf(0f, 83.44f, 68.57f, 1f, 84.67f, 70.77f, 3f, 86.11f, 73.34f, 89f, 73.91f, 1f, 91.48f, 74.41f, 3f, 94.36f, 74.98f, 92.37f, 77.15f, 1f, 90.65f, 79f, 3f, 88.66f, 81.16f, 89f, 84.09f, 1f, 89.3f, 86.59f, 3f, 89.64f, 89.52f, 86.97f, 88.29f, 1f, 84.67f, 87.23f, 3f, 82f, 86f, 79.33f, 87.23f, 1f, 77.03f, 88.29f, 3f, 74.36f, 89.52f, 74.7f, 86.59f, 1f, 75f, 84.09f, 3f, 75.34f, 81.16f, 73.35f, 79f, 1f, 71.63f, 77.15f, 3f, 69.64f, 74.98f, 72.52f, 74.41f, 1f, 75f, 73.91f, 3f, 77.89f, 73.34f, 79.33f, 70.77f, 1f, 80.56f, 68.57f, 3f, 82f, 66f, 83.44f, 68.57f, 4f),
                floatArrayOf(),
                0xFFF3D6, 0xFFF3D6, 0.7f, 0.99f, false, false),
            "heart" to KeyShapeArt(
                "愛心", floatArrayOf(16f, 20f, 68f, 46f),
                floatArrayOf(0f, 50f, 20f, 2f, 52f, 12f, 58f, 6f, 68f, 6f, 2f, 84f, 6f, 96f, 18f, 96f, 38f, 2f, 96f, 62f, 76f, 80f, 57f, 92f, 2f, 53f, 95f, 47f, 95f, 43f, 92f, 2f, 24f, 80f, 4f, 62f, 4f, 38f, 2f, 4f, 18f, 16f, 6f, 32f, 6f, 2f, 42f, 6f, 48f, 12f, 50f, 20f, 4f),
                floatArrayOf(),
                floatArrayOf(),
                null, null, 0f, 0.92f, false, false),
            "latte" to KeyShapeArt(
                "拉花咖啡", floatArrayOf(18f, 52f, 52f, 38f),
                floatArrayOf(0f, 8f, 34f, 2f, 8f, 22f, 24f, 16f, 44f, 16f, 2f, 64f, 16f, 80f, 22f, 80f, 34f, 2f, 82f, 52f, 82f, 70f, 76f, 82f, 2f, 70f, 94f, 58f, 97f, 44f, 97f, 2f, 30f, 97f, 18f, 94f, 12f, 82f, 2f, 6f, 70f, 6f, 52f, 8f, 34f, 4f, 0f, 78f, 42f, 2f, 88f, 35f, 99f, 40f, 99f, 54f, 2f, 99f, 68f, 88f, 77f, 76f, 76f, 1f, 77f, 67f, 2f, 84f, 67f, 89f, 62f, 89f, 55f, 2f, 89f, 48f, 84f, 45f, 79f, 50f, 4f),
                floatArrayOf(0f, 75f, 32f, 2f, 75f, 39.46f, 61.12f, 45.5f, 44f, 45.5f, 2f, 26.88f, 45.5f, 13f, 39.46f, 13f, 32f, 2f, 13f, 24.54f, 26.88f, 18.5f, 44f, 18.5f, 2f, 61.12f, 18.5f, 75f, 24.54f, 75f, 32f, 4f, 0f, 44f, 37.5f, 2f, 50.5f, 33f, 54f, 29.5f, 52.2f, 26.2f, 2f, 50.4f, 23f, 46.4f, 23.4f, 44f, 26.8f, 2f, 41.6f, 23.4f, 37.6f, 23f, 35.8f, 26.2f, 2f, 34f, 29.5f, 37.5f, 33f, 44f, 37.5f, 4f, 0f, 44f, 41.5f, 2f, 52f, 41f, 59.5f, 37f, 61.5f, 30.5f, 2f, 57.5f, 35f, 51f, 38f, 44f, 39.3f, 2f, 37f, 38f, 30.5f, 35f, 26.5f, 30.5f, 2f, 28.5f, 37f, 36f, 41f, 44f, 41.5f, 4f, 0f, 44f, 44.6f, 2f, 50.5f, 44.4f, 56f, 42.6f, 58.5f, 40.3f, 2f, 54f, 42f, 49f, 42.9f, 44f, 42.9f, 2f, 39f, 42.9f, 34f, 42f, 29.5f, 40.3f, 2f, 32f, 42.6f, 37.5f, 44.4f, 44f, 44.6f, 4f),
                floatArrayOf(),
                0xB4774A, 0xC88A5C, 0.95f, 0.84f, false, false),
            "catLine" to KeyShapeArt(
                "貓咪探頭", floatArrayOf(14f, 26f, 72f, 58f),
                floatArrayOf(0f, 19f, 18f, 2f, 33f, 10f, 57f, 12f, 74f, 17f, 1f, 77f, 6f, 1f, 86f, 13f, 1f, 96f, 10f, 1f, 94f, 22f, 2f, 99f, 35f, 99f, 60f, 94f, 72f, 2f, 88f, 89f, 75f, 94f, 51f, 94f, 2f, 26f, 94f, 10f, 85f, 9f, 63f, 2f, 8f, 44f, 10f, 27f, 19f, 18f, 4f),
                floatArrayOf(0f, 84.15f, 22.4f, 2f, 84.15f, 23.04f, 83.64f, 23.55f, 83f, 23.55f, 2f, 82.36f, 23.55f, 81.85f, 23.04f, 81.85f, 22.4f, 2f, 81.85f, 21.76f, 82.36f, 21.25f, 83f, 21.25f, 2f, 83.64f, 21.25f, 84.15f, 21.76f, 84.15f, 22.4f, 4f, 0f, 92.15f, 22.4f, 2f, 92.15f, 23.04f, 91.64f, 23.55f, 91f, 23.55f, 2f, 90.36f, 23.55f, 89.85f, 23.04f, 89.85f, 22.4f, 2f, 89.85f, 21.76f, 90.36f, 21.25f, 91f, 21.25f, 2f, 91.64f, 21.25f, 92.15f, 21.76f, 92.15f, 22.4f, 4f, 0f, 24.8f, 84f, 2f, 24.4f, 81.6f, 26.4f, 80f, 28f, 81.5f, 2f, 29.8f, 79.9f, 31.8f, 81.6f, 31.3f, 84f, 2f, 31.1f, 86.2f, 29.7f, 87f, 28f, 86.7f, 2f, 26.3f, 87f, 24.9f, 86.2f, 24.8f, 84f, 4f, 0f, 25.22f, 77.99f, 2f, 25.55f, 78.81f, 25.36f, 79.66f, 24.8f, 79.88f, 2f, 24.24f, 80.11f, 23.51f, 79.63f, 23.18f, 78.81f, 2f, 22.85f, 77.99f, 23.04f, 77.14f, 23.6f, 76.92f, 2f, 24.16f, 76.69f, 24.89f, 77.17f, 25.22f, 77.99f, 4f, 0f, 28.6f, 77.4f, 2f, 28.6f, 78.26f, 28.11f, 78.95f, 27.5f, 78.95f, 2f, 26.89f, 78.95f, 26.4f, 78.26f, 26.4f, 77.4f, 2f, 26.4f, 76.54f, 26.89f, 75.85f, 27.5f, 75.85f, 2f, 28.11f, 75.85f, 28.6f, 76.54f, 28.6f, 77.4f, 4f, 0f, 31.93f, 78.79f, 2f, 31.61f, 79.62f, 30.89f, 80.11f, 30.33f, 79.89f, 2f, 29.76f, 79.68f, 29.56f, 78.83f, 29.87f, 78.01f, 2f, 30.19f, 77.18f, 30.91f, 76.69f, 31.47f, 76.91f, 2f, 32.04f, 77.12f, 32.24f, 77.97f, 31.93f, 78.79f, 4f, 0f, 72.8f, 84f, 2f, 72.4f, 81.6f, 74.4f, 80f, 76f, 81.5f, 2f, 77.8f, 79.9f, 79.8f, 81.6f, 79.3f, 84f, 2f, 79.1f, 86.2f, 77.7f, 87f, 76f, 86.7f, 2f, 74.3f, 87f, 72.9f, 86.2f, 72.8f, 84f, 4f, 0f, 73.22f, 77.99f, 2f, 73.55f, 78.81f, 73.36f, 79.66f, 72.8f, 79.88f, 2f, 72.24f, 80.11f, 71.51f, 79.63f, 71.18f, 78.81f, 2f, 70.85f, 77.99f, 71.04f, 77.14f, 71.6f, 76.92f, 2f, 72.16f, 76.69f, 72.89f, 77.17f, 73.22f, 77.99f, 4f, 0f, 76.6f, 77.4f, 2f, 76.6f, 78.26f, 76.11f, 78.95f, 75.5f, 78.95f, 2f, 74.89f, 78.95f, 74.4f, 78.26f, 74.4f, 77.4f, 2f, 74.4f, 76.54f, 74.89f, 75.85f, 75.5f, 75.85f, 2f, 76.11f, 75.85f, 76.6f, 76.54f, 76.6f, 77.4f, 4f, 0f, 79.93f, 78.79f, 2f, 79.61f, 79.62f, 78.89f, 80.11f, 78.33f, 79.89f, 2f, 77.76f, 79.68f, 77.56f, 78.83f, 77.87f, 78.01f, 2f, 78.19f, 77.18f, 78.91f, 76.69f, 79.47f, 76.91f, 2f, 80.04f, 77.12f, 80.24f, 77.97f, 79.93f, 78.79f, 4f),
                floatArrayOf(0f, 19f, 18f, 2f, 12f, 20f, 6f, 17f, 7f, 12f, 2f, 8f, 7f, 12f, 7f, 13f, 11f, 2f, 14f, 13f, 11f, 15f, 10f, 12f, 0f, 79f, 24f, 1f, 74f, 23f, 0f, 79f, 29f, 1f, 74f, 30f, 0f, 94f, 24f, 1f, 98f, 23f, 0f, 94f, 29f, 1f, 99f, 30f, 0f, 88.7f, 27f, 3f, 87f, 29f, 85.3f, 27f, 0f, 87f, 26.5f, 1f, 87f, 27.5f),
                null, null, 1f, 0.86f, true, true),
            "circle" to KeyShapeArt(
                "圓形", floatArrayOf(12f, 12f, 76f, 76f),
                floatArrayOf(0f, 49f, 0f, 1f, 51f, 0f, 2f, 78f, 0f, 100f, 22f, 100f, 50f, 2f, 100f, 78f, 78f, 100f, 51f, 100f, 1f, 49f, 100f, 2f, 22f, 100f, 0f, 78f, 0f, 50f, 2f, 0f, 22f, 22f, 0f, 49f, 0f, 4f),
                floatArrayOf(),
                floatArrayOf(),
                null, null, 0f, 1f, true, false),
            "chamfer" to KeyShapeArt(
                "削角", floatArrayOf(8f, 12f, 84f, 72f),
                floatArrayOf(0f, 3f, 0f, 1f, 97f, 0f, 3f, 100f, 0f, 100f, 3f, 1f, 100f, 84f, 1f, 84f, 100f, 1f, 3f, 100f, 3f, 0f, 100f, 0f, 97f, 1f, 0f, 3f, 3f, 0f, 0f, 3f, 0f, 4f),
                floatArrayOf(),
                floatArrayOf(0f, 3f, 0f, 1f, 97f, 0f, 3f, 100f, 0f, 100f, 3f, 1f, 100f, 84f, 1f, 84f, 100f, 1f, 3f, 100f, 3f, 0f, 100f, 0f, 97f, 1f, 0f, 3f, 3f, 0f, 0f, 3f, 0f, 4f, 0f, 12f, 90f, 1f, 24f, 90f),
                null, null, 0f, 1.2f, true, false),
        )

        /** 0 = 移到、1 = 直線、2 = 三次曲線、3 = 二次曲線、4 = 收尾 */
        /** ends：寬鍵拉長時，左右兩端的設計寬度（x 小於 50 貼左邊、大於 50 貼右邊） */
        fun build(ops: FloatArray, r: RectF, ends: Float?): Path {
            val p = Path()
            fun x(k: Int): Float {
                val v = ops[k]
                if (ends == null) return r.left + r.width() * v / 100
                return if (v < 50) r.left + ends * v / 100 else r.right - ends * (100 - v) / 100
            }
            fun y(k: Int) = r.top + r.height() * ops[k] / 100
            var i = 0
            while (i < ops.size) {
                when (ops[i].toInt()) {
                    0 -> { p.moveTo(x(i + 1), y(i + 2)); i += 3 }
                    1 -> { p.lineTo(x(i + 1), y(i + 2)); i += 3 }
                    2 -> { p.cubicTo(x(i + 1), y(i + 2), x(i + 3), y(i + 4), x(i + 5), y(i + 6)); i += 7 }
                    3 -> { p.quadTo(x(i + 1), y(i + 2), x(i + 3), y(i + 4)); i += 5 }
                    else -> { p.close(); i += 1 }
                }
            }
            return p
        }
    }
}
