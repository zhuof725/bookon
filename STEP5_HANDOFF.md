# Step 5 交付文档（JsExtensions 方法体 + org.jsoup.Jsoup 替身 + 收尾三项）

> 只写最终状态。CI 结果以最后一次 push 的真实 run 为准（见文末「最终验证」）。

## 范围

在第 1–4 步成果（API 名称与行为不变）之上：

1. 实现第一批纯算法 JsExtensions 方法（md5/t2s/s2t/timeFormat/base64/hex/htmlFormat/encodeURI/
   randomUUID/toNumChapter/strToBytes/bytesToStr 等）。
2. UI/系统与网络/文件类方法以协议注入（`JsUIProvider` / `JsNetworkExtensionsProvider`）+
   默认 unsupported + 记 diagnostics。
3. 用 SwiftSoup 实现 `org.jsoup.Jsoup` 替身，放行 `org.jsoup.Jsoup.parse` 与
   `Packages.org.jsoup.Jsoup.parse` 两种写法（爱丽丝书屋、台湾小说网真实规则可用）；
   其余 Rhino 互操作仍抛出。
4. 其余 JsExtensions 方法保持 JS Proxy 拦截抛错 + 记 diagnostics。

**收尾三项（本次新增）**：

5. Jsoup 替身与**真实 jsoup 1.16.2** 做 golden 对照（≥40 条用例、≥8 份 HTML、含 3 份以上不规范 HTML）。
6. golden 用例补足：14 个方法各 ≥15 条、`t2s`/`s2t` 各 ≥30 条、`bytesToStr` 覆盖非 UTF-8 字符集。
7. JS 数字入参用**真实 Rhino 1.8.1** 验证，删除全部手写转换规则；淘小说吧签名链的期望值
   改为 golden 里 Java `MessageDigest` 直算的结果。

## 交付内容

### 源码（Sources/LegadoBookSource/RuleEngine/）

- `JsExtensionsCore.swift`：第一批纯算法实现 + `ChineseTransfer`（quick-chinese-transfer 0.2.17
  词典最长匹配 + legado fixT2sDict 排除词）。**收尾新增**：`bytesToStr` 支持 ISO-8859-1
  （256 字节 1:1 映射）与 GBK（合法双字节用 GB18030-2000 逐对解码；非法字节按 JDK
  `sun.nio.cs.DoubleByte.Decoder#crMalformedOrUnmappable` 的「消费 1 还是 2 字节」规则逐个替换为 U+FFFD，
  末尾不足 2 字节按 `endOfInput + underflow → malformedForLength(剩余)` 处理）。
- `JsNumberFormat.swift`（新增）：ECMAScript `Number::toString` 复刻（最短往返数字 + k/n 分段规则），
  供 `JsExtensionsRuntime.stringify` 把 JS number 转成 Java String 参数用。
- `JsExtensionsRuntime.swift`：`__call` 通用分发器 + diagnostics + 同名可调用方法。
  `stringify` 里的手写「整数无 .0」规则已删除，改为 `JsNumberFormat.toString`。
- `JsoupJSBridge.swift`：org.jsoup.Jsoup 替身。**收尾按 golden 先修 5 处语义**：
  `text()` 走 `SwiftSoupTextNormalizeFix`（`&nbsp;` 规整）；`html()`/`outerHtml()` 走
  `JsoupCompatSerializer`（不再用 SwiftSoup 自带 pretty-print）；`Elements.attr` 取
  「第一个**拥有**该属性的元素」；`eq(越界)` 返回空集合；`get(越界)` 抛 JS 异常
  （对齐 `IndexOutOfBoundsException`）。选择器解析失败也抛 JS 异常。
- `JsoupCompatSerializer.swift`：**收尾新增两处修正**——`Document.outerHtml()` 不输出 `<#root>`
  包裹标签（子节点与 `Element.html()` 同口径从 depth 0 开始），属性名输出前小写化
  （jsoup 在 tokenizer 阶段就把属性名规整为小写，SwiftSoup 2.9.6 保留了原始大小写）。
- `JSJavaBridge.swift` / `JsExtensionsCatalog.swift` / `AnalyzeRuleDependencies.swift` / `AnalyzeRule.swift` /
  `JSEngine.swift`：同前（Proxy 桥接、94 方法清单、协议注入、互操作预检测）。
