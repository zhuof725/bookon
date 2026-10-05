// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LegadoBookSource",
    // 第 7 步版本约定：全仓库统一 iOS 17.0 / macOS 14。
    // 升级只放宽下限，不改任何既有行为（前六步测试数量与结果保持不变）。
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "LegadoBookSource",
            targets: ["LegadoBookSource"]
        ),
        // 第 7 步 B 段：与界面无关的调试内核（App target 依赖它）。
        .library(
            name: "BookonDebugKit",
            targets: ["BookonDebugKit"]
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
            path: "Sources/LegadoBookSource",
            resources: [
                // Step 5: quick-chinese-transfer 0.2.17 原始简繁词典（见 Resources/Chinese/PROVENANCE.md）。
                .process("Resources")
            ]
        ),
        // 第 7 步 B 段：调试内核（书源仓库 / 调试会话 / 日志持久化与导出 / 设置）。
        // 用 Observation 框架的 @Observable（不用 ObservableObject / @Published）。
        // 全部非界面逻辑放这里，使测试在 macOS 14 与 iOS 模拟器上数量一致。
        .target(
            name: "BookonDebugKit",
            dependencies: ["LegadoBookSource"],
            path: "Sources/BookonDebugKit"
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
                .copy("Resources/taiwan_real_source.json"),
                // 第 5 步收尾：端到端测试的期望值改为从 golden 读（真实 jsoup 1.16.2 +
                // 真实 Rhino 1.8.1 / Java MessageDigest 跑出来的结果），不再写死或用 Swift 自算。
                .copy("Resources/golden")
            ]
        ),
        // 第 6 步 6A：AnalyzeUrl / 网络层的 @testable 单元测试。
        .testTarget(
            name: "LegadoNetworkTests",
            dependencies: ["LegadoBookSource", "SwiftSoup"],
            path: "Tests/LegadoNetworkTests",
            resources: [
                .copy("Resources/golden"),
                // 6B 可选任务：live-smoke 用仓库内真实书源配置做一次真实网络搜索冒烟。
                .copy("Resources/配置文件_7个.json")
            ]
        ),
        // 第 6 步 6A：网络层的纯 public 接口测试（普通 import，非 @testable）。
        .testTarget(
            name: "LegadoNetworkPublicAPITests",
            dependencies: ["LegadoBookSource"],
            path: "Tests/LegadoNetworkPublicAPITests"
        ),
        // 第 4 步 B：AnalyzeRule 的纯 public 接口测试（普通 import，非 @testable）。
        .testTarget(
            name: "LegadoAnalyzeRulePublicAPITests",
            dependencies: ["LegadoBookSource", "SwiftSoup"],
            path: "Tests/LegadoAnalyzeRulePublicAPITests"
        ),
        // 第 7 步 A 段：WebBook 流程层（搜索/详情/目录/正文/发现）的 @testable 单元测试。
        // 用本地 NWListener 合成服务器 + 手工构造的合成页面逐分支测试（≥150 用例）。
        .testTarget(
            name: "LegadoWebBookTests",
            dependencies: ["LegadoBookSource", "SwiftSoup"],
            path: "Tests/LegadoWebBookTests",
            resources: [
                .copy("Resources/配置文件_14个.json"),
                .copy("Resources/synthetic_flow_pages.json"),
                // 第 7 步 A：HtmlFormatter/wordCountFormat golden（真实 Java 移植产出的期望值）。
                .copy("Resources/golden")
            ]
        ),
        // 第 7 步 A 段：流程层的纯 public 接口测试（普通 import，非 @testable）。
        .testTarget(
            name: "LegadoWebBookPublicAPITests",
            dependencies: ["LegadoBookSource"],
            path: "Tests/LegadoWebBookPublicAPITests"
        ),
        // 第 7 步 B 段：BookonDebugKit 的 @testable 单元测试（≥80 用例，macOS/iOS 数量一致）。
        .testTarget(
            name: "BookonDebugKitTests",
            dependencies: ["BookonDebugKit", "LegadoBookSource"],
            path: "Tests/BookonDebugKitTests",
            resources: [
                .copy("Resources/配置文件_14个.json"),
                .copy("Resources/malformed_sources.json")
            ]
        )
    ]
)
