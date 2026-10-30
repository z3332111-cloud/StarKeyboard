import SwiftUI
import PhotosUI
import UIKit

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
    @State private var message: String?
    @State private var latest: ReleaseInfo?

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
                        Text(ReleaseChecker.currentBuild > 1 ? "目前是第 \(ReleaseChecker.currentBuild) 版" : "開發版")
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

                if let latest = latest, latest.build > ReleaseChecker.currentBuild {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("🎉 有新版：\(latest.title)")
                                .font(.system(.headline, design: .rounded))
                            Text(latest.notes)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text("更新方法：在電腦下載新的 StarKeyboard.ipa，用原 Apple ID 和 Sideloadly 直接安裝；完成 Wi-Fi 配對後可免插線。保留自動續簽設定，讓 Daemon 改用新版。不要先刪掉舊 App，以保留設定與資料。")
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

                Section("試打看看") {
                    Text("在這裡試試新鍵盤").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $testText)
                        .frame(minHeight: 90, maxHeight: 180)
                        .accessibilityLabel("在這裡試試新鍵盤")
                }

                Section {
                    Button { showingPhotoPicker = true } label: {
                        Label("挑一張照片", systemImage: "photo.on.rectangle.angled")
                    }
                    Text("照片會被複製到剪貼簿。接著打開鍵盤：\n• 當背景：⚙️ 設定 › 背景圖片 › 從剪貼簿貼上圖片\n• 做成貼圖：☺ 表符 › ⭐ 我的 › ＋ › 把剪貼簿的圖片做成貼圖")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("背景圖片與自製貼圖")
                }

                Section("使用小提醒") {
                    tip("剪貼簿", "iOS 不讓鍵盤在背景偷看剪貼簿，所以是「打開鍵盤的時候」才把剛複製的東西記下來。複製完切到要打字的地方就會記到。")
                    tip("注音", "大千排列。打到一半、還沒加聲調就會先出現相關詞，例如 ㄋㄧ → 你好、你們。常用單字依字頻與選字習慣排序，開啟聯想詞時也參考游標前的文字。點候選詞即可整段送出，常選的字下次會往前排。")
                    tip("手寫", "寫完停一下就會辨識，點候選字送出；直接寫下一個字會自動送出第一個候選字。")
                    tip("打錯字", "英文打錯按空白會自動修正，改錯了馬上按刪除就復原。注音按到旁邊的鍵、聲調打錯也猜得到；分不清ㄣㄥ、ㄓㄗ可以在 ⚙️ 打開模糊音。")
                    tip("拼音", "給習慣漢語拼音的人（例如馬來西亞朋友）：到 ⚙️ 設定 › 輸入法 打開「拼音」，打 nihao 或只打聲母 nh 就出「你好」，預設是繁體字，可以在設定改成簡體。")
                    tip("韓文、日文", "到鍵盤 ⚙️ 設定 › 輸入法 打開。韓文照兩排式自動拼字；日文打羅馬拼音（sakura）變成假名，可選平假名或片假名。")
                    tip("翻譯", "工具列的「譯」：先打中文，按「→英文」換語言，再按「翻譯」，點結果就送出。")
                    tip("自製表符", "在 ⭐ 我的 按 ＋ 就能新增；長按可以刪除。")
                    tip("空白鍵", "按住空白鍵左右滑，可以移動游標。")
                    tip("Wi-Fi 自動續簽", "免費 Apple ID 的簽章有效 7 天。首次插線配對並啟用 Wi-Fi 同步及 Sideloadly 自動續簽後，可由 Daemon 在快到期時無線續簽。電腦須開著且保持喚醒，Daemon 有執行，手機能在同一網路被找到。")
                    tip("續簽與新版", "Daemon 續簽的是已登錄的版本，不會自動下載 GitHub 新版。更新時下載新 IPA，用原 Apple ID 安裝並保留自動續簽；不要先刪除舊 App。")
                    Link("查看 Wi-Fi 續簽設定步驟", destination: URL(string: "https://z3332111-cloud.github.io/StarKeyboard/#wifi-refresh")!)
                }
            }
            .navigationTitle("糯糯鍵盤")
            .navigationBarTitleDisplayMode(.inline)
            .tint(pink)
            .task {
                ReleaseChecker.fetchLatest { info in latest = info }
            }
            .sheet(isPresented: $showingPhotoPicker) {
                KeyboardPhotoPicker { image in
                    showingPhotoPicker = false
                    guard let image = image else { return }
                    copyPhoto(image)
                }
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("好") {}
            }
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

    @MainActor
    private func copyPhoto(_ image: UIImage) {
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 1000 / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        UIPasteboard.general.image = resized
        message = "已經複製好了！現在打開鍵盤，到 ⚙️ 設定貼上當背景，或到 ⭐ 我的 做成貼圖。"
    }
}
