// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "AsyncVideoView",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "AsyncVideoView",
            targets: ["AsyncVideoView"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/psredzinski/IteoLogger.git",
            from: "1.7.0"
        )
    ],
    targets: [
        .target(
            name: "AsyncVideoView",
            dependencies: [
                .product(name: "IteoLogger", package: "IteoLogger")
            ],
            path: "AsyncVideoView/Sources/AsyncVideoView"
        ),
    ]
)
