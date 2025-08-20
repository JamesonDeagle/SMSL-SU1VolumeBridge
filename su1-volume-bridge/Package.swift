// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "su1-volume-bridge",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "su1-volume-bridge", targets: ["SU1VolumeBridge"])
    ],
    targets: [
        .executableTarget(
            name: "SU1VolumeBridge",
            path: "Sources",
            swiftSettings: [
                .unsafeFlags(["-enable-bare-slash-regex"]) // на всякий случай
            ]
        )
    ]
)


