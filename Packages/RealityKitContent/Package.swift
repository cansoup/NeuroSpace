// swift-tools-version:6.2

import PackageDescription

let package = Package(
    name: "RealityKitContent",
    platforms: [
        .visionOS(.v26),
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26)
    ],
    products: [
        .library(
            name: "RealityKitContent",
            targets: ["RealityKitContent"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "RealityKitContent",
            dependencies: [],
            resources: [
                .process("RealityKitContent.rkassets"),
                .process("lefthandpoint.usdz")
            ],
            swiftSettings: [
                .enableUpcomingFeature("MemberImportVisibility")
            ]
        ),
    ]
)
