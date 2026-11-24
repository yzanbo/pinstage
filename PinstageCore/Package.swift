// swift-tools-version: 6.2
import PackageDescription

// 画面に依存しない中心のロジック（並べ方の計算・ステージの選び方・座標の変換）をまとめたパッケージ
let package = Package(
    name: "PinstageCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PinstageCore", targets: ["PinstageCore"]),
    ],
    targets: [
        .target(name: "PinstageCore"),
        .testTarget(name: "PinstageCoreTests", dependencies: ["PinstageCore"]),
    ]
)
