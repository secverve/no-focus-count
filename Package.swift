// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "NoFocusCount",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "NoFocusCount", targets: ["NoFocusCount"])
    ],
    targets: [
        .executableTarget(
            name: "NoFocusCount",
            path: "Sources/NoFocusCount"
        ),
        .testTarget(
            name: "NoFocusCountTests",
            dependencies: ["NoFocusCount"],
            path: "Tests/NoFocusCountTests"
        )
    ]
)
