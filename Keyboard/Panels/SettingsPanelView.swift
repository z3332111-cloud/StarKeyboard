import UIKit

/// 設定頁的捲動：手指一滑就算捲動，不會順便按到按鈕或開關（滑桿除外，滑桿要能左右拖）
private final class SettingsScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool {
        !(view is UISlider)
    }
}

/// 鍵盤裡的設定：主題、按鍵造型、背景圖片、輸入法、聲音震動
final class SettingsPanelView: UIView, UIScrollViewDelegate {
    var onChange: (() -> Void)?
    var onPasteBackground: (() -> Void)?
    var onClearBackground: (() -> Void)?
    var onAdjustPhoto: (() -> Void)?
    var onPasteFont: (() -> Void)?
    var onDownloadFont: ((String) -> Void)?
    var onPasteSpaceImage: (() -> Void)?
    var onPasteSpaceEmoji: (() -> Void)?
    var onCopyTypingLog: (() -> Void)?
    var onStartLayoutDiagnostics: (() -> Void)?
    var onCopyLayoutDiagnostics: (() -> Void)?
    var onStopLayoutDiagnostics: (() -> Void)?
    var onAddShortcut: (() -> Void)?
    var onResetLearning: (() -> Void)?
    var onBack: (() -> Void)?
    /// 「邊看邊調大小」：關掉設定，選字列換成滑桿
    var onLiveSize: (() -> Void)?
    var style: KeyboardStyle {
        didSet {
            // 拖滑桿時不要重建（不然滑桿會被拿掉），只有換主題或造型才重建
            if oldValue.theme.id != style.theme.id || oldValue.shape != style.shape || oldValue.fontID != style.fontID {
                rebuild()
            } else {
                bar.style = style
            }
        }
    }

    private let settings: KeyboardSettings
    private let hasFullAccess: Bool
    private let shortcuts: ShortcutStore
    private let scroll = SettingsScrollView()
    // 最上面一排：「跳到…」選單（點了直接捲到那一段）＋「邊看邊調大小」
    private let jumpButton = UIButton(type: .system)
    private let liveButton = UIButton(type: .system)
    private var sections: [(name: String, view: UIView)] = []
    private let topH: CGFloat = 40
    private let stack = UIStackView()
    private let bar: PanelBottomBar
    // 換主題會重建，要記住主題那排橫向捲到哪
    private weak var themeScroll: UIScrollView?
    // 自訂配色：現在點色票是改主色還是第二色
    private var editingSecond = false

