// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhispererApp",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "WhispererApp",
            dependencies: ["Yams"],
            path: "Sources/WhispererApp",
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
