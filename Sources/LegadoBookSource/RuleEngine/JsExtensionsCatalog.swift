//
//  JsExtensionsCatalog.swift
//  LegadoBookSource
//
//  JsExtensions.kt 的全部方法名清单（正则自动提取，共 67 个）。
//  本步骤**不实现**这些方法体；JS 引擎用 Proxy 包裹 `java` 对象，调用这些未实现方法时
//  抛出明确 JS 错误「java.xxx 尚未实现（JsExtensions，第 5 步）」并记 diagnostics，
//  不静默返回 undefined。第 5 步按本清单逐个实现。
//
//  注意：其中 ['ajax', 'get', 'getSource', 'getTag', 'put'] 由 AnalyzeRule 自身实现（见 selfImplemented），
//  这些会在 `java` 对象上提供真实实现，不被 Proxy 拦截。
//

import Foundation

enum JsExtensionsCatalog {
    /// JsExtensions.kt 声明的全部方法名（第 5 步实现范围）。
    static let allMethodNames: Set<String> = [
        "ajax",
        "ajaxAll",
        "ajaxTestAll",
        "androidId",
        "base64Decode",
        "base64DecodeToByteArray",
        "base64Encode",
        "bytesToStr",
        "cacheFile",
        "connect",
        "deleteFile",
        "downloadFile",
        "encodeURI",
        "get",
        "get7zByteArrayContent",
        "get7zStringContent",
        "getCookie",
        "getFile",
        "getRarByteArrayContent",
        "getRarStringContent",
        "getReadBookConfig",
        "getReadBookConfigMap",
        "getSource",
        "getTag",
        "getThemeConfig",
        "getThemeConfigMap",
        "getThemeMode",
        "getTxtInFolder",
        "getVerificationCode",
        "getWebViewUA",
        "getZipByteArrayContent",
        "getZipStringContent",
        "head",
        "hexDecodeToByteArray",
        "hexDecodeToString",
        "hexEncodeToString",
        "htmlFormat",
        "importScript",
        "log",
        "logType",
        "longToast",
        "openUrl",
        "openVideoPlayer",
        "post",
        "queryBase64TTF",
        "queryTTF",
        "randomUUID",
        "readFile",
        "readTxtFile",
        "replaceFont",
        "s2t",
        "startBrowser",
        "startBrowserAwait",
        "strToBytes",
        "t2s",
        "timeFormat",
        "timeFormatUTC",
        "toNumChapter",
        "toURL",
        "toast",
        "un7zFile",
        "unArchiveFile",
        "unrarFile",
        "unzipFile",
        "webView",
        "webViewGetOverrideUrl",
        "webViewGetSource"
    ]

    /// 其中由 AnalyzeRule 自身实现、本步骤即在 `java` 对象上提供的方法。
    static let selfImplemented: Set<String> = [
        "ajax", "get", "getSource", "getTag", "put"
    ]

    /// 本步骤未实现、调用即抛错的方法（= allMethodNames - selfImplemented）。
    static var unimplemented: Set<String> { allMethodNames.subtracting(selfImplemented) }
}
