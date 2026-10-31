// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SyncLightPro",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SyncLightPro", targets: ["SyncLightPro"])
    ],
    targets: [
        .executableTarget(
            name: "SyncLightPro",
            path: "Sources/SyncLightPro"
        )
    ]
)
