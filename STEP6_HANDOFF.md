# Step 6 交付文档（6A：AnalyzeUrl 规则解析与请求构造；6B：真实网络 + 字符集检测 + 请求对照）

> 只写最终状态。6A 与 6B 均已并入 main，CI 结果见文末「最终验证」。

## 范围

### 6A

完整移植 `model/analyzeRule/AnalyzeUrl.kt` 的**规则解析与请求构造**（不发网络请求），
以及它依赖的 `ConcurrentRateLimiter.kt`、`help/http/CookieStore.kt`、`CookieManager.kt`、
`help/CacheManager.kt`、`AppPattern.kt` 里的 `JS_PATTERN`/`dataUriRegex`/`domainRegex`、
`NetworkUtils.kt` 的编码与域名工具。

### 6B

在 6A 的请求构造之上补全**真实网络**：`URLSessionHTTPClient`（delegate 手工重定向 /
`Set-Cookie` 全跳保存 / 超时 / 重试 / gzip+deflate / 信任服务器证书 / `dnsIp` 不支持登记）、
`RealJsNetworkExtensionsProvider`（`java.get/post/head/ajax/ajaxAll/connect/cacheFile/downloadFile`）、
`RealAjaxProvider`、**legado icu4j 检测器全量移植 + `EncodingDetect` 判定链接入响应解码**、
`ConcurrentRateLimiter` 接到 get/post/head、JS 面 `StrResponse` 的 `.body` 属性/方法双通道。

## 交付内容

### 源码（`Sources/LegadoBookSource/Network/`）

