# 尚书（BookOn）

兼容 Legado 书源格式的 iOS 阅读器（SwiftUI），参考 Luoyacheng/legado-E。

- Bundle ID: `io.github.xianghuo.book`
- 语言：App 走 Swift 6 语言模式；`Tools/ReaderInteractionTest` 的 UI 测试工程走 5.0
  （UI 测试夹具大量直接操作 UIKit，Swift 6 严格并发会淹没真正的错误）
- 部署目标：iOS 17.0，构建需 iOS 26 SDK（原生 Liquid Glass 无兜底）
- 工程由 XcodeGen 从 `project.yml` 生成，`*.xcodeproj` 不进版本库

## 目录

| 路径 | 内容 |
| --- | --- |
| `Sources/App` | 界面层：书架、阅读器、设置、听书、漫画 |
| `Sources/Engine` | 书源引擎：规则解析、JS 桥、网络、缓存 |
| `Sources/Models` / `Store` / `Shared` | 数据模型、全局状态、App 与扩展共用代码 |
| `Sources/Widget` | Live Activity 扩展（`@main` 与主 App 分开） |
| `Tools/` | 离线回归。`SourceTest` 等由 CI 临时生成 `Package.swift` 后 `swiftc` 编译，仓库里不放包描述文件；`ReaderInteractionTest` 是 XCUITest 工程 |
| `data/sources/` | 需要留档的书源快照，见该目录的 README |
| `docs/` | 34 篇设计文档，改功能前先看对应那篇 |

## 构建

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project BookOn.xcodeproj -scheme BookOn -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
```

## 发布

GitHub Actions（`.github/workflows/build.yml`）：

- push 到 `main` → 构建未签名 IPA，产物在 Actions 的 artifact 里
- 推送 `v*` tag → 同一次构建顺手创建 Release 并附上 IPA，可长期留档
- 另有 4 个 workflow：`source-test.yml` 每次 push 都跑书源解析回归；
  `reader-interaction.yml` 只在 `Sources/App` 阅读器相关文件、`ReadSettings`、
  `Tools/ReaderInteractionTest` 变动时触发；`user-source-test.yml` /
  `reader-diagnostics.yml` 只在需要时手动触发

**注意：`build.yml` 只编译 App target，不编译测试 harness。**
测试代码坏掉时它照样绿——改过 `@MainActor` 隔离或测试夹具后，
务必单独确认 `reader-interaction` 的结果。

安装：下载 `BookOn-unsigned.ipa` 后用自签工具（TrollStore、AltStore、Sideloadly 等）签名安装。

版本号写在 `project.yml` 的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`；
提交信息沿用中文 + `（build N）` 后缀。
