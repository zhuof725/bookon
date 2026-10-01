# JsExtensions（`java.xxx`）使用情况表 — 第 5 步范围依据

扫描对象：`配置文件_7个.json`（7 个真实书源：淘小说书城 / 得奇小说网 / 速读谷 / 魔丸小说 /
笔趣阁345 / 得间小说 / 爱丽丝书屋）里实际出现的 `java.<method>` 调用。
扫描方式：正则 `java\.([a-zA-Z_]\w*)` 统计次数（脚本见 `scripts/` 的分析思路，结果可用
`python3 -c` 复算）。

## 一、真实书源里实际调用的 `java.xxx`（按次数降序）

| 方法名 | 调用次数 | 本步骤状态 | 归属 |
|---|---|---|---|
| `ajax` | 7 | ✅ 已实现（AjaxProvider 注入，默认返回错误串；真实网络第 6 步） | AnalyzeRule 自有 |
| `getString` | 7 | ✅ 已实现（AnalyzeRule 自有，`java` 对象直通） | AnalyzeRule 自有 |
| `hexDecodeToString` | 3 | ❌ 未实现（第 5 步；调用即抛明确错误 + 记 diagnostics） | JsExtensions |
| `base64Encode` | 3 | ❌ 未实现（第 5 步） | JsExtensions |
| `base64Decode` | 1 | ❌ 未实现（第 5 步） | JsExtensions |
| `webView` | 1 | ❌ 未实现（第 5 步，依赖真实 WebView） | JsExtensions |
| `refreshExplore` | 1 | ❌ 未实现（BaseSource 方法，非 JsExtensions，第 5/6 步） | BaseSource |

> 说明：`java.getString`/`java.ajax` 由 AnalyzeRule 自身实现，已在 `java` 对象上提供真实
> 实现（ajax 默认走注入的 `AjaxProvider`，无真实网络时返回错误串，对齐 Kotlin 失败分支）。
> 其余 `java.xxx` 均为 JsExtensions 方法，本步骤不实现方法体，调用即抛
> 「java.xxx 尚未实现（JsExtensions，第 5 步）」并写入 diagnostics。

## 二、Java 互操作标记（Rhino-only，JavaScriptCore 无法运行）

| 标记 | 出现次数 | 书源 | 本步骤处理 |
|---|---|---|---|
| `org.jsoup` | 2 | 爱丽丝书屋（content 的 `@js:` 里用 `org.jsoup.Jsoup.parse`） | 预检测到即抛 `RuleEngineError.jsError` + 记 diagnostics，不假装支持 |

> 魔丸小说、爱丽丝书屋的 `<js>`/`@js:` 规则中含 Java 互操作或未实现的 JsExtensions 方法，
> 端到端测试断言这些规则触发「未实现 / 不支持」错误（见
> `AnalyzeRuleEndToEndTests.testMowan_jsUnimplementedThrows` /
> `testAlice_jsoupInteropThrows`），而非假装成功。

## 三、JS 片段统计

- `<js>...</js>` 片段出现：**11** 次
- `@js:` 片段出现：**12** 次
- `@webjs:` 片段出现：**0** 次（本批 7 个书源均未用 WebJs）

## 四、第 5 步实现优先级建议（按真实使用频次）

1. `hexDecodeToString`（3）、`base64Encode`（3）、`base64Decode`（1）—— 纯编码，优先实现，
   覆盖魔丸小说的解密链路。
2. `webView`（1）—— 依赖真实 WebView，和 `@webjs:`/BackstageWebView 一起在第 5/6 步做。
3. JsExtensions 全量 67 个方法清单见 `Sources/.../JsExtensionsCatalog.swift`
   （正则自动提取自 `JsExtensions.kt`），第 5 步按此清单逐个实现。

## 五、JsExtensions 全量方法名（67 个，正则自动提取，第 5 步范围）

```
ajax ajaxAll ajaxTestAll androidId base64Decode base64DecodeToByteArray base64Encode
bytesToStr cacheFile connect deleteFile downloadFile encodeURI get get7zByteArrayContent
get7zStringContent getCookie getFile getRarByteArrayContent getRarStringContent
getReadBookConfig getReadBookConfigMap getSource getTag getThemeConfig getThemeConfigMap
getThemeMode getTxtInFolder getVerificationCode getWebViewUA getZipByteArrayContent
getZipStringContent head hexDecodeToByteArray hexDecodeToString hexEncodeToString htmlFormat
importScript log logType longToast openUrl openVideoPlayer post queryBase64TTF queryTTF
randomUUID readFile readTxtFile replaceFont s2t startBrowser startBrowserAwait strToBytes
t2s timeFormat timeFormatUTC toNumChapter toURL toast un7zFile unArchiveFile unrarFile
unzipFile webView webViewGetOverrideUrl webViewGetSource
```

> 其中 `ajax`/`get`/`getSource`/`getTag`/`put` 由 AnalyzeRule 自身实现（见 catalog 的
> `selfImplemented`）；`log` 由 AnalyzeRule 以记录诊断的形式提供。其余均未实现。
