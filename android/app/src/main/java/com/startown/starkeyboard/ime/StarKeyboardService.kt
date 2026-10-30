package com.startown.starkeyboard.ime

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.BitmapFactory
import android.graphics.drawable.GradientDrawable
import android.inputmethodservice.InputMethodService
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.view.textservice.SentenceSuggestionsInfo
import android.view.textservice.SpellCheckerSession
import android.view.textservice.SuggestionsInfo
import android.view.textservice.TextInfo
import android.view.textservice.TextServicesManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.content.FileProvider
import androidx.core.view.inputmethod.EditorInfoCompat
import androidx.core.view.inputmethod.InputConnectionCompat
import androidx.core.view.inputmethod.InputContentInfoCompat
import com.startown.starkeyboard.MainActivity
import com.startown.starkeyboard.CrashLog
import com.startown.starkeyboard.core.Bopomofo
import com.startown.starkeyboard.core.ChineseConverter
import com.startown.starkeyboard.core.Candidate
import com.startown.starkeyboard.core.ClipboardStore
import com.startown.starkeyboard.core.EmoticonStore
import com.startown.starkeyboard.core.FancyText
import com.startown.starkeyboard.core.GlideDecoder
import com.startown.starkeyboard.core.Pt
import com.startown.starkeyboard.core.ShortcutStore
import com.startown.starkeyboard.core.HangulComposer
import com.startown.starkeyboard.core.PinyinEngine
import com.startown.starkeyboard.core.Romaji
import com.startown.starkeyboard.core.Spelling
import com.startown.starkeyboard.core.UserPhraseModel
import com.startown.starkeyboard.core.ZhuyinComposer
import com.startown.starkeyboard.core.ZhuyinEngine
import java.io.File
import java.util.Locale

class StarKeyboardService : InputMethodService(), SpellCheckerSession.SpellCheckerSessionListener {
    private enum class SuggestionSource { ASSOCIATION, HANDWRITING, SPELLING, GLIDE }
    private enum class EditorPurpose { EMOTICON, TRANSLATE, FANCY, SHORTCUT_PHRASE, SHORTCUT_CODE, CLIPBOARD_CATEGORY }
    private var renamingCategory: String? = null

    private fun editorLabel(p: EditorPurpose) = when (p) {
        EditorPurpose.EMOTICON -> "表符："
        EditorPurpose.TRANSLATE -> "翻譯："
        EditorPurpose.FANCY -> "花式文字："
        EditorPurpose.SHORTCUT_PHRASE -> "片語內容："
        EditorPurpose.SHORTCUT_CODE -> "縮寫："
        EditorPurpose.CLIPBOARD_CATEGORY -> "分類名稱："
    }

    private fun editorConfirmTitle(p: EditorPurpose) = when (p) {
        EditorPurpose.TRANSLATE -> "翻譯"
        EditorPurpose.FANCY -> "變花樣"
        EditorPurpose.SHORTCUT_PHRASE -> "下一步"
        else -> "儲存"
    }

    private lateinit var settings: KeyboardSettings
    private lateinit var clipStore: ClipboardStore
    private lateinit var emoStore: EmoticonStore
    private lateinit var shortcuts: ShortcutStore
    private var glide: GlideDecoder? = null
    private var lastGlide: String? = null
    private var engine: ZhuyinEngine? = null
    private var pinyinEngine: PinyinEngine? = null
    private var converter: ChineseConverter? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // 狀態
    private var mode = InputMode.ZHUYIN
    private var layer = KeyboardLayer.LETTERS
    private var shift = ShiftState.OFF
    private var lastShiftTap = 0L
    private var lastSpaceTime = 0L
    private val composer = ZhuyinComposer()
    private var kanaBuffer = ""
    private var pinyinBuffer = ""                          // 拼音：還沒送出的字母
    private var candidateOriginals: List<String> = emptyList()   // 拼音候選轉簡體前的原文
    private val hangul = HangulComposer()
    private var hangulComposing = false
    private var candidates: List<Candidate> = emptyList()
    private var suggestions: List<String> = emptyList()
    private var suggestionSource = SuggestionSource.ASSOCIATION
    private var panel: PanelKind? = null
    private var editorText: String? = null
    private var editorPurpose = EditorPurpose.EMOTICON
    private var editorReturnPanel: PanelKind? = null
    /** 編輯框打完後的結果（翻譯、花式文字）：點一個送出，最後一個「✏️ 修改」回去改 */
    private data class EditorResult(val title: String, val items: List<String>)
    private var editorResult: EditorResult? = null
    /** 新增快捷片語：先打片語內容，再打縮寫 */
    private var pendingPhrase = ""
    private var translating = false
    private var lastAutocorrect: Pair<String, String>? = null
    private var styleKey = ""

    // 英文拼字檢查（系統的拼字檢查服務）
    private var spellSession: SpellCheckerSession? = null
    private val spellCache = HashMap<String, List<String>>()   // 打錯的字 → 建議；拼對的字 → 空清單
    private var spellPending: String? = null

    // 畫面
    private var root: FrameLayout? = null
    private lateinit var bgImage: Backdrop
    private lateinit var tint: Backdrop
    private lateinit var column: LinearLayout
    private var photoAdjust: PhotoAdjustOverlay? = null
    private var backgroundStamp = ""
    private lateinit var topBar: TopBar
    private lateinit var content: FrameLayout
    private lateinit var keyboard: KeyboardView
    private var panelView: View? = null
    private var candidatePanel: CandidatePanel? = null
    private var handwriting: HandwritingPanel? = null
    private lateinit var toastView: TextView
    private val ink by lazy { InkRecognizer { toast(it) } }

    private val style get() = settings.style
    private val isComposing get() = composer.isComposing || kanaBuffer.isNotEmpty() || pinyinBuffer.isNotEmpty()
    private val dp get() = resources.displayMetrics.density

    private val clipListener = ClipboardManager.OnPrimaryClipChangedListener { captureClipboard() }

    // ===== 生命週期 =====

    override fun onCreate() {
        super.onCreate()
        settings = KeyboardSettings(this)
        clipStore = ClipboardStore(File(filesDir, "clipboard.json"), settings.clipLimit)
        emoStore = EmoticonStore(filesDir)
        shortcuts = ShortcutStore(File(filesDir, "shortcuts.json"))
        lastSoundStyle = settings.keySoundStyle
        mode = settings.lastMode.takeIf { it in settings.enabledModes } ?: settings.enabledModes.first()
        Thread {
            // 英文滑行輸入的字表
            val words = runCatching {
                assets.open("glide_words.txt").bufferedReader().readLines().mapNotNull { line ->
                    val parts = line.split(' ')
                    parts.getOrNull(1)?.toIntOrNull()?.let { parts[0] to it }
                }
            }.getOrNull()
            if (words != null) {
                val decoder = GlideDecoder(words)
                mainHandler.post { glide = decoder }
            }
            val source = SQLitePhraseSource.open(this)
            val plain = SQLitePhraseSource.open(this, "plain")
            val prefixes = source?.let { Bopomofo.prefixes(it.syllables()) }?.takeIf { it.isNotEmpty() }
            mainHandler.post {
                if (source != null) {
                    engine = ZhuyinEngine(source, UserPhraseModel(File(filesDir, "learned.txt"))).also { it.fuzzy = fuzzyOptions() }
                    composer.validPrefixes = prefixes
                }
                if (plain != null) {
                    pinyinEngine = PinyinEngine(ZhuyinEngine(plain, UserPhraseModel(File(filesDir, "learned-pinyin.txt")), toneless = true), plain.pinyinTable())
                    converter = ChineseConverter { plain.simplified(it) }
                }
            }
        }.start()
        (getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).addPrimaryClipChangedListener(clipListener)
        runCatching {
            val tsm = getSystemService(Context.TEXT_SERVICES_MANAGER_SERVICE) as TextServicesManager
            spellSession = tsm.newSpellCheckerSession(null, Locale.ENGLISH, this, true)
        }
    }

