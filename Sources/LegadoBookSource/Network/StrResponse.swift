//
//  StrResponse.swift
//  LegadoBookSource
//
//  第 6 步 6B：字符串响应（解码后的 body + 元信息）与响应字节解码链。
//
//  对应 Kotlin/Java 位置：
//   - app/src/main/java/io/legado/app/help/http/StrResponse.kt（结构体形态）
//   - app/src/main/java/io/legado/app/help/http/OkHttpUtils.kt 的
//     `ResponseBody.text(encode: String?)`（decodeText 的解码顺序）
//   - app/src/main/java/io/legado/app/utils/EncodingDetect.kt（getHtmlEncode 兜底）
//
//  解码顺序与 legado 一致：
//   1. 剥 UTF-8 BOM（Utf8BomUtils.removeUTF8BOM，先于一切解码）；
//   2. 显式 charset（调用方指定，如书源规则里的 charset 参数）；
//   3. Content-Type 头里的 charset 参数（OkHttp MediaType.charset() 的等价简化）；
//   4. getHtmlEncode（HTML meta → 检测器，最终兜底 "UTF-8"）。
//
//  差异：legado 在显式/头部 charset 名无法被 Charset.forName 识别时抛异常
//  （UnsupportedCharsetException）；这里回退到下一级探测（TextDecoder 对未知名返回 nil）。
//

import Foundation

/// 字符串响应（对应 Kotlin `io.legado.app.help.http.StrResponse` 的纯数据形态）。
public struct StrResponse {
    /// 解码后的响应体字符串（Kotlin `body`）。
    public let body: String
    /// 请求 URL（Kotlin `url()`）。
    public let url: String
    /// 调用耗时毫秒（Kotlin `callTime`）。
    public let callTime: Int

    public init(body: String, url: String, callTime: Int) {
        self.body = body
        self.url = url
        self.callTime = callTime
    }

    /// 把响应字节解码为字符串（对应 Kotlin `ResponseBody.text(encode)` 的完整链路）。
    ///
    /// - Parameters:
    ///   - bytes: 原始响应字节（未做任何预处理）。
    ///   - explicitCharset: 调用方显式指定的字符集名（对应 Kotlin `text(encode)` 参数）。
    ///   - contentTypeHeader: 响应 `Content-Type` 头原文（如 `text/html; charset=gbk`）。
    /// - Returns: 解码后的字符串（不可解码字节按 Java `new String(bytes, charset)`
    ///   的 U+FFFD 替换语义）。
    public static func decodeText(bytes: [UInt8], explicitCharset: String?,
                                  contentTypeHeader: String?) -> String {
        let stripped = EncodingDetect.removeUTF8BOM(bytes)

        // 1) 显式 charset（legado：`charsetName?.let { return String(bytes, forName(it)) }`）
        if let explicit = explicitCharset {
            if let s = TextDecoder.decode(stripped, charsetName: explicit) {
                return s
            }
            // 差异：legado 对不可识别名抛异常；这里回退（注释见文件头）
        }

        // 2) Content-Type 头 charset（legado：`contentType()?.charset()?.let { ... }`）
        if let headerCs = EncodingDetect.charsetFromContentTypeHeader(contentTypeHeader) {
            if let s = TextDecoder.decode(stripped, charsetName: headerCs) {
                return s
            }
        }

        // 3) HTML meta → 检测器（legado：`EncodingDetect.getHtmlEncode(bytes)`）
        let name = EncodingDetect.getHtmlEncode(stripped)
        if let s = TextDecoder.decode(stripped, charsetName: name) {
            return s
        }

        // 检测器给出的名字不在本地解码表（如 EUC-KR/Shift_JIS 等未移植字符集）时，
        // 按 UTF-8 替换语义兜底（差异：legado 用 Charset.forName 直接解码这些名字）。
        return TextDecoder.decode(stripped, charsetName: "UTF-8") ?? ""
    }
}