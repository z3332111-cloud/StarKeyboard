import SwiftUI
import UIKit
import AudioToolbox

// App 的「主題、按鍵、字體、聲音」分頁。
// App 自己記一份設定（給預覽用，和鍵盤是同一套程式畫的），選好就透過具名剪貼簿（AppPick）傳給鍵盤；
// 鍵盤下次打開時照抄，主題圖、字體、聲音沒下載的鍵盤會自己再下載一份。
// 這樣大張的預覽圖和每種字體只在 App 裡載入，鍵盤本身用的記憶體比較少。

// MARK: - 共用的設定

final class LookStore: ObservableObject {
    static let shared = LookStore()
    let settings = KeyboardSettings.shared
    /// 設定變了就加一，畫面跟著重畫
    @Published private(set) var revision = 0
    /// 正在下載的主題、字體、聲音
    @Published var downloading: Set<String> = []
    @Published var message: String?

    private var soundIDs: [String: SystemSoundID] = [:]

    /// 選好了：通知鍵盤、重畫預覽
    func commit() {
        AppPick.publish(from: "app")
        revision += 1
    }

    /// 在鍵盤的 ⚙ 換過：App 跟著變
    func syncFromKeyboard() {
        guard let pick = AppPick.read(), pick.from == "keyboard" else { return }
        if !AppPick.apply(pick.values).isEmpty { revision += 1 }
    }

    // 主題

    func chooseTheme(_ id: String) {
        guard ThemePacks.isReady(id) else {
            download(id, title: KeyboardTheme.named(id).name, with: ThemePacks.download) { [weak self] in self?.setTheme(id) }
            return
        }
        setTheme(id)
    }

    private func setTheme(_ id: String) {
        if ThemeLook.named(settings.themeID) == nil && settings.themeID != FoxLetterTheme.id {
            settings.themeBeforeFox = settings.themeID
        }
        settings.themeID = id
        commit()
    }

    // 字體

    func chooseFont(_ font: KeyFont) {
        guard font.bundled || FontPacks.isReady(font.rawValue) else {
            download(font.rawValue, title: font.title, with: FontPacks.download) { [weak self] in
                self?.settings.fontID = font.rawValue
                self?.commit()
            }
            return
        }
        settings.fontID = font.rawValue
        commit()
    }

    /// 備用字體：選的字體裡沒有的字用這個補
    func chooseFallback(_ font: KeyFont) {
        guard font.bundled || FontPacks.isReady(font.rawValue) else {
            download(font.rawValue, title: font.title, with: FontPacks.download) { [weak self] in
                self?.settings.fontFallbackID = font.rawValue
                self?.commit()
            }
            return
        }
        settings.fontFallbackID = font.rawValue
        commit()
    }

    /// 下載過、不喜歡的字體移除（正在用的不能移除）
    func removeFont(_ font: KeyFont) {
        guard !font.bundled else { return }
        guard settings.fontID != font.rawValue, settings.fontFallbackID != font.rawValue else {
            message = "「\(font.title)」正在使用，先換別的字體再移除"
            return
        }
        FontPacks.remove(font.rawValue)
        revision += 1
    }

    /// 下載過、不喜歡的主題移除（正在用的不能移除）
    func removeTheme(_ id: String) {
        guard settings.themeID != id else {
            message = "這個主題正在使用，先換別的主題再移除"
            return
        }
        ThemePacks.remove(id)
        revision += 1
    }

    // 聲音

    func chooseSound(_ sound: KeySound) {
        settings.keySoundStyle = sound.rawValue
        settings.keySound = true
        commit()
        play(sound)
    }

