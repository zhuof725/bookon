# 第 7 步 交付说明（STEP7_HANDOFF）

> 本文件为第 7 步（A/B/C 段）最终交付状态说明。CI 三 job 全绿 + build-ipa artifact 需推送
> GitHub 后由 Actions 运行产出（本地沙箱无法触发），其余交付物均已就绪并经本地校验。

## 一、交付内容总览

| 段落 | 内容 | 状态 |
|---|---|---|
| A | WebBook 流程层源码移植（搜索/详情/目录/正文/发现/调试） | ✅ 完成，typecheck 通过 |
| A | 流程层测试（154 @testable + 5 public）+ 端到端（7 真实规则） | ✅ 完成 |
| A | golden：HtmlFormatter 85 条 + wordCountFormat 35 条（手工 Java 移植） | ✅ 完成，本地已生成验证 |
| B | BookonDebugKit（@Observable：仓库/会话/日志/设置/清 Cookie 缓存） | ✅ 完成 |
| B | BookonDebugKitTests（82 用例） | ✅ 完成 |
| C | SwiftUI App「书源调试」+ project.yml + Info.plist | ✅ 完成 |
| C | build-ipa CI job + build_ipa.sh + test-ios-simulator 构建 App target | ✅ 完成（配置就绪） |
| D | README 差异表 / 不做清单 / 手机使用说明 / FUNCTION_MAPPING | ✅ 完成 |

## 二、本地校验结果（Linux 沙箱，可复现）

```
scripts/local_typecheck.sh          -> ✅ 类型检查通过（源码，含 shim）
scripts/local_typecheck_tests.sh    -> 流程层测试 typecheck 通过
scripts/local_typecheck_bookon.sh   -> BookonDebugKit 测试 typecheck 通过
python3 scripts/verify_functions.py -> 「Kotlin 有但 Swift 没实现的函数」清单：空
python3 scripts/verify_fields.py    -> 「Kotlin 有但 Swift 没实现的字段」清单：空
python3 scripts/verify_platform_apis.py     -> 未发现 String.Encoding 成员名误用（空）
scripts/verify_html_formatter_golden.sh     -> HtmlFormatter golden PASS=85 FAIL=0（跑真实产品代码）
scripts/golden (mvn package + run)  -> HtmlFormatter 85 条 + wordCountFormat 35 条
```

测试用例数（XCTest 方法计数）：

| target | 用例数 |
|---|---|
| LegadoWebBookTests（流程层，@testable） | 155 |
| LegadoWebBookPublicAPITests（流程层，非 @testable） | 5 |
| BookonDebugKitTests（B 段） | 82 |

> 说明：以上为**本地 typecheck + 逻辑推演 + golden 本地生成**验证。155/5/82 个测试的
> **运行时通过**、iOS==macOS 用例数相等、golden 逐条比对，需 macOS CI 执行确认。

## 二之二、CI 首轮暴露并已修复的缺陷（Linux 本地测不到的盲区）

| # | 缺陷 | 影响 | 修复 |
|---|---|---|---|
| 1 | `WebBookNetwork.decodeBody` 用了 `String.Encoding.gbk/.gb18030/.big5` | **编译失败**，test-macos 的 Build 步骤直接挂 | 这三个成员在 Foundation 里不存在（只在 CF `CFStringEncoding` 层面）。改走 `JsNetTextDecoder.decode(bytes:explicitCharset:contentTypeHeader:)`，与 AnalyzeUrl 共用同一套经 golden 验证的解码器；同时把「严格解码 + 静默退化成 UTF-8 乱码」纠正为 Kotlin 的「容错解码 → U+FFFD」 |
| 2 | `Book.isWebFile/isOnLineTxt/isAudio/isVideo` 用 `type == BookType.x` | **行为不一致**：组合类型书（如 文本+音频）在 Kotlin 判 true、Swift 判 false，副文歌词/弹幕分支被整段跳过 | Kotlin 是 `type and bookType > 0` 位测试。新增 `Book.isType(_:)`，四个属性全部改用它 |

