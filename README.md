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

| 方法 / 行为 | jsoup 1.16.2 | SwiftSoup 2.9.6 | 影响与应对 |
|---|---|---|---|
| `Elements.addAll(Collection)` / `clear()` | `clear()` 只清空集合，不碰 DOM | **无 `addAll`/`clear`**；`empty()` 存在但语义是"清空每个元素的子节点"（会改 DOM，完全不是"清空集合"！） | 本移植用内部扩展 `addElements(_:)` 包装批量添加；**不提供、也不使用**任何"clear 集合"包装——开发中一度错误地用 `empty()` 模拟 `clear()` 导致真实 bug（见下方专门记录），现已改为直接用新 `Elements()` 替换变量，`SwiftSoupElementsCompat.swift` 里保留了该教训的说明注释 |
| `getElementsContainingOwnText(text)` | 存在，匹配元素自身直接文本包含 text | 存在，签名一致（`throws`） | 无差异 |
| `textNodes()` | 返回直接子 `TextNode` 列表 | 同 | 无差异 |
| `ownText()` | 返回元素自身文本（不含子元素），非 throwing | 同，非 throwing | 无差异 |
| `outerHtml()` / `html()` | 抛检查异常（Java 少见但 Kotlin 侧不特殊处理） | `throws`（Swift 强制处理） | 本移植统一用 `try?` 吞掉转空字符串，不影响正常路径结果 |
| `text()` 的空白规整 | 默认 `trimAndNormaliseWhitespace = true`，合并连续空白为单个空格 | 同样默认 `true`（`text(trimAndNormaliseWhitespace: Bool = true)`） | 无差异（本移植未显式传 false，行为一致） |
| `Collector.collect(Evaluator.Id(id), el)` | 存在 | 存在，API 形态一致 | 无差异 |
| 中文 / emoji 解析 | 按 UTF-16 处理属性/选择器字符串（JVM String） | Swift `Character`/`UInt16` 混用；本移植所有下标逻辑改在 UTF-16 code unit 上处理 | 已通过含中文/emoji 的测试验证一致 |

> 若后续实测发现与 jsoup 1.16.2 的其它差异，会在此表继续补充；**目前测试覆盖范围内未发现差异**。

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
判断——**`:eq(n)` 匹配的是"该元素在其父节点所有子节点（不分标签）中的兄弟序号"**，
而不是"在同标签匹配集合里的第 n 个"。这不是 SwiftSoup 与 jsoup 的差异（两者行为一致，
都是标准 CSS 选择器语义），纯粹是移植过程中构造测试用合成 HTML 时的认知错误，已按正确语义
重新设计 `Tests/LegadoHTMLEngineTests/AnalyzeByJSoupTests2.swift` 里 `xiaoshuo2016SearchHTML`
的 DOM 结构（让 `<li>` 的直接子节点顺序与真实规则 `p:eq(2)>a`/`p:eq(3)`/`p:eq(4)` 期望的兄弟位置一致）。

## XPath 已支持 / 不支持语法表

