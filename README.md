# 尚书（BookOn）

兼容 Legado 书源格式的 iOS 阅读器（SwiftUI），参考 Luoyacheng/legado-E。

- Bundle ID: `io.github.xianghuo.book`
- 语言：Swift 6（语言模式 6.0，App 与测试工程、SwiftPM 回归包统一）
- 部署目标：iOS 17.0，构建需 iOS 26 SDK（原生 Liquid Glass 无兜底）
- 工程由 XcodeGen 从 `project.yml` 生成，`*.xcodeproj` 不进版本库

## 目录

| 路径 | 内容 |
| --- | --- |
| `Sources/App` | 界面层：书架、阅读器、设置、听书、漫画 |
| `Sources/Engine` | 书源引擎：规则解析、JS 桥、网络、缓存 |
| `Sources/Models` / `Store` / `Shared` | 数据模型、全局状态、App 与扩展共用代码 |
| `Sources/Widget` | Live Activity 扩展（`@main` 与主 App 分开） |
| `Tools/` | 6 个 SwiftPM 回归测试包（`SourceTest` 等，macOS 上跑） |
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
- 其余 5 个 workflow 只在相关文件变动时触发，跑书源 / 阅读交互回归

安装：下载 `BookOn-unsigned.ipa` 后用自签工具（TrollStore、AltStore、Sideloadly 等）签名安装。

版本号写在 `project.yml` 的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`；
提交信息沿用中文 + `（build N）` 后缀。