> 缺陷 1 之所以本地全绿：那段映射被 `#if os(macOS) || os(iOS)` 包着，Linux 走 `#else`，
> **Darwin 分支根本没被编译过**。
> 防回归：新增 `scripts/verify_platform_apis.py`（静态扫描 `String.Encoding` 的不存在成员），
> 已接入 CI `test-macos` 的 `Verify platform-only API usage` 步骤。

其余首轮失败均为**测试期望写错**（产品代码与 Kotlin 逐行一致），已按真实语义修正：
`canReName` 是「规则非空白即允许改名」而非「字面值判定」；`init` 规则选中的元素会成为新解析根；
`<usehtml>` 须由规则直接选中该元素；`BookChapter` 是 struct（值传递），副作用留在内部副本；
`fetchSubContent` 成功时不打日志；`exportResultJSON` 用 `.prettyPrinted` 输出 `"records" : []`（冒号带空格）。

## 二之三、CI 第二轮暴露并已修复的缺陷（第三次 CI）

| # | 缺陷 | 影响面 | 修复 |
|---|---|---|---|
| 3 | `AnalyzeByJSoup.parse` 不认识 SwiftSoup `Elements` | **产品缺陷**：`setContent(getElement(...))` 后所有后续规则取空值（详情页 `init` 规则、目录/正文里以元素为根的解析全受影响） | Kotlin/JSoup 的 `Elements.toString()` = 各元素 `outerHtml()` 拼接；SwiftSoup 的 `Elements` **没有重写** `toString()`（默认打印 `"SwiftSoup.Elements"`），于是被当作 HTML 解析 → 结果为空。已在 `parse` 中显式处理 `Elements`：拼接 outerHtml 后重新解析，与 Kotlin 逐字对齐 |
| 4 | `HtmlFormatter` 的 `\s` 正则语义 | **43 条 golden 失败**：缩进被叠加成 4 个全角空格 | Java `\s` = `[ \t\n\x0B\f\r]`（6 个 ASCII 空白），不含 U+3000；ICU/NSRegularExpression 的 `\s` 含 U+3000。改用显式字符类 `[ \t\n\x0B\f\r]`（`javaASCIISpace`），`indent1Regex/indent2Regex/lastRegex` 三处 |
| 5 | `BookChapter.getAbsoluteURL()` 未实现 | 相对章节 url 不绝对化 | 核对 Kotlin 后确认：`BookChapterList` **本就不绝对化**（`BookChapterList.kt:239` 原样存），绝对化发生在取正文时（`WebBook.kt:400/448`）。测试期望写错，改为断言 `url == "/c/1"` + `baseUrl` 记录目录页 + `NetworkUtils.getAbsoluteURL(baseUrl, url)` 能解析出绝对地址 |
| 6 | 测试对 `Book.type` 默认值的假设有误 | 副文歌词/弹幕分支根本不可达（用例假绿/假红） | `Book.type` 默认是 `BookType.text`（8，Kotlin `Book.kt:74`），`addType(audio)` 得 `8\|32=40`，`isOnLineTxt` 仍为 true，于是命中 Kotlin `BookContent.kt:132` 的 `if (book.isOnLineTxt) { add(raw); return }` **早返回分支**。要覆盖音频/弹幕分支必须先 `removeAllBookType()` 构造纯 audio/video 书 |
| 7 | XcodeGen 默认工程格式 `objectVersion = 77` 与 Xcode 15.4 不兼容 | `test-ios-simulator` 与 `build-ipa` **整段失败**（`Unable to read project`） | XcodeGen 2.44+ 默认 `projectFormat = xcode16_0`（objectVersion 77），而 macos-14 runner 的 Xcode 15.4 读不了（77 需 Xcode 16.0+）。在 `project.yml` 的 `options` 显式设 `projectFormat: xcode15_3` → objectVersion 降为 **63**（需 Xcode 15.3+，15.4 可读）；并新增 `scripts/verify_xcodeproj_format.sh` 在 `xcodegen generate` 后、`xcodebuild` 前**显式校验** objectVersion 与当前 Xcode 的兼容性（按 CocoaPods/Xcodeproj 权威映射把 objectVersion 映射到「所需最低 Xcode」，再与当前 Xcode 做 major/minor 比较），失败时给出可执行的修复提示 |
| 8 | `xcodegen generate` 生成的 `.xcodeproj` 覆盖了 SwiftPM 包的自动 scheme | `test-ios-simulator` 失败：`Scheme LegadoBookSource is not currently configured for the test action`（退出码 66） | 第 7 步 C 段把「构建 App target（含 `xcodegen generate`）」与「跑 iOS 测试」放在了**同一个 job**、且生成在前。一旦仓库根目录出现 `BookonDebug.xcodeproj`，`xcodebuild` 就解析该工程，其中 `LegadoBookSource` 是 library scheme、**无 test action**，而 `ios_sim_test.sh` 依赖 SwiftPM 包自动 scheme `LegadoBookSource`（带 test action）。修复：**把测试步骤排到 `xcodegen generate` 之前**，并在测试前 `rm -rf BookonDebug.xcodeproj` 兜底；`ios_sim_test.sh` 增加「检测到 `.xcodeproj` 即报错」的自检，避免此约束被无意破坏 |

