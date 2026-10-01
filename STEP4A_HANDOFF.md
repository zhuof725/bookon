# Step 4-A 交接文档（HTML 序列化器彻底重写）

## 目标
用从零遍历 DOM 的 `JsoupCompatSerializer` 替代原先的字符串级后处理
（`SwiftSoupVoidElementFix` / `SwiftSoupBrIndentFix`），按真实 jsoup 1.16.2 算法
重新生成 `outerHtml()`/`html()` 字符串，删除 `GoldenComparisonTests` 的全部
`knownDivergences`，让 golden 逐字节严格比较并全部通过。

## 已完成
- 新增 `Sources/LegadoBookSource/RuleEngine/JsoupCompatSerializer.swift`：
  从零遍历 SwiftSoup DOM（Node/Element/TextNode/Comment/DataNode/DocumentType），
  按 jsoup 1.16.2 的 Element.outerHtmlHead/Tail、shouldIndent、Node.indent、
  TextNode.outerHtmlHead（含 `<br>` 后文本换行特判）、Entities.escape（base 模式）、
  Tag 分类清单、StringUtil.padding/appendNormalisedWhitespace 复刻。
  OutputSettings 固定 jsoup 默认（prettyPrint=true, indentAmount=1, charset=UTF-8,
  escapeMode=base, syntax=html）。
- 切换所有调用点到新序列化器（CSS `@html`/`@all`、XPath `outerHtml()`/`html()`/
  元素节点 `asString`），commit `73eedee`。
- 清空 `GoldenComparisonTests.swift` 的 knownDivergences，golden 改为严格逐字节比较，
  commit `b7c79d0`。
- 新增 66 个合成 HTML golden 用例（golden 用例总数 264），commit `ec3d822`。
- 更新 README / FUNCTION_MAPPING，commit `88f50ea`。
- **布尔/无值属性折叠修复**，commit `f24dc78`（见下「修复记录」）。

## 修复记录：无值属性折叠（jsoup `val==null` 分支）
首轮 CI（run 36811878008）golden 严格比较暴露 8 处不一致，全部同一根因：
`<video class='vd1' controls>` 的 `controls` 属性。
- jsoup 输出 `controls`（折叠），Swift 误输出 `controls=""`。
- 根因：jsoup `Attribute.shouldCollapseAttribute`（Attribute.java:206-211）的真实条件是
  `val==null || (val空或==key) && isBooleanAttribute(key)`——注意 `val==null` 是独立的
  第一分支，**无值属性无论名字是否在布尔清单里都折叠**。`controls` 不在 jsoup 的 30 个
  布尔属性清单里，但因为它无值（val==null）而被折叠。
- SwiftSoup 把「无值属性」表示为 `BooleanAttribute` 子类实例
  （`Token.newAttribute`：无值且非显式空字符串 → `BooleanAttribute`；
   `controls=""` 显式空值 → 普通 `Attribute(value:[])`）。两者 `getValue()` 都返回 `""`，
  必须用 `is BooleanAttribute` 区分，对应 jsoup 的 `val==null`。
- 修复：序列化器 `attributesHTML` 用 `attribute is BooleanAttribute` 判无值属性，
  无条件折叠。已逐一核对 SwiftSoup 2.9.6 `Token.swift`/`Attribute.swift`/
  `BooleanAttribute.swift` 与 jsoup 1.16.2 `Attribute.java` 源码确认语义一致。
- 布尔属性清单（30 个，jsoup 1.16.2 `Attribute.java` 权威数组）已核对逐字一致。

## 验证结果：三个 job 全绿 ✅（CI run 36813221057）
- **golden**（ubuntu）：✓ 16s。6 个用例文件，共 **448 条用例**
  （第 3 步为 184 条；新增 `serializer_synthetic.json` 等序列化器合成用例）。
- **test-macos**：✓ 37s。`Executed 299 tests, with 0 failures (0 unexpected)`。
- **test-ios-simulator**：✓ 1m43s。`** TEST SUCCEEDED **`，实际执行 299 测试。
- 布尔/无值属性修复（`f24dc78`）使首轮 8 处 golden 不一致全部清零。
- `knownDivergences` 已为空数组，golden 逐字节严格比较全部通过，无任何跳过。
- 日志归档：`ci_logs/step4a_all_green_36813221057.log`（全绿）、
  `ci_logs/step4a_test-macos_36811878008.log`（首轮失败，留作修复前后对照）。
- 测试数 300→299：删除旧字符串后处理相关测试、重组序列化测试所致，属正常。

## 复核确认（已核对）
- `SwiftSoupVoidElementFix.swift` 已删除（仅注释里保留历史说明文字），无代码遗留调用。
- `SwiftSoupTextNormalizeFix.swift` 保留，服务于纯文本提取路径（text()/ownText()/
  allText()），非 HTML 序列化路径，职责边界已在文件头注释说明。
- `VoidElementFixTests.swift` 保留，内容已改为验证新序列化器的 void 行为（5 测试全过）。
- 本地无 Swift 工具链，全部验证经 CI 完成。

## 下一步（Step 4-B / 4-C）
A 部分验证全绿后，才按任务书推进 B（AnalyzeRule 总调度 + JS 引擎）、C（golden 验证
getAbsoluteURL / replaceRegex / unescapeHtml4 / JSONPath / AnalyzeByRegex）。
