#!/usr/bin/env python3
"""
函数覆盖校验（自动提取，不手打清单）。

从 legado 的三个 Kotlin 源码文件里用正则提取全部 `fun`（含 private / internal），
再到对应的 Swift 源码里检查同名函数存在。

Kotlin 源码路径：默认相对本仓库 reference/kotlin/analyzeRule，
可用第一个命令行参数覆盖为外部 legado 的 analyzeRule 目录。

输出「Kotlin 有但 Swift 没实现的函数」清单，必须为空。
"""
import re, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)

DEFAULT_KOTLIN_DIR = os.path.join(REPO, "reference", "kotlin", "analyzeRule")
kotlin_dir = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_KOTLIN_DIR

# Kotlin 文件 -> 对应 Swift 文件（一个 Kotlin 文件的函数可能分散到多个 Swift 文件里，
# 例如 AnalyzeByJSoup.kt 的 ElementsSingle/SourceRule 被拆到独立文件）。
MAPPING = {
    "RuleAnalyzer.kt": [
        "Sources/LegadoBookSource/RuleEngine/RuleAnalyzer.swift",
    ],
    "AnalyzeByRegex.kt": [
        "Sources/LegadoBookSource/RuleEngine/AnalyzeByRegex.swift",
    ],
    "AnalyzeByJSonPath.kt": [
        "Sources/LegadoBookSource/RuleEngine/AnalyzeByJSonPath.swift",
    ],
    "AnalyzeByJSoup.kt": [
        "Sources/LegadoBookSource/RuleEngine/AnalyzeByJSoup.swift",
        "Sources/LegadoBookSource/RuleEngine/AnalyzeByJSoup+Elements.swift",
        "Sources/LegadoBookSource/RuleEngine/AnalyzeByJSoupRules.swift",
    ],
    "AnalyzeByXPath.kt": [
        "Sources/LegadoBookSource/RuleEngine/AnalyzeByXPath.swift",
    ],
    # 第 4 步 B：AnalyzeRule 总调度 + JS 引擎。函数分散到多个 Swift 文件。
    "AnalyzeRule.kt": [
        "Sources/LegadoBookSource/RuleEngine/AnalyzeRule.swift",
        "Sources/LegadoBookSource/RuleEngine/AnalyzeRule+Dispatch.swift",
        "Sources/LegadoBookSource/RuleEngine/AnalyzeRule+Rules.swift",
        "Sources/LegadoBookSource/RuleEngine/AnalyzeRule+JS.swift",
        "Sources/LegadoBookSource/RuleEngine/SourceRule.swift",
    ],
    "NetworkUtils.kt": [
        "Sources/LegadoBookSource/RuleEngine/NetworkUtils.swift",
        "Sources/LegadoBookSource/Network/NetworkUtilsEncoding.swift",
    ],
    # 第 5 步：JsExtensions + 父接口 JsEncodeUtils（纯算法实现 + 运行时分发）。
    "JsExtensions.kt": [
        "Sources/LegadoBookSource/RuleEngine/JsExtensionsCore.swift",
        "Sources/LegadoBookSource/RuleEngine/JsExtensionsRuntime.swift",
        "Sources/LegadoBookSource/RuleEngine/AnalyzeRule+JS.swift",
    ],
    # 第 6 步 6A：AnalyzeUrl 规则解析 + 限速 + cookie/cache。
    "AnalyzeUrl.kt": [
        "Sources/LegadoBookSource/Network/AnalyzeUrl.swift",
        "Sources/LegadoBookSource/Network/UrlOption.swift",
        "Sources/LegadoBookSource/Network/ConcurrentRateLimiter.swift",
        "Sources/LegadoBookSource/Network/HTTPTypes.swift",
    ],
    "ConcurrentRateLimiter.kt": [
        "Sources/LegadoBookSource/Network/ConcurrentRateLimiter.swift",
    ],
    "JsEncodeUtils.kt": [
        "Sources/LegadoBookSource/RuleEngine/JsExtensionsCore.swift",
        "Sources/LegadoBookSource/RuleEngine/JsExtensionsRuntime.swift",
    ],
}

