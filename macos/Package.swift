// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DoesGPTCheat",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "DoesGPTCheat",
            path: "Sources/DoesGPTCheat",
            swiftSettings: [.unsafeFlags(["-Osize"])]
        )
    ]
)
