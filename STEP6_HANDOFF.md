# Step 6 交付文档（6A：AnalyzeUrl 规则解析与请求构造；6B 待做）

> 只写最终状态。6A 的 CI 结果见文末「最终验证」；6B 尚未开始。

## 范围（6A）

完整移植 `model/analyzeRule/AnalyzeUrl.kt` 的**规则解析与请求构造**（不发网络请求），
以及它依赖的 `ConcurrentRateLimiter.kt`、`help/http/CookieStore.kt`、`CookieManager.kt`、
`help/CacheManager.kt`、`AppPattern.kt` 里的 `JS_PATTERN`/`dataUriRegex`/`domainRegex`、
`NetworkUtils.kt` 的编码与域名工具。真实网络（URLSession）在 6B。

## 交付内容

### 源码（`Sources/LegadoBookSource/Network/`，均为新增文件，未改动第 1–5 步行为）

| 文件 | 对应 Kotlin | 说明 |
|---|---|---|
| `AnalyzeUrl.swift` | AnalyzeUrl.kt | `init`/`initUrl`/`analyzeJs`（JS_PATTERN 循环 + `@result` 替换）/`replaceKeyPageJs`（`{{}}` 内嵌规则 + `<a,b>` 页码规则）/`analyzeUrl`（paramPattern 切分、UrlOption、method/charset/retry/type/webJs/bodyJs/dnsIp/js/serverID/webViewDelayTime）/`analyzeFields`/`analyzeQuery`/`encodeParams`/`appendEncoded`/`evalJS`（绑定 java=自身、baseUrl、cookie、cache、page、key、speakText、speakSpeed、book、source、result、infoMap）/`put`/`get`/`getUserAgent`/`isPost`/`getSource`/`getTag`/`getByteArrayIfDataUri`/`setCookie` + **`buildRequest()`** |
| `UrlOption.swift` | AnalyzeUrl.kt 的 `UrlOption` | 全部字段与 getter；复刻 legado 的 Gson 定制（`StringJsonDeserializer`、`IntJsonDeserializer`、`ToNumberPolicy.LONG_OR_DOUBLE`、`disableHtmlEscaping`）与「GSONStrict 失败 → GSON 宽松回退」两次尝试（含 `usedLenientFallback` 标记） |
| `GsonJSON.swift` | （新） | Gson 兼容 JSON 值模型与解析器：保序对象、Long/Double 区分、strict/legacy 两种严格度、`Long.intValue()` 的 32 位截断语义 |
| `HTTPTypes.swift` | （新） | `RequestMethod`、`HTTPRequest`（有序 headers、body、contentType、charset、retry、readTimeout、callTimeout、useWebView、webJs、bodyJs、dnsIp、proxy、type、serverID、enabledCookieJar、webViewDelayTime）、`HTTPResponse`（最终 url/状态/有序头/body/callTime）、`HTTPClient` 协议 + `ScriptedHTTPClient` 假实现、`HTTPError`（错误码 -1…-7 对齐 Kotlin 的异常分类） |
| `ConcurrentRateLimiter.swift` | ConcurrentRateLimiter.kt | **actor 化** + 时钟/存储注入；`"次数/毫秒"` 与纯毫秒两种写法、frequency 递增、超限抛 `ConcurrentLimitError`（含 waitTime）、到时重置、`updateConcurrentRate` 非法输入保留旧记录；`ConcurrentRecordStore.shared` 对应 companion 的全局 map |
| `CookieStore.swift` | CookieStore.kt | `cookieToMap`/`mapToCookie`/`setCookie`/`replaceCookie`/`getCookie`（持久化+session 合并，>4096 循环删键）/`getKey`/`getCookieNoSession`/`removeCookie`/`clear`；协议 + 内存 + 文件实现 |
| `CookieManager.swift` | CookieManager.kt | `mergeCookies`/`mergeCookiesToMap`/`setSessionCookie` 读写/`parseSetCookie`（持久化判定=Expires 或 Max-Age）/`saveCookiesFromHeaders`（持久化与会话分流）/`cookieHeaderFor`（对应 `loadRequest`）/`removeCookie(url:key:)` |
| `CacheManager.swift` | CacheManager.kt | `put(key:value:saveTime:)`（秒→毫秒 deadline）、`get(key)`（内存→存储 + 过期判定）、`get(onlyDisk:)`、`putMemory/getFromMemory/deleteMemory`、`getInt/getLong`、`delete`；协议 + 内存（50MB 近似 LRU）+ 文件（JSON 原子写）实现 |
| `NetworkUtilsEncoding.swift` | NetworkUtils.kt | `encodedQuery`/`encodedForm`（逐 UTF-16 单元判定）/`isDigit16Char`/`getSubDomain`/`getDomain`/`isIPv4Address`/`isIPv6Address`/`isIPAddress`/`effectiveTldPlusOne` |
| `JSEngine.swift`（改） | — | `Bindings` 增加 `extraBindings`（默认空，不影响既有调用方），供 AnalyzeUrl 绑定 page/key/speakText/speakSpeed/book/source/infoMap |

