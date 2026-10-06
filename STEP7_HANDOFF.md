# 第 7 步 交付说明（STEP7_HANDOFF）

> 本文件为第 7 步（A/B/C 段）最终交付状态说明。**CI 四 job 已在 GitHub 全绿**
> （run [`37310649613`](https://github.com/zhuof725/bookon/actions/runs/37310649613)），
> 真实日志留存于 `ci_logs/step7_final_*.log`，`bookon-debug-ipa` artifact 已产出。

## 一、交付内容总览

| 段落 | 内容 | 状态 |
|---|---|---|
| A | WebBook 流程层源码移植（搜索/详情/目录/正文/发现/调试） | ✅ 完成，typecheck 通过 |
| A | 流程层测试（155 @testable + 5 public）+ 端到端（7 真实规则） | ✅ CI 809 tests / 0 failures |
| A | golden：HtmlFormatter 85 条 + wordCountFormat 35 条（手工 Java 移植） | ✅ 完成，本地已生成验证 |
| B | BookonDebugKit（@Observable：仓库/会话/日志/设置/清 Cookie 缓存） | ✅ 完成 |
| B | BookonDebugKitTests（82 用例） | ✅ 完成 |
| C | SwiftUI App「书源调试」+ project.yml + Info.plist | ✅ 完成（C 段返工后界面按第四节最终状态） |
| C | build-ipa CI job + build_ipa.sh + test-ios-simulator 构建 App target | ✅ CI 通过，`MinimumOSVersion=17.0`，artifact 已上传 |
| C | **返工**：App 界面补齐 / Cookie 缓存持久化 / 端到端 7 书源精确断言 / StringUtils 强解包 / 文档 | ✅ 完成（详见第四节） |
| D | README 差异表 / 不做清单 / 手机使用说明 / FUNCTION_MAPPING | ✅ 完成 |

## 二、本地校验结果（Linux 沙箱，可复现）

```
scripts/local_typecheck.sh          -> ✅ 类型检查通过（源码，含 shim）
scripts/local_typecheck_tests.sh    -> 流程层测试 typecheck 通过
scripts/local_typecheck_bookon.sh   -> BookonDebugKit 测试 typecheck 通过（9 文件 / 145 用例）
python3 scripts/verify_functions.py -> 「Kotlin 有但 Swift 没实现的函数」清单：空
python3 scripts/verify_fields.py    -> 「Kotlin 有但 Swift 没实现的字段」清单：空
python3 scripts/verify_platform_apis.py     -> 未发现 String.Encoding 成员名误用（空）
scripts/verify_html_formatter_golden.sh     -> HtmlFormatter golden PASS=85 FAIL=0（跑真实产品代码）
scripts/verify_debugkit_logic.sh            -> DebugKit 逻辑 PASS=28 FAIL=0（跑真实产品代码）
scripts/verify/e2e_assert.swift（自建探针）  -> 端到端精确断言 PASS=63 FAIL=0（跑真实产品代码）
scripts/golden (mvn package + run)  -> HtmlFormatter 85 条 + wordCountFormat 35 条
```

测试用例数（XCTest 方法计数）：

| target | 用例数 |
|---|---|
| LegadoWebBookTests（流程层，@testable） | 155 |
| LegadoWebBookPublicAPITests（流程层，非 @testable） | 5 |
| BookonDebugKitTests（B 段） | 82 |

> 说明：上表为**本地 typecheck + 逻辑推演 + golden 本地生成**验证；155/5/82 个测试的
> **运行时通过**、golden 逐条比对、iOS==macOS 用例数相等，已由 macOS CI 全部确认（见第三节）。

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

## 二之三、CI 逐轮暴露并已修复的缺陷（第 3–11 轮 CI 收敛）

| # | 缺陷 | 影响面 | 修复 |
|---|---|---|---|
| 3 | `AnalyzeByJSoup.parse` 不认识 SwiftSoup `Elements` | **产品缺陷**：`setContent(getElement(...))` 后所有后续规则取空值（详情页 `init` 规则、目录/正文里以元素为根的解析全受影响） | Kotlin/JSoup 的 `Elements.toString()` = 各元素 `outerHtml()` 拼接；SwiftSoup 的 `Elements` **没有重写** `toString()`（默认打印 `"SwiftSoup.Elements"`），于是被当作 HTML 解析 → 结果为空。已在 `parse` 中显式处理 `Elements`：拼接 outerHtml 后重新解析，与 Kotlin 逐字对齐 |
| 4 | `HtmlFormatter` 的 `\s` 正则语义 | **43 条 golden 失败**：缩进被叠加成 4 个全角空格 | Java `\s` = `[ \t\n\x0B\f\r]`（6 个 ASCII 空白），不含 U+3000；ICU/NSRegularExpression 的 `\s` 含 U+3000。改用显式字符类 `[ \t\n\x0B\f\r]`（`javaASCIISpace`），`indent1Regex/indent2Regex/lastRegex` 三处 |
| 5 | `BookChapter.getAbsoluteURL()` 未实现 | 相对章节 url 不绝对化 | 核对 Kotlin 后确认：`BookChapterList` **本就不绝对化**（`BookChapterList.kt:239` 原样存），绝对化发生在取正文时（`WebBook.kt:400/448`）。测试期望写错，改为断言 `url == "/c/1"` + `baseUrl` 记录目录页 + `NetworkUtils.getAbsoluteURL(baseUrl, url)` 能解析出绝对地址 |
| 6 | 测试对 `Book.type` 默认值的假设有误 | 副文歌词/弹幕分支根本不可达（用例假绿/假红） | `Book.type` 默认是 `BookType.text`（8，Kotlin `Book.kt:74`），`addType(audio)` 得 `8\|32=40`，`isOnLineTxt` 仍为 true，于是命中 Kotlin `BookContent.kt:132` 的 `if (book.isOnLineTxt) { add(raw); return }` **早返回分支**。要覆盖音频/弹幕分支必须先 `removeAllBookType()` 构造纯 audio/video 书 |
| 7 | XcodeGen 默认工程格式 `objectVersion = 77` 与 Xcode 15.4 不兼容 | `test-ios-simulator` 与 `build-ipa` **整段失败**（`Unable to read project`） | XcodeGen 2.44+ 默认 `projectFormat = xcode16_0`（objectVersion 77），而 macos-14 runner 的 Xcode 15.4 读不了（77 需 Xcode 16.0+）。在 `project.yml` 的 `options` 显式设 `projectFormat: xcode15_3` → objectVersion 降为 **63**（需 Xcode 15.3+，15.4 可读）；并新增 `scripts/verify_xcodeproj_format.sh` 在 `xcodegen generate` 后、`xcodebuild` 前**显式校验** objectVersion 与当前 Xcode 的兼容性（按 CocoaPods/Xcodeproj 权威映射把 objectVersion 映射到「所需最低 Xcode」，再与当前 Xcode 做 major/minor 比较），失败时给出可执行的修复提示 |
| 8 | 硬编码 scheme `LegadoBookSource` 在「多 product 包」下不带 test action | `test-ios-simulator` 失败：`Scheme LegadoBookSource is not currently configured for the test action`（退出码 66） | 第 2 步时本包只有 1 个 library product，Xcode 为 SwiftPM 包自动生成的唯一 scheme 就叫 `LegadoBookSource` 且**带 test action**（`commit 30c78f9` 据此写死）。第 7 步 B 段给 `Package.swift` 加了第二个 product `BookonDebugKit` 后，Xcode 的 scheme 生成策略改变：出现 `BookonDebugKit` / `LegadoBookSource` / **`LegadoBookSource-Package`** 三个 scheme，其中**带 test action 的聚合 scheme 是 `LegadoBookSource-Package`**，`LegadoBookSource` 退化为纯 library scheme。修复：`ios_sim_test.sh` **不再硬编码**，改为用 `xcodebuild -list -json` 优先探测 `<包名>-Package`、回退到 `<包名>`，并对找不到的情况明确报错；同时把「跑测试」步骤排到 `xcodegen generate` **之前**（避免 `.xcodeproj` 存在时 scheme 集合再变），测试前 `rm -rf BookonDebug.xcodeproj` 兜底 |
| 9 | `verify_xcodeproj_format.sh` 在 macOS 上 SIGABRT 且日志全丢 | `test-ios-simulator` 的「Build App target」失败，退出码 **134（SIGABRT）**：`xcodegen generate` 打印 "Created project at …"（退出码 0）后，本脚本**连一行输出都没有**就直接 abort | 脚本内两个高风险点：① `grep -m1 … \| grep -oE …` 管道（macOS BSD grep + pbxproj 的非 UTF-8 注释字节）；② 调用 `xcodebuild -version`（非交互/首次运行场景可能直接 abort）；且 stdout 满缓冲，进程 abort 时缓冲未 flush → 日志全丢。修复：重写为「**宁可退化为不检查，也绝不 abort 整个 CI 步骤**」——objectVersion 改用 **awk 单命令按行取**（无管道）+ `tr -cd '0-9'` 兜底；Xcode 版本改用 **`plutil` 读 `$DEVELOPER_DIR/Contents/version.plist` 的 `CFBundleShortVersionString`**（不再调用 xcodebuild），拿不到就 WARN + `exit 0`；`set -u` 但**不** `set -e`，每条探测都 `\|\| VAR=""`；全脚本 ASCII-only 输出 + 统一 `[verify_xcodeproj_format]` 前缀 |

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

## 三、CI 三 job + build-ipa —— ✅ 已在 GitHub 全绿

`.github/workflows/test.yml` 现有 4 个 job（+ 1 个 `live-smoke` 默认 skipped）：

| job | runner | 实测结果（run [`37310649613`](https://github.com/zhuof725/bookon/actions/runs/37310649613)，commit `7ad1589`） | 日志 |
|---|---|---|---|
| **golden** | ubuntu-latest | ✅ success —— **24 个用例文件 / 2391 条**（HtmlFormatter 85、wordCount 35、UrlOption 84、URL 编码 299、OkHttp 系列、jsoup 91、Rhino 74、Java MessageDigest 2、Rhino 数字入参 42 …） | `ci_logs/step7_final_golden.log` |
| **test-macos** | macos-14 | ✅ success —— **Executed 809 tests, 0 failures**（1 skipped） | `ci_logs/step7_final_macos.log` |
| **test-ios-simulator** | macos-14 | ✅ success —— scheme `LegadoBookSource-Package`，**809 tests / 0 failures**，且 `✅ iOS 总数与 macOS 总数一致（均为 809）`；App target 构建通过；`[verify_xcodeproj_format] Xcode=15.4 objectVersion=63 → OK` | `ci_logs/step7_final_ios.log` |
| **build-ipa** | macos-14 | ✅ success —— `MinimumOSVersion = 17.0 ✓`，产出 `build/BookonDebug.ipa`（1,810,407 B），artifact `bookon-debug-ipa`（1,806,528 B）已上传 | `ci_logs/step7_final_build_ipa.log` |
| live-smoke | ubuntu-latest | skipped（默认不跑真实网络） | — |

**artifact**（run 37310649613）：`golden-data`（227,811 B）、`macos-test-count`（160 B，内容 `809`）、`bookon-debug-ipa`（1,806,528 B）。

### 复现确认（后续两次推送同样全绿）

| run | commit | 结果 |
|---|---|---|
| [37310649613](https://github.com/zhuof725/bookon/actions/runs/37310649613) | `7ad1589` | ✅ 4 job 全绿（上表数据来源） |
| [37312666887](https://github.com/zhuof725/bookon/actions/runs/37312666887) | `489fbed` | ✅ 4 job 全绿（仅文档/日志变更） |
| [37313519896](https://github.com/zhuof725/bookon/actions/runs/37313519896) | `315b58e` | ✅ 4 job 全绿（含 HtmlFormatter 去强解包改动） |
| [37314891664](https://github.com/zhuof725/bookon/actions/runs/37314891664) | `8e988aa` | ✅ 4 job 全绿（文档补充） |

> **四次连续全绿**说明修复稳定、非偶发。`live-smoke` 仅在 `workflow_dispatch` 时运行，push 下为 skipped（预期）。

### 收敛过程（11 轮 CI，56 → 0 失败）

`test-macos` 从 56 项失败逐轮收敛到 0（43 项 `\s` 语义 + 14 项测试期望 + 2 项 `Book.type` 位假设）；
iOS/build-ipa 侧依次修掉：工程格式 `objectVersion` 77（缺陷 7）、scheme 无 test action（缺陷 8）、
校验脚本 SIGABRT（缺陷 9）。全部根因与修复见「二之三」表。

## 四、C 段返工完成状态（最终）

> 本节为 C 段返工的**最终状态**（历史轮次记录见下节「附录：CI 收敛过程」）。
> 返工覆盖 5 项：App 界面补齐、Cookie/缓存持久化、端到端测试补足、StringUtils 强解包清理、文档。

### 4.1 App 界面（业务逻辑全在 BookonDebugKit，界面只装配）

| 需求 | 实现 | 位置 |
|---|---|---|
| 点行进入该书源调试页（不再二次选书源） | 行内 `NavigationLink` + `navigationDestination` | `App/SourceListView.swift` |
| 导入面板 4 入口（粘贴 / `fileImporter` / URL 下载 / 剪贴板） | `ImportSheet` | `App/SourceListView.swift` |
| 导入结果弹窗（成功数 / 失败原因列表 / 警告） | `ImportResultSummary` + `.alert` | `App/SourceListView.swift`、`Sources/BookonDebugKit/ImportOutcome.swift` |
| 输入框下方示例提示（关键字/详情页/`::`/`++`/`--`） | `DebugKeyExample.all` | `Sources/BookonDebugKit/DebugTab.swift` |
| 开始 / 取消 | `DebugSession.start()` / `cancel()` | `App/DebugView.swift` |
| 6 个页签（日志/搜索/详情/目录/正文/结果源码） | `DebugTab` 枚举 + 顶部横向滚动标签条 | `Sources/BookonDebugKit/DebugTab.swift`、`App/DebugView.swift` |
| 源码页签：最后响应 URL/状态码/headers/body 前 N 字符（N 可设） | `DebugSession.capturedResponse(for:)` + `responseSummary(for:)` | `Sources/BookonDebugKit/DebugSession.swift` |
| 结果页签：解析书籍/目录/正文 + 可复制 JSON | `DebugSession.parsedResult` / `exportParsedResultJSON()` | `App/DebugView.swift` |
| 每页签「复制」按钮（UIPasteboard） | `UIPasteboard.general.string`（复制完整响应，不受显示上限） | `App/DebugView.swift` |
| 日志页签：等宽 / 可选中 / 自动滚底 / 错误行红 / 时间前缀 | `ScrollViewReader` + `textSelection(.enabled)` + `state == -1` 红色 | `App/DebugView.swift` |
| 导出日志改 ShareLink + 「已保存到：路径」+ 失败弹错 | `ShareLink` + `exportAlert`（不 `try?` 吞掉） | `App/DebugView.swift` |
| 日志历史（第 4 个 tab）：列 Documents/logs，时间倒序，打开/复制/分享/删除 | `LogHistoryView` + `DebugLogStore.listLogsNewestFirst/readLog/deleteLog` | `App/LogHistoryView.swift`、`Sources/BookonDebugKit/DebugLogStore.swift` |
| 设置：清除缓存（与清除 Cookie 分开）/ 版本 / commit / CI run | `SharedEnvironment.clearCache/clearCookies` + `AppBuildInfo.fromMainBundle()` | `App/SettingsView.swift`、`Sources/BookonDebugKit/{SharedEnvironment,AppBuildInfo}.swift` |

> 标签条按需求做成**顶部横向 `ScrollView(.horizontal)` + Button**（**非** `Picker(.segmented)`、
> **非** `TabView(.page)`）；选中标签主题色背景 + 粗体 + `minHeight 44`、`accessibilityAddTraits(.isSelected)`，
> `ScrollViewReader` 负责把选中标签滚入视野；内容区用 `switch`（非 `TabView`）。
> 某阶段已有响应源码时标签显示小圆点，日志出现 `-1` 时显示红点；圆点逻辑在 `DebugSession.tabBarState`，
> 由 DebugKit 测试覆盖。

### 4.2 Cookie / 缓存持久化

- `makeHTTPClient()` 不再每次新建内存 `CookieStore()` / `CacheManager()`；改用第 6 步文件实现
  （`FileCookiePersistence` / `FileCacheStorage`），路径固定在 `Documents/`
  （`cookies.json` / `legado_cache.json`），全 App 共享同一实例（`SharedEnvironment`），跨次调试保留。
- 设置页「清除 Cookie」/「清除缓存」真正清到这两个文件。
- DebugKit 测试：写 Cookie → 新实例读同一文件仍在 → 清除后消失（见 `DebugEnvironmentTests`）。

### 4.3 端到端测试（规则真实、数据合成）

- 7 个真实书源（按表格：速读谷 / 📂得奇小说网 / 🌸爱丽丝书屋(免翻) / ⚡📂淘小说书城 /
  ⚡📂得间小说 / 木里番茄 / 七猫），每个跑 **搜索→详情→目录→正文**，断言**精确值**。
- 资源：`Tests/LegadoWebBookTests/Resources/real/{real_sources_5,muli_real_source,qimo_real_source}.json`
  （已在 `Package.swift` 注册为资源）。
- **md5 逐字节比对**（muli/qimo 复制前后一致）：

  | 文件 | 字节数 | md5 |
  |---|---|---|
  | `real_sources_5.json`（5 书源合并） | 27054 | `220f427e0f1aa492defa4f700790e26c` |
  | `muli_real_source.json`（复制自 LegadoRuleEngineTests） | 140750 | `49b517c72d440197a4e51f266b1554dd` |
  | `qimo_real_source.json`（复制自 LegadoRuleEngineTests） | 22845 | `898dc0df17a78fb4b5fc0ba3b2d6d88d` |

- 加载器断言**正好 7 个**，名字/URL 与交付表一致；`synthetic_` 前缀负向护栏。
- 特殊 URL 形态专门断言：木里番茄**裸 IP + 端口**、七猫 **`#md` 后缀**、爱丽丝书屋 **Punycode**。
- 删除既有弱断言 `XCTAssertFalse(result.isEmpty)`（原 `WebBookEndToEndTests.swift:75/95`），
  一律换精确值（如 `XCTAssertEqual(result.count, 1)` + `XCTAssertEqual(result[0].name, "…")`）。
- 爱丽丝书屋正文规则含 `org.jsoup`（Rhino 专属），走第 5 步 `JsoupJSBridge` 替代实现。
- 本地用 `scripts/verify/e2e_assert.swift`（无 XCTest，真实产品代码）实测 **PASS=63 FAIL=0**，
  确认所有精确断言成立（含 4 阶段全链路）。

### 4.4 StringUtils 强解包清理

- 删除 `Sources/LegadoBookSource/RuleEngine/StringUtils.swift` 原第 249、252 行
  `unicodeScalars.first!`，改为安全写法（新增 `firstScalarValue(_:)`，空串返回 nil 兜底）。
- **全仓 grep 结果（如实列出，均为本次之前既有、非新增）**：
  `Unicode.Scalar(...)!` 9 处（`StringUtils.swift` 5 + `RealJsNetworkExtensionsProvider.swift` 4）；
  `content!` / `analyzeByXPath!` / `analyzeByJSoup!` / `analyzeByJSonPath!` 6 处（`AnalyzeRule.swift`）；
  `result!.isNull` 1 处（`AnalyzeRule+Dispatch.swift`）；`ind!` 1 处（`JavaURLResolver.swift`）；
  `baseURL!` 2 处（`NetworkUtils.swift`）。**本次改动未新增任何强解包**
  （`git diff HEAD` 中新增强解包命中数 = 0）。

### 4.5 隐私扫描（5 个提取书源）

扫描 `loginUrl` / `header` / `variable` / `cookie` / `token` / `authorization` 字段：

- 5 个目标书源仅含**通用 UA / Referer** 与登录页 URL；「Cookie」命中均来自 `enabledCookieJar` 布尔字段。
- 木里番茄 `loginUrl` 含 `api_key` / `Token` / `password` 关键字，逐条核对**均为 JS 变量名与 UI 文案**，
  无硬编码凭据；七猫 `loginUrl` / `header` 为空串。
- 结论：**未发现可疑个人 token / 凭据，可安全提交**（无需停下）。

### 4.6 测试用例数（本地计数，最终以 CI 为准）

| target | 用例数 |
|---|---|
| LegadoWebBookTests（含新增 `WebBookRealSourcesEndToEndTests` 16 条） | 171 |
| BookonDebugKitTests（含 `DebugKitPublicAPITests` 63 条 public 测试） | 145 |

> macOS 与 iOS 用例数相等由 CI 强制核对（`ios_sim_test.sh` 比对 `macos-test-count` artifact）。

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
- `scripts/verify_xcodeproj_format.sh`（工程 objectVersion 与 Xcode 版本兼容性门禁；awk + plutil，无管道、不依赖 xcodebuild）
- `scripts/ios_sim_test.sh`（iOS 模拟器测试；自动探测 `<包名>-Package` 聚合 scheme，并与 macOS 用例数核对）
- `scripts/build_ipa.sh`（xcodegen → archive → 校验 MinimumOSVersion → 打包 ipa）
- `scripts/local_typecheck.sh`、`scripts/local_typecheck_tests.sh`、`scripts/local_typecheck_bookon.sh`
- `scripts/golden/src/main/java/golden/{HtmlFormatterGen,WordCountGen}.java` + `Main.java`
- `scripts/golden/cases/{html_formatter_cases,word_count_cases}.json`
- `reference/kotlin/analyzeRule/webBook/*.kt`、`reference/kotlin/analyzeRule/Debug.kt`
- `.github/workflows/test.yml`、`Package.swift`、`README.md`、`FUNCTION_MAPPING.md`、`.gitignore`
- `ci_logs/step7_final_{golden,macos,ios,build_ipa}.log`（run 37310649613 的真实 CI 日志）

## 五、关键文件清单（C 段返工，本次新增/修改）

**App（C 段界面）**
- `App/BookonDebugApp.swift`（注入 `SharedEnvironment` / `DebugLogStore`）
- `App/ContentView.swift`（4 个 tab：书源 / 调试 / 日志历史 / 设置）
- `App/SourceListView.swift`（行内 NavigationLink + 导入 4 入口 + 结果弹窗）
- `App/DebugView.swift`（标签条 / 源码标签 / 结果标签 / 日志标签 / ShareLink 导出）
- `App/LogHistoryView.swift`（**新增**）
- `App/SettingsView.swift`（两个源码上限 Stepper + 恢复默认 + 清 Cookie/缓存 + 关于）

**BookonDebugKit（业务逻辑）**
- `Sources/BookonDebugKit/SharedEnvironment.swift`（**新增**：共享 Cookie/缓存实例 + 清除）
- `Sources/BookonDebugKit/DebugTextLimit.swift`（**新增**：两个上限 / 按 Character 截断 / 5MB 硬上限）
- `Sources/BookonDebugKit/DebugTab.swift`（**新增**：标签枚举 + `DebugKeyExample`）
- `Sources/BookonDebugKit/AppBuildInfo.swift`（**新增**：version / commit / CI run）
- `Sources/BookonDebugKit/ImportOutcome.swift`（**新增**：导入结果/弹窗文案）
- `Sources/BookonDebugKit/{BookSourceRepository,DebugSession,DebugLogStore,DebugSettings}.swift`（修改）

**内核（LegadoBookSource）**
- `Sources/LegadoBookSource/RuleEngine/StringUtils.swift`（删除强解包，新增 `firstScalarValue(_:)`）
- `Sources/LegadoBookSource/RuleEngine/DebugLogger.swift`、`WebBook/Debug.swift`（调试钩子/响应留存）

**测试**
- `Tests/LegadoWebBookTests/WebBookRealSourcesEndToEndTests.swift`（**新增**，16 用例）
- `Tests/LegadoWebBookTests/WebBookEndToEndTests.swift`（删除弱断言，改精确值）
- `Tests/BookonDebugKitTests/DebugKitPublicAPITests.swift`（**新增/扩写**，63 条 public 测试）
- `Tests/LegadoWebBookTests/Resources/real/{real_sources_5,muli_real_source,qimo_real_source}.json`（**新增**）

**验收 / 文档 / CI**
- `scripts/verify/e2e_probe.swift`、`scripts/verify/e2e_assert.swift`（本地探针 + 精确断言实测）
- `scripts/verify_debugkit_logic.sh`（DebugKit 逻辑实测 PASS=28 FAIL=0）
- `Package.swift`（注册 `Resources/real/` 资源）
- `README.md`（「如何在手机上使用」按新界面重写 + 两个上限章节 + 端到端章节 + B 段组件表）
- `STEP7_HANDOFF.md`（本文件）
- `ci_logs/`（三 job + build-ipa 真实日志）

## 六、已完成 / 仍需人工

**已完成（本次在 GitHub 上跑通并留存证据）**
- ✅ CI 四 job 全绿：run [`37310649613`](https://github.com/zhuof725/bookon/actions/runs/37310649613)（golden / test-macos / test-ios-simulator / build-ipa）。
- ✅ 真实日志已留存：`ci_logs/step7_final_{golden,macos,ios,build_ipa}.log`。
- ✅ `bookon-debug-ipa` artifact 已产出并确认（1,806,528 B）；`MinimumOSVersion = 17.0 ✓`。
- ✅ iOS == macOS 用例数相等（均为 **809**）；golden **24 文件 / 2391 条**全部通过。

**仍需人工**
- App 的 SwiftUI 界面**运行时**验证（Linux 无法编译/运行 SwiftUI，需在 macOS / 真机 / 模拟器上手点）。
- 书源编辑/分享等 UI 细节（README「不做」清单已声明，超出本步范围）。
- 如需安装到真机：`bookon-debug-ipa` 为**无签名**包，需自行重签或用 AltStore/侧载工具。
