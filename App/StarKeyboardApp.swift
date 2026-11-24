import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import Vision
import CoreImage

@main
struct StarKeyboardApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var testText = ""
    @State private var showingPhotoPicker = false
    @State private var showingFontPicker = false
    /// 挑照片要做什麼：photo 背景／貼圖、cutout 空白鍵（去背）、space 空白鍵（不去背）
    @State private var pickPurpose = "photo"
    @State private var message: String?
    @State private var latest: ReleaseInfo?
    /// 檢查新版：checking 檢查中、done 檢查完、failed 連不上
    @State private var updateState = "checking"
    /// 邊調邊看：大小和透明度（拖滑桿時透過具名剪貼簿傳給鍵盤）
    @State private var look = LiveLook()
    @State private var lookCount = -1
    private let lookTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private let pink = Color(red: 1.0, green: 0.5, blue: 0.65)

    var body: some View {
        NavigationView {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Image("BrandMark")
                            .resizable().frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 17))
                        Text("糯糯鍵盤")
                            .font(.system(.largeTitle, design: .rounded).bold())
                        Text("注音、手寫、英文、表符、顏文字、剪貼簿，還有可愛的主題。")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(ReleaseChecker.currentVersionText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    NavigationLink(destination: PrivacySafetyView()) {
                        Label("隱私與安全", systemImage: "hand.raised")
                    }
                    Text("剪貼簿與外部翻譯預設關閉。使用前請了解保存內容與連網風險。")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("版本") {
                    updateStatus
                    Button(updateState == "checking" ? "檢查中…" : "再檢查一次") { checkUpdate() }
                        .disabled(updateState == "checking")
                }

                if let latest = latest, latest.build > ReleaseChecker.currentBuild {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("🎉 有新版：\(latest.title)（第 \(latest.build) 版）")
                                .font(.system(.headline, design: .rounded))
                            Text(latest.notes)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text("更新方法（都在手機上）：\n1. 點下面「前往下載」，下載新的 .ipa\n2. 打開 LocalDevVPN，確認已連上\n3. 打開 SideStore，左上角 ＋，選剛下載的檔案，蓋過舊的糯糯鍵盤\n不要先刪掉舊 App，設定和資料會保留。")
                                .font(.footnote)
                        }
                        .padding(.vertical, 4)
                        Link("前往下載", destination: ReleaseChecker.downloadPage)
                    }
                }

                Section("第一次使用：打開鍵盤") {
                    step(1, "打開「設定」App › 一般 › 鍵盤 › 鍵盤 › 新增鍵盤…")
                    step(2, "在「第三方鍵盤」選「糯糯鍵盤」")
                    step(3, "點「糯糯鍵盤」，打開「允許完整取用」（剪貼簿、聲音、震動、貼圖、背景圖都需要）")
                    step(4, "打字時長按 🌐 地球鍵，切換到糯糯鍵盤")
                    Button("打開本 App 的設定頁") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                Section("語音輸入") {
                    NavigationLink(destination: VoiceInputView()) {
                        Label("語音轉文字", systemImage: "mic")
                    }
                    Text("直接在聊天框輸入可用鍵盤右下的系統麥克風；也可在這裡辨識、確認，再複製貼上。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Text("先點下面「試打看看」的框，叫出糯糯鍵盤，再拖滑桿，鍵盤會馬上跟著變。（要打開「允許完整取用」）")
                        .font(.footnote).foregroundStyle(.secondary)
                    lookSlider("鍵盤高度", value: $look.heightScale, range: 0.8...1.3)
                    lookSlider("字的大小", value: $look.fontScale, range: 0.8...1.4)
                    lookSlider("按鍵間距", value: $look.gapScale, range: 0.3...1.6)
                    lookSlider("造型大小", value: $look.shapeScale, range: 0.9...1.6)
                    lookSlider("按鍵透明度", value: $look.keyAlpha, range: 0...1)
                    lookSlider("照片淡化", value: $look.backgroundFade, range: 0...0.9)
                    Button("大小恢復預設") {
                        look.heightScale = 1; look.fontScale = 1; look.gapScale = 1; look.shapeScale = 1.15
                    }
                } header: {
                    Text("大小與透明度（邊調邊看）")
                }
                .onAppear { readLook() }
                .onReceive(lookTimer) { _ in readLook() }
                .onChange(of: look) { newValue in
                    lookCount = newValue.publish(from: "app")
                }

                Section("試打看看") {
                    Text("在這裡試試新鍵盤").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $testText)
                        .frame(minHeight: 90, maxHeight: 180)
                        .accessibilityLabel("在這裡試試新鍵盤")
                }

                Section {
                    Button { pickPurpose = "photo"; showingPhotoPicker = true } label: {
                        Label("挑照片（可以一次挑好幾張）", systemImage: "photo.on.rectangle.angled")
                    }
                    Text("照片會被複製到剪貼簿，一次最多 10 張。接著打開鍵盤：\n• 當背景：⚙️ 設定 › 背景圖片 › 從剪貼簿貼上圖片（挑幾張就一次加幾張）\n• 做成貼圖：☺ 表符 › ⭐ 我的 › ＋ › 把剪貼簿的圖片做成貼圖（用第一張）")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("背景圖片與自製貼圖")
                }

                Section {
                    Button { pickPurpose = "cutout"; showingPhotoPicker = true } label: {
                        Label("挑照片（自動去背）", systemImage: "scissors")
                    }
                    Button { pickPurpose = "space"; showingPhotoPicker = true } label: {
                        Label("挑照片（不去背）", systemImage: "photo")
                    }
                    Text("做成空白鍵中間的小圖。挑好會先複製起來，接著打開鍵盤：⚙️ 設定 › 空白鍵 › 貼上圖片／GIF。自動去背要 iOS 17 以上。GIF 動圖請在相簿或聊天裡直接「拷貝」，再到鍵盤貼上。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("空白鍵圖案")
                }

                Section {
                    Button { showingFontPicker = true } label: {
                        Label("匯入我的字體", systemImage: "textformat")
                    }
                    Text("可以用自己買的字體（.ttf／.otf），只在自己的鍵盤上顯示。挑好檔案後會先複製起來，接著打開鍵盤：⚙️ 設定 › 字體 › 貼上我的字體。中文字體檔通常比較大，超過 40MB 的鍵盤裝不下。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("我的字體")
                }

                Section("使用小提醒") {
                    tip("剪貼簿分類", "預設只顯示「全部、📌 釘選」。按側邊固定的「＋」，在跳出的命名小框用下方鍵盤取名，按「建立」後才出現新分頁；取消不會新增；點每筆右邊的資料夾按鈕選歸類。資料夾管理可改名或移除分類，移除後內容留在未分類。已分類或釘選的內容不會被容量上限或「清暫存」自動清掉。JSON 備份包含分類。")
                    tip("剪貼簿", "iOS 不讓鍵盤在背景偷看剪貼簿，所以是「打開鍵盤的時候」才把剛複製的東西記下來。複製完切到要打字的地方就會記到。")
                    tip("注音", "大千排列。打到一半、還沒加聲調就會先出現相關詞，例如 ㄋㄧ → 你好、你們。常用單字依字頻與選字習慣排序，開啟聯想詞時也參考游標前的文字。點候選詞即可整段送出，常選的字下次會往前排。")
                    tip("手寫", "寫完停一下就會辨識，點候選字送出；直接寫下一個字會自動送出第一個候選字。")
                    tip("打錯字", "英文打錯按空白會自動修正，改錯了馬上按刪除就復原。注音按到旁邊的鍵、聲調打錯也猜得到；分不清ㄣㄥ、ㄓㄗ可以在 ⚙️ 打開模糊音。")
                    tip("拼音", "給習慣漢語拼音的人（例如馬來西亞朋友）：到 ⚙️ 設定 › 輸入法 打開「拼音」，打 nihao 或只打聲母 nh 就出「你好」，預設是繁體字，可以在設定改成簡體。")
                    tip("韓文、日文", "到鍵盤 ⚙️ 設定 › 輸入法 打開。韓文照兩排式自動拼字；日文打羅馬拼音（sakura）變成假名，可選平假名或片假名。")
                    tip("翻譯", "工具列的「譯」：先打中文，按「→英文」換語言，再按「翻譯」，點結果就送出。")
                    tip("自製表符", "在 ⭐ 我的 按 ＋ 就能新增；長按可以刪除。")
                    tip("空白鍵", "按住空白鍵左右滑，可以移動游標。")
                    tip("7 天續簽", "免費 Apple ID 的簽章 7 天到期。SideStore 會自己續，也可以在背景續；快到期時打開 LocalDevVPN，SideStore 的 My Apps 會看到剩幾天。不用再接電腦。")
                    tip("怎麼更新", "1. 用 iPhone 打開安裝網站，下載新的 .ipa\n2. 打開 LocalDevVPN，確認已連上\n3. 打開 SideStore，左上角 ＋，選剛下載的檔案，蓋過舊的糯糯鍵盤（延伸功能選 Keep App Extensions）\n不要先刪掉舊 App，設定和資料會保留。")
                    Link("查看更新步驟（安裝網站）", destination: URL(string: "https://z3332111-cloud.github.io/StarKeyboard/#wifi-refresh")!)
                }
            }
            .navigationTitle("糯糯鍵盤")
            .navigationBarTitleDisplayMode(.inline)
            .tint(pink)
            .task { checkUpdate() }
            .sheet(isPresented: $showingPhotoPicker) {
                KeyboardPhotoPicker(limit: pickPurpose == "photo" ? 10 : 1) { images in
                    showingPhotoPicker = false
                    guard let image = images.first else { return }
                    if pickPurpose == "photo" { copyPhotos(images) } else { copySpaceImage(image, cutout: pickPurpose == "cutout") }
                }
            }
            .fileImporter(isPresented: $showingFontPicker, allowedContentTypes: [.font]) { result in
                if case .success(let url) = result { copyFont(url) }
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("好") {}
            }
        }
    }

    /// 版本那一格：檢查中／已經是最新版／有新版／連不上
    @ViewBuilder private var updateStatus: some View {
        if updateState == "checking" {
            HStack(spacing: 8) { ProgressView(); Text("正在檢查有沒有新版…").font(.subheadline) }
        } else if updateState == "failed" || latest == nil {
            Text("⚠️ 沒辦法檢查新版（可能沒有網路），等一下再試一次。").font(.subheadline)
        } else if let latest = latest, latest.build > ReleaseChecker.currentBuild {
            Text("🎉 有新版可以更新：\(latest.title)（第 \(latest.build) 版）").font(.subheadline.bold()).foregroundStyle(pink)
        } else if ReleaseChecker.currentBuild == 0 {
            Text("這是自己在電腦上編的測試版，沒辦法比對版本。").font(.subheadline)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("✅ 已經是最新版").font(.subheadline.bold()).foregroundStyle(.green)
                Text(ReleaseChecker.currentVersionText).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func checkUpdate() {
        updateState = "checking"
        ReleaseChecker.fetchLatest { info in
            latest = info
            updateState = info == nil ? "failed" : "done"
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.system(.callout, design: .rounded).bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(pink))
            Text(text)
                .font(.system(.callout, design: .rounded))
        }
    }

    private func tip(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(.callout, design: .rounded).bold())
            Text(text).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    /// 空白鍵的小圖：可以先自動去背（iOS 17 的 Vision 抓主體），存成透明底的 PNG 複製起來
    @MainActor
    private func copySpaceImage(_ image: UIImage, cutout: Bool) {
        let side: CGFloat = 900
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, side / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        var result = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        var note = ""
        if cutout {
            if #available(iOS 17.0, *), let cut = Self.removeBackground(result) {
                result = cut
            } else {
                note = "（這張找不到主體，或手機版本低於 iOS 17，所以沒有去背）"
            }
        }
        guard let png = result.pngData() else { message = "處理失敗，換一張試試。"; return }
        UIPasteboard.general.setData(png, forPasteboardType: "public.png")
        message = "複製好了！\(note)\n現在打開鍵盤，到 ⚙️ 設定 › 空白鍵 按「貼上圖片／GIF」。"
    }

    @available(iOS 17.0, *)
    private static func removeBackground(_ image: UIImage) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
            guard let obs = request.results?.first else { return nil }
            let buffer = try obs.generateMaskedImage(ofInstances: obs.allInstances, from: handler, croppedToInstancesExtent: true)
            let ci = CIImage(cvPixelBuffer: buffer)
            guard let out = CIContext().createCGImage(ci, from: ci.extent) else { return nil }
            return UIImage(cgImage: out)
        } catch {
            return nil
        }
    }

    /// 字體檔放到剪貼簿（只在這台手機、10 分鐘後消失），鍵盤再從剪貼簿收下
    private func copyFont(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            message = "讀不到這個檔案，請再試一次。"
            return
        }
        guard data.count <= 40 * 1024 * 1024 else {
            message = "這個字體檔超過 40MB，鍵盤裝不下。可以找同一套字體比較小的版本（例如只有常用字的）。"
            return
        }
        guard let provider = CGDataProvider(data: data as CFData), CGFont(provider) != nil else {
            message = "這個檔案不是可以用的字體，請挑 .ttf 或 .otf 檔。"
            return
        }
        let name = url.deletingPathExtension().lastPathComponent
        UIPasteboard.general.setItems([["tw.nuonuo.font": data, "tw.nuonuo.fontname": name]],
                                      options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(600)])
        message = "字體複製好了！現在打開鍵盤，到 ⚙️ 設定 › 字體 按「貼上我的字體」。"
    }

    private func lookSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).frame(width: 88, alignment: .leading)
            Slider(value: value, in: range)
        }
    }

    /// 鍵盤那邊改過（或剛打開時）就把滑桿移到鍵盤現在的值
    private func readLook() {
        let count = LiveLook.changeCount
        guard count != lookCount else { return }
        lookCount = count
        if let last = LiveLook.read(), last.from == "keyboard", last.look != look {
            look = last.look
            lookCount = LiveLook.changeCount
        }
    }

    /// 一張或好幾張照片一起放進剪貼簿（每張一個項目），鍵盤貼上時一次全部加進去
    @MainActor
    private func copyPhotos(_ images: [UIImage]) {
        // 縮到 1600（跟鍵盤存的大小一樣，放大對準臉也不糊）
        let items: [[String: Any]] = images.compactMap { image in
            let longest = max(image.size.width, image.size.height)
            let scale = min(1, 1600 / longest)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            return resized.jpegData(compressionQuality: 0.9).map { ["public.jpeg": $0] }
        }
        guard !items.isEmpty else { return }
        UIPasteboard.general.setItems(items)
        message = images.count > 1
            ? "\(images.count) 張照片複製好了！現在打開鍵盤，到 ⚙️ 設定 › 背景圖片 按「從剪貼簿貼上」，會一次全部加進去。"
            : "已經複製好了！現在打開鍵盤，到 ⚙️ 設定貼上當背景，或到 ⭐ 我的 做成貼圖。"
    }
}
