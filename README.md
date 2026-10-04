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
> ⚠️ **第 4 步 C golden 修正**：上表标「❌ 不支持」的过滤器多条件 `&&`/`||`/`=~`/`in`、聚合函数
> `min/max/avg/sum`、逗号多下标 `[0,2]`、步长切片 `[0:6:2]`、`@` 作顶层根——经真实 Jayway 2.10.0
> 跑 golden 确认**真实 Jayway 其实支持**（返回真实结果，不报错）。本项目自实现子集
> `DefaultJSONPathEvaluator` 仍不支持这些（抛 `unsupportedSyntax` 吞成空），故它们属**本项目子集与
> 真实 Jayway 的已知差异**，逐条记在下方「第 4 步 C」章节的差异表（附真实 Jayway 结果 + 影响面）。
> 书源规则里这些高级语法几乎不出现。
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
| 8 | 浮点 `toString` | Java `Double.toString`（最短往返；NaN/Infinity 大小写、科学计数阈值/`E` 格式） | `JavaDoubleFormat` 用 Swift 最短往返数字重排成 Java 格式 | ✅ Rhino 1.8.1 golden 已验证整数/小数/负数/大数/NaN/Infinity；极端次正规数未覆盖，见第4步 JS 对照说明 |
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
  Step 5 收尾后又新增 `js_ext_cases.json`（321 条）、`jsoup_cases.json`（91 条）、`js_number_args.json`（42 条）
  与 `javaDigestCases`（2 条）；第 6 步新增 `url_codec_cases.json`（299）、`url_option_cases.json`（84）、
  `analyze_url_cases.json`（94）、`cookie_cases.json`（47）、`http_url_cases.json`（170）、
  `charset_cases.json`（240）、`request_cases.json`（43）、`redirect_cases.json`（44）、
  `request_cookie_cases.json`（13）、`auto_header_cases.json`（4）。
  **当前共 22 个用例文件**（以 `scripts/golden/cases/*.json` 与 CI `golden` job 输出为准）。

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

## 后续步骤（第 3 步当时的历史记录，现状见文末）

源码中以 `TODO(后续步骤)` 标注：BaseSource/BaseBook 运行时方法、Book/BookChapter/SearchBook 业务方法、变量存取、`ReadConfig.startDate` 的 LocalDate 强类型化、SwiftData/GRDB 持久化接入。
第 3 步之后仍未做：`AnalyzeRule` 总调度（把 Regex/JSONPath/JSoup/XPath 四个后端按 Mode 统一调度）、JS 引擎、网络、UI。

> **现状（第 6 步后）**：`AnalyzeRule` 总调度、JS 引擎、真实网络均已实现（第 4/5/6 步）；
> 未实现的只剩 WebView 分支、`dnsIp` 直连，以及 SwiftData/GRDB 持久化、UI。


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
  > **注**：该报错文案是第 4 步 B 的记录；第 5 步已实现 67 个方法体，
  > 第 6 步又把 `analyzeRule` 的默认 provider 换成真实实现（见 6B 小节）。
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
| **Java 互操作** | 支持 `Packages.xxx`、`importClass`、`importPackage`、`org.jsoup.Jsoup.parse`、`java.lang.String`、`JavaImporter` | **不存在**，无法运行 | 预检测命中即抛 `RuleEngineError.jsError` + 记 diagnostics；真实书源仅「台湾小说网」「爱丽丝书屋」命中。端到端测试断言抛错，不假装支持 |
| **Rhino Double→String** | `evalJS` 返回 raw；`getString` 最终走 Java `toString()`：`2.0`→`"2.0"`、`1e21`→`"1.0E21"`、NaN/Infinity 保留大小写 | `RuleValue.number.stringValue` 用 `JavaDoubleFormat` 重排 JSC Double 最短往返数字 | ✅ 真实 Rhino 1.8.1 golden 对整数/小数/负数/大数/NaN/Infinity 已对齐。inline `{{}}` 仍按 Kotlin 原码仅对整数 Double 用 Locale.ROOT `"%.0f"`（`2.0`→`"2"`） |
| **Rhino Integer 包装类型** | 少数表达式返回 Java `Integer`（golden 最小复现：`0`/`0.0`、`'hello'.length`、`JSON.parse('{\"k\":7}').k`），`toString()` 无 `.0` | JSC 公共 API 统一暴露 Number/Double，无法恢复 JVM 包装类型，同值输出 `.0` | 已知差异；4 条逐名登记在 `JSRhinoGoldenComparisonTests.integerWrapperDivergences`，inline `{{}}` 路径结果仍一致 |
| **Rhino NativeArray raw.toString** | Java `Object.toString()` 结果为 `org.mozilla.javascript.NativeArray@<identity>`，hash 每次运行不同 | JSC 转为稳定元素列表描述 | 根本不可逐字节复现；数组 raw case 显式登记。数组在 JS 内部的稳定字符串化（`join`、`String(array)`、`JSON.stringify`）继续严格对照 |
| **NativeObject.toString** | 普通对象为 `[object Object]` | `.jsObject.stringValue` 同样返回 `[object Object]` | ✅ 已对齐 |
| **inline `{{}}` 嵌套 `}}`** | legado 的 `\{\{[\w\W]*?\}\}` 同样会在片段内部首个连续 `}}` 提前结束 | Swift 逐行移植相同正则 | `JSON.stringify({a:{b:[1,2]}})` 只在 evalJS/getString 路径严格比较；inline case 登记为共同解析器限制 |
| **ES 版本** | legado 明确 `VERSION_ES6 + setInterpretedMode(true)` | JSC 支持现代 ES | 本轮 74 条片段覆盖常用 ES6；超出样本的现代语法仍不能声称完全一致 |
| **`result` 复杂对象绑定** | 直接把 Kotlin 对象（Element/NativeObject）绑给 JS | 本移植把复杂 RuleValue 以**字符串化**后绑定 | 简化；JS 里对 `result` 做 DOM 操作的规则无法工作（属 Java 互操作范畴，同上抛错） |
| **Java String 返回值的包装（第 5 步收尾新增）** | `WrapFactory.javaPrimitiveWrap` 默认 `true`（`WrapFactory.java:163`），Java 方法返回的 String 会被包成 `NativeJavaObject`（`getPrototype()` 再挂到 JS String 原型上，`NativeJavaObject.java:154`）。于是 `.length` 命中 Java 的 `length()` 方法（`typeof` 为 `"function"`），`.match()`/`.split()` 才落到 JS String 原型/Java 成员 | `JsoupJSBridge` 的方法直接返回 JS 字符串，`.length` 是长度（`typeof` 为 `"number"`） | **已知差异**：golden `divergence_java_string_length_type` 钉住两侧实际值（`"function"` vs `"number"`，测试断言差异必须存在）。影响面：爱丽丝书屋真实规则里的 `content.length < 50` 在 legado 里恒为 `false`（函数与数字比较），本移植会按真实长度判断。书源若要"长度"应显式写 `String(content).length`（golden `alice_content_len` 即按该写法对照） |
| **最小次正规数的最短十进制表示（第 5 步收尾新增）** | Rhino 1.8.1 `DoubleFormatter` 给出 `"4.9e-324"`（2 位有效数字） | JSC/V8 与原样复刻 ECMAScript `Number::toString` 的 `JsNumberFormat` 都给出 `"5e-324"`（1 位） | **已知差异**：golden `numarg_md5_5eneg324` 钉住 `4.9e-324` / `5e-324` 两侧实际值。两者解析回同一个 double，仅字符串形式不同；书源不会把次正规数传给 String 参数（`RhinoNumberArgGoldenTests` 对这条按已登记差异处理） |

### Rhino 1.8.1 返回值 golden（第 4 步最终收尾）

`scripts/golden/cases/js_rhino.json` 含 **74 条合成 JS 片段**，真实依赖
`org.mozilla:rhino:1.8.1`，按 legado `VERSION_ES6 + setInterpretedMode(true)`、
`unwrapReturnValue`（Wrapper/ConsString 拆箱，Undefined→null）运行。Java 生成器同时输出：
- `getString` 路径：raw 为 null→`""`，否则 Java `raw.toString()`；
- inline `{{}}` 路径：null跳过，String原样，整数 Double 用 Locale.ROOT `"%.0f"`，其余 `toString()`。

Swift 测试 `JSRhinoGoldenComparisonTests` 逐条用 JavaScriptCore 跑同一片段并比较两条路径。
以下是经真实对照后仍不能稳定逐字节对齐的完整清单（其余用例严格相等）：

| 最小复现 | Rhino 1.8.1 | JavaScriptCore/Swift | 原因与处理 |
|---|---|---|---|
| `0` / `0.0` | rawType=`Integer`，getString=`"0"` | JSC 统一 Number/Double，`"0.0"` | JVM 包装类型不可从 JSC 公共 API 恢复；登记 `zero_int/zero_float` |
| `'hello'.length` | rawType=`Integer`，`"5"` | Number/Double，`"5.0"` | 同上；登记 `str_length` |
| `JSON.parse('{\"k\":7}').k` | rawType=`Integer`，`"7"` | Number/Double，`"7.0"` | 同上；登记 `json_parse_get` |
| `[1,2,3]`（以及 mixed/nested/JSON.parse array） | `org.mozilla.javascript.NativeArray@<identity>`，每次 hash 不同 | 稳定元素列表描述 | Rhino Java `Object.toString()` 本身非确定输出，无法也不应伪造；golden 用稳定 `<NativeArray identity>` 标记并显式豁免。`join`/`String(array)`/`JSON.stringify` 仍严格比较 |
| `{{JSON.stringify({a:{b:[1,2]}})}}` | JS 本身可求值 | legado/Swift 相同 lazy `{{...}}` 正则在内部首个连续 `}}` 截断 | 两端共同解析器限制；该片段的 evalJS/getString 路径仍严格比较，inline 单项不比较 |