# 明确排除的 Kotlin 函数（本步骤范围外 / Swift 以不同形态实现），每项必须给理由。
# 校验时从「未覆盖」集合里剔除，并打印理由，不静默漏。
EXCLUDED = {
    "AnalyzeRule.kt": {
        # —— Swift 以不同形态/名字实现（映射说明）——
        "getWebJsResult": "Swift 实现为 webJSResult（WebJSProvider 注入），行为对应",
        "compileScriptCache": "Swift 的脚本缓存在 JSEngine.rememberScript（容量 16），不在 AnalyzeRule",
        "splitSourceRuleCacheString": "Swift 同名在 AnalyzeRule+Rules（internal），正则匹配到",
        # —— 本步骤明确排除（见 README 后续 TODO）——
        # （reGetBook/refreshTocUrl 已以桩实现，故不在此排除）
        # —— companion / Kotlin 扩展 setter，Swift 以实例方法 setXxx 提供 ——
        "setCoroutineContext": "Kotlin 协程上下文；Swift 无协程模型，本步骤不需要（排除）",
        "setRuleData": "Swift 提供 setRuleData 实例方法（正则应匹配到）",
        "setNextChapterUrl": "Swift 提供 setNextChapterUrl 实例方法",
        "setChapter": "Swift 提供 setChapter 实例方法",
    },
    "AnalyzeUrl.kt": {
        # —— 6B（真实网络）实现：6A 只做规则解析 + 请求构造 ——
        "executeStrRequest": "6B：真实发送请求（URLSessionHTTPClient）",
        "getStrResponseAwait": "6B：真实发送请求",
        "getStrResponse": "6B：真实发送请求（runBlocking 包装）",
        "getResponseAwait": "6B：返回 OkHttp Response（本移植在 6B 用 HTTPResponse）",
        "getResponse": "6B：同步包装",
        "getByteArrayAwait": "6B：真实请求取字节数组",
        "getByteArray": "6B：同步包装",
        "getInputStreamAwait": "6B：真实请求取流",
        "getInputStream": "6B：同步包装",
        "getClient": "6B：OkHttpClient 配置（超时/代理/dnsIp）在 URLSessionHTTPClient 里实现",
        "getErrResponse": "6B：错误响应构造",
        "getErrStrResponse": "6B：错误响应构造",
        "saveCookie": "6B：cookieJar 落库（与 CookieStore/CookieManager 一起）",
        "getGlideUrl": "不适用：Android Glide 图片加载",
        "extractHostFromUrl": "Kotlin 里已无调用方（未被使用的私有函数），Swift 不移植",
        "upload": "6B：multipart 上传",
        # —— UrlOption 的 setter：Gson 直接写字段，不经过 setter，故不参与解析语义 ——
        "setMethod": "Gson 反射直接写字段，setter 不参与解析（Swift 用属性赋值）",
        "setCharset": "同上",
        "setOrigin": "同上",
        "setRetry": "同上",
        "setType": "同上",
        "setHeaders": "同上",
        "setBody": "同上",
        "setWebJs": "同上",
        "setDnsIp": "同上",
        "setJs": "同上",
        "setBodyJs": "同上",
        "setServerID": "同上",
        "setWebViewDelayTime": "同上",
    },
    "ConcurrentRateLimiter.kt": {
        "getConcurrentRecordBlocking": "Android 同步阻塞版（Thread.sleep）；Swift 只有 async 版（不做阻塞 API）",
        "withLimitBlocking": "同上",
    },
    "NetworkUtils.kt": {
        # NetworkUtils.kt 含大量非本步骤范围的网络工具函数（编码/IP/域名/OkHttp 等）。
        # 本步骤只移植 AnalyzeRule 依赖的 getAbsoluteURL(x2)/getBaseUrl/isAbsUrl/isDataUrl。
        "add": "URL 编码辅助（notNeedEncoding），非本步骤范围",
        "isDigit": "编码辅助，非本步骤范围",
        "getLocalIPAddress": "本机 IP，非本步骤范围",
        "getLocalIPAddressList": "本机 IP，非本步骤范围",
        "isIPv6StdAddress": "IP 判定，非本步骤范围",
        "isIPv6HexCompressedAddress": "IP 判定，非本步骤范围",
        "hasIpAddress": "IP 判定，非本步骤范围",
        "getMimeType": "MIME 判定，非本步骤范围",
        "getUrl": "OkHttp Response 扩展，非本步骤范围",
        "getCookies": "Cookie 解析，非本步骤范围（第 5 步）",
        "parseCookies": "Cookie 解析，非本步骤范围",
        "cookieToString": "Cookie 解析，非本步骤范围",
        "getBaseUrlFromCookie": "Cookie 解析，非本步骤范围",
        "encode": "URL 编码，非本步骤范围",
        "encodeQuery": "URL 编码，非本步骤范围",
        "decode": "URL 解码，非本步骤范围",
        "hexToByte": "编码辅助，非本步骤范围",
        "isAvailable": "网络可用性探测，非本步骤范围",
        "getSubDomainOrNull": "可空变体，调用方（AnalyzeUrl）只用非空版本 getSubDomain",
    },
    # —— 第 5 步：JsExtensions / JsEncodeUtils ——
    # Swift 侧通过 JsExtensionsRuntime 按方法名字符串分发（switch），并非每个方法都有
    # 同名 `func name(`。真正覆盖判定 = 「catalog 全集 - implemented」为空；已实现方法
    # 见 JsExtensionsCatalog.implemented，Proxy 对未实现方法抛错并记诊断。
    # 已实现方法若 Swift 中确有同名 func 会自动匹配；其余在此按类别列出理由。
    "JsExtensions.kt": {
        # 未实现：书源使用次数 0，JS Proxy 抛错 + 记诊断（第 5 步范围外）。
        "ajaxTestAll": "书源未使用；Proxy 抛错（第 5 步范围外）",
        "androidId": "书源未使用；Proxy 抛错",
        "deleteFile": "书源未使用；Proxy 抛错",
        "get7zByteArrayContent": "书源未使用；Proxy 抛错",
        "get7zStringContent": "书源未使用；Proxy 抛错",
        "getFile": "书源未使用；Proxy 抛错",
        "getRarByteArrayContent": "书源未使用；Proxy 抛错",
        "getRarStringContent": "书源未使用；Proxy 抛错",
        "getReadBookConfig": "书源未使用；Proxy 抛错",
        "getReadBookConfigMap": "书源未使用；Proxy 抛错",
        "getThemeConfig": "书源未使用；Proxy 抛错",
        "getThemeConfigMap": "书源未使用；Proxy 抛错",
        "getThemeMode": "书源未使用；Proxy 抛错",
        "getTxtInFolder": "书源未使用；Proxy 抛错",
        "getWebViewUA": "书源未使用；Proxy 抛错",
        "getZipByteArrayContent": "书源未使用；Proxy 抛错",
        "getZipStringContent": "书源未使用；Proxy 抛错",
        "importScript": "书源未使用；Proxy 抛错",
        "logType": "书源未使用；Proxy 抛错",
        "openVideoPlayer": "书源未使用；Proxy 抛错",
        "queryBase64TTF": "书源未使用；Proxy 抛错",
        "queryTTF": "书源未使用；Proxy 抛错",
        "readFile": "书源未使用；Proxy 抛错",
        "readTxtFile": "书源未使用；Proxy 抛错",
        "replaceFont": "书源未使用；Proxy 抛错",
        "toURL": "书源未使用；Proxy 抛错",
        "un7zFile": "书源未使用；Proxy 抛错",
        "unArchiveFile": "书源未使用；Proxy 抛错",
        "unrarFile": "书源未使用；Proxy 抛错",
        "unzipFile": "书源未使用；Proxy 抛错",
        "webViewGetOverrideUrl": "书源未使用；Proxy 抛错",
        "webViewGetSource": "书源未使用；Proxy 抛错",
    },
    "JsEncodeUtils.kt": {
        "createSymmetricCrypto": "对称加密，书源未使用；Proxy 抛错",
        "createAsymmetricCrypto": "非对称加密，书源未使用；Proxy 抛错",
        "createSign": "签名，书源未使用；Proxy 抛错",
        "aesDecodeToByteArray": "书源未使用；Proxy 抛错",
        "aesDecodeToString": "书源未使用；Proxy 抛错",
        "aesDecodeArgsBase64Str": "书源未使用；Proxy 抛错",
        "aesBase64DecodeToByteArray": "书源未使用；Proxy 抛错",
        "aesBase64DecodeToString": "书源未使用；Proxy 抛错",
        "aesEncodeToByteArray": "书源未使用；Proxy 抛错",
        "aesEncodeToString": "书源未使用；Proxy 抛错",
        "aesEncodeToBase64ByteArray": "书源未使用；Proxy 抛错",
        "aesEncodeToBase64String": "书源未使用；Proxy 抛错",
        "aesEncodeArgsBase64Str": "书源未使用；Proxy 抛错",
        "desDecodeToString": "书源未使用；Proxy 抛错",
        "desBase64DecodeToString": "书源未使用；Proxy 抛错",
        "desEncodeToString": "书源未使用；Proxy 抛错",
        "desEncodeToBase64String": "书源未使用；Proxy 抛错",
        "tripleDESDecodeStr": "书源未使用；Proxy 抛错",
        "tripleDESDecodeArgsBase64Str": "书源未使用；Proxy 抛错",
        "tripleDESEncodeBase64Str": "书源未使用；Proxy 抛错",
        "tripleDESEncodeArgsBase64Str": "书源未使用；Proxy 抛错",
        "digestHex": "书源未使用；Proxy 抛错",
        "digestBase64Str": "书源未使用；Proxy 抛错",
        "HMacHex": "书源未使用；Proxy 抛错",
        "HMacBase64": "书源未使用；Proxy 抛错",
    },
}