    init(settings: KeyboardSettings, hasFullAccess: Bool, style: KeyboardStyle, shortcuts: ShortcutStore) {
        self.settings = settings
        self.hasFullAccess = hasFullAccess
        self.shortcuts = shortcuts
        self.style = style
        bar = PanelBottomBar(style: style)
        super.init(frame: .zero)
        stack.axis = .vertical
        stack.spacing = 10
        scroll.addSubview(stack)
        scroll.alwaysBounceVertical = true
        scroll.delegate = self
        addSubview(scroll)
        jumpButton.showsMenuAsPrimaryAction = true
        jumpButton.contentHorizontalAlignment = .left
        jumpButton.titleLabel?.font = .rounded(14, .bold)
        jumpButton.layer.cornerRadius = 10
        jumpButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 8)
        addSubview(jumpButton)
        liveButton.setTitle("📏 邊看邊調大小", for: .normal)
        liveButton.titleLabel?.font = .rounded(14, .bold)
        liveButton.layer.cornerRadius = 10
        liveButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        liveButton.addAction(UIAction { [weak self] _ in self?.onLiveSize?() }, for: .touchUpInside)
        addSubview(liveButton)
        bar.showsBackspace = false
        bar.setTabs(["設定"])
        bar.onBack = { [weak self] in self?.onBack?() }
        addSubview(bar)
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let barH: CGFloat = 40
        let lw = liveButton.sizeThatFits(CGSize(width: 200, height: 34)).width
        liveButton.frame = CGRect(x: bounds.width - 8 - lw, y: 4, width: lw, height: 34)
        jumpButton.frame = CGRect(x: 8, y: 4, width: liveButton.frame.minX - 14, height: 34)
        scroll.frame = CGRect(x: 0, y: topH, width: bounds.width, height: bounds.height - barH - topH)
        bar.frame = CGRect(x: 0, y: bounds.height - barH, width: bounds.width, height: barH)
        let w = bounds.width - 24
        let size = stack.systemLayoutSizeFitting(CGSize(width: w, height: 0),
                                                 withHorizontalFittingPriority: .required,
                                                 verticalFittingPriority: .fittingSizeLevel)
        stack.frame = CGRect(x: 12, y: 8, width: w, height: size.height)
        scroll.contentSize = CGSize(width: bounds.width, height: size.height + 16)
    }

    // MARK: 建立內容

    func rebuild() {
        bar.style = style
        let offset = scroll.contentOffset
        let themeX = themeScroll?.contentOffset.x ?? 0
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        sections = []
        jumpButton.backgroundColor = style.theme.key.withAlphaComponent(0.8)
        jumpButton.setTitleColor(style.theme.keyText, for: .normal)
        liveButton.backgroundColor = style.theme.specialKey
        liveButton.setTitleColor(style.theme.specialText, for: .normal)

        stack.addArrangedSubview(header("主題"))
        stack.addArrangedSubview(foxLetterThemeRow())
        stack.addArrangedSubview(themeRow())
        if settings.themeID == "custom" {
            // 自訂配色：點色票選顏色；雙色時可以分別選主色和第二色
            let two = settings.customHue2 >= 0
            stack.addArrangedSubview(choiceRow(["單色", "雙色"], selected: two ? 1 : 0) { [weak self] i in
                guard let self = self else { return }
                if i == 1 && self.settings.customHue2 < 0 {
                    // 第二色先配一個對比色（色相轉半圈）
                    self.settings.customHue2 = (self.settings.customHue + 0.5).truncatingRemainder(dividingBy: 1)
                    self.settings.customSaturation2 = self.settings.customSaturation
                    self.editingSecond = true
                } else if i == 0 {
                    self.settings.customHue2 = -1
                    self.editingSecond = false
                }
                self.onChange?()
                self.rebuild()
            })
            if two { stack.addArrangedSubview(colorTargetRow()) }
            stack.addArrangedSubview(swatchGrid())
            let second = two && editingSecond
            stack.addArrangedSubview(sliderRow("濃淡", value: Float(second ? settings.customSaturation2 : settings.customSaturation), range: 0.05...1) { [weak self] v in
                if second { self?.settings.customSaturation2 = Double(v) } else { self?.settings.customSaturation = Double(v) }
                self?.onChange?()
            })
            stack.addArrangedSubview(choiceRow(["淺色", "深色"], selected: settings.customDark ? 1 : 0) { [weak self] i in
                self?.settings.customDark = i == 1
                self?.onChange?()
            })
        }

        if style.isFoxLetter {
            stack.addArrangedSubview(note("小狐狸主題已搭配角色造型與插畫質感。原本的造型、質感和背景照片會保留，切回其他主題即可恢復；高度、字體、間距與動畫仍可調整。"))
        } else {
            stack.addArrangedSubview(header("按鍵造型"))
            stack.addArrangedSubview(shapeRow())

            stack.addArrangedSubview(header("按鍵質感"))
            stack.addArrangedSubview(choiceRow(KeyFinish.allCases.map { $0.title },
                                               selected: KeyFinish.allCases.firstIndex(of: settings.keyFinish) ?? 0) { [weak self] i in
                self?.settings.keyFinish = KeyFinish.allCases[i]
                self?.onChange?()
            })
            stack.addArrangedSubview(note("胖胖：圓滾滾，按下去會壓扁。立體：按鍵有厚度，按下去會往下沉；按鍵調透明也看得出來。"))
        }

        stack.addArrangedSubview(header("空白鍵"))
        if style.isFoxLetter {
            stack.addArrangedSubview(note("可繼續使用自己的空白鍵圖片／GIF或表符。使用圖片時會收起信封配件，保留中央圖案空間。"))
        }
        let spaceModes = [("theme", "主題符號"), ("image", "我的圖片"), ("emoji", "表符"), ("text", "只有字")]
        stack.addArrangedSubview(choiceRow(spaceModes.map { $0.1 }, selected: spaceModes.firstIndex { $0.0 == settings.spaceStyle } ?? 0) { [weak self] i in
            guard let self = self else { return }
            if spaceModes[i].0 == "image" && !SpaceArt.hasImage {
                self.onPasteSpaceImage?()
            } else {
                self.settings.spaceStyle = spaceModes[i].0
                self.onChange?()
            }
            self.rebuild()
        })
        stack.addArrangedSubview(buttonRow([
            ("🖼 貼上圖片／GIF", { [weak self] in self?.onPasteSpaceImage?() }),
            ("😊 貼上表符", { [weak self] in self?.onPasteSpaceEmoji?() }),
        ]))
        stack.addArrangedSubview(note("先「拷貝」一張圖片、GIF、表情符號或顏文字，再按上面的按鈕，空白鍵就只放那個小圖。想幫照片去背：打開「糯糯鍵盤」App →「空白鍵圖案」挑照片，會自動去背並複製好。"))

        stack.addArrangedSubview(header("按下去的動作"))
        stack.addArrangedSubview(choiceRow(KeyMotion.allCases.map { $0.title },
                                           selected: KeyMotion.allCases.firstIndex { $0.rawValue == settings.keyMotion } ?? 0) { [weak self] i in
            self?.settings.keyMotion = KeyMotion.allCases[i].rawValue
            self?.onChange?()
        })
        stack.addArrangedSubview(note("果凍彈彈：壓扁再 duang duang 抖回來。跳跳：放開時蹦一下。搖搖：左右扭一扭。"))

        stack.addArrangedSubview(header("注音被拆開了？"))
        stack.addArrangedSubview(buttonRow([("📋 複製剛剛的打字紀錄", { [weak self] in self?.onCopyTypingLog?() })]))
        stack.addArrangedSubview(note("打字時注音被拆開（例如「我覺得」變「我居約得」），先不要刪，直接打開 ⚙ 按這個，再貼給開發的人。紀錄是最近 80 次按鍵的注音、時間和選過的字。"))

        stack.addArrangedSubview(header("鍵盤上方多出空隙？"))
        stack.addArrangedSubview(buttonRow([("開始版面診斷", { [weak self] in self?.onStartLayoutDiagnostics?() })]))
        stack.addArrangedSubview(buttonRow([
            ("複製版面紀錄", { [weak self] in self?.onCopyLayoutDiagnostics?() }),
            ("停止診斷", { [weak self] in self?.onStopLayoutDiagnostics?() }),
        ]))
        stack.addArrangedSubview(note("先在正常時開始，再切到其他 App 並返回。空隙出現後，先複製紀錄再關閉 App。只記錄尺寸、位置與顯示事件，不記錄打字內容；最近 160 筆保留在記憶體，鍵盤程序重啟後清除。複製需要允許完整取用。"))

        stack.addArrangedSubview(header("按鍵特效（按下去冒出小圖案）"))
        stack.addArrangedSubview(choiceRow(KeyEffect.allCases.map { $0.title },
                                           selected: KeyEffect.allCases.firstIndex { $0.rawValue == settings.keyEffect } ?? 0) { [weak self] i in
            self?.settings.keyEffect = KeyEffect.allCases[i].rawValue
            self?.onChange?()
        })

        stack.addArrangedSubview(header("字體（按鍵和候選字）"))
        stack.addArrangedSubview(fontRow())
        if let f = KeyFont(rawValue: settings.fontID), !f.bundled, FontPacks.isReady(f.rawValue) {
            stack.addArrangedSubview(buttonRow([("移除「\(f.title)」（之後可以再下載）", { [weak self] in
                guard let self = self else { return }
                FontPacks.remove(f.rawValue)
                self.settings.fontID = KeyFont.system.rawValue
                self.onChange?()
            })]))
        }
        if settings.fontID.hasPrefix("user:") {
            stack.addArrangedSubview(buttonRow([
                ("＋ 貼上我的字體", { [weak self] in self?.onPasteFont?() }),
                ("刪掉這個字體", { [weak self] in
                    guard let self = self else { return }
                    UserFonts.remove(self.settings.fontID)
                    self.settings.fontID = KeyFont.system.rawValue
                    self.onChange?()
                }),
            ]))
        } else {
            stack.addArrangedSubview(buttonRow([("＋ 貼上我的字體（自己買的字體）", { [weak self] in self?.onPasteFont?() })]))
        }
        stack.addArrangedSubview(note("有 ⬇ 的字體按一下才下載（要開「允許完整取用」和網路），不用的可以移除，鍵盤就不會越來越大。"))
        stack.addArrangedSubview(note("匯入自己的字體：打開「糯糯鍵盤」App 按「匯入我的字體」挑 .ttf／.otf 檔，再回來按上面的按鈕。也可以在「檔案」App 長按字體檔「拷貝」。"))
        stack.addArrangedSubview(note("字體只改變鍵盤上看到的樣子；傳出去的字由對方的 App 決定。想讓別人也看到特別的字，用工具列的「𝒜 花式文字」。"))

        stack.addArrangedSubview(header("大小（邊拖邊看）"))
        stack.addArrangedSubview(sliderRow("鍵盤高度", value: Float(settings.heightScale), range: 0.8...1.3) { [weak self] v in
            self?.settings.heightScale = CGFloat(v)
            self?.onChange?()
        })
        stack.addArrangedSubview(sliderRow("字的大小", value: Float(settings.fontScale), range: 0.8...1.4) { [weak self] v in
            self?.settings.fontScale = CGFloat(v)
            self?.onChange?()
        })
        stack.addArrangedSubview(sliderRow("按鍵間距", value: Float(settings.gapScale), range: 0.3...1.6) { [weak self] v in
            self?.settings.gapScale = CGFloat(v)
            self?.onChange?()
        })
        stack.addArrangedSubview(note("間距越小，按鍵越大、越好按。"))
        stack.addArrangedSubview(sliderRow("造型大小", value: Float(settings.shapeScale), range: 0.9...1.6) { [weak self] v in
            self?.settings.shapeScale = CGFloat(v)
            self?.onChange?()
        })
        stack.addArrangedSubview(note("貓咪、熊熊、肉球這類造型的大小，往右拉會變大顆（可以超出按鍵一點點）。"))
        stack.addArrangedSubview(buttonRow([
            ("大小恢復預設", { [weak self] in
                guard let self = self else { return }
                self.settings.heightScale = 1
                self.settings.fontScale = 1
                self.settings.gapScale = 1
                self.settings.shapeScale = 1.15
                self.onChange?()
                self.rebuild()
            }),
        ]))

        stack.addArrangedSubview(header("背景圖片"))
        stack.addArrangedSubview(note("先在相簿把照片「拷貝」，再按下面的按鈕。也可以用「糯糯鍵盤」App 挑照片。"))
        stack.addArrangedSubview(buttonRow([
            ("＋ 從剪貼簿新增照片", { [weak self] in self?.onPasteBackground?() }),
            ("全部拿掉", { [weak self] in self?.onClearBackground?() }),
        ]))
        if !settings.photos.isEmpty {
            stack.addArrangedSubview(photoRow())
        }
        if settings.photos.count >= 2 {
            let modes = [("fixed", "固定這張"), ("open", "每次打開換"), ("daily", "每天換")]
            stack.addArrangedSubview(choiceRow(modes.map { $0.1 }, selected: modes.firstIndex { $0.0 == settings.photoRotation } ?? 0) { [weak self] i in
                self?.settings.photoRotation = modes[i].0
            })
        }
        if settings.hasBackground {
            stack.addArrangedSubview(buttonRow([
                ("調整照片位置和大小（拖拉、兩指縮放）", { [weak self] in self?.onAdjustPhoto?() }),
            ]))
        }
        stack.addArrangedSubview(sliderRow("圖片淡化", value: Float(settings.backgroundFade), range: 0...0.9) { [weak self] v in
            self?.settings.backgroundFade = CGFloat(v)
            self?.onChange?()
        })
        stack.addArrangedSubview(sliderRow("按鍵透明度", value: Float(settings.keyAlpha), range: 0.35...1) { [weak self] v in
            self?.settings.keyAlpha = CGFloat(v)
            self?.onChange?()
        })

        stack.addArrangedSubview(header("快捷片語（打縮寫就跳出整段話）"))
        stack.addArrangedSubview(buttonRow([("＋ 新增快捷片語", { [weak self] in self?.onAddShortcut?() })]))
        if shortcuts.items.isEmpty {
            stack.addArrangedSubview(note("例如縮寫「地址」→ 你家的完整地址。打注音只打開頭（ㄉㄓ）也可以，英文打 addr 之類也行。"))
        }
        for item in shortcuts.items {
            stack.addArrangedSubview(shortcutRow(item))
        }

        stack.addArrangedSubview(header("上面那一排按鈕（不用的關掉，比較不擠）"))
        for item in ToolbarItem.allCases where item != .settings {
            stack.addArrangedSubview(switchRow(item.title, on: !settings.hiddenToolbarItems.contains(item)) { [weak self] on in
                guard let self = self else { return }
                var hidden = self.settings.hiddenToolbarItems
                if on { hidden.remove(item) } else { hidden.insert(item) }
                self.settings.hiddenToolbarItems = hidden
                self.onChange?()
            })
        }

        stack.addArrangedSubview(header("輸入法（按「中／英」鍵輪流切換）"))
        for mode in InputMode.allCases {
            stack.addArrangedSubview(switchRow(Self.modeName(mode), on: settings.enabledModes.contains(mode)) { [weak self] on in
                guard let self = self else { return }
                var modes = self.settings.enabledModes
                if on {
                    if !modes.contains(mode) { modes.append(mode) }
                } else {
                    modes.removeAll { $0 == mode }
                }
                self.settings.enabledModes = InputMode.allCases.filter { modes.contains($0) }
                self.onChange?()
            })
        }
        stack.addArrangedSubview(switchRow("注音十欄排法（像 Gboard：ㄦ 在空白鍵旁，長按打數字）", on: settings.zhuyinTenColumns) { [weak self] on in
            self?.settings.zhuyinTenColumns = on
            self?.onChange?()
        })
        stack.addArrangedSubview(switchRow("拼音輸出簡體字", on: settings.pinyinSimplified) { [weak self] on in
            self?.settings.pinyinSimplified = on
        })
        stack.addArrangedSubview(switchRow("聯想詞（打完字後推薦下一個字）", on: settings.associations) { [weak self] on in
            self?.settings.associations = on
        })

        stack.addArrangedSubview(header("打錯字修正"))
        stack.addArrangedSubview(switchRow("英文自動修正（按空白時修正，馬上按刪除可以復原）", on: settings.autocorrect) { [weak self] on in
            self?.settings.autocorrect = on
        })
        stack.addArrangedSubview(switchRow("英文滑行輸入（手指不放開，滑過字母就打出整個字）", on: settings.glideTyping) { [weak self] on in
            self?.settings.glideTyping = on
            self?.onChange?()
        })
        stack.addArrangedSubview(switchRow("注音：按到旁邊的鍵也猜得到", on: settings.fuzzyKeys) { [weak self] on in
            self?.settings.fuzzyKeys = on
            self?.onChange?()
        })
        stack.addArrangedSubview(switchRow("注音：聲調打錯或忘了打", on: settings.fuzzyTones) { [weak self] on in
            self?.settings.fuzzyTones = on
            self?.onChange?()
        })
        stack.addArrangedSubview(switchRow("注音模糊音：ㄣㄥ、ㄓㄗ、ㄔㄘ、ㄕㄙ 分不清", on: settings.fuzzyPhonetic) { [weak self] on in
            self?.settings.fuzzyPhonetic = on
            self?.onChange?()
        })
        stack.addArrangedSubview(header("選字列高度"))
        stack.addArrangedSubview(note("也可以按住選字列左下角的小橫條往上或往下拖。字會跟著變大。"))
        stack.addArrangedSubview(candidateHeightRow())

        stack.addArrangedSubview(header("翻譯"))
        stack.addArrangedSubview(note("工具列的「譯」：先打要翻譯的話，選目標語言，按「翻譯」。iOS 26 以上且已下載語言時用 iPhone 內建翻譯，只有開啟「允許外部網路翻譯」後，才會在本機翻譯不可用時使用 MyMemory（原文會傳到該服務）。"))

        stack.addArrangedSubview(header("聲音與震動"))
        stack.addArrangedSubview(switchRow("按鍵聲音", on: settings.keySound) { [weak self] on in
            self?.settings.keySound = on
        })
        stack.addArrangedSubview(choiceRow(KeySound.allCases.map { $0.title },
                                           selected: KeySound.allCases.firstIndex { $0.rawValue == settings.keySoundStyle } ?? 0) { [weak self] i in
            self?.settings.keySoundStyle = KeySound.allCases[i].rawValue
            self?.settings.keySound = true
            self?.onChange?()
        })
        stack.addArrangedSubview(note("點一下就會播放聽聽看（要打開「允許完整取用」）。"))
        stack.addArrangedSubview(switchRow("按鍵震動", on: settings.haptics) { [weak self] on in
            self?.settings.haptics = on
        })

        stack.addArrangedSubview(header("隱私與安全"))
        stack.addArrangedSubview(switchRow("自動記錄剪貼簿", on: settings.clipboardHistoryEnabled) { [weak self] on in
            self?.settings.clipboardHistoryEnabled = on
        })
        stack.addArrangedSubview(note("預設關閉。開啟後會儲存複製的文字；會略過敏感標記，但無法辨識所有密碼。可在剪貼簿逐筆刪除舊資料。"))
        stack.addArrangedSubview(switchRow("允許外部網路翻譯", on: settings.allowOnlineTranslation) { [weak self] on in
            self?.settings.allowOnlineTranslation = on
        })
        stack.addArrangedSubview(note("預設關閉。開啟後，本機翻譯失敗時會將最多 450 字送到 MyMemory；文字在網址參數中，服務商可能保留紀錄。請勿翻譯密碼或私密資料。完整說明見糯糯鍵盤 App 的「隱私與安全」。"))
        stack.addArrangedSubview(header("未分類暫存上限（釘選另存）"))
        stack.addArrangedSubview(clipLimitRow())

        stack.addArrangedSubview(header("其他"))
        stack.addArrangedSubview(buttonRow([
            ("清除選字學習紀錄", { [weak self] in self?.onResetLearning?() }),
        ]))
        if !hasFullAccess {
            stack.addArrangedSubview(note("⚠️ 還沒開啟「允許完整取用」：剪貼簿、聲音、震動、貼圖、背景圖片都需要它。\n設定 › 一般 › 鍵盤 › 鍵盤 › 糯糯鍵盤 › 允許完整取用"))
        }
        let current = ReleaseChecker.currentBuild
        if settings.latestBuild > current {
            stack.addArrangedSubview(note("🎉 有新版：打開「糯糯鍵盤」App 看更新內容和下載方法"))
        }
        stack.addArrangedSubview(note("糯糯鍵盤 v\(ReleaseChecker.currentVersion) ・ 注音字典來自小麥注音（MIT 授權）"))

        jumpButton.menu = UIMenu(title: "跳到…", children: sections.map { s in
            UIAction(title: s.name) { [weak self] _ in self?.jump(to: s.view) }
        })
        setNeedsLayout()
        layoutIfNeeded()
        scroll.contentOffset = CGPoint(x: 0, y: min(offset.y, max(0, scroll.contentSize.height - scroll.bounds.height)))
        updateJumpTitle()
        if let s = themeScroll {
            s.contentOffset = CGPoint(x: min(themeX, max(0, s.contentSize.width - s.bounds.width)), y: 0)
        }
    }

    private static func modeName(_ mode: InputMode) -> String {
        switch mode {
        case .zhuyin: return "注音"
        case .english: return "英文"
        case .handwriting: return "手寫"
        case .korean: return "韓文（한국어）"
        case .japanese: return "日文（羅馬拼音→假名）"
        case .pinyin: return "拼音（馬來西亞、中國用，可出簡體）"
        }
    }

    private var textColor: UIColor { style.theme.keyText }

    private func header(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .rounded(14, .bold)
        l.textColor = textColor.withAlphaComponent(0.8)
        let short = text.components(separatedBy: "（").first?.components(separatedBy: "？").first ?? text
        sections.append((short, l))
        return l
    }

    /// 點「跳到…」裡的一段：捲到那一段的標題
    private func jump(to view: UIView) {
        let y = stack.frame.minY + view.frame.minY - 4
        scroll.setContentOffset(CGPoint(x: 0, y: max(0, min(y, scroll.contentSize.height - scroll.bounds.height))), animated: true)
    }

    /// 捲動時左上角跟著顯示現在在哪一段
    private func updateJumpTitle() {
        let y = scroll.contentOffset.y - stack.frame.minY + 12
        let cur = sections.last { $0.view.frame.minY <= y } ?? sections.first
        jumpButton.setTitle("📑 跳到：\(cur?.name ?? "主題") ▾", for: .normal)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === scroll else { return }
        updateJumpTitle()
    }

    private func note(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.numberOfLines = 0
        l.font = .rounded(12)
        l.textColor = textColor.withAlphaComponent(0.65)
        return l
    }

    private func card() -> UIView {
        let v = UIView()
        v.backgroundColor = style.theme.key.withAlphaComponent(0.55)
        v.layer.cornerRadius = 12
        return v
    }

    private func themeRow() -> UIView {
        let scrollRow = UIScrollView()
        scrollRow.showsHorizontalScrollIndicator = false
        scrollRow.heightAnchor.constraint(equalToConstant: 78).isActive = true
        var x: CGFloat = 0
        for theme in KeyboardTheme.all.filter({ $0.id != FoxLetterTheme.id }) + [KeyboardTheme.named("custom")] {
            let selected = theme.id == settings.themeID
            let b = UIButton(type: .custom)
            b.frame = CGRect(x: x, y: 0, width: 64, height: 76)
            let swatch = UIView(frame: CGRect(x: 8, y: 2, width: 48, height: 48))
            swatch.isUserInteractionEnabled = false
            swatch.backgroundColor = theme.backgroundTop
            swatch.layer.cornerRadius = 24
            swatch.layer.borderWidth = selected ? 3 : 1
            swatch.layer.borderColor = (selected ? theme.accent : theme.shadow).cgColor
            let dot = UIView(frame: CGRect(x: 12, y: 14, width: 24, height: 20))
            dot.backgroundColor = theme.key
            dot.layer.cornerRadius = 7
            let accent = UIView(frame: CGRect(x: 30, y: 30, width: 12, height: 10))
            accent.backgroundColor = theme.accent
            accent.layer.cornerRadius = 4
            swatch.addSubview(dot)
            swatch.addSubview(accent)
            b.addSubview(swatch)
            let name = UILabel(frame: CGRect(x: 0, y: 54, width: 64, height: 18))
            name.text = theme.id == "custom" ? "🎨 自訂" : theme.name
            name.font = .rounded(11, selected ? .bold : .regular)
            name.textAlignment = .center
            name.textColor = textColor
            b.addSubview(name)
            b.addAction(UIAction { [weak self] _ in
                self?.settings.themeID = theme.id
                self?.onChange?()
            }, for: .touchUpInside)
            scrollRow.addSubview(b)
            x += 68
        }
        scrollRow.contentSize = CGSize(width: x, height: 76)
        themeScroll = scrollRow
        return scrollRow
    }

    private func foxLetterThemeRow() -> UIView {
        let selected = settings.themeID == FoxLetterTheme.id
        let button = UIButton(type: .custom)
        button.heightAnchor.constraint(equalToConstant: 82).isActive = true
        button.backgroundColor = UIColor(hex: 0x51424D)
        button.layer.cornerRadius = 14
        button.layer.borderWidth = selected ? 2 : 0.7
        button.layer.borderColor = UIColor(hex: selected ? 0xE9AE78 : 0xA1847E).cgColor
        button.accessibilityLabel = "小狐狸的楓葉信，角色主題"
        button.accessibilityTraits = selected ? [.button, .selected] : [.button]
        let preview = FoxLetterArtworkView(frame: .zero)
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.configure(index: 0, action: .text(""), personalSpaceArt: false)
        button.addSubview(preview)
        let title = UILabel()
        title.text = selected ? "小狐狸的楓葉信 ✓" : "小狐狸的楓葉信"
        title.textColor = UIColor(hex: 0xFFF5E4)
        title.font = .rounded(16, .bold)
        title.adjustsFontSizeToFitWidth = true
        title.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(title)
        let subtitle = UILabel()
        subtitle.text = "秋日角色按鍵 · 點一下套用"
        subtitle.textColor = UIColor(hex: 0xE7C8B1)
        subtitle.font = .rounded(11)
        subtitle.adjustsFontSizeToFitWidth = true
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(subtitle)
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 12),
            preview.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            preview.widthAnchor.constraint(equalToConstant: 43),
            preview.heightAnchor.constraint(equalToConstant: 62),
            title.leadingAnchor.constraint(equalTo: preview.trailingAnchor, constant: 12),
            title.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -12),
            title.topAnchor.constraint(equalTo: button.topAnchor, constant: 18),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 5),
        ])
        button.addAction(UIAction { [weak self] _ in
            self?.settings.themeID = FoxLetterTheme.id
            self?.onChange?()
        }, for: .touchUpInside)
        return button
    }

    private func shortcutRow(_ item: ShortcutStore.Item) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        let label = UILabel()
        label.text = "\(item.code) → \(item.phrase)"
        label.font = .rounded(14)
        label.textColor = textColor
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        row.addArrangedSubview(label)
        let delete = UIButton(type: .system)
        delete.setTitle("刪除", for: .normal)
        delete.titleLabel?.font = .rounded(13, .bold)
        delete.setTitleColor(style.theme.specialText, for: .normal)
        delete.backgroundColor = style.theme.specialKey
        delete.layer.cornerRadius = 10
        delete.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        delete.setContentHuggingPriority(.required, for: .horizontal)
        delete.setContentCompressionResistancePriority(.required, for: .horizontal)
        delete.addAction(UIAction { [weak self, weak row] _ in
            self?.shortcuts.remove(item)
            row?.removeFromSuperview()
            self?.setNeedsLayout()
        }, for: .touchUpInside)
        row.addArrangedSubview(delete)
        return row
    }

    /// 背景照片的縮圖：點一下換成那張，選中的有框；右邊的 ✕ 拿掉目前這張
    private func photoRow() -> UIView {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.heightAnchor.constraint(equalToConstant: 58).isActive = true
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 6
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        var thumbs: [UIButton] = []
        func paint() {
            let n = self.settings.photos.count
            let cur = n == 0 ? -1 : ((self.settings.photoIndex % n) + n) % n
            for (i, b) in thumbs.enumerated() {
                b.layer.borderWidth = i == cur ? 3 : 0
                b.layer.borderColor = self.style.theme.accent.cgColor
            }
        }
        for p in settings.photos {
            let b = UIButton(type: .custom)
            b.setImage(settings.thumbnail(p), for: .normal)
            b.imageView?.contentMode = .scaleAspectFill
            b.contentHorizontalAlignment = .fill
            b.contentVerticalAlignment = .fill
            b.layer.cornerRadius = 12
            b.clipsToBounds = true
            b.widthAnchor.constraint(equalToConstant: 56).isActive = true
            b.heightAnchor.constraint(equalToConstant: 56).isActive = true
            b.addAction(UIAction { [weak self, weak b] _ in
                guard let self = self, let b = b, let i = thumbs.firstIndex(of: b) else { return }
                self.settings.photoIndex = i
                paint()
                self.onChange?()
            }, for: .touchUpInside)
            thumbs.append(b)
            row.addArrangedSubview(b)
        }
        let remove = UIButton(type: .system)
        remove.setTitle("✕ 拿掉這張", for: .normal)
        remove.titleLabel?.font = .rounded(13, .bold)
        remove.setTitleColor(style.theme.specialText, for: .normal)
        remove.backgroundColor = style.theme.specialKey
        remove.layer.cornerRadius = 12
        remove.contentEdgeInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        remove.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            let n = self.settings.photos.count
            guard n > 0 else { return }
            let cur = ((self.settings.photoIndex % n) + n) % n
            self.settings.removePhoto(at: cur)
            thumbs.remove(at: cur).removeFromSuperview()
            paint()
            self.onChange?()
        }, for: .touchUpInside)
        row.addArrangedSubview(remove)
        paint()
        return scroll
    }

    /// 一排可以左右滑的選項，選中的那個是主題色
    private func choiceRow(_ titles: [String], selected: Int, onSelect: @escaping (Int) -> Void) -> UIView {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.heightAnchor.constraint(equalToConstant: 38).isActive = true
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        var buttons: [UIButton] = []
        func paint(_ sel: Int) {
            for (j, b) in buttons.enumerated() {
                let on = j == sel
                b.backgroundColor = on ? self.style.theme.accent : self.style.theme.key.withAlphaComponent(0.6)
                b.setTitleColor(on ? self.style.theme.accentText : self.style.theme.keyText, for: .normal)
                b.titleLabel?.font = .rounded(14, on ? .bold : .regular)
            }
        }
        for (i, title) in titles.enumerated() {
            let b = UIButton(type: .custom)
            b.setTitle(title, for: .normal)
            b.layer.cornerRadius = 12
            b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
            b.addAction(UIAction { _ in
                paint(i)
                onSelect(i)
            }, for: .touchUpInside)
            buttons.append(b)
            row.addArrangedSubview(b)
        }
        paint(selected)
        return scroll
    }

    private func fontRow() -> UIView {
        let column = UIStackView()
        column.axis = .vertical
        column.spacing = 8
        var row = UIStackView()
        let fonts = KeyFont.allCases.map { ($0.rawValue, $0.title) } + UserFonts.all.map { ($0.id, $0.name) }
        for (index, font) in fonts.enumerated() {
            if index % 4 == 0 {
                row = UIStackView()
                row.axis = .horizontal
                row.distribution = .fillEqually
                row.spacing = 8
                row.heightAnchor.constraint(equalToConstant: 40).isActive = true
                column.addArrangedSubview(row)
            }
            let ready = FontPacks.isReady(font.0)
            let selected = font.0 == settings.fontID && ready
            let b = UIButton(type: .custom)
            b.layer.cornerRadius = 12
            b.backgroundColor = selected ? style.theme.accent : style.theme.key.withAlphaComponent(0.6)
            b.setTitle(ready ? font.1 : "⬇ " + font.1, for: .normal)
            b.setTitleColor(selected ? style.theme.accentText : style.theme.keyText, for: .normal)
            b.titleLabel?.font = ready ? KeyFonts.font(font.0, size: 16, weight: selected ? .bold : .regular) : .rounded(15)
            b.titleLabel?.adjustsFontSizeToFitWidth = true
            b.titleLabel?.minimumScaleFactor = 0.6
            b.addAction(UIAction { [weak self] _ in
                guard ready else { self?.onDownloadFont?(font.0); return }
                self?.settings.fontID = font.0
                self?.onChange?()
            }, for: .touchUpInside)
            row.addArrangedSubview(b)
        }
        while row.arrangedSubviews.count < 4 { row.addArrangedSubview(UIView()) }
        return column
    }

    /// 雙色時選「現在要改哪個顏色」：兩顆按鈕，裡面有目前的顏色
    private func colorTargetRow() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 8
        row.heightAnchor.constraint(equalToConstant: 40).isActive = true
        let items: [(String, Double, Double, Bool)] = [
            ("主色（按鍵的字）", settings.customHue, settings.customSaturation, false),
            ("第二色（功能鍵）", settings.customHue2, settings.customSaturation2, true),
        ]
        for (title, h, sat, second) in items {
            let selected = editingSecond == second
            let b = UIButton(type: .custom)
            b.layer.cornerRadius = 12
            b.backgroundColor = selected ? style.theme.accent : style.theme.key.withAlphaComponent(0.6)
            b.setTitle("  " + title, for: .normal)
            b.titleLabel?.font = .rounded(13, selected ? .bold : .regular)
            b.titleLabel?.adjustsFontSizeToFitWidth = true
            b.setTitleColor(selected ? style.theme.accentText : style.theme.keyText, for: .normal)
            let dot = UIView(frame: CGRect(x: 8, y: 10, width: 20, height: 20))
            dot.isUserInteractionEnabled = false
            dot.backgroundColor = KeyboardTheme.swatchColor(h, sat)
            dot.layer.cornerRadius = 10
            dot.layer.borderWidth = 2
            dot.layer.borderColor = UIColor.white.cgColor
            b.addSubview(dot)
            b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 26, bottom: 0, right: 4)
            b.addAction(UIAction { [weak self] _ in
                self?.editingSecond = second
                self?.rebuild()
            }, for: .touchUpInside)
            row.addArrangedSubview(b)
        }
        return row
    }

    /// 色票：一格一個圓點，點了就換顏色（選中的有框）
    private func swatchGrid() -> UIView {
        let column = UIStackView()
        column.axis = .vertical
        column.spacing = 6
        let second = settings.customHue2 >= 0 && editingSecond
        let curH = second ? settings.customHue2 : settings.customHue
        let curS = second ? settings.customSaturation2 : settings.customSaturation
        var row = UIStackView()
        for (index, sw) in KeyboardTheme.swatches.enumerated() {
            if index % 7 == 0 {
                row = UIStackView()
                row.axis = .horizontal
                row.distribution = .fillEqually
                row.spacing = 6
                row.heightAnchor.constraint(equalToConstant: 38).isActive = true
                column.addArrangedSubview(row)
            }
            let selected = abs(sw.0 - curH) < 0.005 && abs(sw.1 - curS) < 0.02
            let b = UIButton(type: .custom)
            let dot = UIView()
            dot.isUserInteractionEnabled = false
            dot.backgroundColor = KeyboardTheme.swatchColor(sw.0, sw.1)
            dot.layer.cornerRadius = 15
            dot.layer.borderWidth = selected ? 3 : 1
            dot.layer.borderColor = (selected ? style.theme.keyText : UIColor.white).cgColor
            dot.translatesAutoresizingMaskIntoConstraints = false
            b.addSubview(dot)
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 30), dot.heightAnchor.constraint(equalToConstant: 30),
                dot.centerXAnchor.constraint(equalTo: b.centerXAnchor), dot.centerYAnchor.constraint(equalTo: b.centerYAnchor),
            ])
            b.addAction(UIAction { [weak self] _ in
                guard let self = self else { return }
                if second {
                    self.settings.customHue2 = sw.0
                    self.settings.customSaturation2 = sw.1
                } else {
                    self.settings.customHue = sw.0
                    self.settings.customSaturation = sw.1
                }
                self.onChange?()
                self.rebuild()
            }, for: .touchUpInside)
            row.addArrangedSubview(b)
        }
        while row.arrangedSubviews.count < 7 { row.addArrangedSubview(UIView()) }
        return column
    }

    private func shapeRow() -> UIView {
        let column = UIStackView()
        column.axis = .vertical
        column.spacing = 8
        var row = UIStackView()
        for (index, shape) in KeyShape.allCases.enumerated() {
            if index % 4 == 0 {
                row = UIStackView()
                row.axis = .horizontal
                row.distribution = .fillEqually
                row.spacing = 8
                row.heightAnchor.constraint(equalToConstant: 64).isActive = true
                column.addArrangedSubview(row)
            }
            let selected = shape == settings.keyShape
            let b = UIButton(type: .custom)
            b.accessibilityLabel = shape.title
            b.accessibilityTraits = selected ? [.button, .selected] : .button
            b.layer.cornerRadius = 12
            b.backgroundColor = selected ? style.theme.specialKey.withAlphaComponent(0.8) : .clear
            let preview = CAShapeLayer()
            preview.path = shape.path(in: CGRect(x: 0, y: 0, width: 40, height: 34))
            preview.fillColor = style.theme.key.cgColor
            preview.strokeColor = style.theme.shadow.cgColor
            preview.lineWidth = 1
            let holder = UIView(frame: CGRect(x: 0, y: 0, width: 40, height: 34))
            holder.isUserInteractionEnabled = false
            holder.layer.addSublayer(preview)
            let detail = CAShapeLayer()
            detail.path = shape.detailPath(in: CGRect(x: 0, y: 0, width: 40, height: 34))
            detail.fillColor = shape.detailColor(theme: style.theme).withAlphaComponent(shape.detailOpacity()).cgColor
            holder.layer.addSublayer(detail)
            holder.translatesAutoresizingMaskIntoConstraints = false
            b.addSubview(holder)
            NSLayoutConstraint.activate([
                holder.centerXAnchor.constraint(equalTo: b.centerXAnchor),
                holder.topAnchor.constraint(equalTo: b.topAnchor, constant: 4),
                holder.widthAnchor.constraint(equalToConstant: 40),
                holder.heightAnchor.constraint(equalToConstant: 34),
            ])
            let name = UILabel()
            name.text = shape.title
            name.font = .rounded(12, selected ? .bold : .regular)
            name.textColor = textColor
            name.translatesAutoresizingMaskIntoConstraints = false
            b.addSubview(name)
            NSLayoutConstraint.activate([
                name.centerXAnchor.constraint(equalTo: b.centerXAnchor),
                name.bottomAnchor.constraint(equalTo: b.bottomAnchor, constant: -4),
            ])
            b.addAction(UIAction { [weak self] _ in
                self?.settings.keyShape = shape
                self?.onChange?()
            }, for: .touchUpInside)
            row.addArrangedSubview(b)
        }
        while row.arrangedSubviews.count < 4 { row.addArrangedSubview(UIView()) }
        return column
    }

    private func buttonRow(_ buttons: [(String, () -> Void)]) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 8
        row.heightAnchor.constraint(equalToConstant: 40).isActive = true
        for (title, action) in buttons {
            let b = UIButton(type: .system)
            b.setTitle(title, for: .normal)
            b.titleLabel?.font = .rounded(14, .semibold)
            b.setTitleColor(style.theme.specialText, for: .normal)
            b.backgroundColor = style.theme.specialKey
            b.layer.cornerRadius = 10
            b.addAction(UIAction { _ in action() }, for: .touchUpInside)
            row.addArrangedSubview(b)
        }
        return row
    }

    private func sliderRow(_ title: String, value: Float, range: ClosedRange<Float>, onChange: @escaping (Float) -> Void) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        let l = UILabel()
        l.text = title
        l.font = .rounded(14)
        l.textColor = textColor
        l.widthAnchor.constraint(equalToConstant: 86).isActive = true
        let s = UISlider()
        s.minimumValue = range.lowerBound
        s.maximumValue = range.upperBound
        s.value = value
        s.minimumTrackTintColor = style.theme.accent
        s.addAction(UIAction { [weak s] _ in if let s = s { onChange(s.value) } }, for: .valueChanged)
        row.addArrangedSubview(l)
        row.addArrangedSubview(s)
        return row
    }

    private func switchRow(_ title: String, on: Bool, onChange: @escaping (Bool) -> Void) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        let l = UILabel()
        l.text = title
        l.font = .rounded(15)
        l.textColor = textColor
        l.numberOfLines = 0
        let sw = UISwitch()
        sw.isOn = on
        sw.onTintColor = style.theme.accent
        sw.setContentHuggingPriority(.required, for: .horizontal)
        sw.addAction(UIAction { [weak sw] _ in if let sw = sw { onChange(sw.isOn) } }, for: .valueChanged)
        row.addArrangedSubview(l)
        row.addArrangedSubview(sw)
        return row
    }

    private func candidateHeightRow() -> UIView {
        let slider = UISlider()
        slider.minimumValue = Float(CandidateBarMetrics.minHeight)
        slider.maximumValue = Float(CandidateBarMetrics.maxHeight)
        slider.value = Float(settings.candidateBarHeight)
        slider.addAction(UIAction { [weak self] _ in
            self?.settings.candidateBarHeight = Double(slider.value)
            self?.onChange?()
        }, for: .valueChanged)
        return slider
    }

    private func clipLimitRow() -> UIView {
        let options = [50, 100, 200, 500]
        let seg = UISegmentedControl(items: options.map { "\($0)" })
        seg.selectedSegmentIndex = options.firstIndex(of: settings.clipLimit) ?? 2
        seg.selectedSegmentTintColor = style.theme.key
        seg.setTitleTextAttributes([.foregroundColor: textColor], for: .normal)
        seg.addAction(UIAction { [weak self, weak seg] _ in
            guard let seg = seg else { return }
            self?.settings.clipLimit = options[seg.selectedSegmentIndex]
            self?.onChange?()
        }, for: .valueChanged)
        return seg
    }
}