- `Resources/Chinese/{t2s,s2t}.txt` + `t2s_exclude.txt` + `PROVENANCE.md`
  （quick-chinese-transfer 0.2.17 原样资源）。

### 测试

- `Tests/LegadoHTMLEngineTests/JsExtGoldenComparisonTests.swift`：321 条 golden 三态对照。
  **收尾改动**：删除 harness 里手写的「整数无 .0」规则，数字参数一律读 golden 的 `argStrings`
  （由真实 Rhino 1.8.1 得出）；`bytesToStr` 支持 `charset` 字段。
- `Tests/LegadoHTMLEngineTests/JsoupBridgeGoldenComparisonTests.swift`（新增）：91 条 jsoup 对照
  （严格对照 90 + 已登记差异 1），用 JSC + 替身求值同一条 JS，与 golden 的「真实 jsoup」结果比较。
- `Tests/LegadoHTMLEngineTests/RhinoNumberArgGoldenTests.swift`（新增）：42 条数字入参三层对照
  （JSC `String(x)` / `JsNumberFormat` / 完整 `AnalyzeRule` 调用链），外加 1 条已登记次正规数差异。
- `Tests/LegadoAnalyzeRuleTests/AnalyzeRuleEndToEndTests.swift`：爱丽丝/台湾两条断言的期望值
  改为从 golden 读（`alice_e2e_text` / `taiwan_e2e_content`）；淘小说吧签名链改为 golden 的
  `javaDigestResults`（Java `MessageDigest`）；不再用 Swift 自己的 md5 反推期望值。
- 为让端到端测试能读 golden：`Package.swift` 给 `LegadoAnalyzeRuleTests` 增加
  `.copy("Resources/golden")`，CI 两个测试 job 在下载 golden artifact 后各加一步
  `Mirror golden for AnalyzeRule end-to-end tests`（`cp` 到该目录）。

### golden（scripts/golden）

- `JsExtGen.java`：`jsExtCases`（321 条）+ **新增** `runJsoup`（91 条，同一 JS 两边跑）
  + `runJavaDigest`（2 条，Java MessageDigest 直算）。数字参数一律取
  `NumberArgGen.receivedForLiteral`（真实 Rhino 结果）。
- `NumberArgGen.java`（新增）：把与 JsExtensions 同名同签名的探针绑成脚本里的 `java`
  （与 legado 的 RhinoScriptEngine 一致：绑定放在标准全局对象下的子作用域上），
  执行 `java.<method>(<字面量>)`，记录 Rhino 实际传给 String 参数的那一串。
- `Main.java`：挂载 `jsoupCases` / `numberArgCases` / `javaDigestCases` 三类新用例。
- 用例文件：`js_ext_cases.json`（321）、`jsoup_cases.json`（91）、`js_number_args.json`（42）
  + 既有的 12 个文件；**合计 15 个文件 1233 条用例**（收尾前为 13 个文件 869 条，新增 364 条）。
- `scripts/extract_jsoup_chains.py`（新增）：从真实书源配置提取 jsoup 链（用例来源可复核），
  `--check` 校验每条用例的 `source` 标签都能命中真实规则。

### 文档

- `README.md`：第 5 步章节更新（方法表、替身、golden 三类生成器、jsoup 用例来源与输入清单、
  数字入参 Rhino 验证三层、样本诚实标注）；Rhino vs JSC 差异表新增两条已登记差异。
- `JS_EXTENSIONS_USAGE.md`、`STEP4_HANDOFF.md` 同前（本步骤未改动其结论）。

## 关键语义对齐（全部经真实库 golden 验证）

