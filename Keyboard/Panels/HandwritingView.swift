import UIKit
import Vision

/// 手寫：左邊寫字，右邊一排功能鍵。停筆一下就辨識，候選字顯示在上面那條
final class HandwritingView: UIView {
    var onResult: (([String]) -> Void)?
    /// 認不出來或辨識出錯：說明給使用者看，也記進打字紀錄
    var onFailure: ((String) -> Void)?
    /// 上一個字辨識完後又開始寫新的字：先把第一個候選字送出
    var onAutoCommit: (() -> Void)?
    let sideGrid: KeyboardGridView
    var style: KeyboardStyle {
        didSet {
            sideGrid.style = style
            applyStyle()
        }
    }

    private let canvas = UIView()
    private let strokeLayer = CAShapeLayer()
    private let hintLabel = UILabel()
    private var strokes: [[CGPoint]] = []
    private var lastResults: [String] = []
    private var lastStrokeEnd = Date.distantPast
    private var timer: Timer?
    private var token = 0

    init(style: KeyboardStyle) {
        self.style = style
        sideGrid = KeyboardGridView(style: style)
        super.init(frame: .zero)
        canvas.layer.cornerRadius = 14
        canvas.layer.addSublayer(strokeLayer)
        strokeLayer.fillColor = nil
        strokeLayer.lineWidth = 7
        strokeLayer.lineCap = .round
        strokeLayer.lineJoin = .round
        hintLabel.text = "在這裡寫字 ✍︎"
        hintLabel.font = .rounded(20, .medium)
        hintLabel.textAlignment = .center
        canvas.addSubview(hintLabel)
        addSubview(canvas)
        addSubview(sideGrid)
        applyStyle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let sideW = min(84, bounds.width * 0.22)
        canvas.frame = CGRect(x: 6, y: 6, width: bounds.width - sideW - 10, height: bounds.height - 12)
        sideGrid.frame = CGRect(x: bounds.width - sideW - 2, y: 0, width: sideW, height: bounds.height)
        strokeLayer.frame = canvas.bounds
        hintLabel.frame = canvas.bounds
    }

    private func applyStyle() {
        let t = style.theme
        canvas.backgroundColor = t.key.withAlphaComponent(style.keyAlpha * 0.55)
        strokeLayer.strokeColor = t.keyText.cgColor
        hintLabel.textColor = t.keyText.withAlphaComponent(0.3)
    }

    func clear() {
        strokes.removeAll()
        lastResults = []
        token += 1
        timer?.invalidate()
        redraw()
    }

    // MARK: 寫字

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let p = touch.location(in: canvas)
        guard canvas.bounds.contains(p) else { return }
        timer?.invalidate()
        if !strokes.isEmpty && !lastResults.isEmpty && Date().timeIntervalSince(lastStrokeEnd) > 1.2 {
            onAutoCommit?()
            clear()
        }
        strokes.append([p])
        redraw()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, !strokes.isEmpty else { return }
        let points = event?.coalescedTouches(for: touch) ?? [touch]
        for t in points {
            strokes[strokes.count - 1].append(t.location(in: canvas))
        }
        redraw()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !strokes.isEmpty else { return }
        lastStrokeEnd = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in self?.recognize() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    private func redraw() {
        let path = UIBezierPath()
        for stroke in strokes {
            guard let first = stroke.first else { continue }
            path.move(to: first)
            if stroke.count == 1 {
                path.addLine(to: CGPoint(x: first.x + 0.5, y: first.y + 0.5))
            }
            for p in stroke.dropFirst() { path.addLine(to: p) }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        strokeLayer.path = path.cgPath
        CATransaction.commit()
        hintLabel.isHidden = !strokes.isEmpty
    }

    private func recognize() {
        token += 1
        let current = token
        HandwritingRecognizer.recognize(strokes: strokes) { [weak self] results, problem in
            guard let self = self, self.token == current else { return }
            self.lastResults = results
            self.onResult?(results)
            if results.isEmpty {
                self.onFailure?(problem.map { "手寫辨識出錯：\($0)" } ?? "沒認出來，寫大一點、一筆一筆分開一點再試試")
            }
        }
    }
}

enum HandwritingRecognizer {
    /// 辨識的設定：第一組沒結果或出錯，就換下一組再試（鍵盤裡有時某個語言模型載不起來）
    private static let attempts: [[String]] = [["zh-Hant", "en-US"], ["zh-Hant"], ["zh-Hans", "en-US"]]

    /// 回傳候選字，和最後一次出錯的原因（沒出錯是 nil）
    static func recognize(strokes: [[CGPoint]], completion: @escaping ([String], String?) -> Void) {
        guard let image = render(strokes) else {
            completion([], nil)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var problem: String?
            for languages in attempts {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                let supported = (try? request.supportedRecognitionLanguages()) ?? []
                let usable = languages.filter { supported.isEmpty || supported.contains($0) }
                guard !usable.isEmpty else { problem = "這支手機的辨識不支援 \(languages.joined(separator: "、"))"; continue }
                request.recognitionLanguages = usable
                do {
                    try autoreleasepool { try VNImageRequestHandler(cgImage: image, options: [:]).perform([request]) }
                } catch {
                    problem = error.localizedDescription
                    continue
                }
                let out = candidates(request.results ?? [])
                if !out.isEmpty {
                    DispatchQueue.main.async { completion(out, nil) }
                    return
                }
            }
            DispatchQueue.main.async { completion([], problem) }
        }
    }

    private static func candidates(_ observations: [VNRecognizedTextObservation]) -> [String] {
        var out: [String] = []
        for obs in observations {
            for candidate in obs.topCandidates(10) {
                let s = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty && !out.contains(s) { out.append(s) }
            }
        }
        // 認成好幾個字時，也把單字拆出來給人選
        for s in out where s.count > 1 {
            for ch in s where !out.contains(String(ch)) && !ch.isWhitespace {
                out.append(String(ch))
            }
        }
        return out
    }

    /// 把筆畫畫成白底黑字的圖，放大置中，留白邊
    static func render(_ strokes: [[CGPoint]]) -> CGImage? {
        let points = strokes.flatMap { $0 }
        guard let minX = points.map({ $0.x }).min(), let maxX = points.map({ $0.x }).max(),
              let minY = points.map({ $0.y }).min(), let maxY = points.map({ $0.y }).max() else { return nil }
        let w = max(maxX - minX, 1), h = max(maxY - minY, 1)
        let scale = 220 / max(w, h, 40)
        let pad: CGFloat = 70
        let size = CGSize(width: w * scale + pad * 2, height: h * scale + pad * 2)
        func map(_ p: CGPoint) -> CGPoint {
            CGPoint(x: (p.x - minX) * scale + pad, y: (p.y - minY) * scale + pad)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let path = UIBezierPath()
            path.lineWidth = 14
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            for stroke in strokes {
                guard let first = stroke.first else { continue }
                path.move(to: map(first))
                if stroke.count == 1 {
                    let m = map(first)
                    path.addLine(to: CGPoint(x: m.x + 0.5, y: m.y + 0.5))
                }
                for p in stroke.dropFirst() { path.addLine(to: map(p)) }
            }
            UIColor.black.setStroke()
            path.stroke()
        }
        return image.cgImage
    }
}