### 测试

- `Tests/LegadoNetworkTests/AnalyzeUrlGoldenComparisonTests.swift`：三组 golden 对照
  （`url_codec_cases` 299 条、`url_option_cases` 84 条、`analyze_url_cases` 94 条），
  失败信息里的 `%` 做了转义（否则 XCTest 的 printf 风格处理会吞掉 `%39` 之类的片段）。
- `Tests/LegadoNetworkTests/CookieGoldenComparisonTests.swift`：`cookie_cases` 47 条。
- `Tests/LegadoNetworkTests/ConcurrentRateLimiterTests.swift`：22 个用例（假时钟，确定性）。
- `Tests/LegadoNetworkPublicAPITests/NetworkPublicAPITests.swift`：16 个用例（普通 `import`，非 @testable），
  覆盖 AnalyzeUrl/UrlOption/NetworkUtils/HttpTypes/CookieMerge/限速器的公开面。
- 测试 target 新增两个（`LegadoNetworkTests` 带 golden 资源、`LegadoNetworkPublicAPITests`），
  CI 两个测试 job 增加把 golden 镜像到 `Tests/LegadoNetworkTests/Resources/golden/` 的步骤。

### golden（`scripts/golden`）

- `UrlRuleGen.java`（新增）：
  - `runCodec`：`encodeParams`（含查询路径用 hutool `RFC3986.UNRESERVED.orNew(PercentCodec.of(...))`、
    表单路径逐字段 `URLEncoder.encode`、`checkEncoded` 判定）、`encodedQuery`/`encodedForm`、
    `EncoderUtils.escape`；
  - `runUrlOption`：真实 Gson + 上面那份定制适配器（与本文件同源的手工搬运）+ STRICT/LEGACY 两次尝试；
  - `runAnalyzeUrl`：**AnalyzeUrl 调度逻辑的手工 Java 移植**（analyzeJs / replaceKeyPageJs / analyzeUrl /
    paramPattern / 页码规则），JS 用真实 Rhino 1.8.1（VERSION_ES6 + interpretedMode）；
  - `runCookie`：`cookieToMap`/`mapToCookie`/`mergeCookies` 的手工移植版。
- 用例文件：`url_codec_cases.json`（299）、`url_option_cases.json`（84）、`analyze_url_cases.json`（94）、
  `cookie_cases.json`（47），全部标注「合成样本」。
- `Main.java`：挂载 `codecCases`/`urlOptionCases`/`analyzeUrlCases`/`cookieCases`（只加不改已有分支）。

> **README 已标明**：`UrlRuleGen.java` 里的 AnalyzeUrl 调度逻辑是**手工 Java 移植**，
> 它只用来验证真实库的行为（hutool / Gson / Rhino / java.net.URL），不是 Kotlin 原码本身。

### 脚本与文档

- `scripts/verify_functions.py`：新增 `AnalyzeUrl.kt`（59 函数）、`ConcurrentRateLimiter.kt`、
  `CookieStore.kt`、`CookieManager.kt`、`CacheManager.kt` 的映射与 EXCLUDED（6B/不适用项逐条给理由）；
  `NetworkUtils.kt` 里 6A 已实现的 9 个函数从 EXCLUDED 移除。实测 **Kotlin 函数总数 272，
  「Kotlin 有但 Swift 没处理」清单为空**。
- `reference/kotlin/analyzeRule/` 新增 5 个 Kotlin 参考文件副本（AnalyzeUrl/ConcurrentRateLimiter/
  CookieStore/CookieManager/CacheManager）。

