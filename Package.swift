// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MacCap",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacCap", targets: ["MacCap"])
    ],
    targets: [
        .target(
            name: "MacCapCore"
        ),
        .executableTarget(
            name: "MacCap",
            dependencies: ["MacCapCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ImageIO"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        ),
        .testTarget(
            name: "MacCapCoreTests",
            dependencies: ["MacCapCore"]
        )
    ]
)
