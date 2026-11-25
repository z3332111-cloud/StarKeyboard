import XCTest
import UIKit

final class FoxLetterThemeTests: XCTestCase {
    @MainActor
    private func style(fox: Bool = true) -> KeyboardStyle {
        FoxLetterTheme.resolved(KeyboardStyle(theme: KeyboardTheme.named(fox ? FoxLetterTheme.id : "milktea"),
            shape: .bunny, keyAlpha: 1, fontScale: 1, gapScale: 1, fontID: KeyFont.system.rawValue,
            finish: .metal, shapeScale: 1.15, motion: KeyMotion.none.rawValue))
    }

    private func context(_ mode: InputMode, _ layer: KeyboardLayer, globe: Bool, ten: Bool, shift: ShiftState = .off) -> KeyLayouts.Context {
        KeyLayouts.Context(mode: mode, layer: layer, shift: shift, needsGlobe: globe,
            returnTitle: "搜尋", spaceTitle: mode.title, nextModeTitle: "英", fullWidthSymbols: true, zhuyinTenColumns: ten)
    }

    @MainActor
    private func artwork(in key: KeyButton) -> [FoxLetterArtworkView] {
        key.subviews.flatMap { $0.subviews.compactMap { $0 as? FoxLetterArtworkView } }
    }

    @MainActor
    private func validate(_ layout: KeyboardLayout, width: CGFloat, height: CGFloat, style: KeyboardStyle,
                          file: StaticString = #filePath, line: UInt = #line) {
        let grid = KeyboardGridView(style: style)
        grid.frame = CGRect(x: 0, y: 0, width: width, height: height)
        grid.setLayout(layout)
        grid.layoutIfNeeded()
        XCTAssertEqual(grid.keys.count, layout.rows.flatMap { $0 }.count, file: file, line: line)
        for (i, key) in grid.keys.enumerated() {
            key.layoutIfNeeded()
            XCTAssertEqual(key.illustratedIndex, i, file: file, line: line)
            XCTAssertEqual(artwork(in: key).count, 1, file: file, line: line)
            XCTAssertGreaterThan(key.frame.width, 0, file: file, line: line)
            XCTAssertGreaterThan(key.frame.height, 0, file: file, line: line)
            XCTAssertTrue(grid.bounds.insetBy(dx: -0.1, dy: -0.1).contains(key.frame), file: file, line: line)
            for container in key.subviews {
                for label in container.subviews.compactMap({ $0 as? UILabel }) where !label.isHidden && !(label.text ?? "").isEmpty {
                    XCTAssertGreaterThan(label.frame.height, 0, file: file, line: line)
                    XCTAssertTrue(key.bounds.contains(label.frame), file: file, line: line)
                    XCTAssertLessThanOrEqual(label.font.lineHeight, label.frame.height + 0.1, file: file, line: line)
                }
            }
        }
    }

    @MainActor
    func testEveryExistingInputModeAndPageAtNarrowAndLandscapeSizes() async {
        for image in [FoxLetterWatercolor.keycaps, FoxLetterWatercolor.wideKeycaps, FoxLetterWatercolor.backdrop] {
            XCTAssertNotNil(image, "測試 bundle 必須包含 FoxLetter 水彩素材")
            if let image { XCTAssertLessThanOrEqual(max(image.width, image.height), 768) }
        }
        for mode in InputMode.allCases {
            for layer in [KeyboardLayer.letters, .numbers, .symbols, .numpad] {
                for globe in [false, true] {
                    for ten in [false, true] {
                        autoreleasepool {
                            let layout = KeyLayouts.layout(context(mode, layer, globe: globe, ten: ten))
                            validate(layout, width: 320, height: 180, style: style())
                            var enlarged = style()
                            enlarged.fontScale = 1.3
                            enlarged.gapScale = 1.8
                            enlarged.shapeScale = 1.3
                            validate(layout, width: 700, height: 164, style: enlarged)
                        }
                    }
                }
            }
        }
    }

    @MainActor
    func testHandwritingFunctionColumnKeepsLabelsAndIcons() async {
        let layout = KeyLayouts.handwritingSide(returnTitle: "完成", nextModeTitle: "英")
        validate(layout, width: 78, height: 216, style: style())
        XCTAssertTrue(layout.rows.flatMap { $0 }.contains { $0.action == .clearCanvas })
        XCTAssertTrue(layout.rows.flatMap { $0 }.contains { $0.action == .returnKey })
    }