可修项已全部对齐：`big_number`/`2^53`/`1e21`/`1e-7`、NaN、±Infinity、
`Date.getTime()`、普通 NativeObject `[object Object]`，以及所有字符串拼接、JSON.stringify、
parseInt、result*1、String(x)、模板字符串。

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

## 已知行为差异（第 4 步 B 补充）

- **@put 非规范 JSON**：Kotlin 用 GSON（lenient）能解析 `@put:{saved:p@text}`（键/值未加引号）。
  本移植的 `parseStringMap` 走标准 JSON 解析，**只接受规范 JSON** `@put:{"saved":"p@text"}`。
  非规范写法会被忽略（不崩溃）。Legado 文档本身推荐规范 JSON；lenient 解析待后续补。
- **`@text` 下的实体解码**：SwiftSoup（同 jsoup）的 `text()` 已对 HTML 实体解码，因此
  `p@text` 规则返回的文本里 `&amp;` 已变 `&`。AnalyzeRule 的 `unescape` 开关作用在**最终
  字符串**上（对还有残留实体的结果再解码），与 Kotlin 一致。
- **`:eq(n)` 等 jsoup 伪选择器**：由底层 SwiftSoup 提供，索引语义与 jsoup 的对齐情况见
  第 3 步「SwiftSoup 与 jsoup 已知差异」。
- **`contentEquals` 近似（`getAnalyzeByXPath/JSoup/JSonPath` 的解析器复用判断）**：Kotlin 里
  `o != content` 是**引用判等**——只有两个中间值引用的是同一个对象才复用缓存解析器，否则新建。
  本移植的 `RuleValue` 不是 `Equatable`，用 **`stringValue` 近似**：两个中间值的 `stringValue`
  相同即视为「相同」、复用解析器。**差异点**：两个内容相同但**不是同一实例**的中间值（如两个
  相等的 String），Kotlin 引用判等会判 false（新建解析器），本移植判 true（复用）。但解析器
  内容完全由 `stringValue` 决定，故无论新建还是复用，后续规则的**求值结果一致**，此差异在
  结果层面**无可观测影响**（已用 `RuleValueObjectBranchTests.testContentEquals_*` 三个边界
  用例固定：同值不同实例判 true 且结果一致；换内容重建取新值；content 为 nil 恒判 false）。
  若未来出现「stringValue 相同但应走不同解析器」的真实书源场景，再精确对齐引用判等。

## 本步骤明确排除（后续步骤已补完，此处保留历史记录）

- `reGetBook` / `refreshTocUrl`：依赖 WebBook，留桩抛 `.unsupported`（**第 6 步仍如此**，见 6B 差异清单）。
- JsExtensions 的 67 个方法体（见 `JsExtensionsCatalog.swift` 与 `JS_EXTENSIONS_USAGE.md`）：**第 5 步已实现**。
- 真实网络（AnalyzeUrl / ajax 真实请求）：**第 6 步已实现**（`URLSessionHTTPClient` + `RealAjaxProvider`）。
- 真实 WebView（WebJs / BackstageWebView / `java.webView`）：**不做**（见 6A 差异表 #5）。
- WebBook/BookList/BookInfo/BookChapterList/BookContent 流程：**第 6 步已实现 AnalyzeUrl**；WebBook 业务流仍属后续。
- Kotlin 协程上下文（`setCoroutineContext`）：Swift 无对应协程模型，排除。

## 样本诚实标注（第 4 步 B）

- 合成样本：`Tests/LegadoAnalyzeRuleTests/` 内除标注「真实规则」外，所有 HTML/JSON/规则文本
  均为合成（测试注释标「合成样本，非真实数据」）。
- 真实规则 + 合成数据：端到端测试（`AnalyzeRuleEndToEndTests`）用 `配置文件_7个.json` 及
  从 `配置文件_14个.json` 提取的 `taiwan_real_source.json` **真实书源规则文本**，输入响应为合成数据，
  每个用例注释标「规则真实、数据合成」及来源书源名（含台湾小说网 Packages.org.jsoup 拒绝用例）。

## java.xxx 使用情况表

见 `JS_EXTENSIONS_USAGE.md`（14 个真实书源实际调用的 `java.xxx` / `cookie.xxx` / `cache.xxx`
方法 + 次数 + 已/未实现状态 + Java 互操作标记 + 第 5 步实现优先级）。


---

## 第 4 步 C：真实 Java 库 golden 对照验证工具函数

第 4 步 B 新增的三块工具函数（JavaURLResolver/NetworkUtils、HtmlUnescape/HtmlEntities、
RegexTemplate）以及第 2 步的 JSONPath、AnalyzeByRegex 后端，之前只有合成单测。本步骤用真实
Java 库生成 golden 对照数据，逐条比较并修正 Swift 实现。

### 新增 golden 依赖（scripts/golden/pom.xml，版本与 legado `gradle/libs.versions.toml` 一致）

| 依赖 | 版本 | 用途 | 是否成功打进 fat jar |
|---|---|---|---|
| json-path（Jayway） | 2.10.0 | JSONPath 真实对照 | ✅（CI golden job success） |
| commons-text | 1.13.1 | unescapeHtml4 真实对照 | ✅ |
| gson | 2.10.1 → **2.13.2** | 与 legado 一致 | ✅ |
| commons-lang3 | 强制 **3.18.0** | commons-text 1.13.1 的 NumericEntityEscaper 用到 `Range.of`，旧的间接 lang3 会 `NoSuchMethodError`，dependencyManagement 收敛 | ✅ |

shade 插件新增 `ServicesResourceTransformer`（合并多依赖的 META-INF/services）+ 去签名文件
filter，保证 fat jar 可运行。jsoup 1.16.2 / JsoupXpath 2.5.3 不变。

### golden 用例数（cases/*.json，均为合成测试数据 synthetic_ 前缀）

| 类别 | 用例数 | 对照的真实库 | 状态 |
|---|---|---|---|
| getAbsoluteURL（url_absolute.json） | **66** | `java.net.URL(base, rel)`（经 Kotlin NetworkUtils 调度，手工移植 Java） | ✅ 全绿 |
| unescapeHtml4（unescape_html4.json） | **52** | `commons-text StringEscapeUtils.unescapeHtml4` | ✅ 全绿 |
| replaceRegex（regex_replace.json） | **51** | Kotlin AnalyzeRule.replaceRegex 语义（真实 `java.util.regex`） | ✅ 全绿 |
| AnalyzeByRegex（regex_analyze.json） | **24** | 真实 Java 正则 getElement/getElements | ✅ 全绿 |
| JSONPath（jsonpath_cases.json） | **62** | 真实 Jayway JsonPath 2.10.0（json-smart） | ✅ 47 对齐 / **15** 登记已知差异（见下） |

> 调度逻辑（Kotlin NetworkUtils.getAbsoluteURL / AnalyzeRule.replaceRegex / AnalyzeByJSonPath
> 单规则路径）是为生成 golden 手工移植到 Java 的，**内部调用的是真实库**（java.net.URL /
> java.util.regex / commons-text / Jayway）；对照的是 Kotlin 工具函数的最终行为。

### golden 暴露并修复的差异（逐条）

1. **getAbsoluteURL — java.net.URLStreamHandler.parseURL 精确算法**（`JavaURLResolver.resolve`）。
   原 B 部分用 RFC 3986 remove_dot_segments 过度规范化，与真实 java.net.URL 不符。已重写为精确
   移植 `java.net.URLStreamHandler.parseURL`：
   - 路径消解（`/./`、`/../`、尾部 `/..` `/.`）**仅对相对路径生效**；绝对路径 `/a/../b` 与协议相对
     `//h/c/../d` **不规范化**，保留字面 `/../`。
   - 越过根的 `/../` 保留字面（如 `../../../b.html` → `/../../b.html`，不裁剪到根）。
   - 路径里的 `//`（连续空段）保留。
   - `"?query"` only 相对引用：path 截到最后一个 `/`（丢掉文件名段）+ query（如
     `http://a.com/b/c.html` + `?k=v` → `http://a.com/b/?k=v`）。
   - `..` / `.` 作为完整相对引用产生尾部 `/`。
   连带修正 B 部分旧单测 `testAbs_queryOnly` 的错误断言。
2. **replaceRegex — 命名组模板 `${name}`/`$<name>`**（`RegexTemplate`）。Java/Kotlin 替换模板支持
   `${name}` 命名组引用，ICU/NSRegularExpression 不支持。已在 `javaToICU(_:pattern:)` 里从 pattern
   解析命名组序号（`namedGroupIndices`，正确跳过非捕获组/断言/字符类/转义括号），把 `${name}`
   转成 `$index`。
3. **JSONPath `.length()` 解析 bug**（`JSONPathParser.readName`）。`readName` 未在 `(` 处停止，把
   `length()` 整体当成字段名导致 pathNotFound → 空串。已让 `readName` 在 `(` 处停止，`.length()`
   正确求值（返回元素个数）。
4. **JSONPath 对象/数组 toString 格式**（`JSONValue.jaywayStringValue` + `javaMapString`）。真实
   Jayway（json-smart）读到的对象经 `Object.toString()` 用 **Java Map 格式** `{key=value, key=value}`
   （`=` 分隔、`, ` 连接、键值不加引号），其中值为数组时渲染成 JSON、值为对象时递归 Map 格式。
   原 Swift 用紧凑 JSON `{"key":value}`。已为 AnalyzeByJSonPath 的 getString/getStringList 的
   对象/数组 toString 路径改用 `jaywayStringValue`（不影响其它 `stringValue` 调用方）。

### 剩余已知差异（真实 Jayway 支持、本项目自实现子集 `DefaultJSONPathEvaluator` 不支持）

