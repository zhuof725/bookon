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

Tests/LegadoBookSourceTests/
├── BookSourceImporterTests.swift
└── Resources/test_bookSources.json   # 4 个真实书源（前 3 字符串形式，第 4 对象形式）
```

## 运行测试

```bash
swift test
```

macOS / Linux（带 Swift 工具链）均可。仓库配置了 GitHub Actions（`.github/workflows/test.yml`）在 macOS runner 上自动 `swift build` + `swift test`。

## 关键设计

1. **字段名 100% 对齐** Kotlin，不转 snake_case，可直接导入现有书源 JSON。
2. **宽松解码**：数字↔字符串↔布尔(0/1) 互转由 property wrapper 处理，缺字段用同样默认值，绝不因类型不符或缺字段报错。
3. **规则字段两用**：`ruleSearch` 等既能吃「对象」也能吃「JSON 字符串」（内层再嵌一层 JSON），编码统一输出对象。对应 Kotlin `BookSource.Converters` + 各 Rule 的 `jsonDeserializer`。
4. **逐条容错导入**：一条坏书源不影响其他，返回成功/失败两个列表。

## 字段覆盖

见 [FIELD_MAPPING.md](FIELD_MAPPING.md)。**「Kotlin 有但 Swift 没实现的字段」清单为空**（225/225 覆盖）。

## 后续步骤（TODO）

源码中以 `TODO(后续步骤)` 标注：BaseSource/BaseBook 运行时方法、Book/BookChapter/SearchBook 业务方法、变量存取、`ReadConfig.startDate` 的 LocalDate 强类型化、SwiftData/GRDB 持久化接入。
