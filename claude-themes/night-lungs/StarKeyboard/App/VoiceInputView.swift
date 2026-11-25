import SwiftUI
import Speech
import AVFoundation
import UIKit

/// Microphone use belongs to the foreground app, never the keyboard extension.
struct VoiceInputView: View {
    @StateObject private var speech = VoiceTranscriber()
    @State private var locale = "zh-TW"
    @State private var allowNetwork = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Section("說話變文字") {
                Text("想直接輸入聊天框，可點鍵盤右下方的系統 🎙。這頁則先辨識、檢查，再複製回原 App 貼上。")
                    .font(.footnote)
                Picker("說話語言", selection: $locale) {
                    Text("中文（台灣）").tag("zh-TW")
                    Text("中文（普通話）").tag("zh-CN")
                    Text("English").tag("en-US")
                    Text("Bahasa Melayu").tag("ms-MY")
                }.disabled(speech.busy)
                Toggle("允許 Apple 線上語音辨識", isOn: $allowNetwork).disabled(speech.busy)
                Text("預設只在裝置上辨識；若這台手機或語言不支援，會提示，不會自行改用網路。開啟線上辨識後，語音可能傳送給 Apple 處理。語音功能不受外部翻譯開關控制。")
                    .font(.footnote).foregroundStyle(.secondary)
                Button(speech.recording ? "停止錄音" : "開始說話（取代目前文字）") {
                    if speech.recording { speech.stop() }
                    else { speech.start(locale: locale, allowNetwork: allowNetwork) }
                }.disabled(speech.busy && !speech.recording)
                Text(speech.status).font(.footnote).accessibilityAddTraits(.updatesFrequently)
            }
            Section("確認文字，可以手動修改") {
                TextEditor(text: $speech.text).frame(minHeight: 150).disabled(speech.busy)
                    .accessibilityLabel("語音辨識結果")
                Button("複製文字，回原 App 貼上") {
                    UIPasteboard.general.setItems([["public.utf8-plain-text": speech.text]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(300)])
                    speech.status = "已複製！回原 App 長按輸入框 → 貼上（5 分鐘內有效）。"
                }.disabled(speech.busy || speech.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("不會自動傳送、保存錄音或加入剪貼簿歷史。只有按複製後才會進系統剪貼簿；若鍵盤開了自動記錄，之後仍可能被保存。離開此頁或切到背景會停止辨識。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("語音轉文字")
        .onDisappear { speech.cancel() }
        .onChange(of: scenePhase) { phase in if phase == .background { speech.cancel() } }
    }
}

final class VoiceTranscriber: ObservableObject {
    @Published var text = ""
    @Published var status = "按開始後才會請求麥克風與語音辨識權限。"
    @Published private(set) var busy = false
    @Published private(set) var recording = false
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var token: UUID?
    private var tapped = false
    private var audioActive = false

    func start(locale: String, allowNetwork: Bool) {
        guard !busy else { return }
        let id = UUID(); token = id; busy = true
        status = "正在準備辨識…"
        SFSpeechRecognizer.requestAuthorization { [weak self] authorization in
            DispatchQueue.main.async {
                guard let self = self, self.token == id else { return }
                guard authorization == .authorized else {
                    self.finish("未取得語音辨識權限，請到 iPhone 設定 → 糯糯鍵盤檢查權限。")
                    return
                }
                AVAudioSession.sharedInstance().requestRecordPermission { [weak self] allowed in
                    DispatchQueue.main.async {
                        guard let self = self, self.token == id else { return }
                        guard allowed else { self.finish("未取得麥克風權限，請到 iPhone 設定檢查。"); return }
                        self.begin(locale: locale, allowNetwork: allowNetwork, id: id)
                    }
                }
            }
        }
    }

    private func begin(locale: String, allowNetwork: Bool, id: UUID) {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)), recognizer.isAvailable else {
            finish("這個語言的辨識服務目前不可用，請換個語言或稍後再試。"); return
        }
        guard allowNetwork || recognizer.supportsOnDeviceRecognition else {
            finish("這台裝置不支援此語言的本機辨識。可換語言，或自行開啟 Apple 線上語音辨識。"); return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            audioActive = true
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                finish("目前沒有可用的麥克風，請檢查裝置或耳機。"); return
            }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = !allowNetwork
            self.request = request; self.recognizer = recognizer
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            tapped = true
            engine.prepare(); try engine.start()
            text = ""; recording = true; status = "正在聽…說完請按停止（每段最多 55 秒）。"
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self = self, self.token == id else { return }
                    if let result = result { self.text = result.bestTranscription.formattedString }
                    if let error = error { self.finish("辨識已停止：" + error.localizedDescription) }
                    else if result?.isFinal == true { self.finish("辨識完成，請確認文字再複製。") }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 55) { [weak self] in
                if self?.token == id && self?.recording == true { self?.stop() }
            }
        } catch { finish("無法開始錄音：" + error.localizedDescription) }
    }

    func stop() {
        guard recording else { return }
        stopAudio(); request?.endAudio()
        status = "正在整理最後一句…"
        let id = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self = self, self.token == id, self.busy else { return }
            self.finish("辨識已停止，請確認目前文字；最後一句可能尚未完成。")
        }
    }
    func cancel() { if busy { finish("已停止。再次按開始才會錄音。") } }
    private func stopAudio() {
        engine.stop()
        if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        if audioActive { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation); audioActive = false }
        recording = false
    }
    private func finish(_ message: String) {
        token = nil
        stopAudio(); request?.endAudio(); task?.cancel()
        task = nil; request = nil; recognizer = nil; busy = false; status = message
    }
}
