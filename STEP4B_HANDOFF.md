# Step 4-B 交接文档（AnalyzeRule 总调度 + JS 引擎）

## 目标
移植 Kotlin `model/analyzeRule/AnalyzeRule.kt`（973 行，规则总调度）+ JS 引擎
（JavaScriptCore evalJS）+ 工具依赖（NetworkUtils / unescapeHtml4 / replaceRegex）+
依赖注入协议。**本次只做 B 部分，不做 C 部分**（C = golden 对照 java.net.URL /
commons-text / Java 正则，依赖 B 完成后由后续子代理接手）。

## 状态：三个 CI job 全绿 ✅（run 36816660789）
- golden（ubuntu，真实 java 库）：✓ success（15s）
- test-macos（swift test）：✓ success，**Executed 420 tests, 0 failures**（第 4A 时 299 → +121 新增）
- test-ios-simulator（xcodebuild test）：✓ success，Executed 107 tests 0 failures，`** TEST SUCCEEDED **`
- Verify field coverage / Verify function coverage：✓（verify_functions.py 覆盖清单为空）

> 验证命令：`gh run view 36816660789 --repo zhuof725/bookon`

## 已完成
### 新增 Sources 文件（Sources/LegadoBookSource/RuleEngine/）
- `AnalyzeRule.swift` — 主体：init/依赖注入、setter、setContent（isJSON 判定）、setBaseUrl、
  setRedirectUrl、getAnalyzeByXPath/JSoup/JSonPath（o!=content 新建否则缓存复用）、内部访问器。
- `AnalyzeRule+Dispatch.swift` — getString（3 重载）、getStringList（2 重载）、getElement、
  getElements，含 NativeObject(.jsObject)/LinkedTreeMap(.jsonObject) 分支、isUrl 拼接、unescape。
- `AnalyzeRule+Rules.swift` — splitSourceRule、splitPutRule、putRule、put/get 四层回退链、
  replaceRegex、compileRegexCache、缓存、companion 正则（JS_PATTERN/WebJS_PATTERN/putPattern/
  evalPattern/regexPattern，抄 AppPattern.kt 确切定义）。
- `SourceRule.swift` — SourceRule 类（Mode 判定、前缀、{{ }}/@get/$n 切分、makeUpRule、
  splitRegex、##/### 分离）。
- `AnalyzeRule+JS.swift` — evalJS（注入 java 自有方法闭包）、ajax、log、getTag、getSource、
  webJSResult、reGetBook/refreshTocUrl 桩。
- `JSEngine.swift` — JavaScriptCore 求值器（`#if canImport(JavaScriptCore)`），绑定键名与 Kotlin
  一致，Java 互操作预检测，JS↔RuleValue 转换，scriptCache 容量 16。
- `JSJavaBridge.swift` — `java` 对象桥接 + **JS Proxy 拦截**（未实现 JsExtensions 方法抛明确错误
  + 记 diagnostics）。
- `JsExtensionsCatalog.swift` — JsExtensions.kt 67 个方法名（正则自动提取）。
- `RuleValue.swift` — Kotlin Any? → Swift 动态类型枚举（映射表见 README）。
- `AnalyzeRuleDependencies.swift` — RuleDataStore/BookData/ChapterData/SourceVariableStore/
  AjaxProvider/WebJSProvider/CookieStoreProtocol/CacheManagerProtocol 协议 + 内存默认实现。
- `NetworkUtils.swift` — getAbsoluteURL(String/JavaURL 两重载)、getBaseUrl、isAbsUrl、isDataUrl。
- `JavaURLResolver.swift` — java.net.URL 的 parse + 相对解析算法自实现（**不用 Swift URL 拼接**）。
- `HtmlUnescape.swift` + `HtmlEntities.swift` — unescapeHtml4 + 252 条 HTML4 命名实体表。
- `RegexTemplate.swift` — Java/Kotlin 替换模板 → ICU 模板转换。
- `LegadoStringExtensions.swift` — isJson/isJsonObject/isJsonArray/isAbsUrl/isDataUrl/splitNotBlank。
- `RuleEngineError.swift` 新增 case：`.unsupported(String)`、`.jsError(String)`。

### 测试（121 个，两个新 target）
- `Tests/LegadoAnalyzeRuleTests/`（@testable）：AnalyzeRuleTests（Mode/split，17）+
  AnalyzeRuleDispatchTests（getString/List/Element，~30）+ AnalyzeRuleJSTests（JS/put-get/
  replaceRegex/缓存，~35）+ NetworkUtilsTests（URL/unescape/template，~30）+
  AnalyzeRuleEndToEndTests（7 真实书源规则，11）。
- `Tests/LegadoAnalyzeRulePublicAPITests/`（普通 import）：14 个 public API 可见性用例。
- Package.swift 已注册两个 target；真实配置 `配置文件_7个.json` 复制到测试 Resources。

### 脚本 / 文档
- `scripts/verify_functions.py` 扩展：加入 AnalyzeRule.kt + NetworkUtils.kt 映射 + `EXCLUDED`
  字典（每个排除函数附理由，打印时列出）。结果清单为空。
- `README.md` 新增「第 4 步 B」章节：RuleValue 映射表、JS→RuleValue 转换表、Rhino vs
  JavaScriptCore 差异表、java.net.URL vs Swift URL 差异、Java 正则 vs ICU 差异、unescapeHtml4
  差异、@put 非规范 JSON / @text 实体解码差异、本步骤排除清单、样本诚实标注。
