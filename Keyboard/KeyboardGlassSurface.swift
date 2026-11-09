import UIKit

/// 原生玻璃只負責材質；觸控仍由原本的按鍵／工具列處理。
/// 不可放進帶遮罩、rasterize 或 alpha < 1 的父視圖。
final class KeyboardGlassSurface: UIVisualEffectView {
    nonisolated static var isSupported: Bool {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    private var appliedTint: UIColor?
    private var appliedDark: Bool?
    private var appliedRadius: CGFloat?

    init() {
        super.init(effect: nil)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(tint: UIColor, isDark: Bool) {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            // 打字會重用按鍵：主題與染色沒變時，不重建效果。
            guard appliedTint != tint || appliedDark != isDark else { return }
            appliedTint = tint
            appliedDark = isDark
            overrideUserInterfaceStyle = isDark ? .dark : .light
            let glass = UIGlassEffect(style: .regular)
            glass.tintColor = tint
            // KeyButton 不接收觸控，按壓回饋由 grid 的 isPressed 驅動。
            glass.isInteractive = false
            effect = glass
        }
        #endif
    }

    func setCornerRadius(_ radius: CGFloat) {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), appliedRadius != radius {
            appliedRadius = radius
            cornerConfiguration = .uniformCorners(radius: .fixed(Double(radius)))
        }
        #endif
    }
}

extension KeyboardStyle {
    var usesNativeGlassBar: Bool {
        !isIllustrated && finish == .liquid && KeyboardGlassSurface.isSupported
    }

    var usesNativeGlassKeys: Bool {
        // 不規則造型需要路徑遮罩，沿用既有畫法，保留耳朵、肉球等輪廓。
        usesNativeGlassBar && (shape == .rounded || shape == .jelly)
    }
}
