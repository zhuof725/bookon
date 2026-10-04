//
//  EncodingDetect.swift
//  LegadoBookSource
//
//  第 6 步 6B：legado `io.legado.app.utils.EncodingDetect`（EncodingDetect.kt）的 Swift 移植。
//
//  对应 Kotlin：app/src/main/java/io/legado/app/utils/EncodingDetect.kt
//   - getHtmlEncode(bytes)：HTML `<head>` 中的 `<meta>`（先 charset 属性，再 http-equiv=content-type
//     的 content），全部未命中或异常则回退 getEncode(bytes)；
//   - getEncode(bytes)：CharsetDetector().setText(bytes).detect()?.name ?: "UTF-8"；
//   - getEncode(filePath)/getEncode(file)：只取文件前若干「负字节」（多字节字符首字节），上限 8000。
//
//  该类型是响应解码链的第 4/5 级，被 `JsNetTextDecoder.decode` 调用（见
//  RealJsNetworkExtensionsProvider.swift）。调用顺序与 Kotlin `ResponseBody.text(encode)` 完全一致：
//    BOM 剥离 → 显式 charset（UrlOption.charset）→ Content-Type charset → getHtmlEncode。
//

import Foundation
#if canImport(SwiftSoup)
import SwiftSoup
#endif

/// legado `EncodingDetect` 的 Swift 等价物。
public enum EncodingDetect {

    /// Kotlin `headTagRegex = "(?i)<head>[\\s\\S]*?</head>"`。
    private static let headOpenBytes: [UInt8] = Array("<head>".utf8)
    private static let headCloseBytes: [UInt8] = Array("</head>".utf8)

    /// 对应 Kotlin `EncodingDetect.getHtmlEncode(bytes)`。
    ///
    /// 判定顺序（与 Kotlin 逐行一致）：
    /// 1. 在字节流里找 `<head>`（大小写敏感的字面量，与 Kotlin 的 `headOpenBytes` 一致）；
    /// 2. 找到则截取到 `</head>`（含）为止的字节段，按 UTF-8 解码成字符串；
    /// 3. 找不到 `<head>` 字面量时，用不区分大小写的正则 `<head>[\s\S]*?</head>` 在整段文本中查找；
    /// 4. 用 SwiftSoup 的 `parseBodyFragment` 解析该片段，遍历全部 `<meta>`：
    ///    - 优先取 `charset` 属性（非空即返回）；
    ///    - 否则当 `http-equiv` 等于 "content-type"（忽略大小写）时，从 `content` 中取
    ///      `charset=` 之后的内容；无 `charset=` 则取 `substringAfter(";")`；
    /// 5. 全部未命中或抛异常 → `getEncode(bytes)`。
    public static func getHtmlEncode(_ bytes: [UInt8]) -> String {
        do {
            var head: String? = nil
            let startIndex = indexOf(bytes, headOpenBytes, from: 0)
            if startIndex > -1 {
                let endIndex = indexOf(bytes, headCloseBytes, from: startIndex)
                if endIndex > -1 {
                    let to = endIndex + headCloseBytes.count
                    head = String(decoding: bytes[startIndex..<to], as: UTF8.self)
                }
            }

            var fragment: String
            if let h = head {
                fragment = h
            } else if let range = fullText(bytes).range(of: headTagPattern,
                                                     options: [.regularExpression, .caseInsensitive]) {
                fragment = String(fullText(bytes)[range])
            } else {
                // Kotlin 里 `headTagRegex.find(String(bytes))!!.value` 会抛 NPE 被 catch 吞掉，
                // 最终回退到检测器；这里显式等价处理。
                return getEncode(bytes)
            }

            let metaTags = try parseMetaTags(fragment)
            for meta in metaTags {
                let charsetStr = meta.charset
                if !charsetStr.isEmpty { return charsetStr }
                if meta.httpEquiv.caseInsensitiveCompare("content-type") == .orderedSame {
                    let content = meta.content
                    let idx = indexOfIgnoreCase(content, "charset=")
                    var value: String
                    if idx > -1 {
                        value = String(content[content.index(content.startIndex,
                                                              offsetBy: idx + "charset=".count)...])
                    } else if let semi = content.firstIndex(of: ";") {
                        value = String(content[content.index(after: semi)...])
                    } else {
                        value = content
                    }
                    if !value.isEmpty { return value }
                }
            }
        } catch {
            // 与 Kotlin 的 catch (ignored: Exception) 一致：静默回退到检测器
        }
        return getEncode(bytes)
    }

    /// 对应 Kotlin `EncodingDetect.getEncode(bytes)`：
    /// `CharsetDetector().setText(bytes).detect()?.name ?: "UTF-8"`。
    public static func getEncode(_ bytes: [UInt8]) -> String {
        CharsetDetector.detectMatch(bytes)?.name ?? "UTF-8"
    }

    /// 对应 Kotlin `EncodingDetect.getEncode(file)`：只收负字节（多字节字符首字节），上限 8000。
    public static func getEncode(file: URL) -> String {
        guard let temp = readFileSignificantBytes(file) else { return "UTF-8" }
        if temp.isEmpty { return "UTF-8" }
        return getEncode(temp)
    }

