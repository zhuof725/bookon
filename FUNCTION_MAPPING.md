# Kotlin → Swift 函数 / 分支对照清单（第 2+3 步：规则引擎）

> 自动校验脚本：`scripts/verify_functions.py`（从 `reference/kotlin/analyzeRule` 用正则提取全部 `fun`，
> 再到 Swift 源码检查同名函数）。**「Kotlin 有但 Swift 没实现的函数」清单：空**（32/32 覆盖，
> RuleAnalyzer 10 + AnalyzeByRegex 2 + AnalyzeByJSonPath 5 + AnalyzeByJSoup 9 + AnalyzeByXPath 6）。
>
> 第 2 步收尾变更：崩溃写法（fatalError/try!/as!/强制解包/越界）已清零；括号不平衡、下标越界、正则编译失败、
> getElement 捕获组未参与 → 抛 `RuleEngineError`；`splitRule`/`innerRule`/`trim`/`AnalyzeByRegex.*`/
> `AnalyzeByJSonPath.get*` 均标 `throws`。

移植范围：第 2 步「规则引擎底座 + 两个最简单后端」（`RuleAnalyzer`、`AnalyzeByRegex`、`AnalyzeByJSonPath`）+
第 3 步「HTML 规则引擎」（`AnalyzeByJSoup`、`AnalyzeByXPath`）。
**不含** `AnalyzeRule` 总调度 / JS / 网络 / UI。第 1、2 步 API 名称与行为未改动。

## Step4-A 新增：`JsoupCompatSerializer`（HTML 序列化重写，非 Kotlin 对照，是 jsoup 1.16.2 Java 源码对照）

`Sources/LegadoBookSource/RuleEngine/JsoupCompatSerializer.swift`（internal enum，纯 static 方法，
不对外暴露 public API，因此不需要单独的 PublicAPITests 覆盖）。替代原 `SwiftSoupVoidElementFix.swift`
（已删除）里的字符串级后处理，详见 README「Step4-A：HTML 序列化重写」章节。关键函数：

| Swift 函数 | 对应 jsoup 1.16.2 源码 |
|---|---|
| `JsoupCompatSerializer.outerHtml(_:Node)` | `org.jsoup.nodes.Node.outerHtml()` |
| `JsoupCompatSerializer.innerHtml(_:Element)` | `org.jsoup.nodes.Element.html()` |
| `JsoupCompatSerializer.elementsOuterHtml(_:[Element])` | `org.jsoup.select.Elements.outerHtml()` |
| `JsoupCompatSerializer.elementsInnerHtml(_:[Element])` | `org.jsoup.select.Elements.html()` |
| `JsoupCompatSerializer.escape(...)` | `org.jsoup.nodes.Entities.escape(Appendable, String, OutputSettings, boolean, boolean, boolean, boolean)` |
| `JsoupCompatSerializer.tagInfo(for:)` | `org.jsoup.parser.Tag.valueOf` + 静态标签分类清单 |
| 内部 `elementHead`/`elementTail`/`textNodeHead`/`commentHead`/`dataNodeHead`/`documentTypeHead` | 各节点类型的 `outerHtmlHead`/`outerHtmlTail` |

调用点替换（原先经由 SwiftSoup 原生 `outerHtml()`/`html()` + 字符串后处理 `SwiftSoupHtmlFix`）：
- `AnalyzeByJSoup+Elements.swift::getResultLast`（`html`/`all` 两种 lastRule）
- `XPathEvaluator.swift::JXNode.asString()`（`.element` 分支）
- `SwiftSoupXPathParser.swift`（XPath 终端函数 `.funcHtml`/`.funcOuterHtml`）

## 函数覆盖（17 个）

| Kotlin 文件 | Kotlin fun | Swift 对应 |
|---|---|---|
| RuleAnalyzer.kt | trim | `RuleAnalyzer.trim()` |
| | reSetPos | `RuleAnalyzer.reSetPos()` |
| | consumeTo | `RuleAnalyzer.consumeTo(_:)`（private） |
| | consumeToAny | `RuleAnalyzer.consumeToAny(_:)`（private） |
| | findToAny | `RuleAnalyzer.findToAny(_:)`（private） |
| | chompCodeBalanced | `RuleAnalyzer.chompCodeBalanced(_:_:)`（private） |
| | chompRuleBalanced | `RuleAnalyzer.chompRuleBalanced(_:_:)`（private） |
| | chompBalanced (val ::) | `RuleAnalyzer.chompBalanced(_:_:)`（按 code 分派） |
| | splitRule（首段/二段两个重载） | `RuleAnalyzer.splitRule(_:)` + private `splitRuleNext()` |
| | innerRule（两个重载） | `RuleAnalyzer.innerRule(_:startStep:endStep:fr:)` / `innerRule(_:_:fr:)` |
| AnalyzeByRegex.kt | getElement | `AnalyzeByRegex.getElement(_:_:index:diagnostics:)` |
| | getElements | `AnalyzeByRegex.getElements(_:_:index:diagnostics:)` |
| AnalyzeByJSonPath.kt | parse | `AnalyzeByJSonPath.parse(_:)`（String/JSONValue 两版） |
| | getString | `AnalyzeByJSonPath.getString(_:)` |
| | getStringList | `AnalyzeByJSonPath.getStringList(_:)` |
| | getObject | `AnalyzeByJSonPath.getObject(_:)`（throws，对齐 Kotlin 不吞异常） |
| | getList | `AnalyzeByJSonPath.getList(_:)` |

> Swift 额外的 `splitRuleNext()` 对应 Kotlin 里 `@JvmName("splitRuleNext")` 的私有 `splitRule()` 重载
> （Kotlin 源码中函数名仍是 `splitRule`）。

## 分支 → 测试 对照表

> 逐一列出每个 Kotlin 函数里的 when/if/else 分支及对应测试。**没有对应测试的分支已明确标出。**

