package com.startown.starkeyboard.ime

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.View
import android.widget.LinearLayout
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.vision.digitalink.DigitalInkRecognition
import com.google.mlkit.vision.digitalink.DigitalInkRecognitionModel
import com.google.mlkit.vision.digitalink.DigitalInkRecognitionModelIdentifier
import com.google.mlkit.vision.digitalink.DigitalInkRecognizer
import com.google.mlkit.vision.digitalink.DigitalInkRecognizerOptions
import com.google.mlkit.vision.digitalink.Ink

/** Google ML Kit 手寫辨識（第一次要下載繁中辨識資料，約 20MB，之後不用網路） */
class InkRecognizer(private val onStatus: (String) -> Unit) {
    private var model: DigitalInkRecognitionModel? = null
    private var recognizer: DigitalInkRecognizer? = null
    private var ready = false
    private var downloading = false

    fun prepare() {
        if (ready || downloading) return
        val id = listOf("zh-Hani-TW", "zh-TW", "zh-Hant").firstNotNullOfOrNull { tag ->
            runCatching { DigitalInkRecognitionModelIdentifier.fromLanguageTag(tag) }.getOrNull()
        } ?: run {
            onStatus("這支手機不支援繁中手寫辨識")
            return
        }
        val m = DigitalInkRecognitionModel.builder(id).build()
        model = m
        val manager = RemoteModelManager.getInstance()
        downloading = true
        manager.isModelDownloaded(m).addOnSuccessListener { downloaded ->
            if (downloaded) {
                finish(m)
            } else {
                onStatus("第一次用手寫，正在下載辨識資料（約 20MB）…")
                manager.download(m, DownloadConditions.Builder().build())
                    .addOnSuccessListener { finish(m); onStatus("手寫辨識準備好了 ✍︎") }
                    .addOnFailureListener { downloading = false; onStatus("下載手寫辨識資料失敗，請確認網路後再試") }
            }
        }.addOnFailureListener { downloading = false; onStatus("手寫辨識資料讀不到：${it.localizedMessage ?: "原因不明"}") }
    }

    private fun finish(m: DigitalInkRecognitionModel) {
        recognizer = DigitalInkRecognition.getClient(DigitalInkRecognizerOptions.builder(m).build())
        ready = true
        downloading = false
    }

    fun recognize(strokes: List<List<FloatArray>>, width: Float, height: Float, done: (List<String>) -> Unit) {
        val r = recognizer
        if (!ready || r == null) {
            prepare()
            if (!downloading) onStatus("手寫辨識還沒準備好，請稍等再寫一次")
            done(emptyList())
            return
        }
        val ink = Ink.builder()
        for (stroke in strokes) {
            val b = Ink.Stroke.builder()
            for (p in stroke) b.addPoint(Ink.Point.create(p[0], p[1], p[2].toLong()))
            ink.addStroke(b.build())
        }
        val context = com.google.mlkit.vision.digitalink.RecognitionContext.builder()
            .setPreContext("")
            .setWritingArea(com.google.mlkit.vision.digitalink.WritingArea(width, height))
            .build()
        r.recognize(ink.build(), context)
            .addOnSuccessListener { result ->
                val out = result.candidates.map { it.text }.filter { it.isNotBlank() }.distinct()
                if (out.isEmpty()) onStatus("沒認出來，寫大一點、一筆一筆分開一點再試試")
                done(out)
            }
            .addOnFailureListener { onStatus("手寫辨識出錯：${it.localizedMessage ?: "原因不明"}"); done(emptyList()) }
    }

    fun close() {
        recognizer?.close()
    }
}

/** 手寫畫面：左邊寫字，右邊一排功能鍵 */
@SuppressLint("ViewConstructor", "ClickableViewAccessibility")
class HandwritingPanel(context: Context, style: KeyboardStyle, private val recognizer: InkRecognizer) : LinearLayout(context) {
    var onResult: ((List<String>) -> Unit)? = null
    /** 上一個字辨識完後又開始寫新的字：先把第一個候選字送出 */
    var onAutoCommit: (() -> Unit)? = null
    val side = KeyboardView(context, style)
    var style = style
        set(value) {
            field = value
            side.style = value
            canvasView.invalidate()
        }