> 均经 golden 真实 Jayway 跑出真实行为后登记，附最小复现 + 两边结果 + 影响面。这些语法在真实
> 书源 JSONPath 规则里几乎不出现（书源多用 `$.data.books`、`$..title`、`[*]`、`[n]` 等基础语法），
> 完整复刻 Jayway 的嵌套过滤器布尔逻辑 / 聚合函数 / 逗号多下标 / 步长切片 / `@` 根超出第 4 步 C
> 预算，故如实登记为子集边界（**非静默跳过**，golden 测试里用 `knownJSONPathDivergences` 显式豁免
> 并在此表记录）。README 原「不支持」表述与真实 Jayway 一致处保留，不一致处以下表真实行为为准。

| 规则（最小复现，doc 见 jsonpath_cases.json doc1） | 真实 Jayway 结果 | 本项目子集结果 | 影响面 |
|---|---|---|---|
| `$.store.book[?(@.price>5 && @.author=='A1')].title` | `T1` | 空（抛 unsupportedSyntax，被吞成空） | 过滤器布尔多条件；书源罕用 |
| `$.store.book[?(@.price>18 \|\| @.price<6)].title` | `T2\nT3`（示例） | 空 | 同上 |
| `$.store.book[?(@.title=~/T.*/)].title` | `T1\nT2\nT3` | 空 | 过滤器正则 `=~`；书源罕用 |
| `$.store.book[?(@.author in ['A1','A2'])].title` | `T1\nT2\nT3` | 空 | 过滤器 `in`；书源罕用 |
| `$.nums.min()` / `.max()` / `.avg()` / `.sum()` | `1.0` / `6.0` / `3.5` / `21.0`（Double） | 空 | 聚合函数；子集只支持 `length()` |
| `$.nums[0,2]` | `1\n3` | 空 | 逗号多下标；书源罕用 |
| `$.store.book[0,2].title` | （多下标）| 空 | 同上 |
| `$.nums[0:6:2]` | `1\n2\n3\n4\n5\n6`（步长被 Jayway 忽略） | 空 | 步长切片；书源罕用 |
| `@.expensive`（`@` 作顶层根） | `15` | 空 | `@` 根；子集仅过滤器内 `@.` 支持 |
| `$.nums[?(@>3)]`（过滤器内裸 `@` 标量比较） | `4\n5\n6` | 空 | 裸 `@` 标量过滤；子集只支持 `@.field` |
| `$.store.book[0]['title','author']` | `{title=T1, author=A1}`（返回 Map 对象） | `["T1","A1"]`（返回列表） | 多字段取值语义：Jayway 合成对象，子集返回列表 |
| `$.store..*`（深度扫描通配） | 特定遍历顺序、不含中间容器对象节点 | 遍历顺序/节点集不同 | `..*` 深扫顺序；书源罕用 |

> 其余 JSONPath 语法（`$`、`.`、`[]`、多字段键取对象外的列表形态、递归 `..`、通配 `*`、下标、
> 切片、单条件过滤器、`length()`、超 Int64 大整数精度）golden 全部对齐。

> **影响面实测（第 4 步收尾，14 个真实书源）**：用 `配置文件_14个.json`（14 个真实书源）严格正则
> 扫描上表全部已知差异语法，**命中数为 0**：
> 过滤器布尔多条件 `&&`（0）、过滤器 `||`（0）、过滤器正则 `=~`（0）、过滤器 `in`（0）、
> 逗号多下标 `[0,2]`（0）、步长切片 `[0:6:2]`（0）、聚合函数 `.min()/.max()/.avg()/.sum()`（0）。
> 即这 14 个真实书源的 JSONPath 规则**完全没有用到**本项目子集不支持的任何高级语法，
> 上表已知差异对这 14 个书源**无实际影响**（用户提供的同口径扫描结果一致）。

### ICU(NSRegularExpression) vs Java 正则根本性差异（匹配侧，非本步骤 golden 用例触发，预防性登记）

replaceRegex / AnalyzeByRegex 的 50 + 24 条 golden 用例全绿（含懒惰/贪婪/锚点/多行/Unicode/
emoji/前后断言/命名组/反向引用等）。以下 Java 正则特性 ICU 不支持或语义不同，书源规则若用到会
不一致（未纳入 golden 用例，预防性登记，真实书源未见使用）：占有量词 `a++`/`a*+`/`a?+`、
`\h`/`\v`（Java 的水平/垂直空白）、`\Z`（Java 末尾锚点语义）、`\G`、内嵌标志作用域 `(?i:...)`
在边角的差异。确需时可逐条补 golden 验证。

### 第 4 步 C 样本诚实标注

所有 golden 用例输入（URL 字符串、待转义字符串、正则、JSON 文档）均为**合成测试数据**，用
`synthetic_` 前缀 + 文件 `_comment` 字段标注。无真实书源规则文本（纯工具函数输入）。

---

# 第 5 步：JsExtensions 方法体 + org.jsoup.Jsoup 替身

在既有 `java`（JsExtensions）Proxy 桥接基础上，实现第一批纯算法方法体、注入 UI/网络类协议、
放行 org.jsoup 两种写法（SwiftSoup 替身），并全部由真实 Java 库 golden 对照验证。

## 已实现的方法（JsExtensionsCore.swift）

| 方法 | 对齐语义（Kotlin 源码 + 真实库） | golden 对照库 |
|---|---|---|
| `md5Encode` / `md5Encode16` | UTF-8 字节 MD5 小写 hex；16 位 = substring(8,24) | hutool 5.8.22 DigestUtil |
| `t2s` | quick-chinese-transfer 0.2.17 最长匹配词典 + legado fixT2sDict 排除词 | quick-transfer-core 0.2.17 |
| `s2t` | 同上（简体→繁体方向） | quick-transfer-core 0.2.17 |
| `timeFormat` | `FastDateFormat("yyyy/MM/dd HH:mm")`（默认时区/区域） | Java SimpleDateFormat |
| `timeFormatUTC(time, format, sh)` | `SimpleTimeZone(sh ms, "UTC")` 的格式 | Java SimpleTimeZone |
| `base64Encode` | android Base64.NO_WRAP 等价（标准表无换行） | hutool Base64 |
| `base64Decode` | hutool Base64Decoder 容错解码（跳过非法字符、`=` padding、4 字符一组） | hutool Base64Decoder 逐行移植 |
| `base64DecodeToByteArray` | 空白输入 -> null；否则容错解码字节 | 同上 |
| `hexEncodeToString` | UTF-8 → 小写 hex | hutool HexUtil |
| `hexDecodeToString` | 空串原样返回；奇数长度前补 `0`；非法字符抛错 | hutool HexUtil/Base16Codec |
| `hexDecodeToByteArray` | 空串 -> null；奇数前补 0；非法抛错 | hutool Base16Codec |
| `htmlFormat` | `HtmlFormatter.formatKeepImg(null)` 全正则链 + img 归一化 | legado 源码逐行复刻 |
| `encodeURI` | `URLEncoder.encode(UTF-8)`：空格→`+`、保留 `. - * _`、异常→`""` | Java URLEncoder |
| `randomUUID` | 小写 UUID 字符串 | Java UUID |
| `toNumChapter` | `(第)(.+?)(章)` + fullToHalf + parseInt/中文数字 | legado StringUtils 逐行复刻 |
| `strToBytes` / `bytesToStr` | UTF-8；`bytesToStr` 另支持 ISO-8859-1（256 字节 1:1 映射）与 GBK（合法双字节用 GB18030-2000 逐对解码，非法字节按 JDK `DoubleByte.Decoder#crMalformedOrUnmappable` 的消费规则逐个替换为 U+FFFD） | Java 标准库（UTF-8 / ISO-8859-1 / GBK） |

## 注入类方法（协议 + 默认实现）

| 方法 | 协议 | 默认行为 |
|---|---|---|
| `toast` / `longToast` / `openUrl` / `startBrowser` / `startBrowserAwait` / `getVerificationCode` / `webView` | `JsUIProvider`（webView 同时接入既有 `WebJSProvider`） | 抛 `RuleEngineError.unsupported` + 记 diagnostics（真实 UI 第 6 步） |
| `get` / `post` / `head` / `ajaxAll` / `connect` / `cacheFile` / `downloadFile` | `JsNetworkExtensionsProvider` | 同上（真实网络第 6 步） |

## org.jsoup.Jsoup 替身（JsoupJSBridge.swift）

- `org.jsoup.Jsoup.parse(...)` 与 `Packages.org.jsoup.Jsoup.parse(...)` 两种写法**放行**，
  用 SwiftSoup 实现真实书源实际用到的链：`parse(html)` → `select(css)` → `text()` / `html()` /
  `attr(name)` / `outerHtml()` / `first()` / `get(i)` / `size()` / `eq(i)` / `remove()`。
- **与真实 jsoup 1.16.2 逐条对照**（91 条 golden，见下方「jsoup 替身 golden」小节）：同一段 JS
  在 Java 侧由 Rhino 跑真实 jsoup、在 Swift 侧由 JavaScriptCore 跑本替身，比较结果字符串/null/抛错。
  对照后先修掉了 5 处语义偏差：`text()` 的 `&nbsp;` 规整、`html()`/`outerHtml()` 改用
  `JsoupCompatSerializer`（不再用 SwiftSoup 自带的 pretty-print）、`Elements.attr` 取
  「第一个**拥有**该属性的元素」、`eq(越界)` 返回空集合、`get(越界)` 抛错；
  另修了 `Document.outerHtml()` 不输出 `<#root>` 包裹、属性名小写化两处。
- 端到端实证：爱丽丝书屋 `org.jsoup.Jsoup.parse(result).select('div.read-content').text()`、
  台湾小说网真实规则原文 `d.select('#content p') → es.get(i).text() → join('\n')` 全链执行，
  断言期望值从 golden 读取（见 `AnalyzeRuleEndToEndTests.testAlice_jsoupParseWorks` /
  `testTaiwan_realJsoupChainWorks`）。
- 其余 Rhino 互操作（`importClass`/`importPackage`/`JavaImporter`/`java.lang|util|io|net|math`、
  非 jsoup 的 `Packages.xxx`）仍预检测抛 `RuleEngineError.jsError` + 记 diagnostics。