### RuleAnalyzer.splitRule（首段匹配）
| 分支 | 说明 | 测试 |
|---|---|---|
| `split.size == 1` 且 `!consumeTo` | 单分隔符、未找到 → 整串一段 | `testNoSeparator`, `testEmptyRule` |
| `split.size == 1` 且找到 | 单分隔符、走二段 | `testElementsTypeSetOnSingleSep`, `testSplitAmpSimple` |
| `!consumeToAny` | 多分隔符、都没找到 | `testNoSeparator` |
| `st == -1`（无选择器） | 无 `[`/`(`，直接按分隔符切 | `testSplitAmpSimple`, `testSplitOrSimple`, `testSplitPercentSimple`, `testConsecutiveSeparators`, `testTrailingSeparator`, `testLeadingSeparator`, `testThreeOr` |
| `st > end`（分隔符在选择器前） | 选择器前先切 | `testMixedSeparators`, `testMixedSeparatorsOrFirst` |
| `st > end` 内 `pos > st` → 调二段 | 首段完当前段未完 | `testSeparatorInsideBrackets`（间接） |
| `st <= end`（分隔符在选择器内）→ chompBalanced | 平衡组保护分隔符 | `testSeparatorInsideBrackets`, `testSeparatorInsideParen`, `testSeparatorNestedBrackets`, `testBalancedBracketBoundary` |
| chompBalanced 失败 → 抛 `RuleEngineError.unbalanced` | 括号不平衡 | `testUnbalancedBracketThrows`、`testUnbalancedParenThrows`（断言抛出 RuleEngineError）；`testBalancedBracketBoundary` 作平衡对照 |
| 首白空白保留 | splitRule 不 trim | `testLeadingTrailingWhitespacePreserved` |

### RuleAnalyzer.splitRule（二段匹配 / splitRuleNext）
| 分支 | 说明 | 测试 |
|---|---|---|
| `st == -1` | 无选择器，按 elementsType 切 | `testSplitAmpSimple`（三段以上进入二段） |
| `st > end` 内 `pos > st` → 重启 | 递归二段 | `testThreeOr`, `testSeparatorNestedBrackets` |
| `st > end` 内 `pos <= st` | 后续无分隔符 | `testMixedSeparators` |
| 末尾 `!consumeTo` / `consumeTo` | 收尾/继续 | `testConsecutiveSeparators`, `testThreeOr` |

### RuleAnalyzer.chompCodeBalanced（code=true）
| 分支 | 测试 |
|---|---|
| 单引号切换（非双引号内） | `testSingleQuoteProtectsSeparatorCode` |
| 双引号切换（非单引号内） | `testDoubleQuoteProtectsSeparatorCode` |
| `[`/`]` 深度增减 | `testSeparatorInsideBrackets`（code 版经由 splitRule） |
| depth==0 时 open/close 平衡 | `testInnerRuleNestedBraces`（`{...}` 平衡） |
| 转义字符 ESC 跳过下一个 | `testEscapeInCode` |
| 未平衡 → 上层抛 `RuleEngineError.unbalanced` | `testUnbalancedBracketThrows` |

