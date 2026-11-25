import CoreGraphics
import Foundation

/// 角色主題（插畫按鍵）的質感：照圖案的透明邊緣算出凹凸，把亮面和陰影畫進圖裡。
/// 換質感時整張圖集算一次，每顆鍵共用；打字時不多花力氣。安卓 FoxLetter.kt 的 ArtFinish、網站 sim.js 的 artFinish 是同一套算法。
enum ArtFinish {
    /// 插畫可以選的質感（線稿是畫框線，插畫用不到）
    static let choices: [KeyFinish] = [.flat, .puffy, .raised, .liquid, .metal]

    private static func radius(_ finish: KeyFinish) -> Float {
        switch finish {
        case .puffy: return 18
        case .raised: return 9
        default: return 7
        }
    }

    static func apply(_ image: CGImage, finish: KeyFinish) -> CGImage? {
        guard choices.contains(finish), finish != .flat else { return image }
        let w = image.width, h = image.height
        guard w > 2, h > 2,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var alpha = [Float](repeating: 0, count: w * h)
        for i in 0..<(w * h) { alpha[i] = Float(px[i * 4 + 3]) / 255 }
        let s = Float(w) / 768
        let r1 = max(1, Int((radius(finish) * s).rounded()))
        let h1 = blur(blur(alpha, w, h, r1), w, h, r1)
        let big = finish != .raised
        let r2 = max(1, Int((40 * s).rounded()))
        let h2 = big ? blur(blur(alpha, w, h, r2), w, h, r2) : h1
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                let a = px[i * 4 + 3]
                guard a > 0 else { continue }
                let af = Float(a) / 255
                var c = (min(1, Float(px[i * 4]) / 255 / af), min(1, Float(px[i * 4 + 1]) / 255 / af), min(1, Float(px[i * 4 + 2]) / 255 / af))
                let e1 = shade(h1, w, h, x, y, r1)
                let e2 = big ? shade(h2, w, h, x, y, r2) : 0
                c = pixel(c, e1, e2, finish)
                px[i * 4] = UInt8((c.0 * af * 255).rounded())
                px[i * 4 + 1] = UInt8((c.1 * af * 255).rounded())
                px[i * 4 + 2] = UInt8((c.2 * af * 255).rounded())
            }
        }
        return ctx.makeImage()
    }

    /// 正數往白、負數往黑
    private static func light(_ v: Float, _ t: Float) -> Float { t >= 0 ? v + (1 - v) * t : v * (1 + t) }

    private static func pixel(_ c: (Float, Float, Float), _ e1: Float, _ e2: Float, _ finish: KeyFinish) -> (Float, Float, Float) {
        var (r, g, b) = c
        func all(_ t: Float) { r = light(r, t); g = light(g, t); b = light(b, t) }
        switch finish {
        case .raised:
            all(e1 > 0 ? e1 * 0.6 : e1 * 0.55)
        case .puffy:
            all(e1 > 0 ? e1 * 0.5 : e1 * 0.45)
            all(pow(max(e2, 0), 1.5) * 0.25)
        case .liquid:
            all(e1 > 0 ? e1 * 0.35 : e1 * 0.35)
            all(pow(max(e1, 0), 2) * 0.9)
            all(pow(max(e2, 0), 1.5) * 0.55)
            let lum = 0.3 * r + 0.59 * g + 0.11 * b
            r = lum + (r - lum) * 1.18; g = lum + (g - lum) * 1.18; b = lum + (b - lum) * 1.18
        case .metal:
            let lum = 0.3 * r + 0.59 * g + 0.11 * b
            r += (lum - r) * 0.6; g += (lum - g) * 0.6; b += (lum - b) * 0.6
            let env = 0.45 + 0.9 * (0.5 + 0.5 * sin(e2 * 4 + 0.6))
            r *= env; g *= env; b *= env
            if e1 < 0 { all(e1 * 0.5) }
            all(pow(max(e1, 0), 2) * 1)
        default:
            break
        }
        return (min(1, max(0, r)), min(1, max(0, g)), min(1, max(0, b)))
    }

    /// 光從左上來：邊緣朝光的一面是正（亮），背光是負（暗），約 -1～1
    private static func shade(_ m: [Float], _ w: Int, _ h: Int, _ x: Int, _ y: Int, _ r: Int) -> Float {
        let gx = (m[y * w + min(x + 1, w - 1)] - m[y * w + max(x - 1, 0)]) / 2
        let gy = (m[min(y + 1, h - 1) * w + x] - m[max(y - 1, 0) * w + x]) / 2
        return min(1, max(-1, (0.45 * gx + gy) * Float(3 * r)))
    }

    /// 方框模糊（先橫再直，超出邊界用邊上的值）
    private static func blur(_ src: [Float], _ w: Int, _ h: Int, _ r: Int) -> [Float] {
        let n = Float(2 * r + 1)
        var tmp = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            let row = y * w
            var sum: Float = 0
            for k in -r...r { sum += src[row + min(max(k, 0), w - 1)] }
            for x in 0..<w {
                tmp[row + x] = sum / n
                sum += src[row + min(x + r + 1, w - 1)] - src[row + max(x - r, 0)]
            }
        }
        var out = [Float](repeating: 0, count: w * h)
        for x in 0..<w {
            var sum: Float = 0
            for k in -r...r { sum += tmp[min(max(k, 0), h - 1) * w + x] }
            for y in 0..<h {
                out[y * w + x] = sum / n
                sum += tmp[min(y + r + 1, h - 1) * w + x] - tmp[max(y - r, 0) * w + x]
            }
        }
        return out
    }
}
