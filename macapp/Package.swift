// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Clip",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Clip", targets: ["Clip"])
    ],
    targets: [
        .executableTarget(
            name: "Clip",
            path: "Sources/ClipBaseApp",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