## golden 对照（真实的 Java 库）

第 5 步收尾后，`scripts/golden` 里有三个生成器覆盖第 5 步全部语义：

| 生成器 / 用例文件 | 真实依赖 | 条数 | 覆盖 |
|---|---|---|---|
| `JsExtGen.java` → `cases/js_ext_cases.json` | hutool 5.8.22（MD5/Base64/Hex）、quick-transfer-core 0.2.17（t2s/s2t）、Java 标准库（URLEncoder / SimpleDateFormat / SimpleTimeZone / Charset） | **321** | 全部 15 个纯算法方法；14 个方法各 ≥15 条、`t2s`/`s2t` 各 38 条；`bytesToStr` 覆盖 UTF-8 / ISO-8859-1 / GBK 的合法与非法字节；`argsJs` 表达 JSON 装不下的字面量（NaN/Infinity/-0） |
| `JsExtGen.runJsoup` → `cases/jsoup_cases.json` | jsoup 1.16.2 + Rhino 1.8.1 | **91** | 同一 JS 表达式两边跑：Java 侧 Rhino + 真实 jsoup，Swift 侧 JSC + `JsoupJSBridge` 替身 |
| `NumberArgGen.java` → `cases/js_number_args.json` | Rhino 1.8.1 | **42** | JS number → Java String 参数的真实转换（25 个字面量 × 多方法） |
| `JsExtGen.runJavaDigest`（`javaDigestCases`，写在 js_ext_cases 里） | `java.security.MessageDigest` | 2 | 端到端测试的期望值（淘小说吧签名链），不用 Swift 自己的 md5 反推 |

- 非法输入以「抛错 <-> 抛错」三态比较（值必须相等、null 必须同为 null、异常必须同为异常）；
- 失败信息含 name/输入/Java 结果/Swift 结果；CI 缺失 golden 必 fail；
- CI 的 `golden` job 一次跑完全部 22 个用例文件（第 5 步收尾时为 15 个文件 1233 条，第 6 步新增 7 个文件）。

### 字符集 / 请求生成器（第 6 步新增）

| 生成器 / 用例文件 | 真实依赖 | 条数 | 覆盖 |
|---|---|---|---|
| `CharsetGen.java` + `CharsetCorpus.java` → `cases/charset_cases.json` | **legado 自带的 icu4j 源码**（`src/main/java/legadoicu/`，逐行复制自 `app/src/main/java/io/legado/app/lib/icu4j/`）+ `EncodingDetectGolden.java`（`EncodingDetect.kt` 的 Java 移植）+ jsoup 1.16.2（`getHtmlEncode` 的 meta 解析） | **240** | UTF-8 带/不带 BOM、GBK、GB2312、GB18030、Big5、EUC-KR、Shift_JIS、EUC-JP、ISO-8859-1、windows-1252、UTF-16 LE/BE、UTF-32、1–10 字节极短文本、HTML 带/不带 meta、中英混排、乱码字节、C1 控制区、空数据；含 **45 份标注的合成小说章节文本**（`syntheticNovelChapter: true`） |
| `RequestGen.java` → `cases/request_cases.json` | 真实 OkHttp 5.3.2（`okhttp-jvm`）+ `com.sun.net.httpserver` | **43** | GET（含 encodedQuery）、POST form、POST json、multipart、HEAD；记录 method / path+query / 有序显式头 / Cookie / body 字节（boundary 归一） |
| `RequestGen.java` → `cases/redirect_cases.json` | 同上 | **44** | 301/302/303/307/308、跨域重定向、重定向链中途 `Set-Cookie`、`followRedirects=false`、超 20 跳上限 |
| `RequestGen.java` → `cases/request_cookie_cases.json` | 同上 | **13** | Cookie 注入/合并/清除/多域 |
| `RequestGen.java` → `cases/auto_header_cases.json` | 同上 | **4** | 客户端自动头清单 |

### jsoup 替身 golden（91 条）

- **用例来源**：`scripts/extract_jsoup_chains.py` 从仓库内真实书源配置（`配置文件_7个.json` 的 7 个书源 +
  `taiwan_real_source.json` 的台湾小说网）提取全部 `org.jsoup.Jsoup` 链，并打印方法使用统计：
  `select 28 / attr 5 / size 5 / text 5 / get 4 / html 1 / remove 1`。
  两个用到 jsoup 的书源（爱丽丝书屋、台湾小说网）都在扫描集合内；替身对外承诺的
  `first`/`eq`/`outerHtml` 另用合成用例覆盖。`--check` 会校验每条用例的 `source` 标签都能命中真实规则。
  （第 4/5 步期间还出现过 `配置文件_14个.json`，该文件未随仓库保存——工作区被系统清空过；
  本脚本以仓库内实际存在的真实配置为准。）
- **执行方式**：每条用例 = 一条 JS 表达式 + 一份 HTML。Java 侧用真实 Rhino 1.8.1 求值
  （classpath 上是真实 jsoup 1.16.2），Swift 侧用 JavaScriptCore + `JsoupJSBridge` 求值**同一条 JS**，
  比较「结果字符串 / null / 抛错」。测试：`JsoupBridgeGoldenComparisonTests`。
- **HTML 输入 14 份**（全部合成、结构模仿真实书源页面），其中 4 份不规范：未闭合 `<p>`/`<li>`、
  没有 `<tbody>` 的表格、大写标签 `<DIV CLASS="...">`、实体字符（`&nbsp;`/`&amp;`/`&lt;`/`&copy;`）。
- **替身因此先修的 5 处语义偏差**：`text()` 走 `SwiftSoupTextNormalizeFix`；
  `html()`/`outerHtml()` 走 `JsoupCompatSerializer`（不再用 SwiftSoup 自带的 pretty-print）；
  `Elements.attr` 取「第一个**拥有**该属性的元素」（不是"第一个元素的属性"）；
  `eq(越界)` 返回空集合；`get(越界)` 抛错（对齐 `IndexOutOfBoundsException`）。
- **端到端**：`alice_e2e_text` / `alice_e2e_html` / `taiwan_e2e_content`（后者是**真实规则原文**，
  含 `java.t2s` 与 `Packages.org.jsoup`）。`AnalyzeRuleEndToEndTests` 里爱丽丝/台湾两条断言的
  期望值改为从 golden 读取（不再写死、不用"非空"弱断言）；淘小说吧签名链的期望值改为 golden 里
  `java.security.MessageDigest` 直算的结果。

### JS 数字入参：真实 Rhino 验证（不再有任何手写规则）

旧实现在 `JsExtGen.numberToString` 与 Swift harness 里各写了一套「整数无 `.0`」的假设——已**全部删除**。

- 原理（已读 Rhino 1.8.1 源码确认，非凭记忆）：legado 把 JsExtensions 实例绑成脚本里的 `java`
  （NativeJavaObject），JS 调 `java.md5Encode(1e21)` 时 Rhino 走 `NativeJavaObject.coerceTypeImpl`
  （`JSTYPE_NUMBER && type == STRING` → `ScriptRuntime.toString(value)`）→
  `org.mozilla.javascript.dtoa.DoubleFormatter.toString(double)`，其源码注释原文：
  *"Convert a double to String as defined in the "Number::toString" operation in ECMAScript."*
- `NumberArgGen.java` 把与 JsExtensions 同名同签名的探针绑成 `java`，执行 `java.<method>(<字面量>)`，
  记录 Rhino **实际传进 String 参数的那一串**（`javaReceived`，42 条）。
- Java 侧 harness 的数字参数一律取同一份 Rhino 结果（写进 `js_ext_cases` 的 `argStrings`），
  Swift 侧测试直接读 `argStrings` 使用；运行时 `JsExtensionsRuntime.stringify` 改用
  `JsNumberFormat`（ECMAScript Number::toString 复刻）。
- 三层逐条比较（`RhinoNumberArgGoldenTests`）：① JSC 的 `String(x)` == Rhino 的转换结果；
  ② `JsNumberFormat.toString(Double(literal))` == Rhino；③ 走完整 `AnalyzeRule` 的
  `<js>java.xxx(字面量)</js>` == Rhino 的 `callResult`。
- 覆盖：`0 / -0 / 1 / -1 / 42 / 123 / 1.5 / -1.5 / 0.5 / 1e21 / 1e-7 / 1e-6 / 1e20 /
  12345678901234567890 / 9007199254740993 / 1.7976931348623157e308 / 5e-324 / NaN / ±Infinity /
  3.141592653589793 / 100.0 / -0.5 / 1700000000000 / 2.5e-8`。

## 样本诚实标注（第 5 步）

- `cases/js_ext_cases.json` / `cases/jsoup_cases.json` / `cases/js_number_args.json` 全部输入为**合成样本**
  （文件名/`_comment`/`_SAMPLE_KIND` 字段标注）。其中 jsoup 用例的 JS 链取自真实书源规则的同类写法，
  `source` 字段标注来源书源与规则路径（可用 `scripts/extract_jsoup_chains.py --check` 复核），
  HTML 全部手工构造。
- 端到端测试使用 14 书源**真实规则文本** + 合成响应（规则真实、数据合成），来源书源名在用例注释标出。
- `Sources/LegadoBookSource/Resources/Chinese/*.txt` 为 quick-chinese-transfer 0.2.17 原样资源
  （含 `PROVENANCE.md`），非本项目编写。


# 第 6 步 6A：AnalyzeUrl 规则解析与请求构造（不发网络请求）

在既有 RuleEngine（第 1–5 步 API 与行为不变）之上，新增 `Sources/LegadoBookSource/Network/`：
`AnalyzeUrl.swift`（AnalyzeUrl.kt 的完整移植：initUrl/analyzeJs/replaceKeyPageJs/analyzeUrl/
encodeParams/evalJS/put/get/buildRequest 等）、`UrlOption.swift`、`GsonJSON.swift`、
`ConcurrentRateLimiter.swift`（actor + 时钟注入）、`CookieStore.swift`、`CookieManager.swift`、
`CacheManager.swift`、`NetworkUtilsEncoding.swift`、`HTTPTypes.swift`（HTTPRequest/HTTPResponse/
HTTPClient 协议 + ScriptedHTTPClient 假实现）。**真实网络实现（`URLSessionHTTPClient`）见下方 6B 小节。**

