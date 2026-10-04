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
| `md5Encode` | **177** | ✅ **第 5 步已实现**（JsExtensionsCore / hutool 对照 golden） | JsExtensions |
| `getString` | 16 | ✅ 已实现（AnalyzeRule 自有，`java` 对象直通） | AnalyzeRule 自有 |
| `ajax` | 8 | ✅ **已实现（真实网络，第 6 步 6B）**：`AjaxProvider` 默认已换为 `RealAjaxProvider`（AnalyzeUrl + URLSessionHTTPClient）；失败返回错误串 | AnalyzeRule 自有 |
| `t2s` | 6 | ✅ **第 5 步已实现**（quick-chinese-transfer 0.2.17 词典 + 排除词） | JsExtensions |
| `timeFormat` | 4 | ✅ **第 5 步已实现**（FastDateFormat `yyyy/MM/dd HH:mm` 对照） | JsExtensions |
| `toast` | 4 | ⚠️ 协议注入（`JsUIProvider`，默认抛 unsupported + 记 diagnostics；真实 UI 第 6 步） | JsExtensions |
| `hexDecodeToString` | 3 | ✅ **第 5 步已实现**（hutool Base16Codec 语义：奇数前补 0、非法抛错） | JsExtensions |
| `base64Encode` | 3 | ✅ **第 5 步已实现** | JsExtensions |
| `base64Decode` | 1 | ✅ **第 5 步已实现**（hutool 容错解码移植，逐字节对照） | JsExtensions |
| `startBrowser` | 1 | ⚠️ 协议注入（`JsUIProvider`，默认 unsupported；真实系统第 6 步） | JsExtensions |
| `webView` | 1 | ⚠️ 协议注入（`WebJSProvider`/`JsUIProvider`，默认 unsupported；真实 WebView 第 6 步） | JsExtensions |
| `refreshExplore` | 1 | ❌ 未实现（BaseSource 方法，非 JsExtensions，第 5/6 步） | BaseSource |

> **14 书源里没有任何书源用到 `java.getString` 之外的 Java 互操作来取 JS 对象键值以外的能力；
> `java.getString`/`java.ajax` 由 AnalyzeRule 自身实现，已在 `java` 对象上提供真实实现**
> （ajax 默认走 `AjaxProvider`，第 6 步 6B 起默认实现是 `RealAjaxProvider`（真实网络）；
> 失败时返回错误串，对齐 Kotlin `getOrElse { stackTraceStr }` 分支；测试/App 仍可注入
> `UnsupportedAjaxProvider` 覆盖）。

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

## 三、Java 互操作标记（Step 5 起：org.jsoup 已由替身放行）

| 标记 | 出现次数 | 书源 | 本步骤处理 |
|---|---|---|---|
| `Packages.org.jsoup.Jsoup.parse` | **8** | **台湾小说网** | ✅ **Step 5 已放行**：JsoupJSBridge（SwiftSoup 实现）支持 parse/select/text/html/attr/outerHtml/first/get/size/eq/remove |
| `org.jsoup.Jsoup.parse` | **2** | **爱丽丝书屋(免翻)** | ✅ 同上（无 `Packages.` 前缀的同一写法） |

> **Step 5 状态更新**：
> - `org.jsoup.Jsoup` / `Packages.org.jsoup.Jsoup` 两种写法已由 `JsoupJSBridge` 用 SwiftSoup 实现放行；
>   真实书源的 `parse(...).select(...)...` 链可以真实执行（端到端测试 `testAlice_jsoupParseWorks` /
>   `testTaiwan_realJsoupChainWorks` 断言实际结果）。
> - 其余 Rhino 互操作（`importClass`、`importPackage`、`JavaImporter`、`java.lang/util/io/net/math`、
>   非 jsoup 的 `Packages.xxx`）仍预检测抛 `RuleEngineError.jsError` + 记 diagnostics，不假装支持。
> - 旧版（7 书源扫描）曾写「魔丸小说也用到 Java 互操作」。按 14 书源严格扫描，
>   **魔丸小说并未命中任何 Rhino 互操作标记**（它的 JS 用的是 `java.hexDecodeToString / base64*
>   / ajax / cache.get/put`——这些是 JsExtensions/AjaxProvider/CacheManager）。

## 四、JS 片段统计（14 书源合计）

- `<js>...</js>` 片段：**13** 次
- `@js:` 片段：**196** 次
- `@webjs:` 片段：**0** 次（14 个书源均未用 WebJs）
- `{{...}}` 内联 JS 片段：**876** 次

## 五、第 5 步实现结果（按真实使用频次）

1. **`md5Encode`（177）**—— ✅ 已实现（hutool 5.8.22 对照 golden：空串/中文/emoji/超长/数字入参全对齐）。
2. **`t2s`（6）、`timeFormat`（4）**—— ✅ 已实现（quick-chinese-transfer 0.2.17 词典 + legado 排除词；FastDateFormat 对照）。
3. **`hexDecodeToString`（3）、`base64Encode`（3）、`base64Decode`（1）**—— ✅ 已实现
   （hutool Base16Codec/Base64Decoder 语义逐字节对照，含奇数列前补 0、容错解码、非法输入抛错）。
