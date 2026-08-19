// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "MacFan",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MacFanCore", targets: ["MacFanCore"]),
        .executable(name: "MacFan", targets: ["MacFanApp"]),
        .executable(name: "macfan-helper", targets: ["MacFanHelper"]),
    ],
    targets: [
        .target(
            name: "CSMC",
            linkerSettings: [
                .linkedFramework("CoreFoundation"),
                .linkedFramework("IOKit"),
            ]
        ),
        .target(name: "MacFanCore", dependencies: ["CSMC"]),
        .executableTarget(
            name: "MacFanApp",
            dependencies: ["MacFanCore"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "MacFanHelper",
            dependencies: ["MacFanCore"],
            linkerSettings: [.linkedFramework("Security")]
        ),
        .testTarget(name: "MacFanCoreTests", dependencies: ["MacFanCore"]),
    ]
)