    func play(_ sound: KeySound) {
        if sound == .system {
            AudioServicesPlaySystemSound(1104)
            return
        }
        guard SoundPacks.isReady(sound) else {
            download(sound.rawValue, title: sound.title, with: { _, done in SoundPacks.download(sound, done: done) }) { [weak self] in
                self?.play(sound)
            }
            return
        }
        guard let name = sound.normalFiles.randomElement() else { return }
        playFile(name)
        // 機械軸放開還有一聲
        if let up = sound.releaseFile(big: false) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { [weak self] in self?.playFile(up) }
        }
    }

    private func playFile(_ name: String) {
        if let id = soundIDs[name] {
            AudioServicesPlaySystemSound(id)
            return
        }
        guard let url = SoundPacks.url(name) ?? Bundle.main.url(forResource: name, withExtension: "wav")
                ?? Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Sounds") else { return }
        var id: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(url as CFURL, &id) == noErr else { return }
        soundIDs[name] = id
        AudioServicesPlaySystemSound(id)
    }

    private func download(_ key: String, title: String, with start: (String, @escaping (Bool) -> Void) -> Void, then: @escaping () -> Void) {
        guard !downloading.contains(key) else { return }
        downloading.insert(key)
        start(key) { [weak self] ok in
            guard let self = self else { return }
            self.downloading.remove(key)
            if ok {
                then()
            } else {
                self.message = "「\(title)」下載失敗，檢查一下網路再試"
            }
        }
    }
}

// MARK: - 預覽（和鍵盤同一套程式畫）

enum PreviewLayouts {
    static var full: KeyboardLayout {
        KeyLayouts.layout(.init(mode: .zhuyin, layer: .letters, shift: .off, needsGlobe: false,
                                returnTitle: "換行", spaceTitle: "糯糯鍵盤", nextModeTitle: "中"))
    }

    /// 卡片上的一排：123、六顆注音、換行
    static var row: KeyboardLayout {
        let letters = Array(full.rows.first?.prefix(6) ?? [])
        let number = KeySpec(face: .text("123"), action: .layer(.numbers), width: 1.4, kind: .special, fontSize: 16)
        let enter = KeySpec(face: .symbol("return"), action: .returnKey, width: 1.6, kind: .accent, fontSize: 16)
        return KeyboardLayout(rows: [[number] + letters + [enter]], columns: 9)
    }
}

final class KeyboardPreviewHost: UIView {
    private let gradient = CAGradientLayer()
    private let paper = CALayer()
    private let grid: KeyboardGridView

    init(style: KeyboardStyle, layout: KeyboardLayout) {
        grid = KeyboardGridView(style: style)
        super.init(frame: .zero)
        clipsToBounds = true
        layer.cornerRadius = 14
        layer.addSublayer(gradient)
        layer.addSublayer(paper)
        paper.contentsRect = CGRect(x: 0, y: 0.2, width: 1, height: 0.8)
        grid.isUserInteractionEnabled = false
        addSubview(grid)
        grid.setLayout(layout)
        apply(style)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(_ s: KeyboardStyle) {
        FoxLetterWatercolor.finish = s.isIllustrated ? KeyboardSettings.shared.artFinish : .flat
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.colors = [s.theme.backgroundTop.cgColor, s.theme.backgroundBottom.cgColor]
        paper.contents = s.isFoxLetter ? FoxLetterWatercolor.backdrop : nil
        CATransaction.commit()
        grid.style = s
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        paper.frame = bounds
        CATransaction.commit()
        grid.frame = bounds.insetBy(dx: 3, dy: 5)
    }
}

struct KeyboardPreview: UIViewRepresentable {
    var style: KeyboardStyle
    var compact = false

    func makeUIView(context: Context) -> KeyboardPreviewHost {
        KeyboardPreviewHost(style: style, layout: compact ? PreviewLayouts.row : PreviewLayouts.full)
    }

    func updateUIView(_ view: KeyboardPreviewHost, context: Context) {
        view.apply(style)
    }
}

/// 分頁最上面：現在的樣子（整個鍵盤）
private struct CurrentPreview: View {
    @ObservedObject var store = LookStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            KeyboardPreview(style: store.settings.style())
                .frame(height: 230)
                .id(store.revision)
            Text("選好後切到糯糯鍵盤就會換好（鍵盤要開「允許完整取用」）。還沒下載的主題、字體、聲音，鍵盤會自己再下載一次。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

/// 「移除」小按鈕：下載過、不喜歡的主題和字體刪掉，要用再下載
private struct RemoveButton: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label("移除", systemImage: "trash")
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color(UIColor.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
        .foregroundColor(.red)
    }
}

private struct Card<Content: View>: View {
    var selected: Bool
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(selected ? Color.accentColor.opacity(0.12) : Color(UIColor.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .padding(.horizontal, 16)
    }
}

private struct SelectedMark: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.title2)
            .foregroundColor(.accentColor)
    }
}

