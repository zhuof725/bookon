# Step 4-C 交接文档（真实 Java 库 golden 对照验证工具函数）

## 目标
用真实 Java 库生成 golden 对照数据，验证并修正第 2、4 步工具函数：
- getAbsoluteURL（JavaURLResolver/NetworkUtils）← `java.net.URL`
- unescapeHtml4（HtmlUnescape/HtmlEntities）← `commons-text` 1.13.1
- replaceRegex（RegexTemplate + AnalyzeRule.replaceRegex）← `java.util.regex`
- JSONPath（AnalyzeByJSonPath/DefaultJSONPathEvaluator）← 真实 Jayway JsonPath 2.10.0
- AnalyzeByRegex（getElement/getElements）← 真实 Java 正则

## 状态：最终 CI run 36820xxxxxx（见下，待最后一次 push 跑完确认）
最近一次**确认看到的** CI 结果（run 36819511474，batch 2）：
- golden（ubuntu，真实 java 库 + 新依赖）：✓ **success**（18s）——新依赖成功打进 fat jar、golden 数据生成。
- test-macos（swift test）：✗ failure，**Executed 425 tests, with 1 failure**（唯一失败=旧 B 部分单测
  `NetworkUtilsTests.testAbs_queryOnly` 的陈旧断言，与 4-C 修正的真实 java.net.URL 行为冲突）。
  **UtilGoldenComparisonTests 全部 5 个方法已通过**（URL/unescape/replaceRegex/AnalyzeByRegex/JSONPath）。
- test-ios-simulator：与 macOS 同源，受同一处旧断言影响。

> batch 3（commit 92e985f）已修掉该旧断言 + 补 README；预期 macOS/iOS 全绿。
> **接手者务必**跑 `gh run list --repo zhuof725/bookon -L 3` 确认最新 run 三 job 真实 success，
> 不要凭本文件假设全绿（本文件写于 batch 3 push 之后、CI 跑完之前）。

## 已完成

### golden Maven 项目（scripts/golden/）
- **pom.xml 新增依赖**（版本对齐 legado `gradle/libs.versions.toml`）：
  - `com.jayway.jsonpath:json-path:2.10.0`（toml jsonPath=2.10.0）
  - `org.apache.commons:commons-text:1.13.1`（toml commonsText=1.13.1）
  - gson 2.10.1 → **2.13.2**（toml gson=2.13.2）
  - **强制 `commons-lang3:3.18.0`**（dependencyManagement）——commons-text 1.13.1 的
    NumericEntityEscaper 用 `Range.of(Comparable,Comparable)`，旧的间接 lang3 导致运行期
    `NoSuchMethodError`（CI 第一次 push 就是栽在这，第二次修好）。
  - shade 加 `ServicesResourceTransformer`（合并 META-INF/services）+ 去签名 filter。
  - jsoup 1.16.2 / JsoupXpath 2.5.3 不变。
  - **fat jar 可运行、golden 数据成功生成**（golden job success 已证实）。
- **新增 Java 生成器**（src/main/java/golden/）：
  - `UrlResolver.java`：Kotlin NetworkUtils.getAbsoluteURL 调度逻辑手工移植，内部真实 java.net.URL。
  - `UtilGen.java`：unescapeHtml4（真实 commons-text）、replaceRegex（Kotlin 语义 + 真实
    java.util.regex）、AnalyzeByRegex.getElement/getElements（从 legado 源码原样复刻）。
  - `JsonPathGen.java`：Kotlin AnalyzeByJSonPath 单规则路径 + 真实 Jayway。
  - `Main.java`：扩展识别 urlCases/unescapeCases/regexReplaceCases/regexAnalyzeCases/jsonPathCases。

### golden 用例（cases/*.json，全部 synthetic_ 标注）
| 文件 | 类别 | 用例数 | golden 对齐状态 |
|---|---|---|---|
| url_absolute.json | getAbsoluteURL | **67** | ✅ 全绿 |
| unescape_html4.json | unescapeHtml4 | **52** | ✅ 全绿 |
| regex_replace.json | replaceRegex | **51** | ✅ 全绿 |
| regex_analyze.json | AnalyzeByRegex | **24** | ✅ 全绿 |
| jsonpath_cases.json | JSONPath | **63** | ✅ 49 对齐 / 14 登记已知差异 |

### Swift 对照测试
- `Tests/LegadoHTMLEngineTests/UtilGoldenComparisonTests.swift`（@testable）：5 个测试方法，逐条比较，
  失败信息含 规则/输入/Java结果/Swift结果；CI 下 golden 缺失 XCTFail（不 XCTSkip）。
  JSONPath 的 14 条子集差异用 `knownJSONPathDivergences` 显式豁免（每条带注释理由）。

### 修复的 Swift 实现差异（golden 暴露后修）
1. **JavaURLResolver.resolve 重写**：精确移植 `java.net.URLStreamHandler.parseURL`——
   规范化仅对相对路径生效、越根 `/../` 保留字面、`//` 保留、`?query` only 丢文件名段、`..`/`.`
   产生尾斜杠。（原 B 部分用 RFC remove_dot_segments 过度规范化，9 处 URL 不一致全部修正。）
2. **RegexTemplate.javaToICU 加命名组支持**：`javaToICU(_:pattern:)` 解析 pattern 的命名组序号，
   把 `${name}`/`$<name>` 转成 `$index`（ICU 不支持命名引用）。（replaceRegex 1 处不一致修正。）
