// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kado",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Kado", targets: ["Kado"])],
    targets: [.executableTarget(name: "Kado", swiftSettings: [.swiftLanguageMode(.v5)])]
)