## 与 Kotlin 的已知差异（README 差异表逐条登记）

| # | 主题 | Kotlin | 本移植 | 影响 |
|---|---|---|---|---|
| 1 | `getSubDomain` 的公共后缀 | Android `PublicSuffixDatabase`（完整列表） | 内置常见多段后缀表 + 默认末两段 | 常见书源域名一致；冷门后缀会取末两段 |
| 2 | 4096 cookie 截断 | `cookieMap.keys.random()` 随机删 | 按插入顺序删第一个 | 语义同为「降到 4096 以下」，结果可复现 |
| 3 | 持久化存储 | Room（cookieDao）/ ACache | 协议 + JSON 文件原子写 | 接口一致，落盘格式不同 |
| 4 | `getCookie`/`getSessionCookie` 的 domain 归属 | 同 | 同 | — |
| 5 | `escape` 的遍历单位 | Kotlin `Char`（UTF-16 单元） | 同（emoji → `%ud83d%ude00`） | golden 已对照 |
| 6 | 非 UTF-8 字符集编码 | `String.getBytes(charset)` / `URLEncoder`：不可表示字符 → `?`；多字节里的 ASCII 字节同样 %XX | 同（逐标量 + 全部字节转义） | golden 已对照 |
| 7 | `Long.intValue()` 截断 | 32 位截断（`{"retry":9999999999}` → 1410065407） | 同 | golden 已对照 |
| 8 | `{{}}` 取值 | `evalJS(it) ?: ""`，Double%1==0 用 `%.0f` | 同 | golden 已对照 |
| 9 | `@js:` 取值 | `evalJS(...).toString()`（null → `"null"`） | 同 | golden 已对照 |
| 10 | HttpUrl 规范化（OkHttp） | OkHttp 的 `HttpUrl` 会对 path/空查询做规范化 | 本移植的 `buildRequest()` 直接拼接 `urlNoQuery` + `?` + encodedQuery，不做 OkHttp 级规范化 | 6B 的请求对照会暴露差异（自动头/规范化），届时在此表补充 |
| 11 | WebView 分支 | `BackstageWebView`（useWebView=true） | 不实现：`HTTPRequest.useWebView/webJs/bodyJs/dnsIp/proxy` 只记录 | 6B/后续 |
| 12 | `ConcurrentRateLimiter` 的阻塞版本 | `getConcurrentRecordBlocking`/`withLimitBlocking` | 只有 async 版本（不提供阻塞 API） | 调用方改用 `withLimit` |
| 13 | `getSubDomainOrNull`/`getDomain` 等 | 见 Kotlin | `getDomain` 已实现；`getSubDomainOrNull` 未移植（AnalyzeUrl 只用非空版本） | — |

## 最终验证（真实 CI 结果，run 37142531415，HEAD 见 ci_logs）

三个 job 全绿 ✅：

| job | 状态 | 关键数字 | 日志 |
|---|---|---|---|
| golden（ubuntu） | ✓ success | **1757 条用例 / 19 个用例文件**（本轮新增 524 条：编码 299、UrlOption 84、AnalyzeUrl 94、Cookie 47） | `ci_logs/step6a_final_golden.log` |
| test-macos | ✓ success | **Executed 495 tests, 0 failures** | `ci_logs/step6a_final_macos.log` |
| test-ios-simulator | ✓ success | **实际执行 495 个测试**（与 macOS 相等） | `ci_logs/step6a_final_ios.log` |

**iOS == macOS 核对**：脚本实测打印 `✅ iOS 总数与 macOS 总数一致（均为 495）`。
（6A 前：453 个测试 / 1233 条 golden；6A 新增 42 个测试方法、524 条 golden 用例。）

## 后续（6B）

- `URLSessionHTTPClient`（delegate 手工重定向/`Set-Cookie` 全跳保存/超时/重试/gzip/deflate/证书/代理/dnsIp 差异登记）。
- `StrResponse` 字符集判定顺序 + icu4j 检测器完整移植。
- `JsNetworkExtensionsProvider` 真实实现（get/post/head/ajax/ajaxAll/connect/cacheFile/downloadFile）。
- 本地测试服务器（NWListener）+ 请求对照 golden（≥60）、重定向/Cookie（≥30）、字符集（≥200+40）。
- live-smoke 可选 job。
