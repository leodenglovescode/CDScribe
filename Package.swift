// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CDScribe",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CDScribeCore", targets: ["CDScribeCore"]),
        .executable(name: "CDScribe", targets: ["CDScribeApp"])
    ],
    targets: [
        .target(name: "NativeDisc", publicHeadersPath: "include", linkerSettings: [.linkedFramework("DiscRecording")]),
        .target(name: "CDScribeCore", dependencies: ["NativeDisc"]),
        .executableTarget(name: "CDScribeApp", dependencies: ["CDScribeCore"]),
        .testTarget(name: "CDScribeCoreTests", dependencies: ["CDScribeCore", "NativeDisc"])
    ]
)