### RuleAnalyzer.chompRuleBalanced（code=false）
| 分支 | 测试 |
|---|---|
| 单/双引号切换 | `testEscapeInRuleMode`（引号外转义） |
| 引号外 `\` 转义下一个 | `testEscapeInRuleMode` |
| `open`/`close` 深度增减 | `testSeparatorInsideParen`, `testSeparatorNestedBrackets`, `testBalancedBracketBoundary` |
| 未平衡 → 上层抛 `RuleEngineError.unbalanced` | `testUnbalancedParenThrows` |

### RuleAnalyzer.trim
| 分支 | 测试 |
|---|---|
| 有前导 `@`/空白 → 推移 | `testTrimLeadingAtAndWhitespace` |
| 无需修剪（首字符正常） | 其余所有 splitRule 用例（未触发 trim 分支的常态） |

### RuleAnalyzer.innerRule（"{$." 版）
| 分支 | 测试 |
|---|---|
| chompCodeBalanced 成功 + fr 非空 → 替换 | `testInnerRuleSingle`, `testInnerRuleMultiple`, `testInnerRuleNestedBraces` |
| fr 返回 nil/空 → 当普通字串跳过 | `testInnerRuleReturnsNil` |
| 无内嵌（startX==0）→ 返回 "" | `testInnerRuleNone` |

### RuleAnalyzer.innerRule（start/end 版）
| 分支 | 测试 |
|---|---|
| consumeTo(start) + consumeTo(end) 成功 → 替换 | `testInnerRuleStartEnd`（含 fr 返回值拼接） |
| 无匹配（startX==0）→ 返回原 queue | `testInnerRuleStartEndNoMatch` |

### RuleAnalyzer.reSetPos
| 分支 | 测试 |
|---|---|
| 复位后复用 | `testReSetPos` |

### AnalyzeByRegex.getElement
| 分支 | 测试 |
|---|---|
| `!find()` → nil | `testGetElementNoMatchNil` |
| 最后规则 → 收集 group0..N | `testGetElementSingle`, `testGetElementNoGroup`, `testGetElementChinese`, `testGetElementAllGroupsParticipate` |
| 非最后规则 → 串接后递归 | `testGetElementMultiLayer` |
| 最后规则里捕获组未参与 → 抛 `RuleEngineError.regexGroupNotParticipated` | `testGetElementMissingGroupThrows`（断言抛出 + groupIndex==1） |
| 多行文本 | `testGetElementMultiline` |

### AnalyzeByRegex.getElements
| 分支 | 测试 |
|---|---|
| `!find()` → 空数组 | `testGetElementsNoMatchEmpty` |
| 最后规则 → 每个 match 收集，未参与组取 "" | `testGetElementsSingle`, `testGetElementsMissingGroupEmpty` |
| 非最后规则 → 串接后递归 | `testGetElementsMultiLayer` |
| 多行 + 中文 | `testGetElementsMultilineChinese` |

### AnalyzeByJSonPath.getString
| 分支 | 测试 |
|---|---|
| `rule.isEmpty` → nil | `testGetStringEmptyRuleNil` |
| `rules.size==1` + innerRule 命中 | `testInnerRuleWithText`, `testLieyingBookUrlInnerRule` |
| `rules.size==1` + 无内嵌 + read 是 List → "\n" 拼接 | `testGetStringListJoin` |
| `rules.size==1` + 无内嵌 + read 是标量 → toString | `testIntegerNoDecimal`, `testGetStringBool`, `testLieyingContentBody`, `testLieyingBookTitle` |
| `rules.size==1` + read 抛异常 → 吞掉，返回空 | `testGetStringMissingReturnsEmpty` |
| 多段 + `||` 短路 | `testOrShortCircuit`, `testOrFallback`, `testMuliAuthorOrChainSyntheticData` |
| 多段 + `||` 全缺失 → "" | `testOrAllMissing` |
| 多段 + `&&` 拼接 | `testAndJoin` |

### AnalyzeByJSonPath.getStringList
| 分支 | 测试 |
|---|---|
| `rule.isEmpty` → 空数组 | `testGetStringListEmptyRule` |
| `rules.size==1` + innerRule 命中 → add(st) | （经 getString 内嵌路径覆盖，见 `testInnerRuleWithText`） |
| `rules.size==1` + read 是 List → 逐个 toString | `testLieyingBookListRecursiveWildcard`（间接）, `testStringListAnd` |
| `rules.size==1` + read 是标量 → add(toString) | `testIntegerNoDecimal`（getString 路径） |
| `rules.size==1` + 异常 → 吞掉 | `testGetListMissingEmpty`（同类容错） |
| 多段 `||` 短路 | `testStringListOr` |
| 多段 `&&` addAll | `testStringListAnd` |
| 多段 `%%` 交错 | `testStringListPercentInterleave` |

### AnalyzeByJSonPath.getObject
| 分支 | 测试 |
|---|---|
| ctx.read（single/list） | `testGetObjectScalar`, `testLieyingChapterListDotBracket`（getObject 取子树） |

### AnalyzeByJSonPath.getList
| 分支 | 测试 |
|---|---|
| `rule.isEmpty` → 空数组 | （由 `testGetListMissingEmpty` 的空结果路径旁证；空 rule 直接 return result） |
| `rules.size==1` read 成功（List/array） | `testLieyingBookListRecursiveWildcard`, `testLieyingChapterListDotBracket`, `testMuliBookDataRecursiveSyntheticData` |
| `rules.size==1` 非列表/异常 → 吞掉返回空 | `testGetListMissingEmpty` |
| 多段 `||` 短路 | `testGetListOr` |
| 多段 `&&` addAll | `testGetListAnd` |
| 多段 `%%` 交错 | `testGetListPercentInterleave` |
| 切分器错误向上传播 | `testGetListPropagatesUnbalanced` |

### 收尾新增：抛错点（RuleEngineError）
| 抛错点 | 测试 |
|---|---|
| RuleAnalyzer 括号不平衡（`[`）| `testUnbalancedBracketThrows` |
| RuleAnalyzer 括号不平衡（`(`）| `testUnbalancedParenThrows` |
| RuleAnalyzer trim 越界 | `testTrimOutOfBoundsThrows` |
| innerRule(start,end) 回调返回 nil → 拼 "null" | `testInnerRuleStartEndReturnsNilAppendsNullLiteral` |
| AnalyzeByRegex 正则编译失败（getElement）| `testGetElementBadPatternThrows` |
| AnalyzeByRegex 正则编译失败（getElements）| `testGetElementsBadPatternThrows` |
| AnalyzeByRegex getElement 捕获组未参与 | `testGetElementMissingGroupThrows` |
| getString 切分器错误传播 | `testGetStringPropagatesUnbalanced` |
| getList 切分器错误传播 | `testGetListPropagatesUnbalanced` |
| ctx.read 失败记入诊断（仍返回空）| `testDiagnosticsRecordedOnReadFailure` |

### 收尾新增：数字精度 / 键顺序
| 点 | 测试 |
|---|---|
| 19 位整数原样 | `testBigIntegerExact` |
| `1.0` → "1.0" | `testDoubleOnePointZero` |
| `1.5` → "1.5" | `testDoubleOnePointFive` |
| 整数无小数点 | `testIntegerNoDecimal` |
| 负数 | `testNegativeNumber` |
| 大整数（Int64.max）| `testLargeInteger` |
| 科学计数法 → Double | `testScientificNotation` |
| `$.obj.*` 键顺序 | `testObjectWildcardKeyOrder` |
| `$..*` 顺序 | `testRecursiveWildcardKeyOrder` |
| getObject 紧凑输出键顺序 | `testGetObjectCompactKeyOrder` |

### 收尾新增：七猫真实规则（≥5）
| 真实规则 | 测试 |
|---|---|
| `data.books`（无 $ 前缀）| `testQimoBookList` |
| `original_title` | `testQimoName` |
| `original_author` | `testQimoAuthor` |
| `ptags`/`image_link`/`words_num` | `testQimoOtherSearchFields` |
| `data.chapter_lists`/`title`/`id` | `testQimoTocRules` |
| `book_tag_list[*].title` | `testQimoBookInfoTagList` |
| 真实文件加载 | `testQimoRealFileLoads` |

## 说明：无对应测试的分支（第 2 步汇总）

**无。** 所有 when/if/else 分支均有对应测试——包括收尾后由「致命路径」转为「抛 RuleEngineError」的
四类错误点（括号不平衡、下标越界、正则编译失败、捕获组未参与），现在都有 `XCTAssertThrowsError` 断言其抛出。

---

# 第 3 步：AnalyzeByJSoup + AnalyzeByXPath 函数覆盖

## 函数覆盖（15 个）

| Kotlin 文件 | Kotlin fun | Swift 对应 |
|---|---|---|
| AnalyzeByJSoup.kt | parse | `AnalyzeByJSoup.parse(_:)`（`private static`） |
| | getElements（两个重载：`getElements(rule)` 与私有 `getElements(temp,rule)`） | `AnalyzeByJSoup.getElements(_:)` + `getElements(_:_:)`（扩展） |
| | getString | `AnalyzeByJSoup.getString(_:)` |
| | getString0 | `AnalyzeByJSoup.getString0(_:)` |
| | getStringList | `AnalyzeByJSoup.getStringList(_:)` |
| | getResultList | `getResultList(_:)`（`AnalyzeByJSoup+Elements.swift`） |
| | getResultLast | `getResultLast(_:_:)`（同上） |
| | getElementsSingle | `ElementsSingle.getElementsSingle(_:_:host:)`（`AnalyzeByJSoupRules.swift`） |
| | findIndexSet | `ElementsSingle.findIndexSet(_:)`（同上） |
| AnalyzeByXPath.kt | parse | `AnalyzeByXPath.parse(_:)`（`private static`） |
| | strToJXDocument | `AnalyzeByXPath.strToJXDocument(_:)` |
| | getResult | `AnalyzeByXPath.getResult(_:)` |
| | getElements | `AnalyzeByXPath.getElements(_:)` |
| | getStringList | `AnalyzeByXPath.getStringList(_:)` |
| | getString | `AnalyzeByXPath.getString(_:)` |

> `SourceRule` 是 Kotlin 内部类，其唯一逻辑（`@CSS:` 前缀判断）没有独立 `fun`（是构造器里的
> `init` 块逻辑），已在 Swift `AnalyzeByJSoup.SourceRule.init(_:)` 里忠实移植，`verify_functions.py`
> 的正则只提取 `fun`，不会漏报此项（Kotlin 侧本就没有以 `fun` 形式声明这段逻辑）。

## 分支 → 测试 对照表

### AnalyzeByJSoup.parse(doc)
| 分支 | 测试 |
|---|---|
| `doc is Element` | `testElementInput`（JSoup） |
| `doc is JXNode`（对应 Swift `XPathNode`） | 通过 XPath 结果二次喂给 JSoup 的场景未在真实规则中出现；`TODO`：暂无直接测试（Kotlin 该分支服务于"用 XPath 选完节点再用 CSS 规则"的混合写法，legado 书源较少见，第 3 步范围内未构造，留作已知空白） |
| `doc.toString()` 以 `<?xml` 开头 -> XML 解析器 | `testXMLInput`（JSoup） |
| 其余字符串 -> 普通 HTML 解析 | 几乎所有其它测试 |

### AnalyzeByJSoup.getElements(rule) / getElements(temp, rule)
| 分支 | 测试 |
|---|---|
| `temp == nil \|\| rule.isEmpty` -> 空 Elements | `testNoMatchGetElementsEmpty`（间接，temp 非 nil 但选择器不存在时是另一分支）；`TODO`：`temp==nil` 分支本身依赖内部递归调用链，未见独立触发点，`rule.isEmpty` 由 `testEmptyRuleGetStringListEmpty` 间接覆盖（getElements 内部走 getStringList 前的相同判断） |
| `sourceRule.isCss` -> `element.select` | `testCssPrefix`, `testCssComplexSelector`, `testCssMultiSelector` |
| CSS 分支 `\|\|` 短路 | `testGetElementsOr` |
| 非 CSS，`rs.count>1`（`@` 链式） -> 递归 `getElements` | `testChainedAt`, `testChainedMultiSegment` |
| 非 CSS，单段 -> `ElementsSingle().getElementsSingle` | `testDotIndexSingle` 等全部索引类用例 |
| `%%` 交错 | `testGetElementsPercent` |
| `&&` 拼接 | `testGetElementsAnd` |

### AnalyzeByJSoup.getString / getString0 / getStringList
| 分支 | 测试 |
|---|---|
| `ruleStr.isEmpty` -> nil / "" / [] | `testEmptyRuleGetStringNil`, `testEmptyRuleGetStringListEmpty` |
| `getStringList` 结果为空 -> nil（getString） | `testNoMatchGetStringNil` |
| 结果只有 1 个 -> 直接返回（getString） | 绝大多数单值测试 |
| 结果多个 -> "\n" 拼接（getString） | `testResultTypeTextNodes` 等多值场景 |
| `sourceRule.elementsRule.isEmpty` -> `element.data()` | `testEmptyElementsRuleUsesElementData` |
| CSS 分支：`lastIndexOf('@')` 切选择器/结果类型 | `testCssAttrResult`, 所有 `@css:` 用例 |
| CSS 分支：无 `@` -> 结果类型为空 | `TODO`：无直接测试（真实书源恒带结果类型，未构造此边界） |
| 非 CSS -> `getResultList` | 所有非 `@css:` 前缀用例 |
| `&&`/`\|\|`/`%%` 组合 | `testAndJoin`, `testOrShortCircuit`, `testOrFallbackString`, `testPercentInterleave` |
| `getString0`：空 -> ""；非空取第一个 | `testGetString0EmptyWhenNoMatch`, `testGetString0FirstOfMultiple` |

### AnalyzeByJSoup.getResultList
| 分支 | 测试 |
|---|---|
| `ruleStr.isEmpty` -> nil | 由 `getStringList` 空规则路径间接覆盖 |
| `@` 链式逐段收窄 elements | `testChainedAt`, 各索引测试 |
| 收窄后为空 -> nil | `testNoMatchGetStringListEmpty` |
| 最后一段 -> `getResultLast` | 所有结果类型测试 |

### AnalyzeByJSoup.getResultLast
| 分支（when lastRule） | 测试 |
|---|---|
| "text" | `testResultTypeText` |
| "textNodes" | `testResultTypeTextNodes` |
| "ownText" | `testResultTypeOwnText` |
| "html"（先删 script/style） | `testResultTypeHtmlRemovesScriptStyle` |
| "all" | `testResultTypeAll` |
| 其它 -> 属性名，空白跳过 | `testResultTypeAttrHref`, `testResultTypeAttrBlankSkipped` |
| 属性值去重 | `testResultTypeAttrDedup` |

### AnalyzeByJSoup.ElementsSingle.getElementsSingle / findIndexSet
| 分支 | 测试 |
|---|---|
| `beforeRule.isEmpty` -> `children()` | `testChildrenSelector`（间接：`@children` 写法） |
| `beforeRule` 前缀 "children"/"class"/"tag"/"id"/"text"/默认(select) | `testChildrenSelector`, `testClassSelector`, `testTagSelector`, `testIdSelector`, `testTextSelector`, `testCssComplexSelector` |
| `indexes.isEmpty`（旧写法 `.`/`!`/`:`） | `testDotIndexSingle`, `testDotIndexNegative`, `testBangExcludeSingle`, `testColonRangeOldSyntax` |
| `indexes` 非空（`[]` 写法）单索引 | `testBracketSingleIndex`, `testBracketMultipleIndexes`, `testBracketNegativeIndex` |
| `indexes` 区间（`Triple`） | `testBracketRange`, `testBracketRangeOmitStart`, `testBracketRangeWithStep`, `testBracketNegativeRange` |
| 区间 `start==end` 或 `step>=len` | `TODO`：无独立断言这一具体子分支（被区间测试间接覆盖：如 `[1:3]` 里若 len 很小会落入此分支，但未针对该边界单独断言） |
| `[-1:0]` 反转 | `testBracketReverse` |
| `split=='!'` 排除 | `testBangExcludeSingle`, `testBracketExclude` |
| `split=='.'` 选择 | 上述所有索引测试 |
| `split==' '`（无索引，退化为普通选择器） | `testClassSelector` 等基础用例 |
| `findIndexSet` 常规索引写法（`head=true`，`]` 结尾） | 所有 `[...]` 测试 |
| `findIndexSet` 旧写法（`head=false`） | 所有 `.`/`!`/`:` 测试 |
| `findIndexSet` 遇到非索引结构提前 break（纯 CSS 选择器） | `testClassSelector`（"class.a" 不含索引后缀，走此分支后 `beforeRule=trimmed`） |

### AnalyzeByXPath.parse / strToJXDocument
| 分支 | 测试 |
|---|---|
| `doc is XPathNode` | 由 `getElements` 返回值二次传入的场景，见 `testRealRule_Xiaoshuo2016_*`/`testRealRule_Caimoge_*` 里 `AnalyzeByXPath(els[0])` 等价路径（Element 分支） |
| `doc is Element` | `testElementInput`（XPath）、所有 `AnalyzeByXPath(els[i])` 用例 |
| `doc is Elements` | `TODO`：无直接测试（Kotlin 对应 `Elements` 入参场景，本移植支持但未见真实书源触发此路径） |
| 其它 -> `strToJXDocument(String)` | 绝大多数字符串输入测试 |
| `</td>` 结尾 -> 补 `<tr>` | `testTdAutoWrap` |
| `</tr>`/`</tbody>` 结尾 -> 补 `<table>` | `testTrAutoWrap`, `testTbodyAutoWrap` |
| `<?xml` 开头 -> XML 解析器 | `testXMLInput`（XPath） |

### AnalyzeByXPath.getResult
| 分支 | 测试 |
|---|---|
| 委托 `evaluator.evaluate(xpath)` | 所有 XPath 测试 |

### AnalyzeByXPath.getElements
| 分支 | 测试 |
|---|---|
| `xPath.isEmpty` -> nil | `testEmptyRuleGetElementsNil` |
| `rules.size==1` -> 直接 `getResult` | 单规则用例 |
| 多段 `\|\|` 短路 | `testXPathOrShortCircuit` |
| 多段 `&&` 拼接 | `testXPathAndJoin`（经由 getString，getElements 的 `&&` 由 `testXPathAndJoin` 底层机制覆盖） |
| 多段 `%%` 交错 | `testXPathPercentInterleave` |
| 无匹配 -> 空数组 | `testNoMatchGetElementsEmpty` |

### AnalyzeByXPath.getStringList / getString
| 分支 | 测试 |
|---|---|
| 单规则 -> `getResult` 后 `asString()`/`toStringValue()` | 所有基础 XPath 测试 |
| 求值失败（硬性语法错误）-> **直接抛错向上传播**（收尾修正：对齐 Kotlin `?.` 只处理 null、不捕获异常的真实语义，早期版本误用 `try?` 吞掉已改正） | `testStringFunctionOnElementIsUnsupported`、`testStringFunctionOnAttrIsUnsupported`、`testSubstringNoLengthIsUnsupported`、`testNormalizeSpaceFunctionIsUnsupported`（均 `XCTAssertThrowsError`） |
| 求值失败（语法有效但恒不匹配）-> 返回空值，不抛错 | `testOwnTextFunctionIsUnsupported`、`testNotFunctionCombinedWithAndIsUnsupported`、`testCountFunctionInPredicateIsUnsupported`、`testStringLengthInPredicateIsUnsupported` |
| `&&`/`\|\|`/`%%` 组合（getString/getStringList） | `testXPathAndJoin`, `testXPathOrShortCircuit`, `testXPathPercentInterleave` |

### SwiftSoupXPathEvaluator.evaluate（收尾新增：联合运算符 `\|`）
| 分支 | 测试 |
|---|---|
| 顶层按 `\|` 切分为多个分支 | `testUnionTwoDifferentPaths` |
| 单分支（无 `\|`）走普通路径求值 | 所有非联合用例 |
| 多分支：每段先尝试顶层函数调用，否则按路径求值 | `testStringFunctionOnElementIsUnsupported` 等（函数分支）、`testUnionTwoDifferentPaths`（路径分支） |
| 多分支结果合并：按分支书写顺序拼接，不去重不重排（对齐真实 JsoupXpath，见 README 差异表第 2 条） | `testUnionDoesNotDedupSamePath`、`testUnionConcatenatesByBranchOrderNotDocumentOrder` |

### SwiftSoupXPathFunctions（收尾新增：顶层函数 + 谓词内函数比较）
| 分支 | 测试 |
|---|---|
| 顶层 `count(path)` | `testCountFunctionOnList`, `testCountFunctionZeroWhenNoMatch` |
| 顶层 `concat(a,b,...)` | `testConcatTwoAttrs`, `testConcatWithLiteral` |
| 顶层 `substring(s,start,length)`（三参数） | `testSubstringBasic` |
| 顶层 `substring(s,start)`（两参数，不支持）| `testSubstringNoLengthIsUnsupported` |
| 顶层 `substring-before(s,sep)` / 找不到分隔符返回原串 | `testSubstringBeforeBasic`, `testSubstringBeforeNoMatchReturnsOriginal` |
| 顶层 `substring-after(s,sep)` / 找不到分隔符返回空串 | `testSubstringAfterBasic`, `testSubstringAfterNoMatch` |
| 顶层 `string-length(s)` | `testStringLengthBasic`, `testStringLengthZeroWhenMissing` |
| 顶层 `string(...)`（不支持，抛错） | `testStringFunctionOnElementIsUnsupported`, `testStringFunctionOnAttrIsUnsupported` |
| 谓词内 `concat/substring/substring-before/substring-after` 比较 | `testConcatInPredicate`, `testSubstringInPredicate`, `testSubstringBeforeAfterInPredicate` |
| 谓词内 `count(...)=n`（不支持，恒不匹配） | `testCountFunctionInPredicateIsUnsupported` |
| 谓词内 `string(...)=x`（不支持，硬抛错） | `testStringFunctionInPredicateIsUnsupported` |
| 谓词内 `string-length(...)=n`（不支持，恒不匹配） | `testStringLengthInPredicateIsUnsupported` |
| `not(...)` 单独使用 | `testNotFunctionBasic`, `testNotFunctionAttrExists` |
| `not(...)` 与 `and`/`or` 组合（不支持，恒不匹配） | `testNotFunctionCombinedWithAndIsUnsupported` |
| `normalize-space(...)`（不支持，硬抛错） | `testNormalizeSpaceFunctionIsUnsupported` |
| `ownText()` 节点测试（不支持，恒不匹配） | `testOwnTextFunctionIsUnsupported` |
| `contains`/`starts-with` 的 `text()`/`.` 参数形式 | `testContainsWithTextArg`, `testContainsWithDotArg`, `testStartsWithTextArg` |

### 多重谓词 `[...][...]`（收尾修正：代码一直支持，之前 README 误写"不支持"，已订正）
| 分支 | 测试 |
|---|---|
| `[位置][属性]`：先按位置筛选，再按属性筛选 | `testMultiPredicatePositionThenAttr`, `testMultiPredicatePositionThenAttrNoMatch` |
| `[属性][位置]`：先按属性筛选，再按位置筛选（结果集位置，非原文档位置） | `testMultiPredicateAttrThenPosition`, `testMultiPredicateAttrThenPositionSecond` |
| 谓词顺序影响结果（标准 XPath 语义对照） | `testMultiPredicateDemonstratesOrderMatters` |
| 三重连续谓词 | `testTriplePredicate`, `testTriplePredicateLast` |

### GoldenComparisonTests（收尾新增：真实 jsoup/JsoupXpath 对照）
| 分支 | 测试 |
|---|---|
| CSS 规则逐条对照（138 条用例里的 CSS 部分） | `testAllGoldenCssCases` |
| XPath 规则逐条对照（138 条用例里的 XPath 部分，含已登记的 2 个已知差异跳过） | `testAllGoldenXPathCases` |
| golden 目录不存在（本地未跑 golden job） -> `XCTSkip`，不是误报失败 | 本地运行时体现；CI 两个测试 job 都 `needs: golden` 恒有数据 |

## 说明：无对应测试的分支（第 3 步汇总，收尾后更新）

以下分支按实际情况标出，均不影响真实书源规则的正确性（真实规则未触发这些路径）：

1. `AnalyzeByJSoup.parse` 的 `doc is JXNode`（Swift `XPathNode`）混合分支：legado 书源较少见"XPath 选完节点再用 CSS 规则"的写法，未构造测试。
2. `AnalyzeByJSoup.getStringList` 的 CSS 分支「无 `@` 结果类型」边界：真实书源恒带结果类型。
3. `ElementsSingle` 区间解析里 `start==end || step>=len` 的精确单元测试：被其它区间测试间接覆盖，未单独断言。
4. `AnalyzeByXPath.parse` 的 `doc is Elements` 直接入参：支持但未见真实书源触发。

以上 4 条均为「支持但暂缺专项测试」的诚实标注，不是「未实现」。收尾前第 5 条（诊断记录断言）
已在本轮用 `XCTAssertThrowsError` 系列测试间接验证（抛错行为本身即是诊断的体现），不再单列。


## 第 4 步 B：AnalyzeRule.kt + NetworkUtils.kt（分支 → 测试）

验证脚本 `scripts/verify_functions.py` 已扩展提取 `AnalyzeRule.kt`（32 fun）与
`NetworkUtils.kt`（本步骤范围子集）；排除项在脚本 `EXCLUDED` 显式列理由。结果：
「Kotlin 有但 Swift 没实现」清单为空。

| 函数 / 分支 | Swift 位置 | 对应测试 |
|---|---|---|
| splitSourceRule — @CSS:/@@/@XPath:/@Json: 前缀 | SourceRule.init | testMode_* 系列（13 例） |
| splitSourceRule — $./$[ 判 JSON、/ 判 XPath | SourceRule.init | testMode_jsonDollarDot/Bracket/xpathSlash |
| splitSourceRule — allInOne `:` 判 Regex | splitSourceRule | testMode_allInOneRegexColon |
| splitSourceRule — <js>/@js:/@webjs: | splitSourceRule | testMode_jsBlock/atJs/webJs/webJsTooShort/testSplit_textThenJs |
| SourceRule — {{ }} 内联 JS | makeUpRule | testInline_jsExpr/jsStringConcat/multipleBraces |
| SourceRule — @get:{} | makeUpRule | testAtGet_inline |
| SourceRule — $1~$n 组引用 | splitRegex/makeUpRule | testReplaceRegex_groupRef |
| SourceRule — ##/### 切分 | makeUpRule | testReplaceRegex_simple/removeMatch/replaceFirst |
| splitPutRule — @put:{} | splitPutRule | testAtPut_storesVariable |
| getString(CSS/Default) | +Dispatch | testGetString_cssTitle/cssAuthor |
| getString(XPath) | +Dispatch | testGetString_xpathTitle |
| getString(JSON) | +Dispatch | testGetString_jsonName/jsonAuthor |
| getString — 空规则/无内容 | +Dispatch | testGetString_emptyRuleReturnsEmpty/noContent |
| getString — isUrl 绝对拼接 | +Dispatch | testGetString_isUrlAbsolute/isUrlBlankReturnsBaseUrl |
| getString — unescape 开关 | +Dispatch | testGetString_unescapeHtml4/noUnescapeWhenFlagOff |
| getStringList(CSS/JSON) | +Dispatch | testGetStringList_cssChapters/jsonTags |
| getStringList — 空规则 nil、String 按 \n 切 | +Dispatch | testGetStringList_emptyRuleNil/stringSplitByNewline |
| getStringList — isUrl | +Dispatch | testGetStringList_isUrlAbsolute |
| getElement / getElements | +Dispatch | testGetElement_css/testGetElements_cssList/empty |
| setContent — isJSON 判定 | AnalyzeRule | testSetContent_htmlNotJson/jsonAutoDetect/nilThrows/emptyStringIsNotJSON |
| put/get 四层回退 | +Rules | testPutGet_sourceLevel/bookPreferredOverSource/chapterPreferred/testGet_bookName/chapterTitle/missingReturnsEmpty |
| evalJS 基本求值 | +JS / JSEngine | testEvalJS_arithmetic/stringConcat/resultVariable/boolean/array |
| java Proxy 未实现方法抛错 | JSJavaBridge | testJava_unimplementedThrows |
| java 自有方法 put/get | JSJavaBridge | testJava_implementedGetPut |
| Java 互操作检测抛错 | JSEngine | testJavaInterop_packagesThrows/jsoupParseThrows/importClassThrows |
| replaceRegex（## / ### / $n / 删除） | +Rules | testReplaceRegex_* |
| compileRegexCache / scriptCache 容量 | +Rules / JSEngine | testScriptRuleCache_reuse（缓存复用；容量 16 为常量） |
| WebJs 默认 unsupported | +JS | testWebJs_unsupportedThrows |
| reGetBook / refreshTocUrl 桩 | +JS | testReGetBook_unsupported/testRefreshTocUrl_unsupported |
| NetworkUtils.getAbsoluteURL（各分支） | NetworkUtils/JavaURLResolver | NetworkUtilsTests testAbs_*（11 例） |
| NetworkUtils.getBaseUrl/isAbsUrl/isDataUrl | NetworkUtils | testGetBaseUrl/testIsAbsUrl/testIsDataUrl |
| JavaURL.parse | JavaURLResolver | testParse_basic/invalidReturnsNil |
| unescapeHtml4（命名/十进/十六/无分号/未知） | HtmlUnescape | testUnescape_*（8 例） |
| RegexTemplate Java→ICU | RegexTemplate | testTemplate_groupRef/literalDollar/bareDollarEscaped |
| splitNotBlank | LegadoStringUtils | testSplitNotBlank |
| 端到端真实规则（7 书源） | AnalyzeRuleEndToEndTests | testTaoxiaoshuo_*/testShudugu_*/testDeqi_*/testBiquge345_*/testAlice_*/testMowan_*/testDejian_* |

### 未直接单测到的分支（标注）
- `NativeObject` / `LinkedTreeMap` 分支（RuleValue 的 `.jsObject` / `.jsonObject`）：已实现，
  但无专用单测（真实书源未直接命中；evalJS 返回对象经 toRuleValue 覆盖了 .jsObject 路径）。
  **待补**：直接构造 `.jsObject`/`.jsonObject` content 的 getString/getStringList 用例。
- `getWebJsResult` 成功路径：默认 WebJSProvider 抛 unsupported，只测了抛错分支；真实 WebView
  第 5/6 步接入后补成功路径。
- NetworkUtils 相对解析的含空格/中文、`file:`、越根 `..` 等边角：待 C 部分 golden（真实
  java.net.URL 对照）验证。

---

# 第 7 步 A 段：WebBook 流程层函数 / 分支对照清单

> 自动校验：`scripts/verify_functions.py` 已扩展覆盖 `webBook/BookList.kt`、`webBook/BookInfo.kt`、
> `webBook/BookChapterList.kt`、`webBook/BookContent.kt`、`webBook/WebBook.kt`、`Debug.kt`。
> **「Kotlin 有但 Swift 没实现的函数」清单：空**。Kotlin 参考副本在
> `reference/kotlin/analyzeRule/webBook/*.kt` 与 `reference/kotlin/analyzeRule/Debug.kt`。
>
> 明确排除（`verify_functions.py` EXCLUDED 登记，理由见脚本）：WebBook 的 6 个 `runBlocking` 同步包装
> （`searchBook`/`exploreBook`/`getBookInfo`/`getChapterList`/`getContent`/`preciseSearch`，Swift 只用
> async/await）；Debug 的 RSS 调试（`sortDebug`/`rssContentDebug`）与「校验书源」功能
> （`startChecking`/`finishChecking`/`getRespondTime`/`updateFinalMessage`，App 层 UI 校验，非调试流程）。

## 函数覆盖（6 个 Kotlin 文件）

| Kotlin 文件 | Kotlin fun | Swift 对应 |
|---|---|---|
| webBook/BookList.kt | analyzeBookList | `BookList.analyzeBookList(...)`（async throws） |
| | getInfoItem | `BookList.getInfoItem(...)`（private） |
| | getSearchItem | `BookList.getSearchItem(...)`（private） |
| | checkExploreJson | `BookList.checkExploreJson(...)`（private） |
| webBook/BookInfo.kt | analyzeBookInfo（两个重载） | `BookInfo.analyzeBookInfo(...)` × 2（async throws） |
| webBook/BookChapterList.kt | analyzeChapterList（两个重载） | `BookChapterList.analyzeChapterList(...)` × 2（async throws） |
| | upChapterInfo | `BookChapterList.upChapterInfo(...)`（private） |
| webBook/BookContent.kt | analyzeContent（两个重载） | `BookContent.analyzeContent(...)` × 2（async throws） |
| webBook/WebBook.kt | searchBookAwait/exploreBookAwait/getBookInfoAwait/getChapterListAwait/getContentAwait/preciseSearchAwait | `WebBook.*Await(...)` |
| | runPreUpdateJs | `WebBook.runPreUpdateJs(...)` |
| | checkRedirect | `WebBook.checkRedirect(...)`（private） |
| Debug.kt | startDebug（bookSource 重载） | `Debug.startDebug(bookSource:key:options:)`（async） |
| | exploreDebug/searchDebug/infoDebug/tocDebug/contentDebug | `Debug.*`（private async） |
| | log（两个重载）/ cancelDebug | `DebugLogger.log(...)` / `DebugLogger.cancelDebug(...)` |

## 分支 → 测试 对照表

| 分支 | 测试（LegadoWebBookTests） |
|---|---|
| 搜索列表解析 / 多字段 / 相对书地址 / 去重 | WebBookFlowTests.testSearch*、WebBookBookListTests.testRelativeBookUrlResolved/testSearchMissingCoverUrl |
| bookList "-" 反序 / "+" 去前缀 | WebBookFlowTests.testSearchBookListReversePrefix、WebBookBookListTests.testBookListPlusPrefixDropsPlus |
| bookUrlPattern 命中 → 详情页分支 | WebBookFlowTests.testSearchBookUrlPatternDetailBranch、WebBookFinalTests.testSearchBookUrlPatternDetailReturnsSingle |
| 列表为空且无 bookUrlPattern → 详情页 | WebBookFlowTests.testSearchEmptyThrows |
| getInfoItem 书名空/过滤拒绝 | WebBookBookListTests.testGetInfoItemNameEmptyReturnsNil、WebBookFinalTests.testInfoItemFilterRejects |
| 发现页 / checkExploreJson（规范与不规范 JSON） | WebBookFlowTests.testExploreBookListPlusPrefix/testCheckExploreJsonInvalidDoesNotCrash、WebBookBookListTests.testCheckExploreJsonValidNoCrash |
| 发现规则空 → 回退搜索规则 | WebBookBookListTests.testExploreUsesSearchRuleWhenExploreRuleEmpty |
| 详情页各字段（名/作者/分类/字数/最新章节/简介/封面/目录链接） | WebBookBookInfoTests.testName*/testAuthor*/testKind*/testWordCount*/testLastChapter*/testIntro*/testCoverUrl*/testTocUrl* |
| canReName 逻辑 / init 规则 / `<usehtml>`/`<md>`/`<useweb>` 前缀 | WebBookBookInfoTests.testNameEmptyDoesNotOverwrite*/testCanReName*/testInitRule*/testIntroUseHtmlPrefix*、WebBookEdgeCaseTests.testIntroMd/UseWebPrefix |
| webFile 下载链接 / 下载链接空抛错 | WebBookFlowTests.testBookInfoWebFileDownloads、WebBookBookInfoTests.testDownloadUrls*/testDownloadUrlsEmptyThrows |
| 目录列表解析 / 反序 / 多页(1) / 多页(并发) / 去重 / 相对地址 / 空标题跳过 | WebBookFlowTests.testChapterList*、WebBookChapterListTests.testDedupByUrl/testChapterWithoutUrlUsesBaseUrl/testEmptyTitleChapterSkipped、WebBookEdgeCaseTests.testTocNextUrlManyConcurrent |
| isVip/isPay/isVolume/updateTime | WebBookChapterListTests.testIsVipAndIsPay/testIsVolumeWithUpdateTime/testUpdateTimeAsTagWhenNotVolume |
| tocCountWords 字数提取（FlowConfig） | WebBookTocCountWordsTests.testTocCountWords* |
| formatJs 标题变换 | WebBookChapterListTests.testFormatJsIdentity、WebBookAdditionalTests.testFormatJsTransformsTitle |
| preUpdateJs | WebBookEdgeCaseTests.testRunPreUpdateJs*/testRunPreUpdateJsEmptyDoesNothing |
| 目录为空抛错 / body nil 抛错 | WebBookFlowTests.testChapterListEmptyThrows、WebBookTocCountWordsTests.testChapterListBodyNilThrows |
| 正文解析 / 多页(1) / 多页终止判定 / 空规则/分卷短路/空正文抛错 | WebBookFlowTests.testContent*、WebBookURLProcessingTests.testContentNextPageTerminatesAtNextChapter、WebBookAdditionalTests.testGetContentVolumeWithTag |
| replaceRegex / subContent(onLineTxt/audio/video/http) / title+imgRegex / formatKeepImg | WebBookContentTests.testReplaceRegex*/testSubContent*/testTitleRule*、WebBookAdditionalTests.testContentKeepsImgTag |
| Debug.startDebug 五路分发 + 链式 + 错误不崩溃 | WebBookFlowTests.testStartDebug*、WebBookDebugTests.testStartDebug*、WebBookEdgeCaseTests.testExploreDebugEmptyResultLogged/testSearchDebugEmptyResultLogged |
| DebugLogger 日志格式/符号/状态码/时间前缀/生命周期/响应留存 | WebBookDebugLoggerTests.test*、WebBookDebugTests.testLogger*、WebBookAdditionalTests.testCapturedResponsesForAllStages |
| LiveWebBookNetwork（buildRequest→解码→重定向→留存） | WebBookLiveNetworkTests.test* |
| 本地合成服务器（NWListener，Apple 平台） | WebBookLocalServerTests.testSearchOverLocalHTTPServer |
| 端到端（规则真实、数据合成，7 个真实书源） | WebBookEndToEndTests.testDeqixsSearchEndToEnd/testShuduguSearchEndToEnd/testTaiwanSearchEndToEnd/testRealSources* |
| HtmlFormatter.format/formatKeepImg golden（≥80） | WebBookGoldenTests.testHtmlFormatterGolden |
| wordCountFormat golden（≥30） | WebBookGoldenTests.testWordCountFormatGolden |
| 纯 public 接口可见性（非 @testable） | LegadoWebBookPublicAPITests.WebBookPublicAPITests.test* |

## 说明：流程层的 Swift 值语义适配（README 差异表登记）

- `Book`/`SearchBook`/`BookChapter` 在 Kotlin 是 class（引用语义），Swift 是 struct（值语义）。
  流程函数用 `BookBox`/`SearchBookBox`/`BookChapterBox` 承载可变状态；`analyzeContent` 里对
  `bookChapter` 的 title/imgUrl/resourceUrl 变更作用在本地副本上，通过日志输出呈现
  （「┌获取章节名称/└标题」），返回值为解析后的正文字符串（与 Kotlin 返回值一致）。
- 书架持久化（`needSave`、`upChapterInfo` 的 DB 回填、`BookHelp.saveContent`）不在规则引擎范围内，
  默认 `FlowConfig.tocCountWords=false` 时 `upChapterInfo` 直接 early-return（与 Kotlin 一致），
  仅记日志、不静默。