> 缺陷 3 之所以本地全绿：该分支只在 `.elements([单元素])` 作为 content 时触发，
> 既有测试路径未覆盖「`getElement` 取单元素再 `setContent`」这一组合，Linux 本地 typecheck 也只看类型不看值。
> 防回归：新增 `scripts/verify_html_formatter_golden.sh`（用**真实 `HtmlFormatter.swift`** + 最小 stub
> 跑 85 条 golden，`PASS=85 FAIL=0`），已在本地作为断言固化。

**其余第二轮失败均为测试期望写错**（产品代码与 Kotlin 一致），逐条核对 Kotlin 原文后修正：
`searchBookAwait` 空结果**不抛异常**（"未搜索到 xxx 书籍" 出自按书名找书的 BookHelp/Book.kt）；
`LiveWebBookNetwork` 对 404 **不抛错**（只在网络层异常时抛），转成空 body 响应后返回空列表；
`replaceRegex` 替换后为空会触发 Kotlin `BookContent.kt:204` 的 `ContentEmptyException("内容为空")`（**正确**行为）；
`getContentAwait` 的卷短路条件是 `isVolume && url.startsWith(title)`，测试需构造以标题开头的 url；
端到端用例的 Mock 键必须是**原始** key（Kotlin `{{key}}` 替换后不做百分号编码）；
`exportResultJSON` 的 `.prettyPrinted` 会把空数组展开成多行 `[\n\n  ]`，**不存在** `[]` 字面量，改为解析 JSON 后语义断言。

> 以上缺陷 3/4/5 均用「编译真实产品代码 + 最小 stub/驱动」的独立程序**实测**复现与验证，
> 而非阅读代码推测：缺陷 3 打印出 `String(describing: Elements) == "SwiftSoup.Elements"`；
> 缺陷 5 打印出 `url: [/c/1] baseUrl: [http://synthetic.test/toc/1]`；
> 缺陷 6 打印出 `book.type = 40 isAudio=true isOnLineTxt=true`（未清类型位）与
> `book.type = 32 isAudio=true isOnLineTxt=false`（清位后，歌词分支命中）。

## 三、CI 三 job + build-ipa（需推送 GitHub 触发）

`.github/workflows/test.yml` 现有 4 个 job：

