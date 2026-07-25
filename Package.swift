// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LangSwitcher",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "LangSwitcher",
            path: "Sources/LangSwitcher"
        )
    ]
)
