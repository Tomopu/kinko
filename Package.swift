// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Kinko",
  platforms: [.macOS(.v14)],
  dependencies: [
    // Argon2id（パスワードから鍵を作る）のためだけに libsodium を使う。
    // Swift ラッパー（Sodium）は非 ASCII のパスワードでクラッシュするので、C API（Clibsodium）を直接呼ぶ
    .package(url: "https://github.com/jedisct1/swift-sodium.git", exact: "0.9.1"),
    // Markdown の解析（cmark-gfm）。どこが見出しや太字かを知るためだけに使う
    .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0"),
  ],
  targets: [
    .target(
      name: "KinkoCore",
      dependencies: [
        .product(name: "Clibsodium", package: "swift-sodium"),
        .product(name: "Markdown", package: "swift-markdown"),
      ]
    ),
    .executableTarget(name: "Kinko", dependencies: ["KinkoCore"]),
    .testTarget(name: "KinkoCoreTests", dependencies: ["KinkoCore"]),
  ]
)