| 文件 | 对应 Kotlin | 说明 |
|---|---|---|
| `AnalyzeUrl.swift` | AnalyzeUrl.kt | `init`/`initUrl`/`analyzeJs`（JS_PATTERN 循环 + `@result` 替换）/`replaceKeyPageJs`（`{{}}` 内嵌规则 + `<a,b>` 页码规则）/`analyzeUrl`（paramPattern 切分、UrlOption、method/charset/retry/type/webJs/bodyJs/dnsIp/js/serverID/webViewDelayTime）/`analyzeFields`/`analyzeQuery`/`encodeParams`/`appendEncoded`/`evalJS`（绑定 java=自身、baseUrl、cookie、cache、page、key、speakText、speakSpeed、book、source、result、infoMap）/`put`/`get`/`getUserAgent`/`isPost`/`getSource`/`getTag`/`getByteArrayIfDataUri`/`setCookie` + **`buildRequest()`** + **`makeRateLimiter(concurrentRate:key:)`**（6B：从书源 `concurrentRate` 字符串造限速器） |
| `UrlOption.swift` | AnalyzeUrl.kt 的 `UrlOption` | 全部字段与 getter；复刻 legado 的 Gson 定制（`StringJsonDeserializer`、`IntJsonDeserializer`、`ToNumberPolicy.LONG_OR_DOUBLE`、`disableHtmlEscaping`）与「GSONStrict 失败 → GSON 宽松回退」两次尝试（含 `usedLenientFallback` 标记） |
| `GsonJSON.swift` | （新） | Gson 兼容 JSON 值模型与解析器：保序对象、Long/Double 区分、strict/legacy 两种严格度、`Long.intValue()` 的 32 位截断语义 |
| `HTTPTypes.swift` | （新） | `RequestMethod`、`HTTPRequest`（有序 headers、body、contentType、charset、retry、readTimeout、callTimeout、useWebView、webJs、bodyJs、dnsIp、proxy、type、serverID、enabledCookieJar、webViewDelayTime、`followRedirects`）、`HTTPResponse`（最终 url/状态/有序头/body/callTime）、`HTTPClient` 协议 + `ScriptedHTTPClient` 假实现、`HTTPError`（错误码 -1…-7 对齐 Kotlin 的异常分类） |
| `HttpUrl.swift` | OkHttp `HttpUrl` | 按 OkHttp 5.x 行为复刻的规范化（非法 `%` 原样、控制字符丢弃、`\` 当 `/`、`%2E`/`%2e%2e` 视作点段、多前导斜杠折叠、输入 trim、片段 `#` 不编码）；`buildRequest()` 产出的 URL 必经它 |
| `ConcurrentRateLimiter.swift` | ConcurrentRateLimiter.kt | **actor 化** + 时钟/存储注入；`"次数/毫秒"` 与纯毫秒两种写法、frequency 递增、超限抛 `ConcurrentLimitError`（含 waitTime）、到时重置、`updateConcurrentRate` 非法输入保留旧记录；`ConcurrentRecordStore.shared` 对应 companion 的全局 map |
| `CookieStore.swift` | CookieStore.kt | `cookieToMap`/`mapToCookie`/`setCookie`/`replaceCookie`/`getCookie`（持久化+session 合并，>4096 循环删键）/`getKey`/`getCookieNoSession`/`removeCookie`/`clear`；协议 + 内存 + 文件实现 |
| `CookieManager.swift` | CookieManager.kt | `mergeCookies`/`mergeCookiesToMap`/`setSessionCookie` 读写/`parseSetCookie`（持久化判定=Expires 或 Max-Age）/`saveCookiesFromHeaders`（持久化与会话分流）/`cookieHeaderFor`（对应 `loadRequest`）/`removeCookie(url:key:)` |
| `CacheManager.swift` | CacheManager.kt | `put(key:value:saveTime:)`（秒→毫秒 deadline）、`get(key)`（内存→存储 + 过期判定）、`get(onlyDisk:)`、`putMemory/getFromMemory/deleteMemory`、`getInt/getLong`、`delete`；协议 + 内存（50MB 近似 LRU）+ 文件（JSON 原子写）实现 |
| `NetworkUtilsEncoding.swift` | NetworkUtils.kt | `encodedQuery`/`encodedForm`（逐 UTF-16 单元判定）/`isDigit16Char`/`getSubDomain`/`getDomain`/`isIPv4Address`/`isIPv6Address`/`isIPAddress`/`effectiveTldPlusOne` |
| `URLSessionHTTPClient.swift` | `help/http/OkHttpUtils.kt` + `SSLHelper` | 真实网络实现：delegate 拿 `willPerformHTTPRedirection` 手工重定向（`followRedirects` 可关、上限 20 同 OkHttp）、逐跳保存 `Set-Cookie`、超时（readTimeout/callTimeout）、retry、gzip/deflate 自动解压、**信任服务器证书**（等价 `SSLHelper`）、`dnsIp` 不支持并记 diagnostics、可选代理 |
| `RealJsNetworkExtensionsProvider.swift` | `help/JsExtensions.kt` | `ajax`/`get`/`post`/`head`/`connect`/`ajaxAll`/`cacheFile`/`downloadFile` 的真实实现；**`JsNetTextDecoder` 实现 legado 判定链**（BOM → explicit → Content-Type → `EncodingDetect.getHtmlEncode`）；**get/post/head 走 `ConcurrentRateLimiter`**；JS 信封 `\u{1}JSCONN\u{1}/JSSTR/JSSTRS` |
| `RealAjaxProvider.swift` | `help/http/OkHttpUtils.kt` | `AnalyzeUrl` → `getStrResponse` → `body`；失败返回 `ajax(url) error\n<错误>` |
| `CharsetDetector/CharsetDetector.swift` | `lib/icu4j/CharsetDetector.java` | legado 自带 icu4j 检测器的 Swift 移植（识别器打分 0–100、`detectAll` 按 confidence 降序、并列取识别器列表靠后者）；新增 `detectMatch(_:) -> Detection?`（无匹配返回 nil，不兜底）与 `detectAllMatches(_:)` |
| `CharsetDetector/EncodingDetect.swift` | `utils/EncodingDetect.kt` | `getHtmlEncode(_:)`（`<head>` 切片 → SwiftSoup `parseBodyFragment` → `<meta charset>` / `http-equiv=content-type` 的 `charset=`）、`getEncode(_:)`（检测器 + `"UTF-8"` 兜底）、`getEncode(file:)`（只收 ≥0x80 字节，上限 8000） |
| `CharsetDetector/CharsetTables.swift` | `lib/icu4j/*` 的表数据 | 由 `scripts/golden/extract_icu4j_tables.py` 从 legado 原码提取（52 KB，36 个表常量） |
| `JSEngine.swift`（改） | — | `Bindings` 增加 `extraBindings`（默认空，不影响既有调用方），供 AnalyzeUrl 绑定 page/key/speakText/speakSpeed/book/source/infoMap |
| `RuleEngine/JSJavaBridge.swift`（改） | — | `__installDualChannel` 让 `StrResponse` 在 JS 面同时提供 `.body` **属性**与 `.body()` **方法**；`__dualValue` 用 `new Proxy(callable, …)` 令二者语义一致（`String(x)`/`+`/`indexOf`/`length`/`JSON.stringify` 全部按字符串工作） |

