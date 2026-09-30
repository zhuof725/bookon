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

> 不支持的语法在解析时抛 `JSONPathError.unsupportedSyntax`；`AnalyzeByJSonPath` 会（如同 Kotlin 吞异常）
> 返回空值，并把错误记入可选的 `RuleEngineDiagnostics`（默认关闭）。

## 非致命错误：诊断而非静默 / 抛出

Kotlin 里 `AnalyzeByJSonPath` 用 `try-catch` + `e.printOnDebug()` 吞掉的异常（如 JSONPath 读取失败），
本移植**保持返回空值的行为不变**，同时提供可选的 `RuleEngineDiagnostics` 收集器（默认 `nil`，不收集、不影响返回值）。
构造时传入即可记录：`AnalyzeByJSonPath(json, diagnostics: collector)` / `AnalyzeByRegex.getElement(..., diagnostics: collector)`。

> ⚠️ 两处「致命」路径按 Kotlin 原行为复刻（非本移植新增）：`RuleAnalyzer` 括号不平衡（Kotlin 抛 `Error`）、
> `AnalyzeByRegex.getElement` 最后规则里捕获组未参与匹配（Kotlin `group(i)!!` 抛 NPE）——Swift 用 `fatalError` 触发。

## 样本诚实标注

- `synthetic_lieying_like.json`、以及测试里各内联 JSON：**合成样本，非真实数据**（文件名 `synthetic_` 前缀 +
  文件内 `_SAMPLE_KIND` 字段 + 测试注释三处标注）。
- `Resources/real/muli_real_source.json`（🍅木里番茄）、`Resources/real/qimo_real_source.json`（七猫小说）：
  **真实书源，来源：用户提供**，放在 `real/` 目录。
- 用真实书源『规则文本』+ 合成『数据』的测试（如木里的 `$.author||...` 短路），已在注释里注明「规则真实 / 数据合成」。

## 函数与分支覆盖

见 [FUNCTION_MAPPING.md](FUNCTION_MAPPING.md)。`scripts/verify_functions.py` 自动从 Kotlin 源码提取全部 `fun` 校验，
**「Kotlin 有但 Swift 没实现的函数」清单为空**（17/17）。分支→测试对照表见该文件，未覆盖分支已明确标出。

## 第 2 步测试规模

RuleAnalyzer 34 + AnalyzeByRegex 12 + AnalyzeByJSonPath 28 + RuleEnginePublicAPI 5，
连同第 1 步共 **93 个测试**，Linux (swift 5.10.1) 与 macOS (swift 5.10) 两平台 `swift build` + `swift test` 全绿。

## 后续步骤（TODO）

源码中以 `TODO(后续步骤)` 标注：BaseSource/BaseBook 运行时方法、Book/BookChapter/SearchBook 业务方法、变量存取、`ReadConfig.startDate` 的 LocalDate 强类型化、SwiftData/GRDB 持久化接入。
第 2 步之后仍未做：JSoup / XPath 后端、`AnalyzeRule` 总调度、JS 引擎、网络、UI（本步骤不含，按任务约定）。