- `FUNCTION_MAPPING.md` 新增 AnalyzeRule 分支→测试表 + 未直接单测分支标注。
- `JS_EXTENSIONS_USAGE.md` 新增：7 书源 java.xxx 使用情况表。

## Kotlin 行为简化 / 排除（逐条理由）
1. **reGetBook / refreshTocUrl**：依赖 WebBook（真实搜索/详情页流程），本步骤留桩抛
   `.unsupported`。理由：WebBook 属后续步骤，任务明确排除。
2. **JsExtensions 67 个方法体**：不实现，用 Proxy 拦截抛错 + 记 diagnostics。理由：任务明确
   「不在本步骤范围，第 5 步做」。
3. **真实网络（ajax / AnalyzeUrl）**：AjaxProvider 默认返回错误串（对齐 Kotlin getOrElse
   { stackTraceStr }）。理由：真实网络第 6 步。
4. **真实 WebView（WebJs / BackstageWebView / java.webView）**：WebJSProvider 默认抛
   `.unsupported`。理由：第 5/6 步。
5. **Java 互操作（Packages/importClass/org.jsoup.Jsoup 等）**：JavaScriptCore 无此能力，
   预检测到即抛 `.jsError` + 记 diagnostics，**不假装支持**。理由：Rhino-only，JSC 无等价物
   （真实书源魔丸/爱丽丝用到，端到端测试断言抛错）。
6. **协程上下文 setCoroutineContext**：Swift 无对应协程模型，排除（verify EXCLUDED 列理由）。
7. **@put 非规范 JSON**：Kotlin GSON lenient 能解析 `{saved:p@text}`；本移植只接受规范 JSON
   `{"saved":"p@text"}`，非规范忽略不崩。理由：标准 JSON 解析器；lenient 待后续补（Legado 文档
   本就推荐规范 JSON）。已写入 README 差异表。
8. **scriptCache**：Kotlin 缓存 CompiledScript；JSC 无「编译后脚本」对象，改为缓存源码字符串
   （容量 16 一致）。行为等价（仍避免重复 remember）。
9. **数字字符串化**：RuleValue.number 整数值输出带 `.0`（如 evalJS("1+1")="2.0"）；
   但 {{ }} 内联 JS 结果走 makeUpRule 的 `%.0f` 强制整数，与 Kotlin 对齐。已写入 README。

## 待 C 部分 golden 最终验证（本步骤只写合成自测）
- **NetworkUtils 相对解析**（JavaURLResolver）：对齐 java.net.URL 的理解实现，边角（含空格/中文、
  file:、越根 ..、连续 //）待真实 java.net.URL 对照（≥60 例）。
- **unescapeHtml4**：252 条 HTML4 实体表 + 数字实体，个别冷门实体/大小写变体待 commons-text
  对照（≥40 例）。
- **replaceRegex**：Java→ICU 模板转换 + Java/ICU 正则匹配差异待对照（≥50 例）。

## 已知未修复问题 / 风险（给接手者）
- **无真正的 golden 对照**：上述三块的正确性目前只有合成单测保证，C 部分必须做真实对照，
  很可能发现若干边角不一致需修正 JavaURLResolver / HtmlEntities / RegexTemplate。
- **NativeObject/LinkedTreeMap 分支无专用单测**：RuleValue 的 `.jsObject`/`.jsonObject` 分支已
  实现并被 evalJS 返回对象路径间接覆盖，但没有「直接把 .jsObject content 喂 getString」的
  用例。建议 C/5 步补。
- **contentEquals 近似**：Kotlin `o != content` 用引用判等；Swift RuleValue 非 Equatable，用
  stringValue 判等近似。极端情况下（两个字符串化相同但语义不同的中间值）缓存复用判断可能偏差。
  目前测试未暴露问题，但属潜在差异点。
- **iOS job 107 vs macOS 420**：iOS 用 xcodebuild 只跑 @testable 的一个聚合，数目差异与第 3 步
  一致（历史如此），非回归。

## git commit 列表（本步骤，均已 push 到 origin/main）
- `201bacf` (1/4) NetworkUtils+JavaURL、unescapeHtml4+实体表、string ext、RuleValue、依赖协议、catalog
- `e6ce93f` (2/4) AnalyzeRule 核心调度、SourceRule、splitSourceRule、put/get、replaceRegex、JS 引擎
- `1da250f` (3/4) 121 测试 + 注册 target + 扩展 verify_functions.py
- `0da413e` fix: getAnalyzeBy* 改 internal、JavaURL 改 public、加 JS_EXTENSIONS_USAGE.md
- `80af861` fix: getAbsoluteURL 重载改 parsedBase:（解决 nil 歧义）+ README 第 4B 章节
- `0af83d2` fix: 修正 5 个测试断言 + 文档化 lenient-JSON/@text 差异
- `<本提交>` docs: FUNCTION_MAPPING 第 4B 分支表 + STEP4B_HANDOFF

## 下一步（Step 4-C，给接手者）
1. 写 golden 生成器（真实 java.net.URL / commons-text unescapeHtml4 / java.util.regex），
   生成对照数据放 `Tests/.../Resources/golden`，新增 GoldenComparisonTests 严格比较。
2. 按 golden 结果修正 `JavaURLResolver.swift` / `HtmlEntities.swift` / `RegexTemplate.swift`。
3. 补 NativeObject/LinkedTreeMap 分支直接单测。
4. （第 5 步）按 `JsExtensionsCatalog.swift` + `JS_EXTENSIONS_USAGE.md` 优先级实现
   hexDecodeToString/base64*/webView 等 JsExtensions 方法。