    override fun onDestroy() {
        soundPool?.release()
        soundPool = null
        (getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).removePrimaryClipChangedListener(clipListener)
        spellSession?.close()
        ink.close()
        super.onDestroy()
    }

    private fun fuzzyOptions() = ZhuyinEngine.FuzzyOptions(settings.fuzzyKeys, settings.fuzzyTones, settings.fuzzyPhonetic)

    override fun onEvaluateFullscreenMode() = false

    override fun onCreateInputView(): View {
        val r = FrameLayout(this)
        bgImage = Backdrop(this)
        tint = Backdrop(this)
        r.addView(bgImage, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        r.addView(tint, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        column = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; clipChildren = false }
        topBar = TopBar(this, style)
        content = FrameLayout(this).apply { clipChildren = false }
        keyboard = KeyboardView(this, style)
        content.addView(keyboard, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        column.addView(topBar, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, (50 * dp).toInt()))
        column.addView(content, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, contentHeight()))
        r.addView(column, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT))
        toastView = TextView(this).apply {
            textSize = 13f
            gravity = Gravity.CENTER
            setPadding((14 * dp).toInt(), (8 * dp).toInt(), (14 * dp).toInt(), (8 * dp).toInt())
            alpha = 0f
            maxLines = 2
        }
        r.addView(toastView, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER_HORIZONTAL or Gravity.TOP).apply {
            topMargin = (54 * dp).toInt()
        })
        root = r
        wire()
        applyStyle()
        rebuildKeys()
        refreshTopBar()
        return r
    }

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        emoStore.load()
        shortcuts.load()
        clipStore.load()
        if (mode !in settings.enabledModes) mode = settings.enabledModes.first()
        resetComposition()
        // 背景照片輪播（剛挑好照片要調整時不換）
        if (!settings.adjustPhotoPending) settings.rotatePhoto()
        applyStyle()
        captureClipboard()
        checkForUpdate()
        rebuildKeys()
        updateAutoShift()
        refreshTopBar()
        // 剛在 App 挑了照片：直接進入調整照片（等版面排好才知道鍵盤多大）
        if (settings.adjustPhotoPending && settings.hasBackground) {
            settings.adjustPhotoPending = false
            root?.post { startPhotoAdjust() }
        }
    }

    override fun onFinishInputView(finishingInput: Boolean) {
        finishPhotoAdjust()
        resetComposition()
        super.onFinishInputView(finishingInput)
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (root != null) rebuildKeys()
    }

    private fun resetComposition() {
        composer.clear()
        kanaBuffer = ""
        pinyinBuffer = ""
        hangul.reset()
        hangulComposing = false
        candidates = emptyList()
        suggestions = emptyList()
        currentInputConnection?.finishComposingText()
    }

    private fun wire() {
        keyboard.onKey = { handle(it) }
        keyboard.onLongPress = { showImePicker() }
        keyboard.onCursorMove = { steps -> if (!isComposing) moveCursor(steps) }
        keyboard.onGlide = { path, centers, kw -> glideTyped(path, centers, kw) }
        topBar.onScriptToggle = {
            if (mode == InputMode.PINYIN) {
                settings.pinyinSimplified = !settings.pinyinSimplified
                clearSuggestions()
                updateCandidates()
            }
        }
        topBar.onToolbar = { toolbarTapped(it) }
        topBar.onCandidate = { selectCandidate(it, true) }
        topBar.onTrailing = { trailing ->
            when (trailing) {
                Trailing.EXPAND -> toggleCandidatePanel()
                Trailing.CLOSE -> {
                    if (editorResult != null) endEditor() else {
                        if (suggestionSource == SuggestionSource.HANDWRITING) handwriting?.clear()
                        clearSuggestions()
                    }
                }
            }
        }
        topBar.onEditor = { confirm -> if (confirm) confirmEditor() else endEditor() }
        topBar.onEditorExtra = { editorExtraTapped() }
        topBar.onEditorSource = {
            // 原文語言：自動 → 英文 → 日文 → … 輪流換
            val codes = listOf("auto") + Translator.targets.map { it.code }
            val i = maxOf(0, codes.indexOf(settings.translateSource))
            settings.translateSource = codes[(i + 1) % codes.size]
            refreshTopBar()
        }
    }

    private fun showImePicker() {
        (getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager).showInputMethodPicker()
    }

    private fun moveCursor(steps: Int) {
        val ic = currentInputConnection ?: return
        finishHangul()
        val code = if (steps > 0) KeyEvent.KEYCODE_DPAD_RIGHT else KeyEvent.KEYCODE_DPAD_LEFT
        repeat(kotlin.math.abs(steps)) {
            ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, code))
            ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, code))
        }
    }

    // ===== 按鍵 =====

    private fun handle(spec: KeySpec) {
        feedback()
        val pending = lastAutocorrect
        lastAutocorrect = null
        val action = spec.action
        if (action == KeyAction.Backspace && pending != null && revertAutocorrect(pending)) return
        if (action !is KeyAction.Jamo && action != KeyAction.Backspace && action != KeyAction.Shift) finishHangul()
        when (action) {
            is KeyAction.Text -> typeText(action.s)
            is KeyAction.Zhuyin -> typeZhuyin(action.c)
            is KeyAction.Jamo -> typeJamo(action.c)
            is KeyAction.Romaji -> typeRomaji(action.c)
            is KeyAction.Pinyin -> typePinyin(action.c)
            is KeyAction.Layer -> { layer = action.layer; rebuildKeys() }
            is KeyAction.Panel -> openPanel(action.kind)
            KeyAction.Backspace -> backspace()
            KeyAction.Space -> space()
            KeyAction.Return -> returnKey()
            KeyAction.Shift -> toggleShift()
            KeyAction.NextMode -> switchMode()
            KeyAction.ClearCanvas -> { handwriting?.clear(); clearSuggestions() }
            KeyAction.ToggleWidth -> {
                settings.fullWidthSymbols = !settings.fullWidthSymbols
                toast(if (settings.fullWidthSymbols) "換成全形符號（中文排版用）" else "換成半形符號（Discord 語法用）")
                rebuildKeys()
            }
        }
    }

    private fun typeText(s: String) {
        if (isComposing) commitAll()
        clearSuggestions()
        if (mode == InputMode.ENGLISH && s in listOf(".", ",", "!", "?", ";", ":")) applyAutocorrect()
        output(s)
        if (shift == ShiftState.ON) {
            shift = ShiftState.OFF
            rebuildKeys()
        }
        updateSpelling()
    }

    private fun typeZhuyin(c: Char) {
        suggestions = emptyList()
        if (!composer.input(c)) {
            output(c.toString())
            refreshTopBar()
            return
        }
        if (composer.syllables.size >= 20) {
            commitAll()
            return
        }
        updateCandidates()
    }

    private fun typePinyin(c: Char) {
        suggestions = emptyList()
        if (c == '\'' &&(pinyinBuffer.isEmpty() || pinyinBuffer.endsWith("'"))) return
        pinyinBuffer += c
        if (pinyinBuffer.length >= 60) {
            commitAll()
            return
        }
        updateCandidates()
    }

    /** 拼音模式要不要轉成簡體 */
    private fun simplify(s: String): String {
        val c = converter
        return if (mode == InputMode.PINYIN && settings.pinyinSimplified && c != null) c.convert(s) else s
    }

    private fun typeRomaji(c: Char) {
        suggestions = emptyList()
        kanaBuffer += c
        if (kanaBuffer.length >= 60) {
            commitAll()
            return
        }
        updateCandidates()
    }

    private fun typeJamo(c: Char) {
        clearSuggestions()
        val out = hangul.input(c)
        if (editorText != null) {
            // 編輯框裡：只把拼完的字放進去，正在拼的顯示在後面
            editorText = (editorText ?: "") + out.commit
            refreshTopBar()
        } else {
            val ic = currentInputConnection
            if (out.commit.isNotEmpty()) ic?.commitText(out.commit, 1)
            if (out.composing.isNotEmpty()) ic?.setComposingText(out.composing, 1)
        }
        hangulComposing = out.composing.isNotEmpty()
        if (shift == ShiftState.ON) {
            shift = ShiftState.OFF
            rebuildKeys()
        }
    }

    private fun finishHangul() {
        if (!hangulComposing) return
        if (editorText != null) {
            editorText = (editorText ?: "") + hangul.composing
            refreshTopBar()
        } else {
            currentInputConnection?.finishComposingText()
        }
        hangul.reset()
        hangulComposing = false
    }

    private fun backspace() {
        if (pinyinBuffer.isNotEmpty()) {
            pinyinBuffer = pinyinBuffer.dropLast(1)
            updateCandidates()
            return
        }
        if (kanaBuffer.isNotEmpty()) {
            kanaBuffer = kanaBuffer.dropLast(1)
            updateCandidates()
            return
        }
        if (composer.isComposing) {
            composer.backspace()
            updateCandidates()
            return
        }
        if (hangulComposing && hangul.backspace()) {
            val c = hangul.composing
            if (editorText == null) currentInputConnection?.setComposingText(c, 1)
            hangulComposing = c.isNotEmpty()
            if (!hangulComposing) currentInputConnection?.finishComposingText()
            return
        }
        finishHangul()
        clearSuggestions()
        deleteOutput()
        updateAutoShift()
        updateSpelling()
    }

    private fun space() {
        if (mode == InputMode.ZHUYIN && layer == KeyboardLayer.LETTERS && composer.hasPendingSyllable) {
            // 空白鍵＝一聲；這個音沒有一聲的字（例如只打了 ㄋ）就直接送出預覽的字
            val noFirstTone = engine?.phrases(listOf(composer.current.reading))?.isEmpty() ?: false
            if (noFirstTone && candidates.isNotEmpty()) selectCandidate(0, false)
            else if (composer.confirmSyllable()) updateCandidates()
            return
        }
        if (isComposing) {
            if (candidates.isEmpty()) commitAll() else selectCandidate(0, false)
            return
        }
        if (suggestionSource == SuggestionSource.HANDWRITING && suggestions.isNotEmpty()) {
            selectCandidate(0, false)
            return
        }
        clearSuggestions()
        val now = System.currentTimeMillis()
        // 英文：快速按兩下空白變成句號
        if (mode == InputMode.ENGLISH && editorText == null && now - lastSpaceTime < 400) {
            val before = currentInputConnection?.getTextBeforeCursor(2, 0)?.toString() ?: ""
            if (before.length == 2 && before[1] == ' ' && before[0].isLetterOrDigit()) {
                deleteOutput()
                output(". ")
                lastSpaceTime = 0
                updateAutoShift()
                return
            }
        }
        applyAutocorrect()
        lastSpaceTime = now
        output(" ")
        updateAutoShift()
    }

    private fun returnKey() {
        if (isComposing) {
            commitAll()
            return
        }
        if (editorResult != null) {
            selectCandidate(0, false)
            return
        }
        if (editorText != null) {
            confirmEditor()
            return
        }
        clearSuggestions()
        val info = currentInputEditorInfo
        val action = (info?.imeOptions ?: 0) and EditorInfo.IME_MASK_ACTION
        val noEnterAction = ((info?.imeOptions ?: 0) and EditorInfo.IME_FLAG_NO_ENTER_ACTION) != 0
        if (!noEnterAction && action != EditorInfo.IME_ACTION_NONE && action != EditorInfo.IME_ACTION_UNSPECIFIED) {
            currentInputConnection?.performEditorAction(action)
        } else {
            sendDownUpKeyEvents(KeyEvent.KEYCODE_ENTER)
        }
        updateAutoShift()
    }

    private fun toggleShift() {
        val now = System.currentTimeMillis()
        val quick = now - lastShiftTap < 350
        shift = when (shift) {
            ShiftState.OFF -> ShiftState.ON
            ShiftState.ON -> if (quick) ShiftState.LOCKED else ShiftState.OFF
            ShiftState.LOCKED -> ShiftState.OFF
        }
        lastShiftTap = now
        rebuildKeys()
    }

    private fun updateAutoShift() {
        if (mode != InputMode.ENGLISH || layer != KeyboardLayer.LETTERS || shift == ShiftState.LOCKED || editorText != null) return
        val info = currentInputEditorInfo ?: return
        val caps = currentInputConnection?.getCursorCapsMode(info.inputType) ?: 0
        val want = if (caps != 0) ShiftState.ON else ShiftState.OFF
        if (want != shift) {
            shift = want
            rebuildKeys()
        }
    }

    private fun switchMode() {
        commitAll()
        finishHangul()
        clearSuggestions()
        val modes = settings.enabledModes
        val i = modes.indexOf(mode)
        mode = if (i >= 0) modes[(i + 1) % modes.size] else modes.first()
        settings.lastMode = mode
        layer = KeyboardLayer.LETTERS
        shift = ShiftState.OFF
        rebuildKeys()
        updateAutoShift()
    }

    private val nextModeTitle: String
        get() {
            val modes = settings.enabledModes
            if (modes.size <= 1) return mode.short
            val i = maxOf(0, modes.indexOf(mode))
            return modes[(i + 1) % modes.size].short
        }

    // ===== 輸出（用編輯框時打到編輯框，平常打到 App） =====

    private fun output(s: String) {
        if (s.isEmpty()) return
        if (editorText != null && editorResult == null) {
            editorText = editorText + s
            refreshTopBar()
            return
        }
        currentInputConnection?.commitText(s, 1)
    }

    private fun deleteOutput() {
        val t = editorText
        if (t != null && editorResult == null) {
            if (t.isNotEmpty()) editorText = t.substring(0, t.offsetByCodePoints(t.length, -1))
            refreshTopBar()
            return
        }
        val ic = currentInputConnection ?: return
        val selected = ic.getSelectedText(0)
        when {
            !selected.isNullOrEmpty() -> ic.commitText("", 1)
            ic.getTextBeforeCursor(1, 0).isNullOrEmpty() -> sendDownUpKeyEvents(KeyEvent.KEYCODE_DEL)
            else -> ic.deleteSurroundingTextInCodePoints(1, 0)
        }
    }

    /** 注音、日文組字時，把正在打的字顯示在輸入框裡（底下有底線） */
    private fun syncComposing() {
        if (editorText != null) return
        val ic = currentInputConnection ?: return
        if (isComposing) ic.setComposingText(compositionText, 1) else ic.finishComposingText()
    }

    // ===== 選字（注音、日文） =====

    private fun updateCandidates() {
        candidateOriginals = emptyList()
        candidates = when {
            pinyinBuffer.isNotEmpty() -> {
                // 拼音：查到的是繁體，要的話轉成簡體；轉完一樣的只留一個
                val seen = HashSet<String>()
                val list = ArrayList<Candidate>()
                val originals = ArrayList<String>()
                for (c in pinyinEngine?.candidates(pinyinBuffer) ?: emptyList()) {
                    val shown = simplify(c.text)
                    if (!seen.add(shown)) continue
                    list.add(c.copy(text = shown))
                    originals.add(c.text)
                }
                candidateOriginals = originals
                list
            }
            kanaBuffer.isNotEmpty() -> {
                val hira = Romaji.finalize(kanaBuffer)
                listOf(hira, Romaji.katakana(hira), kanaBuffer).distinct().map { Candidate(it, 0, Candidate.Kind.PHRASE) }
            }
            composer.readings.isEmpty() -> emptyList()
            else -> safely { engine?.candidates(composer.readings) }
                ?: listOf(Candidate(ZhuyinEngine.display(composer.readings.joinToString("")), composer.readings.size, Candidate.Kind.LITERAL))
        }
        if (composer.readings.isNotEmpty() && pinyinBuffer.isEmpty() && kanaBuffer.isEmpty()) {
            candidates = withShortcuts(candidates)
        }
        if (!isComposing) {
            currentInputConnection?.setComposingText("", 1)
            closeCandidatePanel()
        }
        syncComposing()
        candidatePanel?.setCandidates(candidates.map { it.text })
        refreshTopBar()
        refreshReturnTitle()
    }

    // ===== 英文滑行輸入 =====

    private fun glideTyped(path: List<Pt>, centers: Map<Char, Pt>, keyWidth: Float) {
        val decoder = glide
        if (decoder == null) {
            toast("英文字表還在載入，等一下再試")
            return
        }
        val words = safely { decoder.decode(path, centers, keyWidth) } ?: emptyList()
        if (words.isEmpty()) {
            toast("沒認出來，再滑一次看看")
            return
        }
        val shaped = words.map { w ->
            when (shift) {
                ShiftState.LOCKED -> w.uppercase()
                ShiftState.ON -> w.replaceFirstChar { it.uppercase() }
                else -> w
            }
        }
        // 前面是字的話先補一個空白
        val before = if (editorText != null) editorText!!.takeLast(1) else currentInputConnection?.getTextBeforeCursor(1, 0)?.toString() ?: ""
        val prefix = if (before.isNotEmpty() && !before.last().isWhitespace() && before.last() !in "([{\"'") " " else ""
        output(prefix + shaped[0])
        if (shift == ShiftState.ON) {
            shift = ShiftState.OFF
            rebuildKeys()
        }
        if (editorText != null) return
        lastGlide = shaped[0]
        suggestions = shaped
        suggestionSource = SuggestionSource.GLIDE
        refreshTopBar()
    }

    /** 選字出錯時不要讓整個鍵盤當掉：記下原因，這次就當成查不到 */
    private fun <T> safely(block: () -> T?): T? = try {
        block()
    } catch (e: Exception) {
        CrashLog.record(this, e)
        null
    }

    /** 快捷片語：打的字（整句）或注音（例如 ㄉㄓ）和縮寫一樣，就把片語放在第二個 */
    private fun withShortcuts(list: List<Candidate>): List<Candidate> {
        if (shortcuts.items.isEmpty()) return list
        val typed = composer.readings.joinToString("") { r -> r.filter { Bopomofo.TONES.indexOf(it) < 0 && it != '*' } }
        val phrases = listOfNotNull(list.firstOrNull()?.text, typed).flatMap { shortcuts.matching(it) }.distinct()
        if (phrases.isEmpty()) return list
        val extra = phrases.map { Candidate(it, composer.readings.size, Candidate.Kind.LITERAL) }
        val at = minOf(1, list.size)
        return list.take(at) + extra + list.drop(at)
    }

    private val compositionText: String
        get() {
            if (pinyinBuffer.isNotEmpty()) return pinyinEngine?.display(pinyinBuffer) ?: pinyinBuffer
            if (kanaBuffer.isNotEmpty()) {
                val (kana, rest) = Romaji.convert(kanaBuffer)
                return kana + rest
            }
            // 正在打的字也先預覽成中文（還沒打聲調、只打開頭都可以）
            if (composer.readings.isEmpty()) return ""
            return candidates.firstOrNull()?.text ?: ZhuyinEngine.display(composer.readings.joinToString(""))
        }

    private fun selectCandidate(i: Int, learn: Boolean) {
        editorResult?.let { r ->
            val chosen = r.items.getOrNull(i)
            editorResult = null
            if (chosen != null) {
                editorText = null
                currentInputConnection?.commitText(chosen, 1)
                rebuildKeys()
            }
            refreshTopBar()
            refreshReturnTitle()
            return
        }
        if (pinyinBuffer.isNotEmpty()) {
            val c = candidates.getOrNull(i) ?: return
            val original = candidateOriginals.getOrNull(i) ?: c.text
            val p = pinyinEngine
            if (p != null) {
                if (learn && c.kind != Candidate.Kind.LITERAL) {
                    p.engine.learn(p.readings(p.segment(pinyinBuffer)).take(c.span), original)
                }
                pinyinBuffer = pinyinBuffer.drop(p.consumedLength(pinyinBuffer, c.span)).trimStart('\'')
            } else {
                pinyinBuffer = ""
            }
            output(c.text)
            if (pinyinBuffer.isNotEmpty()) {
                updateCandidates()
            } else {
                candidates = emptyList()
                candidateOriginals = emptyList()
                closeCandidatePanel()
                showAssociations(original)
                refreshReturnTitle()
            }
            return
        }
        if (kanaBuffer.isNotEmpty()) {
            val text = candidates.getOrNull(i)?.text ?: return
            kanaBuffer = ""
            candidates = emptyList()
            closeCandidatePanel()
            output(text)
            refreshTopBar()
            refreshReturnTitle()
            return
        }
        if (composer.isComposing) {
            val c = candidates.getOrNull(i) ?: return
            if (learn && c.kind != Candidate.Kind.LITERAL) engine?.learn(composer.readings.take(c.span), c.text)
            output(c.text)
            composer.removeFirst(c.span)
            if (composer.isComposing) {
                updateCandidates()
            } else {
                candidates = emptyList()
                closeCandidatePanel()
                showAssociations(c.text)
                refreshReturnTitle()
            }
            return
        }
        if (suggestionSource == SuggestionSource.GLIDE) {
            // 滑行輸入認錯了：換成點的那個字
            val choice = suggestions.getOrNull(i) ?: return
            val last = lastGlide
            val ic = currentInputConnection
            if (last != null && choice != last && ic?.getTextBeforeCursor(last.length, 0)?.toString() == last) {
                ic.deleteSurroundingText(last.length, 0)
                ic.commitText(choice, 1)
                lastGlide = choice
            }
            clearSuggestions()
            return
        }
        if (suggestionSource == SuggestionSource.SPELLING) {
            val choice = suggestions.getOrNull(i) ?: return
            val word = currentWord
            val ic = currentInputConnection
            if (choice != word) {
                ic?.deleteSurroundingText(word.length, 0)
                ic?.commitText(choice, 1)
            }
            ic?.commitText(" ", 1)
            clearSuggestions()
            updateAutoShift()
            return
        }
        val s = suggestions.getOrNull(i) ?: return
        output(s)
        if (suggestionSource == SuggestionSource.HANDWRITING) handwriting?.clear()
        showAssociations(s)
    }

    private fun commitAll() {
        if (!isComposing) return
        val text: String
        if (pinyinBuffer.isNotEmpty()) {
            // 拼音：送出整句（第一個候選）；完全查不到就照打的字母送出
            text = candidates.firstOrNull()?.text ?: pinyinBuffer.replace("'", "")
            pinyinBuffer = ""
            candidateOriginals = emptyList()
        } else if (kanaBuffer.isNotEmpty()) {
            text = Romaji.finalize(kanaBuffer)
            kanaBuffer = ""
        } else {
            text = safely { engine?.bestSegments(composer.readings)?.joinToString("") { it.text } }
                ?: ZhuyinEngine.display(composer.readings.joinToString(""))
            composer.clear()
        }
        candidates = emptyList()
        closeCandidatePanel()
        if (editorText != null) output(text) else currentInputConnection?.commitText(text, 1)
        refreshTopBar()
        refreshReturnTitle()
    }

    private fun showAssociations(text: String) {
        suggestions = if (settings.associations && editorText == null && (mode == InputMode.ZHUYIN || mode == InputMode.HANDWRITING)) {
            engine?.associations(text) ?: emptyList()
        } else if (settings.associations && editorText == null && mode == InputMode.PINYIN) {
            // 拼音：用繁體原文查，結果再轉簡體
            (pinyinEngine?.engine?.associations(text) ?: emptyList()).map { simplify(it) }.distinct()
        } else emptyList()
        suggestionSource = SuggestionSource.ASSOCIATION
        refreshTopBar()
    }

    private fun clearSuggestions() {
        if (suggestions.isEmpty()) return
        suggestions = emptyList()
        refreshTopBar()
    }

    private fun refreshTopBar() {
        if (root == null) return
        topBar.scriptTitle = if (mode == InputMode.PINYIN && editorResult == null) (if (settings.pinyinSimplified) "簡" else "繁") else null
        val tr = editorResult
        val ed = editorText
        when {
            tr != null -> topBar.showCandidates(tr.title, tr.items + "✏️ 修改", Trailing.CLOSE)
            isComposing -> {
                val prefix = if (ed != null) editorLabel(editorPurpose) + ed + " ｜ " else ""
                topBar.showCandidates(if (ed != null) prefix + compositionText else "", candidates.map { it.text }, Trailing.EXPAND)
            }
            ed != null && (suggestions.isEmpty() || suggestionSource == SuggestionSource.ASSOCIATION) -> {
                val pending = if (hangulComposing) hangul.composing else ""
                when (editorPurpose) {
                    EditorPurpose.EMOTICON -> topBar.showEditor("新增表符：", ed + pending, "(•ᴗ•)", "儲存")
                    EditorPurpose.TRANSLATE -> {
                        val name = Translator.targets.firstOrNull { it.code == settings.translateTarget }?.name ?: "英文"
                        val from = Translator.targets.firstOrNull { it.code == settings.translateSource }?.name ?: "自動"
                        topBar.showEditor(if (translating) "翻譯中…" else "翻譯：", ed + pending, "→$name", "翻譯", "從：$from")
                    }
                    else -> topBar.showEditor(editorLabel(editorPurpose), ed + pending, "", editorConfirmTitle(editorPurpose))
                }
            }
            suggestions.isNotEmpty() -> topBar.showCandidates("", suggestions, Trailing.CLOSE)
            else -> topBar.showToolbar()
        }
    }

    private fun toggleCandidatePanel() {
        if (candidatePanel != null) {
            closeCandidatePanel()
            return
        }
        val p = CandidatePanel(this, style, { selectCandidate(it, true) }, { closeCandidatePanel() }, { backspace() })
        p.setCandidates(candidates.map { it.text })
        content.addView(p, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        candidatePanel = p
    }

    private fun closeCandidatePanel() {
        candidatePanel?.let { content.removeView(it) }
        candidatePanel = null
    }

    // ===== 英文自動修正 =====

    /** 游標前面正在打的英文字 */
    private val currentWord: String
        get() {
            if (editorText != null) return ""
            val before = currentInputConnection?.getTextBeforeCursor(40, 0)?.toString() ?: return ""
            return before.takeLastWhile { (it.isLetter() && it.code < 128) || it == '\'' }
        }

    private fun updateSpelling() {
        if (mode != InputMode.ENGLISH || !settings.autocorrect) return
        val word = currentWord
        if (word.length < 2) {
            if (suggestionSource == SuggestionSource.SPELLING) clearSuggestions()
            return
        }
        val cached = spellCache[word]
        if (cached != null) {
            showSpelling(word, cached)
        } else {
            spellPending = word
            spellSession?.getSentenceSuggestions(arrayOf(TextInfo(word)), 5)
        }
    }

    private fun showSpelling(word: String, fixes: List<String>) {
        if (word != currentWord) return
        val options = (shortcuts.matching(word) + fixes.map { Spelling.matchCase(it, word) }).filter { it != word }.distinct()
        if (options.isEmpty()) {
            if (suggestionSource == SuggestionSource.SPELLING) clearSuggestions()
            return
        }
        suggestions = listOf(word) + options.take(5)
        suggestionSource = SuggestionSource.SPELLING
        refreshTopBar()
    }

    override fun onGetSentenceSuggestions(results: Array<out SentenceSuggestionsInfo>?) {
        val word = spellPending ?: return
        val fixes = ArrayList<String>()
        var typo = false
        results?.forEach { s ->
            for (i in 0 until s.suggestionsCount) {
                val info = s.getSuggestionsInfoAt(i) ?: continue
                val attrs = info.suggestionsAttributes
                if (attrs and (SuggestionsInfo.RESULT_ATTR_LOOKS_LIKE_TYPO or SuggestionsInfo.RESULT_ATTR_HAS_RECOMMENDED_SUGGESTIONS) != 0 &&
                    attrs and SuggestionsInfo.RESULT_ATTR_IN_THE_DICTIONARY == 0) {
                    typo = true
                }
                for (j in 0 until info.suggestionsCount) info.getSuggestionAt(j)?.let { fixes.add(it) }
            }
        }
        val list = if (typo) fixes else emptyList()
        spellCache[word] = list
        mainHandler.post { showSpelling(word, list) }
    }

    override fun onGetSuggestions(results: Array<out SuggestionsInfo>?) {}

    private fun applyAutocorrect(): Boolean {
        if (mode != InputMode.ENGLISH || editorText != null || !settings.autocorrect) return false
        val word = currentWord
        if (word.length < 2 || word.uppercase() == word) return false
        val fix = spellCache[word]?.firstOrNull() ?: return false
        if (!Spelling.isCloseEnough(word, fix)) return false
        val fixed = Spelling.matchCase(fix, word)
        val ic = currentInputConnection ?: return false
        ic.deleteSurroundingText(word.length, 0)
        ic.commitText(fixed, 1)
        lastAutocorrect = word to fixed
        return true
    }

    private fun revertAutocorrect(ac: Pair<String, String>): Boolean {
        val ic = currentInputConnection ?: return false
        val (original, corrected) = ac
        val before = ic.getTextBeforeCursor(corrected.length + 1, 0)?.toString() ?: return false
        if (before.length != corrected.length + 1 || !before.startsWith(corrected) || before.last().isLetter()) return false
        val last = before.last()
        ic.deleteSurroundingText(corrected.length + 1, 0)
        ic.commitText(if (last == ' ') original else original + last, 1)
        spellCache[original] = emptyList()
        clearSuggestions()
        toast("已改回「$original」，之後不會再改它")
        return true
    }

    // ===== 工具列與面板 =====

    private fun toolbarTapped(item: ToolbarItem) {
        feedback()
        finishHangul()
        when (item) {
            ToolbarItem.CLIPBOARD -> togglePanel(PanelKind.CLIPBOARD)
            ToolbarItem.EMOJI -> togglePanel(PanelKind.EMOJI)
            ToolbarItem.KAOMOJI -> togglePanel(PanelKind.KAOMOJI)
            ToolbarItem.SYMBOLS -> togglePanel(PanelKind.SYMBOLS)
            ToolbarItem.VOICE -> {
                commitAll()
                startActivity(Intent(this, com.startown.starkeyboard.VoiceInputActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
            ToolbarItem.SETTINGS -> togglePanel(PanelKind.SETTINGS)
            ToolbarItem.TRANSLATE -> beginEditor(EditorPurpose.TRANSLATE)
            ToolbarItem.FANCY -> beginEditor(EditorPurpose.FANCY)
            ToolbarItem.HANDWRITING -> {
                closePanel()
                if (mode == InputMode.HANDWRITING) {
                    switchMode()
                } else {
                    if (InputMode.HANDWRITING !in settings.enabledModes) settings.enabledModes = settings.enabledModes + InputMode.HANDWRITING
                    commitAll()
                    mode = InputMode.HANDWRITING
                    settings.lastMode = mode
                    layer = KeyboardLayer.LETTERS
                    rebuildKeys()
                }
            }
            ToolbarItem.DISMISS -> {
                commitAll()
                requestHideSelf(0)
            }
        }
    }

    private fun togglePanel(kind: PanelKind) {
        if (panel == kind) closePanel() else openPanel(kind)
    }

    private fun openPanel(kind: PanelKind) {
        commitAll()
        finishHangul()
        closePanel()
        panel = kind
        val v: View = when (kind) {
            PanelKind.EMOJI, PanelKind.KAOMOJI, PanelKind.SYMBOLS -> EmojiPanel(this, kind, emoStore, style,
                onInsert = { feedback(); output(it) },
                onSticker = { sendSticker(it) },
                onAdd = { addEmoticon(it) },
                onBack = { closePanel() },
                onBackspace = { deleteOutput() })
            PanelKind.CLIPBOARD -> {
                captureClipboard()
                ClipboardPanel(this, clipStore, style,
                    onInsert = { feedback(); output(it) },
                    onAddCurrent = { addCurrentClipboard() },
                    onEditCategory = { name ->
                        renamingCategory = name
                        beginEditor(EditorPurpose.CLIPBOARD_CATEGORY)
                        editorText = name ?: ""
                        refreshTopBar()
                    },
                    onTransfer = {
                        startActivity(Intent(this, com.startown.starkeyboard.ClipboardTransferActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    },
                    onBack = { closePanel() },
                    onBackspace = { deleteOutput() })
            }
            PanelKind.SETTINGS -> SettingsPanel(this, settings, style,
                onChange = { settingsChanged() },
                onOpenApp = { openApp() },
                onAdjustPhoto = { startPhotoAdjust() },
                shortcuts = shortcuts,
                onAddShortcut = { beginEditor(EditorPurpose.SHORTCUT_PHRASE) },
                onResetLearning = { engine?.resetLearning(); toast("已清除選字學習紀錄") },
                onBack = { closePanel() })
        }
        // 面板墊一層半透明的底，放背景照片時字和按鈕才看得清楚（設定的字多，墊厚一點）
        val strong = if (kind == PanelKind.SETTINGS) 0.82f else 0.6f
        v.setBackgroundColor(if (style.theme.dark) android.graphics.Color.BLACK.withAlpha(strong - 0.2f) else android.graphics.Color.WHITE.withAlpha(strong))
        content.addView(v, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        panelView = v
        keyboard.visibility = View.GONE
        handwriting?.visibility = View.GONE
    }

    // ===== 調整背景照片（直接在鍵盤上拖拉、縮放，看到的就是實際的樣子） =====

    private fun startPhotoAdjust() {
        val r = root ?: return
        if (!settings.hasBackground) {
            toast("先到糯糯鍵盤 App 挑一張照片")
            return
        }
        if (photoAdjust != null) return
        commitAll()
        closePanel()
        column.alpha = 0.35f
        val overlay = PhotoAdjustOverlay(this, style,
            onPan = { dx, dy -> bgImage.pan(dx, dy) },
            onScale = { f -> bgImage.zoomBy(f) },
            onReset = { bgImage.zoom = 1f; bgImage.focusX = 0.5f; bgImage.focusY = 0.3f; bgImage.pan(0f, 0f) },
            onDone = { finishPhotoAdjust() })
        r.addView(overlay, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        photoAdjust = overlay
    }

    private fun finishPhotoAdjust() {
        val overlay = photoAdjust ?: return
        root?.removeView(overlay)
        photoAdjust = null
        column.alpha = 1f
        settings.backgroundZoom = bgImage.zoom
        settings.backgroundFocusX = bgImage.focusX
        settings.backgroundFocusY = bgImage.focusY
        toast("照片位置存好了")
    }

    private fun closePanel() {
        panelView?.let { content.removeView(it) }
        panelView = null
        panel = null
        val showHandwriting = mode == InputMode.HANDWRITING && layer == KeyboardLayer.LETTERS
        keyboard.visibility = if (showHandwriting) View.GONE else View.VISIBLE
        handwriting?.visibility = if (showHandwriting) View.VISIBLE else View.GONE
    }

    private fun settingsChanged() {
        clipStore.limit = settings.clipLimit
        // 換了按鍵音：播一下讓你聽聽看
        if (settings.keySoundStyle != lastSoundStyle) {
            lastSoundStyle = settings.keySoundStyle
            if (settings.keySound) playKeySound()
        }
        engine?.fuzzy = fuzzyOptions()
        if (mode !in settings.enabledModes) {
            mode = settings.enabledModes.first()
            settings.lastMode = mode
            layer = KeyboardLayer.LETTERS
        }
        val oldKey = styleKey
        applyStyle()
        rebuildKeys()
        // 換了主題或造型才重建設定面板（拖滑桿時不重建，不然滑桿會被拿掉）
        if (panel == PanelKind.SETTINGS && oldKey != styleKey) {
            openPanel(PanelKind.SETTINGS)
        }
    }

    private fun openApp() {
        startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    // ===== 剪貼簿 =====

    private fun captureClipboard() {
        if (!settings.clipboardHistoryEnabled) return
        runCatching {
            val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            if (cm.primaryClipDescription?.extras?.getBoolean("android.content.extra.IS_SENSITIVE", false) == true) return
            val clip = cm.primaryClip ?: return
            if (clip.description.extras?.getBoolean("android.content.extra.IS_SENSITIVE", false) == true) return
            if (clip.itemCount == 0) return
            val text = clip.getItemAt(0).coerceToText(this)?.toString() ?: return
            if (clipStore.add(text)) (panelView as? ClipboardPanel)?.reload()
        }
    }

    private fun addCurrentClipboard() {
        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = cm.primaryClip
        if (clip?.description?.extras?.getBoolean("android.content.extra.IS_SENSITIVE", false) == true) {
            toast("已略過標示為敏感的剪貼簿內容")
            return
        }
        val text = clip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(this)?.toString()
        if (text.isNullOrBlank() || !clipStore.add(text)) {
            toast("剪貼簿裡沒有文字")
            return
        }
        (panelView as? ClipboardPanel)?.reload()
    }

    // ===== 編輯框（新增表符、翻譯） =====

    private fun beginEditor(purpose: EditorPurpose) {
        commitAll()
        finishHangul()
        suggestions = emptyList()
        editorReturnPanel = if (purpose == EditorPurpose.EMOTICON || purpose == EditorPurpose.SHORTCUT_PHRASE || purpose == EditorPurpose.CLIPBOARD_CATEGORY) panel else null
        closePanel()
        if (purpose != EditorPurpose.TRANSLATE && mode == InputMode.HANDWRITING) {
            mode = settings.enabledModes.firstOrNull { it != InputMode.HANDWRITING } ?: InputMode.ZHUYIN
        }
        layer = KeyboardLayer.LETTERS
        editorPurpose = purpose
        editorText = ""
        editorResult = null
        rebuildKeys()
        refreshTopBar()
        toast(when (purpose) {
            EditorPurpose.EMOTICON -> "用鍵盤打字，或按 (•ᴗ•) 挑顏文字零件"
            EditorPurpose.TRANSLATE -> "先打要翻譯的話，按「→語言」換目標語言"
            EditorPurpose.FANCY -> "打想變花樣的字（英文樣式最多），再按「變花樣」"
            EditorPurpose.SHORTCUT_PHRASE -> "先打常用的整段話，例如地址、自我介紹"
            EditorPurpose.SHORTCUT_CODE -> "再打縮寫"
            EditorPurpose.CLIPBOARD_CATEGORY -> "自己取一個分類名稱，最多 40 字"
        })
    }

    private fun editorExtraTapped() {
        if (editorPurpose == EditorPurpose.EMOTICON) {
            togglePanel(PanelKind.KAOMOJI)
        } else if (editorPurpose == EditorPurpose.TRANSLATE) {
            val targets = Translator.targets
            val i = maxOf(0, targets.indexOfFirst { it.code == settings.translateTarget })
            settings.translateTarget = targets[(i + 1) % targets.size].code
            refreshTopBar()
        }
    }

    private fun confirmEditor() {
        commitAll()
        finishHangul()
        val text = editorText?.trim() ?: return
        if (editorPurpose == EditorPurpose.EMOTICON) {
            if (text.isNotEmpty()) {
                emoStore.addCustom(text)
                toast("已加入我的表符")
            }
            val back = editorReturnPanel
            endEditor()
            back?.let { openPanel(it) }
            return
        }
        when (editorPurpose) {
            EditorPurpose.CLIPBOARD_CATEGORY -> {
                try {
                    val old = renamingCategory
                    if (old == null) clipStore.addCategory(text) else clipStore.renameCategory(old, text)
                    endEditor(); openPanel(PanelKind.CLIPBOARD)
                } catch (e: Exception) { toast(e.message ?: "無法儲存分類") }
                return
            }
            EditorPurpose.FANCY -> {
                if (text.isEmpty()) { toast("先打想變花樣的字"); return }
                editorResult = EditorResult("點一個樣式送出（可以左右滑）", FancyText.variants(text))
                refreshTopBar()
                refreshReturnTitle()
                return
            }
            EditorPurpose.SHORTCUT_PHRASE -> {
                if (text.isEmpty()) { toast("先打片語內容"); return }
                pendingPhrase = editorText ?: text
                editorPurpose = EditorPurpose.SHORTCUT_CODE
                editorText = ""
                refreshTopBar()
                refreshReturnTitle()
                toast("再打縮寫，例如「地址」或「addr」")
                return
            }
            EditorPurpose.SHORTCUT_CODE -> {
                if (text.isEmpty()) { toast("先打縮寫"); return }
                shortcuts.add(text, pendingPhrase)
                pendingPhrase = ""
                toast("好了！打「$text」就會出現這段話")
                val back = editorReturnPanel
                endEditor()
                back?.let { openPanel(it) }
                return
            }
            else -> {}
        }
        if (text.isEmpty()) {
            toast("先打要翻譯的話")
            return
        }
        if (translating) return
        translating = true
        refreshTopBar()
        Translator.translate(text, settings.translateSource, settings.translateTarget, settings.allowOnlineTranslation, status = { toast(it) }) { result ->
            translating = false
            if (editorText == null) return@translate
            result.onSuccess { editorResult = EditorResult("點翻譯結果送出 ・ 原文：$text", listOf(it)) }.onFailure { toast(it.message ?: "翻譯失敗") }
            refreshTopBar()
            refreshReturnTitle()
        }
    }

    private fun endEditor() {
        composer.clear()
        kanaBuffer = ""
        pinyinBuffer = ""
        hangul.reset()
        hangulComposing = false
        candidates = emptyList()
        editorText = null
        editorReturnPanel = null
        editorResult = null
        translating = false
        refreshTopBar()
        rebuildKeys()
    }

    // ===== 我的表符、貼圖 =====

    private fun addEmoticon(option: EmojiPanel.AddOption) {
        when (option) {
            EmojiPanel.AddOption.TYPE -> beginEditor(EditorPurpose.EMOTICON)
            EmojiPanel.AddOption.CLIPBOARD_TEXT -> {
                val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                val clip = cm.primaryClip
        if (clip?.description?.extras?.getBoolean("android.content.extra.IS_SENSITIVE", false) == true) {
            toast("已略過標示為敏感的剪貼簿內容")
            return
        }
        val text = clip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(this)?.toString()
                if (text.isNullOrBlank()) {
                    toast("剪貼簿裡沒有文字")
                    return
                }
                emoStore.addCustom(text)
                (panelView as? EmojiPanel)?.reload()
                toast("已加入我的表符")
            }
            EmojiPanel.AddOption.PICK_IMAGE -> {
                startActivity(Intent(this, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    .putExtra(MainActivity.EXTRA_PICK, MainActivity.PICK_STICKER))
            }
        }
    }

    /** 貼圖：App 支援的話直接送出圖片，不支援就複製到剪貼簿 */
    private fun sendSticker(name: String) {
        val file = emoStore.stickerFile(name) ?: return
        val uri = runCatching { FileProvider.getUriForFile(this, "$packageName.files", file) }.getOrNull() ?: return
        val info = currentInputEditorInfo
        val ic = currentInputConnection
        val types = if (info != null) EditorInfoCompat.getContentMimeTypes(info) else emptyArray()
        val supports = types.any { ClipDescription.compareMimeTypes("image/png", it) }
        if (supports && ic != null && info != null) {
            val content = InputContentInfoCompat(uri, ClipDescription("貼圖", arrayOf("image/png")), null)
            if (InputConnectionCompat.commitContent(ic, info, content, InputConnectionCompat.INPUT_CONTENT_GRANT_READ_URI_PERMISSION, null)) return
        }
        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        cm.setPrimaryClip(ClipData.newUri(contentResolver, "貼圖", uri))
        toast("這個 App 不能直接送圖，已複製貼圖，長按輸入框「貼上」")
    }

    // ===== 主題與版面 =====

    private fun applyStyle() {
        val r = root ?: return
        val s = style
        styleKey = s.theme.id + s.shape.name + s.fontId
        r.background = GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, intArrayOf(s.theme.top, s.theme.bottom))
        if (settings.hasBackground) {
            // 拖滑桿時也會跑這裡：照片沒換就不用重新讀檔
            val file = settings.backgroundFile
            val stamp = file.path + ":" + file.lastModified()
            if (stamp != backgroundStamp || bgImage.drawable == null) {
                bgImage.setImageBitmap(BitmapFactory.decodeFile(file.path))
                backgroundStamp = stamp
            }
            if (photoAdjust == null) {
                bgImage.zoom = settings.backgroundZoom
                bgImage.focusX = settings.backgroundFocusX
                bgImage.focusY = settings.backgroundFocusY
            }
            bgImage.visibility = View.VISIBLE
            tint.setBackgroundColor(s.theme.top.withAlpha(settings.backgroundFade))
            tint.visibility = View.VISIBLE
        } else {
            bgImage.setImageDrawable(null)
            backgroundStamp = ""
            bgImage.visibility = View.GONE
            tint.visibility = View.GONE
        }
        topBar.style = s
        keyboard.style = s
        handwriting?.style = s
        toastView.background = roundRect(s.theme.accent.withAlpha(0.95f), 14 * dp)
        toastView.setTextColor(s.theme.accentText)
        refreshTopBar()
    }

    private var lastReturnTitle = ""

    private val returnTitle: String
        get() {
            if (isComposing) return "確認"
            if (editorResult != null) return "送出"
            if (editorText != null) return editorConfirmTitle(editorPurpose)
            val info = currentInputEditorInfo ?: return "換行"
            if (info.imeOptions and EditorInfo.IME_FLAG_NO_ENTER_ACTION != 0) return "換行"
            return when (info.imeOptions and EditorInfo.IME_MASK_ACTION) {
                EditorInfo.IME_ACTION_GO -> "前往"
                EditorInfo.IME_ACTION_SEARCH -> "搜尋"
                EditorInfo.IME_ACTION_SEND -> "傳送"
                EditorInfo.IME_ACTION_NEXT -> "下一項"
                EditorInfo.IME_ACTION_DONE -> "完成"
                else -> "換行"
            }
        }

    private val spaceTitle get() = style.theme.decoration.let { if (it.isEmpty()) mode.title else "$it ${mode.title}" }

    private fun refreshReturnTitle() {
        if (returnTitle != lastReturnTitle) rebuildKeys()
    }

    private val isLandscape get() = resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE

    private fun contentHeight(): Int {
        val fiveRows = mode == InputMode.ZHUYIN && layer == KeyboardLayer.LETTERS
        val base = if (isLandscape) (if (fiveRows) 196f else 164f) else (if (fiveRows) 252f else 216f)
        val scale = if (isLandscape) minOf(settings.heightScale, 1.1f) else settings.heightScale
        return (base * scale * dp).toInt()
    }

    private fun rebuildKeys() {
        if (root == null) return
        lastReturnTitle = returnTitle
        val ctx = KeyLayouts.Context(mode, layer, shift, returnTitle, spaceTitle, nextModeTitle, settings.fullWidthSymbols)
        keyboard.setLayout(KeyLayouts.layout(ctx))
        keyboard.glideEnabled = mode == InputMode.ENGLISH && layer == KeyboardLayer.LETTERS && settings.glideTyping
        val showHandwriting = mode == InputMode.HANDWRITING && layer == KeyboardLayer.LETTERS
        if (showHandwriting) {
            val hw = handwriting ?: HandwritingPanel(this, style, ink).also { hw ->
                hw.side.onKey = { handle(it) }
                hw.side.onLongPress = { showImePicker() }
                hw.onResult = { results ->
                    suggestions = results
                    suggestionSource = SuggestionSource.HANDWRITING
                    refreshTopBar()
                }
                hw.onAutoCommit = {
                    if (suggestionSource == SuggestionSource.HANDWRITING) {
                        suggestions.firstOrNull()?.let { output(it) }
                        suggestions = emptyList()
                        refreshTopBar()
                    }
                }
                content.addView(hw, 0, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
                handwriting = hw
            }
            hw.side.setLayout(KeyLayouts.handwritingSide(returnTitle, nextModeTitle))
        } else {
            handwriting?.let { content.removeView(it) }
            handwriting = null
            if (suggestionSource == SuggestionSource.HANDWRITING) clearSuggestions()
        }
        if (panelView == null) {
            keyboard.visibility = if (showHandwriting) View.GONE else View.VISIBLE
        } else {
            handwriting?.visibility = View.GONE
        }
        candidatePanel?.bringToFront()
        content.layoutParams = content.layoutParams.apply { height = contentHeight() }
    }

    // ===== 回饋、提醒 =====

    // 可愛按鍵音：第一次用到時才載入
    private var soundPool: android.media.SoundPool? = null
    private val soundIds = HashMap<String, Int>()
    private var lastSoundStyle = ""

    private fun playKeySound() {
        val style = KeySound.from(settings.keySoundStyle)
        if (style == KeySound.SYSTEM) {
            (getSystemService(Context.AUDIO_SERVICE) as AudioManager).playSoundEffect(AudioManager.FX_KEYPRESS_STANDARD, -1f)
            return
        }
        val pool = soundPool ?: android.media.SoundPool.Builder().setMaxStreams(4).setAudioAttributes(
            android.media.AudioAttributes.Builder()
                .setUsage(android.media.AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION).build(),
        ).build().also { p ->
            soundPool = p
            for (s in KeySound.values()) {
                if (s == KeySound.SYSTEM) continue
                val res = resources.getIdentifier("key_" + s.id, "raw", packageName)
                if (res != 0) soundIds[s.id] = p.load(this, res, 1)
            }
        }
        val id = soundIds[style.id] ?: return
        // 每次音高差一點點，連打時比較不單調
        pool.play(id, 0.6f, 0.6f, 1, 0, 0.94f + Math.random().toFloat() * 0.12f)
    }

    private fun feedback() {
        if (settings.keySound) playKeySound()
        if (settings.haptics) root?.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP, HapticFeedbackConstants.FLAG_IGNORE_VIEW_SETTING)
    }

    private var toastToken = 0

    private fun toast(text: String) {
        if (root == null) return
        val token = ++toastToken
        toastView.text = text
        toastView.bringToFront()
        toastView.animate().alpha(1f).setDuration(150).start()
        mainHandler.postDelayed({
            if (toastToken == token) toastView.animate().alpha(0f).setDuration(300).start()
        }, 1800)
    }

    /** 每 6 小時最多問一次 GitHub；有新版就提醒一次 */
    private fun checkForUpdate() {
        val now = System.currentTimeMillis()
        if (now - settings.lastUpdateCheck < 6 * 3600 * 1000L) {
            showUpdateNotice()
            return
        }
        settings.lastUpdateCheck = now
        UpdateFetcher.fetch { info ->
            if (info != null) {
                settings.latestBuild = info.build
                showUpdateNotice()
            }
        }
    }

    private fun showUpdateNotice() {
        val latest = settings.latestBuild
        if (latest <= BuildInfo.current(this) || latest <= settings.notifiedBuild) return
        settings.notifiedBuild = latest
        toast("有新版！打開糯糯鍵盤 App 更新")
    }
}