    @MainActor
    func testCaseChangeAndCursorModeReuseArtworkAndKeepActions() async {
        let grid = KeyboardGridView(style: style())
        grid.frame = CGRect(x: 0, y: 0, width: 390, height: 216)
        grid.setLayout(KeyLayouts.layout(context(.english, .letters, globe: false, ten: false)))
        grid.layoutIfNeeded()
        let key = grid.keys[0]
        let original = artwork(in: key).first
        let originalColor = original?.textColor
        grid.setLayout(KeyLayouts.layout(context(.english, .letters, globe: false, ten: false, shift: .locked)))
        grid.layoutIfNeeded()
        XCTAssertTrue(grid.keys[0] === key)
        XCTAssertTrue(artwork(in: key).first === original)
        XCTAssertEqual(original?.textColor, originalColor)
        XCTAssertEqual(key.spec.action, .text("Q"))
        key.visualOpacity = 0.45
        key.isPressed = true
        key.isPressed = false
        key.visualOpacity = 1
        XCTAssertEqual(artwork(in: key).count, 1)
    }

    @MainActor
    func testThemeRoundTripRemovesArtworkAndRestoresOtherFinishes() async {
        let grid = KeyboardGridView(style: style())
        grid.frame = CGRect(x: 0, y: 0, width: 390, height: 216)
        grid.setLayout(KeyLayouts.layout(context(.english, .letters, globe: false, ten: false)))
        grid.layoutIfNeeded()
        for _ in 0..<3 {
            grid.style = style(fox: false)
            grid.layoutIfNeeded()
            grid.keys.forEach { $0.layoutIfNeeded(); XCTAssertTrue(artwork(in: $0).isEmpty) }
            grid.style = style()
            grid.layoutIfNeeded()
            grid.keys.forEach { $0.layoutIfNeeded(); XCTAssertEqual(artwork(in: $0).count, 1) }
        }
    }

    @MainActor
    func testResolvingIllustratedThemeDoesNotOverwritePersonalStyle() async {
        let saved = KeyboardStyle(theme: KeyboardTheme.named(FoxLetterTheme.id), shape: .bunny,
            keyAlpha: 0.6, fontScale: 1.2, gapScale: 0.8, finish: .liquid, shapeScale: 1.25)
        let resolved = FoxLetterTheme.resolved(saved)
        XCTAssertEqual(saved.shape, .bunny)
        XCTAssertEqual(saved.finish, .liquid)
        XCTAssertEqual(resolved.shape, .rounded)
        XCTAssertEqual(resolved.finish, .flat)
        XCTAssertEqual(resolved.keyAlpha, saved.keyAlpha)
        XCTAssertEqual(resolved.fontScale, saved.fontScale)
        XCTAssertEqual(resolved.gapScale, saved.gapScale)
        XCTAssertEqual(resolved.shapeScale, saved.shapeScale)
        XCTAssertFalse(resolved.usesNativeGlassKeys)
    }

    @MainActor
    func testCreamKeyChangesInkWhenItsSurfaceBecomesTranslucent() async {
        let palette = FoxLetterArtwork.palettes[1]
        let theme = FoxLetterArtwork.theme
        XCTAssertEqual(FoxLetterTheme.textColor(fur: palette.fur, preferred: palette.text, opacity: 1, theme: theme), palette.text)
        XCTAssertEqual(FoxLetterTheme.textColor(fur: palette.fur, preferred: palette.text, opacity: 0.5, theme: theme), UIColor.black)
        for alpha in [CGFloat(0.4), 0.45, 0.41, 0.451] {
            let ink = FoxLetterTheme.ink(fur: palette.fur, preferred: palette.text, opacity: alpha, theme: theme)
            XCTAssertNotNil(ink.outline)
            let title = FoxLetterTheme.title("ㄅ", ink: ink)
            XCTAssertEqual(title.attribute(.strokeColor, at: 0, effectiveRange: nil) as? UIColor, ink.outline)
            XCTAssertEqual(title.attribute(.strokeWidth, at: 0, effectiveRange: nil) as? Int, -3)
            if let image = UIImage(systemName: "shift") {
                let bordered = FoxLetterTheme.outlinedSymbol(image, ink: ink)
                XCTAssertEqual(bordered.renderingMode, .alwaysOriginal)
                XCTAssertGreaterThan(bordered.size.width, image.size.width)
            }
        }
        XCTAssertNil(FoxLetterTheme.ink(fur: palette.fur, preferred: palette.text, opacity: 1, theme: theme).outline)
    }