### 测试

| 文件 | 内容 |
|---|---|
| `Tests/LegadoNetworkTests/AnalyzeUrlGoldenComparisonTests.swift` | 三组 golden 对照（`url_codec_cases` 299、`url_option_cases` 84、`analyze_url_cases` 94）；失败信息里的 `%` 做了转义 |
| `Tests/LegadoNetworkTests/CookieGoldenComparisonTests.swift` | `cookie_cases` 47 条 |
| `Tests/LegadoNetworkTests/ConcurrentRateLimiterTests.swift` | 22 个用例（假时钟，确定性） |
| `Tests/LegadoNetworkTests/HttpUrlGoldenComparisonTests.swift` / `HttpUrlRequestReplayTests.swift` | 170 条 `http_url_cases` 逐条比较；线上 request-target 与 OkHttp 的已知差异逐名钉住 |
| `Tests/LegadoNetworkTests/URLSessionHTTPClientTests.swift` | 真实 `URLSessionHTTPClient` + 内置 `LocalScriptedServer`（`NWListener` 脚本化 HTTP 服务器） |
| `Tests/LegadoNetworkTests/CharsetDetectorGoldenComparisonTests.swift` | **新增**：`charset_cases.json` 逐条比字符集名 + 置信度 + `detectAll` 顺序；`getHtmlEncode` 逐条；解码链 10 种组合 ≥40 条；另含优先级/BOM/HTML meta 三条独立断言。**CI 下 golden 缺失直接 `XCTFail`** |
| `Tests/LegadoNetworkTests/RequestGoldenComparisonTests.swift` | **新增**：用 `LocalScriptedServer` 重放 golden 请求（`request_cases`/`redirect_cases`/`request_cookie_cases`/`auto_header_cases`），比 method / path+query / 有序显式头 / Cookie 头 / body 字节 |
| `Tests/LegadoNetworkTests/RealJsNetworkProviderTests.swift` | 29 个用例；含 `.body` 属性与方法双通道 3 条、限速接线 3 条 |
| `Tests/LegadoNetworkTests/LiveSmokeTests.swift` | 仅 `LEGADO_LIVE_SMOKE=1` 时执行的真实联网冒烟（见下） |
| `Tests/LegadoNetworkPublicAPITests/NetworkPublicAPITests.swift` | 16 个用例（普通 `import`），覆盖 AnalyzeUrl/UrlOption/NetworkUtils/HttpTypes/CookieMerge/限速器公开面 |

### golden（`scripts/golden`）

- **legado 自带 icu4j 源码原样编入**：`src/main/java/legadoicu/` 下 8 个 Java 文件从
  `app/src/main/java/io/legado/app/lib/icu4j/` 逐行复制，只做两处必要改动：
  `package io.legado.app.lib.icu4j;` → `package legadoicu;`，以及删除 Android 专有的
  `ParcelFileDescriptor` 重载（连同 `android.os`/`android.system` import）。
  另加 `src/main/java/androidx/annotation/{NonNull,Nullable}.java` 两个零依赖桩注解，
  让源码零改写即可编译。
- `EncodingDetectGolden.java`（新增）：`utils/EncodingDetect.kt` 的 Java 移植
  （`getHtmlEncode`/`getEncode`/`detectAll`/`removeUTF8Bom`/`decodeBody`/`charsetFromContentType`），
  检测结果直接由 legado 原码产生。
- `CharsetCorpus.java` + `CharsetGen.java`（新增）：构造 **240 份**字节样本并写出
  `charset_cases.json` 的 `charsetResults`。
- `RequestGen.java`（新增）：真实 OkHttp 5.3.2 → 本地 `com.sun.net.httpserver`，
  按 `OkHttpUtils.kt` 的 `get`/`postForm`/`postJson`/`postMultipart`/`addHeaders` 构造请求。
- `UrlRuleGen.java`（6A 新增）：`runCodec`（hutool `RFC3986`/`URLEncoder`/`EncoderUtils.escape`）、
  `runUrlOption`（真实 Gson + legado 定制适配器）、`runAnalyzeUrl`（真实 Rhino 1.8.1）、
  `runCookie`（纯函数手工移植）。
- `Main.java`：挂载 `codecCases`/`urlOptionCases`/`analyzeUrlCases`/`cookieCases` 与
  6B 的 `charsetCases`/`requestCases` 六类分支（只加不改已有分支）。