| 语法 / 函数 | 示例 | 支持 |
|---|---|---|
| 绝对/任意深度路径 | `//div`、`/html/body` | ✅ |
| 相对路径 / 当前节点 | `.//a`、`.` | ✅ |
| 属性取值 | `@href`、`//a/@href` | ✅ |
| `text()` | `//p/text()` | ✅（作用于上下文节点自身的直接子文本） |
| 位置谓词 `[n]` | `//li[1]` | ✅ |
| `[last()]` / `[last()-n]` | `//li[last()]` | ✅ |
| `[position()>n]` 等比较 | `//li[position()>1]` | ✅（`>` `<` `>=` `<=` `=`） |
| `contains(@attr,'v')` / `contains(text(),'v')` | `//p[contains(@class,'x')]` | ✅ |
| `starts-with(...)` | `//p[starts-with(@class,'x')]` | ✅ |
| `normalize-space(...)` | `//p[normalize-space(text())='x']` | ✅ |
| 属性存在 / 比较 | `[@id]`、`[@id='x']`、`[@id!='x']` | ✅ |
| `text()='v'` / `!='v'` | `//a[text()='阅读']` | ✅ |
| 多条件 `and` / `or` | `[@a='1' and @b='2']` | ✅（简单顶层拆分，不支持带括号的复杂嵌套分组） |
| `following-sibling::` | `//li[@id='x']/following-sibling::li` | ✅ |
| `preceding-sibling::` | 同上反向 | ✅ |
| `parent::` / `..` | `//p/parent::div`、`//p/..` | ✅ |
| `child::`（默认轴） | `//div/child::p` | ✅ |
| `descendant::` / `ancestor::` | `//div/descendant::p` | ✅ |
| `following::` / `preceding::` | 文档顺序前后（非祖先/后代） | ✅ |
| `self::` | `//div/self::div` | ✅ |
| 通配符 `*` | `//div/*` | ✅ |
| `node()` | `//div/node()` | ✅（子节点，不做类型区分） |
| JsoupXpath 扩展 `allText()` | `//div/allText()` | ✅（对齐 Jsoup `text()` 语义：所有后代文本拼接） |
| JsoupXpath 扩展 `ownText()` | `//div/ownText()` | ✅ |
| JsoupXpath 扩展 `html()` | `//div/html()` | ✅（innerHtml） |
| JsoupXpath 扩展 `outerHtml()` | `//div/outerHtml()` | ✅ |
| `</td>`/`</tr>`/`</tbody>` 片段自动补全 | 输入以这些结尾时自动包一层 | ✅（对齐 Kotlin `strToJXDocument`） |
| `<?xml` 输入走 XML 解析器 | | ✅ |
| **命名空间轴 `namespace::`** | | ❌ **不支持**（Jsoup DOM 无命名空间概念，JsoupXpath 文档也标注不支持） |
| **`[@a='1' and (@b='2' or @c='3')]` 带括号的复杂逻辑分组** | | ❌ **不支持**（仅支持顶层单层 `and`/`or` 拆分，不解析括号分组） |
| **数值/字符串函数**（`concat()`、`substring()`、`string-length()`、`count()`、`sum()` 等） | | ❌ **不支持** |
| **多重谓词的复合轴表达式**（如 `//a[1][@href]` 连续多个 `[]`） | | ❌ **不支持**（本实现每个 step 只解析一组 `[...]`，多个方括号会被当成单个谓词文本解析失败） |
| **变量引用 `$var`** | | ❌ **不支持** |
| `//*[@id="x"]/*[position()>1]` 这类真实规则里出现的写法 | 采墨阁 `nextTocUrl` 规则 | ✅（`*` 通配 + position 谓词组合，已用真实规则测试验证） |

> 不支持的语法在解析阶段抛 `RuleEngineError.invalidXPath`，`AnalyzeByXPath` 按 Kotlin 吞异常的语义
> 捕获后返回空值，并记入可选的 `RuleEngineDiagnostics`。

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
CSS 选择器解析失败、XPath 语法不支持、HTML 解析失败均抛这些错误，public 方法标 `throws`；
`AnalyzeByXPath.getString/getStringList` 里 `getResult` 失败（对齐 Kotlin `getResult(xPath)?.let{}` 的
`null` 分支）保持返回空值/nil，同时记入可选的 `RuleEngineDiagnostics`。

## 第 3 步 + 累计测试规模与 CI（最新，含实测输出）

- AnalyzeByJSoup：`AnalyzeByJSoupTests.swift`（34）+ `AnalyzeByJSoupTests2.swift`（33，含真实规则用例与
  两个 SwiftSoup Elements bug 的回归测试）；AnalyzeByXPath：`AnalyzeByXPathTests.swift`（52）；
  `HTMLEnginePublicAPITests.swift`（4）。第 3 步小计 123，连同第 1、2 步共 **252 个测试**。
- CI（`.github/workflows/test.yml`）两个 job，均含 `verify_fields.py` + `verify_functions.py`：
  - **test-macos**：`swift build` + `swift test`（macOS，swift 5.10）。
  - **test-ios-simulator**：`xcodebuild test`，脚本 `scripts/ios_sim_test.sh` 固定 scheme
    `LegadoBookSource`、自动挑可用 iPhone 模拟器、统计并打印实际执行的测试总数（为 0 则失败）。
  - 已去掉 Linux job（SwiftSoup/XPath 目标平台仅 iOS 15+ / macOS 本地开发）。
- **最近一次绿色运行**（commit `61fcb77`，run 36758479905）：
  - macOS job：`Executed 252 tests, with 0 failures (0 unexpected)`。
  - iOS 模拟器 job：`conclusion: success`（同样跑全部 252 个测试，`ios_sim_test.sh` 统计通过）。

## 后续步骤（TODO）

源码中以 `TODO(后续步骤)` 标注：BaseSource/BaseBook 运行时方法、Book/BookChapter/SearchBook 业务方法、变量存取、`ReadConfig.startDate` 的 LocalDate 强类型化、SwiftData/GRDB 持久化接入。
第 3 步之后仍未做：`AnalyzeRule` 总调度（把 Regex/JSONPath/JSoup/XPath 四个后端按 Mode 统一调度）、JS 引擎、网络、UI。