    @MainActor
    func testReturnSymbolAndTextTitleCanReuseTheSameKey() async {
        let key = KeyButton(spec: KeySpec(face: .symbol("return"), action: .returnKey, kind: .accent), style: style())
        key.frame = CGRect(x: 0, y: 0, width: 75, height: 50)
        key.layoutIfNeeded()
        let oldArtwork = artwork(in: key).first
        key.spec = KeySpec(face: .text("搜尋"), action: .returnKey, kind: .accent, fontSize: 16)
        key.layoutIfNeeded()
        let labels = key.subviews.flatMap { $0.subviews.compactMap { $0 as? UILabel } }
        XCTAssertTrue(labels.contains { !$0.isHidden && $0.text == "搜尋" })
        XCTAssertTrue(artwork(in: key).first === oldArtwork)
        XCTAssertEqual(key.spec.action, .returnKey)
    }

    @MainActor
    private func renderLayers(in artwork: FoxLetterArtworkView) -> [CALayer] {
        func visit(_ layer: CALayer) -> [CALayer] {
            let own = layer.contents != nil || (layer as? CAShapeLayer)?.path != nil ? [layer] : []
            return own + (layer.sublayers ?? []).flatMap(visit)
        }
        return visit(artwork.layer)
    }

    @MainActor
    func testRepeatedPressesReuseLayersAndPathsWithoutChangingHitArea() async throws {
        let animations = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animations) }
        var translucent = style()
        translucent.keyAlpha = 0.5
        let key = KeyButton(spec: KeySpec(face: .text("Q"), action: .text("Q")), style: translucent)
        key.illustratedIndex = 1 // 奶油色需要分別處理按壓前後的字色。
        key.frame = CGRect(x: 0, y: 0, width: 36, height: 50)
        key.layoutIfNeeded()
        let art = try XCTUnwrap(artwork(in: key).first)
        art.layoutIfNeeded()
        let shapes = renderLayers(in: art)
        XCTAssertFalse(shapes.isEmpty)
        let paths = shapes.map { ($0 as? CAShapeLayer)?.path }
        let images = shapes.map { $0.contents as AnyObject? }
        let hitArea = key.bounds
        let label = try XCTUnwrap(key.subviews.flatMap { $0.subviews.compactMap { $0 as? UILabel } }
            .first { $0.text == "Q" })
        let palette = FoxLetterArtwork.palettes[1]
        key.isPressed = true
        XCTAssertEqual(label.textColor, FoxLetterTheme.textColor(fur: palette.fur, preferred: palette.text,
            opacity: 0.41, theme: FoxLetterArtwork.theme))
        XCTAssertNotNil(label.attributedText?.attribute(.strokeColor, at: 0, effectiveRange: nil))
        key.isPressed = false
        XCTAssertEqual(label.textColor, FoxLetterTheme.textColor(fur: palette.fur, preferred: palette.text,
            opacity: 0.5, theme: FoxLetterArtwork.theme))
        XCTAssertNil(label.attributedText?.attribute(.strokeColor, at: 0, effectiveRange: nil))
        for _ in 0..<500 {
            key.isPressed = true
            key.visualOpacity = 0.45
            key.isPressed = false
            key.visualOpacity = 1
            key.layoutIfNeeded()
            art.layoutIfNeeded()
        }
        XCTAssertEqual(key.bounds, hitArea)
        XCTAssertEqual(key.spec.action, .text("Q"))
        XCTAssertFalse(art.isUserInteractionEnabled)
        let finalShapes = renderLayers(in: art)
        XCTAssertEqual(finalShapes.count, shapes.count)
        for i in 0..<min(finalShapes.count, shapes.count) {
            XCTAssertTrue(finalShapes[i] === shapes[i])
            XCTAssertTrue((finalShapes[i] as? CAShapeLayer)?.path === paths[i])
            XCTAssertTrue((finalShapes[i].contents as AnyObject?) === images[i])
        }
        XCTAssertEqual(artwork(in: key).count, 1)
    }

    @MainActor
    func testTextAndPaletteChangesReuseRenderingLayersAndSharedImages() async throws {
        let art = FoxLetterArtworkView(frame: CGRect(x: 0, y: 0, width: 36, height: 48))
        art.configure(index: 0, action: .text("q"), personalSpaceArt: false)
        art.layoutIfNeeded()
        let shapes = renderLayers(in: art)
        XCTAssertFalse(shapes.isEmpty)
        let paths = shapes.map { ($0 as? CAShapeLayer)?.path }
        let images = shapes.map { $0.contents as AnyObject? }
        // 橘色與橄欖色共用楓葉，變更毛色不應重算幾何。
        art.configure(index: 4, action: .text("Q"), personalSpaceArt: false)
        art.layoutIfNeeded()
        XCTAssertEqual(art.furColor, FoxLetterArtwork.palettes[4].fur)
        let finalShapes = renderLayers(in: art)
        XCTAssertEqual(finalShapes.count, shapes.count)
        for i in 0..<min(finalShapes.count, shapes.count) {
            XCTAssertTrue(finalShapes[i] === shapes[i])
            XCTAssertTrue((finalShapes[i] as? CAShapeLayer)?.path === paths[i])
            XCTAssertTrue((finalShapes[i].contents as AnyObject?) === images[i])
        }
    }

    @MainActor
    func testSharedPathCacheDistinguishesSizeAndComposition() async {
        let bounds = CGRect(x: 0, y: 0, width: 36, height: 48)
        let leaf = FoxLetterPathCache.paths(in: bounds, compact: false, accessory: "leaf")
        XCTAssertTrue(leaf === FoxLetterPathCache.paths(in: bounds, compact: false, accessory: "leaf"))
        XCTAssertFalse(leaf === FoxLetterPathCache.paths(in: bounds, compact: false, accessory: "letter"))
        let wide = FoxLetterPathCache.paths(in: CGRect(x: 0, y: 0, width: 160, height: 48), compact: false, accessory: "leaf")
        XCTAssertFalse(leaf === wide)
        let compact = FoxLetterPathCache.paths(in: bounds, compact: true, accessory: "leaf")
        XCTAssertFalse(leaf === compact)
        XCTAssertTrue(compact === FoxLetterPathCache.paths(in: bounds, compact: true, accessory: "letter"))
        XCTAssertTrue(leaf.values.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(compact.values.count, 2)
    }

    @MainActor
    func testCompactAndPersonalSpaceArtworkReuseLayersWithoutStaleDecorations() async {
        let art = FoxLetterArtworkView(frame: CGRect(x: 0, y: 0, width: 160, height: 48))
        art.configure(index: 0, action: .space, personalSpaceArt: false)
        art.layoutIfNeeded()
        let original = renderLayers(in: art)
        let originalSources = original.map { $0.contentsRect }
        XCTAssertEqual(original.count, 5)
        for _ in 0..<100 {
            art.configure(index: 0, action: .space, personalSpaceArt: true)
            art.layoutIfNeeded()
            XCTAssertEqual(renderLayers(in: art).count, original.count)
            art.configure(index: 0, action: .space, personalSpaceArt: true, compact: true)
            art.layoutIfNeeded()
            for (piece, source) in zip(renderLayers(in: art), originalSources) {
                XCTAssertLessThan(piece.contentsRect.height, source.height)
            }
            art.configure(index: 0, action: .space, personalSpaceArt: false, compact: false)
            art.layoutIfNeeded()
        }
        let final = renderLayers(in: art)
        XCTAssertEqual(final.count, original.count)
        for (a, b) in zip(original, final) { XCTAssertTrue(a === b) }
    }

    @MainActor
    func testSharedCacheDoesNotRetainRemovedKeyViews() async {
        let animations = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animations) }
        weak var removedKey: KeyButton?
        weak var removedArt: FoxLetterArtworkView?
        autoreleasepool {
            let key = KeyButton(spec: KeySpec(face: .text("Q"), action: .text("Q")), style: style())
            key.frame = CGRect(x: 0, y: 0, width: 36, height: 50)
            key.layoutIfNeeded()
            key.isPressed = true
            key.isPressed = false
            removedKey = key
            removedArt = artwork(in: key).first
            XCTAssertNotNil(removedArt)
        }
        XCTAssertNil(removedKey)
        XCTAssertNil(removedArt)
    }

    /// CI 記錄暖機後的主執行緒成本；模擬器數字不能代替真機流暢度。
    @MainActor
    func testPerformanceOfRepeatedPressFeedback() {
        let animations = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animations) }
        let grid = KeyboardGridView(style: style())
        grid.frame = CGRect(x: 0, y: 0, width: 390, height: 216)
        grid.setLayout(KeyLayouts.layout(context(.english, .letters, globe: true, ten: false)))
        grid.layoutIfNeeded()
        grid.keys.forEach { $0.layoutIfNeeded() }
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            for i in 0..<1_000 {
                let key = grid.keys[i % grid.keys.count]
                key.isPressed = true
                key.isPressed = false
                key.layoutIfNeeded()
            }
        }
    }
}
