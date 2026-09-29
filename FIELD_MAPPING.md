# Kotlin → Swift 字段对照清单

> 本清单覆盖任务要求移植的全部数据模型类。
> 校验脚本：`scripts/verify_fields.py`（对每个字段做词边界匹配，确认在对应 Swift 文件里出现）。
> **「Kotlin 有但 Swift 没实现的字段」清单：空。** 全部 225 个数据字段均已实现。

## 移植范围说明

本步骤**只做数据模型**，不做规则解析引擎、网络请求、UI、持久化。因此：

- 每个 Kotlin `data class` → 一个 Swift `struct`，遵循 `Codable`。
- 字段名 / JSON key 与 Kotlin **完全一致**，不改名、不转 snake_case。
- Kotlin 可空字段 → Swift `Optional`；有默认值字段 → `decodeIfPresent` + **同样的默认值**，JSON 缺字段不报错。
- Kotlin 的 `@Ignore` / `@IgnoredOnParcel` 运行时字段（如 `infoHtml`、`tocHtml`、`downloadUrls`、`titleMD5`）在 Swift 里保留为普通属性但**不参与 Codable**（不在 `CodingKeys` 中）。
- Kotlin 的运行时业务方法（JS 执行、DB、变量存取、URL 拼接等）**不移植**，在各文件以 `TODO(后续步骤)` 注释标出。
- Kotlin 的 Room `Converters`（Rule ↔ JSON 字符串）通过 `StringOrObject` property wrapper 实现：解码兼容「对象」与「JSON 字符串」两种形式，编码统一输出为对象。

---

## 1. BookSource（32 字段）→ `Sources/LegadoBookSource/BookSource.swift`

| Kotlin 字段 | Kotlin 类型 / 默认值 | Swift 实现 |
|---|---|---|
| bookSourceUrl | String = "" | `@LenientString<EmptyString>` |
| bookSourceName | String = "" | `@LenientString<EmptyString>` |
| bookSourceGroup | String? = null | `@LenientOptionalString` |
| bookSourceType | Int = 0 | `@LenientInt<ZeroInt>` |
| bookUrlPattern | String? = null | `@LenientOptionalString` |
| customOrder | Int = 0 | `@LenientInt<ZeroInt>` |
| enabled | Boolean = true | `@LenientBool<TrueBool>` |
| enabledExplore | Boolean = true | `@LenientBool<TrueBool>` |
| jsLib | String? = null | `@LenientOptionalString` |
| enabledCookieJar | Boolean? = true | `@LenientOptionalBool`（可空，默认 true 见构造器） |
| concurrentRate | String? = null | `@LenientOptionalString` |
| header | String? = null | `@LenientOptionalString` |
| loginUrl | String? = null | `@LenientOptionalString` |
| loginUi | String? = null | `@LenientOptionalString` |
| loginCheckJs | String? = null | `@LenientOptionalString` |
| coverDecodeJs | String? = null | `@LenientOptionalString` |
| bookSourceComment | String? = null | `@LenientOptionalString` |
| variableComment | String? = null | `@LenientOptionalString` |
| lastUpdateTime | Long = 0 | `@LenientInt64<ZeroInt64>` |
| respondTime | Long = 180000L | `@LenientInt64<RespondTimeDefault=180000>` |
| weight | Int = 0 | `@LenientInt<ZeroInt>` |
| exploreUrl | String? = null | `@LenientOptionalString` |
| exploreScreen | String? = null | `@LenientOptionalString` |
| ruleExplore | ExploreRule? = null | `@StringOrObject<ExploreRule>` |
| searchUrl | String? = null | `@LenientOptionalString` |
| ruleSearch | SearchRule? = null | `@StringOrObject<SearchRule>` |
| ruleBookInfo | BookInfoRule? = null | `@StringOrObject<BookInfoRule>` |
| ruleToc | TocRule? = null | `@StringOrObject<TocRule>` |
| ruleContent | ContentRule? = null | `@StringOrObject<ContentRule>` |
| ruleReview | ReviewRule? = null | `@StringOrObject<ReviewRule>` |
| eventListener | Boolean = false | `@LenientBool<FalseBool>` |
| customButton | Boolean = false | `@LenientBool<FalseBool>` |

> 说明：`enabledCookieJar` 在 Kotlin 中类型为 `Boolean?`，构造默认值 `true`，Room 列默认 `"0"`。Swift 保留其可空性（`Bool?`），构造器默认 `true`，与 Kotlin 构造语义一致。

## 2. BaseSource（接口，6 字段）→ `BaseSource.swift`

