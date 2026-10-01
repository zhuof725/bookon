# bookon — legado 书源数据模型 Swift 移植（第 1 步）

用 Swift 5.9+ 移植 [legado](https://github.com/gedoor/legado) 的书源数据模型。
**本步骤只做数据模型**，不含规则解析引擎、网络请求、UI、持久化。

## 结构

```
Sources/LegadoBookSource/
├── LenientDecoding.swift     # 宽松解码 property wrapper（Int/Int64/Bool/String，覆盖类型不统一）
├── StringOrObject.swift      # 规则字段「对象 or JSON 字符串」两用解码，编码统一为对象
├── LegadoJSON.swift          # 统一 JSONEncoder/Decoder（不转 snake_case，不转义斜杠）
├── BaseSource.swift          # BaseSource 协议（数据字段）
├── BaseBook.swift            # BaseBook 协议（数据字段）
├── BookSource.swift          # 书源主模型
├── Book.swift                # 书籍（含内嵌 ReadConfig）
├── BookChapter.swift         # 章节
├── SearchBook.swift          # 搜索结果书籍
├── BookSourceImporter.swift  # 逐条容错导入器（成功列表 + 失败原因列表）
├── Constant/
│   ├── BookType.swift
│   └── BookSourceType.swift
└── Rule/
    ├── BookListRule.swift    # 协议
    ├── SearchRule.swift  ExploreRule.swift  BookInfoRule.swift
    ├── TocRule.swift  ContentRule.swift  ReviewRule.swift
    └── ExploreKind.swift  FlexChildStyle.swift  RowUi.swift

Tests/LegadoBookSourceTests/            # @testable 单元测试
├── BookSourceImporterTests.swift
└── Resources/
    ├── test_bookSources.json           # 见下方「测试样本说明」
    └── muli_real_source.json           # 真实书源（🍅木里番茄），用于真实往返测试

Tests/LegadoBookSourcePublicAPITests/   # 纯 public 接口测试（普通 import，非 @testable）
├── PublicAPITests.swift
└── Resources/ (同上两份 json)
```

## 测试样本说明

- `test_bookSources.json` 共 6 个书源：
  - **#0–#3 是真实书源**（前 3 个的规则字段为「JSON 字符串」形式，第 4 个为「对象」形式）。
  - **#4、#5（“段评测试-对象/字符串”）是合成样本，非真实书源**：为覆盖 `ReviewRule`
    全字段而手工构造，用于验证 `ruleReview` 两种形式的 decode/encode 一致性。
- `muli_real_source.json` 是用户提供的**真实**书源（🍅木里番茄）。注意它通过
  `ruleContent.callBackJs` 的 JS 实现段评，**不含数据模型层的 `ruleReview` 结构化字段**，
  因此不能作为“真实 ruleReview 样本”；它被用作真实书源的整体往返一致性测试。
  截至目前尚无「真实带 ruleReview 字段」的书源样本，故 #4/#5 保留为合成样本并已明确标注。

## 运行测试

```bash
swift test
```

会同时运行两个测试 target：`LegadoBookSourceTests`（@testable 单元测试）与
`LegadoBookSourcePublicAPITests`（纯 public 接口测试）。
macOS / Linux（带 Swift 工具链）均可。GitHub Actions（`.github/workflows/test.yml`）
在 **Linux（swift 5.10）与 macOS 两个平台**上自动跑「字段校验 → build → test」。

## 关键设计

1. **字段名 100% 对齐** Kotlin，不转 snake_case，可直接导入现有书源 JSON。
2. **宽松解码**：数字↔字符串↔布尔(0/1) 互转由 property wrapper 处理，缺字段用同样默认值，绝不因类型不符或缺字段报错。
3. **规则字段两用**：`ruleSearch` / `ruleReview` 等既能吃「对象」也能吃「JSON 字符串」（内层再嵌一层 JSON），编码统一输出对象。对应 Kotlin `BookSource.Converters` + 各 Rule 的 `jsonDeserializer`。
   容错时 `StringOrObject` **区分三种情况**记录警告（均不抛错、置 nil）：
   - 值是**字符串**但内层二次解析失败 → 警告「(JSON 字符串)内层解析失败」；二次解析复用外层同一个
     `DecodingWarningCollector`，内层更深一层的警告不会丢失；
   - 值是**对象**但解码失败 → 警告「规则字段是对象但解码失败：具体错误」（不吞错误）；
   - 值**既不是对象也不是字符串**（数字/数组/布尔）→ 警告「既不是对象也不是字符串」。
   警告统一汇总进 `BookSourceImportResult.warnings`。
4. **逐条容错导入**：一条坏书源不影响其他，返回成功列表 / 失败列表 / 警告列表三部分。
5. **对外 API 均为 `public`**：所有模型类型、property wrapper、导入器、`LegadoJSON` 等可作为独立 SwiftPM 库被外部模块使用。
   由**独立的 `LegadoBookSourcePublicAPITests` target（普通 `import`，非 `@testable`）**守护——
   若任何对外成员漏了 `public`，该 target 会编译失败。
   > 已知 API 小瑕疵：`ExploreKind.Type` / `RowUi.Type` 这两个嵌套的字符串常量命名空间，
   > 与 Swift 元类型 `.Type` 语法冲突，无法在模块外用 `ExploreKind.Type.url` 直接引用
   > （常量本身仍是 public）。为不改动既有 API 名称，暂保留现状；如需在外部使用请直接用对应字符串字面量。

## 字段覆盖

见 [FIELD_MAPPING.md](FIELD_MAPPING.md)。**「Kotlin 有但 Swift 没实现的字段」清单为空**（225/225 覆盖）。

---

# 第 2 步：规则引擎底座 + 两个最简单后端

移植 legado 规则引擎的「切分器 + 正则后端 + JSONPath 后端」。
**不含** JSoup / XPath / AnalyzeRule 总调度 / JS / 网络 / UI；第 1 步 API 名称与行为未改动。

## 新增结构

```
Sources/LegadoBookSource/RuleEngine/
├── RuleAnalyzer.swift          # 规则切分器（对照 Kotlin RuleAnalyzer.kt 逐行移植）
├── AnalyzeByRegex.swift        # 正则后端（NSRegularExpression）
├── AnalyzeByJSonPath.swift     # JSONPath 后端（依赖 RuleAnalyzer + JSONPathEvaluator）
├── JSONPathEvaluator.swift     # JSONPath 求值协议 + JSONValue 模型 + 结果类型
├── DefaultJSONPathEvaluator.swift  # 自实现 JSONPath 子集求值器
├── JSONPathParser.swift        # JSONPath 表达式解析
└── RuleEngineDiagnostics.swift # 非致命错误的可选诊断收集器（默认关闭）

Tests/LegadoRuleEngineTests/            # @testable 单元测试
├── RuleAnalyzerTests.swift             # 34 例
├── AnalyzeByRegexTests.swift           # 12 例
├── AnalyzeByJSonPathTests.swift        # 28 例
└── Resources/
    ├── synthetic_lieying_like.json     # ⚠️ 合成样本（非真实数据），结构参考猎鹰小说网规则
    └── real/
        ├── muli_real_source.json       # 真实书源（🍅木里番茄），来源：用户提供
        └── qimo_real_source.json       # 真实书源（七猫小说），来源：用户提供
Tests/LegadoRuleEnginePublicAPITests/   # 纯 public 接口测试（普通 import，非 @testable）
└── RuleEnginePublicAPITests.swift      # 5 例
```

## 下标语义（中文 / emoji 不错位）

Kotlin 的 `String` 按 **UTF-16 code unit** 下标（`queue[pos]`、`indexOf`、`substring`、`regionMatches`）。
`RuleAnalyzer` 内部完全在 `[UInt16]`（UTF-16 code unit 数组）上操作，切片时从 UTF-16 范围重建 `String`，
保证含中文、emoji（UTF-16 代理对）时位置与 Kotlin 完全一致。

## JSONPath 引擎选型

Kotlin 用的是 **Jayway JsonPath**（JVM 库，无法直接用于 Swift/iOS/Linux）。

评估：
- **Sextant**（纯 Swift JSONPath）：可用，但其语义与 Jayway 有出入（对 definite/indefinite、
  `..` 递归、`.[*]` 点后方括号、结果去重等行为不完全一致），且会引入额外依赖，增加 Linux CI 的不确定性。
- **自实现子集**（本项目采用）：把引擎封装在 `JSONPathEvaluator` 协议后面，`AnalyzeByJSonPath` 只依赖协议，
  以后可无缝替换为 Sextant 或其它库。自实现只覆盖书源实际用到 + 任务点名的语法，行为对齐 Jayway 的
  definite/indefinite 语义（确定路径返回单值、含 `..`/`[*]`/过滤器/多下标/切片的返回列表）。

> 选型结论：**自实现子集 `DefaultJSONPathEvaluator`**，协议隔离，便于替换。

### Jayway JsonProvider 确认（对象/数组转字符串格式、数字、键顺序）

去 Kotlin 源码确认：`AnalyzeByJSonPath.parse` 用的是 `JsonPath.parse(json)`，即 Jayway 的
**默认 Configuration**（`utils/JsonExtensions.kt` 里那个 `SUPPRESS_EXCEPTIONS` 的 ParseContext 是另一处工具，
`AnalyzeByJSonPath` 未使用）。Jayway 默认 provider 是 **json-smart（`JsonSmartJsonProvider`）**，因此：
- **对象有序**：json-smart 用 `net.minidev.json.JSONObject`（`LinkedHashMap`），保留 JSON 文本键顺序。
  → 本移植用保序的 `JSONValue.OrderedObject` 对齐。
- **数字**：整数解析为 `Long`（`toString` 无小数点、19 位精确），小数解析为 `Double`（`1.0`→`"1.0"`）。
  → 本移植 `JSONValue` 拆 `int(Int64)` / `double(Double)`，用自实现保序解析器直接解析数字文本，不经 `Double` 丢精度。
- **对象/数组 `toString`**：json-smart 输出**紧凑 JSON**（`{"k":v,...}`，键值无空格）。
  → 本移植 `compactJSONString` 输出同样的紧凑、保序格式。

### 已支持 / 不支持的 JSONPath 语法

| 语法 | 示例 | 支持 |
|---|---|---|
| 根 | `$` | ✅ |
| 子字段（点） | `$.a.b` | ✅ |
| 子字段（方括号引号） | `$['a']`、`$["a"]` | ✅ |
| 多字段 | `$['a','b']` | ✅（indefinite） |
| 裸方括号字段 | `$[a]` | ✅（Jayway 容忍） |
| 递归下降 | `$..a`、`$..[*]` | ✅（indefinite） |
| 通配 | `$.a[*]`、`$.a.*`、`$[*]` | ✅（indefinite） |
| 点后方括号 | `$.a.[*]` | ✅（如木里/猎鹰规则） |
| 数组下标 | `$.a[0]`、`$.a[-1]` | ✅（支持负数从末尾） |
| 数组切片 | `$.a[1:3]`、`$.a[:2]`、`$.a[2:]` | ✅（indefinite） |
| 过滤器（比较/存在） | `$.a[?(@.x=='y')]`、`>` `<` `>=` `<=` `!=`、`[?(@.x)]` | ✅（单条件，indefinite） |
| length 函数 | `$.a.length()` | ✅ |
| **过滤器多条件 `&&`/`||`/`in`/正则 `=~`** | `[?(@.x=='a' && @.y>1)]` | ❌ **不支持** |
| **脚本表达式 / 函数（min/max/avg/sum...）** | `$.a.min()` | ❌ **不支持** |
| **下标含表达式 / 逗号多下标** | `$.a[0,2]` | ❌ **不支持** |
| **步长切片** | `$.a[0:6:2]` | ❌ **不支持** |
| **`@`(当前节点根)作为路径根** | `@.x` 作为顶层 | ❌ **不支持**（仅过滤器内 `@.` 支持） |
| 无 `$` 前缀的裸路径 | `data.books`、`original_author` | ✅（Jayway/legado 容忍；七猫书源即此写法） |

> 不支持的语法在解析时抛 `JSONPathError.unsupportedSyntax`；`AnalyzeByJSonPath` 会（如同 Kotlin 吞异常）
> 返回空值，并把错误记入可选的 `RuleEngineDiagnostics`（默认关闭）。
>
> **对象键顺序**：`$.obj.*` / `$..*` 等通配结果按 JSON 文本顺序返回（对齐 Jayway 有序语义），
> 有测试 `testObjectWildcardKeyOrder` / `testRecursiveWildcardKeyOrder` / `testGetObjectCompactKeyOrder` 固定。
> **数字精度**：整数(`int` Int64) / 小数(`double`) / **超 Int64 大整数(`bigInteger` 原始文本)** 三分；
> 19 位整数原样、超 Int64 的 20 位整数原样、`1.0`→`"1.0"`、`1.5`→`"1.5"`、负数/科学计数法各有测试固定。

## 错误处理：无崩溃、抛 Swift Error、非致命走诊断

本轮收尾把所有会让 App 崩溃的写法全部消除，改为：

**会抛 `RuleEngineError`（对齐 Kotlin 会向上传播的异常）：**
- `RuleAnalyzer` 括号/平衡组不平衡（Kotlin 抛 `Error`）→ `RuleEngineError.unbalanced`。
- `RuleAnalyzer` 下标越界 / `trim()` 越界（Kotlin `queue[pos]`/`substring` 抛异常）→ `RuleEngineError.indexOutOfBounds`。
- `AnalyzeByRegex` 正则编译失败（Kotlin `Pattern.compile` 抛异常）→ `RuleEngineError.regexCompileFailed`。
- `AnalyzeByRegex.getElement` 最后规则里捕获组未参与匹配（Kotlin `group(i)!!` 抛 NPE）→ `RuleEngineError.regexGroupNotParticipated`。

因 Kotlin 里 `splitRule` 不在 try 内、异常会向上传播，Swift 对应 public 方法都标 `throws`：
`RuleAnalyzer.splitRule/innerRule/trim`、`AnalyzeByRegex.getElement/getElements`、
`AnalyzeByJSonPath.getString/getStringList/getList/getObject`。

**保持吞掉并记录（对齐 Kotlin `try-catch`+`printOnDebug`）：**
- `AnalyzeByJSonPath` 里 `ctx.read` 读取失败：仍返回空值（`""`/`[]`/`nil`），
  同时记入可选的 `RuleEngineDiagnostics`（默认 `nil`，不收集、不影响返回值）。
  构造时传入即可：`AnalyzeByJSonPath(json, diagnostics: collector)`。

**无效 JSON 输入（第 2 点）：不再静默变 null：**
- 容错版 `init(_:)`：JSON 解析失败时**记录到 diagnostics**（`source = "AnalyzeByJSonPath.init"`）后，
  以空根继续，后续读取返回空值。
- 严格版 `init(validatingJSON:) throws`：JSON 解析失败**抛 `RuleEngineError.invalidJSON`**
  （对齐 Jayway `JsonPath.parse` 解析失败抛异常）。
- 测试：`testInvalidJSONRecordsDiagnostics` / `testValidatingInitThrowsOnInvalidJSON` / `testValidatingInitWorksOnValidJSON`。

**innerRule 回调抛错（第 3 点）：立即中断，与 Kotlin 一致：**
- `innerRule` 的 `fr` 闭包声明为 `throws`；回调抛错会**立即中断 innerRule 并向上传播**
  （不再用「延后捕获再抛」）。对齐 Kotlin 里 `innerRule("{$.") { getString(it) }` 直接调用的传播语义。
- 测试：`testInnerRuleCallbackErrorPropagatesImmediately`。

**全仓库审计（命令与结果）：**
```
rg -n "fatalError" Sources     # 仅注释命中，代码 0 处
rg -n "try!" Sources           # 无
rg -n '\bas!' Sources          # 无
rg -n '\S!(\s|$|\))' Sources | rg -v '// |/// |!='   # 代码行强制解包：无
```
`fatalError` / `try!` / `as!` / 强制解包 / 可能越界的数组访问：**代码中均已清零**（`fatalError` 只在注释里描述 Kotlin 行为）。

## 与 Kotlin 已知差异

| # | 位置 | Kotlin 行为 | 本移植行为 | 说明 |
|---|---|---|---|---|
| 1 | 括号不平衡 | `throw Error("…后未平衡")`（未捕获则崩） | 抛 `RuleEngineError.unbalanced`（message 同为 "…后未平衡"） | 语义一致，收敛为可捕获的 Swift Error，不崩溃 |
| 2 | 下标越界 | `StringIndexOutOfBoundsException` | 抛 `RuleEngineError.indexOutOfBounds` | 同上 |
| 3 | 正则编译失败 | `PatternSyntaxException` | 抛 `RuleEngineError.regexCompileFailed` | 同上 |
| 4 | getElement 捕获组未参与 | `group(i)!!` 抛 NPE | 抛 `RuleEngineError.regexGroupNotParticipated` | 同上；getElements 仍取 `""`（与 Kotlin `?: ""` 一致） |
| 5 | `innerRule(start,end)` 回调返回 null | `st.append(前缀 + null)` → 拼接字面量 `"null"` | `frv ?? "null"`，同样拼接 `"null"` | **精确对齐**（易被误写成 `?? ""`，已用测试 `testInnerRuleStartEndReturnsNilAppendsNullLiteral` 固定） |
| 6 | `innerRule("{$.")` 回调返回 null/空 | `!frv.isNullOrEmpty()` 才拼接，否则跳过 | `if let frv, !frv.isEmpty` 才拼接 | 一致 |
| 7 | 超过 Int64 的纯整数 | json-smart 用 `BigInteger`，精确 | `JSONValue.bigInteger(String)` **保留原始数字文本**，getString/紧凑输出原样，精确不丢 | ✅ 已对齐（`testBeyondInt64IntegerExact` 等固定）。仅过滤器 `[?(...)]` 大小比较时会转 Double（可能损失精度），已在代码注释标注 |
| 8 | 浮点 `toString` | Java `Double.toString`（最短往返） | 整数值浮点输出 `"x.0"`，其余用 Swift `String(Double)` | 常见小数一致；极端边界（非常长的尾数）可能与 Java 最短表示有细微差别，如遇到再对齐 |
| 9 | 无效 JSON 传入 | Jayway `parse` 抛异常 | 容错版记诊断+空根；严格版 `init(validatingJSON:)` 抛 `RuleEngineError.invalidJSON` | 提供两种，默认容错、可选严格 |

> 除以上 9 条，暂无其它已知不一致。第 8 条为如实标注的浮点边界差异；第 7 条超大整数已保精度对齐（仅过滤器比较用 Double）。

## 样本诚实标注

- `synthetic_lieying_like.json`、以及测试里各内联 JSON：**合成样本，非真实数据**（文件名 `synthetic_` 前缀 +
  文件内 `_SAMPLE_KIND` 字段 + 测试注释三处标注）。
- `Resources/real/muli_real_source.json`（🍅木里番茄）、`Resources/real/qimo_real_source.json`（七猫小说）：
  **真实书源，来源：用户提供**，放在 `real/` 目录。七猫的 `ruleSearch`/`ruleToc`/`ruleBookInfo` 里的
  纯 JSONPath 规则（`data.books`、`original_author`、`book_tag_list[*].title`、`data.chapter_lists` 等）
  用于 6+ 个测试（`testQimo*`）——**规则真实、数据为按规则形状构造的合成 JSON**，已在注释标注。
- 用真实书源『规则文本』+ 合成『数据』的测试（如木里的 `$.author||...` 短路），已在注释里注明「规则真实 / 数据合成」。

## 函数与分支覆盖（第 2 步部分）

见 [FUNCTION_MAPPING.md](FUNCTION_MAPPING.md)。`scripts/verify_functions.py` 自动从 Kotlin 源码提取全部 `fun` 校验，
**「Kotlin 有但 Swift 没实现的函数」清单为空**（第 2 步 17/17；连同第 3 步共 32/32，见文件末尾）。
分支→测试对照表见该文件，未覆盖分支已明确标出。

## 第 2 步测试规模与 CI（历史记录，第 3 步 CI 配置见下方最新版）

第 2 步交付时规则引擎测试连同第 1 步共 130+ 个测试；第 3 步完成后总数见文末「测试规模」章节。

---

# 第 3 步：HTML 规则引擎（AnalyzeByJSoup + AnalyzeByXPath）

移植 legado 的 CSS(JSoup) 与 XPath 规则解析后端。**不做** `AnalyzeRule` 总调度、JS、网络、UI；
第 1、2 步 API 名称与行为未改动。目标平台 iOS 15+（macOS 仅本地开发用）。

## 依赖选型

### CSS / DOM：SwiftSoup

Kotlin 用 **jsoup 1.16.2**（`libs.versions.toml` 里有注释提示新版有破坏性变更，故锁定该版本）。
Swift 侧选用 **SwiftSoup**（`scinfu/SwiftSoup`），是 jsoup 的逐方法移植，API 形态最接近，
`select()` 支持同一套 CSS 选择器语法（含 `:eq()`、`,` 多选择器等书源常用写法）。

版本锁定：`exact: "2.9.6"`（swift-tools-version 5.9，与 CI 的 Swift 5.10 工具链兼容）。
**未选 2.10.0+**：SwiftSoup 自 2.10.0 起把 `swift-tools-version` 提到 6.0，
GitHub Actions 当前 `swift:5.10`/Xcode 15.4 工具链无法解析该依赖（`Package.resolved` 报
"incompatible tools version"），故锁定最后一个 tools-5.9 版本。

### XPath：自实现子集（`SwiftSoupXPathEvaluator`）

Kotlin 用 **JsoupXpath 2.5.3**（在 Jsoup DOM 上执行 XPath，并提供 `allText()/html()/outerHtml()/ownText()` 等扩展）。
Swift 无等价库，评估两个方案：

- **(a) libxml2 / Kanna**：Kanna 底层是 libxml2 的 HTML 解析器，其 HTML 容错策略（如何处理
  未闭合标签、隐式 `<tbody>` 插入、属性大小写等）与 Jsoup **不同**，会导致同一份不规范书源 HTML
  在两边选出不同的 DOM 结构，进而选择结果不一致——这违背"与 Kotlin 行为一致"的要求。
- **(b) 在 SwiftSoup 的 DOM 上自实现 XPath 子集**：直接复用步骤里已经用 SwiftSoup 解析出的
  同一棵 DOM 树，保证 CSS 和 XPath 两个后端看到的是同一份解析结果，行为可控、可与 JsoupXpath
  的常见用法对齐。

**选型结论：(b) 自实现子集**，已在 `XPathEvaluator` 协议后面隔离（`AnalyzeByXPath` 只依赖协议），
以后如需替换为更完整的实现，可直接替换 `evaluatorType` 参数而不改调用方代码。

## SwiftSoup 与 jsoup 1.16.2 已知差异

**本表已用 `scripts/golden`（真实 jsoup 1.16.2 + JsoupXpath 2.5.3，见下方「golden 对照」章节）逐条验证。**

| 方法 / 行为 | jsoup 1.16.2 | SwiftSoup 2.9.6 | 影响与应对 |
|---|---|---|---|
| `Elements.addAll(Collection)` / `clear()` | `clear()` 只清空集合，不碰 DOM | **无 `addAll`/`clear`**；`empty()` 存在但语义是"清空每个元素的子节点"（会改 DOM，完全不是"清空集合"！） | 本移植用内部扩展 `addElements(_:)` 包装批量添加；**不提供、也不使用**任何"clear 集合"包装——开发中一度错误地用 `empty()` 模拟 `clear()` 导致真实 bug（见下方专门记录），现已改为直接用新 `Elements()` 替换变量 |
| `getElementsContainingOwnText(text)` | 存在，匹配元素自身直接文本包含 text | 存在，签名一致（`throws`） | 无差异 |
| `textNodes()` | 返回直接子 `TextNode` 列表 | 同 | 无差异 |
| `ownText()` | 返回元素自身文本（不含子元素），非 throwing | 同，非 throwing | 无差异 |
| `outerHtml()` / `html()` | 返回 String，不抛检查异常 | Swift 签名 `throws`（Swift 语言层面的强制，非行为差异） | 本移植统一用 `try?` 吞掉（理论上不会真的失败），不影响正常路径结果 |
| `text()` 的空白规整 | 默认 `trimAndNormaliseWhitespace = true`，合并连续空白为单个空格 | 同样默认 `true` | 无差异（golden 验证一致） |
| `Collector.collect(Evaluator.Id(id), el)` | 存在 | 存在，API 形态一致 | 无差异 |
| 中文 / emoji 解析 | 按 UTF-16 处理属性/选择器字符串（JVM String） | Swift `Character`/`UInt16` 混用；本移植所有下标逻辑改在 UTF-16 code unit 上处理 | 已通过含中文/emoji 的测试验证一致 |
| void 元素（如 `<img>`）的 `outerHtml()` 渲染 | 渲染为 `<img src="...">`（无自闭合斜杠） | SwiftSoup 源码 `Element.swift` 的 `outerHtmlHead` 把 HTML/XML 两个语法分支都错写成了 `" />"`（库自身 bug，已读源码定位到具体行） | **Step4-A 已彻底修复**：不再依赖字符串后处理，`JsoupCompatSerializer` 从零按 jsoup `Tag.java` 的 `emptyTags` 清单重新生成标签输出，详见下方「Step4-A：HTML 序列化重写」章节 |
| `&nbsp;`（U+00A0）的空白规整（HTML 序列化路径，`@html`/`@all`/`outerHtml()`/`html()`） | `StringUtil.isActuallyWhitespace` 把 nbsp 纳入可折叠空白（jsoup 特有扩展，非 HTML 规范） | 只认标准空白字符，遗漏 nbsp | **Step4-A 已彻底修复**：`JsoupCompatSerializer.escape()` 复刻 jsoup `Entities.escape()` 的 nbsp 转义规则，序列化路径不再有此问题 |
| `&nbsp;`（U+00A0）的空白规整（纯文本提取路径，`text()`/`ownText()`/`allText()`） | 同上 | 同上 | **已修正**：`SwiftSoupTextNormalizeFix`（职责边界见该文件顶部注释：只服务于不经过 HTML 序列化的纯文本提取 API） |
| `<br>` 后文本节点的 pretty-print 换行缩进 | `TextNode.outerHtmlHead` 有 `前一兄弟是 <br>` 的专门换行规则，缩进深度取其在 DOM 树里的真实嵌套深度（由 `NodeTraversor` 遍历维护） | 缺失这条分支，`<br>` 后文本永远不换行 | **Step4-A 已彻底修复**：字符串级后处理（`SwiftSoupBrIndentFix`）已被证明不可靠并删除，`JsoupCompatSerializer` 改为自己做深度优先遍历（自带真实树深度 `depth` 参数），完整复刻 `TextNode.outerHtmlHead` 的该分支，详见下方「Step4-A：HTML 序列化重写」章节 |

> 若后续实测发现与 jsoup 1.16.2 的其它差异，会在此表继续补充。

## Step4-A：HTML 序列化重写（`JsoupCompatSerializer`）

### 背景与动机

Step3 发现 SwiftSoup 2.9.6 的 `outerHtml()`/`html()` 与真实 jsoup 1.16.2 在两类上有差异
（见上表），当时用字符串级后处理（`SwiftSoupVoidElementFix` 修 void 元素自闭合、
`SwiftSoupBrIndentFix` 尝试修 `<br>` 后缩进）。后者被证明**不可靠**：同一条"文本紧跟 `<br>`"
规则在不同 DOM 嵌套位置下的真实缩进深度不同，纯字符串处理只能看到当前行的局部文本，无法正确
推算该文本节点在完整 DOM 树里的真实深度，因此回退并记录为已知差异（9 项登记在
`GoldenComparisonTests.knownDivergences`）。

Step4-A 的目标就是彻底解决这个问题：**不再对 SwiftSoup 输出的字符串做任何后处理**，而是绕开
SwiftSoup 自带的 `outerHtml()`/`html()`，自己从零遍历 SwiftSoup 解析出的 DOM 节点
（`Node`/`Element`/`TextNode`/`Comment`/`DataNode`/`DocumentType`，均为 SwiftSoup 公开类型，
通过 `getChildNodes()`/`parent()`/`previousSibling()`/`nextSibling()`/`siblingIndex` 等公开
API 访问），按真实 jsoup 1.16.2 的算法重新生成字符串。这样"深度"就是遍历时天然维护的真实树深度，
不再需要从字符串猜测。

### 实现：`Sources/LegadoBookSource/RuleEngine/JsoupCompatSerializer.swift`

对照来源（均已逐行读取 jsoup 1.16.2 官方 GitHub 源码确认，而非凭记忆）：

| 复刻内容 | jsoup 源码位置 |
|---|---|
| Tag 分类清单（block/inline/empty/formatAsInline/preserveWhitespace） | `org.jsoup.parser.Tag`（静态初始化块：`blockTags`/`inlineTags`/`emptyTags`/`formatAsInlineTags`/`preserveWhitespaceTags`） |
| 深度优先遍历 + 真实树深度 | `org.jsoup.select.NodeTraversor.traverse`（depth 随 descend/ascend 增减） |
| `indent()` | `org.jsoup.nodes.Node.indent`：`'\n' + StringUtil.padding(depth * indentAmount, maxPaddingWidth)` |
| 元素 head/tail、`shouldIndent`/`isFormatAsBlock`/`isInlineable` | `org.jsoup.nodes.Element`：`outerHtmlHead`/`outerHtmlTail`/`shouldIndent`/`isFormatAsBlock`/`isInlineable` |
| 文本节点换行与转义（含 `<br>` 后文本特判） | `org.jsoup.nodes.TextNode.outerHtmlHead` |
| 注释、DataNode（script/style 原样输出）、DocumentType | `org.jsoup.nodes.Comment`/`DataNode`/`DocumentType` 的 `outerHtmlHead` |
| 转义规则（base 模式、`&nbsp;`、非 BMP 字符原样输出） | `org.jsoup.nodes.Entities.escape()` |
| 属性输出（布尔属性折叠、属性值转义） | `org.jsoup.nodes.Attribute`/`Attributes`（`shouldCollapseAttribute`/`htmlNoValidate`） |
| `StringUtil` 等价函数 | `org.jsoup.internal.StringUtil`（`padding`/`isActuallyWhitespace`/`isWhitespace`/`isInvisibleChar`/`appendNormalisedWhitespace`） |

`OutputSettings` 固定为 jsoup 默认组合：`prettyPrint=true, indentAmount=1, maxPaddingWidth=30,
outline=false, charset=UTF-8, escapeMode=base, syntax=html`——这是 legado 书源规则引擎唯一
会用到的组合，规则引擎本身不提供任何修改 `OutputSettings` 的接口，因此代码里没有做成可配置的，
而是直接把这些默认值内联进各分支判断（已在每处注释标注对应省略了 jsoup 源码里哪个恒为
`false`/默认值的分支，例如全文省略了 `out.outline()` 分支，因为固定为 `false`）。

调用点替换：
- `AnalyzeByJSoup+Elements.swift` 的 `getResultLast`（`html`/`all` 两种 lastRule）：
  `elements.outerHtml()` → `JsoupCompatSerializer.elementsOuterHtml(elements.array())`
- `XPathEvaluator.swift` 的 `JXNode.asString()`（元素节点场景）：
  `e.outerHtml()` → `JsoupCompatSerializer.outerHtml(e)`
- `SwiftSoupXPathParser.swift` 的 XPath 终端函数 `html()`/`outerHtml()`：
  分别改用 `JsoupCompatSerializer.innerHtml(e)` / `.outerHtml(e)`

### 删除的字符串后处理

- `SwiftSoupVoidElementFix.swift` 整个文件已删除（含其中的 `SwiftSoupVoidElementFix`、
  `SwiftSoupBrIndentFix`、组合入口 `SwiftSoupHtmlFix`）。void 元素自闭合格式和 `<br>` 后
  缩进现在都由 `JsoupCompatSerializer` 直接按 jsoup 算法保证正确，不再需要任何后处理补丁。
- `SwiftSoupTextNormalizeFix`（nbsp 规整）**被拆到独立文件** `SwiftSoupTextNormalizeFix.swift`
  保留，因为它服务的是另一条完全不同的路径：

**职责边界**（写明以避免未来误删或误用）：
- `JsoupCompatSerializer`：负责"HTML 结构序列化"路径——CSS 规则的 `@html`/`@all`，XPath 的
  `html()`/`outerHtml()`/元素节点 `asString()`。这些路径自己遍历 DOM 树，内部已经复刻了 jsoup
  `Entities.escape()` 的空白折叠规则（含 nbsp），**不依赖** `SwiftSoupTextNormalizeFix`。
- `SwiftSoupTextNormalizeFix`：负责"纯文本提取"路径——`text()`/`ownText()`/`allText()`、XPath
  的 `text()`/`funcText`/`funcAllText`。这些路径调用的是 SwiftSoup 原生 `Element.text()`/
  `TextNode.text()`/`Element.ownText()`，其内部空白折叠用的是 SwiftSoup 自己的
  `StringUtil.isWhitespace`（没有被 `JsoupCompatSerializer` 取代，因为这条路径根本不经过
  本项目的 DOM 遍历），因此仍需要这个文件对结果再做一次 nbsp 等价规整。

### golden 测试：knownDivergences 已清零

`Tests/LegadoHTMLEngineTests/GoldenComparisonTests.swift` 里原先登记的全部 9 项
`knownDivergences`（`realBookList`、`brSeparatedContent_html`、`brSeparatedContent_outerHtml`、
`consecutiveBr_bodyOuterHtml` 等）已全部删除，`knownDivergences` 现在是空集合。golden 比较
对所有用例（含新增的序列化场景）做逐字节严格比较，不允许任何形式的豁免。

### 新增 golden 用例：`scripts/golden/cases/serializer_synthetic.json`

Step4-A 新增 66 个合成（synthetic）HTML 样本，覆盖：块级嵌套内联/内联嵌套块级、多层无序/
有序列表嵌套、表格（含 thead/tbody/tfoot/colgroup/嵌套表格）、pre/textarea 空白保留、连续多个
`<br>`、`<br>` 夹在文本中间、`<img>` 混排图文、空元素、HTML 注释、实体
（`&amp;`/`&lt;`/`&nbsp;`/`&copy;`/`&quot;`）、emoji/非 BMP 字符（含代理对）、属性值含引号和
换行、布尔属性（`disabled`/`checked`/`multiple`）、深层嵌套（14 层 `<div>`）、超长单行文本、
`<script>`/`<style>` 内容、未闭合标签（`<p>`/`<li>`/`<span>` 缺少闭合经 jsoup 容错修复）、纯文本
片段等。每个 HTML 样本同时产出 4 条用例：CSS `@html`、CSS `@all`、XPath `html()`、XPath
`outerHtml()`，共 264 条用例（66 × 4），全部标注 `_SAMPLE_KIND: "合成样本（synthetic）"`
与既有 `css_basic.json`/`xpath_basic.json` 的标注风格一致。

### 验证方式与影响面评估（legado `HtmlFormatter.formatKeepImg`）

legado 原生对**正文内容**会调用 `HtmlFormatter.formatKeepImg`（见
`app/src/main/java/io/legado/app/model/BookContent.kt` 第 244 行附近）做空白折叠后再显示，
所以即使序列化结果在缩进/换行上有差异，对最终阅读正文的影响也很小——这也是 Step3 阶段能暂时
容忍已知差异、不影响发版质量判断的原因。但**书籍简介、目录标题**等字段如果书源规则直接用
`@html`/`@all` 取整块 HTML 字符串（不经过 `formatKeepImg` 这层后处理），格式差异会直接暴露给
用户（例如多一个换行、缩进空格数不对，显示到详情页时肉眼可见）。

因此 Step4-A 的目标被定为"golden 逐字节完全一致"，**不因为"反正正文会被 formatKeepImg 后处理
掉"而放松标准**——验证方式是：
1. 本地：`python3 scripts/verify_functions.py` / `scripts/verify_fields.py` 做字段与函数覆盖
   的静态核对（不能跑 Swift 编译器，见"环境限制"）。
2. 真正验证：push 后由 CI 的 `golden` job（Maven + jsoup 1.16.2 + JsoupXpath 2.5.3，真实运行
   产出对照 JSON）+ `test-macos`/`test-ios-simulator` 两个 job（下载 golden 产物，跑
   `GoldenComparisonTests` 做逐字段严格比较）确认。截至本次提交，CI 结果见
   `STEP4A_HANDOFF.md`（如实记录，不在本文承诺"已全绿"）。

### 环境限制说明

本项目开发环境（iSH / Alpine Linux aarch64）**没有 Swift 工具链**，无法本地 `swift build`/
`swift test` 做编译期验证，只能：
1. 读 jsoup 1.16.2 官方源码（GitHub raw，非凭记忆）逐行核对算法；
2. 读 SwiftSoup 2.9.6 源码确认其公开 API 的真实签名与行为（`Node`/`Element`/`TextNode`/
   `Tag`/`Attributes` 等）；
3. 用 Python 脚本（`verify_functions.py`/`verify_fields.py`）做字段/函数覆盖的静态核对；
4. 手工逐行 trace 新代码对已知样例（如 `brSeparatedContent`/`consecutiveBr`）的输出，
   在纸面上模拟 jsoup 算法确认一致；
5. 最终依赖 push 后的 GitHub Actions CI 三个 job 做真正的编译 + golden 比对验证。

### 开发中定位并修复的一个自身实现 bug（非 SwiftSoup / Kotlin 差异，记录备查）

`SwiftSoup.Elements` 没有 Jsoup 的 `clear()`（清空集合，不碰 DOM）。初版误将其包装成调用
SwiftSoup 的 `Elements.empty()`——但 `empty()` 的真实语义是 **"清空每个已匹配元素的子节点"**
（对应 `Element#empty()`，会真的修改 DOM！），完全不是"清空集合"。这导致 `getResultList`/`getElements`
里"处理完一段 `@` 链式规则后清空临时集合复用"的写法，实际上会把 `self.element`（原始文档）的子节点
整个清空，使同一个 `AnalyzeByJSoup` 实例上第二次及以后的规则查询全部失效（`&&`/`||`/`%%` 组合规则、
连续两次 `getStringList` 调用等均受影响）。
**修复**：删除这个错误的 `clearAll()` 包装，所有"清空复用"的地方一律改为直接赋值一个新的 `Elements()`
实例。已用专门的回归测试固定（`testRegressionConsecutiveClassSelectors`、
`testRegressionConsecutiveTagSelectors`、`testRegressionGetResultListTwiceInSequence`、
以及 `testAndJoin` 等全部 `&&`/`||`/`%%` 组合测试）。
这不是 Kotlin 与 Swift 的行为差异，纯属移植过程中的实现错误，已在交付前发现并修复。

### 开发中的一处自我认知纠正：CSS `:eq(n)` 的真实语义

调试上面那个 bug 时，一度误以为 CSS `p:eq(2)` 表示"匹配到的所有 `<p>` 里的第 3 个"，
但 jsoup/SwiftSoup 的 `Evaluator.IndexEquals` 实际用 `element.elementSiblingIndex() == index`
判断，而 `elementSiblingIndex()` 内部用 `parent().children()`（jsoup: `childElementsList()`）
取同级节点列表——**该列表只包含同级的 Element（元素）节点，不含文本节点**。
故准确表述为：**`:eq(n)` 匹配的是"该元素在其同级 Element（不分标签，但不含文本节点）中的
序号"**，而不是"在同标签匹配集合里的第 n 个"。这不是 SwiftSoup 与 jsoup 的差异（两者行为一致，
都是标准 CSS 选择器语义），纯粹是移植过程中构造测试用合成 HTML 时的认知错误，已按正确语义
重新设计 `Tests/LegadoHTMLEngineTests/AnalyzeByJSoupTests2.swift` 里 `xiaoshuo2016SearchHTML`
的 DOM 结构（让 `<li>` 的直接子节点顺序与真实规则 `p:eq(2)>a`/`p:eq(3)`/`p:eq(4)` 期望的兄弟位置一致）。
「不含文本节点」这一点已用 golden 用例 `eqExcludesTextNodesCss`/`eqExcludesTextNodesCssSecond`
（`Resources` 里含纯文本节点穿插在两个 `<p>` 之间的 HTML）验证：`p:eq(0)`/`p:eq(1)` 按
Element 序号命中，不受中间文本节点干扰。

## XPath 已支持 / 不支持语法表

**本表已用 `scripts/golden`（真实 jsoup 1.16.2 + JsoupXpath 2.5.3）逐条验证**，不是凭文档猜测。
部分条目标注了"与 Kotlin 已知差异"，详见下一节对照表。

| 语法 / 函数 | 示例 | 支持 |
|---|---|---|
| 绝对/任意深度路径 | `//div`、`/html/body` | ✅ |
| 相对路径 / 当前节点 | `.//a`、`.` | ✅ |
| 属性取值 | `@href`、`//a/@href` | ✅ |
| `text()` | `//p/text()` | ✅（作用于上下文节点自身的直接子文本） |
| **多重谓词 `[...][...]`（连续多个）** | `//li[1][@id]`、`//li[@class='x'][@id][last()]` | ✅（依次连续过滤，语义与标准 XPath 一致：先执行的谓词在前一个谓词筛选后的集合上继续筛选，谓词顺序影响结果，已用 `testMultiPredicate*`/`testTriplePredicate*` 等 6+ 测试验证，含 golden 对照） |
| 联合运算符 `\|` | `//h1\|//p` | ✅（**与 Kotlin 已知差异**，见下表：真实结果既不去重也不按文档顺序排列） |
| 位置谓词 `[n]` | `//li[1]` | ✅ |
| `[last()]` / `[last()-n]` | `//li[last()]` | ✅ |
| `[position()>n]` 等比较 | `//li[position()>1]` | ✅（`>` `<` `>=` `<=` `=`） |
| `contains(@attr,'v')` / `contains(text(),'v')` / `contains(.,'v')` | `//p[contains(@class,'x')]` | ✅ |
| `starts-with(...)` 同上参数形式 | `//p[starts-with(text(),'x')]` | ✅ |
| 属性存在 / 比较 | `[@id]`、`[@id='x']`、`[@id!='x']` | ✅ |
| `text()='v'` / `!='v'` | `//a[text()='阅读']` | ✅ |
| 简单多条件 `and` / `or`（左右都是属性/文本比较） | `[@a='1' and @b='2']` | ✅（简单顶层拆分，不支持带括号的复杂嵌套分组） |
| `not(...)`（单独使用） | `//li[not(@class='skip')]` | ✅ |
| `following-sibling::` | `//li[@id='x']/following-sibling::li` | ✅ |
| `preceding-sibling::` | 同上反向 | ✅ |
| `parent::` / `..` | `//p/parent::div`、`//p/..` | ✅ |
| `child::`（默认轴） | `//div/child::p` | ✅ |
| `descendant::` / `ancestor::` | `//div/descendant::p` | ✅ |
| `following::` / `preceding::` | 文档顺序前后（非祖先/后代） | ✅ |
| `self::` | `//div/self::div` | ✅ |
| 通配符 `*` | `//div/*` | ✅（结果是元素节点，`asString()`=outerHtml，见「与 Kotlin 已知差异」） |
| `node()` | `//div/node()` | ✅（子节点，不做类型区分） |
| JsoupXpath 扩展 `allText()` | `//div/allText()` | ✅（所有后代文本拼接） |
| JsoupXpath 扩展 `html()` | `//div/html()` | ✅（innerHtml） |
| JsoupXpath 扩展 `outerHtml()` | `//div/outerHtml()` | ✅ |
| `count(node-set)`（**仅顶层调用**） | `count(//li)` | ✅ |
| `concat(s1,s2,...)`（顶层与谓词内均可） | `concat(//div/@a,//div/@b)`、`[concat(@a,@b)='x']` | ✅ |
| `substring(s,start,length)`（**仅三参数形式**） | `substring(//p/text(),1,5)` | ✅ |
| `substring-before(s,sep)` / `substring-after(s,sep)`（顶层与谓词内均可） | `substring-before(//p/text(),'-')` | ✅ |
| `string-length(s?)`（**仅顶层调用**） | `string-length(//p/text())` | ✅ |
| `</td>`/`</tr>`/`</tbody>` 片段自动补全 | 输入以这些结尾时自动包一层 | ✅（对齐 Kotlin `strToJXDocument`） |
| `<?xml` 输入走 XML 解析器 | | ✅ |
| **`ownText()` 作为 XPath 函数** | `//div/ownText()` | ❌ **不支持**（golden 验证：JsoupXpath 官方 NodeTest 列表没有此函数，真实结果恒为空） |
| **`normalize-space(...)`** | `//p[normalize-space(text())='x']` | ❌ **不支持**（golden 验证：真实结果是解析失败，本项目对齐为抛 `RuleEngineError.invalidXPath`） |
| **`string(...)`（顶层与谓词内）** | `string(//div)`、`[string(@id)='x']` | ❌ **不支持**（golden 验证：真实结果是解析失败，本项目对齐为抛错） |
| **`count(...)`/`string-length(...)` 用于谓词内比较** | `[count(li)=3]`、`[string-length(text())=5]` | ❌ **不支持**（顶层调用可用，但谓词内比较真实结果恒不匹配，不是语法错误；本项目对齐为"恒不匹配"而非抛错） |
| **`substring(s,start)` 两参数形式** | `substring(//p/text(),6)` | ❌ **不支持**（golden 验证：真实只认三参数形式，两参数返回 nil/解析失败） |
| **`not(...)` 与 `and`/`or` 组合** | `[not(@a='1') and position()=2]` | ❌ **不支持**（golden 验证：真实结果恒不匹配，不是语法错误；本项目对齐为"恒不匹配"） |
| **命名空间轴 `namespace::`** | | ❌ **不支持**（Jsoup DOM 无命名空间概念） |
| **`[@a='1' and (@b='2' or @c='3')]` 带括号的复杂逻辑分组** | | ❌ **不支持**（仅支持顶层单层 `and`/`or` 拆分，不解析括号分组） |
| **`sum()`/`num()`/`format-date()`** | | ❌ **不支持**（JsoupXpath 文档列出但本项目未实现，书源规则中未见实际使用，如需可后续补充） |
| **变量引用 `$var`** | | ❌ **不支持** |
| `//*[@id="x"]/*[position()>1]` 这类真实规则里出现的写法 | 采墨阁 `nextTocUrl` 规则 | ✅（`*` 通配 + position 谓词组合，已用真实规则测试验证） |

> 不支持的语法分两类：**(a) 硬性解析失败**（`normalize-space`/`string()`/两参数 `substring`）—
> 抛 `RuleEngineError.invalidXPath`，`AnalyzeByXPath` 按 Kotlin 吞异常的语义捕获后返回空值；
> **(b) 语法有效但恒不匹配**（`count`/`string-length` 谓词内比较、`not()+and/or`）—直接返回空结果，
> 不抛错，这是用 golden 实测真实 JsoupXpath 行为后得出的精确区分，而非主观假设。

## XPath 引擎与 Kotlin（真实 JsoupXpath）已知差异汇总

**以下全部用 `scripts/golden` 实测验证，每条都有对应的 golden 用例和 Swift 测试。**

| # | 点 | 真实 JsoupXpath 2.5.3 行为 | 本移植行为 | 测试 |
|---|---|---|---|---|
| 1 | 元素节点 `asString()`/`toString()` | 对纯元素节点（非 `text()` 等函数产出的文本）返回其 **outerHtml**（pretty-print 多行缩进），不是纯文本 | 完全对齐：`XPathNode.asString()`/`toStringValue()` 对 `.element` 情形返回 `outerHtml()`（已去读 JsoupXpath 源码 `JXNode.asString()` 确认：`e.toString()` 对非 `JX_TEXT` 标签元素即 outerHtml） | 所有 golden CSS/XPath 对照用例间接验证；`testRealRule_Caimoge_BookList` 等 |
| 2 | `\|` 联合运算符 | **不去重、不按文档顺序重排**：直接按"分支书写顺序 + 分支内命中顺序"拼接（不是标准 XPath 1.0 的集合并集语义） | 完全对齐，复刻这一"不完全合规范"的真实行为 | `testUnionDoesNotDedupSamePath`、`testUnionConcatenatesByBranchOrderNotDocumentOrder`、golden `unionDedup`/`unionOrderPreserved`/`unionTwoPaths` |
| 3 | `ownText()` 作为 XPath 函数 | 不存在该函数，真实结果恒为空 | 对齐：不解析为已知函数，匹配恒为空集合 | `testOwnTextFunctionIsUnsupported` |
| 4 | `normalize-space(...)` | 完全不支持，真实结果是解析失败（elementsCount=-1, getString=nil） | 对齐：抛 `RuleEngineError.invalidXPath` | `testNormalizeSpaceFunctionIsUnsupported` |
| 5 | `string(...)`（顶层/谓词内） | 完全不支持，真实结果是解析失败 | 对齐：抛 `RuleEngineError.invalidXPath` | `testStringFunctionOnElementIsUnsupported`、`testStringFunctionOnAttrIsUnsupported`、`testStringFunctionInPredicateIsUnsupported` |
| 6 | `count(...)` 顶层 vs 谓词内 | 顶层调用可用（返回正确计数）；谓词内比较 `[count(...)=n]` 不生效（解析通过但恒不匹配，不是语法错误） | 完全对齐这一"顶层可用、谓词内不可用"的精确区分 | `testCountFunctionOnList`、`testCountFunctionZeroWhenNoMatch`、`testCountFunctionInPredicateIsUnsupported` |
| 7 | `string-length(...)` 顶层 vs 谓词内 | 同上：顶层可用，谓词内比较不生效 | 完全对齐 | `testStringLengthBasic`、`testStringLengthZeroWhenMissing`、`testStringLengthInPredicateIsUnsupported` |
| 8 | `substring(s,start)` 两参数形式 | 不支持，只认三参数形式，两参数返回 nil | 对齐：两参数时抛 `RuleEngineError.invalidXPath` | `testSubstringNoLengthIsUnsupported` |
| 9 | `substring-before(s,sep)` 分隔符不存在 | 返回**原字符串**（不是 W3C 规范要求的空串，是 JsoupXpath 自身实现偏差） | 完全对齐，复刻这一偏差行为 | `testSubstringBeforeNoMatchReturnsOriginal` |
| 10 | `not(...)` 与 `and`/`or` 组合 | 不支持，解析通过但恒不匹配（不是语法错误） | 对齐：遇到该组合返回恒不匹配的谓词，不抛错 | `testNotFunctionCombinedWithAndIsUnsupported` |
| 11 | `getString`/`getStringList` 对 XPath 解析失败的处理 | Kotlin 原始签名 `getResult(rule)?.let{}`/`?.map{}` 的 `?.` 只处理 null，**不捕获异常**——解析失败会直接向上传播 | 已修正：早期版本误用 `try?` 吞掉异常（行为不对齐），现改为 `try` 直接传播，与 Kotlin 真实语义一致 | `testStringFunctionOnElementIsUnsupported`（断言 `XCTAssertThrowsError`）等 |
| 12 | `getString` 对 XPath 的 `%%` 组合符 | Kotlin 原始签名里 `getString` 只识别 `&&`/`||`，不识别 `%%`；传入含字面 `%%` 的规则时，JsoupXpath 的 ANTLR 解析器有自己的容错路径返回 `""` | **已修正对齐**：`AnalyzeByXPath.getString` 在侦测到规则含字面 `%%` 且解析失败时，专门把结果降级为 `""`（而不是抛错/返回 nil），与真实库一致 | `testXPathGetStringWithPercentReturnsEmptyString`，golden `xpath_basic/xpathPercentInterleave` 已不再需要跳过 |
| 13 | void 元素 `outerHtml()` 自闭合格式 | `<img src="...">`（无斜杠）——已读 jsoup `Element.java:1737-1744` 源码确认：HTML 语法下 `isEmpty` 标签只输出 `>` | SwiftSoup 2.9.6 源码 `Element.swift` 的 `outerHtmlHead` 把 if/else 两个分支都错写成了自闭合 `" />"`（库自身的移植缺陷） | **Step4-A 已彻底修复**：不再依赖字符串后处理（原 `SwiftSoupVoidElementFix` 已删除），`JsoupCompatSerializer` 从零按 jsoup `Tag.java` 的 `emptyTags` 清单重新生成标签输出，void 标签天然不带斜杠；应用在 CSS `@html`/`@all`、XPath `html()`/`outerHtml()`/元素节点 `asString()` 全部输出口 | `VoidElementFixTests.swift`（端到端用例）+ golden `serializer_synthetic.json` 多个 void 元素/图文混排用例 |
| 14 | `&nbsp;`（U+00A0）在 `text()`/`ownText()`/`allText()` 规整中的处理 | jsoup `StringUtil.isActuallyWhitespace` 特意把 `&nbsp;` 纳入"可折叠空白"（源码注释："Not in the spec but expected"），前导/尾随/连续 nbsp 会被裁剪或折叠成单个空格，等同普通空白 | SwiftSoup 2.9.6 的空白判定只认标准空白（空格/Tab/换行/换页/回车），遗漏了这个 jsoup 特有扩展，导致含 `&nbsp;` 的文本前导空白不会被裁剪 | **已修正**：`SwiftSoupTextNormalizeFix`（纯文本提取路径）+ `JsoupCompatSerializer.escape()`（HTML 序列化路径，各自独立复刻，职责边界见 `SwiftSoupTextNormalizeFix.swift` 顶部注释），应用在 CSS `@text`/`@ownText`/`@textNodes`/`@html`/`@all`、XPath `text()`/`allText()`/`html()`/`outerHtml()` 全部文本与序列化输出口 | golden `malformed_html/htmlEntities_text` + `serializer_synthetic/entityNbsp_*` |
| 15 | `<br>` 后文本节点在 pretty-print 输出里的换行缩进 | jsoup `TextNode.outerHtmlHead` 有一条专门规则：`siblingIndex > 0 && 前一个兄弟节点是 <br>` 时换行缩进（源码注释 "special case wrap on inline `<br>` - doesn't make sense as a block tag"），缩进深度取决于该文本节点在完整 DOM 树中的真实嵌套深度 | SwiftSoup 的 `TextNode.outerHtmlHead` 移植遗漏了这整条分支（以及同方法里的 trimLeading/trimTrailing/couldSkip 逻辑） | **Step4-A 已彻底修复**：字符串级后处理（原 `SwiftSoupBrIndentFix`）已被证明不可靠并删除。`JsoupCompatSerializer` 改为自己做深度优先遍历，`depth` 参数是遍历时天然维护的真实树深度（不是从字符串猜测），完整复刻 `TextNode.outerHtmlHead` 的该分支及 trimLeading/trimTrailing/couldSkip 逻辑 | golden `malformed_html/brSeparatedContent_html`/`brSeparatedContent_outerHtml`/`consecutiveBr_bodyOuterHtml`、`xpath_real_caimoge/realBookList` 的 `knownDivergences` 豁免已全部删除，改为严格比较；`GoldenComparisonTests.knownDivergences` 现为空集合 |

> 以上 15 条全部来自 golden 真实对照，**不是主观猜测**；Step4-A 彻底重写 HTML 序列化后，第 13/14/15 条
> 已从"已知差异/已尝试修复但回退"升级为"彻底修复"，不再需要任何 `knownDivergences` 豁免。

## golden 对照（CI 自动生成，不需要本地跑任何东西）

`scripts/golden/` 是一个独立的 Maven 项目：
- 依赖 `org.jsoup:jsoup:1.16.2`（用 `dependencyManagement` 强制锁定，与 legado 的 `libs.versions.toml`
  一致）和 `cn.wanghaomiao:JsoupXpath:2.5.3`（legado 实际使用的版本）。
- `src/main/java/golden/`：`RuleAnalyzer.java`/`AnalyzeByJSoup.java`/`AnalyzeByXPath.java` 是
  对应 Kotlin 源文件的逐函数 Java 移植（调用真实 jsoup/JsoupXpath API，不是另一套实现），
  `Main.java` 读取 `cases/*.json` 用例清单，对每条 CSS/XPath 规则在对应 HTML 上跑出真实结果，
  写到 `golden/*.json`（含用到的 HTML 全文，避免 Swift 侧还要读取其它路径）。
- CI `.github/workflows/test.yml` 的 `golden` job（`ubuntu-latest`）：`setup-java` + `mvn package` 编译、
  运行生成 `*.json`，若 Maven 下载失败、Java 运行失败、或一条用例都没生成，job 直接失败（不允许跳过）；
  产物作为 artifact 上传。`test-macos`/`test-ios-simulator` 两个 job 都 `needs: golden`，
  会先下载 artifact 到 `Tests/LegadoHTMLEngineTests/Resources/golden/` 再跑 `swift build`/`xcodebuild test`。
- `Tests/LegadoHTMLEngineTests/GoldenComparisonTests.swift`：`testAllGoldenCssCases`/`testAllGoldenXPathCases`
  两个测试方法，读取 golden 目录下所有 `*.json`，对每条用例的 `elementsCount`/`getString`/`getStringList`/
  `getString0` 逐项比较 Java 与 Swift 的结果；**不一致时不静默放过**，`XCTFail` 的信息包含
  「规则 / 输入(HTML) / Java 结果 / Swift 结果」四项，已知且登记过的差异（`knownDivergences`）除外。
- 覆盖范围：`cases/css_basic.json`（全部 CSS 语法、全部结果类型、`&&`/`||`/`%%`）、
  `cases/xpath_basic.json`（全部已支持 XPath 语法、`|`/`not()`/字符串函数、多重谓词）、
  `cases/css_real_xiaoshuo2016.json`/`cases/xpath_real_caimoge.json`（两个真实书源的真实规则）、
  `cases/malformed_html.json`（未闭合标签等 jsoup 容错场景）、
  `cases/serializer_synthetic.json`（Step4-A 新增：66 个合成 HTML 样本 × 4 种序列化结果类型
  `@html`/`@all`/XPath `html()`/`outerHtml()` = 264 条用例，专门验证 `JsoupCompatSerializer`
  与真实 jsoup 逐字节对齐，详见上方「Step4-A：HTML 序列化重写」章节）。
  共 6 个用例文件、约 400+ 条用例（随用例文件持续增长，以 `scripts/golden/cases/*.json` 实际内容为准）。

## 真实书源规则扫描清单（测试用例来源）

扫描 `Tests/LegadoBookSourceTests/Resources/test_bookSources.json`（第 1 步提供）、
`Tests/LegadoRuleEngineTests/Resources/real/{muli,qimo}_real_source.json`（第 2 步用户提供）后，
用于本步骤测试的真实 CSS / XPath 规则汇总（完整清单见 `Tests/LegadoHTMLEngineTests/Resources/real/*.json`）：

- **CSS（🔥小说2016）**：`@css:.name@text`、`@css:p:eq(2)>a@text`、`@css:li.clearfix`、
  `@css:.name>a@href`、`@css:img@src`、`@css:.note.clearfix p@text`、`@css:.note_text,p:eq(4)@text`、
  `@css:p:eq(3)@text`、`.articleDiv p@textNodes`。
- **XPath（🔥采墨阁手机版）**：`//dd[2]/text()`、`//*[@id="sitebox"]/dl`、`//dt/a/@href`、`//img/@src`、
  `//dd[2]/span/text()`、`//h3/a/text()`、`//*[@property="og:novel:author"]/@content`、
  `//*[@property="og:image"]/@content`、`//*[@property="og:description"]/@content`、
  `//*[@property="og:novel:category"]/@content`、`//*[@id="newlist"]//li[1]/a/text()`、
  `//*[@property="og:novel:book_name"]/@content`、`//a[text()="阅读"]/@href`、
  `//*[@id="pagelist"]/*[position()>1]/@value`、`//*[@id="content"]`。
- 木里番茄 / 七猫小说（第 2 步真实书源）未见 CSS/XPath 规则（分别用 JS 和 JSONPath），故第 3 步真实规则
  以上述两个书源为准，符合任务要求「用两个真实书源里扫描出来的 CSS/XPath 规则各写至少 10 个用例」。

## 样本诚实标注（第 3 步）

- 所有合成 HTML 测试数据：文件内/测试方法注释均以 `⚠️ 合成样本，非真实数据` 标注；
  `Tests/LegadoHTMLEngineTests/AnalyzeByJSoupTests.swift`、`AnalyzeByJSoupTests2.swift`、
  `AnalyzeByXPathTests.swift` 文件头注释统一声明。
- 真实规则文本：`Tests/LegadoHTMLEngineTests/Resources/real/xiaoshuo2016_rules.json` 与
  `caimoge_rules.json`，文件内 `_SAMPLE_KIND` 字段与对应测试方法注释均标注「规则真实、数据合成」，
  并注明规则来源（`test_bookSources.json` 中的具体书源名）。
- 本步骤未收到用户提供的真实网页响应文件，因此**不存在** `Resources/real/*.html` 类真实网页数据；
  凡涉及真实规则的测试均搭配合成 HTML，已如实标注，未冒充为真实抓取数据。

## 崩溃写法审计（第 3 步新增代码）

```
rg -n "fatalError|try!|\bas!" Sources/LegadoBookSource/RuleEngine/AnalyzeByJSoup*.swift \
   Sources/LegadoBookSource/RuleEngine/SwiftSoupXPath*.swift Sources/LegadoBookSource/RuleEngine/XPathEvaluator.swift
# 结果：无命中
```
新增错误类型 `RuleEngineError.invalidSelector` / `.invalidXPath` / `.invalidHTML`，
CSS 选择器解析失败、XPath 语法不支持（硬性失败类，见上表分类 a）均抛这些错误，public 方法标 `throws`；
`AnalyzeByXPath.getString`/`getStringList` 对 `getResult` 失败**直接传播异常**（对齐 Kotlin
`getResult(xPath)?.let{}`/`?.map{}` 的 `?.` 只处理 null、不捕获异常的真实语义——开发中一度误用
`try?` 吞掉异常，已改正，见上方「XPath 引擎已知差异」表第 11 条）；"语法有效但恒不匹配"类
（见上表分类 b）返回空结果，不抛错。

## 第 3 步 + 累计测试规模与 CI（最新，含实测输出）

- AnalyzeByJSoup：`AnalyzeByJSoupTests.swift`（34）+ `AnalyzeByJSoupTests2.swift`（33，含真实规则用例与
  SwiftSoup Elements bug 的回归测试）；AnalyzeByXPath：`AnalyzeByXPathTests.swift`（52）+
  `AnalyzeByXPathTests2.swift`（39，`|`/`not()`/字符串函数/多重谓词）；`HTMLEnginePublicAPITests.swift`（4）；
  `GoldenComparisonTests.swift`（2，内部逐条比较 138 条 golden 用例）。
  第 3 步小计 164，连同第 1、2 步共 **293 个测试**。
- CI（`.github/workflows/test.yml`）三个 job：
  - **golden**（`ubuntu-latest`）：Maven 编译 + 运行，生成真实 jsoup/JsoupXpath 对照数据，失败则整体失败。
  - **test-macos**（`needs: golden`）：下载 golden artifact，`verify_fields.py`/`verify_functions.py`，
    `swift build` + `swift test`（macOS，swift 5.10）。
  - **test-ios-simulator**（`needs: golden`）：同样下载 golden artifact 后，`xcodebuild test`，
    脚本 `scripts/ios_sim_test.sh` 固定 scheme `LegadoBookSource`、自动挑可用 iPhone 模拟器、
    统计并打印实际执行的测试总数（为 0 则失败）。
  - 已去掉 Linux job（SwiftSoup/XPath 目标平台仅 iOS 15+ / macOS 本地开发）。
- **最近一次绿色运行**（commit `c7a67e1`，run 36796820710，三个 job 均 success）：
  - golden job：生成 4 个用例文件，共 138 条用例。
  - macOS job：`Test Suite 'All tests' passed`，`Executed 293 tests, with 0 failures (0 unexpected)`。
  - iOS 模拟器 job：`** TEST SUCCEEDED **`，`ios_sim_test.sh` 统计「实际执行的测试总数: 293」，`xcodebuild` 退出码 0。

## 后续步骤（TODO）

源码中以 `TODO(后续步骤)` 标注：BaseSource/BaseBook 运行时方法、Book/BookChapter/SearchBook 业务方法、变量存取、`ReadConfig.startDate` 的 LocalDate 强类型化、SwiftData/GRDB 持久化接入。
第 3 步之后仍未做：`AnalyzeRule` 总调度（把 Regex/JSONPath/JSoup/XPath 四个后端按 Mode 统一调度）、JS 引擎、网络、UI。


# 第 4 步 B：AnalyzeRule 总调度 + JS 引擎

本节记录 Step4-B 的移植：`AnalyzeRule`（规则总调度）、JS 引擎（JavaScriptCore）、
`NetworkUtils`、`unescapeHtml4`、`replaceRegex`、依赖注入协议。对应 Kotlin
`model/analyzeRule/AnalyzeRule.kt`（973 行）及其工具依赖。

## 已实现内容

- **AnalyzeRule 主体**：`getString`（3 重载）、`getStringList`（2 重载）、`getElement`、
  `getElements`、`splitSourceRule` / `SourceRule`（Mode 判定：XPath/Json/Default/Js/Regex/WebJs；
  前缀 `@CSS:`/`@@`/`@XPath:`/`@Json:` 大小写不敏感；`$.`/`$[` 判 JSON；`/` 判 XPath；
  allInOne 下 `:` 前缀判 Regex；`{{ }}` 内联、`@get:{}`、`@put:{}`、`$1~$99` 组反向引用、
  `##`/`###` 切分 replaceRegex/replacement/replaceFirst）、`putRule`/`splitPutRule`、
  `replaceRegex`、`compileRegexCache`、缓存（stringRuleCache、regexCache 容量 16、
  scriptCache 容量 16）、`setContent`（含 `isJSON` 判定）、`setBaseUrl`、`setRedirectUrl`、
  `getAnalyzeByXPath/JSoup/JSonPath`（`o != content` 新建、否则缓存复用）、put/get 四层
  回退链（chapter→book→ruleData→source）、`setChapter/setNextChapterUrl/setRuleData` 等 setter。
- **JS 引擎（JavaScriptCore）**：`evalJS` 绑定键名与 Kotlin 完全一致（java、cookie、cache、
  source、book、result、baseUrl、chapter、title、src、nextChapterUrl、rssArticle、fromBookInfo）。
  `java` 对象用 **Proxy 包裹**：AnalyzeRule 自有方法（put/get/getString/getStringList/
  getElement/getElements/ajax/log/getSource/getTag）直通；JsExtensions 的 67 个方法
  （见 `JsExtensionsCatalog.swift`，正则自动提取）调用时**抛明确 JS 错误
  「java.xxx 尚未实现（JsExtensions，第 5 步）」并记 diagnostics**，不静默返回 undefined。
- **NetworkUtils**：`getAbsoluteURL`（String base / JavaURL base 两重载）、`isAbsUrl`、
  `isDataUrl`、`getBaseUrl`。URL 相对解析按 **java.net.URL 算法自实现**（`JavaURLResolver.swift`），
  不用 Swift Foundation URL 拼接（见下「与 Kotlin 已知差异」）。
- **unescapeHtml4**：自实现，含 252 条 HTML4 命名实体表（`HtmlEntities.swift`，源自 CPython
  `html.entities.name2codepoint`）、十进制 `&#123;`、十六进制 `&#xAB;`，无分号实体不还原
  （对齐 commons-text LookupTranslator）。
- **依赖注入协议 + 内存默认实现**：`RuleDataStore`（含 >=10000 字符走 big variable 分支）、
  `BookData`、`ChapterData`、`SourceVariableStore`、`AjaxProvider`（默认返回错误串）、
  `WebJSProvider`（默认抛 `.unsupported`）、`CookieStoreProtocol`、`CacheManagerProtocol`。

## RuleValue：Kotlin `Any?` → Swift 动态类型映射表

AnalyzeRule 调度过程中的中间值（Kotlin 的 `Any?`）用 `RuleValue` 枚举表达：

| Kotlin 类型 | RuleValue case |
|---|---|
| `String` | `.string` |
| `List<String>` / `ArrayList<String>` | `.stringList` |
| org.jsoup `Element` | `.element` |
| org.jsoup `Elements` / `List<Node>` | `.elements` |
| JsoupXpath `JXNode` / `List<JXNode>` | `.xpathNodes` |
| Jayway JSON 读取结果（对象/数组/标量） | `.json`（`JSONValue`） |
| Rhino `NativeObject` / JS 对象 | `.jsObject`（键值 map） |
| Gson `LinkedTreeMap<*,*>` | `.jsonObject`（键值 map，直接按键取值） |
| JS 数字 / 布尔 | `.number` / `.bool` |
| `null` | `.null` |

## JS 值 → RuleValue 转换表

| JavaScriptCore JSValue | RuleValue |
|---|---|
| string | `.string` |
| number | `.number`（Double） |
| boolean | `.bool` |
| array | `.stringList`（元素逐个字符串化） |
| object | `.jsObject`（键值浅转换） |
| null / undefined | `.null` |

## Rhino（Kotlin）vs JavaScriptCore（本移植）已知差异

| 主题 | Rhino（Kotlin） | JavaScriptCore（本移植） | 处理 |
|---|---|---|---|
| **Java 互操作** | 支持 `Packages.xxx`、`importClass`、`importPackage`、`org.jsoup.Jsoup.parse`、`java.lang.String`、`JavaImporter` | **不存在**，无法运行 | 预检测这些标记，命中即抛 `RuleEngineError.jsError` + 记 diagnostics；**不假装支持**。真实书源「魔丸小说」「爱丽丝书屋」用到，端到端测试断言抛错 |
| **整数值 Double→String** | `Double.toString()`：`1.0` → `"1.0"`（Rhino 对整数值 Double 的 `+` 字符串化规则有特例） | `Number→String`：`1` → `"1"` | AnalyzeRule.makeUpRule 对 `{{ }}` 内 JS 结果 `Double%1==0` 用 `String.format("%.0f")` 强制整数输出，**已对齐**（见 `testInline_jsExpr`）。但直接 `evalJS("1+1").stringValue` 本移植返回 `"2.0"`（RuleValue.number 整数带 .0），**与 Rhino 的裸求值字符串化可能不同**，标注差异 |
| **ES 版本** | Rhino 默认 ES5 + 部分 ES6 | JSC 支持现代 ES（含 ES2020+、Proxy、let/const、箭头函数等） | 现代语法在 JSC 可用而 Rhino 可能不可用；**未验证**是否有真实书源依赖 Rhino 特有的旧行为 |
| **`result` 复杂对象绑定** | 直接把 Kotlin 对象（Element/NativeObject）绑给 JS | 本移植把复杂 RuleValue 以**字符串化**后绑定 | 简化；JS 里对 `result` 做 DOM 操作的规则无法工作（属 Java 互操作范畴，同上抛错） |

## NetworkUtils：java.net.URL vs Swift URL 已知差异（本步骤待 C 部分 golden 验证）

Kotlin 用 `java.net.URL(base, relative)` 做相对解析。本移植**不用** Swift
`URL(string:relativeTo:)`（二者在 `../`、`//host`、`?`/`#` 开头相对、空相对、含空格/中文
未转义字符上行为不同），改为按 java.net.URL / RFC 3986 的算法自实现（`JavaURLResolver.swift`）：

- 空 relative → 结果 = base（保留 ref）
- `#frag` 开头 → 仅换 ref
- `//host` 开头 → 换 authority
- `/path` 开头 → 绝对路径（保留 base authority）
- `?query` 开头 → 保留 base path，换 query
- 相对路径 → 基于 base 目录拼接 + `.`/`..` 规范化（`remove_dot_segments`）
- 同协议 `scheme:rel` → 去 scheme 当相对处理；异协议 → 作为独立绝对 URL
- java **不**对 path 做百分号编码，原样保留空格/中文

> ⚠️ **本步骤为「按理解实现」**，最终正确性由 **C 部分 golden（真实 java.net.URL 对照，
> 至少 60 例）** 验证。可能的边角差异：含未转义空格/中文时 java 的具体输出、`file:`/无
> authority scheme、连续 `//` 的 path、越过根的 `..` 处理细节。这些在 C 部分核对修正。

## replaceRegex：Java/Kotlin 正则 vs ICU（NSRegularExpression）已知差异

替换模板转换见 `RegexTemplate.javaToICU`：`$1..$9` 组引用保留；`\$` 字面 $；`\\` 字面 \；
`$` 后非数字转义为 `\$`。匹配侧（NSRegularExpression 用 ICU 正则）与 Java 正则的已知差异：

| 特性 | Java 正则 | ICU（NSRegularExpression） |
|---|---|---|
| 占有量词 `X++` `X*+` `X?+` | 支持 | **不支持**（会报错或语义不同） |
| `\h` `\v`（水平/垂直空白） | 支持 | 支持（ICU 也有，但语义可能略异） |
| `\Z`（输入末尾，允许最终换行） | 支持 | ICU 用 `\Z`/`\z`，语义基本一致 |
| 命名组 `(?<name>...)` / `\k<name>` | 支持 | 支持（语法一致） |
| 内嵌标志作用域 `(?i)` | 影响其后 | ICU 行为基本一致 |
| 替换模板 `${name}` | 支持命名组引用 | **不支持 ${name}**，只支持 `$n` |

> ⚠️ 最终由 **C 部分 golden（至少 50 例）** 验证。

## unescapeHtml4：commons-text vs 本移植已知差异（待 C 部分 golden 验证）

- 命名实体表来自 CPython `html.entities.name2codepoint`（252 条，HTML4 命名实体集）。
  commons-text 1.13.1 的 `EntityArrays` 并集理论上与之一致，但**个别冷门实体或大小写变体
  可能有出入**，待 golden 核对。
- 无分号命名实体（`&amp` 不带 `;`）**不还原**（对齐 commons-text LookupTranslator 键带分号）。
- 数字实体要求分号（`&#65;` 可，`&#65` 不还原），对齐 commons-text NumericEntityUnescaper 默认。
- 超出 Unicode 范围 / 无效 scalar 的数字实体：本移植**原样保留**；commons-text 行为待核对。

> ⚠️ 最终由 **C 部分 golden（至少 40 例）** 验证。

## 本步骤明确排除（后续 TODO）

- `reGetBook` / `refreshTocUrl`：依赖 WebBook，**留桩抛 `.unsupported`**（第 6 步）。
- JsExtensions 的 67 个方法体（见 `JsExtensionsCatalog.swift` 与 `JS_EXTENSIONS_USAGE.md`）：第 5 步。
- 真实网络（AnalyzeUrl / ajax 真实请求）：第 6 步。
- 真实 WebView（WebJs / BackstageWebView / `java.webView`）：第 5/6 步。
- WebBook/BookList/BookInfo/BookChapterList/BookContent 流程、AnalyzeUrl：后续步骤。
- Kotlin 协程上下文（`setCoroutineContext`）：Swift 无对应协程模型，排除。

## 样本诚实标注（第 4 步 B）

- 合成样本：`Tests/LegadoAnalyzeRuleTests/` 内除标注「真实规则」外，所有 HTML/JSON/规则文本
  均为合成（测试注释标「合成样本，非真实数据」）。
- 真实规则 + 合成数据：端到端测试（`AnalyzeRuleEndToEndTests`）用 `配置文件_7个.json` 里的
  **真实书源规则文本**，输入响应为合成数据，每个用例注释标「规则真实、数据合成」及来源书源名
  （淘小说书城/速读谷/得奇小说网/笔趣阁345/得间小说/魔丸小说/爱丽丝书屋）。

## java.xxx 使用情况表

见 `JS_EXTENSIONS_USAGE.md`（7 个真实书源实际调用的 `java.xxx` 方法 + 次数 + 已/未实现状态 +
Java 互操作标记 + 第 5 步实现优先级）。
