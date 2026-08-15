// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cocker",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Cocker",
            path: "Sources/Cocker",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CockerTests",
            dependencies: ["Cocker"],
            path: "Tests/CockerTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
