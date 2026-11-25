// swift-tools-version:5.7
import PackageDescription

// 鍵盤的核心邏輯（注音組字、選字、剪貼簿、表符），不含畫面，可以在 Mac 上直接跑測試
let package = Package(
    name: "KeyboardCore",
    platforms: [.macOS(.v12), .iOS(.v15)],
    products: [.library(name: "KeyboardCore", targets: ["KeyboardCore"])],
    targets: [
        .target(name: "KeyboardCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "KeyboardCoreTests", dependencies: ["KeyboardCore"]),
    ]
)