    /// 对应 Kotlin `EncodingDetect.getEncode(filePath)`。
    public static func getEncode(filePath: String) -> String {
        getEncode(file: URL(fileURLWithPath: filePath))
    }

    // MARK: - 内部

    /// Kotlin `headTagRegex`（不区分大小写）。
    private static let headTagPattern = "<head>[\\s\\S]*?</head>"

    private static func fullText(_ bytes: [UInt8]) -> String {
        // Kotlin `String(bytes)` 用平台默认字符集（Android 为 UTF-8）；
        // 这里按 UTF-8 替换语义解码，与 Kotlin 在 Android 上的行为一致。
        String(decoding: bytes, as: UTF8.self)
    }

    /// 用 SwiftSoup 解析 `<meta>` 列表（对应 Jsoup `parseBodyFragment` + `getElementsByTag("meta")`）。
    private static func parseMetaTags(_ fragment: String) throws -> [(charset: String, httpEquiv: String, content: String)] {
        #if canImport(SwiftSoup)
        let doc = try SwiftSoup.parseBodyFragment(fragment)
        let metas = try doc.getElementsByTag("meta")
        var out: [(String, String, String)] = []
        for m in metas {
            // Jsoup `attr("x")` 在不存在的属性上返回空串；SwiftSoup 的 attr 亦返回空串。
            let charset = (try? m.attr("charset")) ?? ""
            let httpEquiv = (try? m.attr("http-equiv")) ?? ""
            let content = (try? m.attr("content")) ?? ""
            out.append((charset, httpEquiv, content))
        }
        return out
        #else
        // 无 SwiftSoup 时退化为极简解析（只覆盖 <meta ...> 的属性扫描），保证行为可用。
        return simpleMetaScan(fragment)
        #endif
    }

    /// 不依赖 SwiftSoup 的 `<meta>` 属性扫描（仅作 canImport(SwiftSoup) 为假时的兜底）。
    private static func simpleMetaScan(_ fragment: String) -> [(charset: String, httpEquiv: String, content: String)] {
        var out: [(String, String, String)] = []
        let lower = fragment.lowercased()
        var searchStart = lower.startIndex
        while let metaStart = lower.range(of: "<meta", range: searchStart..<lower.endIndex) {
            guard let tagEnd = lower.range(of: ">", range: metaStart.upperBound..<lower.endIndex) else { break }
            let tag = String(fragment[metaStart.lowerBound..<tagEnd.upperBound])
            out.append((attr(tag, "charset"), attr(tag, "http-equiv"), attr(tag, "content")))
            searchStart = tagEnd.upperBound
        }
        return out
    }

    /// 从单个标签文本里取属性值（支持双引号/单引号/无引号）。
    private static func attr(_ tag: String, _ name: String) -> String {
        let pattern = "(?i)" + NSRegularExpression.escapedPattern(for: name)
            + "\\s*=\\s*(\"([^\"]*)\"|'([^']*)'|([^\\s\"'>]+))"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return "" }
        let ns = tag as NSString
        guard let m = re.firstMatch(in: tag, range: NSRange(location: 0, length: ns.length)) else { return "" }
        for group in 2...4 where m.range(at: group).location != NSNotFound {
            return ns.substring(with: m.range(at: group))
        }
        return ""
    }

    /// Kotlin `ByteArray.indexOf(bytes)`（从 from 起找首个完全匹配）。
    static func indexOf(_ haystack: [UInt8], _ needle: [UInt8], from: Int) -> Int {
        if needle.isEmpty { return max(from, 0) }
        var i = max(from, 0)
        while i + needle.count <= haystack.count {
            var j = 0
            while j < needle.count && haystack[i + j] == needle[j] { j += 1 }
            if j == needle.count { return i }
            i += 1
        }
        return -1
    }

    /// 大小写不敏感的子串查找（返回起始 offset，找不到为 -1）。对应 Kotlin `indexOf(s, ignoreCase=true)`。
    static func indexOfIgnoreCase(_ haystack: String, _ needle: String) -> Int {
        guard let r = haystack.range(of: needle, options: [.caseInsensitive]) else { return -1 }
        return haystack.distance(from: haystack.startIndex, to: r.lowerBound)
    }

    /// Kotlin `getFileBytes(file)`：逐字节读，只保留负字节（≥0x80 即多字节字符首字节），最多 8000 个。
    private static func readFileSignificantBytes(_ file: URL) -> [UInt8]? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        var out: [UInt8] = []
        out.reserveCapacity(8000)
        let chunkSize = 4096
        while out.count < 8000 {
            let data: Data
            do { data = try handle.read(upToCount: chunkSize) ?? Data() } catch { break }
            if data.isEmpty { break }
            for b in data {
                if b >= 0x80 { // Kotlin `byteArray[pos] < 0`（有符号视角的负字节）
                    out.append(b)
                    if out.count >= 8000 { break }
                }
            }
        }
        return out
    }
}