> **README 已标明**：`UrlRuleGen.java` 里的 AnalyzeUrl 调度逻辑是**手工 Java 移植**；
> 字符集检测则**不是**移植——`goldenicu` 下就是 legado 自己的 icu4j 源码。

#### 字符集语料构成（240 份）

| 分组 | 份数 | 内容 |
|---|---|---|
| `plain-utf8` / `plain-ext-en` | 4 + 若干 | UTF-8 纯 ASCII、中英混排 |
| `plain-gbk` / `plain-ext-cn` | 8 + 若干 | GBK/GB18030/GB2312 中文，含长度梯度 |
| `plain-big5` / `plain-jp` / `plain-kr` | 3 / 5 / 2 | Big5、Shift_JIS、EUC-JP、EUC-KR |
| `plain-latin` | 4 | ISO-8859-1、windows-1252 |
| `plain-utf16` / `plain-utf32` | 7 / 2 | UTF-16 LE/BE（带/不带 BOM）、UTF-32 |
| `plain-other` | 6 | 其它 ASCII 兼容编码 |
| `bom` | 9 | 各编码 BOM 组合 |
| `short` | 23 | 1–10 字节的极短文本 |
| `html-meta` | 20 | 带/不带 `<meta charset>`、`http-equiv` 两种写法 |
| `mixed` | 9 | 中英/中繁/中韩混排 |
| `garbage` / `garbage-length` / `garbage-c1` | 12 / 10 / 6 | 乱码字节、C1 控制区、随机长度 |
| `empty` | 6 | 空数据 / 全空白 |
| `novel-*`（cn/tw/jp/kr/en/utf16/long/latin） | **45** | **合成的小说章节风格文本**，`syntheticNovelChapter=true` 标注 |

每条样本输出 `detectName` / `detectConfidence` / `allMatches` / `htmlEncode`，
以及 10 种解码组合（`decodedDefault`、`decodedExplicitUtf8/Gbk/Big5/Iso88591`、
`decodedContentTypeUtf8/Gbk/Quoted/NoCharset`、`decodedExplicitBeatsHeader`）。

#### 请求对照语料构成（104 条）

| 文件 | 条数 | 内容 |
|---|---|---|
| `request_cases.json` | 43 | GET（含 encodedQuery）、POST form、POST json、multipart、HEAD；每条记录 method / path+query / 有序显式头 / Cookie 头 / body 字节（multipart boundary 归一为 `--BOUNDARY--`） |
| `redirect_cases.json` | 44 | 301/302/303/307/308、跨域重定向、重定向链中途 `Set-Cookie`、`followRedirects=false`、超 20 跳上限（`Too many follow-up requests: 21`） |
| `request_cookie_cases.json` | 13 | Cookie 头注入/合并/清除/多域 |
| `auto_header_cases.json` | 4 | 客户端自动头清单（`host`/`connection`/`accept-encoding`/`user-agent`/`content-length`/`transfer-encoding`/`cookie`） |

### 脚本与文档

- `scripts/verify_functions.py`：新增 `AnalyzeUrl.kt`（59 函数）、`ConcurrentRateLimiter.kt`、
  `CookieStore.kt`、`CookieManager.kt`、`CacheManager.kt`、`EncodingDetect.kt`、`icu4j/*` 的映射与 EXCLUDED
  （不适用项逐条给理由）；`NetworkUtils.kt` 里 6A 已实现的 9 个函数从 EXCLUDED 移除。
  实测 **Kotlin 函数总数 272，「Kotlin 有但 Swift 没处理」清单为空**。
- `scripts/golden/extract_icu4j_tables.py`：从 legado 原码提取检测表生成 `CharsetTables.swift`；
  路径改为相对脚本推导（不再硬编码绝对路径）。
- `reference/kotlin/` 新增 AnalyzeUrl/ConcurrentRateLimiter/CookieStore/CookieManager/CacheManager、
  EncodingDetect、icu4j 参考副本。
- `.github/workflows/test.yml` 增加 `live-smoke` job（`workflow_dispatch` 触发，`continue-on-error`）。

## 与 Kotlin 的已知差异（README 差异表逐条登记）