    private val strokes = ArrayList<ArrayList<FloatArray>>()
    private var lastResults: List<String> = emptyList()
    private var lastStrokeEnd = 0L
    private var baseTime = 0L   // 筆畫時間用相對時間（float 放不下完整的毫秒數）
    private var token = 0
    private val mainHandler = Handler(Looper.getMainLooper())
    private val recognizeRunnable = Runnable { recognize() }

    private val canvasView = object : View(context) {
        private val bg = Paint(Paint.ANTI_ALIAS_FLAG)
        private val ink = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            setStyle(Paint.Style.STROKE); strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
        }
        private val hint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER }

        override fun onDraw(canvas: Canvas) {
            val t = this@HandwritingPanel.style.theme
            bg.color = t.key.withAlpha(this@HandwritingPanel.style.keyAlpha * 0.55f)
            canvas.drawRoundRect(RectF(0f, 0f, width.toFloat(), height.toFloat()), dp(14f), dp(14f), bg)
            if (strokes.isEmpty()) {
                hint.color = t.keyText.withAlpha(0.3f)
                hint.textSize = dp(20f)
                canvas.drawText("在這裡寫字 ✍︎", width / 2f, height / 2f, hint)
            }
            ink.color = t.keyText
            ink.strokeWidth = dp(5f)
            for (s in strokes) {
                if (s.isEmpty()) continue
                val path = Path()
                path.moveTo(s[0][0], s[0][1])
                if (s.size == 1) path.lineTo(s[0][0] + 0.5f, s[0][1] + 0.5f)
                for (p in s.drop(1)) path.lineTo(p[0], p[1])
                canvas.drawPath(path, ink)
            }
        }
    }

    init {
        orientation = HORIZONTAL
        setPadding(dpi(6f), dpi(6f), dpi(2f), dpi(6f))
        addView(canvasView, LayoutParams(0, LayoutParams.MATCH_PARENT, 1f))
        addView(side, LayoutParams(dpi(84f), LayoutParams.MATCH_PARENT).apply { leftMargin = dpi(4f) })
        canvasView.setOnTouchListener { _, e -> touch(e); true }
        recognizer.prepare()
    }

    private fun touch(e: MotionEvent) {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                mainHandler.removeCallbacks(recognizeRunnable)
                if (strokes.isNotEmpty() && lastResults.isNotEmpty() && System.currentTimeMillis() - lastStrokeEnd > 1200) {
                    onAutoCommit?.invoke()
                    clear()
                }
                if (strokes.isEmpty()) baseTime = e.eventTime
                strokes.add(arrayListOf(floatArrayOf(e.x, e.y, (e.eventTime - baseTime).toFloat())))
            }
            MotionEvent.ACTION_MOVE -> {
                val s = strokes.lastOrNull() ?: return
                for (h in 0 until e.historySize) s.add(floatArrayOf(e.getHistoricalX(h), e.getHistoricalY(h), (e.getHistoricalEventTime(h) - baseTime).toFloat()))
                s.add(floatArrayOf(e.x, e.y, (e.eventTime - baseTime).toFloat()))
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                lastStrokeEnd = System.currentTimeMillis()
                mainHandler.postDelayed(recognizeRunnable, 450)
            }
        }
        canvasView.invalidate()
    }

    fun clear() {
        strokes.clear()
        lastResults = emptyList()
        token++
        mainHandler.removeCallbacks(recognizeRunnable)
        canvasView.invalidate()
    }

    private fun recognize() {
        val current = ++token
        val snapshot = strokes.map { s -> s.map { it.copyOf() } }
        recognizer.recognize(snapshot, canvasView.width.toFloat(), canvasView.height.toFloat()) { results ->
            if (token != current) return@recognize
            lastResults = results
            onResult?.invoke(results)
        }
    }
}