private struct SectionTitle: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 14)
    }
}

private extension View {
    /// 打開分頁、回到 App 時，先跟鍵盤那邊對一下
    func syncsWithKeyboard(_ store: LookStore) -> some View {
        self
            .onAppear { store.syncFromKeyboard() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                store.syncFromKeyboard()
            }
            .alert(item: Binding(get: { store.message.map { AlertText(text: $0) } }, set: { _ in store.message = nil })) { a in
                Alert(title: Text(a.text))
            }
    }
}

private struct AlertText: Identifiable {
    let text: String
    var id: String { text }
}

// MARK: - 主題

struct ThemeGalleryView: View {
    @ObservedObject var store = LookStore.shared

    private struct Item: Identifiable {
        let id: String, name: String, emoji: String, subtitle: String
    }

    private var illustrated: [Item] {
        ThemeLook.all.map { Item(id: $0.theme.id, name: $0.theme.name, emoji: $0.emoji, subtitle: $0.subtitle) }
            + [Item(id: FoxLetterTheme.id, name: "小狐狸的楓葉信", emoji: "🦊", subtitle: "秋日水彩")]
    }

    private var classic: [Item] {
        KeyboardTheme.all.filter { $0.id != FoxLetterTheme.id && ThemeLook.named($0.id) == nil }
            .map { Item(id: $0.id, name: $0.name, emoji: "", subtitle: "") }
            + [Item(id: "custom", name: "自訂配色", emoji: "🎨", subtitle: "在鍵盤的 ⚙ 調顏色")]
    }

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 12) {
                    CurrentPreview()
                    SectionTitle(text: "插畫主題（要用時才下載）")
                    ForEach(illustrated) { card($0) }
                    SectionTitle(text: "經典配色")
                    ForEach(classic) { card($0) }
                }
                .padding(.bottom, 24)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("主題")
        }
        .navigationViewStyle(.stack)
        .syncsWithKeyboard(store)
    }

    private func card(_ item: Item) -> some View {
        let selected = store.settings.themeID == item.id
        let needsDownload = !ThemePacks.isReady(item.id)
        let removable = !needsDownload && !selected && !ThemePacks.files(item.id).isEmpty && !store.downloading.contains(item.id)
        return ZStack(alignment: .topTrailing) {
            themeButton(item, selected: selected, needsDownload: needsDownload)
            if removable {
                RemoveButton { store.removeTheme(item.id) }
                    .padding(.trailing, 30)
                    .padding(.top, 14)
            }
        }
    }

    private func themeButton(_ item: Item, selected: Bool, needsDownload: Bool) -> some View {
        Button {
            store.chooseTheme(item.id)
        } label: {
            Card(selected: selected) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        if !item.emoji.isEmpty {
                            Text(item.emoji).font(.title2)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.system(.headline, design: .rounded)).foregroundColor(.primary)
                            if !item.subtitle.isEmpty {
                                Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if store.downloading.contains(item.id) {
                            ProgressView()
                        } else if selected {
                            SelectedMark()
                        } else if needsDownload {
                            Label("下載", systemImage: "arrow.down.circle").font(.footnote.bold())
                        }
                    }
                    KeyboardPreview(style: store.settings.style(themeID: item.id), compact: true)
                        .frame(height: 58)
                        .id("\(item.id)-\(store.revision)-\(needsDownload)")
                        .opacity(needsDownload ? 0.75 : 1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 按鍵（造型、質感、動作、特效、字的顏色）

struct KeyLookView: View {
    @ObservedObject var store = LookStore.shared
    private let columns = [GridItem(.adaptive(minimum: 78), spacing: 8)]

    var body: some View {
        let s = store.settings
        let style = s.style()
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    CurrentPreview()
                    if ThemeLook.named(s.themeID)?.hasArt == false {
                        note("這個主題已配好造型和質感；換回其他主題就恢復你選的。")
                    } else if style.isIllustrated {
                        SectionTitle(text: "質感")
                        chips(ArtFinish.choices.map { ($0.rawValue, $0.title) }, selected: s.artFinish.rawValue) {
                            if let f = KeyFinish(rawValue: $0) { s.artFinish = f }
                        }
                    } else {
                        SectionTitle(text: "造型")
                        chips(KeyShape.allCases.map { ($0.rawValue, $0.title) }, selected: s.keyShape.rawValue) {
                            if let shape = KeyShape(rawValue: $0) { s.keyShape = shape }
                        }
                        SectionTitle(text: "質感")
                        chips(KeyFinish.allCases.map { ($0.rawValue, $0.title) }, selected: s.keyFinish.rawValue) {
                            if let f = KeyFinish(rawValue: $0) { s.keyFinish = f }
                        }
                    }
                    SectionTitle(text: "按下去的動作")
                    chips(KeyMotion.allCases.map { ($0.rawValue, $0.title) }, selected: s.keyMotion) { s.keyMotion = $0 }
                    SectionTitle(text: "按鍵特效（按下去冒出小圖案）")
                    chips(KeyEffect.allCases.map { ($0.rawValue, $0.title) }, selected: s.keyEffect) { s.keyEffect = $0 }
                    SectionTitle(text: "按鍵字的顏色")
                    colorGrid
                    note("注音、英文、數字和符號的顏色。更細的深淺可以在鍵盤的 ⚙ 用滑桿調。")
                }
                .padding(.bottom, 24)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("按鍵")
        }
        .navigationViewStyle(.stack)
        .syncsWithKeyboard(store)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
    }

    private func chips(_ items: [(String, String)], selected: String, pick: @escaping (String) -> Void) -> some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(items, id: \.0) { item in
                Button {
                    pick(item.0)
                    store.commit()
                } label: {
                    Text(item.1)
                        .font(.system(.subheadline, design: .rounded).weight(item.0 == selected ? .bold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundColor(item.0 == selected ? .white : .primary)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(item.0 == selected ? Color.accentColor : Color(UIColor.secondarySystemGroupedBackground))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    private var colorGrid: some View {
        let s = store.settings
        let theme = s.style().theme
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 38), spacing: 6)], spacing: 8) {
            ForEach([-1] + KeyboardTheme.candidateColors, id: \.self) { value in
                Button {
                    s.keyTextColor = value
                    store.commit()
                } label: {
                    ZStack {
                        Circle().fill(Color(value < 0 ? theme.key : UIColor(hex: UInt32(value))))
                        if value < 0 {
                            Text("主題").font(.system(size: 10, weight: .bold)).foregroundColor(Color(theme.keyText))
                        }
                    }
                    .frame(width: 34, height: 34)
                    .overlay(Circle().stroke(value == s.keyTextColor ? Color.accentColor : Color.gray.opacity(0.35),
                                             lineWidth: value == s.keyTextColor ? 3 : 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - 字體

struct FontGalleryView: View {
    @ObservedObject var store = LookStore.shared

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 12) {
                    CurrentPreview()
                    fallbackCard
                    ForEach(KeyFont.allCases, id: \.rawValue) { card($0) }
                    Text("自己買的字體：在「首頁」按「匯入我的字體」，再到鍵盤的 ⚙ 貼上。")
                        .font(.footnote).foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                }
                .padding(.bottom, 24)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("字體")
        }
        .navigationViewStyle(.stack)
        .syncsWithKeyboard(store)
    }

    /// 備用字體：選的字體缺字時用哪一款補
    private var fallbackCard: some View {
        let current = KeyFont(rawValue: store.settings.fontFallbackID) ?? .system
        return Card(selected: false) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("備用字體").font(.system(.headline, design: .rounded))
                    Spacer()
                    Menu {
                        ForEach(KeyFont.allCases, id: \.rawValue) { f in
                            Button {
                                store.chooseFallback(f)
                            } label: {
                                if f == current { Label(f.title, systemImage: "checkmark") } else { Text(f.title) }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(current == .system ? "手機內建" : current.title)
                            Image(systemName: "chevron.up.chevron.down").font(.caption)
                        }
                        .font(.subheadline.bold())
                    }
                }
                Text("選的字體裡沒有的字，用這款補上（例如落雁體缺的字）。沒下載的選了會先下載。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func card(_ font: KeyFont) -> some View {
        let ready = font.bundled || FontPacks.isReady(font.rawValue)
        let selected = store.settings.fontID == font.rawValue
        let inUse = selected || store.settings.fontFallbackID == font.rawValue
        return ZStack(alignment: .trailing) {
            fontButton(font, ready: ready, selected: selected)
            // 下載過、沒在用的可以移除
            if ready && !font.bundled && !inUse && !store.downloading.contains(font.rawValue) {
                RemoveButton { store.removeFont(font) }
                    .padding(.trailing, 30)
            }
        }
    }

    private func fontButton(_ font: KeyFont, ready: Bool, selected: Bool) -> some View {
        Button {
            store.chooseFont(font)
        } label: {
            Card(selected: selected) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(font.title).font(.system(.headline, design: .rounded)).foregroundColor(.primary)
                            Text(font.style).font(.caption).foregroundColor(.secondary)
                        }
                        Text("糯糯鍵盤 ㄅㄆㄇ Aa 123")
                            .font(ready ? Font(KeyFonts.font(font.rawValue, size: 24) as CTFont) : .system(size: 24))
                            .foregroundColor(ready ? .primary : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .id("\(font.rawValue)-\(ready)-\(store.revision)")
                    }
                    Spacer()
                    if store.downloading.contains(font.rawValue) {
                        ProgressView()
                    } else if selected {
                        SelectedMark()
                    } else if !ready {
                        Label("下載", systemImage: "arrow.down.circle").font(.footnote.bold())
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 聲音

struct SoundGalleryView: View {
    @ObservedObject var store = LookStore.shared

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 12) {
                    Toggle("按鍵聲音", isOn: Binding(get: { store.settings.keySound }, set: {
                        store.settings.keySound = $0
                        store.commit()
                    }))
                    .font(.system(.headline, design: .rounded))
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    Text("點一下聽聽看，順便換成這個聲音。機械軸是真實錄音，第一次會先下載（每種只有幾十 KB）；鍵盤也會自己再下載一次。")
                        .font(.footnote).foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                    ForEach(KeySound.allCases, id: \.rawValue) { card($0) }
                }
                .padding(.bottom, 24)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("聲音")
        }
        .navigationViewStyle(.stack)
        .syncsWithKeyboard(store)
    }

    private func card(_ sound: KeySound) -> some View {
        let selected = store.settings.keySound && store.settings.keySoundStyle == sound.rawValue
        let ready = SoundPacks.isReady(sound)
        return Button {
            store.chooseSound(sound)
        } label: {
            Card(selected: selected) {
                HStack(spacing: 12) {
                    Image(systemName: sound.downloadable ? "keyboard" : "iphone")
                        .font(.title3)
                        .frame(width: 30)
                        .foregroundColor(.accentColor)
                    Text(sound.title).font(.system(.headline, design: .rounded)).foregroundColor(.primary)
                    Spacer()
                    if store.downloading.contains(sound.rawValue) {
                        ProgressView()
                    } else if selected {
                        SelectedMark()
                    } else if !ready {
                        Image(systemName: "arrow.down.circle").foregroundColor(.accentColor)
                    } else {
                        Image(systemName: "speaker.wave.2").foregroundColor(.secondary)
                    }
                }
                .id("\(sound.rawValue)-\(store.revision)")
            }
        }
        .buttonStyle(.plain)
    }
}