| # | 主题 | Kotlin | 本移植 | 影响 |
|---|---|---|---|---|
| 1 | `getSubDomain` 的公共后缀 | Android `PublicSuffixDatabase`（完整列表） | 内置常见多段后缀表 + 默认末两段 | 常见书源域名一致；冷门后缀会取末两段 |
| 2 | 4096 cookie 截断 | `cookieMap.keys.random()` 随机删 | 按插入顺序删第一个 | 语义同为「降到 4096 以下」，结果可复现 |
| 3 | 持久化存储 | Room（cookieDao）/ ACache | 协议 + JSON 文件原子写 | 接口一致，落盘格式不同 |
| 4 | `escape` 的遍历单位 | Kotlin `Char`（UTF-16 单元） | 同（emoji → `%ud83d%ude00`） | golden 已对照 |
| 5 | 非 UTF-8 字符集编码 | `String.getBytes(charset)` / `URLEncoder`：不可表示字符 → `?`；多字节里的 ASCII 字节同样 %XX | 同（逐标量 + 全部字节转义） | golden 已对照 |
| 6 | `Long.intValue()` 截断 | 32 位截断 | 同 | golden 已对照 |
| 7 | `{{}}` 取值 | `evalJS(it) ?: ""`，Double%1==0 用 `%.0f` | 同 | golden 已对照 |
| 8 | `@js:` 取值 | `evalJS(...).toString()`（null → `"null"`） | 同 | golden 已对照 |
| 9 | **线上请求行的额外百分号编码** | OkHttp 把 `\|` `{` `}` `^` `` ` `` `[` `]` 与非法 `%`（如 `%zz`）原样写进 request-target | URLSession/CFNetwork 会额外编码成 `%7C` `%7B` `%7D` `%5E` `%60` `%5B` `%5D` 与 `%25zz` | 已逐名钉住（`HttpUrlRequestReplayTests.knownWireEncodingDivergences`）。最小复现：`https://x.com/?a=b\|c` → OkHttp 线上 `GET /?a=b\|c`，本移植 `GET /?a=b%7Cc`；规范化结果（`HttpUrl`）本身与 OkHttp 完全一致 |
| 10 | WebView 分支 | `BackstageWebView`（useWebView=true） | **不支持**：`HTTPRequest.useWebView/webJs/bodyJs` 只记录并由 `URLSessionHTTPClient` 记 diagnostics | 真实书源里 `webView` 分支占比极低；WebView 需 UIKit/WebKit 宿主，SwiftPM 库不做 |
| 11 | `dnsIp` 自定义解析 | OkHttp `Dns` 直连指定 IP | **不支持**：`HTTPRequest.dnsIp` 已落到 `URLSessionHTTPClient` 并写 diagnostics，仍走系统 DNS | URLSession 无公开 API 指定解析 IP；已在 README 写明 |
| 12 | 证书策略 | `SSLHelper` 信任所有证书 | **已实现**：`URLSessionHTTPClient` 的 delegate 接受服务器证书（`URLAuthenticationChallenge` → `.useCredential`） | 与 legado 同等安全取舍，README 明写风险 |
| 13 | `ConcurrentRateLimiter` 的阻塞版本 | `getConcurrentRecordBlocking`/`withLimitBlocking` | 只有 async 版本（不提供阻塞 API） | 调用方改用 `withLimit` |
| 14 | `getSubDomainOrNull`/`getDomain` 等 | 见 Kotlin | `getDomain` 已实现；`getSubDomainOrNull` 未移植（AnalyzeUrl 只用非空版本） | — |

### 6B 追加差异（`RealJsNetworkExtensionsProvider` 面）