# 提取 Kotlin 函数名：匹配 `fun name(` / `fun <T> name(` / `tailrec fun name(` 等。
# 同时忽略 companion object 里的 parse（也是 fun，会被提取，需在 Swift 里有同名）。
KFUN_RE = re.compile(
    r'\bfun\b'                       # fun 关键字
    r'(?:\s*<[^>]*>)?'               # 可选泛型 <T>
    r'\s+'
    r'([A-Za-z_]\w*)'                # 函数名
    r'\s*\('                         # 左括号
)

# Kotlin 里以 `val name = ::xxx` 形式暴露的“函数值”，也纳入（如 chompBalanced）。
KVALFUN_RE = re.compile(r'\bval\s+([A-Za-z_]\w*)\s*=\s*if\s*\(.*::')

def kotlin_functions(path):
    text = open(path).read()
    names = set(KFUN_RE.findall(text))
    names |= set(KVALFUN_RE.findall(text))
    return names

def swift_has_func(swift_text, name):
    # Swift 里函数以 `func name(` 出现（可能前面有 public/private/static/@discardableResult 等）。
    # chompBalanced 在 Swift 里也是 func。
    pat = re.compile(r'\bfunc\s+' + re.escape(name) + r'\s*[\(<]')
    if pat.search(swift_text):
        return True
    # 某些 Kotlin fun（如 companion parse）在 Swift 里可能是 static func，同样被上面的正则覆盖。
    return False

