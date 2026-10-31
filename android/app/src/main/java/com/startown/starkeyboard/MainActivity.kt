package com.startown.starkeyboard

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.PointF
import android.media.FaceDetector
import android.graphics.Typeface
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import com.startown.starkeyboard.core.EmoticonStore
import com.startown.starkeyboard.core.ReleaseChecker
import com.startown.starkeyboard.ime.BuildInfo
import com.startown.starkeyboard.ime.KeyboardSettings
import com.startown.starkeyboard.ime.UpdateFetcher
import java.io.ByteArrayOutputStream

/** 外殼 App：開啟鍵盤的步驟、試打、挑背景照片、做貼圖、檢查新版 */
class MainActivity : Activity() {
    companion object {
        const val EXTRA_PICK = "pick"
        const val PICK_BACKGROUND = 1
        const val PICK_STICKER = 2
    }

    private val pink = Color.parseColor("#E8577E")
    private lateinit var col: LinearLayout
    private lateinit var updateBox: LinearLayout
    private lateinit var tryBox: EditText
    private val dp get() = resources.displayMetrics.density

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Color.parseColor("#FFF6F8")
        col = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(px(20f), px(24f), px(20f), px(40f))
            setBackgroundColor(Color.parseColor("#FFF6F8"))
        }
        setContentView(ScrollView(this).apply { setBackgroundColor(Color.parseColor("#FFF6F8")); addView(col) })
        build()
        intent?.getIntExtra(EXTRA_PICK, 0)?.takeIf { it != 0 }?.let { pick(it) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent?.getIntExtra(EXTRA_PICK, 0)?.takeIf { it != 0 }?.let { pick(it) }
    }

    private fun px(v: Float) = (v * dp).toInt()

    private fun title(s: String, size: Float = 20f) = col.addView(TextView(this).apply {
        text = s; textSize = size; setTextColor(Color.parseColor("#43262F")); typeface = Typeface.DEFAULT_BOLD
        setPadding(0, px(18f), 0, px(6f))
    })

    private fun text(s: String, parent: LinearLayout = col) = parent.addView(TextView(this).apply {
        text = s; textSize = 15f; setTextColor(Color.parseColor("#5B3A45")); setLineSpacing(0f, 1.25f)
        setPadding(0, px(3f), 0, px(3f))
    })

    private fun button(s: String, parent: LinearLayout = col, action: () -> Unit) = parent.addView(Button(this).apply {
        text = s; isAllCaps = false; setTextColor(Color.WHITE); textSize = 15f
        background = android.graphics.drawable.GradientDrawable().apply { setColor(pink); cornerRadius = 24 * dp }
        setOnClickListener { action() }
    }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, px(48f)).apply { topMargin = px(8f) })

    /** 版本那一格：檢查中／已經是最新版／有新版／連不上，都可以再檢查一次 */
    private fun checkUpdate() {
        updateBox.removeAllViews()
        text("正在檢查有沒有新版…", updateBox)
        UpdateFetcher.fetch { info ->
            updateBox.removeAllViews()
            val current = BuildInfo.current(this)
            when {
                info == null -> text("⚠️ 沒辦法檢查新版（可能沒有網路），等一下再試一次。", updateBox)
                info.build > current -> {
                    KeyboardSettings(this).latestBuild = info.build
                    updateBox.addView(TextView(this).apply {
                        text = "🎉 有新版：${info.title}（第 ${info.build} 版）"; textSize = 18f; typeface = Typeface.DEFAULT_BOLD; setTextColor(pink)
                        setPadding(0, px(16f), 0, px(4f))
                    })
                    text(info.notes, updateBox)
                    text("按下面的按鈕下載 APK。目前要先移除舊版（長按糯糯鍵盤圖示 › 解除安裝）再點開新的安裝檔安裝，裝好後要重新選一次鍵盤。", updateBox)
                    button("下載新版", updateBox) {
                        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(info.apkUrl ?: info.pageUrl)))
                    }
                }
                current == 0 -> text("這是自己在電腦上編的測試版，沒辦法比對版本。", updateBox)
                else -> updateBox.addView(TextView(this).apply {
                    text = "✅ 已經是最新版"; textSize = 16f; typeface = Typeface.DEFAULT_BOLD; setTextColor(Color.parseColor("#2F8F6B"))
                    setPadding(0, px(8f), 0, px(2f))
                })
            }
            button("再檢查一次", updateBox) { checkUpdate() }
        }
    }

    private fun build() {
        col.addView(TextView(this).apply {
            text = "糯糯鍵盤"; textSize = 30f; typeface = Typeface.DEFAULT_BOLD; setTextColor(Color.parseColor("#43262F"))
        })
        text("注音、手寫、英文、韓文、日文、表符、顏文字、剪貼簿、翻譯，還有可愛的主題。")
        val current = BuildInfo.current(this)
        text(if (current > 0) "目前版本 v${BuildInfo.version(this)}（第 $current 版）" else "目前版本 v${BuildInfo.version(this)}")

        button("語音轉文字") { startActivity(Intent(this, VoiceInputActivity::class.java)) }
        button("剪貼簿匯入／匯出") { startActivity(Intent(this, ClipboardTransferActivity::class.java)) }
        updateBox = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        col.addView(updateBox)
        checkUpdate()

        button("隱私與安全") { PrivacySafety.show(this) }
        text("剪貼簿與外部翻譯預設關閉。使用前請了解保存內容與連網風險。")
        showCrashLog()

        title("第一次使用：打開鍵盤")
        text("1. 按下面的按鈕，在清單裡打開「糯糯鍵盤」（手機會提醒第三方鍵盤可能讀取你打的字，按確定）")
        button("① 打開鍵盤設定") { startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS)) }
        text("2. 再按一次，選「糯糯鍵盤」當目前的鍵盤")
        button("② 切換成糯糯鍵盤") { (getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager).showInputMethodPicker() }
        text("3. 在下面試打看看")
        tryBox = EditText(this).apply {
            hint = "在這裡試試新鍵盤"
            minLines = 2
            gravity = Gravity.TOP
        }
        col.addView(tryBox, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { topMargin = px(6f) })

        title("背景照片與自製貼圖")
        button("新增一張背景照片") { pick(PICK_BACKGROUND) }
        text("可以放好幾張，在鍵盤的 ⚙ 設定裡選要用哪張，或設定每天、每次打開自動換。")
        button("拿掉全部背景照片") {
            KeyboardSettings(this).clearPhotos()
            toast("已拿掉全部背景照片")
        }
        button("挑一張照片做成貼圖") { pick(PICK_STICKER) }
        text("貼圖會出現在鍵盤的 ☺ 表符 › ⭐ 我的。支援傳圖片的 App（像 LINE、Messenger）會直接送出圖片，不支援的會先複製，再長按貼上。")

        title("使用小提醒")
        text("• 注音是大千排列。空白鍵＝一聲；打完按空白送出整句，或點上面的候選字一段一段選。")
        text("• 拼音：給習慣漢語拼音的人（例如馬來西亞朋友）。到鍵盤 ⚙ 設定 › 輸入法打開「拼音」，打 nihao 或只打聲母 nh 就出「你好」，預設繁體字（設定裡可以改簡體）。")
        text("• 按住「中／英」鍵可以換回別的鍵盤。按住空白鍵左右滑可以移動游標。")
        text("• 手寫：第一次用會下載 Google 的手寫辨識資料（約 20MB），之後不用網路。")
        text("• 翻譯：工具列的「譯」。第一次翻譯某個語言要下載資料。")
        text("• 剪貼簿：自動記錄預設關閉，可在鍵盤 ⚙ → 隱私與安全開啟；不要保存密碼或驗證碼。")
        text("• 大小、主題、按鍵造型都在鍵盤的 ⚙ 設定裡調。")
        text("• 所有版本：${ReleaseChecker.PAGE}")
    }

    /** 鍵盤當掉或出錯過：把紀錄顯示出來，可以複製傳給開發的人 */
    private fun showCrashLog() {
        val f = CrashLog.file(this)
        if (!f.exists() || f.length() == 0L) return
        val log = f.readText()
        title("⚠️ 鍵盤出過問題")
        text("請按「複製紀錄」貼給開發的人（或截圖這段），會比較快找到原因。")
        col.addView(TextView(this).apply {
            text = log.take(1500); textSize = 11f; setTextColor(Color.parseColor("#7A4A55")); setTextIsSelectable(true)
            setBackgroundColor(Color.parseColor("#FFE9EE")); setPadding(px(10f), px(8f), px(10f), px(8f))
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { topMargin = px(6f) })
        button("複製紀錄") {
            (getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager)
                .setPrimaryClip(android.content.ClipData.newPlainText("糯糯鍵盤紀錄", log))
            toast("已複製")
        }
        button("清除紀錄") {
            f.delete()
            toast("已清除，重新打開 App 就不會顯示")
        }
    }

    private fun pick(what: Int) {
        val intent = Intent(Intent.ACTION_GET_CONTENT).setType("image/*").addCategory(Intent.CATEGORY_OPENABLE)
        @Suppress("DEPRECATION")
        startActivityForResult(Intent.createChooser(intent, "挑一張照片"), what)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        val uri = data?.data ?: return
        if (resultCode != RESULT_OK) return
        val bitmap = load(uri, if (requestCode == PICK_STICKER) 512 else 1000) ?: run {
            toast("讀不到這張照片")
            return
        }
        when (requestCode) {
            PICK_BACKGROUND -> {
                val s = KeyboardSettings(this)
                // 對準臉；找不到臉就偏上面一點（人像的頭通常在上面）
                val face = faceCenter(bitmap)
                s.addPhoto(face?.first ?: 0.5f, face?.second ?: 0.3f) { f ->
                    f.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 85, it) }
                }
                // 接著叫出鍵盤，直接在鍵盤上拖拉、縮放照片
                s.adjustPhotoPending = true
                tryBox.requestFocus()
                tryBox.post {
                    (getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager).showSoftInput(tryBox, 0)
                    (col.parent as? ScrollView)?.smoothScrollTo(0, tryBox.top)
                }
                toast("換好背景了！在鍵盤上拖拉、兩指縮放照片，好了按「完成」")
            }
            PICK_STICKER -> {
                val out = ByteArrayOutputStream()
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
                EmoticonStore(filesDir).addSticker(out.toByteArray())
                toast("做好貼圖了！在鍵盤的 ☺ › ⭐ 我的")
            }
        }
    }

    /** 照片裡最大那張臉的中心（0～1）；找不到回傳 null（手機內建的臉部偵測，畫的人物可能找不到） */
    private fun faceCenter(bitmap: Bitmap): Pair<Float, Float>? = runCatching {
        val w = bitmap.width and 1.inv()   // 偵測器要偶數寬
        val img = Bitmap.createBitmap(bitmap, 0, 0, w, bitmap.height).copy(Bitmap.Config.RGB_565, false)
        val faces = arrayOfNulls<FaceDetector.Face>(5)
        val n = FaceDetector(img.width, img.height, faces.size).findFaces(img, faces)
        val face = faces.take(n).filterNotNull().maxByOrNull { it.eyesDistance() } ?: return null
        val eyes = PointF()
        face.getMidPoint(eyes)
        // 兩眼中間往下一點是臉的中間
        (eyes.x / img.width).coerceIn(0f, 1f) to ((eyes.y + face.eyesDistance() * 0.4f) / img.height).coerceIn(0f, 1f)
    }.getOrNull()

    /** 讀照片並縮小到最長邊 maxSide */
    private fun load(uri: Uri, maxSide: Int): Bitmap? = runCatching {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxSide) sample *= 2
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        val raw = contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, opts) } ?: return null
        val scale = minOf(1f, maxSide.toFloat() / maxOf(raw.width, raw.height))
        if (scale >= 1f) raw else Bitmap.createScaledBitmap(raw, (raw.width * scale).toInt(), (raw.height * scale).toInt(), true)
    }.getOrNull()

    private fun toast(s: String) = Toast.makeText(this, s, Toast.LENGTH_SHORT).show()
}
