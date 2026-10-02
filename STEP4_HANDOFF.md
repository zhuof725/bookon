# 第 4 步交付文档（A + B + C 三部分汇总，最终状态）

> 本文件由 STEP4A/4B/4C_HANDOFF.md 合并而来，**只保留最终状态**，中间过程措辞已删除。
> 所有 CI 结果以最后一次 push 的真实 run 为准（见下「最终验证」）。

---

## 最终验证（真实 CI 结果，run 37048761810，HEAD `1b3272a`）

三个 job 全绿 ✅：

| job | 状态 | 关键数字 | 日志 |
|---|---|---|---|
| golden（ubuntu，真实 java 库） | ✓ success | **703 条用例**（11 个用例文件） | `ci_logs/step4_final_golden.log` |
| test-macos（swift test） | ✓ success | **Executed 443 tests, 0 failures** | `ci_logs/step4_final_macos.log` |
| test-ios-simulator（xcodebuild test） | ✓ success | **实际执行 443 个测试**（与 macOS 相等） | `ci_logs/step4_final_ios.log` |

**iOS == macOS 测试总数核对**：iOS 按 8 个 xctest bundle 求和得 443，macOS `swift test` 的
「All tests」总数也是 443，两者**相等**（`scripts/ios_sim_test.sh` 实测打印
`✅ iOS 总数与 macOS 总数一致（均为 443）`，workflow 已加入相等性强制核对，不相等则 iOS job 失败）。

iOS 各 bundle 明细（来自 `step4_final_ios.log`）：
`LegadoAnalyzeRuleTests`=126、`LegadoAnalyzeRulePublicAPITests`=13、
`LegadoBookSourceTests`=14、`LegadoBookSourcePublicAPITests`=3、
`LegadoHTMLEngineTests`=171、`LegadoHTMLEnginePublicAPITests`=4、
`LegadoRuleEngineTests`=107、`LegadoRuleEnginePublicAPITests`=5，合计 443。

> **更正记录**：STEP4B 曾写「iOS 107 vs macOS 420，与第 3 步历史一致」。经核对**该说法错误**——
> 107 是单个 bundle（LegadoRuleEngineTests）的执行数被误当成 iOS 总数；iOS 实际跑全部 8 个
> bundle。第 3 步/4A 的真实日志里 iOS 与 macOS 数量本就一致（300/299）。本次已修复统计口径
> 并加入 CI 强制核对。

---

## 4-A：HTML 序列化器彻底重写

- 新增 `Sources/LegadoBookSource/RuleEngine/JsoupCompatSerializer.swift`：从零遍历 SwiftSoup
  DOM，按 jsoup 1.16.2 算法重新生成 `outerHtml()`/`html()`，替代旧的字符串级后处理
  `SwiftSoupVoidElementFix`（已删除）。`SwiftSoupTextNormalizeFix` 保留（仅服务于纯文本提取路径
  text()/ownText()/allText()，非 HTML 序列化）。
- 删除 `GoldenComparisonTests.swift` 的全部 `knownDivergences`，golden 改为严格逐字节比较。
- 新增 66 个合成 HTML golden 用例（`serializer_synthetic.json`）。
- 修复**无值属性折叠**：jsoup `Attribute.shouldCollapseAttribute` 的 `val==null` 分支——无值属性
  （如 `<video controls>`）无论名字是否在 30 个布尔属性清单里都折叠；SwiftSoup 用 `BooleanAttribute`
  子类表示无值属性，`getValue()` 一律返回 `""`，必须用 `is BooleanAttribute` 区分。修复后首轮
  8 处 golden 不一致全部清零。

## 4-B：AnalyzeRule 总调度 + JS 引擎（JavaScriptCore）

- 完整移植 `AnalyzeRule.kt`：getString（3 重载）/getStringList（2 重载）/getElement/getElements、
  splitSourceRule、SourceRule（Mode 判定、`{{ }}`、`@get:{}`、`@put:{}`、`$1~$99`、`##`/`###`）、
  putRule/splitPutRule/replaceRegex、各缓存（容量上限与 Kotlin 一致）、setContent（isJSON 判定）、
  put/get 四层回退链（chapter→book→ruleData→source）。
- `RuleValue` 枚举表达 Kotlin `Any?`（映射表见 README）。JS 引擎用 JavaScriptCore 实现 `evalJS`，
  绑定键名与 Kotlin 一致；`java` 对象只暴露 AnalyzeRule 自有方法，JsExtensions 67 个方法用
  JS Proxy 拦截，调用即抛「第 5 步未实现」错误 + 记 diagnostics，不静默返回 undefined。
- 外部依赖协议注入（RuleDataStore/AjaxProvider/WebJSProvider/CookieStore/CacheManager + 内存默认实现）。
- 移植 NetworkUtils（按 java.net.URL 算法，非 Swift URL 拼接）、unescapeHtml4、replaceRegex（Java→ICU 模板）。