## 请求构造（6A 的核心输出）

`AnalyzeUrl.buildRequest() -> HTTPRequest` 把 Kotlin `executeStrRequest`/`getResponseAwait`/`upload`
里「构造 Request」的部分抽出来：url（GET/HEAD 为 `urlNoQuery` + `?` + encodedQuery，POST 为 urlNoQuery）、
method、**有序** headers（headerMap 插入顺序 + `setCookie()` 注入的 Cookie 与 `CookieJar` 标记）、
body（form / 按 Content-Type 的原始体 / JSON 三种形态）、contentType、charset、retry、readTimeout、
callTimeout、useWebView、webJs、bodyJs、dnsIp、proxy、type、serverID。

## golden 对照（真实 Java 库）

`scripts/golden/UrlRuleGen.java` 新增四类用例，共 **524 条**：

| 用例文件 | 条数 | 对照对象 |
|---|---|---|
| `url_codec_cases.json` | 299 | hutool `RFC3986.UNRESERVED.orNew(PercentCodec.of(...))`、`URLEncoder`、`EncoderUtils.escape`、`NetworkUtils.encodedQuery/encodedForm` |
| `url_option_cases.json` | 84 | 真实 Gson 2.13.2 + legado 的 `StringJsonDeserializer`/`IntJsonDeserializer`/`LONG_OR_DOUBLE` |
| `analyze_url_cases.json` | 94 | java.net.URL + Rhino 1.8.1（JS）+ **AnalyzeUrl 调度逻辑的手工 Java 移植** |
| `cookie_cases.json` | 47 | CookieStore/CookieManager 纯函数的手工移植版 |

（6B 又新增了 `charset_cases.json` 240、`request_cases.json` 43、`redirect_cases.json` 44、
`request_cookie_cases.json` 13、`auto_header_cases.json` 4，详见下方 6B 小节的生成器表格；
`scripts/golden` 当前共 **22 个用例文件、2271 条用例**。）

> **本 README 明确标注**：`UrlRuleGen.java` 里的 `encodeParams`/`analyzeJs`/`replaceKeyPageJs`/`analyzeUrl`
> 是 AnalyzeUrl.kt **调度逻辑的手工 Java 移植**（不是 Kotlin 原码），它只验证真实库的行为；
> 逐条对照的结果以 CI 的 `golden` job 为准（每个测试都要求「值必须相等 / null 同为 null / 异常同为异常」）。

## 与 Kotlin 的已知差异（第 6 步 6A）

| # | 主题 | Kotlin | 本移植 | 处理 |
|---|---|---|---|---|
| 1 | 公共后缀 | Android `PublicSuffixDatabase` 完整列表 | 内置常见多段后缀 + 默认末两段 | 差异表登记；常见书源域名一致 |
| 2 | cookie 4096 截断 | 随机删键 | 按插入顺序删第一个 | 结果可复现，语义相同 |
| 3 | 持久化 | Room/ACache | 协议 + JSON 文件原子写 | 接口一致 |
| 4 | OkHttp `HttpUrl` 规范化 | OkHttp 对 path/query 做规范化（scheme/host 小写、IDN→punycode、默认端口剥离、路径 `%xx` 与 `.`/`..` 段解析等） | **已对齐**：`Sources/.../Network/HttpUrl.swift` 按 OkHttp 5.x 的行为复刻（含：非法 `%` 转义原样保留、控制字符丢弃、路径里 `\` 当 `/`、`%2E`/`%2e%2e` 视作点段、多个前导斜杠折叠、输入 trim、片段里的 `#` 不编码），`AnalyzeUrl.buildRequest()` 产出的 URL **必经它** | 170 条 golden（`cases/http_url_cases.json`，真实 OkHttp 5.3.2 的 `HttpUrl` 生成）逐条相等；`HttpUrlGoldenComparisonTests` 严格比较（含解析失败样例），另有一条断言 buildRequest 产出已规范化 |
| 4b | **线上请求行的额外百分号编码** | OkHttp 把 `|` `{` `}` `^` `` ` `` `[` `]` 与非法 `%` 转义（如 `%zz`）按原样写进 request-target | URLSession/CFNetwork 会把它们额外编码成 `%7C` `%7B` `%7D` `%5E` `%60` `%5B` `%5D` 与 `%25zz` | **登记为已知差异**（`HttpUrlRequestReplayTests.knownWireEncodingDivergences` 逐名钉住）。最小复现：`https://x.com/?a=b|c` → OkHttp 线上 `GET /?a=b|c`，本移植经 URLSession 发出为 `GET /?a=b%7Cc`；`https://x.com/%zz` → OkHttp `/%zz`，本移植 `/%25zz`。影响：此类字符在真实书源 URL 中极少见，且服务器多数会等价解码；规范化结果本身（HttpUrl）与 OkHttp 完全一致，差异只出现在 URLSession 写线上的最后一步 |
| 5 | WebView 分支 | `BackstageWebView`（useWebView=true） | **不支持**：`HTTPRequest.useWebView/webJs/bodyJs` 只记录字段，`URLSessionHTTPClient` 对此记 diagnostics。WebView 需 UIKit/WebKit 宿主视图，SwiftPM 库层不做 | 真实书源里走 `webView` 分支的占比极低；受影响书源需宿主 App 自行接管 |
| 6 | 阻塞版限速 API | `getConcurrentRecordBlocking`/`withLimitBlocking` | 只有 async | 调用方用 `withLimit` |
| 7 | `dnsIp` 自定义解析 | OkHttp `Dns` 直连指定 IP | **不支持**：`dnsIp` 已落到 `HTTPRequest` 并由 `URLSessionHTTPClient` 写 diagnostics，实际仍走系统 DNS | URLSession 无公开 API 指定解析 IP，如实登记 |
| 8 | 证书策略 | `SSLHelper` 信任所有证书 | **已实现**：`URLSessionHTTPClient` 实现 `urlSession(_:didReceive:completionHandler:)`，对服务器信任挑战回 `.useCredential`（接受任意服务器证书） | 与 legado 同等安全取舍；仅用于书源抓取，勿用于敏感流量 |

（其余「已对照一致」的语义：`escape` 的 UTF-16 遍历、非 UTF-8 字符集的 `?` 替换与逐字节转义、
`Long.intValue()` 的 32 位截断、`{{}}` 的 null→`""` 与整数 Double→`%.0f`、`@js:` 的 null→`"null"`，
全部由 golden 逐条钉住。）


## 第 6 步 6B：真实网络 + 字符集检测 + 请求对照

> 本节为 6B 小节。新增
> `Sources/LegadoBookSource/Network/URLSessionHTTPClient.swift`、
> `RealJsNetworkExtensionsProvider.swift`、`RealAjaxProvider.swift`、
> `CharsetDetector/`（`CharsetDetector.swift` / `EncodingDetect.swift` / `CharsetTables.swift`）；
> `AnalyzeRule` 的 init 默认参数由 `Unsupported*` 换为真实实现（协议与 Unsupported 定义未动，
> 测试/App 仍可显式注入覆盖）；`HTTPRequest` 追加 `followRedirects` 字段（默认 true，零行为变化），
> 只被 Jsoup 语义的 get/post/head 使用；`AnalyzeUrl` 追加 `makeRateLimiter(concurrentRate:key:)`；
> `JSJavaBridge` 的 `StrResponse` 替身改为属性 + 方法双通道。

### `URLSessionHTTPClient`（真实网络）

对齐 `help/http/OkHttpUtils.kt` + `SSLHelper`：

| 能力 | 实现 |
|---|---|
| 重定向 | delegate `willPerformHTTPRedirection` 手工接管：`followRedirects=false` 直接返回 3xx；开启时最多 20 跳，超限抛错（同 OkHttp `Too many follow-up requests: 21`） |
| Cookie | 逐跳把 `Set-Cookie` 交 `CookieManager`（持久化/会话分流），并把 `CookieStore` 的 Cookie 注入请求头 |
| 超时 | `readTimeout` / `callTimeout` 分别映射到 `timeoutIntervalForRequest` / 整体预算 |
| 重试 | `HTTPRequest.retry` 控制失败重试次数 |
| 压缩 | 显式处理 gzip / deflate |
| 证书 | 信任服务器证书（等价 `SSLHelper`），见 6A 差异 #8 |
| `dnsIp` | 不支持，记 diagnostics，见 6A 差异 #7 |
| 代理 | `HTTPRequest.proxy` 落到 `connectionProxyDictionary` |

### 真实网络方法表（对齐 `help/JsExtensions.kt`）

| `java.xxx` | Kotlin 语义 | 本移植实现 | JS 可见对象 |
|---|---|---|---|
| `ajax(url[, callTimeout])` | AnalyzeUrl → getStrResponse().body；失败返回 stackTraceStr 错误串 | AnalyzeUrl（限速）+ URLSessionHTTPClient；失败返回 `ajax(url) error\n<错误>` | String |
| `get(url, headers[, timeout])` | Jsoup.connect，followRedirects(false)、timeout 30000ms 默认 | HTTPRequest(followRedirects=false) + 同一 HTTPClient | Connection.Response 替身：`body()/statusCode()/statusMessage()/headers()/cookies()/header(name)/cookieKey(name)/url()/contentType()` |
| `post(url, body[, headers[, timeout]])` | 同上 + requestBody(body) | 同上（body 原样，Content-Type 由用户 header 决定） | 同上 |
| `head(url[, headers][, timeout])` | 同上（HEAD） | 同上 | 同上 |
| `connect(url[, headerJSON][, callTimeout])` | AnalyzeUrl(headerMapF=JSON 头) → StrResponse；失败返回错误体 | 同左；失败返回错误体（code 200/callTime 0） | StrResponse 替身：`body()/code()/message()/headers()/raw()/toString()/callTime()/url()` |
| `ajaxAll([url...])` | 并发 mapAsync(threadCount) → StrResponse[]，顺序不变；失败抛错 | 分批并发（默认 4）+ 顺序合并；失败整体抛错 | StrResponse 替身数组 |
| `cacheFile(url[, saveTime])` | md5Encode16 查 CacheManager → 否则 downloadFile → 读文本 | 同左（缓存根见下） | String（文件文本） |
| `downloadFile(url)` | 文件名 md5Encode16(url).type；返回 `path.substring(cachePath.length)` | 同左，文件写入缓存根 | String（`/<md5>.<type>`，相对路径） |