concurrentRate, loginUrl, loginUi, header, enabledCookieJar, jsLib —— 全部在 protocol 声明并由 `BookSource` 实现。运行时方法（`login()` / `getHeaderMap()` / `evalJS()` 等）以 TODO 标出，不移植。

## 3. rule/ 目录

- **BookListRule**（接口，10 字段）→ `Rule/BookListRule.swift`：protocol。
- **SearchRule**（11 字段）→ `Rule/SearchRule.swift`：checkKeyWord + BookListRule 10 字段。
- **ExploreRule**（10 字段）→ `Rule/ExploreRule.swift`。
- **BookInfoRule**（12 字段）→ `Rule/BookInfoRule.swift`：`init` 用反引号 `` `init` `` 处理关键字。
- **TocRule**（10 字段）→ `Rule/TocRule.swift`。
- **ContentRule**（11 字段）→ `Rule/ContentRule.swift`。
- **ReviewRule**（10 字段）→ `Rule/ReviewRule.swift`。
- **ExploreKind**（8 字段）→ `Rule/ExploreKind.swift`：`chars: Array<String?>?` → `[String?]?`；内嵌 `object Type` → enum 命名空间；自定义 equals 保留。
- **FlexChildStyle**（6 字段）→ `Rule/FlexChildStyle.swift`：Float 字段保持 Float；UI 方法（`apply(view:)`）不移植。
- **RowUi**（7 字段）→ `Rule/RowUi.swift`：同 ExploreKind 处理。

## 4. Book（33 字段）→ `Book.swift`

全部字段见表（`bookUrl … syncTime`）。内嵌 `ReadConfig`（16 字段）单列见下。运行时 `@Ignore` 字段 `infoHtml`/`tocHtml`/`downloadUrls`/`folderName` 不参与 Codable（folderName 为私有实现细节，未建模）。

### Book.ReadConfig（16 字段）→ `Book.swift` 内嵌

reverseToc, pageAnim, reSegment, imageStyle, useReplaceRule, delTag, ttsEngine, splitLongChapter, readSimulating, **startDate**, startChapter, dailyChapters, openCredits, closeCredits, playMode, playSpeed。

> **TODO / 不确定点**：`startDate` 在 Kotlin 为 `java.time.LocalDate?`，其 JSON 序列化格式取决于 Gson 的 LocalDate 适配器（项目中未见显式注册）。为避免猜测日期格式，Swift 暂以 `String?` 承载其原始 JSON 表示，已在源码中以 TODO 标注，待确认存储格式后再改为强类型。**未发明新字段，未丢字段。**

## 5. BookChapter（17 字段）→ `BookChapter.swift`

url, title, isVolume, baseUrl, bookUrl, index, isVip, isPay, resourceUrl, tag, wordCount, start, end, startFragmentId, endFragmentId, variable, imgUrl。运行时 `@Ignore titleMD5` 不参与 Codable。

## 6. SearchBook（18 字段）→ `SearchBook.swift`

bookUrl, origin, originName, type, name, author, kind, coverUrl, intro, wordCount, latestChapterTitle, tocUrl, time, variable, originOrder, chapterWordCountText, chapterWordCount(-1), respondTime(-1)。运行时 `@Ignore infoHtml/tocHtml` 不参与 Codable。Comparable 语义按 Kotlin `compareTo` 移植。

## 7. BaseBook（接口，8 字段）→ `BaseBook.swift`

name, author, bookUrl, kind, wordCount, variable, infoHtml, tocHtml —— protocol 声明。`getKindList()` 纯数据方法已移植；变量存取（依赖 GSON/缓存）以 TODO 标出。

---

## 时间默认值处理说明

Kotlin 中 `latestChapterTime` / `lastCheckTime` / `durChapterTime` / `SearchBook.time` 的**构造默认值**为 `System.currentTimeMillis()`，但 Room **列默认值**为 `"0"`。
Swift 移植：**构造器**默认用当前毫秒时间戳（与 Kotlin 构造语义一致），但**JSON decode 缺字段**时用 `0`（与数据库落库语义一致，保证 decode 确定性与可复现的 round-trip）。这是为了让「导入书源 JSON → 导出 → 再导入」结果稳定一致。

## 判等 / 哈希

各实体的自定义 `equals`/`hashCode`（BookSource 按 bookSourceUrl、Book/SearchBook 按 bookUrl、BookChapter 按 url、ExploreKind/RowUi 按选定字段）均按 Kotlin 语义移植。
各 Rule struct 额外实现了**逐字段** `Equatable`（Swift 自动合成），用于 round-trip 一致性测试。
