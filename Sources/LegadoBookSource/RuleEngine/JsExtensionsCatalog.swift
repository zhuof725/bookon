//
//  JsExtensionsCatalog.swift
//  LegadoBookSource
//
//  JsExtensions.kt + 其父接口 JsEncodeUtils.kt 的全部方法名清单（正则自动提取，共 94 个）。
//  Step 5 实现一批纯算法方法；未实现方法由 JS Proxy 拦截，调用即抛明确 JS 错误
//  「java.xxx 尚未实现（JsExtensions 未实现）」并记 diagnostics，不静默返回 undefined。
//
//  注意：
//  - ['ajax', 'get', 'getSource', 'getTag', 'put'] 由 AnalyzeRule 自身实现（selfImplemented）。
//  - step5Implemented 为 Step 5 已提供真实实现的 JsExtensions 纯算法方法
//    （见 JsExtensionsCore.swift）。
//  - UI/系统类（toast/browser/webView 等）与网络/文件类（get/post/head 等）分别由
//    JsUIProvider / JsNetworkExtensionsProvider 协议注入，默认抛 RuleEngineError.unsupported。
//

import Foundation

enum JsExtensionsCatalog {
    /// JsExtensions.kt 声明的全部方法名。
    static let jsExtensionsMethodNames: Set<String> = [
        "ajax", "ajaxAll", "ajaxTestAll", "androidId", "base64Decode",
        "base64DecodeToByteArray", "base64Encode", "bytesToStr", "cacheFile", "connect",
        "deleteFile", "downloadFile", "encodeURI", "get", "get7zByteArrayContent",
        "get7zStringContent", "getCookie", "getFile", "getRarByteArrayContent",
        "getRarStringContent", "getReadBookConfig", "getReadBookConfigMap", "getSource",
        "getTag", "getThemeConfig", "getThemeConfigMap", "getThemeMode", "getTxtInFolder",
        "getVerificationCode", "getWebViewUA", "getZipByteArrayContent", "getZipStringContent",
        "head", "hexDecodeToByteArray", "hexDecodeToString", "hexEncodeToString", "htmlFormat",
        "importScript", "log", "logType", "longToast", "openUrl", "openVideoPlayer", "post",
        "queryBase64TTF", "queryTTF", "randomUUID", "readFile", "readTxtFile", "replaceFont",
        "s2t", "startBrowser", "startBrowserAwait", "strToBytes", "t2s", "timeFormat",
        "timeFormatUTC", "toNumChapter", "toURL", "toast", "un7zFile", "unArchiveFile",
        "unrarFile", "unzipFile", "webView", "webViewGetOverrideUrl", "webViewGetSource"
    ]

    /// JsEncodeUtils.kt（JsExtensions 的父接口）声明的全部方法名。
    static let jsEncodeUtilsMethodNames: Set<String> = [
        "HMacBase64", "HMacHex", "aesBase64DecodeToByteArray", "aesBase64DecodeToString",
        "aesDecodeArgsBase64Str", "aesDecodeToByteArray", "aesDecodeToString",
        "aesEncodeArgsBase64Str", "aesEncodeToBase64ByteArray", "aesEncodeToBase64String",
        "aesEncodeToByteArray", "aesEncodeToString", "createAsymmetricCrypto", "createSign",
        "createSymmetricCrypto", "desBase64DecodeToString", "desDecodeToString",
        "desEncodeToBase64String", "desEncodeToString", "digestBase64Str", "digestHex",
        "md5Encode", "md5Encode16", "tripleDESDecodeArgsBase64Str", "tripleDESDecodeStr",
        "tripleDESEncodeArgsBase64Str", "tripleDESEncodeBase64Str"
    ]

    /// JsExtensions + JsEncodeUtils 并集（Proxy 需要覆盖全部，未实现也不能漏）。
    static var allMethodNames: Set<String> {
        jsExtensionsMethodNames.union(jsEncodeUtilsMethodNames)
    }

    /// 其中由 AnalyzeRule 自身实现、本步骤即在 `java` 对象上提供的方法。
    static let selfImplemented: Set<String> = [
        "ajax", "get", "getSource", "getTag", "put"
    ]

    /// Step 5 已实现真实方法体的 JsExtensions/JsEncodeUtils 方法（纯算法，见 JsExtensionsCore）。
    static let step5Implemented: Set<String> = [
        "md5Encode", "md5Encode16",
        "t2s", "s2t",
        "timeFormat", "timeFormatUTC",
        "base64Encode", "base64Decode", "base64DecodeToByteArray",
        "hexDecodeToString", "hexEncodeToString", "hexDecodeToByteArray",
        "htmlFormat", "encodeURI", "randomUUID", "toNumChapter",
        "strToBytes", "bytesToStr"
    ]

    /// 通过依赖注入提供的方法（Step 5：UI/系统 与 网络/文件）。
    static let providerImplemented: Set<String> = [
        // JsUIProvider
        "toast", "longToast", "openUrl", "startBrowser", "startBrowserAwait",
        "getVerificationCode", "webView",
        // JsNetworkExtensionsProvider
        "get", "post", "head", "ajaxAll", "connect", "cacheFile", "downloadFile",
        // AnalyzeRule 自有（evalJS 内直接提供）
        "log", "getSource", "getTag", "ajax", "put", "get"
    ]

    /// 本步骤可被调用的方法 = 自有 + 纯算法 + provider；其余保持 Proxy 抛错。
    static var implemented: Set<String> {
        selfImplemented.union(step5Implemented).union(providerImplemented)
    }

    /// 未处理（Proxy 抛错）方法 = 全集 - implemented。
    static var unimplemented: Set<String> { allMethodNames.subtracting(implemented) }
}