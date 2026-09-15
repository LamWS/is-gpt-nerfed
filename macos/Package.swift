// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "IsGPTNerfed",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "IsGPTNerfed",
            path: "Sources/IsGPTNerfed",
            swiftSettings: [.unsafeFlags(["-Osize"])]
        )
    ]
)