3. **JSONPathParser.readName 修 bug**：在 `(` 处停止，`.length()` 不再被当成字段名 `length()`。
4. **JSONValue.jaywayStringValue + javaMapString 新增**：对象用 Java Map 格式 `{k=v, k=v}`（值为
   数组→JSON、值为对象→递归 Map），AnalyzeByJSonPath 的 getString/getStringList 对象/数组 toString
   路径改用之。（JSONPath 多处对象格式不一致修正，不影响其它 stringValue 调用方。）
5. **修正 B 部分旧单测 `testAbs_queryOnly`** 的错误断言（c.html?k=v → b/?k=v），对齐真实 java.net.URL。

### 文档
- README 新增「第 4 步 C」章节：新依赖表、各类用例数、逐条修复、剩余已知差异表（11 条 JSONPath
  子集差异 + ICU vs Java 正则预防性登记）、样本诚实标注。
- README JSONPath 支持表加 4-C 修正注记（真实 Jayway 其实支持那些"不支持"项，本项目子集登记为差异）。

## 剩余 TODO / 还没对齐的差异（接手者可选补完）
以下 14 条 JSONPath 用例登记为**已知差异**（真实 Jayway 支持、自实现子集 DefaultJSONPathEvaluator
不支持），**非静默跳过**（golden 已跑真实行为，README 差异表 + knownJSONPathDivergences 均记录）。
诊断：书源规则几乎不用这些高级语法，完整复刻 Jayway 超出本步骤预算。接手者若要消灭这些差异，
需在 DefaultJSONPathEvaluator/JSONPathParser 实现：
1. 过滤器布尔多条件 `&&`/`||`（synthetic_unsupported_filter_and/or）——诊断：需给 FilterExpr 加
   布尔组合与优先级解析。**打算：登记为已知差异**（可后续补）。
2. 过滤器正则 `=~` / `in`（filter_regex/filter_in）——需加 `=~`、`in [..]` 操作符。**登记为已知差异**。
3. 聚合函数 min/max/avg/sum（unsupported_min/max/avg/sum，返回 Double）——需在 Token 加聚合。**登记**。
4. 逗号多下标 `[0,2]`、步长切片 `[0:6:2]`（multi_index/multi_index_book/step_slice）——需扩 parseBracket。**登记**。
5. `@` 作顶层根（unsupported_at_root）、过滤器内裸 `@`（filter_on_root_array，`$.nums[?(@>3)]`）——需
   支持 @ 等价 $ 及裸 @ 标量比较。**登记**。
6. 多字段取值 `['a','b']` 返回 Map 对象（multi_field_bracket）——Jayway 合成对象 `{a=..,b=..}`，子集
   返回列表。语义差异。**登记**。
7. `$.store..*` 深扫顺序/节点集（deep_scan_wildcard）——`..*` 遍历顺序与是否含中间容器不同。**登记**。

> 其余 JSONPath（$ . [] 递归 .. 通配 * 下标 切片 单条件过滤器 length() 超 Int64 大整数）全部 golden 对齐。

ICU vs Java 正则根本差异（占有量词 `a++`、`\h`/`\v`、`\Z`、内嵌标志作用域）——未纳入 golden 用例
（真实书源未见使用），README 预防性登记。replaceRegex/AnalyzeByRegex 的 75 条用例已全绿。

## 新增依赖是否成功打进 fat jar
**是**。golden job（ubuntu）`mvn -B -ntp package` + `java -jar target/golden-generator.jar cases out`
成功（run 36819511474 golden ✓ success 18s），生成所有类别 golden JSON。commons-lang3 3.18.0 收敛
解决了 commons-text 的 NoSuchMethodError。

## git commit 列表（本步骤，均已 push origin/main）
- `949f0e1` (1/n) 加 json-path/commons-text/gson 依赖 + 5 类 case 文件 + Java 生成器 + Main 分派 + Swift 对照测试
- `c37ebca` fix: 强制 commons-lang3 3.18.0（修 commons-text NoSuchMethodError）
- `1eb4957` (2/n) 修 getAbsoluteURL(java.net.URLStreamHandler 精确算法) + replaceRegex 命名组模板 +
  JSONPath .length() parser bug + jaywayStringValue Java-Map 格式 + 登记 14 条 JSONPath 子集差异
- `92e985f` (3/n) 修旧 testAbs_queryOnly 断言 + README 第4步C章节 + JSONPath 支持表修正注记

## 全局规范核对
- 绝不崩溃：`rg -n "fatalError|try!|\bas!" Sources` 仅注释命中，0 真实命中 ✅。
- verify_functions.py：「Kotlin 有但 Swift 没实现」清单为空 ✅（AnalyzeByJSonPath/AnalyzeByRegex/
  NetworkUtils.getAbsoluteURL 均已覆盖，本步骤未新增需排除的函数）。
- golden 缺失 CI 必 fail（UtilGoldenComparisonTests 用 failOrSkipWhenNoGoldenData，CI 下 XCTFail）。

## 下一步建议
1. 确认 batch 3（92e985f）CI 三 job 全绿（旧断言已修）。
2. 可选：按上方 TODO 在 DefaultJSONPathEvaluator 补 Jayway 高级语法，逐条消灭已知差异。
3. 第 5 步：JsExtensions 方法体实现（见 JsExtensionsCatalog.swift / JS_EXTENSIONS_USAGE.md）。