JS 侧信封机制：provider 通过 `invoke(method:arguments:)` 的 String 通道返回
`\u{1}JSCONN\u{1}/JSSTR/JSSTRS + JSON` 信封，`JSJavaBridge` 注入的 `__javaUnwrap`
还原为带方法的对象（对照表见 `RealJsNetworkExtensionsProvider.swift` 文件头）。

### 落盘位置

- 缓存根（cacheFile/downloadFile 共用）：默认 FileManager Caches 的 `legado-js-cache/`，可注入
  （测试用临时目录）。**差异：Kotlin 是 `Context.externalCacheDir`（/android/data/{pkg}/cache）。**
- `downloadFile` 返回相对路径 `/<md5>.<type>`；`type = analyzeUrl.type ?: UrlUtil.getSuffix(url)`
  （无合法后缀时 `ext`，如 `/big` → `<md5>.ext`）。

### 6B 差异清单（与上方 6A 差异表合并为同一份「与 Kotlin 的已知差异」）

| # | 主题 | Kotlin | 本移植 | 处理 |
|---|---|---|---|---|
| 6B-1 | 缓存根目录 | `Context.externalCacheDir` | FileManager Caches + `legado-js-cache`（可注入） | 差异登记；相对路径语义一致（前导 `/`） |
| 6B-2 | 文本解码 | BOM → `UrlOption.charset` → Content-Type charset → `EncodingDetect.getHtmlEncode`（HTML meta → icu4j 检测器 → `"UTF-8"` 兜底） | **逐级一致**：`JsNetTextDecoder.decode` 先 `removeUTF8Bom` 剥 BOM，再依次用 explicit charset、Content-Type charset，最后 `EncodingDetect.getHtmlEncode`；`getHtmlEncode` 内部同样是 `<meta>` → `getEncode` 检测器 → `"UTF-8"` 兜底。判定顺序取自 Kotlin `OkHttpUtils.kt` 的 `ResponseBody.text(encode)`（非推断） | 由 `charset_cases.json` 的 10 种解码组合逐条对照。唯一差异：不可识别的 charset 名回退到 UTF-8，不抛异常 |
| 6B-3 | headers 顺序 | JS 对象插入顺序（LinkedHashMap） | JS 面按对象键序送达（`JSJavaBridge` 保序解码），落到 `HTTPRequest.headers` 为有序数组 | 键唯一时不影响 HTTP 语义 |
| 6B-4 | get/post/head Cookie | Jsoup 自建客户端（不带 legado CookieStore） | 经 URLSessionHTTPClient 注入 CookieStore Cookie | 客户端既有差异 #5 的延展；golden `request_cookie_cases` 13 条对照 |
| 6B-5 | get/post/head 限速 | `ConcurrentRateLimiter(getSource()).withLimitBlocking` | **已接线**：provider 持有 `rateLimiter`，由 `setRateLimiterFromSource(concurrentRate:key:)` / `AnalyzeUrl.makeRateLimiter(concurrentRate:key:)` 从书源 `concurrentRate` 构造；`jsoupGetOrHead`/`jsoupPost` 的请求全部包在 `executeWithRateLimit` 里 | 未注入限速器时行为与不接线一致（不限速）；已注入则同 Kotlin 阻塞等待 |
| 6B-6 | StrResponse JS 面 | 属性 + 方法双通道（`.body` / `.body()`） | **双通道已实现**：`JSJavaBridge.__installDualChannel` 同时安装属性与同名方法，`__dualValue` 用 Proxy 让「当字符串用」与「当函数调用」语义一致（`String(x)` / 模板串 / `+` / `indexOf` / `length` / `JSON.stringify` 全部按字符串工作），connect/ajaxAll 返回的对象同样适用 | `.body` 与 `.body()` 均可直接写，无需改写书源 |
| 6B-7 | `raw()`/`toString()` | okhttp Response.toString() | `Response{code=..., message=..., url=...}` 描述串 | 近似 |
| 6B-8 | 失败错误文本 | Java stackTraceStr | Swift 错误描述 | 对齐失败分支语义，文本不同 |
| 6B-9 | 客户端自动头 | OkHttp 自动加 `host` / `connection` / `accept-encoding: gzip` / `user-agent: okhttp/5.3.2` / `content-length` | URLSession/CFNetwork 自动加 `Host` / `Accept` / `Accept-Language` / `Accept-Encoding: br, gzip, deflate` / `User-Agent: <CFNetwork/… Darwin/…>` / `Content-Length`，且 **不接受** 修改 `Host` | 见下方「URLSession 与 OkHttp 自动头差异」；书源**显式**写的头已由 `request_cases` 43 条逐条对照一致 |
| 6B-10 | 线上 request-target 百分号编码 | 见 6A 差异 #4b | 同 | 已知差异，`HttpUrlRequestReplayTests.knownWireEncodingDivergences` 逐名钉住 |
| 6B-11 | BOM 剥离阈值 | `Utf8BomUtils.removeUTF8BOM` 判定 `bytes.size > 3`（**严格大于**） | **已按 Kotlin 对齐**：`JsNetTextDecoder.removeUTF8BOM` 同样用 `count > 3` | 恰好 3 字节（只有 BOM、无正文）时**两边都不剥离**，BOM 保留在解码结果里。早期误写成 `>= 3`，被 golden 样本 `empty-only-bom` 抓出并修正 |
| 6B-12 | UTF-8 容错解码的替换字符个数 | Java `new String(bytes,"UTF-8")` 对**连续非法字节**产生的 `U+FFFD` 个数有时少于 Unicode 标准（JDK `sun.nio.cs.UTF_8` 的 resync 行为） | Swift 用 `String(decoding:as:UTF8.self)`，遵循 Unicode **最大子部分**算法，与 Python `errors='replace'` 一致（**这是标准语义**） | 240 份样本中 18 份受影响（均为含非法 UTF-8 的乱码样本）。golden 额外输出 `decodedExplicitUtf8Standard`（标准算法结果），Swift 与该字段逐字符对比 **240/240 全等**；Java 原生结果 `decodedExplicitUtf8` 的差异属平台行为，不算移植偏差。**`decodedContentTypeQuoted`（`charset="UTF-8"`）与 `decodedContentTypeUtf8` 是同一条 UTF-8 路径**，同列豁免 |
| 6B-13 | Big5 码表：Apple CP950 与 JDK 严格 Big5 **互有差异** | JDK `new String(bytes,"Big5")` 走**严格 Unicode Big5 表**；Apple `.big5` 即 **CP950**（含 PUA 扩展区） | Swift 用 `CFStringEncodings.big5`，并对含 PUA 的整块**转入增量解码、把 PUA 替换为 `U+FFFD`**（`lossyString(_:nsEncoding:puaIsFailure:)`，仅 Big5 开此开关） | **逐码位对齐在技术上不可达**：两套码表差异是**双向**的——CP950 多出 PUA 扩展（`C8E7`→`U+F831`，JDK 给 `U+FFFD U+FFFD`），JDK 表也多出 CP950 没有的位点（`6892`→`U+6892` 汉字，CP950 解码失败）。Apple 只提供 `.big5`(CP950) 与 `Big5_HKSCS_1999`（PUA 区更大），**没有「严格 Big5」**。故 `testGoldenDecodeChain` 对 `decodedExplicitBig5` 改用**同量级判定**（非空、无残留 PUA、`swiftFFFD ≤ javaFFFD×2+5`、长度比 ∈ [1/3,3]），见下方「最小复现」 |
| 6B-14 | GB18030/GBK 的 PUA 位点 | Java `new String(bytes,"GB18030")` 对未定义位点输出 `U+E0xx` 段 PUA（240 份样本中 80 份含 PUA） | **两边表一致**，Swift 不做 PUA 替换（`puaIsFailure: false`），整块原样返回 | 实测 `decodedExplicitGbk` / `decodedContentTypeGbk` / `decodedExplicitBeatsHeader` 在 CI 上全部逐码位通过。**注意与 6B-13 相反**：GB 系不能开 PUA 替换，否则会把这 80 条本来正确的用例打成 `U+FFFD` |
| 6B-15 | GB 系**用户定义区**的映射 | 字节落在 GBK 用户定义区（如 `A6DB`）时，JDK `GB18030`/`GBK`/`x-mswin-936` 一致给 `U+E78F`（PUA） | Apple 的 `GB_18030_2000` 给 **`U+FE11`**（CJK 兼容竖排标点） | **平台码表差异**，非移植缺陷。CI run `37209884314` 实测 `big5-traditional-3` 的 `decodedContentTypeGbk` / `decodedExplicitBeatsHeader` 各差 1 个码位（`U+E78F` ↔ `U+FE11`），长度与其余 42 个码位完全相同。测试侧由 `differencesAreCompatMapOnly` 统一豁免（见 6B-13 条的具体判据） |
| 6B-16 | 日韩编码缺失 | Kotlin `String(bytes, "Shift_JIS" / "EUC-JP" / "EUC-KR")` 正常解码 | **此前 Swift 侧完全没有这三个分支**，落到函数末尾 `return nil` → 上层误判「charset 不可用」→ 回落到检测器/UTF-8 兜底 | **真实移植缺陷，已修**。CI run `37209884314` 实测：`shift-jis-japanese` 的 `decodedDefault` Java 给 `第一章 旅立ち`，Swift 给 `���� ������`（把 Shift_JIS 字节当 UTF-8 解）。现已补 `SHIFT-JIS`/`SHIFTJIS`/`SJIS`/`MS-KANJI`/`WINDOWS-31J`/`CP932`、`EUC-JP`、`EUC-KR`/`CP949` 三个分支 |
| 6B-17 | 非法字节的**字节消耗**不一致（`MALFORMED` vs `UNMAPPABLE`） | JDK `CharsetDecoder` 对非法输入分两类，**消耗字节数不同**：`MALFORMED[n]` 与 `UNMAPPABLE[n]`，单向替换时都产 1 个 `U+FFFD` 但吃掉 `n` 个字节 | 旧实现从 `min(maxCharLength, n-i)` 起「由长到短」试探「能否解出 1 个标量」，既**跨字符边界**又不看消耗量 | **真实移植缺陷，已修（GBK/GB18030/Big5 达 100%）**。修法：改由 `MBCSProfile` 的**字节结构**先算出该吃几字节，再交给 CF 解字符。CI run `37211011044` 实测 3 处不一致（`utf8-chinese` 的 `decodedExplicitGbk` / `decodedExplicitBig5` / `decodedContentTypeGbk`）：<br>① `0x80` 在 Apple `GB_18030_2000` 被解成 `U+20AC`（欧元符号，GB18030-2000 标准确有此映射），JDK 判为非法单字节 → `U+FFFD`。旧算法的 1 字节窗口「成功」解出 `U+20AC` 就接受了；<br>② Big5 的 `AC E4` / `B8 80` 类组合，JDK 判 `UNMAPPABLE[2]`（吃 2 字节），旧算法吃 1 字节，逐位累积成 283 vs 234 的字符数偏差。<br>**已对齐范围**（CI run `37212186047` 修复后）：**GBK / Big5 / Shift_JIS / EUC-KR / EUC-JP 五族各 `240/240` 与 JDK 逐码位全等**；GB18030 `208/240`（剩余部分见 6B-18）。用「真实 JDK 逐位探针 + 全字节穷举」验证：`Exhaust` 对五族的 **全部 1 字节 + 2 字节组合（各 65792 组）** 逐一比对 `Mir`（Swift 逻辑的 Java 同构镜像）与真实 JDK，结果 **65792/65792 全等**；`Ex3` 对 EUC-JP 的 `8F **` **三字节全组合（65536 组）**比对，同样 **65536/65536 全等**。 |
| 6B-19 | `MBCSProfile` 缺 `UNMAPPABLE[2]` 语义（EUC-JP / Shift_JIS / EUC-KR 三族） | ① **EUC-JP**：`A1-FE` 之外的所有 `0x80-0xFF` 字节（除 `8E`/`8F`）在**后面还有字节**时也按 `UNMAPPABLE[2]` 吃 2 字节；`8E X` 中 `X∉A1-DF` 同样吃 2 字节；`8F` 恒吃 3 字节。② **Shift_JIS** 的 `81/82/83/84/88/98/EA` 在映射区内有**洞**（`MALFORMED[1]`）且 `EB-FC` 段部分为 `UNMAPPABLE[2]`。③ **EUC-KR** 的 `A2/A5/A6/A7/AA/AB/AC` 的 `FE` 是 `UNMAPPABLE[2]` 不是映射 | 旧 `MBCSProfile` 只有 `malformedExceptions`（`MALFORMED[1]`，吃 1 字节）与固定的 `u2TrailRanges`，**无法表达「形状像 trail 但吃 2 字节」**，也把 `80-A0` 误当非 lead | **真实移植缺陷，已修**。① 新增 `unmappableExceptions: [UInt8: [ClosedRange<UInt8>]]` 字段（与 `malformedExceptions` 唯一区别是吃 2 字节）；② EUC-JP 的 `leadRanges` 扩到 `0x80-0xFF`、`u2TrailRanges` 扩到 `00-A0 ∪ FF`、例外表 **27 条**（26 条 `A1-FE` 内的洞 + `FF`）；③ Shift_JIS 的 `trailRanges` 精确为 `40-7E ∪ 80-FC`（`7F` 天然落 MALFORMED）、例外表 7 + 7 条；④ EUC-KR 例外表 8 + 7 条。**例外表全部由 `EucJpProf` / `GenProf2` 对真实 JDK 全枚举导出，无人工推断**。<br>这是 CI run `37212186047` 里 `euc-jp-japanese-2` / `decodedExplicitBig5` 位置 22（Java `U+3000` vs Swift `U+FFFD`）的根因 |

