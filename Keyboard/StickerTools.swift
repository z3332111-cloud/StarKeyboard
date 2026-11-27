import UIKit
import ImageIO

/// 自製貼圖：從剪貼簿讀圖片（相簿、網頁、LINE、其他 App 複製的都可以）、純色背景自動去背、貼出去的大小。
enum StickerTools {
    /// 貼圖存的大小（最長邊）；貼出去時再照設定縮
    static let storedSide: CGFloat = 512

    /// 貼出去的大小：小（以前的大小）／中／大
    static let sizes: [(title: String, side: CGFloat)] = [("小", 180), ("中", 320), ("大", 512)]

    /// 不是圖片的剪貼簿格式（文字、網址、富文字），讀圖時跳過
    private static let textTypes: Set<String> = [
        "public.utf8-plain-text", "public.plain-text", "public.text", "public.url", "public.html",
        "public.rtf", "com.apple.flat-rtfd", "public.utf16-plain-text", "com.apple.webarchive",
    ]

    /// 剪貼簿裡的圖片，讀成最長邊 maxSide 的小圖。
    /// 每一種格式都試著當圖片讀（網頁常常是 WebP、GIF，以前只認 JPEG／PNG／HEIC 才讀不到）
    static func pasteboardImage(maxSide: CGFloat) -> UIImage? {
        let pb = UIPasteboard.general
        for type in pb.types where !textTypes.contains(type) {
            let found: UIImage? = autoreleasepool {
                guard let data = pb.data(forPasteboardType: type), data.count > 32,
                      let src = CGImageSourceCreateWithData(data as CFData, nil),
                      CGImageSourceGetCount(src) > 0 else { return nil }
                return UIImage.downsampled(src, maxSide: maxSide)
            }
            if let found { return found }
        }
        return pb.hasImages ? pb.image?.resized(maxSide: maxSide) : nil
    }

    /// 剪貼簿只有圖片網址（「拷貝圖片位址」、「複製連結」）時的網址
    static func pasteboardImageURL() -> URL? {
        let pb = UIPasteboard.general
        let candidates = [pb.url?.absoluteString, pb.string].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        for s in candidates where s.hasPrefix("http://") || s.hasPrefix("https://") {
            if !s.contains(" "), let url = URL(string: s) { return url }
        }
        return nil
    }

    /// 下載網址上的圖片（最多 15MB），讀成小圖，在主執行緒回報
    static func download(_ url: URL, maxSide: CGFloat, done: @escaping (UIImage?) -> Void) {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let image: UIImage? = autoreleasepool {
                guard let data, data.count > 32, data.count < 15_000_000,
                      let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
                return UIImage.downsampled(src, maxSide: maxSide)
            }
            DispatchQueue.main.async { done(image) }
        }.resume()
    }

    /// 純色背景（白底、黑底、任何單一顏色）自動去背：從四邊往內，把和背景同色、連在一起的地方變透明，
    /// 邊緣淡出不會有鋸齒。圖案裡面同色但沒有連到邊的地方會留著。背景不是單一顏色就回傳 nil。
    static func removeSolidBackground(_ image: UIImage) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let w = cg.width, h = cg.height
        guard w > 4, h > 4, w * h <= 1_200_000,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let raw = ctx.data else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = raw.bindMemory(to: UInt8.self, capacity: w * h * 4)

        // 四邊的像素：找出最多的顏色當背景色
        var border: [Int] = []
        for x in 0..<w { border.append(x); border.append((h - 1) * w + x) }
        for y in 1..<(h - 1) { border.append(y * w); border.append(y * w + w - 1) }
        var buckets: [Int: (count: Int, r: Int, g: Int, b: Int)] = [:]
        var transparentBorder = 0
        for i in border {
            let a = Int(px[i * 4 + 3])
            if a < 16 { transparentBorder += 1; continue }
            let r = Int(px[i * 4]), g = Int(px[i * 4 + 1]), b = Int(px[i * 4 + 2])
            let key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)
            let old = buckets[key] ?? (0, 0, 0, 0)
            buckets[key] = (old.count + 1, old.r + r, old.g + g, old.b + b)
        }
        // 已經是透明背景：不用再去
        if transparentBorder > border.count / 2 { return image }
        guard let top = buckets.values.max(by: { $0.count < $1.count }) else { return nil }
        let bg = (r: top.r / top.count, g: top.g / top.count, b: top.b / top.count)
        let tol = 42
        func dist(_ i: Int) -> Int {
            let dr = Int(px[i * 4]) - bg.r, dg = Int(px[i * 4 + 1]) - bg.g, db = Int(px[i * 4 + 2]) - bg.b
            return Int(Double(dr * dr + dg * dg + db * db).squareRoot())
        }
        let near = border.filter { px[$0 * 4 + 3] < 16 || dist($0) < tol }.count
        // 四邊大部分都是同一個顏色，才算純色背景
        guard Double(near) / Double(border.count) > 0.6 else { return nil }

        // 從四邊往內找連在一起的背景
        var isBg = [Bool](repeating: false, count: w * h)
        var stack: [Int] = []
        stack.reserveCapacity(w * 4)
        for i in border where px[i * 4 + 3] < 16 || dist(i) < tol {
            if !isBg[i] { isBg[i] = true; stack.append(i) }
        }
        while let i = stack.popLast() {
            let x = i % w, y = i / w
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] where nx >= 0 && ny >= 0 && nx < w && ny < h {
                let n = ny * w + nx
                if !isBg[n] && (px[n * 4 + 3] < 16 || dist(n) < tol) {
                    isBg[n] = true
                    stack.append(n)
                }
            }
        }
        var removed = 0
        for i in 0..<(w * h) where isBg[i] {
            px[i * 4] = 0; px[i * 4 + 1] = 0; px[i * 4 + 2] = 0; px[i * 4 + 3] = 0
            removed += 1
        }
        // 幾乎全部都被當成背景（圖案跟背景同色）：不去背
        guard removed < w * h * 95 / 100 else { return nil }
        // 邊緣：緊鄰背景、顏色又有點接近背景的像素，照接近的程度變半透明（不會有白邊、鋸齒）
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                guard !isBg[i], px[i * 4 + 3] > 0 else { continue }
                let touching = (x > 0 && isBg[i - 1]) || (x < w - 1 && isBg[i + 1]) || (y > 0 && isBg[i - w]) || (y < h - 1 && isBg[i + w])
                guard touching else { continue }
                let d = dist(i)
                guard d < tol * 2 else { continue }
                let keep = Double(d - tol) / Double(tol) * 0.7 + 0.3
                for c in 0..<4 { px[i * 4 + c] = UInt8(Double(px[i * 4 + c]) * max(0.3, min(1, keep))) }
            }
        }
        guard let out = ctx.makeImage() else { return nil }
        return UIImage(cgImage: out)
    }

    /// 貼出去用的 PNG（保留透明），照設定的大小縮
    static func pngForSending(url: URL, side: CGFloat) -> Data? {
        autoreleasepool { UIImage.downsampled(url: url, maxSide: side)?.pngData() }
    }
}