**Kotlin 行为排除**（详见 README 差异表）：reGetBook/refreshTocUrl 留桩抛 unsupported；
真实网络 ajax → AjaxProvider 默认错误串；WebJs → 抛 unsupported；Java 互操作（Packages/importClass/
org.jsoup.Jsoup）→ JSC 无法运行，预检测抛 jsError + 记诊断；@put 只收规范 JSON；scriptCache 改缓存
源码字符串；数字字符串化整数带 `.0` 对齐 Kotlin。

## 4-C：真实 Java 库 golden 验证工具函数

- golden pom 新增 `json-path 2.10.0`、`commons-text 1.13.1`，gson 升 2.13.2，并强制
  `commons-lang3 3.18.0`（解决 commons-text NumericEntityEscaper 的 `Range.of` NoSuchMethodError）。
- 5 类工具函数 golden 用例全部达标：**getAbsoluteURL 66 / unescapeHtml4 52 / replaceRegex 51 /
  AnalyzeByRegex 24 / JSONPath 62**（≥60/40/50/20/60）。golden 总用例 448 → **703**。
- golden 暴露并修复的差异（逐条见 README）：
  1. `JavaURLResolver.resolve` 重写，精确移植 `java.net.URLStreamHandler.parseURL`（9 处 URL 修正）；
  2. `RegexTemplate` 命名组 `${name}`/`$<name>` → `$index`（ICU 不支持命名引用）；
  3. `JSONPathParser.readName` 在 `(` 处停止（修 `.length()` 被当字段名的 bug）；
  4. `jaywayStringValue` 用 Java-Map toString 格式；
  5. 修正旧单测 `testAbs_queryOnly` 错误断言。
- **JSONPath 15 条子集差异如实登记为已知差异**（真实 Jayway 支持、本项目自实现子集未覆盖：
  过滤器布尔多条件 `&&`/`||`、正则 `=~`、`in`、聚合 min/max/avg/sum、逗号多下标 `[0,2]`（×2）、
  步长切片、`@` 顶层根、裸 `@` 过滤器、多字段取值、`..*` 深扫顺序），`knownJSONPathDivergences`
  显式豁免，每条带注释理由，非静默跳过。**影响面实测**：14 个真实书源扫描这些语法**命中数为 0**。

## 第 4 步收尾补强（本次）

- **iOS==macOS 测试总数核对**：`ios_sim_test.sh` 改为按 bundle 求和 + 与 macOS artifact 总数比对，
  不相等则 iOS job 失败；新增 `scripts/extract_macos_count.py`；workflow 加 artifact 传递。
- **补 RuleValue `.jsObject`/`.jsonObject` 分支测试**：`RuleValueObjectBranchTests.swift`（17 例），
  覆盖 getString/getStringList/getElement/getElements 的键值直取、`{{ }}`、嵌套对象、数组、
  null、数字格式 + contentEquals 近似 3 个边界用例（结果无差异，README 已记录）。
- **`JS_EXTENSIONS_USAGE.md` 重写**：基于 14 个真实书源（`配置文件_14个.json`）严格扫描，
  更正「魔丸小说用 Java 互操作」的误述（实际未用）；仅**台湾小说网（8 次 `Packages.org.jsoup.Jsoup.parse`）**
  和**爱丽丝书屋（2 次 `org.jsoup.Jsoup.parse`）**用 Rhino 互操作；补 java/cookie/cache 方法清单与频次，
  标注已实现/未实现，作为第 5 步范围依据（最高频 `md5Encode`×177）。

## 全局规范核对（最终）

- 崩溃写法审计：`rg -n "fatalError|try!|\bas!" Sources` 仅注释命中，代码 0 命中 ✅。
- `verify_functions.py`：「Kotlin 有但 Swift 没实现」清单为空 ✅。
- golden 缺失在 CI 下必 fail（`failOrSkipWhenNoGoldenData`），不 XCTSkip ✅。
- 合成样本均标注（synthetic_ 前缀 / 文件内 `_SAMPLE_KIND` / 测试注释 / README）✅。

## 后续步骤 TODO

- **第 5 步**：实现 JsExtensions 方法体（优先级见 `JS_EXTENSIONS_USAGE.md`：md5Encode 177、
  t2s 6、timeFormat 4、toast 4、hexDecodeToString 3、base64* 4、startBrowser 1、webView 1、
  refreshExplore 1）。
- **第 6 步**：真实网络 ajax / AnalyzeUrl / WebBook 流程 / 真实 WebView。
- 可选：补 JSONPath 高级语法消灭 15 条已知差异；补 contentEquals 引用判等精确对齐。