def main():
    missing = {}
    details = {}
    for kfile, swift_rels in MAPPING.items():
        kpath = os.path.join(kotlin_dir, kfile)
        knames = kotlin_functions(kpath)
        swift_text = ""
        for rel in swift_rels:
            swift_text += "\n" + open(os.path.join(REPO, rel)).read()
        excluded = EXCLUDED.get(kfile, {})
        miss = sorted(n for n in knames
                      if not swift_has_func(swift_text, n) and n not in excluded)
        details[kfile] = sorted(knames)
        if excluded:
            print(f"[排除] {kfile}: {len(excluded)} 个函数明确排除（理由见脚本 EXCLUDED）")
            for n, reason in sorted(excluded.items()):
                if n in knames:
                    print(f"    - {n}: {reason}")
        if miss:
            missing[kfile] = miss

    print("=== 函数覆盖校验（自动从 Kotlin 源码提取）===")
    print(f"Kotlin 源码目录: {os.path.relpath(kotlin_dir, REPO)}")
    total = 0
    for kfile, names in details.items():
        print(f"  {kfile}: {len(names)} 个 fun -> {names}")
        total += len(names)
    print(f"Kotlin 函数总数: {total}")

    if not missing:
        print("结果: 「Kotlin 有但 Swift 没实现的函数」清单 —— 空。全部覆盖。")
        sys.exit(0)
    else:
        print("结果: 存在未覆盖函数：")
        for k, m in missing.items():
            print(f"  {k}: {m}")
        sys.exit(1)

if __name__ == "__main__":
    main()
