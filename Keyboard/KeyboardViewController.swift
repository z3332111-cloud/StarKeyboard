import UIKit
import AudioToolbox
import Vision
import CoreImage
import ImageIO

private final class KeyboardInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
    var onWindowChange: (() -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?()
    }
}

final class KeyboardViewController: UIInputViewController {
    private enum Metrics {
        static let barHeight: CGFloat = 64
    }

    private enum SuggestionSource { case association, handwriting, spelling, glide }

    /// 上面那條編輯框的用途：新增表符，或是先打中文再翻譯
    private enum EditorPurpose { case emoticon, symbol, clipboardSearch, translate, fancy, shortcutPhrase, shortcutCode, clipboardCategory, clipboardItem }
    private var renamingCategory: String?
    private var editingClipID: UUID?
    /// 編輯框裡的游標位置（第幾個字後面）；nil = 永遠在最後面
    private var editorCursor: Int?
    private var folderNameBox: FolderNameBox!
    private var namingFolder: Bool { editorText != nil && editorPurpose == .clipboardCategory }
    /// 改剪貼簿：用和新增資料夾一樣的小對話框
    private var editingClipBox: Bool { editorText != nil && editorPurpose == .clipboardItem && editorResult == nil }
    /// 搜尋剪貼簿：上面一個小框打關鍵字，候選列列出找到的
    private var searchingClip: Bool { editorText != nil && editorPurpose == .clipboardSearch && editorResult == nil }
    private var clipResults: [ClipItem] = []
    private var folderBoxHeight: CGFloat { (namingFolder || searchingClip) ? 84 : (editingClipBox ? FolderNameBox.clipHeight : 0) }

    /// 編輯框顯示的字：有游標時只顯示游標附近，中間放 ▏ 表示游標
    private func editorDisplay(_ text: String) -> String {
        guard let c = editorCursor else { return text }
        let chars = Array(text)
        let i = max(0, min(chars.count, c))
        let before = chars[max(0, i - 14)..<i]
        let after = chars[i..<min(chars.count, i + 10)]
        return (i > 14 ? "…" : "") + String(before) + "▏" + String(after) + (chars.count - i > 10 ? "…" : "")
    }

    private func editorLabel(_ p: EditorPurpose) -> String {
        switch p {
        case .emoticon: return "表符："
        case .symbol: return "新增符號："
        case .translate: return "翻譯："
        case .fancy: return "花式文字："
        case .shortcutPhrase: return "片語內容："
        case .shortcutCode: return "縮寫："
        case .clipboardCategory: return "分類名稱："
        case .clipboardItem: return "編輯剪貼簿："
        case .clipboardSearch: return "搜尋剪貼簿："
        }
    }

    private func editorConfirmTitle(_ p: EditorPurpose) -> String {
        switch p {
        case .translate: return "翻譯"
        case .fancy: return "變花樣"
        case .shortcutPhrase: return "下一步"
        default: return "儲存"
        }
    }

    private let settings = KeyboardSettings.shared
    private lazy var clipboardTransfer = ClipboardTransferController(presenter: self, store: clipStore, style: { [unowned self] in self.style }) { [weak self] in
        (self?.panelView as? ClipboardPanelView)?.reload()
    }
    private lazy var clipStore = ClipboardStore(fileURL: Storage.url("clipboard.json"), limit: settings.clipLimit)
    private lazy var emoStore = EmoticonStore(directory: Storage.directory)
    private var learningModels: [UserPhraseModel] = []
    /// 字典在背景讀進記憶體。按鍵當下不開 SQLite。
    private var zhuyinEngineStore: ZhuyinEngine?
    private var pinyinEngineStore: PinyinEngine?
    private var converterStore: ChineseConverter?
    private var engine: ZhuyinEngine? { zhuyinEngineStore }
    private var pinyinEngine: PinyinEngine? { pinyinEngineStore }
    private var converter: ChineseConverter? { converterStore }
    private var candidateGeneration = 0
    private lazy var textChecker = UITextChecker()
    /// 剛剛自動修正的字：馬上按刪除就改回原本打的
    private var lastAutocorrect: (original: String, corrected: String)?

    private var fuzzyOptions: ZhuyinEngine.FuzzyOptions {
        ZhuyinEngine.FuzzyOptions(keyNeighbors: settings.fuzzyKeys, tones: settings.fuzzyTones, phonetic: settings.fuzzyPhonetic)
    }

    // 狀態
    private var mode: InputMode = .zhuyin
    private var layer: KeyboardLayer = .letters
    private var shift: ShiftState = .off
    private var lastShiftTap = Date.distantPast
    private var lastSpaceTime = Date.distantPast
    private let zhuyin = ZhuyinSession()
    private var composer: ZhuyinComposer {
        get { zhuyin.composer }
        set { zhuyin.composer = newValue }
    }
    private var kanaBuffer = ""              // 日文：還沒送出的羅馬拼音
    private var pinyinBuffer = ""            // 拼音：還沒送出的字母
    private var candidateOriginals: [String] = []   // 拼音候選轉簡體前的原文（學習、聯想詞用）
    private var hangul = HangulComposer()
    private var hangulShown = ""             // 韓文：已經放進輸入框、還在拼的那個字
    private var candidates: [Candidate] = []
    /// 每個字的部首（候選字面板用部首篩選）
    private var radicals: [Character: String] = [:]
    private var suggestions: [String] = []
    private var suggestionSource: SuggestionSource = .association
    private var panel: PanelKind?
    private var editorText: String?          // 編輯框裡的字（nil = 沒在用編輯框）
    private var editorPurpose: EditorPurpose = .emoticon
    private var editorReturnPanel: PanelKind?
    /// 編輯框打完後的結果（翻譯、花式文字）：點一個送出，最後一個「✏️ 修改」回去改
    private var editorResult: (title: String, items: [String])?
    /// 新增快捷片語：先打片語內容，再打縮寫
    private var pendingPhrase = ""
    private lazy var shortcutStore = ShortcutStore(fileURL: Storage.url("shortcuts.json"))
    /// 英文滑行輸入（字表在背景載入）
    private var glide: GlideDecoder?
    private var lastGlide: String?
    private var translating = false
    /// 快速翻譯：直接把輸入框裡的字換成翻譯（original 原文、current 現在輸入框裡的字）
    private var quick: (original: String, current: String)?
    private var lastReturnTitle = ""
    private var backgroundImage: UIImage?
    private var clipboardTimer: Timer?
    private var heightConstraint: NSLayoutConstraint?
    private let layoutDiagnostics = KeyboardLayoutDiagnostics()
    /// 看不見的「量高度用的尺」：上下貼齊鍵盤，iOS 照它決定鍵盤多高
    private let heightRuler = UIView()
    private var toastToken = 0
    private lazy var haptic = UIImpactFeedbackGenerator(style: .light)
    /// 移動游標時每動一格的輕輕「喀」
    private lazy var tick = UISelectionFeedbackGenerator()
    /// 連續上下換行時要回到的直排位置（左右移動後重算）
    private var goalColumn: Int?

    // 畫面
    private let backdropView = KeyboardBackdropView()
    private let gradientLayer = CAGradientLayer()
    private let foxPaperLayer = CALayer()
    private let backgroundImageView = UIImageView()
    private var photoAdjustView: PhotoAdjustView?
    /// 邊看鍵盤邊調大小（蓋在選字列的位置）
    private var sizeBar: SizeAdjustBar?
    private let tintOverlay = UIView()
    private var topBar: TopBarView!
    private let contentView = UIView()
    private var grid: KeyboardGridView!
    private var panelView: UIView?
    private var candidatePanel: CandidatePanelView?
    private var handwritingView: HandwritingView?
    private let toastLabel = UILabel()

    private var style: KeyboardStyle {
        FoxLetterTheme.resolved(KeyboardStyle(theme: KeyboardTheme.named(settings.themeID), shape: settings.keyShape, keyAlpha: settings.keyAlpha,
                      fontScale: settings.fontScale, gapScale: settings.gapScale, fontID: settings.fontID,
                      keyEffect: settings.keyEffect, finish: settings.keyFinish, shapeScale: settings.shapeScale, motion: settings.keyMotion))
    }

    /// 注音或日文正在組字
    private var isComposing: Bool { composer.isComposing || !kanaBuffer.isEmpty || !pinyinBuffer.isEmpty }

    // MARK: - 生命週期

    override func loadView() {
        view = KeyboardInputView(frame: .zero, inputViewStyle: .keyboard)
        (view as? KeyboardInputView)?.onWindowChange = { [weak self] in
            self?.layoutDiagnostics.record("inputView.didMoveToWindow", force: true)
        }
        // 保留系統鍵盤材質，讓自訂背景邊緣能銜接系統管理的區域。
        view.backgroundColor = .clear
        view.isOpaque = false
    }

    deinit {
        for id in soundIDs.values { AudioServicesDisposeSystemSoundID(id) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // 讓 iOS 照我們自己設的高度（不然「鍵盤高度」滑桿會被系統的預設高度蓋掉）
        (view as? UIInputView)?.allowsSelfSizing = true
        heightRuler.isUserInteractionEnabled = false
        heightRuler.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(heightRuler, at: 0)
        NSLayoutConstraint.activate([
            heightRuler.topAnchor.constraint(equalTo: view.topAnchor),
            heightRuler.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            heightRuler.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            heightRuler.widthAnchor.constraint(equalToConstant: 1),
        ])
        let modes = settings.enabledModes
        mode = modes.contains(settings.lastMode) ? settings.lastMode : modes[0]

        view.clipsToBounds = true   // 照片放大後會超出鍵盤，超出的部分不要畫
        view.addSubview(backdropView)
        backdropView.layer.insertSublayer(gradientLayer, at: 0)
        backdropView.layer.addSublayer(foxPaperLayer)
        foxPaperLayer.contentsRect = CGRect(x: 0, y: 0.2, width: 1, height: 0.8)
        foxPaperLayer.isHidden = true
        backgroundImageView.contentMode = .scaleAspectFill
        backgroundImageView.clipsToBounds = true
        backdropView.addSubview(backgroundImageView)
        backdropView.addSubview(tintOverlay)

        topBar = TopBarView(style: style)
        view.addSubview(topBar)
        folderNameBox = FolderNameBox()
        folderNameBox.isHidden = true
        folderNameBox.onSave = { [weak self] in self?.confirmEditor() }
        folderNameBox.onCancel = { [weak self] in
            guard let self = self else { return }
            // 改剪貼簿的 endEditor 自己會打開剪貼簿
            let wasClip = self.editorPurpose == .clipboardItem
            self.endEditor()
            if !wasClip { self.openPanel(.clipboard) }
        }
        // 改剪貼簿：點文字就把游標移過去（按住空白鍵滑也可以）
        folderNameBox.onTapIndex = { [weak self] i in
            guard let self = self, self.editorPurpose == .clipboardItem, let t = self.editorText else { return }
            if self.isComposing { self.commitAll() }
            self.editorCursor = min(i, self.editorText?.count ?? t.count)
            self.refreshTopBar()
        }
        view.addSubview(folderNameBox)
        view.addSubview(contentView)
        grid = KeyboardGridView(style: style)
        contentView.addSubview(grid)

        toastLabel.font = .rounded(14, .semibold)
        toastLabel.textAlignment = .center
        toastLabel.layer.cornerRadius = 14
        toastLabel.clipsToBounds = true
        toastLabel.alpha = 0
        toastLabel.numberOfLines = 2
        view.addSubview(toastLabel)

        view.isMultipleTouchEnabled = true
        contentView.isMultipleTouchEnabled = true
        wireCallbacks()
        loadBackground()
        applyStyle()
        rebuildKeys()
        refreshTopBar()
        preloadDictionary()
    }

    /// 鍵盤一出現就在背景把字典索引建好。這一段不碰畫面。
    private func preloadDictionary() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let path = Bundle.main.path(forResource: "zhuyin", ofType: "sqlite"),
                  let db = SQLiteDB(path: path) else { return }
            let index = PhraseIndex.load(from: db)
            let zhuyinUser = UserPhraseModel(fileURL: Storage.url("learned.json"), asynchronousWrites: true)
            let zhuyin = ZhuyinEngine(db: db, userModel: zhuyinUser, sharedIndex: index)
            let pinyinUser = UserPhraseModel(fileURL: Storage.url("learned-pinyin.json"), asynchronousWrites: true)
            let pinyinCore = ZhuyinEngine(db: db, userModel: pinyinUser, column: "plain", sharedIndex: index)
            let pinyin = PinyinEngine(engine: pinyinCore, table: PinyinEngine.loadTable(from: db))
            let converter = ChineseConverter(db: db)
            let radicals = Radicals.load(from: db)
            let prefixes = zhuyin.syllablePrefixes()
            let fullSyllables = zhuyin.completeSyllables()
            DispatchQueue.main.async {
                guard let self = self else { return }
                zhuyin.fuzzy = self.fuzzyOptions
                self.zhuyinEngineStore = zhuyin
                self.zhuyin.engine = zhuyin
                self.pinyinEngineStore = pinyin
                self.converterStore = converter
                self.radicals = radicals
                self.learningModels = [zhuyinUser, pinyinUser]
                if !prefixes.isEmpty { self.composer.validPrefixes = prefixes }
                if !fullSyllables.isEmpty { self.composer.validSyllables = fullSyllables }
                if self.isComposing { self.updateCandidatesNow() }
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        layoutDiagnostics.record("viewWillAppear.beforeUpdates", force: true)
        loadGlideWords()
        prepareKeySound()
        // 背景照片輪播
        settings.rotatePhoto()
        loadBackground()
        applyStyle()
        captureClipboard()
        checkForUpdate()
        clipboardTimer?.invalidate()
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.captureClipboard()
        }
        rebuildKeys()
        updateAutoShift()
        startLiveLook()
    }