| # | 主题 | Kotlin | 本移植 | 处理 |
|---|---|---|---|---|
| 6B-1 | 缓存根目录 | `Context.externalCacheDir` | FileManager Caches + `legado-js-cache`（可注入） | 差异登记；相对路径语义一致（前导 `/`） |
| 6B-2 | 文本解码 | BOM → `UrlOption.charset` → Content-Type charset → `EncodingDetect.getHtmlEncode`（HTML meta → icu4j 检测器 → `"UTF-8"` 兜底） | **逐级一致**：`JsNetTextDecoder` 先 `removeUTF8Bom`，再 explicit、Content-Type，最后 `EncodingDetect.getHtmlEncode`；`getHtmlEncode` 内部同样是 meta → 检测器 → 兜底 | 由 `charset_cases` 的 10 种解码组合逐条对照；唯一差异：不可识别的 charset 名回退到 UTF-8 而不抛异常 |
| 6B-3 | headers 顺序 | JS 对象插入顺序（LinkedHashMap） | JS 面按对象键序送达（`JSJavaBridge` 保序解码），落到 `HTTPRequest.headers` 为有序数组 | 键唯一时不影响 HTTP 语义 |
| 6B-4 | get/post/head Cookie | Jsoup 自建客户端（不带 legado CookieStore） | 经 `URLSessionHTTPClient` 注入 `CookieStore` Cookie | 客户端既有差异的延展，已在 golden `request_cookie_cases` 对照 |
| 6B-5 | get/post/head 限速 | `ConcurrentRateLimiter(getSource()).withLimitBlocking` | **已接线**：provider 持有 `rateLimiter`，`setRateLimiterFromSource(concurrentRate:key:)` 从书源 `concurrentRate` 构造；`jsoupGetOrHead`/`jsoupPost` 全部走 `executeWithRateLimit` | 测试 `testGetHonoursInjectedRateLimiter`（`"1/1000"` 断言 ≥0.9s）与两条对照用例 |
| 6B-6 | StrResponse JS 面 | 属性 + 方法双通道（`.body` / `.body()`） | **双通道已实现**：`__installDualChannel` 同时装属性与同名方法 | `.body` 与 `.body()` 均可直接使用 |
| 6B-7 | `raw()`/`toString()` | okhttp `Response.toString()` | `Response{code=..., message=..., url=...}` 描述串 | 近似 |
| 6B-8 | 失败错误文本 | Java `stackTraceStr` | Swift 错误描述 | 对齐失败分支语义，文本不同 |
| 6B-9 | 客户端自动头 | OkHttp 强制 `host`/`connection`/`accept-encoding: gzip`/`user-agent: okhttp/5.3.2` 等 | URLSession 自动头为 `Accept`/`Accept-Language`/`Accept-Encoding: br, gzip, deflate`/`User-Agent: <CFNetwork>` 等 | 逐项列于 README「URLSession 与 OkHttp 自动头差异」；显式头（书源写的那部分）已在 `request_cases` 逐条对照一致 |
| 6B-10 | 线上 request-target 百分号编码 | 见 6A 差异 #9 | 同 | 已知差异，逐名钉住 |

## 最终验证

### golden（本环境真实运行，与 CI 同一 jar / 同一批用例文件）

| 项 | 值 |
|---|---|
| 用例文件 | **22 个** |
| **用例总数** | **2271 条** |
| 6B 新增 | 字符集 240、请求 43、重定向 44、Cookie 13、自动头 4 |
| 运行时间 | 4.87 s（`EXIT=0`） |
| 日志 | `ci_logs/step6b_final_golden.log`、`ci_logs/step6b_mid_golden.log` |

命令：`cd scripts/golden && mvn -q package -DskipTests && java -jar target/golden-generator.jar cases out`

> **本轮修掉一个会让 CI golden job 卡死的缺陷**：`RequestGen` 的 `com.sun.net.httpserver`
> 默认执行器是非守护线程池，`main` 结束后 JVM 不退出（实测挂起 15 分钟以上，会把 golden job
> 拖到超时）。已把两处 `HttpServer` 改用守护线程池，并在 `Main` 收尾加 `System.exit(0)`；
> 修复后同一批用例 4.87 秒跑完并正常退出。

### 编译与语法验证（本环境实测）

| 检查 | 结果 |
|---|---|
| 全部 `.swift` 文件 `swiftc -parse` 语法解析 | **0 错误**（`Sources/` + `Tests/` 全量，含本轮新增/改动的 9 个文件） |
| 主 library 全量类型检查（Linux + SwiftSoup 2.9.6 本地副本） | 推进到 **160/160 个文件**；残留错误**全部**是 Apple 专属 API 在 Linux 的缺失（`CFNetwork` / `CryptoKit` / `FoundationNetworking` 的 `URLSession` 家族），**与本次改动无关**，CI 只跑 macOS / iOS 不受影响 |
| `python3 scripts/verify_functions.py` | Kotlin 函数总数 272，**「Kotlin 有但 Swift 没处理」清单为空** |
| `python3 scripts/verify_fields.py` | Kotlin 数据字段总数 225，**「Kotlin 有但 Swift 没实现」清单为空** |

本轮从编译验证里**抓到并修掉**的真实缺陷：

1. **`Tests/LegadoNetworkTests/LiveSmokeTests.swift` 无法编译**：文件头注释用了 17 行 `#` 作行首
   （Python/shell 风格），Swift 里 `#` 是非法字符，`swiftc -parse` 直接报
   `expected a macro identifier for a pound literal expression`。已改成 `//`。
   ——若不做这一步，CI 的 macOS 与 iOS 两个 job 都会在编译阶段就失败。
