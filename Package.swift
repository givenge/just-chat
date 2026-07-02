// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "JustChat",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "JustChat", targets: ["JustChat"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown", from: "0.5.0")
    ],
    targets: [
        .executableTarget(
            name: "JustChat",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "JustChatTests",
            dependencies: ["JustChat"]
        )
    ]
)