    // MARK: - App 裡邊調邊看：App 拖滑桿時，鍵盤馬上跟著變

    private var liveLookTimer: Timer?
    private var liveLookCount = -1

    private var currentLook: LiveLook {
        var l = LiveLook()
        l.heightScale = Double(settings.heightScale)
        l.fontScale = Double(settings.fontScale)
        l.gapScale = Double(settings.gapScale)
        l.shapeScale = Double(settings.shapeScale)
        l.keyAlpha = Double(settings.keyAlpha)
        l.backgroundFade = Double(settings.backgroundFade)
        return l
    }

    private func startLiveLook() {
        guard hasFullAccess else { return }
        // 先把鍵盤現在的值告訴 App（App 的滑桿才會從現在的位置開始）
        if let last = LiveLook.read(), last.from == "app", last.look != currentLook {
            applyLiveLook(last.look)
        }
        liveLookCount = currentLook.publish(from: "keyboard")
        liveLookTimer?.invalidate()
        liveLookTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let count = LiveLook.changeCount
            guard count != self.liveLookCount else { return }
            self.liveLookCount = count
            if let last = LiveLook.read(), last.from == "app", last.look != self.currentLook {
                self.applyLiveLook(last.look)
            }
        }
    }

    private func applyLiveLook(_ l: LiveLook) {
        settings.heightScale = CGFloat(l.heightScale)
        settings.fontScale = CGFloat(l.fontScale)
        settings.gapScale = CGFloat(l.gapScale)
        settings.shapeScale = CGFloat(l.shapeScale)
        settings.keyAlpha = CGFloat(l.keyAlpha)
        settings.backgroundFade = CGFloat(l.backgroundFade)
        settingsChanged()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        layoutDiagnostics.record("viewDidAppear.beforeExistingHeightReset", force: true)
        // 鍵盤剛載入時設的高度有時會被系統忽略：出現後重新套一次
        heightConstraint?.isActive = false
        heightConstraint = nil
        updateHeight()
        layoutDiagnostics.record("viewDidAppear.afterExistingHeightReset", force: true)
    }

    /// iOS 說記憶體快不夠了：先把可以重新讀的東西丟掉，免得鍵盤被系統強制關掉（閃退）
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        engine?.trimCaches()
        pinyinEngineStore?.engine.trimCaches()
        glide = nil   // 滑行輸入的字表，下次打開鍵盤再讀
        if panelView != nil && panel != .settings { closePanel() }   // 表符面板的圖片
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        layoutDiagnostics.record("viewWillDisappear", force: true)
        clipboardTimer?.invalidate()
        clipboardTimer = nil
        liveLookTimer?.invalidate()
        liveLookTimer = nil
        // 在鍵盤裡調過的大小也告訴 App
        if hasFullAccess { currentLook.publish(from: "keyboard") }
        for model in learningModels { model.flushPendingWrites() }
        finishHangul()
        finishPhotoAdjust()
    }

    // 液態玻璃：模糊過的背景照片（照片、淡化、主題沒變就不重做）
    private var glassKey = ""

    private func updateGlass() {
        guard style.finish == .liquid, !style.usesNativeGlassKeys, let img = backgroundImage else {
            glassKey = ""
            if GlassBackdrop.image != nil { GlassBackdrop.image = nil; GlassBackdrop.version += 1; grid.refreshGlass() }
            return
        }
        let key = "\(loadedPhoto ?? "")|\(settings.backgroundFade)|\(style.theme.id)"
        if key != glassKey {
            glassKey = key
            GlassBackdrop.image = Self.blurredGlass(img, tint: style.theme.backgroundTop.withAlphaComponent(settings.backgroundFade))
            GlassBackdrop.version += 1
        }
        let rect = backdropView.convert(backgroundImageView.frame, to: grid)
        if rect != GlassBackdrop.rect {
            GlassBackdrop.rect = rect
            GlassBackdrop.version += 1
        }
        grid.refreshGlass()
    }

    /// 照片縮到最長邊 360，蓋上淡化那層顏色，再模糊（只做一次，每顆鍵共用）
    private static func blurredGlass(_ image: UIImage, tint: UIColor) -> CGImage? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let s = min(1, 360 / longest)
        let size = CGSize(width: max(1, image.size.width * s), height: max(1, image.size.height * s))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        // 先縮成很小（約 1/8）再放大回來，就是柔柔的模糊；不用 CoreImage（它在鍵盤裡會佔一大塊顯示記憶體）
        let tinySize = CGSize(width: max(1, (size.width / 8).rounded()), height: max(1, (size.height / 8).rounded()))
        let tiny = UIGraphicsImageRenderer(size: tinySize, format: format).image { ctx in
            ctx.cgContext.interpolationQuality = .medium
            image.draw(in: CGRect(origin: .zero, size: tinySize))
            tint.setFill()
            ctx.fill(CGRect(origin: .zero, size: tinySize))
        }
        let soft = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            ctx.cgContext.interpolationQuality = .high
            tiny.draw(in: CGRect(origin: .zero, size: size))
        }
        return soft.cgImage
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdropView.frame = b
        gradientLayer.frame = b
        foxPaperLayer.frame = b
        CATransaction.commit()
        backgroundImageView.frame = backgroundFrame(in: b)
        photoAdjustView?.frame = b
        tintOverlay.frame = b
        folderNameBox.frame = CGRect(x: 10, y: 6, width: b.width - 20, height: max(0, folderBoxHeight - 10))
        let barH = CGFloat(settings.candidateBarHeight)
        topBar.candidateFontSize = CGFloat(CandidateBarMetrics.fontSize(barHeight: settings.candidateBarHeight))
        let barY = folderBoxHeight
        topBar.frame = CGRect(x: 0, y: barY, width: b.width, height: barH)
        sizeBar?.frame = CGRect(x: 0, y: barY, width: b.width, height: barH)
        contentView.frame = CGRect(x: 0, y: barY + barH, width: b.width, height: max(0, b.height - barH - barY))
        grid.frame = contentView.bounds
        panelView?.frame = contentView.bounds
        candidatePanel?.frame = contentView.bounds
        handwritingView?.frame = contentView.bounds
        updateGlass()
        let toastW = min(b.width - 40, 300)
        toastLabel.frame = CGRect(x: (b.width - toastW) / 2, y: barY + barH + 8, width: toastW, height: 44)
        layoutDiagnostics.record("viewDidLayoutSubviews")
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        layoutDiagnostics.record("viewSafeAreaInsetsDidChange", force: true)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.updateHeight() }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // 使用者自己點到別的地方：韓文正在拼的字就算拼完了
        if !hangulShown.isEmpty && !(textDocumentProxy.documentContextBeforeInput ?? "").hasSuffix(hangulShown) {
            finishHangul()
        }
        refreshReturnTitle()
        updateAutoShift()
    }

    // MARK: - 接線

    private func wireCallbacks() {
        grid.onKey = { [weak self] spec in self?.handle(spec) }
        // 手指一按下去就震動、出聲（不用等放開）
        grid.onPress = { [weak self] in self?.feedback() }
        grid.onGlobe = { [weak self] view, event in
            guard let event = event else { return }
            self?.handleInputModeList(from: view, with: event)
        }
        grid.onGlide = { [weak self] path, centers, kw in self?.glideTyped(path: path, centers: centers, keyWidth: kw) }
        grid.onCursorMode = { [weak self] on in
            guard let self = self else { return }
            self.goalColumn = nil
            if on { self.cursorTick() }
        }
        grid.onCursorMove = { [weak self] steps in
            guard let self = self else { return }
            self.cursorTick()
            self.goalColumn = nil
            // 打注音打到一半：游標在注音裡移動，可以只改打錯的那一個（像 iPhone 內建注音）
            if self.mode == .zhuyin, self.pinyinBuffer.isEmpty, self.kanaBuffer.isEmpty, self.composer.isComposing {
                self.zhuyin.moveCursor(steps)
                self.refreshTopBar()
                return
            }
            guard !self.isComposing else { return }
            // 在編輯框裡（例如改剪貼簿）：移動編輯框自己的游標
            if let c = self.editorCursor, let t = self.editorText {
                self.editorCursor = max(0, min(t.count, c + steps))
                self.refreshTopBar()
                return
            }
            self.finishHangul()
            self.textDocumentProxy.adjustTextPosition(byCharacterOffset: steps)
        }
        grid.onCursorLine = { [weak self] dir in
            guard let self = self, !self.isComposing, self.editorText == nil else { return }
            self.cursorTick()
            self.finishHangul()
            self.moveCursorLine(dir)
        }
        topBar.onScriptToggle = { [weak self] in
            guard let self = self, self.mode == .pinyin else { return }
            self.settings.pinyinSimplified.toggle()
            self.clearSuggestions(refresh: false)
            self.updateCandidates()
        }
        topBar.onToolbar = { [weak self] item in self?.toolbarTapped(item) }
        topBar.onCandidate = { [weak self] i in self?.selectCandidate(at: i, learn: true) }
        topBar.candidateFontSize = CGFloat(CandidateBarMetrics.fontSize(barHeight: settings.candidateBarHeight))
        topBar.onHeightDrag = { [weak self] dy in
            guard let self = self else { return }
            self.settings.candidateBarHeight += Double(dy)
            self.topBar.candidateFontSize = CGFloat(CandidateBarMetrics.fontSize(barHeight: self.settings.candidateBarHeight))
            self.updateHeight()
            self.view.setNeedsLayout()
        }
        topBar.onTrailing = { [weak self] trailing in
            guard let self = self else { return }
            switch trailing {
            case .expand:
                self.toggleCandidatePanel()
            case .close:
                if self.editorResult != nil {
                    self.endEditor()
                    return
                }
                // 搜尋剪貼簿：✕ 回到剪貼簿
                if self.searchingClip {
                    self.endEditor()
                    self.openPanel(.clipboard)
                    return
                }
                self.clearSuggestions()
                if self.suggestionSource == .handwriting { self.handwritingView?.clear() }
            }
        }
        topBar.onEditor = { [weak self] confirm in
            guard let self = self else { return }
            if self.quick != nil {
                // 快速翻譯：「還原」放回原文；✕ 留著翻譯
                if confirm { self.restoreQuickTranslate() } else { self.quick = nil; self.refreshTopBar() }
                return
            }
            if confirm { self.confirmEditor() } else { self.endEditor() }
        }
        topBar.onEditorExtra = { [weak self] in
            guard let self = self else { return }
            if let q = self.quick {
                let targets = Translator.targets
                let i = targets.firstIndex { $0.code == self.settings.translateTarget } ?? 0
                self.settings.translateTarget = targets[(i + 1) % targets.count].code
                self.runQuickTranslate(q.original)
                return
            }
            self.editorExtraTapped()
        }
        topBar.onEditorSource = { [weak self] in
            guard let self = self else { return }
            if let q = self.quick {
                let codes = ["auto"] + Translator.targets.map { $0.code }
                let i = codes.firstIndex(of: self.settings.translateSource) ?? 0
                self.settings.translateSource = codes[(i + 1) % codes.count]
                self.runQuickTranslate(q.original)
                return
            }
            // 新增表符、符號、快捷片語：把剪貼簿的文字貼進編輯框
            if self.editorPurpose == .emoticon || self.editorPurpose == .symbol || self.editorPurpose == .shortcutPhrase {
                self.pasteIntoEditor()
                return
            }
            // 原文語言：自動 → 英文 → 日文 → … 輪流換
            let codes = ["auto"] + Translator.targets.map { $0.code }
            let i = codes.firstIndex(of: self.settings.translateSource) ?? 0
            self.settings.translateSource = codes[(i + 1) % codes.count]
            self.refreshTopBar()
        }
    }

    // MARK: - 按鍵

    private func handle(_ spec: KeySpec) {
        if quick != nil {
            quick = nil
            refreshTopBar()
        }
        let pendingAutocorrect = lastAutocorrect
        lastAutocorrect = nil
        if spec.action == .backspace, let ac = pendingAutocorrect, revertAutocorrect(ac) { return }
        if case .jamo = spec.action {} else if spec.action != .backspace && spec.action != .shift {
            finishHangul()
        }
        switch spec.action {
        case .text(let s): typeText(s)
        case .zhuyin(let c): typeZhuyin(c)
        case .jamo(let c): typeJamo(c)
        case .romaji(let c): typeRomaji(c)
        case .pinyin(let c): typePinyin(c)
        case .backspace: backspace()
        case .space: space()
        case .returnKey: returnKey()
        case .shift: toggleShift()
        case .globe: break
        case .nextMode: switchMode()
        case .layer(let l):
            layer = l
            rebuildKeys()
        case .panel(let p): openPanel(p)
        case .clearCanvas:
            handwritingView?.clear()
            clearSuggestions()
        case .toggleWidth:
            settings.fullWidthSymbols.toggle()
            toast(settings.fullWidthSymbols ? "全形：（）：；？！" : "半形：():;?!")
            rebuildKeys()
        }
    }

    private func typeText(_ s: String) {
        if isComposing { commitAll() }
        clearSuggestions()
        // 英文打標點時，前一個字也順便修正
        if mode == .english, ".,!?;:".contains(s) { applyAutocorrect() }
        output(s)
        if shift == .on {
            shift = .off
            rebuildKeys()
        }
        updateSpelling()
    }

    // MARK: - 英文自動修正

    /// 游標前面正在打的英文字
    private var currentWord: String {
        guard editorText == nil, let before = textDocumentProxy.documentContextBeforeInput else { return "" }
        var word = ""
        for ch in before.reversed() {
            guard ch.isASCII && (ch.isLetter || ch == "'") else { break }
            word.insert(ch, at: word.startIndex)
        }
        return word
    }

    private func isMisspelled(_ word: String) -> Bool {
        let range = NSRange(location: 0, length: (word as NSString).length)
        let miss = textChecker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false, language: "en_US")
        return miss.location != NSNotFound
    }

    private func guesses(_ word: String) -> [String] {
        let range = NSRange(location: 0, length: (word as NSString).length)
        return textChecker.guesses(forWordRange: range, in: word, language: "en_US") ?? []
    }

    /// 打字時在上面列出拼字建議：第一個是原本打的，後面是修正和補完
    private func updateSpelling() {
        guard mode == .english, settings.autocorrect else { return }
        let word = currentWord
        guard word.count >= 2 else {
            if suggestionSource == .spelling { clearSuggestions() }
            return
        }
        var list: [String] = []
        if isMisspelled(word) { list += guesses(word).prefix(3) }
        let range = NSRange(location: 0, length: (word as NSString).length)
        list += (textChecker.completions(forPartialWordRange: range, in: word, language: "en_US") ?? []).prefix(5)
        var seen: Set<String> = [word]
        let options = (shortcutStore.matching(word) + list.map { Spelling.matchCase($0, like: word) }).filter { seen.insert($0).inserted }
        suggestions = options.isEmpty ? [] : [word] + options
        suggestionSource = .spelling
        refreshTopBar()
    }

    private func autocorrection(for word: String) -> String? {
        guard word.count >= 2, word.uppercased() != word, isMisspelled(word),
              let guess = guesses(word).first, Spelling.isCloseEnough(word, guess) else { return nil }
        return Spelling.matchCase(guess, like: word)
    }

    /// 把游標前打錯的字換掉；有換就回傳 true
    @discardableResult
    private func applyAutocorrect() -> Bool {
        guard mode == .english, editorText == nil, settings.autocorrect else { return false }
        let word = currentWord
        guard let fix = autocorrection(for: word) else { return false }
        for _ in word { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(fix)
        lastAutocorrect = (word, fix)
        return true
    }

    private func revertAutocorrect(_ ac: (original: String, corrected: String)) -> Bool {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        guard let last = before.last, !last.isLetter, before.dropLast().hasSuffix(ac.corrected) else { return false }
        for _ in 0...ac.corrected.count { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(last == " " ? ac.original : ac.original + String(last))
        UITextChecker.learnWord(ac.original)
        clearSuggestions()
        toast("已改回「\(ac.original)」，之後不會再改它")
        return true
    }

    private func typeZhuyin(_ c: Character) {
        clearSuggestions(refresh: false)
        if composer.validPrefixes == nil, let prefixes = engine?.syllablePrefixes(), !prefixes.isEmpty {
            composer.validPrefixes = prefixes
        }
        // 注音與聲調只進組字區。緩衝區很長時，前面那段先送出中文，這顆鍵仍留在後面。
        let committed = zhuyin.type(c)
        if !committed.isEmpty { output(committed) }
        refreshTopBar()
        scheduleCandidateRefresh()
    }

    private func typePinyin(_ c: Character) {
        clearSuggestions(refresh: false)
        if c == "'" && (pinyinBuffer.isEmpty || pinyinBuffer.hasSuffix("'")) { return }
        pinyinBuffer.append(c)
        if pinyinBuffer.count >= 60 {
            commitAll()
            return
        }
        updateCandidates()
    }

    /// 拼音模式要不要轉成簡體
    private func simplify(_ s: String) -> String {
        guard mode == .pinyin, settings.pinyinSimplified, let c = converter else { return s }
        return c.convert(s)
    }

    private func typeRomaji(_ c: Character) {
        clearSuggestions(refresh: false)
        kanaBuffer.append(c)
        if kanaBuffer.count >= 60 {
            commitAll()
            return
        }
        updateCandidates()
    }

    private func typeJamo(_ c: Character) {
        clearSuggestions()
        let out = hangul.input(c)
        showHangul(out.commit + out.composing, composing: out.composing)
        if shift == .on {
            shift = .off
            rebuildKeys()
        }
    }

    /// 韓文：把上次放進去、還在拼的字刪掉，換成新的
    private func showHangul(_ text: String, composing: String) {
        for _ in hangulShown { deleteOutput() }
        output(text)
        hangulShown = composing
    }

    private func finishHangul() {
        hangul.reset()
        hangulShown = ""
    }

    private func backspace() {
        if !pinyinBuffer.isEmpty {
            pinyinBuffer.removeLast()
            updateCandidates()
            return
        }
        if !kanaBuffer.isEmpty {
            kanaBuffer.removeLast()
            updateCandidates()
            return
        }
        if zhuyin.backspace() {
            updateCandidatesNow()
            return
        }
        if !hangulShown.isEmpty && hangul.backspace() {
            showHangul(hangul.composing, composing: hangul.composing)
            return
        }
        finishHangul()
        clearSuggestions()
        deleteOutput()
        updateAutoShift()
        updateSpelling()
    }

    private func space() {
        if mode == .zhuyin && layer == .letters && composer.hasPendingSyllable {
            _ = zhuyin.space()
            updateCandidatesNow()
            return
        }
        if mode == .zhuyin && layer == .letters && composer.isComposing {
            updateCandidatesNow()
            switch zhuyin.space() {
            case .passthrough:
                break
            case .stay:
                if zhuyin.cursor != nil { updateCandidatesNow() } else { refreshTopBar() }
                return
            case .commit(let text):
                if !text.isEmpty { output(text) }
                showAssociations(after: text)
                refreshTopBar()
                refreshReturnTitle()
                return
            }
        }
        _ = composer.consumeStrayTone()
        if isComposing {
            updateCandidatesNow()
            if candidates.isEmpty { commitAll() } else { selectCandidate(at: 0, learn: false) }
            return
        }
        if suggestionSource == .handwriting && !suggestions.isEmpty {
            selectCandidate(at: 0, learn: false)
            return
        }
        clearSuggestions()
        // 英文：快速按兩下空白變成句號
        if mode == .english, editorText == nil, Date().timeIntervalSince(lastSpaceTime) < 0.4,
           let before = textDocumentProxy.documentContextBeforeInput, before.hasSuffix(" "),
           let prev = before.dropLast().last, prev.isLetter || prev.isNumber {
            deleteOutput()
            output(". ")
            lastSpaceTime = .distantPast
            updateAutoShift()
            return
        }
        applyAutocorrect()
        lastSpaceTime = Date()
        output(" ")
        updateAutoShift()
    }

    private func returnKey() {
        if isComposing {
            updateCandidatesNow()
            // 拼音打到一半按換行：送出打的英文字母（例如 apps），不是中文候選字
            commitAll(rawPinyin: true)
            return
        }
        if editorResult != nil {
            selectCandidate(at: 0, learn: false)
            return
        }
        if editorText != nil {
            confirmEditor()
            return
        }
        clearSuggestions()
        output("\n")
        updateAutoShift()
    }

    private func toggleShift() {
        let now = Date()
        let quick = now.timeIntervalSince(lastShiftTap) < 0.35
        switch shift {
        case .off: shift = .on
        case .on: shift = quick ? .locked : .off
        case .locked: shift = .off
        }
        lastShiftTap = now
        rebuildKeys()
    }

    private func updateAutoShift() {
        guard mode == .english, layer == .letters, shift != .locked, editorText == nil else { return }
        let type = textDocumentProxy.autocapitalizationType ?? .sentences
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        var want = false
        switch type {
        case .allCharacters:
            want = true
        case .words:
            want = before.isEmpty || before.hasSuffix(" ") || before.hasSuffix("\n")
        case .sentences:
            let trimmed = before.trimmingCharacters(in: .whitespaces)
            want = before.isEmpty || before.hasSuffix("\n")
                || (before.hasSuffix(" ") && (trimmed.last.map { ".!?".contains($0) } ?? false))
        default:
            want = false
        }
        let newShift: ShiftState = want ? .on : .off
        if newShift != shift {
            shift = newShift
            rebuildKeys()
        }
    }

    private func switchMode() {
        commitAll()
        finishHangul()
        clearSuggestions()
        let modes = settings.enabledModes
        if let i = modes.firstIndex(of: mode) {
            mode = modes[(i + 1) % modes.count]
        } else {
            mode = modes[0]
        }
        settings.lastMode = mode
        layer = .letters
        shift = .off
        rebuildKeys()
        updateAutoShift()
    }

    private var nextModeTitle: String {
        let modes = settings.enabledModes
        guard modes.count > 1 else { return mode.shortTitle }
        let i = modes.firstIndex(of: mode) ?? 0
        return modes[(i + 1) % modes.count].shortTitle
    }

    // MARK: - 輸出（用編輯框時打到編輯框，平常打到 App）

    private func output(_ s: String) {
        guard !s.isEmpty else { return }
        if editorText != nil && editorResult == nil {
            if let c = editorCursor, let t = editorText {
                let i = t.index(t.startIndex, offsetBy: min(c, t.count))
                editorText!.insert(contentsOf: s, at: i)
                editorCursor = min(c, t.count) + s.count
            } else {
                editorText! += s
            }
            refreshTopBar()
            return
        }
        textDocumentProxy.insertText(s)
    }

    private func deleteOutput() {
        if var t = editorText, editorResult == nil {
            if let c = editorCursor {
                if c > 0, c <= t.count {
                    t.remove(at: t.index(t.startIndex, offsetBy: c - 1))
                    editorCursor = c - 1
                }
            } else if !t.isEmpty {
                t.removeLast()
            }
            editorText = t
            refreshTopBar()
            return
        }
        textDocumentProxy.deleteBackward()
    }

    // MARK: - 選字（注音、日文）

    private let candidateQueue = DispatchQueue(label: "star.zhuyin.candidates", qos: .userInteractive)

    /// 按鍵當下只更新組字區。選字在背景算，下一個鍵會取消還沒用上的結果。
    private func scheduleCandidateRefresh() {
        candidateGeneration += 1
        let generation = candidateGeneration
        let readings = composer.readings
        let context = settings.associations ? (editorText ?? textDocumentProxy.documentContextBeforeInput ?? "") : ""
        let engine = self.engine
        candidateQueue.async { [weak self] in
            let list = readings.isEmpty ? [] : (engine?.candidates(for: readings, before: context) ?? [])
            DispatchQueue.main.async {
                guard let self = self, generation == self.candidateGeneration else { return }
                self.applyZhuyinCandidates(list)
            }
        }
    }

    private func applyZhuyinCandidates(_ raw: [Candidate]) {
        guard pinyinBuffer.isEmpty, kanaBuffer.isEmpty else {
            updateCandidates()
            return
        }
        if composer.readings.isEmpty {
            candidates = []
            zhuyin.candidates = []
        } else {
            let cleaned = raw.compactMap { c -> Candidate? in
                let text = PhoneticText.commit(c.text)
                guard !text.isEmpty else { return nil }
                return Candidate(text: text, span: c.span, kind: c.kind, reading: c.reading)
            }
            candidates = withRawZhuyin(withShortcuts(cleaned).filter { !PhoneticText.containsPhonetic($0.text) && !$0.text.isEmpty })
            zhuyin.candidates = candidates
        }
        if !isComposing { closeCandidatePanel() }
        candidatePanel?.setCandidates(candidates.map { $0.text })
        refreshTopBar()
        refreshReturnTitle()
    }

    /// 空白、退格、換行要馬上看見新的候選，不能用上一拍的結果。
    private func updateCandidatesNow() {
        candidateGeneration += 1
        let generation = candidateGeneration
        guard pinyinBuffer.isEmpty, kanaBuffer.isEmpty, !composer.readings.isEmpty, engine != nil else {
            updateCandidates()
            return
        }
        let readings = composer.readings
        let context = settings.associations ? (editorText ?? textDocumentProxy.documentContextBeforeInput ?? "") : ""
        let engine = self.engine
        let list = candidateQueue.sync { engine?.candidates(for: readings, before: context) ?? [] }
        guard generation == candidateGeneration else { return }
        applyZhuyinCandidates(list)
    }

    private func updateCandidates() {
        candidateOriginals = []
        if !pinyinBuffer.isEmpty {
            // 拼音：查到的是繁體，要的話轉成簡體；轉完一樣的只留一個
            let raw = pinyinEngine?.candidates(for: pinyinBuffer) ?? []
            var seen = Set<String>()
            var list: [Candidate] = []
            for c in raw {
                let shown = simplify(c.text)
                guard seen.insert(shown).inserted else { continue }
                list.append(Candidate(text: shown, span: c.span, kind: c.kind))
                candidateOriginals.append(c.text)
            }
            candidates = list
        } else if !kanaBuffer.isEmpty {
            let hiragana = Romaji.finalize(kanaBuffer)
            var texts = [hiragana, Romaji.katakana(hiragana), kanaBuffer]
            var seen = Set<String>()
            texts = texts.filter { seen.insert($0).inserted }
            candidates = texts.map { Candidate(text: $0, span: 0, kind: .phrase) }
        } else if composer.readings.isEmpty {
            candidates = []
        } else if engine != nil {
            let context = settings.associations ? (editorText ?? textDocumentProxy.documentContextBeforeInput ?? "") : ""
            zhuyin.refresh(context: context)
            candidates = zhuyin.candidates
        } else {
            candidates = []
            zhuyin.candidates = []
        }
        if !composer.readings.isEmpty && pinyinBuffer.isEmpty && kanaBuffer.isEmpty {
            candidates = withRawZhuyin(withShortcuts(candidates).filter { !PhoneticText.containsPhonetic($0.text) && !$0.text.isEmpty })
            zhuyin.candidates = candidates
        }
        if !isComposing { closeCandidatePanel() }
        candidatePanel?.setCandidates(candidates.map { $0.text })
        refreshTopBar()
        refreshReturnTitle()
    }

    /// 直接送出注音本身（例如 ㄓㄜㄧㄤㄇ）：放在第 4 個（前面是最常用的字詞）
    private func withRawZhuyin(_ list: [Candidate]) -> [Candidate] {
        let raw = String(composer.keys.filter { $0 != "ˉ" && $0 != "*" && $0 != "~" && $0 != " " })
        guard !raw.isEmpty, !list.contains(where: { $0.text == raw }) else { return list }
        let at = min(3, list.count)
        return Array(list.prefix(at)) + [Candidate(text: raw, span: composer.readings.count, kind: .raw)] + Array(list.dropFirst(at))
    }

    /// 快捷片語：打的字（整句）或注音（例如 ㄉㄓ）和縮寫一樣，就把片語放在第二個
    private func withShortcuts(_ list: [Candidate]) -> [Candidate] {
        guard !shortcutStore.items.isEmpty else { return list }
        let typed = composer.readings.map { r in String(r.filter { !Bopomofo.tones.contains($0) && $0 != "*" && $0 != "~" }) }.joined()
        var seen = Set<String>()
        let phrases = ([list.first?.text, typed].compactMap { $0 }).flatMap { shortcutStore.matching($0) }.filter { seen.insert($0).inserted }
        guard !phrases.isEmpty else { return list }
        let extra = phrases.map { Candidate(text: $0, span: composer.readings.count, kind: .literal) }
        let at = min(1, list.count)
        return Array(list.prefix(at)) + extra + Array(list.dropFirst(at))
    }

    private var compositionText: String {
        if !pinyinBuffer.isEmpty {
            return pinyinEngine?.display(pinyinBuffer) ?? pinyinBuffer
        }
        if !kanaBuffer.isEmpty {
            let r = Romaji.convert(kanaBuffer)
            return r.kana + r.rest
        }
        // 上排顯示真正按過的注音，中文預覽留在下排候選字，方便找出按錯的音。
        return zhuyin.displayText
    }

    private func selectCandidate(at i: Int, learn: Bool) {
        // 搜尋剪貼簿：點找到的那一筆就貼上
        if searchingClip && !isComposing {
            guard i < clipResults.count else { return }
            let text = clipResults[i].text
            endEditor()
            textDocumentProxy.insertText(text)
            feedback()
            return
        }
        if let r = editorResult {
            editorResult = nil
            if i < r.items.count {
                editorText = nil
                editorCursor = nil
                textDocumentProxy.insertText(r.items[i])
                rebuildKeys()
            }
            refreshTopBar()
            refreshReturnTitle()
            return
        }
        if !pinyinBuffer.isEmpty {
            guard i < candidates.count else { return }
            let c = candidates[i]
            let original = i < candidateOriginals.count ? candidateOriginals[i] : c.text
            if let p = pinyinEngine {
                if learn && c.kind != .literal {
                    let readings = p.readings(for: p.segment(pinyinBuffer))
                    p.engine.learn(readings: Array(readings.prefix(c.span)), text: original)
                }
                let used = p.consumedLength(pinyinBuffer, span: c.span)
                pinyinBuffer = String(pinyinBuffer.dropFirst(used))
                while pinyinBuffer.hasPrefix("'") { pinyinBuffer.removeFirst() }
            } else {
                pinyinBuffer = ""
            }
            output(c.text)
            if !pinyinBuffer.isEmpty {
                updateCandidates()
            } else {
                candidates = []
                candidateOriginals = []
                closeCandidatePanel()
                showAssociations(after: original)
                refreshReturnTitle()
            }
            return
        }
        if !kanaBuffer.isEmpty {
            guard i < candidates.count else { return }
            let text = candidates[i].text
            kanaBuffer = ""
            candidates = []
            closeCandidatePanel()
            output(text)
            refreshTopBar()
            refreshReturnTitle()
            return
        }
        if composer.isComposing {
            candidateGeneration += 1
            candidateQueue.sync {}
            let text = zhuyin.pick(i, learn: learn)
            if !text.isEmpty { output(text) }
            candidates = zhuyin.candidates
            if composer.isComposing {
                updateCandidates()
            } else {
                closeCandidatePanel()
                showAssociations(after: text)
                refreshReturnTitle()
            }
        } else if suggestionSource == .glide, i < suggestions.count {
            // 滑行輸入認錯了：換成點的那個字
            let choice = suggestions[i]
            if let last = lastGlide, choice != last, textDocumentProxy.documentContextBeforeInput?.hasSuffix(last) == true {
                for _ in last { textDocumentProxy.deleteBackward() }
                textDocumentProxy.insertText(choice)
                lastGlide = choice
            }
            clearSuggestions()
        } else if suggestionSource == .spelling, i < suggestions.count {
            // 換掉正在打的英文字，後面補一個空白
            let word = currentWord
            let choice = suggestions[i]
            if choice != word {
                for _ in word { textDocumentProxy.deleteBackward() }
                textDocumentProxy.insertText(choice)
            }
            textDocumentProxy.insertText(" ")
            clearSuggestions()
            updateAutoShift()
        } else if i < suggestions.count {
            let s = suggestions[i]
            output(s)
            if suggestionSource == .handwriting { handwritingView?.clear() }
            if PunctuationSuggestions.marks.contains(s) {
                clearSuggestions()   // 打完標點就收起來
            } else {
                showAssociations(after: s)
            }
        }
    }

    // MARK: - 英文滑行輸入

    private func loadGlideWords() {
        guard glide == nil, let url = Bundle.main.url(forResource: "glide_words", withExtension: "txt") else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
            let decoder = GlideDecoder(text: text)
            DispatchQueue.main.async { self?.glide = decoder }
        }
    }

    private func glideTyped(path: [CGPoint], centers: [Character: CGPoint], keyWidth: CGFloat) {
        guard let decoder = glide else {
            loadGlideWords()
        prepareKeySound()
            toast("英文字表還在載入，等一下再試")
            return
        }
        let words = decoder.decode(path: path, centers: centers, keyWidth: keyWidth)
        guard !words.isEmpty else {
            toast("沒認出來，再滑一次看看")
            return
        }
        let shaped = words.map { w -> String in
            switch shift {
            case .locked: return w.uppercased()
            case .on: return w.prefix(1).uppercased() + w.dropFirst()
            case .off: return w
            }
        }
        // 前面是字的話先補一個空白
        let before = editorText ?? textDocumentProxy.documentContextBeforeInput ?? ""
        let needSpace = before.last.map { !$0.isWhitespace && !"([{\"'".contains($0) } ?? false
        output((needSpace ? " " : "") + shaped[0])
        if shift == .on {
            shift = .off
            rebuildKeys()
        }
        guard editorText == nil else { return }
        lastGlide = shaped[0]
        suggestions = shaped
        suggestionSource = .glide
        refreshTopBar()
    }

    /// rawPinyin：拼音照打的字母送出（拼音打到一半按換行鍵，像三星鍵盤）
    private func commitAll(rawPinyin: Bool = false) {
        guard isComposing else { return }
        var text = ""
        if !pinyinBuffer.isEmpty {
            // 拼音：送出整句（第一個候選）；完全查不到就照打的字母送出
            text = (rawPinyin ? nil : candidates.first?.text) ?? pinyinBuffer.replacingOccurrences(of: "'", with: "")
            pinyinBuffer = ""
            candidateOriginals = []
        } else if !kanaBuffer.isEmpty {
            text = Romaji.finalize(kanaBuffer)
            kanaBuffer = ""
        } else {
            candidateGeneration += 1
            candidateQueue.sync {}
            text = zhuyin.commitAll()
            candidates = []
        }
        candidates = []
        closeCandidatePanel()
        output(text)
        refreshTopBar()
        refreshReturnTitle()
    }

    private func showAssociations(after text: String) {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let context = before.hasSuffix(text) ? before : before + text
        if settings.associations, editorText == nil, mode == .zhuyin || mode == .handwriting, let engine = engine {
            suggestions = engine.associations(after: context)
        } else if settings.associations, editorText == nil, mode == .pinyin, let p = pinyinEngine {
            // 拼音：用繁體原文查，結果再轉簡體
            var seen = Set<String>()
            suggestions = p.engine.associations(after: text).map { simplify($0) }.filter { seen.insert($0).inserted }
        } else {
            suggestions = []
        }
        // 中文模式：選字那排最前面放標點，看起來是問句就把「？」排第一個
        if editorText == nil, mode == .zhuyin || mode == .handwriting || mode == .pinyin {
            let punctuation = PunctuationSuggestions.after(context)
            // 先露出兩個聯想詞，再放其餘標點，避免四個符號擋住所有詞。
            suggestions = Array(punctuation.prefix(1)) + Array(suggestions.prefix(2)) +
                Array(punctuation.dropFirst()) + Array(suggestions.dropFirst(2))
        }
        suggestionSource = .association
        refreshTopBar()
    }

    private func clearSuggestions(refresh: Bool = true) {
        guard !suggestions.isEmpty else { return }
        suggestions = []
        if refresh { refreshTopBar() }
    }

    private func refreshTopBar() {
        guard topBar != nil else { return }
        folderNameBox.isHidden = !(namingFolder || editingClipBox || searchingClip)
        if searchingClip {
            clipResults = searchClipboard(editorText ?? "")
            folderNameBox.updateSearch(text: editorText ?? "", composing: isComposing ? compositionText : "", style: style)
        }
        if namingFolder {
            folderNameBox.update(name: editorText ?? "", renaming: renamingCategory != nil, style: style)
        } else if editingClipBox {
            folderNameBox.updateClip(text: editorText ?? "", cursor: editorCursor,
                                     composing: isComposing ? compositionText : "", style: style)
        }
        topBar.scriptTitle = mode == .pinyin && editorResult == nil ? (settings.pinyinSimplified ? "簡" : "繁") : nil
        if let q = quick {
            let name = Translator.targets.first { $0.code == settings.translateTarget }?.name ?? "英文"
            let from = Translator.targets.first { $0.code == settings.translateSource }?.name ?? "自動"
            topBar.show(.editor(prompt: translating ? "翻譯中…" : "已翻成\(name)・原文：", text: q.original, extra: "→\(name)",
                                confirm: "還原", source: "從：\(from)"))
        } else if let r = editorResult {
            topBar.show(.candidates(composition: r.title, items: r.items + ["✏️ 修改"], trailing: .close))
        } else if isComposing {
            // 用編輯框時，前面也顯示已經打好的字
            let prefix = editingClipBox ? "" : (editorText.map { editorLabel(editorPurpose) + editorDisplay($0) + " ｜ " } ?? "")
            topBar.show(.candidates(composition: prefix + compositionText, items: candidates.map { $0.text },
                                    trailing: .expand))
        } else if namingFolder && suggestions.isEmpty {
            topBar.show(.candidates(composition: "用下方鍵盤輸入名稱，再按建立", items: [], trailing: .expand))
        } else if searchingClip {
            let q = editorText ?? ""
            let title = q.isEmpty ? "打關鍵字就會開始找（最近的在前面）" : (clipResults.isEmpty ? "找不到，換個字試試" : "找到 " + String(clipResults.count) + " 筆，點一下貼上")
            topBar.show(.candidates(composition: title, items: clipResults.map { clipPreview($0.text) }, trailing: .close))
        } else if editingClipBox && suggestions.isEmpty {
            topBar.show(.candidates(composition: "用下方鍵盤修改，改好按上面的「儲存」", items: [], trailing: .expand))
        } else if let text = editorText, suggestions.isEmpty || suggestionSource == .association {
            switch editorPurpose {
            case .emoticon:
                topBar.show(.editor(prompt: "新增表符：", text: text, extra: "(•ᴗ•)", confirm: "儲存", source: "📋 貼上"))
            case .symbol:
                topBar.show(.editor(prompt: "新增符號：", text: text, extra: "※", confirm: "儲存", source: "📋 貼上"))
            case .shortcutPhrase:
                // 很長的地址、自我介紹：先在別的地方複製，再按「📋 貼上」
                topBar.show(.editor(prompt: editorLabel(editorPurpose), text: editorDisplay(text), extra: "", confirm: editorConfirmTitle(editorPurpose), source: "📋 貼上"))
            case .translate:
                let name = Translator.targets.first { $0.code == settings.translateTarget }?.name ?? "英文"
                let from = Translator.targets.first { $0.code == settings.translateSource }?.name ?? "自動"
                topBar.show(.editor(prompt: translating ? "翻譯中…" : "翻譯：", text: text, extra: "→\(name)",
                                    confirm: "翻譯", source: "從：\(from)"))
            default:
                topBar.show(.editor(prompt: editorLabel(editorPurpose), text: editorDisplay(text), extra: "", confirm: editorConfirmTitle(editorPurpose)))
            }
        } else if !suggestions.isEmpty {
            topBar.show(.candidates(composition: "", items: suggestions, trailing: .close))
        } else {
            topBar.show(.toolbar)
        }
    }

    private func toggleCandidatePanel() {
        if candidatePanel != nil {
            closeCandidatePanel()
            return
        }
        let p = CandidatePanelView(style: style)
        p.onSelect = { [weak self] i in self?.selectCandidate(at: i, learn: true) }
        p.onBack = { [weak self] in self?.closeCandidatePanel() }
        p.onBackspace = { [weak self] in self?.backspace() }
        p.radicalOf = { [weak self] c in self?.radicals[c] }
        p.setCandidates(candidates.map { $0.text })
        p.frame = contentView.bounds
        // 不透明的底，而且先把後面的按鍵藏起來，候選字才不會跟按鍵疊在一起看不清楚
        contentView.addSubview(p)
        candidatePanel = p
        grid.isHidden = true
        handwritingView?.isHidden = true
    }

    private func closeCandidatePanel() {
        guard let p = candidatePanel else { return }
        p.removeFromSuperview()
        candidatePanel = nil
        // 按鍵恢復（有開別的面板就維持藏著）
        let showHandwriting = mode == .handwriting && layer == .letters
        if panelView == nil {
            grid.isHidden = showHandwriting
            handwritingView?.isHidden = !showHandwriting
        }
    }

    // MARK: - 工具列與面板

    private func toolbarTapped(_ item: ToolbarItem) {
        feedback()
        finishHangul()
        switch item {
        case .clipboard: togglePanel(.clipboard)
        case .emoji: togglePanel(.emoji)
        case .kaomoji: togglePanel(.kaomoji)
        case .symbols: togglePanel(.symbols)
        case .voice:
            // 鍵盤裡不能跳系統的提示框（會閃退），改成畫在鍵盤上的說明卡
            showNotice(title: "語音輸入", message: "直接說話輸入：點鍵盤右下方的系統 🎙。若沒有麥克風，請到 iPhone 設定 → 一般 → 鍵盤 → 啟用聽寫；必要時長按 🌐 切到 Apple 鍵盤。\n\n也可打開桌面的「糯糯鍵盤」App → 語音轉文字，辨識後檢查並複製回來貼上。iPhone 不允許第三方鍵盤直接錄音。")
        case .settings: togglePanel(.settings)
        case .translate:
            if let text = fieldText(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isComposing {
                startQuickTranslate(text)
            } else {
                beginEditor(.translate)
            }
        case .fancy: beginEditor(.fancy)
        case .handwriting:
            closePanel()
            if mode == .handwriting {
                switchMode()
            } else {
                if !settings.enabledModes.contains(.handwriting) {
                    settings.enabledModes = settings.enabledModes + [.handwriting]
                }
                commitAll()
                mode = .handwriting
                settings.lastMode = mode
                layer = .letters
                rebuildKeys()
            }
        case .dismiss:
            commitAll()
            dismissKeyboard()
        }
    }

    private func togglePanel(_ kind: PanelKind) {
        if panel == kind { closePanel() } else { openPanel(kind) }
    }

    private func openPanel(_ kind: PanelKind) {
        commitAll()
        finishHangul()
        closePanel()
        panel = kind
        let v: UIView
        switch kind {
        case .emoji, .kaomoji, .symbols:
            let panelKind: EmojiPanelView.Kind = kind == .emoji ? .emoji : (kind == .kaomoji ? .kaomoji : .symbols)
            let p = EmojiPanelView(kind: panelKind, store: emoStore, style: style)
            p.onInsert = { [weak self] s in
                self?.feedback()
                self?.output(s)
            }
            p.onCopyImage = { [weak self] img in self?.copySticker(img) }
            p.onAdd = { [weak self] option in self?.addEmoticon(option) }
            p.onBack = { [weak self] in self?.closePanel() }
            p.onBackspace = { [weak self] in self?.deleteOutput() }
            v = p
        case .clipboard:
            captureClipboard()
            let p = ClipboardPanelView(store: clipStore, hasFullAccess: hasFullAccess, style: style)
            p.onInsert = { [weak self] s in
                self?.feedback()
                self?.output(s)
            }
            p.onTransfer = { [weak self] in
                guard let self = self else { return }
                guard self.hasFullAccess else { self.toast("請先開啟允許完整取用，再使用剪貼簿搬家"); return }
                self.clipboardTransfer.show()
            }
            p.onError = { [weak self] message in self?.toast(message) }
            p.autoRecord = settings.clipboardHistoryEnabled
            p.onToggleAuto = { [weak self, weak p] on in
                guard let self = self else { return }
                guard self.hasFullAccess || !on else {
                    p?.autoRecord = false
                    self.toast("要先開啟「允許完整取用」")
                    return
                }
                self.settings.clipboardHistoryEnabled = on
                // 打開時把現在剪貼簿的那則當成已看過，只記之後複製的
                if on { self.settings.lastPasteboardChange = UIPasteboard.general.changeCount }
                self.toast(on ? "自動記錄已開：之後複製的文字會自己存進來" : "自動記錄已關")
            }
            p.onEditCategory = { [weak self] name in
                guard let self = self else { return }
                self.renamingCategory = name
                self.beginEditor(.clipboardCategory)
                self.editorText = name ?? ""
                self.refreshTopBar()
            }
            p.onEdit = { [weak self] item in
                guard let self = self else { return }
                self.editingClipID = item.id
                self.beginEditor(.clipboardItem)
                self.editorText = item.text
                self.editorCursor = item.text.count   // 游標先放最後，按住空白鍵左右滑可以移動
                self.toast("按住空白鍵左右滑，移到要改的地方")
                self.refreshTopBar()
            }
            p.onAddCurrent = { [weak self] in self?.addCurrentClipboard() }
            p.onSearch = { [weak self] in self?.beginEditor(.clipboardSearch) }
            p.onBack = { [weak self] in self?.closePanel() }
            p.onBackspace = { [weak self] in self?.deleteOutput() }
            v = p
        case .settings:
            shortcutStore.load()
            let p = SettingsPanelView(settings: settings, hasFullAccess: hasFullAccess, style: style, shortcuts: shortcutStore)
            p.onAddShortcut = { [weak self] in self?.beginEditor(.shortcutPhrase) }
            p.onChange = { [weak self] in self?.settingsChanged() }
            p.onPasteBackground = { [weak self] in self?.pasteBackground() }
            p.onClearBackground = { [weak self] in self?.clearBackground() }
            p.onAdjustPhoto = { [weak self] in self?.startPhotoAdjust() }
            p.onLiveSize = { [weak self] in self?.startSizeAdjust() }
            p.onPasteFont = { [weak self] in self?.pasteFont() }
            p.onDownloadFont = { [weak self] id in self?.downloadFont(id) }
            p.onPasteSpaceImage = { [weak self] in self?.pasteSpaceImage() }
            p.onPasteSpaceEmoji = { [weak self] in self?.pasteSpaceEmoji() }
            p.onCopyTypingLog = { [weak self] in
                guard let self = self else { return }
                guard self.hasFullAccess else { self.toast("要先開啟「允許完整取用」才能複製"); return }
                let head = "糯糯鍵盤 v\(ReleaseChecker.currentVersion) iPhone 打字紀錄\n"
                UIPasteboard.general.string = head + self.zhuyin.log.joined(separator: "\n")
                self.toast("已複製 \(self.zhuyin.log.count) 筆紀錄，貼給開發的人")
            }
            p.onStartLayoutDiagnostics = { [weak self] in
                guard let self = self else { return }
                self.layoutDiagnostics.start { [weak self] in self?.layoutDiagnosticSnapshot() ?? "controller released" }
                self.closePanel()
                self.toast("版面診斷已開始，請切換 App 重現問題")
            }
            p.onCopyLayoutDiagnostics = { [weak self] in
                guard let self = self else { return }
                guard self.hasFullAccess else { self.toast("要先開啟「允許完整取用」才能複製"); return }
                guard let report = self.layoutDiagnostics.report() else {
                    self.toast("請先開始版面診斷，再重現問題")
                    return
                }
                UIPasteboard.general.setItems([["public.utf8-plain-text": report]],
                    options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(300)])
                self.settings.lastPasteboardChange = UIPasteboard.general.changeCount
                self.toast("已複製版面紀錄，請在 5 分鐘內貼出")
            }
            p.onStopLayoutDiagnostics = { [weak self] in
                self?.layoutDiagnostics.stop()
                self?.toast("版面診斷已停止，仍可複製本次紀錄")
            }
            p.onResetLearning = { [weak self] in
                self?.engine?.resetLearning()
                self?.toast("已清除選字學習紀錄")
            }
            p.onBack = { [weak self] in self?.closePanel() }
            v = p
        }
        // 面板墊一層半透明的底，放背景照片時字和按鈕才看得清楚（設定的字多，墊厚一點）
        let strong: CGFloat = kind == .settings ? 0.82 : 0.6
        v.backgroundColor = style.theme.isDark ? UIColor.black.withAlphaComponent(strong - 0.2) : UIColor.white.withAlphaComponent(strong)
        v.frame = contentView.bounds
        contentView.addSubview(v)
        panelView = v
        grid.isHidden = true
        handwritingView?.isHidden = true
    }

    private func closePanel() {
        panelView?.removeFromSuperview()
        panelView = nil
        panel = nil
        let showHandwriting = mode == .handwriting && layer == .letters
        grid.isHidden = showHandwriting
        handwritingView?.isHidden = !showHandwriting
    }

    private func settingsChanged() {
        loadBackground()   // 可能在設定裡換了照片
        prepareKeySound()
        // 換了按鍵音：播一下讓你聽聽看
        if settings.keySoundStyle != lastSoundStyle {
            lastSoundStyle = settings.keySoundStyle
            prepareKeySound()
            if settings.keySound && hasFullAccess { playKeySound() }
        }
        engine?.fuzzy = fuzzyOptions
        topBar.candidateFontSize = CGFloat(CandidateBarMetrics.fontSize(barHeight: settings.candidateBarHeight))
        clipStore.limit = settings.clipLimit
        updateHeight()
        view.setNeedsLayout()
        let modes = settings.enabledModes
        if !modes.contains(mode) {
            mode = modes[0]
            settings.lastMode = mode
            layer = .letters
        }
        applyStyle()
        rebuildKeys()
    }

    // MARK: - 剪貼簿

    private func captureClipboard() {
        guard hasFullAccess, settings.clipboardHistoryEnabled else { return }
        let pb = UIPasteboard.general
        guard pb.changeCount != settings.lastPasteboardChange else { return }
        settings.lastPasteboardChange = pb.changeCount
        guard ClipboardPrivacy.mayRecord(types: pb.types), pb.hasStrings, let s = pb.string else { return }
        if clipStore.add(s) {
            (panelView as? ClipboardPanelView)?.reload()
        }
    }

    private func addCurrentClipboard() {
        guard hasFullAccess else {
            toast("要先開啟「允許完整取用」")
            return
        }
        let pb = UIPasteboard.general
        guard ClipboardPrivacy.mayRecord(types: pb.types) else {
            toast("已略過標示為敏感或暫存的剪貼簿內容")
            return
        }
        guard let s = pb.string, clipStore.add(s) else {
            toast("剪貼簿裡沒有文字")
            return
        }
        (panelView as? ClipboardPanelView)?.reload()
    }

    // MARK: - 編輯框（新增表符、翻譯）

    private func beginEditor(_ purpose: EditorPurpose) {
        commitAll()
        finishHangul()
        clearSuggestions(refresh: false)
        editorReturnPanel = purpose == .emoticon || purpose == .symbol || purpose == .shortcutPhrase || purpose == .clipboardCategory ? panel : nil
        closePanel()
        if purpose != .translate && mode == .handwriting {
            mode = settings.enabledModes.first { $0 != .handwriting } ?? .zhuyin
        }
        layer = .letters
        editorPurpose = purpose
        editorText = ""
        editorResult = nil
        rebuildKeys()
        refreshTopBar()
        switch purpose {
        case .emoticon: toast("用鍵盤打字，或按 (•ᴗ•) 挑顏文字零件")
        case .symbol: toast("打想加的符號，空白隔開可以一次加好幾個")
        case .translate: toast("先打要翻譯的話，按「→語言」換目標語言")
        case .fancy: toast("打想變花樣的字（英文樣式最多），再按「變花樣」")
        case .shortcutPhrase: toast("打常用的整段話，或先複製好再按「📋 貼上」")
        case .shortcutCode: toast("再打縮寫")
        case .clipboardCategory: break
        case .clipboardItem: toast("改完按儲存。按取消會留下原本的文字")
        case .clipboardSearch: break
        }
    }

    private func editorExtraTapped() {
        switch editorPurpose {
        case .emoticon:
            togglePanel(.kaomoji)
        case .symbol:
            togglePanel(.symbols)
        case .translate:
            let targets = Translator.targets
            let i = targets.firstIndex { $0.code == settings.translateTarget } ?? 0
            settings.translateTarget = targets[(i + 1) % targets.count].code
            refreshTopBar()
        default:
            break
        }
    }

    private func confirmEditor() {
        commitAll()
        guard let text = editorText else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch editorPurpose {
        case .clipboardCategory:
            do {
                if let old = renamingCategory { try clipStore.renameCategory(old, to: trimmed) }
                else { try clipStore.addCategory(trimmed) }
                endEditor(); openPanel(.clipboard)
                (panelView as? ClipboardPanelView)?.selectCategory(trimmed)
            } catch { toast(error.localizedDescription) }
        case .clipboardSearch:
            endEditor()
            openPanel(.clipboard)
        case .clipboardItem:
            if let id = editingClipID, !trimmed.isEmpty {
                clipStore.updateText(id, text)
            }
            endEditor()
        case .emoticon:
            if !trimmed.isEmpty {
                // 貼了好幾行：每一行各自變成一個表符
                let n = addEmoticonLines(text)
                toast(n > 1 ? "已加入 \(n) 個表符" : "已加入我的表符")
            }
            let back = editorReturnPanel
            endEditor()
            if let p = back { openPanel(p) }
        case .symbol:
            let n = emoStore.addSymbols(trimmed)
            if n > 0 { toast("已加入 \(n) 個符號到「我的」") }
            let back = editorReturnPanel
            endEditor()
            if let p = back { openPanel(p) }
        case .fancy:
            guard !trimmed.isEmpty else {
                toast("先打想變花樣的字")
                return
            }
            editorResult = ("點一個樣式送出（可以左右滑）", FancyText.variants(trimmed))
            refreshTopBar()
            refreshReturnTitle()
        case .shortcutPhrase:
            guard !trimmed.isEmpty else {
                toast("先打片語內容")
                return
            }
            pendingPhrase = text
            editorPurpose = .shortcutCode
            editorText = ""
            refreshTopBar()
            refreshReturnTitle()
            toast("再打縮寫，例如「地址」或「addr」")
        case .shortcutCode:
            guard !trimmed.isEmpty else {
                toast("先打縮寫")
                return
            }
            shortcutStore.add(code: trimmed, phrase: pendingPhrase)
            pendingPhrase = ""
            toast("好了！打「\(trimmed)」就會出現這段話")
            let back = editorReturnPanel
            endEditor()
            if let p = back { openPanel(p) }
        case .translate:
            guard !trimmed.isEmpty else {
                toast("先打要翻譯的話")
                return
            }
            guard !translating else { return }
            translating = true
            refreshTopBar()
            Translator.translate(trimmed, from: settings.translateSource, to: settings.translateTarget, allowOnline: settings.allowOnlineTranslation) { [weak self] result in
                guard let self = self, self.editorText != nil else { return }
                self.translating = false
                switch result {
                case .success(let translated):
                    self.editorResult = ("點翻譯結果送出 ・ 原文：\(trimmed)", [translated])
                case .failure(.message(let message)):
                    self.toast(message)
                }
                self.refreshTopBar()
                self.refreshReturnTitle()
            }
        }
    }

    // MARK: - 快速翻譯

    /// 輸入框裡全部的字（系統只給游標前後一段，很長的文章可能不完整）
    private func fieldText() -> String? {
        guard editorText == nil else { return nil }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let after = textDocumentProxy.documentContextAfterInput ?? ""
        let all = before + after
        return all.isEmpty ? nil : all
    }

    /// 把輸入框的字整段換掉：游標移到最後，刪掉全部，再打上新的
    private func replaceField(with text: String) {
        let after = textDocumentProxy.documentContextAfterInput ?? ""
        if !after.isEmpty { textDocumentProxy.adjustTextPosition(byCharacterOffset: after.count) }
        var guardCount = 0
        while let before = textDocumentProxy.documentContextBeforeInput, !before.isEmpty, guardCount < 5000 {
            for _ in 0..<before.count { textDocumentProxy.deleteBackward() }
            guardCount += before.count
        }
        textDocumentProxy.insertText(text)
    }

    private func startQuickTranslate(_ text: String) {
        closePanel()
        quick = (text, text)
        runQuickTranslate(text)
    }

    private func runQuickTranslate(_ original: String) {
        guard !translating else { return }
        translating = true
        refreshTopBar()
        Translator.translate(original, from: settings.translateSource, to: settings.translateTarget, allowOnline: settings.allowOnlineTranslation) { [weak self] result in
            guard let self = self else { return }
            self.translating = false
            guard self.quick?.original == original else { self.refreshTopBar(); return }
            switch result {
            case .success(let translated):
                self.replaceField(with: translated)
                self.quick = (original, translated)
            case .failure(.message(let message)):
                self.toast(message)
                self.quick = nil
            }
            self.refreshTopBar()
        }
    }

    private func restoreQuickTranslate() {
        guard let q = quick else { return }
        replaceField(with: q.original)
        quick = nil
        refreshTopBar()
    }

    private func endEditor() {
        let reopenClipboard = editorPurpose == .clipboardItem
        closeCandidatePanel()
        composer.clear()
        kanaBuffer = ""
        pinyinBuffer = ""
        candidates = []
        editingClipID = nil
        editorText = nil
        editorCursor = nil
        editorReturnPanel = nil
        editorResult = nil
        translating = false
        refreshTopBar()
        rebuildKeys()
        if reopenClipboard { openPanel(.clipboard) }
    }

    // MARK: - 我的表符、貼圖

    private func addEmoticon(_ option: EmojiPanelView.AddOption) {
        let forSymbols = (panelView as? EmojiPanelView)?.kind == .symbols
        switch option {
        case .type:
            beginEditor(forSymbols ? .symbol : .emoticon)
        case .clipboardText:
            guard hasFullAccess else {
                toast("要先開啟「允許完整取用」")
                return
            }
            guard let s = UIPasteboard.general.string, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                toast("剪貼簿裡沒有文字")
                return
            }
            if forSymbols {
                let n = emoStore.addSymbols(s)
                (panelView as? EmojiPanelView)?.reload()
                toast("已加入 \(n) 個符號到「我的」")
                return
            }
            let n = addEmoticonLines(s)
            (panelView as? EmojiPanelView)?.reload()
            toast(n > 1 ? "已加入 \(n) 個表符（一行一個）" : "已加入我的表符")
        case .clipboardImage:
            guard hasFullAccess else {
                toast("要先開啟「允許完整取用」")
                return
            }
            guard let img = UIPasteboard.general.downsampledImage(maxSide: 512), let data = img.pngData() else {
                toast("剪貼簿裡沒有圖片，先到相簿「拷貝」一張")
                return
            }
            emoStore.addSticker(pngData: data)
            (panelView as? EmojiPanelView)?.reload()
            toast("已做成貼圖，點一下就能複製")
        }
    }

    /// 找剪貼簿：每個關鍵字都要出現（不分大小寫），最多 40 筆，最近的在前面
    private func searchClipboard(_ query: String) -> [ClipItem] {
        let words = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let all = clipStore.ordered
        guard !words.isEmpty else { return Array(all.prefix(40)) }
        var out: [ClipItem] = []
        for item in all {
            let t = item.text.lowercased()
            if words.allSatisfy({ t.contains($0) }) {
                out.append(item)
                if out.count >= 40 { break }
            }
        }
        return out
    }

    /// 候選列放不下整段：只顯示第一行前 16 個字
    private func clipPreview(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return line.count > 16 ? String(line.prefix(16)) + "…" : line
    }

    /// 一行一個表符加進「我的」，回傳加了幾個
    @discardableResult
    private func addEmoticonLines(_ text: String) -> Int {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for line in lines.reversed() { emoStore.addCustom(line) }
        return lines.count
    }

    /// 新增表符、符號的編輯框：把剪貼簿的文字貼在游標的位置
    private func pasteIntoEditor() {
        guard hasFullAccess else {
            toast("要先開啟「允許完整取用」才能貼上")
            return
        }
        guard let s = UIPasteboard.general.string, !s.isEmpty else {
            toast("剪貼簿裡沒有文字，先到別的地方「拷貝」")
            return
        }
        commitAll()
        output(s)
        refreshTopBar()
    }

    private func copySticker(_ image: UIImage) {
        guard hasFullAccess else {
            toast("要先開啟「允許完整取用」")
            return
        }
        UIPasteboard.general.image = image
        settings.lastPasteboardChange = UIPasteboard.general.changeCount
        toast("已複製貼圖！在輸入框長按「貼上」")
    }

    // MARK: - 主題與背景

    /// 照片放大到蓋滿鍵盤，對準的點（例如臉）盡量放在中間，超出的部分裁掉
    private func backgroundFrame(in b: CGRect) -> CGRect {
        guard let img = backgroundImage, img.size.width > 0, img.size.height > 0 else { return b }
        let s = max(b.width / img.size.width, b.height / img.size.height) * CGFloat(settings.backgroundZoom)
        let w = img.size.width * s
        let h = img.size.height * s
        let x = min(0, max(b.width - w, b.width / 2 - CGFloat(settings.backgroundFocusX) * w))
        let y = min(0, max(b.height - h, b.height / 2 - CGFloat(settings.backgroundFocusY) * h))
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// 照片裡最大那張臉的中心（0～1，左上是 0,0）；找不到回傳 nil（畫的人物可能找不到）
    private func faceCenter(in image: UIImage) -> CGPoint? {
        guard let cg = image.cgImage else { return nil }
        let request = VNDetectFaceRectanglesRequest()
        let orientation: CGImagePropertyOrientation
        switch image.imageOrientation {
        case .down: orientation = .down
        case .left: orientation = .left
        case .right: orientation = .right
        case .upMirrored: orientation = .upMirrored
        case .downMirrored: orientation = .downMirrored
        case .leftMirrored: orientation = .leftMirrored
        case .rightMirrored: orientation = .rightMirrored
        default: orientation = .up
        }
        try? VNImageRequestHandler(cgImage: cg, orientation: orientation, options: [:]).perform([request])
        let faces = request.results ?? []
        guard let face = faces.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }) else { return nil }
        // Vision 的座標原點在左下角
        let box = face.boundingBox
        return CGPoint(x: box.midX, y: 1 - box.midY)
    }

    // MARK: - 調整背景照片（直接在鍵盤上拖拉、縮放，看到的就是實際的樣子）

    // MARK: - 邊看鍵盤邊調大小：選字列換成滑桿，下面的鍵盤照常顯示、可以直接試打

    private func startSizeAdjust() {
        guard sizeBar == nil else { return }
        closePanel()
        let bar = SizeAdjustBar(style: style, settings: settings)
        bar.onChange = { [weak self] in self?.settingsChanged() }
        bar.onDone = { [weak self] in self?.finishSizeAdjust() }
        view.addSubview(bar)
        sizeBar = bar
        topBar.isHidden = true
        view.setNeedsLayout()
        toast("拖滑桿調整，下面的鍵盤可以直接試打")
    }

    private func finishSizeAdjust() {
        guard let bar = sizeBar else { return }
        bar.removeFromSuperview()
        sizeBar = nil
        topBar.isHidden = false
        toast("大小存好了")
    }

    private func startPhotoAdjust() {
        guard !style.isFoxLetter else {
            toast("照片已保留；切回一般主題後可調整位置")
            return
        }
        guard backgroundImage != nil else {
            toast("先貼上一張照片")
            return
        }
        guard photoAdjustView == nil else { return }
        commitAll()
        closePanel()
        topBar.isPhotoAdjusting = true
        grid.previewOpacity = 0.35
        let v = PhotoAdjustView(style: style)
        v.onPan = { [weak self] d in self?.panPhoto(by: d) }
        v.onPinch = { [weak self] f in
            guard let self = self else { return }
            self.settings.backgroundZoom *= Double(f)
            self.panPhoto(by: .zero)
        }
        v.onReset = { [weak self] in
            guard let self = self else { return }
            self.settings.backgroundZoom = 1
            self.settings.backgroundFocusX = 0.5
            self.settings.backgroundFocusY = 0.3
            self.panPhoto(by: .zero)
        }
        v.onDone = { [weak self] in self?.finishPhotoAdjust() }
        v.frame = view.bounds
        view.addSubview(v)
        photoAdjustView = v
    }

    private func finishPhotoAdjust() {
        guard let v = photoAdjustView else { return }
        v.removeFromSuperview()
        photoAdjustView = nil
        topBar.isPhotoAdjusting = false
        grid.previewOpacity = 1
        toast("照片位置存好了")
    }

    /// 手指拖了 d 點：照片跟著手指走（對準點不能太靠邊，不然拖了沒反應）
    private func panPhoto(by d: CGPoint) {
        guard let img = backgroundImage, img.size.width > 0, img.size.height > 0 else { return }
        let b = view.bounds
        guard b.width > 0, b.height > 0 else { return }
        let s = max(b.width / img.size.width, b.height / img.size.height) * CGFloat(settings.backgroundZoom)
        let w = img.size.width * s
        let h = img.size.height * s
        func clamp(_ f: CGFloat, visible: CGFloat) -> Double {
            let half = visible / 2
            return half >= 0.5 ? 0.5 : Double(min(max(f, half), 1 - half))
        }
        settings.backgroundFocusX = clamp(CGFloat(settings.backgroundFocusX) - d.x / w, visible: b.width / w)
        settings.backgroundFocusY = clamp(CGFloat(settings.backgroundFocusY) - d.y / h, visible: b.height / h)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundImageView.frame = backgroundFrame(in: b)
        CATransaction.commit()
    }

    /// 目前載入的是哪一張（沒換就不用重新讀檔）
    private var loadedPhoto: String?

    private var loadedMaxSide: CGFloat = 0

    private func loadBackground() {
        let url = settings.hasBackground && !style.isFoxLetter ? settings.currentPhotoURL : nil
        let need = url.map { backgroundMaxSide(url: $0) } ?? 0
        // 同一張照片：放大後需要更清楚才重讀
        guard url?.path != loadedPhoto || (url != nil && backgroundImage == nil) || need > loadedMaxSide * 1.15 else { return }
        loadedPhoto = url?.path
        loadedMaxSide = need
        backgroundImage = nil   // 先放掉舊的，不要兩張同時在記憶體裡
        backgroundImageView.image = nil
        backgroundImage = url.flatMap { UIImage.downsampled(url: $0, maxSide: need) }
    }

    /// 背景照片要讀多大：剛好蓋滿鍵盤（含放大倍數），照螢幕真正的解析度（一樣清楚），最多 1600。
    /// 蓋滿鍵盤用不到那麼大時（例如橫的照片）就讀小一點，省記憶體
    private func backgroundMaxSide(url: URL) -> CGFloat {
        let b = view.bounds.size
        let w = b.width > 0 ? b.width : UIScreen.main.bounds.width
        let h = b.height > 0 ? b.height : 300
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let iw = (p[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let ih = (p[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue, iw > 0, ih > 0 else { return 1000 }
        // 照片轉向（直拍）時寬高要對調
        let rotated = ((p[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1) >= 5
        let pw = CGFloat(rotated ? ih : iw), ph = CGFloat(rotated ? iw : ih)
        let s = max(w / pw, h / ph) * CGFloat(max(1, settings.backgroundZoom))
        let longSide = max(pw, ph) * s * max(2, UIScreen.main.scale)
        return min(1600, max(640, longSide.rounded()))
    }

    private func pasteBackground() {
        guard hasFullAccess else {
            toast("要先開啟「允許完整取用」")
            return
        }
        // 背景照片留到 1600（放大對準臉比較不糊；再大鍵盤的記憶體會不夠）
        // App 一次挑好幾張時，剪貼簿裡會有好幾張，全部一起加進來
        let images = UIPasteboard.general.downsampledImages(maxSide: 1600)
        guard !images.isEmpty else {
            toast("剪貼簿裡沒有圖片，先到相簿「拷貝」一張")
            return
        }
        var added = 0
        for small in images {
            autoreleasepool {
                guard let data = small.jpegData(compressionQuality: 0.85) else { return }
                // 對準臉；找不到臉就偏上面一點（人像的頭通常在上面）
                let face = faceCenter(in: small)
                if (try? settings.addPhoto(data, fx: Double(face?.x ?? 0.5), fy: Double(face?.y ?? 0.3))) != nil { added += 1 }
            }
        }
        guard added > 0 else {
            toast("存檔失敗")
            return
        }
        loadBackground()
        applyStyle()
        if added == 1 {
            // 貼上後直接在鍵盤上拖拉、縮放照片
            startPhotoAdjust()
        } else {
            toast("加好 \(added) 張背景照片了！點縮圖可以換，選好再按「調整照片位置」")
            (panelView as? SettingsPanelView)?.rebuild()
        }
    }

    /// 游標換行：有換行字元就跳到上／下一行的同一欄；同一段太長（畫面上自動折行）就照一行大約幾個字跳
    private func moveCursorLine(_ dir: Int) {
        let perLine = max(8, Int(view.bounds.width / 19))
        let before = Array(textDocumentProxy.documentContextBeforeInput ?? "")
        let after = Array(textDocumentProxy.documentContextAfterInput ?? "")
        // 現在在這一行的第幾個字；連續上下滑時用一開始的位置（經過短的行也能回到原本的直排）
        let currentCol = before.count - ((before.lastIndex(of: "\n") ?? -1) + 1)
        let col = goalColumn ?? (currentCol % perLine)
        goalColumn = col
        if dir < 0 {
            guard !before.isEmpty else { return }
            var offset = -min(perLine, before.count)
            if let nl = before.lastIndex(of: "\n"), currentCol <= perLine {
                let start = before[..<nl].lastIndex(of: "\n").map { $0 + 1 } ?? 0
                offset = start + min(col, nl - start) - before.count
            }
            textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
        } else {
            guard !after.isEmpty else { return }
            var offset = min(perLine, after.count)
            if let nl = after.firstIndex(of: "\n"), nl <= perLine {
                let nextEnd = after[(nl + 1)...].firstIndex(of: "\n") ?? after.count
                offset = min(nl + 1 + col, nextEnd)
            }
            textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
        }
    }

    private func cursorTick() {
        guard hasFullAccess, settings.haptics else { return }
        tick.selectionChanged()
        tick.prepare()
    }

    /// 空白鍵的圖：剪貼簿裡的 GIF（保持會動）或圖片
    private func pasteSpaceImage() {
        guard hasFullAccess else { toast("要先開啟「允許完整取用」"); return }
        let pb = UIPasteboard.general
        do {
            if let gif = pb.data(forPasteboardType: "com.compuserve.gif") {
                guard gif.count <= SpaceArt.maxBytes else { toast("這個 GIF 太大了（超過 3MB），換小一點的"); return }
                try SpaceArt.save(gifData: gif)
            } else if let img = pb.downsampledImage(maxSide: 200) {
                try SpaceArt.save(image: img)
            } else {
                toast("剪貼簿裡沒有圖片，先「拷貝」一張圖片或 GIF")
                return
            }
            settings.spaceStyle = "image"
            settingsChanged()
            toast("空白鍵換好了")
        } catch {
            toast("存檔失敗")
        }
    }

    /// 空白鍵的表符：剪貼簿裡剛複製的表情或顏文字（太長的只留前面）
    private func pasteSpaceEmoji() {
        guard hasFullAccess else { toast("要先開啟「允許完整取用」"); return }
        guard let s = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
            toast("先複製一個表情符號或顏文字")
            return
        }
        settings.spaceEmoji = String(s.prefix(12))
        settings.spaceStyle = "emoji"
        settingsChanged()
        toast("空白鍵換好了")
    }

    /// 下載字體包裡的字體，好了就換成它
    private func downloadFont(_ id: String) {
        guard hasFullAccess else {
            toast("要先開啟「允許完整取用」才能下載")
            return
        }
        let name = KeyFont(rawValue: id)?.title ?? "字體"
        toast("正在下載「\(name)」…")
        FontPacks.download(id) { [weak self] ok in
            guard let self = self else { return }
            if ok {
                self.settings.fontID = id
                self.settingsChanged()
                self.toast("「\(name)」下載好了")
            } else {
                self.toast("下載失敗，檢查一下網路再試")
            }
        }
    }

    /// 從剪貼簿收字體：App 放的（tw.nuonuo.font）或「檔案」App 拷貝的字體檔
    private func pasteFont() {
        guard hasFullAccess else {
            toast("要先開啟「允許完整取用」")
            return
        }
        let pb = UIPasteboard.general
        let known = ["tw.nuonuo.font", "public.truetype-ttf-font", "public.opentype-font", "public.font", "public.truetype-font"]
        let types = pb.types
        guard let type = known.first(where: { types.contains($0) })
                ?? types.first(where: { $0.lowercased().contains("font") || $0.hasSuffix("ttf") || $0.hasSuffix("otf") }),
              let data = pb.data(forPasteboardType: type) else {
            toast("剪貼簿裡沒有字體，先到 App 按「匯入我的字體」")
            return
        }
        let name = (pb.value(forPasteboardType: "tw.nuonuo.fontname") as? String)
            ?? (pb.data(forPasteboardType: "tw.nuonuo.fontname")).flatMap { String(data: $0, encoding: .utf8) }
        do {
            let item = try UserFonts.add(data, name: name)
            settings.fontID = item.id
            settingsChanged()
            toast("已加入字體「\(item.name)」")
        } catch UserFonts.ImportError.tooBig {
            toast("字體檔太大（超過 40MB），鍵盤裝不下")
        } catch {
            toast("讀不到這個字體，請用 .ttf 或 .otf 檔")
        }
    }

    private func clearBackground() {
        settings.clearPhotos()
        loadedPhoto = nil
        backgroundImage = nil
        applyStyle()
    }

    private func applyStyle() {
        let s = style
        if s.isFoxLetter {
            foxPaperLayer.contents = FoxLetterWatercolor.backdrop
            foxPaperLayer.isHidden = false
        } else {
            foxPaperLayer.contents = nil
            foxPaperLayer.isHidden = true
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.colors = [s.theme.backgroundTop.cgColor, s.theme.backgroundBottom.cgColor]
        CATransaction.commit()
        if let img = backgroundImage {
            backgroundImageView.image = img
            view.setNeedsLayout()
            backgroundImageView.isHidden = false
            tintOverlay.isHidden = false
            tintOverlay.backgroundColor = s.theme.backgroundTop.withAlphaComponent(settings.backgroundFade)
        } else {
            backgroundImageView.isHidden = true
            tintOverlay.isHidden = true
        }
        topBar.style = s
        topBar.hiddenTools = settings.hiddenToolbarItems
        grid.style = s
        updateGlass()
        handwritingView?.style = s
        candidatePanel?.style = s
        if let p = panelView as? EmojiPanelView { p.style = s }
        if let p = panelView as? ClipboardPanelView { p.style = s }
        if let p = panelView as? SettingsPanelView { p.style = s }
        if let p = panelView, let kind = panel {
            let strong: CGFloat = kind == .settings ? 0.82 : 0.6
            p.backgroundColor = s.theme.isDark ? UIColor.black.withAlphaComponent(strong - 0.2) : UIColor.white.withAlphaComponent(strong)
        }
        toastLabel.backgroundColor = s.theme.accent.withAlphaComponent(0.95)
        toastLabel.textColor = s.theme.accentText
    }

    // MARK: - 版面

    private var returnTitle: String {
        if isComposing { return "確認" }
        if editorResult != nil { return "送出" }
        if editorText != nil { return editorConfirmTitle(editorPurpose) }
        switch textDocumentProxy.returnKeyType ?? .default {
        case .go: return "前往"
        case .google, .yahoo, .search: return "搜尋"
        case .join: return "加入"
        case .next: return "下一項"
        case .route: return "路線"
        case .send: return "傳送"
        case .done: return "完成"
        case .continue: return "繼續"
        default: return "換行"
        }
    }

    private var spaceTitle: String {
        switch settings.spaceStyle {
        // 圖片：按鍵自己畫圖，這裡的字只用來讓換圖時按鍵重畫（看不到）
        case "image" where SpaceArt.hasImage: return KeySpec.spaceArtMark + SpaceArt.version
        case "emoji": return settings.spaceEmoji
        case "text": return mode.title
        default:
            let deco = style.theme.decoration
            return deco.isEmpty ? mode.title : "\(deco) \(mode.title)"
        }
    }

    private func refreshReturnTitle() {
        if returnTitle != lastReturnTitle { rebuildKeys() }
    }

    private func rebuildKeys() {
        guard grid != nil else { return }
        lastReturnTitle = returnTitle
        let context = KeyLayouts.Context(mode: mode, layer: layer, shift: shift, needsGlobe: needsInputModeSwitchKey,
                                         returnTitle: returnTitle, spaceTitle: spaceTitle, nextModeTitle: nextModeTitle,
                                         fullWidthSymbols: settings.fullWidthSymbols, zhuyinTenColumns: settings.zhuyinTenColumns)
        grid.setLayout(KeyLayouts.layout(context))
        grid.glideEnabled = mode == .english && layer == .letters && settings.glideTyping

        let showHandwriting = mode == .handwriting && layer == .letters
        if showHandwriting {
            let hw: HandwritingView
            if let existing = handwritingView {
                hw = existing
            } else {
                hw = HandwritingView(style: style)
                hw.sideGrid.onKey = { [weak self] spec in self?.handle(spec) }
                hw.onResult = { [weak self] results in
                    guard let self = self else { return }
                    self.suggestions = results
                    self.suggestionSource = .handwriting
                    self.refreshTopBar()
                }
                hw.onAutoCommit = { [weak self] in
                    guard let self = self, self.suggestionSource == .handwriting, let first = self.suggestions.first else { return }
                    self.output(first)
                    self.showAssociations(after: first)
                }
                hw.frame = contentView.bounds
                contentView.addSubview(hw)
                handwritingView = hw
            }
            hw.sideGrid.setLayout(KeyLayouts.handwritingSide(returnTitle: returnTitle, nextModeTitle: nextModeTitle))
        } else if let hw = handwritingView {
            hw.removeFromSuperview()
            handwritingView = nil
            if suggestionSource == .handwriting { clearSuggestions() }
        }
        grid.isHidden = showHandwriting || panelView != nil || candidatePanel != nil
        handwritingView?.isHidden = !showHandwriting || panelView != nil || candidatePanel != nil
        if let p = candidatePanel { contentView.bringSubviewToFront(p) }
        updateHeight()
    }

    private var isLandscape: Bool {
        let screen = UIScreen.main.bounds
        return screen.width > screen.height
    }

    /// 不呼叫 layoutIfNeeded／systemLayoutSizeFitting，避免量測本身觸發重新排版。
    private func layoutDiagnosticSnapshot() -> String {
        guard isViewLoaded else { return "view not loaded" }
        var lines = ["controller=\(ObjectIdentifier(self)) attached=\(view.window != nil) landscape=\(isLandscape)",
                     "mode=\(mode.rawValue) fox=\(style.isFoxLetter) panel=\(panel != nil)",
                     "folderHeight=\(folderBoxHeight) barHeight=\(settings.candidateBarHeight)"]
        if let constraint = heightConstraint {
            lines.append("height requested=\(constraint.constant) actual=\(view.bounds.height) delta=\(view.bounds.height - constraint.constant) active=\(constraint.isActive) priority=\(constraint.priority.rawValue)")
        } else {
            lines.append("height constraint=nil")
        }
        lines.append("allowsSelfSizing=\((view as? UIInputView)?.allowsSelfSizing == true) ambiguous=\(view.hasAmbiguousLayout)")
        lines.append(KeyboardLayoutDiagnostics.geometry("inputView", view))
        lines.append(KeyboardLayoutDiagnostics.geometry("heightRuler", heightRuler))
        lines.append(KeyboardLayoutDiagnostics.geometry("backdrop", backdropView))
        lines.append(KeyboardLayoutDiagnostics.geometry("topBar", topBar))
        lines.append(KeyboardLayoutDiagnostics.geometry("content", contentView))
        var parent = view.superview
        for index in 0..<8 {
            guard let current = parent else { break }
            lines.append(KeyboardLayoutDiagnostics.geometry("ancestor[\(index)]", current))
            parent = current.superview
        }
        if let window = view.window {
            lines.append("window=\(ObjectIdentifier(window)) screenBounds=\(KeyboardLayoutDiagnostics.rect(window.screen.bounds))")
            if let scene = window.windowScene {
                lines.append("sceneState=\(scene.activationState.rawValue) orientation=\(scene.interfaceOrientation.rawValue)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func updateHeight() {
        let fiveRows = (mode == .zhuyin || mode == .pinyin) && layer == .letters || layer == .numbers
        let content: CGFloat
        if isLandscape {
            content = fiveRows ? 196 : 164
        } else {
            content = fiveRows ? 252 : 216
        }
        // 使用者自己調的高度；橫放時螢幕矮，最多只放大到 1.1 倍
        let scale = isLandscape ? min(settings.heightScale, 1.1) : settings.heightScale
        let h = folderBoxHeight + CGFloat(settings.candidateBarHeight) + (content * scale).rounded()
        if let c = heightConstraint {
            if c.constant != h { c.constant = h }
        } else {
            let c = heightRuler.heightAnchor.constraint(equalToConstant: h)
            c.priority = UILayoutPriority(999)
            c.isActive = true
            heightConstraint = c
        }
    }

    // MARK: - 新版提醒

    /// 每 6 小時最多問一次 GitHub；有新版就提醒一次
    private func checkForUpdate() {
        guard hasFullAccess else { return }
        let now = Date().timeIntervalSince1970
        guard now - settings.lastUpdateCheck > 6 * 3600 else {
            showUpdateNoticeIfNeeded()
            return
        }
        settings.lastUpdateCheck = now
        ReleaseChecker.fetchLatest { [weak self] info in
            guard let self = self, let info = info else { return }
            self.settings.latestBuild = info.build
            self.showUpdateNoticeIfNeeded()
        }
    }

    private func showUpdateNoticeIfNeeded() {
        let latest = settings.latestBuild
        guard latest > ReleaseChecker.currentBuild, latest > settings.notifiedBuild else { return }
        settings.notifiedBuild = latest
        toast("有新版！打開糯糯鍵盤 App 看更新內容")
    }

    // MARK: - 回饋

    // 可愛按鍵音：第一次用到時才載入
    private var soundIDs: [String: SystemSoundID] = [:]
    private lazy var lastSoundStyle = settings.keySoundStyle

    private func prepareKeySound() {
        guard hasFullAccess, settings.keySound,
              KeySound(rawValue: settings.keySoundStyle) == .tink,
              soundIDs["tink"] == nil,
              let url = Bundle.main.url(forResource: "key_tink", withExtension: "wav")
                ?? Bundle.main.url(forResource: "key_tink", withExtension: "wav", subdirectory: "Sounds") else { return }
        var id: SystemSoundID = 0
        if AudioServicesCreateSystemSoundID(url as CFURL, &id) == noErr { soundIDs["tink"] = id }
    }

    private func playKeySound() {
        if KeySound(rawValue: settings.keySoundStyle) == .tink, let id = soundIDs["tink"] {
            AudioServicesPlaySystemSound(id)
        } else {
            // 使用公開的鍵盤音效 API，跟隨系統鍵盤聲音設定。
            UIDevice.current.playInputClick()
        }
    }

    private func feedback() {
        guard hasFullAccess else { return }
        if settings.keySound { playKeySound() }
        if settings.haptics {
            haptic.impactOccurred()
            haptic.prepare()   // 先暖機，下一次按才不會慢半拍
        }
    }

    /// 蓋在鍵盤上的說明卡（鍵盤裡不能用 UIAlertController），按「知道了」或點外面關掉
    private func showNotice(title: String, message: String) {
        closeNotice()
        let t = style.theme
        let dim = UIControl(frame: view.bounds)
        dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dim.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        dim.addAction(UIAction { [weak self] _ in self?.closeNotice() }, for: .touchUpInside)
        let card = UIView()
        card.backgroundColor = t.isDark ? UIColor(white: 0.16, alpha: 1) : .white
        card.layer.cornerRadius = 18
        card.translatesAutoresizingMaskIntoConstraints = false
        dim.addSubview(card)
        let fg: UIColor = t.isDark ? .white : UIColor(white: 0.15, alpha: 1)
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .rounded(17, .bold)
        titleLabel.textColor = fg
        let body = UILabel()
        body.text = message
        body.numberOfLines = 0
        body.font = .rounded(14, .medium)
        body.textColor = fg
        body.adjustsFontSizeToFitWidth = true
        body.minimumScaleFactor = 0.6
        let ok = UIButton(type: .system)
        ok.setTitle("知道了", for: .normal)
        ok.titleLabel?.font = .rounded(16, .bold)
        ok.tintColor = t.accent
        ok.addAction(UIAction { [weak self] _ in self?.closeNotice() }, for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [titleLabel, body, ok])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: dim.leadingAnchor, constant: 12),
            card.trailingAnchor.constraint(equalTo: dim.trailingAnchor, constant: -12),
            card.topAnchor.constraint(equalTo: dim.topAnchor, constant: 8),
            card.bottomAnchor.constraint(lessThanOrEqualTo: dim.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -6),
        ])
        view.addSubview(dim)
        noticeView = dim
    }

    private var noticeView: UIView?

    private func closeNotice() {
        noticeView?.removeFromSuperview()
        noticeView = nil
    }

    private func toast(_ text: String) {
        toastToken += 1
        let token = toastToken
        toastLabel.text = text
        view.bringSubviewToFront(toastLabel)
        UIView.animate(withDuration: 0.15) { self.toastLabel.alpha = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard let self = self, self.toastToken == token else { return }
            UIView.animate(withDuration: 0.3) { self.toastLabel.alpha = 0 }
        }
    }
}
