// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipBase",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ClipBase", targets: ["ClipBaseApp"])
    ],
    targets: [
        .executableTarget(
            name: "ClipBaseApp",
            path: "Sources/ClipBaseApp",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "ClipBaseAppTests",
            dependencies: ["ClipBaseApp"],
            path: "Tests/ClipBaseAppTests"
        )
    ]
)
