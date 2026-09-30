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
                .copy("Resources/test_bookSources.json"),
                .copy("Resources/muli_real_source.json")
            ]
        ),
        // 纯 public 接口测试：普通 import（非 @testable），验证对外 API 可见性完整。
        .testTarget(
            name: "LegadoBookSourcePublicAPITests",
            dependencies: ["LegadoBookSource"],
            path: "Tests/LegadoBookSourcePublicAPITests",
            resources: [
                .copy("Resources/test_bookSources.json"),
                .copy("Resources/muli_real_source.json")
            ]
        )
    ]
)
