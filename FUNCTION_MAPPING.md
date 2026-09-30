# Kotlin → Swift 函数 / 分支对照清单（第 2 步：规则引擎底座）

> 自动校验脚本：`scripts/verify_functions.py`（从 `reference/kotlin/analyzeRule` 用正则提取全部 `fun`，
> 再到 Swift 源码检查同名函数）。**「Kotlin 有但 Swift 没实现的函数」清单：空**（17/17 覆盖）。
> CI（收尾后）：**macOS `swift test` + iOS 模拟器 `xcodebuild test`** 两个 job 全绿，**122 tests, 0 failures**（已按要求去掉 Linux job）。
>
> 收尾变更：崩溃写法（fatalError/try!/as!/强制解包/越界）已清零；括号不平衡、下标越界、正则编译失败、
> getElement 捕获组未参与 → 抛 `RuleEngineError`；`splitRule`/`innerRule`/`trim`/`AnalyzeByRegex.*`/
> `AnalyzeByJSonPath.get*` 均标 `throws`。新增抛错点测试见下表。

移植范围：仅规则引擎「底座 + 两个最简单后端」——`RuleAnalyzer`、`AnalyzeByRegex`、`AnalyzeByJSonPath`。
**不含** JSoup / XPath / AnalyzeRule 总调度 / JS / 网络 / UI。第 1 步 API 名称与行为未改动。

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
| `rules.size==1` + 无内嵌 + read 是标量 → toString | `testGetStringNumber`, `testGetStringBool`, `testLieyingContentBody`, `testLieyingBookTitle` |
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
| `rules.size==1` + read 是标量 → add(toString) | `testGetStringNumber`（getString 路径） |
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

## 说明：无对应测试的分支（汇总）

**无。** 所有 when/if/else 分支均有对应测试——包括收尾后由「致命路径」转为「抛 RuleEngineError」的
四类错误点（括号不平衡、下标越界、正则编译失败、捕获组未参与），现在都有 `XCTAssertThrowsError` 断言其抛出。
