import UIKit

/// 鍵盤裡的設定：主題、按鍵造型、背景圖片、輸入法、聲音震動
final class SettingsPanelView: UIView {
    var onChange: (() -> Void)?
    var onPasteBackground: (() -> Void)?
    var onClearBackground: (() -> Void)?
    var onAdjustPhoto: (() -> Void)?
    var onAddShortcut: (() -> Void)?
    var onResetLearning: (() -> Void)?
    var onBack: (() -> Void)?
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
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let bar: PanelBottomBar
    // 換主題會重建，要記住主題那排橫向捲到哪
    private weak var themeScroll: UIScrollView?

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
        addSubview(scroll)
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
        scroll.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - barH)
        bar.frame = CGRect(x: 0, y: bounds.height - barH, width: bounds.width, height: barH)
        let w = bounds.width - 24
        let size = stack.systemLayoutSizeFitting(CGSize(width: w, height: 0),
                                                 withHorizontalFittingPriority: .required,
                                                 verticalFittingPriority: .fittingSizeLevel)
        stack.frame = CGRect(x: 12, y: 8, width: w, height: size.height)
        scroll.contentSize = CGSize(width: bounds.width, height: size.height + 16)
    }

    // MARK: 建立內容

    private func rebuild() {
        bar.style = style
        let offset = scroll.contentOffset
        let themeX = themeScroll?.contentOffset.x ?? 0
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        stack.addArrangedSubview(header("主題"))
        stack.addArrangedSubview(themeRow())

        stack.addArrangedSubview(header("按鍵造型"))
        stack.addArrangedSubview(shapeRow())

        stack.addArrangedSubview(header("按鍵特效（按下去冒出小圖案）"))
        stack.addArrangedSubview(choiceRow(KeyEffect.allCases.map { $0.title },
                                           selected: KeyEffect.allCases.firstIndex { $0.rawValue == settings.keyEffect } ?? 0) { [weak self] i in
            self?.settings.keyEffect = KeyEffect.allCases[i].rawValue
            self?.onChange?()
        })

        stack.addArrangedSubview(header("字體（按鍵和候選字）"))
        stack.addArrangedSubview(fontRow())
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
        stack.addArrangedSubview(buttonRow([
            ("大小恢復預設", { [weak self] in
                guard let self = self else { return }
                self.settings.heightScale = 1
                self.settings.fontScale = 1
                self.settings.gapScale = 1
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

        setNeedsLayout()
        layoutIfNeeded()
        scroll.contentOffset = CGPoint(x: 0, y: min(offset.y, max(0, scroll.contentSize.height - scroll.bounds.height)))
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
        return l
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
        for theme in KeyboardTheme.all {
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
            name.text = theme.name
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
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 8
        row.heightAnchor.constraint(equalToConstant: 40).isActive = true
        for font in KeyFont.allCases {
            let selected = font.rawValue == settings.fontID
            let b = UIButton(type: .custom)
            b.layer.cornerRadius = 12
            b.backgroundColor = selected ? style.theme.accent : style.theme.key.withAlphaComponent(0.6)
            b.setTitle(font.title, for: .normal)
            b.setTitleColor(selected ? style.theme.accentText : style.theme.keyText, for: .normal)
            b.titleLabel?.font = KeyFonts.font(font.rawValue, size: 16, weight: selected ? .bold : .regular)
            b.addAction(UIAction { [weak self] _ in
                self?.settings.fontID = font.rawValue
                self?.onChange?()
            }, for: .touchUpInside)
            row.addArrangedSubview(b)
        }
        return row
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
            detail.fillColor = shape.detailColor(theme: style.theme).withAlphaComponent(shape == .pudding || shape == .duck ? 0.85 : 0.4).cgColor
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
