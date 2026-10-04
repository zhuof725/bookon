# MBCS 字节消耗语义对拍工具

本目录是 `LegadoBookSource` 里 `RealJsNetworkExtensionsProvider` 的 MBCS（多字节字符集）
容错解码逻辑的**可复现验证夹具**。它解决一个具体问题：

> Swift 的 `incrementalLossyDecode` 必须逐字节复刻 JDK `CharsetDecoder` 的
> `MALFORMED[n]` / `UNMAPPABLE[n]` 消耗语义（两者都产 1 个 `U+FFFD`，但吃掉
> 的字节数不同），否则解码结果会从此处起**整体错位**。

因为 Apple 的 CoreFoundation 表与 JDK 表在这些边角上有差异，且 Apple 不提供
「严格 Big5 / 严格 GBK」编码，验证不能只靠在 macOS 上跑测试——必须有一个
**以真实 JDK 为唯一真值**的对拍通道。

## 文件

| 文件 | 作用 |
|---|---|
| `Mir.java` | Swift `MBCSProfile` + `incrementalLossyDecode` 的 **Java 同构镜像**。参数与 Swift 源码逐字段对应；`tryDecode` 用 JDK 表代替 CF 表（对 GBK/EUC-JP/EUC-KR/Shift_JIS 两表一致）。 |
| `JdkProf.java` | 逐 lead 导出 JDK 的真实分带：`<hi> MAP… U… M…`，即每个 `(lead, trail)` 判 `MAP` / `UNMAPPABLE[n]` / `MALFORMED[n]`。 |
| `EucJpProf.java` | EUC-JP 全 94 个 lead × 256 个 trail 的完整分带（用于导出 26 条「映射洞」）。 |
| `GenProf2.java` | 通用导出器：给定编码名，输出单字节集、lead 区间、每 lead 分带。EUC-KR / Shift_JIS 的例外表由它生成。 |
| `G2312Prof.java` | GB2312 全 87 个 lead × 256 个 trail 的分带导出（由它得出 GB2312 的 `u2 = 80-A0 ∪ FF`，见 README 6B-21）。 |
| `Cross2.java` | 对 240 份 golden 样本（`charset_cases.json`）逐条比较 `Mir` 与真实 JDK，输出各族通过率。 |
| `Exhaust.java` | **穷举**：对六族的全部 1 字节 + 2 字节组合（各 65792 组）比较 `Mir` 与 JDK。 |
| `Ex3.java` | **穷举**：EUC-JP 的 `8F **` 三字节全组合（65536 组）。 |
| `U16Ex.java` | **穷举**：UTF-16LE 的 1+2 字节全组合（65792 组）+ 高代理开头的 4 字节组合（325 万组）——验证 `MALFORMED[4]`（高代理 + 非低代理吃 2 个码元）语义。 |

## 用法

需要 JDK 21+ 与 `gson`（`Cross2` 用）。golden 数据由 `scripts/golden` Maven 工程生成。

```bash
# 编译
javac -encoding UTF-8 Mir.java JdkProf.java EucJpProf.java GenProf2.java G2312Prof.java Exhaust.java Ex3.java U16Ex.java

# 逐 lead 分带
java JdkProf SHIFT-JIS 81
java JdkProf EUC-JP single

# 生成某族的完整 profile（含例外表素材）
java GenProf2 EUC-KR

# 240 份 golden 样本对拍
java -cp "$GSON_JAR:." Cross2          # 读 /tmp/golden_out/charset_cases.json，可用 -Dgolden= 覆盖

# 穷举验证（全字节空间）
java -Xss64m Exhaust
java Ex3
```

## 当前结果（2026-10，JDK 21）

```
Cross2（240 份 golden 样本，JDK 真值现算）:
  EUC-JP     240/240  ✅
  SHIFT-JIS  240/240  ✅
  EUC-KR     240/240  ✅
  GBK        240/240  ✅
  GB2312     240/240  ✅
  BIG5       240/240  ✅
  GB18030    208/240        ← 4 字节序列差异，见 README 差异表 6B-18 / 6B-22

Exhaust（全 1 字节 + 2 字节组合）:
  GBK        65792/65792 ✅
  GB2312     65792/65792 ✅
  BIG5       65792/65792 ✅
  SHIFT-JIS  65792/65792 ✅
  EUC-KR     65792/65792 ✅
  EUC-JP     65792/65792 ✅

Ex3（EUC-JP 的 8F ** 三字节组合）:
  EUC-JP     65536/65536 ✅

U16Ex（UTF-16LE）:
  1+2 字节     65792/65792 ✅
  高代理 4 字节 3250426/3250426 ✅
```

## 修改 Swift profile 时的注意

`Mir.java` 的 `P` record 字段与 Swift `MBCSProfile` 一一对应：

| Swift 字段 | Mir 字段 |
|---|---|
| `singleByteMax` | `singleMax` |
| `singleByteExtra` | `sbExtraLo` / `sbExtraHi` |
| `leadRanges` | `lead` |
| `trailRanges` | `trail` |
| `u2TrailRanges` | `u2` |
| `m2TrailRanges` | `m2` |
| `malformedExceptions` | `exc` |
| `unmappableExceptions` | `exc2` |
| `threeByteLead` | `three` |
| `fourByteDigitRange` | `digit` |
| `useJdkBig5Table` | `jdkBig5` |

**改 Swift 的 `mbcsProfile` 后必须同步改 `Mir.java`**，否则对拍结论失效。

生成例外表时，用 `GenProf2` / `EucJpProf` 的**全枚举输出直接导出，不要人工推断区间**——
这两族的分带在映射区内部开洞，肉眼归纳必错（本轮即因人工推断导致 EUC-JP 从 240 掉到 146）。
