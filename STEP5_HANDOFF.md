# Step 5 交付文档（JsExtensions 方法体 + org.jsoup.Jsoup 替身）

> 只写最终状态。CI 结果以最后一次 push 的真实 run 为准（见文末「最终验证」）。

## 范围与目标

在第 1–4 步成果（API 名称与行为不变）之上：
1. 实现第一批纯算法 JsExtensions 方法（md5/t2s/s2t/timeFormat/base64/hex/htmlFormat/encodeURI/
   randomUUID/toNumChapter/strToBytes/bytesToStr 等）。
2. UI/系统与网络/文件类方法以协议注入（`JsUIProvider` / `JsNetworkExtensionsProvider`）+
   默认 unsupported + 记 diagnostics。
3. 用 SwiftSoup 实现 `org.jsoup.Jsoup` 替身，放行 `org.jsoup.Jsoup.parse` 与
   `Packages.org.jsoup.Jsoup.parse` 两种写法（爱丽丝书屋、台湾小说网真实规则可用）；
   其余 Rhino 互操作仍抛出。
4. 其余 JsExtensions 方法保持 JS Proxy 拦截抛错 + 记 diagnostics。

## 交付内容

### 源码（Sources/LegadoBookSource/RuleEngine/）
- `JsExtensionsCore.swift`：第一批纯算法实现 + `ChineseTransfer`（quick-chinese-transfer 0.2.17
  词典最长匹配 + legado fixT2sDict 排除词）。
- `JsExtensionsRuntime.swift`：`__call` 通用分发器（自有方法 / 纯算法 / UI / 网络 / WebJs），
  统一 ok/error 返回、diagnostics 记录；含同名的可直接调用方法（供 verify_functions 匹配）。
- `JSJavaBridge.swift`：`java` 对象 Proxy 桥接（对 `JsExtensionsCatalog.implemented` 生成包装函数；
  未实现方法仍抛「尚未实现」+ 记诊断）。
- `JsoupJSBridge.swift`：org.jsoup.Jsoup 替身（parse/select/text/html/attr/outerHtml/first/get/
  size/eq/remove，基于 SwiftSoup）。
- `JSEngine.swift`：互操作预检测放宽——`Packages.org.jsoup` 归一后仅剩 org.jsoup 放行；
  其余标记（importClass/importPackage/JavaImporter/java.lang|util|io|net|math、非 jsoup Packages.）
  仍抛 `RuleEngineError.jsError`。
- `AnalyzeRuleDependencies.swift`：新增 `JsUIProvider` / `JsNetworkExtensionsProvider` 协议 +
  Unsupported 默认实现。
- `AnalyzeRule.swift`：init 注入上述协议。
- `JsExtensionsCatalog.swift`：全量方法清单升级为 JsExtensions.kt(67) + JsEncodeUtils.kt(27) = 94；
  新增 `step5Implemented` / `providerImplemented` / `implemented` / `unimplemented`。
- `Resources/Chinese/{t2s,s2t}.txt` + `t2s_exclude.txt` + `PROVENANCE.md`
  （quick-chinese-transfer 0.2.17 原样资源，Package.swift `.process("Resources")`）。

### 测试
- `Tests/LegadoHTMLEngineTests/JsExtGoldenComparisonTests.swift`：96 条 golden 三态对照
  （抛错/ null / 值），失败信息含 name/输入/Java/Swift；CI 缺失 golden 必 fail。
- `Tests/LegadoAnalyzeRuleTests/AnalyzeRuleJSTests.swift`：更新旧断言（md5Encode 已实现、
  aesDecodeToString 未实现抛错、org.jsoup 放行）。
- `Tests/LegadoAnalyzeRuleTests/AnalyzeRuleEndToEndTests.swift`：爱丽丝/台湾 jsoup 链真实执行断言、
  魔丸 hexDecode 真实解码断言、淘小说吧 md5 签名链。
- `Tests/LegadoAnalyzeRuleTests/Resources/taiwan_real_source.json`（第 4 步已有，本步骤复用）。

### golden（scripts/golden）
- pom：hutool-core/hutool-crypto 5.8.22、quick-transfer-core 0.2.17（JitPack 仓库）。
- `JsExtGen.java`：逐方法对照真实库；`cases/js_ext_cases.json`（约 96 条，含数字入参与非法输入）。
- `Main.java`：挂载 `jsExtCases` -> `jsExtResults`。

### 脚本 / 文档
- `scripts/verify_functions.py`：新增 JsExtensions.kt + JsEncodeUtils.kt 映射与 EXCLUDED；
  「Kotlin 有但 Swift 没处理」清单为空。
- `JS_EXTENSIONS_USAGE.md`：实现状态更新（✅ 已实现 / ⚠️ 协议注入 / ❌ 未实现 0 次）。
- `README.md`：新增「第 5 步」章节（方法表、替身、golden、数字入参差异、样本标注）。

## 关键语义对齐（经真实库 golden 验证）

| 方法 | 关键点 |
|---|---|
| `hexDecodeToString` | 空串原样返回 `""`；奇数长度前补 `0`；非法字符抛错（`UtilException` 对应 Swift throw） |
| `base64Decode` | hutool Base64Decoder 容错解码（跳过非法字符、`=` padding、4 字符一组），逐行移植并逐字节对照 |
| `md5Encode16` | md5 全串 substring(8,24)（注意：`abc` -> `3cd24fb0d6963f7d`） |
| `toNumChapter` | `(第)(.+?)(章)` 最短匹配；fullToHalf + parseInt/中文数字；`第一千零一夜.txt` 不匹配原样返回 |
| `htmlFormat` | Kotlin 正则 `\s` 只含 ASCII 空白（ICU `\s` 含全角空格，已显式替换）；img 归一化 |
| `encodeURI` | 空格 `+`、保留 `. - * _`、其余百分号编码（UTF-8，大写 hex） |
| 数字入参 | JS number → Java String 参数按 JS ToString（整数无 `.0`），harness 与 runtime 同规则 |

## 已知差异（登记 README）

- `bytesToStr` 非 UTF-8 字符集对非法字节的行为：Swift `String(data:encoding:)` 返回 nil 时抛错，
  Java `new String(bytes, charset)` 会替换字符——本步骤 golden 只覆盖 UTF-8（书源实际用到的），
  非 UTF-8 非法字节路径未对照，登记为已知边界。
- JS `NaN`/`Infinity` 数字经 `stringify` 输出 Swift 字面量（`nan`/`inf`）与 JS ToString 不同；
  书源未用到把这两个值传给 String 参数的场景，登记为已知边界。

## 最终验证（真实 CI）

- 本步骤最后 push 的 run 与三 job 结果见文末追加（以 gh 实测为准）。

## 后续 TODO（第 6 步）

- 真实网络：AjaxProvider 接入 AnalyzeUrl（get/post/head/ajaxAll/connect/cacheFile/downloadFile）。
- 真实 WebView：WebJSProvider/BackstageWebView（webView/webViewGetSource/webViewGetOverrideUrl）。
- UI 能力：JsUIProvider 的真实实现（toast/startBrowser/getVerificationCode 等）。
- JsExtensions 其余方法（压缩/字体/TTF/读书配置/主题/加密）按需实现。
