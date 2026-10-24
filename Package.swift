// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Dictate",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DictateCore"),
        .executableTarget(name: "Dictate", dependencies: ["DictateCore"]),
        .testTarget(name: "DictateCoreTests", dependencies: ["DictateCore"]),
    ]
)
