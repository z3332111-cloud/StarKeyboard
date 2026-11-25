package com.startown.starkeyboard

import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import com.startown.starkeyboard.ime.ArtFinish
import com.startown.starkeyboard.ime.FoxLetter
import com.startown.starkeyboard.ime.FoxPaperDrawable
import com.startown.starkeyboard.ime.FontPacks
import com.startown.starkeyboard.ime.InputMode
import com.startown.starkeyboard.ime.KeyAction
import com.startown.starkeyboard.ime.KeyEffect
import com.startown.starkeyboard.ime.KeyFinish
import com.startown.starkeyboard.ime.KeyFont
import com.startown.starkeyboard.ime.KeyFonts
import com.startown.starkeyboard.ime.KeyLayouts
import com.startown.starkeyboard.ime.KeyMotion
import com.startown.starkeyboard.ime.KeyShape
import com.startown.starkeyboard.ime.KeySound
import com.startown.starkeyboard.ime.KeyboardLayer
import com.startown.starkeyboard.ime.KeyboardLayout
import com.startown.starkeyboard.ime.KeyboardSettings
import com.startown.starkeyboard.ime.KeyboardStyle
import com.startown.starkeyboard.ime.KeyboardTheme
import com.startown.starkeyboard.ime.KeyboardView
import com.startown.starkeyboard.ime.ShiftState
import com.startown.starkeyboard.ime.SoundPacks
import com.startown.starkeyboard.ime.ThemeLooks
import com.startown.starkeyboard.ime.ThemePacks
import com.startown.starkeyboard.ime.UserFonts
import com.startown.starkeyboard.ime.isFoxLetter
import com.startown.starkeyboard.ime.isIllustrated

/**
 * App 的「主題、按鍵、字體、聲音」分頁。App 和鍵盤共用同一份設定，選了鍵盤就換（鍵盤開著也會馬上跟著變）；
 * 預覽用鍵盤同一套程式畫。大張的預覽圖和每種字體只在這裡載入，鍵盤的 ⚙ 裡不再放這些，比較省記憶體。
 */
class LookTabs(private val activity: Activity, private val col: LinearLayout, private val refresh: () -> Unit) {
    private val ks = KeyboardSettings(activity)
    private val dp = activity.resources.displayMetrics.density
    private fun px(v: Float) = (v * dp).toInt()
    private val ink = Color.parseColor("#43262F")
    private val soft = Color.parseColor("#7A5A64")
    private val pink = Color.parseColor("#E8577E")

    companion object {
        /** 正在下載的主題、字體、聲音（換分頁也記得） */
        private val downloading = HashSet<String>()
        private var pool: SoundPool? = null
    }

    // MARK: 共用的小元件

    private fun title(s: String) = col.addView(TextView(activity).apply {
        text = s; textSize = 18f; setTextColor(ink); typeface = Typeface.DEFAULT_BOLD
        setPadding(px(4f), px(18f), 0, px(6f))
    })

    private fun note(s: String) = col.addView(TextView(activity).apply {
        text = s; textSize = 13f; setTextColor(soft); setLineSpacing(0f, 1.2f)
        setPadding(px(4f), px(2f), px(4f), px(4f))
    })