4. **`toast`（4）、`startBrowser`（1）、`webView`（1）**—— ⚠️ 协议注入（`JsUIProvider`/`WebJSProvider`），
   默认抛 unsupported + 记 diagnostics；真实 UI/WebView 第 6 步。
5. **`refreshExplore`（1）**—— ❌ BaseSource 方法（非 JsExtensions），第 5/6 步。

> 第 5 步另外实现（书源未用但属首批纯算法）：`s2t`、`timeFormatUTC`、`hexEncodeToString`、
> `base64DecodeToByteArray`、`hexDecodeToByteArray`、`htmlFormat`、`encodeURI`、`randomUUID`、
> `toNumChapter`、`strToBytes`、`bytesToStr`、`md5Encode16`。
> **第 6 步 6B 更新**：网络/文件类（get/post/head/ajaxAll/connect/cacheFile/downloadFile）已由
> `RealJsNetworkExtensionsProvider` **接真实实现**（`JsNetworkExtensionsProvider` 协议保留，
> `UnsupportedJsNetworkExtensionsProvider` 仍可注入覆盖；AnalyzeRule 默认已换为真实实现）。
> 各方法语义、JS 可见对象方法、落盘位置与 Kotlin 差异见文末「七、第 6 步 6B 实施明细」。
> 压缩/字体/TTF/读书配置/主题/加密等保持 Proxy 拦截抛错。
> JsExtensions 全量方法清单见 `Sources/.../JsExtensionsCatalog.swift`（JsExtensions.kt 67 +
> JsEncodeUtils.kt 27 = 94 个，正则自动提取），`scripts/verify_functions.py` 校验未处理清单为空。

## 六、JsExtensions 全量方法名（94 个 = JsExtensions 67 + JsEncodeUtils 27，正则自动提取）

```
HMacBase64 HMacHex aesBase64DecodeToByteArray aesBase64DecodeToString
aesDecodeArgsBase64Str aesDecodeToByteArray aesDecodeToString aesEncodeArgsBase64Str
aesEncodeToBase64ByteArray aesEncodeToBase64String aesEncodeToByteArray
aesEncodeToString ajax ajaxAll ajaxTestAll androidId base64Decode
base64DecodeToByteArray base64Encode bytesToStr cacheFile connect createAsymmetricCrypto
createSign createSymmetricCrypto deleteFile desBase64DecodeToString desDecodeToString
desEncodeToBase64String desEncodeToString digestBase64Str digestHex downloadFile
encodeURI get get7zByteArrayContent get7zStringContent getCookie getFile
getRarByteArrayContent getRarStringContent getReadBookConfig getReadBookConfigMap
getSource getTag getThemeConfig getThemeConfigMap getThemeMode getTxtInFolder
getVerificationCode getWebViewUA getZipByteArrayContent getZipStringContent head
hexDecodeToByteArray hexDecodeToString hexEncodeToString htmlFormat importScript log
logType longToast md5Encode md5Encode16 openUrl openVideoPlayer post queryBase64TTF
queryTTF randomUUID readFile readTxtFile replaceFont s2t startBrowser startBrowserAwait
strToBytes t2s timeFormat timeFormatUTC toNumChapter toURL toast
tripleDESDecodeArgsBase64Str tripleDESDecodeStr tripleDESEncodeArgsBase64Str
tripleDESEncodeBase64Str un7zFile unArchiveFile unrarFile unzipFile webView
webViewGetOverrideUrl webViewGetSource
```

> `ajax`/`get`/`getSource`/`getTag`/`put` 由 AnalyzeRule 自身实现（catalog `selfImplemented`）；
> `log` 由 AnalyzeRule 记录诊断提供；`md5Encode/md5Encode16/t2s/s2t/timeFormat/timeFormatUTC/`
> `base64Encode/base64Decode/base64DecodeToByteArray/hexDecodeToString/hexEncodeToString/`
> `hexDecodeToByteArray/htmlFormat/encodeURI/randomUUID/toNumChapter/strToBytes/bytesToStr`
> 为 Step 5 真实实现（JsExtensionsCore）；`toast/longToast/openUrl/startBrowser/startBrowserAwait/`
> `getVerificationCode/webView` 经 JsUIProvider/WebJSProvider 注入；`get/post/head/ajaxAll/connect/`
> `cacheFile/downloadFile` 经 `RealJsNetworkExtensionsProvider`（**第 6 步 6B 已接真实实现**，
> 见文末「七」）。其余（压缩/字体/TTF/读书配置/主题/
> 加密等）保持 JS Proxy 拦截抛错 + 记 diagnostics，且 14 书源使用次数均为 0。

## 七、第 6 步 6B 实施明细（网络方法真实实现）

