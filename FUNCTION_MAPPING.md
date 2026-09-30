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
| 求值失败（`try?` 为 nil）-> 记诊断，返回空 | `TODO`：无独立断言诊断记录内容（第 2 步的 `AnalyzeByJSonPath` 已有等价诊断测试模式，可复用但本步骤未重复编写） |
| `&&`/`\|\|`/`%%` 组合（getString/getStringList） | `testXPathAndJoin`, `testXPathOrShortCircuit`, `testXPathPercentInterleave` |

## 说明：无对应测试的分支（第 3 步汇总）

以下分支按实际情况标出，均不影响真实书源规则的正确性（真实规则未触发这些路径）：

1. `AnalyzeByJSoup.parse` 的 `doc is JXNode`（Swift `XPathNode`）混合分支：legado 书源较少见"XPath 选完节点再用 CSS 规则"的写法，未构造测试。
2. `AnalyzeByJSoup.getStringList` 的 CSS 分支「无 `@` 结果类型」边界：真实书源恒带结果类型。
3. `ElementsSingle` 区间解析里 `start==end || step>=len` 的精确单元测试：被其它区间测试间接覆盖，未单独断言。
4. `AnalyzeByXPath.parse` 的 `doc is Elements` 直接入参：支持但未见真实书源触发。
5. `AnalyzeByXPath.getStringList/getString` 求值失败记诊断的具体内容断言：机制与第 2 步一致，未重复编写专测。

以上 5 条均为「支持但暂缺专项测试」的诚实标注，不是「未实现」。