    private fun card(selected: Boolean): LinearLayout = LinearLayout(activity).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(px(14f), px(12f), px(14f), px(12f))
        background = GradientDrawable().apply {
            cornerRadius = 20 * dp
            setColor(if (selected) Color.parseColor("#FFE6EE") else Color.WHITE)
            setStroke(if (selected) px(2f) else px(1f), if (selected) pink else Color.parseColor("#F1DDE3"))
        }
    }

    private fun addCard(c: View) = col.addView(c, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { topMargin = px(10f) })

    /** 卡片上面那一行：名字、副標題、右邊的狀態（✓、下載、下載中） */
    private fun header(parent: LinearLayout, name: String, subtitle: String, status: String, typeface: Typeface? = null) {
        val row = LinearLayout(activity).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        val texts = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
        texts.addView(TextView(activity).apply {
            text = name; textSize = 16f; setTextColor(ink); this.typeface = typeface ?: Typeface.DEFAULT_BOLD
        })
        if (subtitle.isNotEmpty()) texts.addView(TextView(activity).apply { text = subtitle; textSize = 12f; setTextColor(soft) })
        row.addView(texts, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        if (status.isNotEmpty()) row.addView(TextView(activity).apply {
            text = status; textSize = 14f; typeface = Typeface.DEFAULT_BOLD; setTextColor(pink)
        })
        parent.addView(row)
    }

    private fun toast(s: String) = Toast.makeText(activity, s, Toast.LENGTH_SHORT).show()

    // MARK: 預覽（和鍵盤同一套程式畫）

    private val fullLayout: KeyboardLayout
        get() = KeyLayouts.layout(KeyLayouts.Context(InputMode.ZHUYIN, KeyboardLayer.LETTERS, ShiftState.OFF, "換行", "糯糯鍵盤", "中"))

    /** 卡片上的一排：123、六顆注音、換行 */
    private val rowLayout: KeyboardLayout
        get() {
            val full = fullLayout
            val all = full.rows.flatten()
            val number = all.firstOrNull { it.action is KeyAction.Layer }?.copy(width = 1.4f)
            val enter = all.firstOrNull { it.action == KeyAction.Return }?.copy(width = 1.6f)
            val letters = full.rows.firstOrNull()?.take(6) ?: emptyList()
            return KeyboardLayout(listOf(listOfNotNull(number) + letters + listOfNotNull(enter)), 9f)
        }

    private fun preview(parent: LinearLayout, style: KeyboardStyle, compact: Boolean, height: Float) {
        FoxLetter.finish = if (style.isIllustrated) ks.artFinish else KeyFinish.FLAT
        val box = FrameLayout(activity)
        val paper = if (style.isFoxLetter) FoxLetter.backdrop(activity) else null
        box.background = if (paper != null) FoxPaperDrawable(paper)
            else GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, intArrayOf(style.theme.top, style.theme.bottom)).apply { cornerRadius = 14 * dp }
        box.clipToOutline = true
        box.setPadding(px(3f), px(5f), px(3f), px(5f))
        val kv = KeyboardView(activity, style)
        kv.setLayout(if (compact) rowLayout else fullLayout)
        // 只是預覽：手指按上去不打字
        kv.setOnTouchListener { _, _ -> true }
        box.addView(kv, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        parent.addView(box, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, px(height)).apply { topMargin = px(8f) })
    }

    /** 分頁最上面：現在的樣子（整個鍵盤） */
    private fun current() {
        preview(col, ks.style, false, 230f)
        note("點一下就換好，鍵盤開著也會馬上跟著變。還沒下載的主題、字體、聲音會先下載（要有網路）。")
    }

    // MARK: 主題

    fun themes() {
        current()
        title("插畫主題（要用時才下載）")
        val illustrated = ThemeLooks.all.map { Triple(it.theme.id, "${it.emoji} ${it.theme.name}", it.subtitle) } +
            Triple(FoxLetter.ID, "🦊 小狐狸的楓葉信", "秋日水彩")
        for ((id, name, subtitle) in illustrated) themeCard(id, name, subtitle)
        title("經典配色")
        for (t in KeyboardTheme.all) themeCard(t.id, t.name, "")
        themeCard("custom", "🎨 自訂配色", "在鍵盤的 ⚙ 調顏色")
    }

    private fun themeCard(id: String, name: String, subtitle: String) {
        val selected = ks.themeId == id
        val ready = ThemePacks.isReady(activity, id)
        val c = card(selected)
        header(c, name, subtitle, when {
            id in downloading -> "下載中…"
            selected -> "✓ 使用中"
            !ready -> "⬇ 下載"
            else -> ""
        })
        preview(c, ks.style(id), true, 58f)
        c.setOnClickListener { chooseTheme(id, name) }
        addCard(c)
    }

    private fun chooseTheme(id: String, name: String) {
        if (id in downloading) return
        if (!ThemePacks.isReady(activity, id)) {
            downloading.add(id)
            refresh()
            ThemePacks.download(activity, id) { ok ->
                downloading.remove(id)
                if (ok) setTheme(id) else toast("「$name」下載失敗，檢查一下網路再試")
                refresh()
            }
            return
        }
        setTheme(id)
        refresh()
    }

    private fun setTheme(id: String) {
        if (ThemeLooks.named(ks.themeId) == null && ks.themeId != FoxLetter.ID) ks.themeBeforeFox = ks.themeId
        ks.themeId = id
    }

    // MARK: 按鍵（造型、質感、動作、特效、字的顏色）

    fun keys() {
        current()
        val style = ks.style
        if (ThemeLooks.named(ks.themeId)?.hasArt == false) {
            note("這個主題已配好造型和質感；換回其他主題就恢復你選的。")
        } else if (style.isIllustrated) {
            title("質感")
            chips(ArtFinish.choices.map { it.name to it.title }, ks.artFinish.name) { ks.artFinish = KeyFinish.valueOf(it) }
        } else {
            title("造型")
            chips(KeyShape.values().map { it.name to it.title }, ks.shape.name) { ks.shape = KeyShape.valueOf(it) }
            title("質感")
            chips(KeyFinish.values().map { it.name to it.title }, ks.keyFinish.name) { ks.keyFinish = KeyFinish.valueOf(it) }
        }
        title("按下去的動作")
        chips(KeyMotion.values().map { it.id to it.title }, ks.keyMotion) { ks.keyMotion = it }
        title("按鍵特效（按下去冒出小圖案）")
        chips(KeyEffect.values().map { it.id to it.title }, ks.keyEffect) { ks.keyEffect = it }
        title("按鍵字的顏色")
        colorGrid(style.theme)
        note("注音、英文、數字和符號的顏色。更細的深淺可以在鍵盤的 ⚙ 用滑桿調。")
    }

    /** 一排一排的選項（一排三個） */
    private fun chips(items: List<Pair<String, String>>, selected: String, pick: (String) -> Unit) {
        for (group in items.chunked(3)) {
            val row = LinearLayout(activity).apply { orientation = LinearLayout.HORIZONTAL }
            for ((id, title) in group) {
                val on = id == selected
                row.addView(TextView(activity).apply {
                    text = title; textSize = 14f; gravity = Gravity.CENTER; maxLines = 1
                    setTextColor(if (on) Color.WHITE else ink)
                    typeface = if (on) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
                    background = GradientDrawable().apply { cornerRadius = 12 * dp; setColor(if (on) pink else Color.WHITE) }
                    setOnClickListener { pick(id); refresh() }
                }, LinearLayout.LayoutParams(0, px(42f), 1f).apply { setMargins(px(3f), px(3f), px(3f), px(3f)) })
            }
            repeat(3 - group.size) { row.addView(View(activity), LinearLayout.LayoutParams(0, px(42f), 1f)) }
            col.addView(row)
        }
    }

    private fun colorGrid(theme: KeyboardTheme) {
        val options = listOf(-1) + KeyboardTheme.candidateColors
        for (group in options.chunked(8)) {
            val row = LinearLayout(activity).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
            for (value in group) {
                val on = value == ks.keyTextColor
                val cell = FrameLayout(activity)
                cell.addView(TextView(activity).apply {
                    gravity = Gravity.CENTER
                    if (value < 0) { text = "主題"; textSize = 10f; typeface = Typeface.DEFAULT_BOLD; setTextColor(theme.keyText) }
                    background = GradientDrawable().apply {
                        shape = GradientDrawable.OVAL
                        setColor(if (value < 0) theme.key else (0xFF000000.toInt() or value))
                        setStroke(if (on) px(3f) else px(1f), if (on) pink else Color.parseColor("#D9C6CC"))
                    }
                }, FrameLayout.LayoutParams(px(32f), px(32f), Gravity.CENTER))
                cell.setOnClickListener { ks.keyTextColor = value; refresh() }
                row.addView(cell, LinearLayout.LayoutParams(0, px(40f), 1f))
            }
            repeat(8 - group.size) { row.addView(View(activity), LinearLayout.LayoutParams(0, px(40f), 1f)) }
            col.addView(row)
        }
    }

    // MARK: 字體

    fun fonts() {
        current()
        val all = KeyFont.values().map { Triple(it.id, it.title, it) } + UserFonts.all(activity).map { Triple(it.id, it.name, null) }
        for ((id, name, font) in all) {
            val ready = font == KeyFont.SYSTEM || FontPacks.isReady(activity, id)
            val selected = ks.fontId == id
            val c = card(selected)
            header(c, name, if (font == null) "我匯入的字體" else "", when {
                id in downloading -> "下載中…"
                selected -> "✓ 使用中"
                !ready -> "⬇ 下載"
                else -> ""
            })
            c.addView(TextView(activity).apply {
                text = "糯糯鍵盤 ㄅㄆㄇ Aa 123"; textSize = 24f; maxLines = 1
                setTextColor(if (ready) ink else soft)
                typeface = if (ready) KeyFonts.get(activity, id) ?: Typeface.DEFAULT else Typeface.DEFAULT
                setPadding(0, px(6f), 0, 0)
            })
            c.setOnClickListener { if (font != null) chooseFont(font) else { ks.fontId = id; refresh() } }
            addCard(c)
        }
        note("自己買的字體：在「首頁」按「匯入我的字體」，匯入後會出現在這裡。")
    }

    private fun chooseFont(font: KeyFont) {
        if (font.id in downloading) return
        if (font != KeyFont.SYSTEM && !FontPacks.isReady(activity, font.id)) {
            downloading.add(font.id)
            refresh()
            FontPacks.download(activity, font.id) { ok ->
                downloading.remove(font.id)
                if (ok) ks.fontId = font.id else toast("「${font.title}」下載失敗，檢查一下網路再試")
                refresh()
            }
            return
        }
        ks.fontId = font.id
        refresh()
    }

    // MARK: 聲音

    fun sounds() {
        val on = ks.keySound
        val c = card(false)
        header(c, "按鍵聲音", "點下面的聲音聽聽看，順便換成那個聲音", if (on) "開" else "關")
        c.setOnClickListener { ks.keySound = !ks.keySound; refresh() }
        addCard(c)
        note("機械軸是真實錄音，第一次會先下載（每種只有幾十 KB）。")
        for (sound in KeySound.values()) {
            val ready = SoundPacks.isReady(activity, sound)
            val selected = on && ks.keySoundStyle == sound.id
            val s = card(selected)
            header(s, (if (sound.mechanical) "⌨️ " else "🔔 ") + sound.title, "", when {
                sound.id in downloading -> "下載中…"
                selected -> "✓ 使用中"
                !ready -> "⬇ 下載"
                else -> "🔊"
            })
            s.setOnClickListener { chooseSound(sound) }
            addCard(s)
        }
    }

    private fun chooseSound(sound: KeySound) {
        if (sound.id in downloading) return
        if (!SoundPacks.isReady(activity, sound)) {
            downloading.add(sound.id)
            refresh()
            SoundPacks.download(activity, sound) { ok ->
                downloading.remove(sound.id)
                if (ok) chooseSound(sound) else { toast("「${sound.title}」下載失敗，檢查一下網路再試"); refresh() }
            }
            return
        }
        ks.keySoundStyle = sound.id
        ks.keySound = true
        play(sound)
        refresh()
    }

    private fun play(sound: KeySound) {
        if (sound == KeySound.SYSTEM) {
            (activity.getSystemService(android.content.Context.AUDIO_SERVICE) as AudioManager).playSoundEffect(AudioManager.FX_KEYPRESS_STANDARD, -1f)
            return
        }
        val name = sound.normalFiles.randomOrNull() ?: return
        val p = pool ?: SoundPool.Builder().setMaxStreams(4).setAudioAttributes(
            AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build(),
        ).build().also { sp ->
            pool = sp
            // 載好就播，播完就放掉（只是試聽）
            sp.setOnLoadCompleteListener { loaded, sample, status ->
                if (status == 0) loaded.play(sample, 0.6f, 0.6f, 1, 0, 1f)
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({ loaded.unload(sample) }, 1500)
            }
        }
        val file = SoundPacks.file(activity, name)
        if (sound.mechanical && file.exists()) {
            p.load(file.path, 1)
        } else {
            val res = activity.resources.getIdentifier(name, "raw", activity.packageName)
            if (res != 0) p.load(activity, res, 1)
        }
    }
}