> 第 6 步 6B 新增：`Sources/LegadoBookSource/Network/RealJsNetworkExtensionsProvider.swift`
> （JsNetworkExtensionsProvider 真实实现）与 `RealAjaxProvider.swift`（AjaxProvider 真实实现）；
> `AnalyzeRule` 的 init 默认参数已把两者换成真实实现（`Unsupported*` 定义与协议均未改动，
> 测试/App 仍可注入覆盖）。

### 7.1 方法与 JS 可见对象

| `java.xxx` | 语义（对齐 JsExtensions.kt） | JS 返回值 |
|---|---|---|
| `ajax(url[, callTimeout])` | AnalyzeUrl（含 concurrentRateLimiter 限速）→ URLSessionHTTPClient → 解码后 body；失败返回 `"ajax(url) error\n..."` 错误串（对齐 `getOrElse { stackTraceStr }`） | String |
| `get(url, headers[, timeout])` | Jsoup.connect 语义（不走 AnalyzeUrl）：followRedirects(false)、timeout 默认 30000ms、ignoreContentType | Connection.Response 替身 |
| `post(url, body[, headers[, timeout]])` | 同上 + requestBody(body)（jsoup 不自动加 Content-Type，用户给了才发） | Connection.Response 替身 |
| `head(url[, headers][, timeout])` | 同上（HEAD） | Connection.Response 替身 |
| `connect(url[, headerJSON][, callTimeout])` | AnalyzeUrl（header 为 JSON 字符串，容错解析）→ StrResponse；失败返回错误体（code 200/callTime 0，对齐 Kotlin 错误构造器） | StrResponse 替身 |
| `ajaxAll([url...])` | 并发（默认 4，可注入）请求，顺序与输入一致；任一失败整体抛错（对齐 isTest=false） | StrResponse 替身数组 |
| `cacheFile(url[, saveTime])` | md5Encode16(url) 查 CacheManager；命中文件 → 读文本；否则 downloadFile 落盘并缓存后读文本 | String（文件文本） |
| `downloadFile(url)` | 文件名 `md5Encode16(url).<type>`（type = analyzeUrl.type ?: getSuffix(url)），写入缓存根 | String（相对路径，带前导 `/`） |

**Connection.Response 替身（get/post/head）在 JS 里可调用的方法**：
`body()`、`statusCode()`、`statusMessage()`、`headers()`（`{name: [values]}`，另带非枚举
`get(name)` 大小写不敏感查询，向 jsoup Headers 靠拢）、`cookies()`（`{name: value}`，带 `get(name)`）、
`header(name)`（首个同名值或 null）、`cookieKey(name)`（cookies()[name] 便捷读取，Kotlin 无此方法）、
`url()`、`contentType()`。

**StrResponse 替身（connect/ajaxAll 元素）在 JS 里可调用的方法**（对齐 jsHelp.md 文档面）：
`body()`、`code()`、`message()`、`headers()`、`raw()`、`toString()`、`callTime()`、`url()`。

> 差异：Kotlin 的 StrResponse 是「JavaBean 属性 + 同名方法」双通道（`.body` 与 `body()` 都能用），
> JS 对象上同名数据属性与方法无法并存，本移植只提供**同名方法**（`.body` 请写 `.body()`）。

### 7.2 落盘位置

- 缓存根（cacheFile/downloadFile）：默认 `FileManager` 的 Caches 目录 + `legado-js-cache/`
  （可注入；测试用临时目录）。**差异：Kotlin 用 `Context.externalCacheDir`
  （`/android/data/{pkg}/cache`）。**
- 文件名：`md5Encode16(url) + "." + type`；`downloadFile` 返回相对路径 `/<文件名>`
  （对齐 Kotlin `path.substring(getCachePath().length)`）。
- `cacheFile` 的 key 也是 `md5Encode16(url)`；缓存条目用 `CacheManager.put(key, path, saveTime)`
  （注入的 cacheManager 是带 saveTime 的 `CacheManager` 时透传 TTL，否则退化为无 TTL 版本）。

### 7.3 主要差异（与 Kotlin）

1. 缓存根目录不同（见上）。
2. 文本解码为最小链（BOM → 显式 charset → Content-Type charset → UTF-8 替换语义）；
   Kotlin 还有 ICU4J `EncodingDetect.getHtmlEncode` 检测级（该链在 step6-6b-wip 分支 WIP(4)/(5)，
   尚未并入 main）。
3. headers 参数顺序按 JSON 字典序（JS 对象插入顺序经桥接不可恢复；键唯一时不影响 HTTP 语义）。
4. get/post/head 经 URLSessionHTTPClient 会注入 CookieStore 的 Cookie（Kotlin 的 Jsoup.connect
   用自建客户端，不带 legado CookieStore）；书源并发率限速也未接线（provider 不携带书源）。
5. StrResponse 只提供同名方法（无 `.body` 属性通道）；`raw()`/`toString()` 返回
   `Response{code=..., message=..., url=...}` 描述串（Kotlin 是 okhttp Response.toString()）。
6. `ajax` 失败串里是 Swift 错误描述（Kotlin 是 Java stackTraceStr）。