1. **golden**（ubuntu-latest）：Maven 构建 golden 生成器 → 生成全部 golden JSON → upload-artifact。
2. **test-macos**（macos-14，needs golden）：`swift test` + 提取测试总数 → upload-artifact。
3. **test-ios-simulator**（macos-14，needs golden+test-macos）：`xcodebuild test`（iOS 17 模拟器）
   + **构建 App target** + iOS==macOS 用例数核对。
4. **build-ipa**（macos-14，needs golden+test-macos）：`xcodegen generate` → `xcodebuild archive`
   （Release、无签名、注入 `GIT_COMMIT`/`CI_RUN_ID`）→ 校验 `MinimumOSVersion == 17.0` →
   `Payload/BookonDebug.app` zip 成 `BookonDebug.ipa` → upload-artifact `bookon-debug-ipa`。

**验收需在 GitHub 上**：
- 推送本仓库到远端（`git push`），观察 4 个 job 全绿。
- 下载 `bookon-debug-ipa` artifact 与 golden artifact。
- 把真实日志留存到 `ci_logs/step7_final_*.log`（golden / macOS swift test / iOS xcodebuild test）。

## 四、关键文件清单（本次新增/修改）

**源码**
- `Sources/LegadoBookSource/WebBook/`（9 个文件：WebBook/BookList/BookInfo/BookChapterList/BookContent/Debug/WebBookSupport/WebBookNetwork/WebBookOptions）
- `Sources/LegadoBookSource/RuleEngine/DebugLogger.swift`、`HtmlFormatter.swift`、`StringUtils.swift`
- `Sources/LegadoBookSource/Network/CacheManager.swift`（新增 `clearAll()`）

**B 段**
- `Sources/BookonDebugKit/`（5 个文件：BookSourceRepository/DebugSession/DebugLogStore/DebugSettings/DebugEnvironment）

**C 段**
- `App/`（5 个 SwiftUI 文件 + Info.plist）
- `project.yml`（`options.projectFormat: xcode15_3`，固定工程格式以兼容 Xcode 15.4 runner）
- `scripts/build_ipa.sh`

**测试**
- `Tests/LegadoWebBookTests/`（16 个文件，155 用例）
- `Tests/LegadoWebBookPublicAPITests/`（1 个文件，5 用例）
- `Tests/BookonDebugKitTests/`（8 个文件，82 用例）+ `Resources/{配置文件_14个,malformed_sources}.json`
- `Tests/LegadoWebBookTests/Resources/{配置文件_14个,synthetic_flow_pages}.json`

**验收/文档/CI**
- `scripts/verify_functions.py`（扩展 webBook/*.kt + Debug.kt）
- `scripts/verify_platform_apis.py`（String.Encoding 成员名误用门禁）
- `scripts/verify_html_formatter_golden.sh`（真实 HtmlFormatter.swift 跑 85 条 golden）
- `scripts/verify_xcodeproj_format.sh`（工程 objectVersion 与 Xcode 版本兼容性门禁）
- `scripts/local_typecheck.sh`、`scripts/local_typecheck_tests.sh`、`scripts/local_typecheck_bookon.sh`
- `scripts/golden/src/main/java/golden/{HtmlFormatterGen,WordCountGen}.java` + `Main.java`
- `scripts/golden/cases/{html_formatter_cases,word_count_cases}.json`
- `reference/kotlin/analyzeRule/webBook/*.kt`、`reference/kotlin/analyzeRule/Debug.kt`
- `.github/workflows/test.yml`、`Package.swift`、`README.md`、`FUNCTION_MAPPING.md`、`.gitignore`

## 五、未完成 / 需人工

- CI 四 job 实际运行与日志留存（需 GitHub Actions）。
- `build-ipa` 运行链接 / artifact 确认（需 GitHub）。
- App 的 SwiftUI 界面运行时验证（Linux 无法编译 SwiftUI，需 macOS/iOS）。
- 书源编辑/分享等 UI 细节（README「不做」清单已声明）。
