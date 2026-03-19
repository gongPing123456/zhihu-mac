// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Halo",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "Halo",
            targets: ["Halo"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "Halo",
            path: "Sources/Halo",
            resources: [
                .process("Resources")
            ]
        ),
    ]
)
