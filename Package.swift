// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LegadoBookSource",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "LegadoBookSource",
            targets: ["LegadoBookSource"]
        )
    ],
    targets: [
        .target(
            name: "LegadoBookSource",
            path: "Sources/LegadoBookSource"
        ),
        .testTarget(
            name: "LegadoBookSourceTests",
            dependencies: ["LegadoBookSource"],
            path: "Tests/LegadoBookSourceTests",
            resources: [
                .copy("Resources/test_bookSources.json")
            ]
        )
    ]
)
