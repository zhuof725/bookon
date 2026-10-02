# JsExtensions（`java.xxx`）使用情况表 — 第 5 步范围依据

> **第 4 步收尾更新**：扫描对象从旧的 `配置文件_7个.json` 换成用户提供的 **`配置文件_14个.json`**
> （14 个真实书源：松鹤阅读 / 无错 / 小原文学网 / 淘小说吧 / 淘小说书城 / 得奇小说网 / 速读谷 /
> 魔丸小说 / 星星小说网 / 台湾小说网 / 衍墨轩 / 笔趣阁345 / 得间小说 / 爱丽丝书屋）。
> Rhino 互操作、java/cookie/cache 方法清单均按 14 个书源重新严格正则扫描，**以本表为准**。

扫描方式：严格正则逐个书源扫描（不是宽松匹配，不会把 `java.ajax` 误算成其它）。
- 方法调用：`java.<method>(` / `cookie.<method>(` / `cache.<method>(`，排除 `java.lang/util/io/net/math.` 这类包路径。
- Rhino 互操作：`Packages.`、`importClass(`、`importPackage(`、`JavaImporter`、`new java.`、
  `java.(lang|util|io|net|math).`、`org.jsoup.`、`.getClass()`。

## 一、真实书源里实际调用的 `java.xxx`（14 书源，按次数降序）

| 方法名 | 调用次数 | 本步骤状态 | 归属 |
|---|---|---|---|
| `md5Encode` | **177** | ❌ 未实现（第 5 步；调用即抛明确错误 + 记 diagnostics） | JsExtensions |
| `getString` | 16 | ✅ 已实现（AnalyzeRule 自有，`java` 对象直通） | AnalyzeRule 自有 |
| `ajax` | 8 | ✅ 已实现（AjaxProvider 注入，默认返回错误串；真实网络第 6 步） | AnalyzeRule 自有 |
| `t2s` | 6 | ❌ 未实现（第 5 步） | JsExtensions |
| `timeFormat` | 4 | ❌ 未实现（第 5 步） | JsExtensions |
| `toast` | 4 | ❌ 未实现（第 5 步，需 UI 环境） | JsExtensions |
| `hexDecodeToString` | 3 | ❌ 未实现（第 5 步） | JsExtensions |
| `base64Encode` | 3 | ❌ 未实现（第 5 步） | JsExtensions |
| `base64Decode` | 1 | ❌ 未实现（第 5 步） | JsExtensions |
| `startBrowser` | 1 | ❌ 未实现（第 5 步） | JsExtensions |
| `webView` | 1 | ❌ 未实现（第 5 步，依赖真实 WebView） | JsExtensions |
| `refreshExplore` | 1 | ❌ 未实现（BaseSource 方法，非 JsExtensions，第 5/6 步） | BaseSource |

> **14 书源里没有任何书源用到 `java.getString` 之外的 Java 互操作来取 JS 对象键值以外的能力；
> `java.getString`/`java.ajax` 由 AnalyzeRule 自身实现，已在 `java` 对象上提供真实实现**
> （ajax 默认走注入的 `AjaxProvider`，无真实网络时返回错误串，对齐 Kotlin 失败分支）。

## 二、`cookie.xxx` / `cache.xxx`（14 书源）

| 对象 | 方法名 | 调用次数 | 书源 | 本步骤状态 | 归属 |
|---|---|---|---|---|---|
| `cookie` | `removeCookie` | 1 | 笔趣阁345 | ✅ 已实现（JSEngine 已绑定 `cookie.removeCookie`，默认内存 CookieStore） | JSEngine 绑定 |
| `cache` | `get` | 2 | 魔丸小说 | ✅ 已实现（JSEngine 已绑定 `cache.get`，默认内存 CacheManager） | JSEngine 绑定 |
| `cache` | `put` | 2 | 魔丸小说 | ✅ 已实现（JSEngine 已绑定 `cache.put`，默认内存 CacheManager） | JSEngine 绑定 |

> JSEngine 绑定的完整 cookie 方法：`getCookie / setCookie / removeCookie`；
> 完整 cache 方法：`get / put / delete`（见 `Sources/.../JSEngine.swift`）。
> 真实网络/磁盘持久化实现第 5/6 步；当前默认内存实现即可支撑 `cache.get/put/delete` 与
> `cookie.removeCookie` 的调用语义。

## 三、Java 互操作标记（Rhino-only，JavaScriptCore 无法运行）

| 标记 | 出现次数 | 书源 | 本步骤处理 |
|---|---|---|---|
| `Packages.org.jsoup.Jsoup.parse` | **8** | **台湾小说网** | 预检测到即抛 `RuleEngineError.jsError` + 记 diagnostics，不假装支持 |
| `org.jsoup.Jsoup.parse` | **2** | **爱丽丝书屋(免翻)** | 同上（同一互操作，`Packages.` 前缀省略的写法） |

> **更正**：旧版（7 书源扫描）曾写「魔丸小说也用到 Java 互操作」。按 14 书源严格扫描，
> **魔丸小说并未命中任何 Rhino 互操作标记**（它的 JS 用的是 `java.hexDecodeToString / base64*
> / ajax / cache.get/put`——这些全是 JsExtensions/AjaxProvider/CacheManager，第 5/6 步）。
> 爱丽丝书屋的 `org.jsoup` 命中 2 次、台湾小说网的 `Packages.org.jsoup` 命中 8 次，均为
> Java 互操作，JavaScriptCore 无法运行。
> 真实书源里凡含这两种互操作的 `<js>`/`@js:` 规则，端到端测试断言其触发
> 「不支持/未实现」错误（见 `AnalyzeRuleEndToEndTests.testAlice_jsoupInteropThrows`），
> 而非假装成功。**台湾小说网尚无端到端测试**（其规则含 `Packages.org.jsoup` 互操作，预期同样抛错）。

## 四、JS 片段统计（14 书源合计）

- `<js>...</js>` 片段：**13** 次
- `@js:` 片段：**196** 次
- `@webjs:` 片段：**0** 次（14 个书源均未用 WebJs）
- `{{...}}` 内联 JS 片段：**876** 次

## 五、第 5 步实现优先级建议（按真实使用频次）

1. **`md5Encode`（177）**—— 14 书源里最高频（全部来自淘小说吧的签名/加密链路），第 5 步最优先，
   纯算法（MD5），无外部依赖。
2. **`t2s`（6）、`timeFormat`（4）**—— 简繁转换与时间格式化，纯算法。
3. **`hexDecodeToString`（3）、`base64Encode`（3）、`base64Decode`（1）**—— 纯编码，覆盖魔丸小说解密链路。
4. **`toast`（4）、`startBrowser`（1）、`webView`（1）**—— 需 UI/系统能力，和真实 WebView 一起第 5/6 步。
5. **`refreshExplore`（1）**—— BaseSource 方法（非 JsExtensions），第 5/6 步。

> JsExtensions 全量 67 个方法清单见 `Sources/.../JsExtensionsCatalog.swift`
> （正则自动提取自 `JsExtensions.kt`），第 5 步按本清单逐个实现；上面 1-5 是**真实书源
> 实际用到**的，其余方法未被这 14 个书源使用。

## 六、JsExtensions 全量方法名（67 个，正则自动提取，第 5 步范围）

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