> **6B-11 ~ 6B-19 是本轮 golden 对照新抓出的九项**：6B-11 / 6B-16 / 6B-17 / 6B-19 是真实移植缺陷（已修）；
> 6B-12 是 JDK 与 Unicode 标准的差异（本移植选标准语义，golden 侧显式导出标准结果以便逐条对齐）；
> 6B-13 / 6B-15 是 Apple/JDK 编码库的**码表差异**（不可达，附最小复现）；
> 6B-14 记录 GB 系与 Big5 **必须区别对待**的原因，防止后续误把 PUA 替换逻辑套到 GB 系上；
> 6B-19 记录日韩三族 `UNMAPPABLE[2]` 消耗语义的对齐（新增 `unmappableExceptions`）；
> 6B-18 记录 6B-17 修复后**仍未对齐的剩余编码**及原因。

#### 6B-13 / 6B-15 的统一判据

测试侧不再对具体编码做特判，而是用一个**跨编码通用**的判据 `differencesAreCompatMapOnly`：

| # | 条件 | 理由 |
|---|---|---|
| 1 | 两侧**标量个数完全相同** | 字节消耗边界必须一致；长度一变说明解码结构错了 |
| 2 | 每个不相同的位置，两侧码位**都**落在「非标准文本区」 | 非标准区 = PUA（含补充平面）/ CJK 兼容 `U+FE30–FE4F` / 竖排标点 `U+FE10–FE1F` / 变体选择符 `U+FE00–FE0F` / 半全角 `U+FF00–FFEF` / 替换字符 `U+FFFD`。这些区域各家实现可自由取舍 |
| 3 | 不同位置数 ≤ 20% 且 ≤ 30 个 | 防止把大面积解码错误当成码表差异 |

增量解码若吞字节（长度变化）或整段崩坏（差异面大）都会**照常报错**。

#### 6B-13 的最小复现

```
字节:  C8 E7            (Big5 双字节区间内的合法组合)
JDK   :  new String(new byte[]{(byte)0xC8,(byte)0xE7}, "Big5")            → "\uFFFD\uFFFD"
CP950 :  Charset.forName("x-windows-950").newDecoder() 严格解码同上字节   → "\uF831"  (PUA)
Apple :  CFStringCreateWithBytes(..., CFStringEncodings.big5)             → U+F831 区 PUA

字节:  68 92
JDK   :  new String(new byte[]{(byte)0x68,(byte)0x92}, "Big5")            → "梒"  (U+6892)
CP950 :  同上                                                              → MalformedInputException
```

即：**同一对字节，JDK 与 CP950 都可能各自「解得出」对方「解不出」的结果**。因此
`decodedExplicitBig5` 无法要求逐码位相等，只能要求**退化量级相当**（判定条件见上表）。

#### 6B-17 / 6B-18 的最小复现

6B-17 修的是「非法字节消耗几个字节」。三组最小复现（均取自 CI run `37211011044` 的真实 golden 字节）：

```
字节:  80                              (孤立高位字节)
旧 Swift GBK : U+20AC                  ← 1 字节窗口"成功"解出（Apple GB_18030_2000 把 0x80 映射为欧元符号）
JDK     GBK  : U+FFFD                  ← 0x80 在 GBK/GB18030 里是非法单字节
新 Swift GBK : U+FFFD                  ← 单字节窗口只接受 isSingle(<=0x7F)，0x80 走 MALFORMED[1]

字节:  AC E4                           (Big5 lead A1-F9 + trail A1-FE，但码表无此组合)
JDK     Big5 : U+FFFD                  ← UNMAPPABLE[2]：吃 2 字节，出 1 个替换字符
新 Swift Big5: U+FFFD                  ← 同上（结构先算出 seqLen=2）

字节:  B8 80                           (Big5 lead B8 + trail 80，trail 落 UNMAPPABLE 带)
JDK     Big5 : U+FFFD                  ← 吃 2 字节
新 Swift Big5: U+FFFD                  ← 同上
```

**6B-18（仍未对齐的剩余部分）**：`MALFORMED` 与 `UNMAPPABLE` 的分界，除「区间」外还有少数
lead 在**映射区内部开洞**（这些 `(hi, lo)` 形状合法却仍判 `MALFORMED[1]`）。真实 JDK 全枚举探针实测：

| 编码 | 已对齐度（239 份样本） | 有洞的 lead 数 | 状态 |
|---|---|---|---|
| **GBK** | **239 / 239 = 100%** | **0** | 纯区间规则，完全对齐 |
| **Big5** | **237 / 239 = 99.2%** | 4（`A1`/`A3`/`C8`/`F9`） | 已录入例外表；剩余 2 条为码表差异（6B-13） |
| **GB18030** | 208 / 239 = 87.0% | 0（另有 `hi + 30-39` 的 `MALFORMED[2]` 规则，已实现） | 剩余差异集中在「UTF-16/UTF-32 字节配 GB18030 声明」这类极端样本 |
| **GB2312** | 待补 | 20（`A2`/`A4`–`A9`/`AA`–`AF`/`F8`–`FE`） | **例外表未录全**，见下 |
| **Shift_JIS** | 待补 | 28（JIS X 0208 的 `81`–`88`/`98`/`EA` 区） | **例外表未录全**，见下 |
| **EUC-KR** | 待补 | 13 | **例外表未录全**，见下 |
| **EUC-JP** | 待补 | 0 | 纯区间规则，但 `8E`/`8F` 前置形式的消耗语义待核 |