2. **`RequestGoldenComparisonTests` 的 golden 模型会 decode 崩**：golden 里 `bodyKind`(26/43 缺)、
   `requestForm`(36/43 缺)、`exception`(43/44 缺)、`withJar`(10/13 缺) 等键**在部分条目上不存在**，
   Swift 的 `Decodable` 对 `String?` 缺键会抛 `keyNotFound`。已给所有可选字段加
   `decodeIfPresent` 兜底，并把 `load` 改成整段解码（不再逐条 `JSONSerialization` 往返）。
   `withJar` 的缺省值经 golden 核对为 **`false`**（10 条 `cookie-no-jar-*` 用例均无 CookieJar）。
3. **`testGoldenRequestCapture` 缺 `async`**：函数体里有 `await`，原签名是同步 `throws`，编译不过。
   已改为 `async throws`。
4. **`CharsetDetectorGoldenComparisonTests` 同样的缺键问题**：`htmlDecodeError`(237/240 缺)、
   `decodedDefault`(3/240 缺)、`decodedContentTypeQuoted`(3/240 缺) 等 6 个键部分条目不存在，已同样兜底。
5. **`URLSessionHTTPClient.swift` 的多余 `import CFNetwork`**：全文件无任何 CF 符号使用
   （已用 grep 确认），删除后不影响任何平台行为，同时消除了一个无谓的平台耦合。

### CI 状态

三个 job 的**真实远程日志尚未产出**：本交付环境没有 GitHub 凭据、也没有 git 仓库
（`gh auth status` 未登录、`git remote -v` 报 not a git repository），无法 push 触发远程 CI。
本地能做的验证（golden 全量生成、语法/类型检查、字段与函数覆盖）已全部执行并记录在上表；
`ci_logs/step6b_final_macos.log` 与 `ci_logs/step6b_final_ios.log` **未生成**，不做伪造。

CI 配置本身已就绪：`.github/workflows/test.yml` 的 `golden` / `test-macos` /
`test-ios-simulator` 三个 job 结构与 6A 完全一致（6A 实测 run 37142531415 三 job 全绿，
golden 1757 条 / 19 文件，macOS 与 iOS 均 **495** 个测试、脚本打印
`✅ iOS 总数与 macOS 总数一致（均为 495）`）。本轮在 6A 基础上新增 7 个用例文件、
41 个测试方法（字符集 4 + 请求 4 + JS 面 5 + 其他回归），push 后 iOS 与 macOS 仍会按
同一脚本自动核对总数相等。

## 交付说明：README 与代码逐条核对结果

核对方式：README 中提到每一个文件名 / 类名 / 方法名 / 用例文件，都在仓库里实际 grep 一遍。

### ✅ 一致（逐条实测存在）

| README 提到的 | 实际位置 |
|---|---|
| 16 个 Network 源文件（AnalyzeUrl / UrlOption / GsonJSON / HTTPTypes / HttpUrl / ConcurrentRateLimiter / CookieStore / CookieManager / CacheManager / NetworkUtilsEncoding / URLSessionHTTPClient / RealJsNetworkExtensionsProvider / RealAjaxProvider / CharsetDetector / EncodingDetect / CharsetTables） | `Sources/LegadoBookSource/Network/` 全部存在 |
| 11 个测试文件（AnalyzeUrlGoldenComparison / CookieGoldenComparison / ConcurrentRateLimiter / HttpUrlGoldenComparison / HttpUrlRequestReplay / URLSessionHTTPClient / CharsetDetectorGoldenComparison / RequestGoldenComparison / RealJsNetworkProvider / LiveSmoke / NetworkPublicAPITests） | `Tests/` 下全部存在 |
| `CharsetDetector.detectMatch` / `detectAllMatches` | `CharsetDetector.swift` ✓ |
| `EncodingDetect.getHtmlEncode` / `getEncode` | `EncodingDetect.swift` ✓ |
| `AnalyzeUrl.makeRateLimiter` | `AnalyzeUrl.swift` ✓ |
| `JSJavaBridge.__installDualChannel` / `__dualValue` | `JSJavaBridge.swift` ✓ |
| `setRateLimiterFromSource` / `executeWithRateLimit` | `RealJsNetworkExtensionsProvider.swift` ✓ |
| `HttpUrlRequestReplayTests.knownWireEncodingDivergences` | `HttpUrlRequestReplayTests.swift` ✓ |
| golden 用例文件（charset/request/redirect/request_cookie/auto_header） | `scripts/golden/` 生成，条数与 README 表格逐项相等（240/43/44/13/4） |

