// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Voice2Input",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Voice2Input", targets: ["Voice2Input"])
    ],
    targets: [
        .executableTarget(
            name: "Voice2Input",
            path: "Sources/Voice2Input"
        )
    ]
)
