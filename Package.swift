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
    dependencies: [
        // CSS/DOM 解析后端（对应 Kotlin 的 Jsoup）。选型理由见 README。
        .package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.9.6")
    ],
    targets: [
        .target(
            name: "LegadoBookSource",
            dependencies: ["SwiftSoup"],
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
        ),
        // 第 2 步：规则引擎的 @testable 单元测试。
        .testTarget(
            name: "LegadoRuleEngineTests",
            dependencies: ["LegadoBookSource"],
            path: "Tests/LegadoRuleEngineTests",
            resources: [
                .copy("Resources/synthetic_lieying_like.json"),
                .copy("Resources/real/muli_real_source.json"),
                .copy("Resources/real/qimo_real_source.json")
            ]
        ),
        // 第 2 步：规则引擎的纯 public 接口测试（普通 import，非 @testable）。
        .testTarget(
            name: "LegadoRuleEnginePublicAPITests",
            dependencies: ["LegadoBookSource"],
            path: "Tests/LegadoRuleEnginePublicAPITests"
        ),
        // 第 3 步：HTML 规则引擎（JSoup/XPath）的 @testable 单元测试。
        .testTarget(
            name: "LegadoHTMLEngineTests",
            dependencies: ["LegadoBookSource", "SwiftSoup"],
            path: "Tests/LegadoHTMLEngineTests",
            resources: [
                .copy("Resources/real/xiaoshuo2016_rules.json"),
                .copy("Resources/real/caimoge_rules.json"),
                // CI 的 golden job 用真实 jsoup 1.16.2 + JsoupXpath 2.5.3 生成的对照数据，
                // 在 test-macos / test-ios-simulator 跑 swift build 之前下载到这个目录。
                .copy("Resources/golden")
            ]
        ),
        // 第 3 步：HTML 规则引擎的纯 public 接口测试（普通 import，非 @testable）。
        .testTarget(
            name: "LegadoHTMLEnginePublicAPITests",
            dependencies: ["LegadoBookSource", "SwiftSoup"],
            path: "Tests/LegadoHTMLEnginePublicAPITests"
        ),
        // 第 4 步 B：AnalyzeRule 总调度 + JS 引擎的 @testable 单元测试。
        .testTarget(
            name: "LegadoAnalyzeRuleTests",
            dependencies: ["LegadoBookSource", "SwiftSoup"],
            path: "Tests/LegadoAnalyzeRuleTests",
            resources: [
                .copy("Resources/配置文件_7个.json"),
                .copy("Resources/taiwan_real_source.json")
            ]
        ),
        // 第 4 步 B：AnalyzeRule 的纯 public 接口测试（普通 import，非 @testable）。
        .testTarget(
            name: "LegadoAnalyzeRulePublicAPITests",
            dependencies: ["LegadoBookSource", "SwiftSoup"],
            path: "Tests/LegadoAnalyzeRulePublicAPITests"
        )
    ]
)