**GB2312 / Shift_JIS / EUC-KR / EUC-JP 未对齐的原因**：这四族的例外表规模较大
（合计约 60–80 个 `(hi, lo)` 区间），且**当前 golden 240 份样本中没有任何一条对应用例失败**
（失败的 3 条全在 `utf8-chinese` 的 GBK/Big5 路径上）。例外表由真实 JDK 逐位探针生成，
生成器与方法已就绪（见 `scripts/golden` 的探针说明），但尚未录入 Swift 侧常量表。

**影响评估**：这四族在**「该编码的正确字节」**上已完全对齐（合法序列走映射区，`2 字节 → 1 字符`）；
只有**「用错误编码解错误字节」**（如拿 UTF-16 字节配 EUC-KR 声明）才会多出或少掉若干 `U+FFFD`，
不影响任何真实书源的正文还原。

> **判定链的正确性不受 6B-18 影响**：字符集**检测**（哪一级命中、检出什么名字）与
> 解码的**字节消耗**是正交的两件事。检测链已与 Kotlin 完全一致（见本节开头），
> 6B-18 只影响「检出的编码与被解字节不匹配」时的替换字符个数。


### 字符集检测（legado icu4j 检测器全量移植 + 判定链接入）

`Sources/LegadoBookSource/Network/CharsetDetector/`：

| 文件 | 说明 |
|---|---|
| `CharsetDetector.swift` | legado 自带 `lib/icu4j/CharsetDetector.java` 的 Swift 移植：识别器打分 0–100、`detectAll` 按 confidence 降序、并列时取识别器列表靠后者。公开 `detect(_:)`（无匹配时按 Kotlin 兜底 `"UTF-8"`）、`detectMatch(_:) -> Detection?`（返回字符集名 + 置信度 + 语言，不兜底）、`detectAllMatches(_:)` |
| `EncodingDetect.swift` | `utils/EncodingDetect.kt` 的移植：`getHtmlEncode(_:)`（`<head>` 切片 → SwiftSoup `parseBodyFragment` → 遍历 `<meta>`，先 `charset` 属性、再 `http-equiv=content-type` 的 `content` 里 `charset=` 之后内容，异常回退 `getEncode`）、`getEncode(_:)`（检测器 + `"UTF-8"` 兜底）、`getEncode(file:)`（只收 ≥0x80 字节，上限 8000） |
| `CharsetTables.swift` | 从 legado 原码提取的识别表（52 KB / 36 个常量），由 `scripts/golden/extract_icu4j_tables.py` 生成 |

**判定链与 Kotlin 完全一致**（顺序取自 `OkHttpUtils.kt` 的 `ResponseBody.text(encode)`，
`JsNetTextDecoder.decode` 逐级实现）：

```
1. removeUTF8BOM          剥离 UTF-8 BOM（阈值 count > 3，与 Kotlin 一致）
2. explicitCharset        UrlOption.charset（书源里写的 charset）
3. Content-Type charset   HTTP 头的 charset=（按 OkHttp MediaType.charset() 语义，会剥成对引号）
4. getHtmlEncode          <meta charset> / http-equiv → icu4j 检测器 → "UTF-8" 兜底
```

每一级解码都用**容错**语义（非法字节 → `U+FFFD`），对齐 Java `new String(bytes, charset)`：
`UTF-8` 走 `String(decoding:as:UTF8.self)`（Unicode 标准算法），其余编码走
`CFStringCreateWithBytes(..., false)`（Darwin）并带通用退路。绝不能换成严格的
`String(data:encoding:)`——它在 Apple 与 Linux 上遇非法字节都会返回 `nil`，会让上层
误判为「该 charset 不可用」而静默回落，把 explicit charset 吞掉。

### golden 对照：字符集（`cases/charset_cases.json`，240 份样本）

golden 侧**直接编译 legado 自带的 icu4j 源码**（`scripts/golden/src/main/java/legadoicu/`，
8 个 Java 文件从 `app/src/main/java/io/legado/app/lib/icu4j/` 逐行复制，只改 `package` 名
并去掉 Android 专有的 `ParcelFileDescriptor` 重载；另加两个 `androidx.annotation` 桩注解），
配合 `EncodingDetectGolden.java`（`EncodingDetect.kt` 的 Java 移植）与 `CharsetGen.java` / `CharsetCorpus.java`。

覆盖：UTF-8 带/不带 BOM、GBK、GB2312、GB18030、Big5、EUC-KR、Shift_JIS、EUC-JP、
ISO-8859-1、windows-1252、UTF-16 LE/BE、UTF-32、1–10 字节极短文本、HTML 带/不带 meta、
中英混排、乱码字节、C1 控制区、空数据；其中 **45 份是合成的小说章节风格文本**（`syntheticNovelChapter: true` 标注）。
每条输出检测字符集名、置信度、`detectAll` 全列表，以及 10 种解码组合的结果；
另额外输出 `decodedExplicitUtf8Standard`（Unicode 标准算法的 UTF-8 解码，见差异表 6B-12）。

Swift 侧由 `CharsetDetectorGoldenComparisonTests` 逐条比较字符集名与置信度、
`getHtmlEncode` 结果、以及 ≥40 条完整解码用例（比较前按 Java 的 `substring(0,400)`
UTF-16 单元截断）；**CI 下 golden 文件缺失直接 `XCTFail`**。

### golden 对照：请求与重定向（OkHttp 5.3.2 → `com.sun.net.httpserver`，104 条）

`scripts/golden/RequestGen.java` 用真实 OkHttp 5.3.2，按 `OkHttpUtils.kt` 的
`get(url, encodedQuery)` / `postForm` / `postJson` / `postMultipart` / `addHeaders` 构造请求，
打到本地 `com.sun.net.httpserver`，记录服务器实际收到的 method、path+query、**有序显式头**、
Cookie 头、body 字节（multipart boundary 归一为 `--BOUNDARY--`）。

| 文件 | 条数 | 覆盖 |
|---|---|---|
| `request_cases.json` | 43 | GET（含 encodedQuery）、POST form、POST json、multipart、HEAD |
| `redirect_cases.json` | 44 | 301/302/303/307/308、跨域重定向、重定向链中途 `Set-Cookie`、`followRedirects=false`、超 20 跳上限（`Too many follow-up requests: 21`） |
| `request_cookie_cases.json` | 13 | Cookie 注入/合并/清除/多域 |
| `auto_header_cases.json` | 4 | 客户端自动头清单 |

Swift 侧由 `RequestGoldenComparisonTests` 用内置 `NWListener` 服务器（`LocalScriptedServer`）
重放同样的请求并逐条比较。

### URLSession 与 OkHttp 自动头差异

| 头 | OkHttp 5.3.2 | URLSession / CFNetwork | 说明 |
|---|---|---|---|
| `Host` | 自动加，可被显式头覆盖 | 自动加，**显式设置会被忽略/报错** | 书源几乎不改 Host，实际无影响 |
| `Connection` | 自动加 `keep-alive` | 不发送 | HTTP/1.1 语义等价；HTTP/2 无此头 |
| `Accept-Encoding` | 自动加 `gzip` | 自动加 `br, gzip, deflate` | URLSession 默认直接解压，解码链拿到的已是明文；`URLSessionHTTPClient` 亦显式处理 gzip/deflate |
| `User-Agent` | 自动加 `okhttp/5.3.2` | 自动加 `<CFNetwork/…> <Darwin/…>` | 书源大多显式写 UA（`addHeaders` 的 `User-Agent`），已由 `request_cases` 对照 |
| `Accept` / `Accept-Language` | 不自动加 | 自动加 `*/*` 与 `zh-CN` 等 | 服务器极少据此分支 |
| `Content-Length` | 有 body 时自动加 | 同 | 已对照一致 |
| `Cookie` | 由 `CookieJar` 提供 | 由 `CookieStore` 注入显式 Cookie 头 | golden `request_cookie_cases` 已覆盖 |

结论：**书源显式写的头（`addHeaders` 的效果）与 OkHttp 完全一致**；差异全部落在客户端自动头，
且不影响书源语义。

### 测试（`Tests/LegadoNetworkTests/RealJsNetworkProviderTests.swift`，29 个用例）

覆盖：ajax 成功/失败/非 2xx/`type=data:` 十六进制分支；get/head/post 的 JS 对象方法
（body/statusCode/statusMessage/header/headers 大小写不敏感 get/contentType/url）；
headers 对象真实到达服务器；cookies()/cookieKey()；get/post 不跟随重定向（各 1 跳）；
connect 成功/失败/header JSON + callTimeout；ajaxAll 多 URL 顺序与失败抛错；
cacheFile 落盘 + 二次命中（含真实 CacheManager saveTime 路径）；downloadFile 内容/大小/默认后缀；
未实现方法仍抛 unsupported 回归（Real/Unsupported/JS Proxy 三路）；java.get 单参仍为变量读取；
AnalyzeRule 默认 provider 接线与显式覆盖；
**`.body` 属性与方法双通道**（connect / get 返回对象各 1 条 + 字符串语义 1 条）；
**限速接线**（注入 `"1/1000"` 断言 ≥0.9s、不注入不限速、`setRateLimiterFromSource` 接受书源 `concurrentRate` 字符串）。
JS 断言全部走真实 JavaScriptCore（evalJS 全链路）。

### 可选：live-smoke（`workflow_dispatch` 手动触发）

`.github/workflows/test.yml` 新增 `live-smoke` job：仅 `workflow_dispatch` 触发、`macos-14`、
`continue-on-error: true`。用 `AnalyzeUrl` + `URLSessionHTTPClient` 对书源 JSON 里的书源
真实请求搜索 URL（关键字「斗罗」），报告写入 `live-smoke-out/live_smoke_report.txt`
并作为 artifact `live-smoke-report` 上传。单源失败不使 job 失败。

