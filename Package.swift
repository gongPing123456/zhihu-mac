// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ZhihuMoyuMac",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "ZhihuMoyuMac",
            targets: ["ZhihuMoyuMac"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "ZhihuMoyuMac",
            path: "Sources/ZhihuMoyuMac"
        ),
    ]
)
