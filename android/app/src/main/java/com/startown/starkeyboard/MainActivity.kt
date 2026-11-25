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
        const val PICK_FONT = 3
        const val PICK_SPACE = 4
    }

    private val pink = Color.parseColor("#E8577E")
    private lateinit var col: LinearLayout
    private lateinit var updateBox: LinearLayout
    private lateinit var tryBox: EditText
    private val dp get() = resources.displayMetrics.density
    private lateinit var scroll: ScrollView
    private lateinit var tabBar: LinearLayout
    private lateinit var looks: LookTabs
    /** 下面的分頁：首頁、主題、按鍵、字體、聲音 */
    private var tab = 0
    private val tabs = listOf("🏠" to "首頁", "🎨" to "主題", "⌨️" to "按鍵", "🔤" to "字體", "🔊" to "聲音")

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Color.parseColor("#FFF6F8")
        col = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(px(20f), px(24f), px(20f), px(40f))
            setBackgroundColor(Color.parseColor("#FFF6F8"))
        }
        scroll = ScrollView(this).apply { setBackgroundColor(Color.parseColor("#FFF6F8")); addView(col) }
        tabBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setBackgroundColor(Color.WHITE)
            elevation = 8 * dp
        }
        setContentView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(scroll, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
            addView(tabBar, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, px(60f)))
        })
        looks = LookTabs(this, col) { showTab(tab, keepScroll = true) }
        showTab(0)
        intent?.getIntExtra(EXTRA_PICK, 0)?.takeIf { it != 0 }?.let { pick(it) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent?.getIntExtra(EXTRA_PICK, 0)?.takeIf { it != 0 }?.let { if (tab != 0) showTab(0); pick(it) }
    }

    /** 換分頁（keepScroll：同一頁重畫時留在原本捲到的地方） */
    private fun showTab(index: Int, keepScroll: Boolean = false) {
        if (isFinishing || isDestroyed) return
        val y = if (keepScroll && index == tab) scroll.scrollY else 0
        tab = index
        col.removeAllViews()
        when (index) {
            1 -> looks.themes()
            2 -> looks.keys()
            3 -> looks.fonts()
            4 -> looks.sounds()
            else -> build()
        }
        scroll.post { scroll.scrollTo(0, y) }
        tabBar.removeAllViews()
        for ((i, t) in tabs.withIndex()) {
            val on = i == tab
            tabBar.addView(TextView(this).apply {
                text = "${t.first}\n${t.second}"; textSize = 12f; gravity = Gravity.CENTER
                setTextColor(if (on) pink else Color.parseColor("#7A5A64"))
                typeface = if (on) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
                setOnClickListener { if (i != tab) showTab(i) }
            }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1f))
        }
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

    /** 一條滑桿；回傳（滑桿, 把滑桿移到某個值） */
    private fun lookSlider(title: String, value: Float, lo: Float, hi: Float, set: (Float) -> Unit): Pair<android.widget.SeekBar, (Float) -> Unit> {
        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        row.addView(TextView(this).apply { text = title; textSize = 15f; setTextColor(Color.parseColor("#5B3A45")) },
            LinearLayout.LayoutParams(px(96f), LinearLayout.LayoutParams.WRAP_CONTENT))
        val seek = android.widget.SeekBar(this).apply {
            max = 100
            progress = (((value - lo) / (hi - lo)) * 100).toInt().coerceIn(0, 100)
            setOnSeekBarChangeListener(object : android.widget.SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(s: android.widget.SeekBar, p: Int, fromUser: Boolean) {
                    if (fromUser) set(lo + (hi - lo) * p / 100f)
                }
                override fun onStartTrackingTouch(s: android.widget.SeekBar) {}
                override fun onStopTrackingTouch(s: android.widget.SeekBar) {}
            })
        }
        row.addView(seek, LinearLayout.LayoutParams(0, px(44f), 1f))
        col.addView(row)
        return seek to { v: Float -> seek.progress = (((v - lo) / (hi - lo)) * 100).toInt().coerceIn(0, 100) }
    }

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
                    updateBox.addView(TextView(this).apply {
                        text = "直接下載安裝就能蓋過舊版，設定和剪貼簿都會留著，不用刪舊版。"
                        textSize = 15f; typeface = Typeface.DEFAULT_BOLD; setTextColor(Color.parseColor("#B5612A"))
                        setPadding(0, px(6f), 0, px(4f))
                    })
                    text("下載後到「檔案」App 的下載資料夾點新的安裝檔，按「更新」。想保險的話可以先備份剪貼簿（不一定要）。", updateBox)
                    button("備份剪貼簿（存成檔案，可以不做）", updateBox) { startActivity(Intent(this, ClipboardTransferActivity::class.java)) }
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

        // 邊調邊看：App 和鍵盤共用同一份設定，拖滑桿時鍵盤馬上跟著變
        title("大小與透明度（邊調邊看）")
        text("先點上面「在這裡試試新鍵盤」的框叫出糯糯鍵盤，再拖滑桿，鍵盤會馬上跟著變。")
        val ks = KeyboardSettings(this)
        val sliders = listOf(
            lookSlider("鍵盤高度", ks.heightScale, 0.8f, 1.3f) { ks.heightScale = it },
            lookSlider("字的大小", ks.fontScale, 0.8f, 1.4f) { ks.fontScale = it },
            lookSlider("按鍵間距", ks.gapScale, 0.3f, 1.6f) { ks.gapScale = it },
            lookSlider("造型大小", ks.shapeScale, 0.9f, 1.6f) { ks.shapeScale = it },
            lookSlider("按鍵透明度", ks.keyAlpha, 0f, 1f) { ks.keyAlpha = it },
            lookSlider("照片淡化", ks.backgroundFade, 0f, 0.9f) { ks.backgroundFade = it },
        )
        button("大小恢復預設") {
            ks.heightScale = 1f; ks.fontScale = 1f; ks.gapScale = 1f; ks.shapeScale = 1.15f
            listOf(1f, 1f, 1f, 1.15f).forEachIndexed { i, v -> sliders[i].second(v) }
        }

        title("背景照片與自製貼圖")
        button("新增背景照片（可以一次挑好幾張）") { pick(PICK_BACKGROUND) }
        text("可以放好幾張，在鍵盤的 ⚙ 設定裡選要用哪張，或設定每天、每次打開自動換。")
        button("拿掉全部背景照片") {
            KeyboardSettings(this).clearPhotos()
            toast("已拿掉全部背景照片")
        }
        button("挑一張照片做成貼圖") { pick(PICK_STICKER) }
        text("貼圖會出現在鍵盤的 ☺ 表符 › ⭐ 我的。支援傳圖片的 App（像 LINE、Messenger）會直接送出圖片，不支援的會先複製，再長按貼上。")

        title("空白鍵圖案")
        button("挑圖片或 GIF 做成空白鍵的小圖") { pick(PICK_SPACE) }
        text("照片可以選自動去背；GIF 會保持會動（Android 9 以上）。之後在鍵盤 ⚙ 設定 › 空白鍵 可以換回主題符號或改用表符。")

        title("我的字體")
        button("匯入我的字體（.ttf／.otf）") { pick(PICK_FONT) }
        text("可以用自己買的字體，只在自己的鍵盤上顯示。匯入後到下面的「字體」分頁選它；不要的話到鍵盤 ⚙ 設定按「刪掉這個字體」。中文字體檔通常比較大，超過 40MB 的鍵盤裝不下。")

        title("使用小提醒")
        text("• 注音是大千排列。空白鍵＝一聲；打完按空白送出整句，或點上面的候選字一段一段選。")
        text("• 拼音：給習慣漢語拼音的人（例如馬來西亞朋友）。到鍵盤 ⚙ 設定 › 輸入法打開「拼音」，打 nihao 或只打聲母 nh 就出「你好」，預設繁體字（設定裡可以改簡體）。")
        text("• 按住「中／英」鍵可以換回別的鍵盤。按住空白鍵左右滑可以移動游標。")
        text("• 手寫：第一次用會下載 Google 的手寫辨識資料（約 20MB），之後不用網路。")
        text("• 翻譯：工具列的「譯」。第一次翻譯某個語言要下載資料。")
        text("• 剪貼簿：自動記錄預設關閉，可在鍵盤 ⚙ → 隱私與安全開啟；不要保存密碼或驗證碼。")
        text("• 主題、按鍵造型、字體、聲音在下面的分頁換，可以先預覽；大小在上面「邊調邊看」或鍵盤的 ⚙ 設定裡調。")
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
        if (what == PICK_FONT) {
            // 字體檔的類型各家檔案 App 標得不一樣，全部都讓她挑，讀進來再檢查
            @Suppress("DEPRECATION")
            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*"), what)
            return
        }
        val intent = Intent(Intent.ACTION_GET_CONTENT).setType("image/*").addCategory(Intent.CATEGORY_OPENABLE)
        // 背景照片可以一次挑好幾張
        if (what == PICK_BACKGROUND) intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        @Suppress("DEPRECATION")
        startActivityForResult(Intent.createChooser(intent, if (what == PICK_BACKGROUND) "挑照片（可以一次挑好幾張）" else "挑一張照片"), what)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (resultCode != RESULT_OK) return
        // 一次挑好幾張：每張都加進背景照片
        val clip = data?.clipData
        if (requestCode == PICK_BACKGROUND && clip != null && clip.itemCount > 1) {
            addBackgrounds((0 until minOf(clip.itemCount, 10)).map { clip.getItemAt(it).uri })
            return
        }
        val uri = data?.data ?: clip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.uri ?: return
        if (requestCode == PICK_FONT) {
            importFont(uri)
            return
        }
        if (requestCode == PICK_SPACE) {
            pickedSpace(uri)
            return
        }
        // 背景照片留大一點（放大對準臉也不會糊）；貼圖小小的就好
        val bitmap = load(uri, if (requestCode == PICK_STICKER) 512 else 2048) ?: run {
            toast("讀不到這張照片")
            return
        }
        when (requestCode) {
            PICK_BACKGROUND -> {
                val s = KeyboardSettings(this)
                // 對準臉；找不到臉就偏上面一點（人像的頭通常在上面）
                val face = faceCenter(bitmap)
                s.addPhoto(face?.first ?: 0.5f, face?.second ?: 0.3f) { f ->
                    f.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 92, it) }
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

    /** 一次加好幾張背景照片（一張一張讀，不會一次吃光記憶體） */
    private fun addBackgrounds(uris: List<Uri>) {
        val s = KeyboardSettings(this)
        var added = 0
        for (u in uris) {
            val bitmap = load(u, 2048) ?: continue
            val face = faceCenter(bitmap)
            s.addPhoto(face?.first ?: 0.5f, face?.second ?: 0.3f) { f ->
                f.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 92, it) }
            }
            bitmap.recycle()
            added++
        }
        toast(if (added == 0) "讀不到這些照片" else "加好 $added 張背景照片了！在鍵盤 ⚙ 設定 › 背景照片 點縮圖就能換")
    }

    /** 空白鍵的圖：GIF 原樣保存；照片問要不要去背 */
    private fun pickedSpace(uri: Uri) {
        val isGif = contentResolver.getType(uri) == "image/gif"
        if (isGif) {
            runCatching {
                val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: error("讀不到這個檔案")
                com.startown.starkeyboard.ime.SpaceArt.saveGif(this, bytes)
            }.onSuccess { spaceDone() }.onFailure { toast(it.message ?: "讀不到這個 GIF") }
            return
        }
        val bitmap = load(uri, 900) ?: run { toast("讀不到這張照片"); return }
        android.app.AlertDialog.Builder(this).setTitle("要自動去背嗎？")
            .setMessage("去背會只留下主角（人、動物、物品），第一次用要等它下載一下。")
            .setPositiveButton("自動去背") { _, _ -> cutout(bitmap) }
            .setNegativeButton("不用") { _, _ -> saveSpace(bitmap) }
            .show()
    }

    private fun cutout(bitmap: Bitmap) {
        toast("去背中…")
        val options = com.google.mlkit.vision.segmentation.subject.SubjectSegmenterOptions.Builder()
            .enableForegroundBitmap().build()
        com.google.mlkit.vision.segmentation.subject.SubjectSegmentation.getClient(options)
            .process(com.google.mlkit.vision.common.InputImage.fromBitmap(bitmap, 0))
            .addOnSuccessListener { result ->
                val fg = result.foregroundBitmap
                if (fg == null) { toast("找不到主角，先用原圖"); saveSpace(bitmap) } else saveSpace(trim(fg))
            }
            .addOnFailureListener { toast("沒辦法去背（可能還在下載，等一下再試），先用原圖"); saveSpace(bitmap) }
    }

    /** 把透明的邊裁掉，主角才會大大的 */
    private fun trim(b: Bitmap): Bitmap {
        var l = b.width; var t = b.height; var r = -1; var btm = -1
        val row = IntArray(b.width)
        for (y in 0 until b.height) {
            b.getPixels(row, 0, b.width, 0, y, b.width, 1)
            for (x in 0 until b.width) if ((row[x] ushr 24) > 16) { if (x < l) l = x; if (x > r) r = x; if (y < t) t = y; btm = y }
        }
        return if (r < l || btm < t) b else Bitmap.createBitmap(b, l, t, r - l + 1, btm - t + 1)
    }

    private fun saveSpace(bitmap: Bitmap) {
        runCatching { com.startown.starkeyboard.ime.SpaceArt.saveImage(this, bitmap) }
            .onSuccess { spaceDone() }.onFailure { toast("存檔失敗") }
    }

    private fun spaceDone() {
        KeyboardSettings(this).spaceStyle = "image"
        toast("空白鍵換好了！打開鍵盤看看")
    }

    /** 把挑好的字體檔存進鍵盤，順便換成這個字體 */
    private fun importFont(uri: android.net.Uri) {
        runCatching {
            var name = "我的字體"
            contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) name = c.getString(0).substringBeforeLast('.')
            }
            val bytes = contentResolver.openInputStream(uri)?.use { input ->
                val out = ByteArrayOutputStream()
                val buffer = ByteArray(65536)
                while (true) {
                    val n = input.read(buffer)
                    if (n < 0) break
                    require(out.size() + n <= com.startown.starkeyboard.ime.UserFonts.MAX_BYTES) { "字體檔超過 40MB，鍵盤裝不下" }
                    out.write(buffer, 0, n)
                }
                out.toByteArray()
            } ?: error("讀不到這個檔案")
            val item = com.startown.starkeyboard.ime.UserFonts.add(this, bytes, name)
            KeyboardSettings(this).fontId = item.id
            item
        }.onSuccess {
            toast("加好了！鍵盤已經換成「${it.name}」")
        }.onFailure {
            toast(it.message ?: "讀不到這個字體")
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