### ✅ 本轮修正的 README 措辞（原文 → 现文）

| 位置 | 原文 | 现文 |
|---|---|---|
| 6A 差异表 #5 WebView | 「不实现（只记录字段）」+ 处理列「6B/后续」 | 「**不支持**：只记录字段，`URLSessionHTTPClient` 记 diagnostics；WebView 需 UIKit/WebKit 宿主，SwiftPM 库不做」 |
| 6A 差异表 #7 `dnsIp` | 「只落到 HTTPRequest」+「6B 里 URLSession 不支持」 | 「**不支持**：已落到 `HTTPRequest` 并由 `URLSessionHTTPClient` 写 diagnostics，实际仍走系统 DNS」 |
| 6A 差异表 #8 证书策略 | 「6B 实现（…）」 | 「**已实现**：`urlSession(_:didReceive:completionHandler:)` 回 `.useCredential` 接受任意服务器证书」 |
| 6B-2 文本解码 | 「最小链；ICU4J 检测链在 step6-6b-wip 分支 WIP(4)/(5)，尚未并入 main」 | 「**逐级一致**：`JsNetTextDecoder` 完整实现 BOM → explicit → Content-Type → `getHtmlEncode`（meta → 检测器 → 兜底），顺序取自 Kotlin `ResponseBody.text(encode)`」 |
| 6B-5 限速 | 「provider 不携带书源，未接线」 | 「**已接线**：`setRateLimiterFromSource` / `AnalyzeUrl.makeRateLimiter` 从书源 `concurrentRate` 构造，get/post/head 全部走 `executeWithRateLimit`」 |
| 6B-6 `.body` | 「仅同名方法」+「`.body` 请改用 `.body()`」 | 「**双通道已实现**：`.body` 与 `.body()` 均可直接写」 |
| 6B 小节标题 | 「JsExtensions 网络方法 + AjaxProvider 真实实现（追加）」 | 「真实网络 + 字符集检测 + 请求对照」 |
| 第 3 步「后续步骤（TODO）」 | 「第 3 步之后仍未做：…网络、UI」 | 保留历史记录并加注现状（网络已在第 6 步实现） |
| 第 4 步「本步骤明确排除（后续 TODO）」 | 「第 5 步 / 第 6 步 / 第 5/6 步」 | 改为「**第 N 步已实现** / **不做**」并给出差异表编号 |
| 第 6 步 6A 开头 | 「**真实网络在 6B。**」 | 「真实网络实现（`URLSessionHTTPClient`）见 6B 小节」 |

上表中「原文」一列是为了留痕而引用的旧措辞；**正文（`STEP6_HANDOFF.md` 与 `README.md` 的
描述性内容）已不再出现**「6B 待做」「WIP」「step6-6b-wip」「最小链」「6B 尚未开始」等表述
（已对两个文件 grep 确认，仅剩本对照表的引用行）。

### 差异表合并情况

6A 差异表（13 条）与 6B 差异清单（原 8 条）已并入**同一份「与 Kotlin 的已知差异」**叙述，
6B 小节标题改为「6B 差异清单（与上方 6A 差异表合并为同一份「与 Kotlin 的已知差异」）」，
并新增 6B-9（客户端自动头差异）与 6B-10（线上 request-target 编码）两条，
后接新增的「URLSession 与 OkHttp 自动头差异」对照表。两处不再有互相矛盾的表述。

## 可选：live-smoke

`workflow_dispatch` 手动触发的 `live-smoke` job（macOS-14，`continue-on-error: true`）：
对书源 JSON 中的书源用 `AnalyzeUrl` + `URLSessionHTTPClient` 真实请求搜索 URL（关键字「斗罗」），
报告落到 artifact `live-smoke-report`（`live-smoke-out/live_smoke_report.txt` + `live_smoke_test.log`）。
单源失败不 fail CI。

> 触发方式：Actions → Test → Run workflow。测试读取 `Tests/LegadoNetworkTests/Resources/`
> 下的书源样本（仓库里保存的是 `配置文件_7个.json`；README 已说明 `配置文件_14个.json`
> 未随仓库保存，因此以实际随仓保存的那份为输入）。