| 方法 / 行为 | 关键点 |
|---|---|
| `md5Encode` / `md5Encode16` | UTF-8 字节 MD5 小写 hex；16 位 = substring(8,24)（`abc` → `3cd24fb0d6963f7d`） |
| `base64Encode` / `base64Decode` | hutool 容错解码逐行移植（跳过非法字符、`=` padding、4 字符一组） |
| `hexEncodeToString` / `hexDecodeToString` | 空串原样 `""`；奇数长度前补 `0`；非法字符抛错 |
| `t2s` / `s2t` | quick-chinese-transfer 0.2.17 词典最长匹配 + legado fixT2sDict 排除词（各 38 条用例） |
| `timeFormat` / `timeFormatUTC` | SimpleDateFormat / `SimpleTimeZone(sh ms, "UTC")` 语义 |
| `encodeURI` | URLEncoder：空格→`+`、保留 `. - * _`、UTF-8 大写 hex |
| `toNumChapter` | `(第)(.+?)(章)` + fullToHalf + parseInt/中文数字（逗号、小数点、异体字路径都覆盖） |
| `htmlFormat` | HtmlFormatter.formatKeepImg(null) 全正则链；Java `\s` 只含 ASCII 空白 |
| `strToBytes` / `bytesToStr` | UTF-8 / ISO-8859-1 / GBK；非法字节的 U+FFFD 替换语义与 Java 一致 |
| JS number → String 参数 | ECMAScript `Number::toString`（`1e21`→`1e+21`、`1e-7`→`1e-7`、`-0`→`0`、`NaN`/`Infinity` 保留）；由真实 Rhino 1.8.1 定义并逐条对照 |
| jsoup 替身 | 90 条严格对照全部一致（含不规范 HTML 的容错解析、pretty-print 序列化、属性/文本语义） |

## 已知差异（登记 README 差异表）

1. **Java String 返回值的包装**：Rhino `javaPrimitiveWrap` 默认 true（`WrapFactory.java:163`），
   Java 方法返回的 String 被包成 `NativeJavaObject`，`.length` 解析为 Java 的 `length()` 方法
   （`typeof` 为 `"function"`）；替身返回 JS 字符串（`.length` 为数字）。
   golden `divergence_java_string_length_type` 钉住两侧实际值，测试断言差异必须存在。
   影响面：爱丽丝书屋真实规则里的 `content.length < 50` 在 legado 里恒为 false；本移植按真实长度判断。
2. **最小次正规数的最短十进制表示**：Rhino 1.8.1 `DoubleFormatter` 给 `"4.9e-324"`，
   JSC/V8 与本移植的 ECMAScript 复刻给 `"5e-324"`。golden `numarg_md5_5eneg324` 钉住两侧值；
   两者解析回同一个 double，书源不会把次正规数传给 String 参数。

> 旧版曾登记的「bytesToStr 非 UTF-8 未对照」「NaN/Infinity 数字经 stringify 输出 Swift 字面量」
> 两条**已消除**：前者已按 UTF-8/ISO-8859-1/GBK 真实对照，后者已由 Rhino 定义 + `JsNumberFormat` 复刻。

## 最终验证（真实 CI 结果，run 37135836791，HEAD `45b03a4`）

三个 job 全绿 ✅：

| job | 状态 | 关键数字 | 日志 |
|---|---|---|---|
| golden（ubuntu，真实 java 库） | ✓ success | **1233 条用例 / 15 个用例文件**（jsoup 91、js_ext 321、numberArg 42、javaDigest 2） | `ci_logs/step5c_final_golden.log` |
| test-macos（swift test） | ✓ success | **Executed 453 tests, 0 failures** | `ci_logs/step5c_final_macos.log` |
| test-ios-simulator（xcodebuild test） | ✓ success | **实际执行 453 个测试**（与 macOS 相等） | `ci_logs/step5c_final_ios.log` |

**iOS == macOS 测试总数核对**：iOS 按 8 个 xctest bundle 求和得 453，macOS `swift test` 的
「All tests」总数也是 453，脚本实测打印 `✅ iOS 总数与 macOS 总数一致（均为 453）`。

iOS 各 bundle 明细：`LegadoAnalyzeRuleTests`=129、`LegadoAnalyzeRulePublicAPITests`=13、
`LegadoBookSourceTests`=14、`LegadoBookSourcePublicAPITests`=3、`LegadoHTMLEngineTests`=178、
`LegadoHTMLEnginePublicAPITests`=4、`LegadoRuleEngineTests`=107、`LegadoRuleEnginePublicAPITests`=5。

（收尾前：449 个测试 / 869 条 golden 用例；收尾后新增 4 个测试方法、364 条 golden 用例。）

## 后续 TODO（第 6 步）

- 真实网络：AjaxProvider 接入 AnalyzeUrl（get/post/head/ajaxAll/connect/cacheFile/downloadFile）。
- 真实 WebView：WebJSProvider/BackstageWebView（webView/webViewGetSource/webViewGetOverrideUrl）。
- UI 能力：JsUIProvider 的真实实现（toast/startBrowser/getVerificationCode 等）。
- JsExtensions 其余方法（压缩/字体/TTF/读书配置/主题/加密）按需实现。
