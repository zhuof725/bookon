//
//  EncodingDetect.swift
//  LegadoBookSource
//
//  第 6 步 6B：响应编码探测（Kotlin EncodingDetect 的 Swift 移植）。
//
//  对应 Kotlin/Java 位置：
//   - app/src/main/java/io/legado/app/utils/EncodingDetect.kt
//     （getHtmlEncode / getEncode，jsoup 解析 meta 的部分用等价正则替代，见「差异」）
//   - app/src/main/java/io/legado/app/utils/Utf8BomUtils.kt（removeUTF8BOM）
//   - app/src/main/java/io/legado/app/lib/icu4j/CharsetDetector.java（detect）
//
//  调用顺序与 legado 完全一致：
//   removeUTF8BOM → <head> 字节级查找 → meta 标签（charset 属性优先，
//   http-equiv=content-type 的 charset= 次之）→ CharsetDetector.detect 兜底（无匹配 "UTF-8"）。
//
//  差异：Kotlin 用 jsoup parseBodyFragment 解析 head 片段并遍历 DOM meta 节点；
//  这里用等价的「正则提取 <meta> 标签 + 手工属性解析」，对书源实际出现的
//  meta 写法（charset 属性 / http-equiv Content-Type / 大小写 / 引号/无引号值）
//  行为一致；对注释内 <meta>、畸形 HTML 等 jsoup 的容错细节不完全一致。
//

import Foundation

/// 响应编码探测（对应 Kotlin `io.legado.app.utils.EncodingDetect`）。
public enum EncodingDetect {

    /// 头部区域正则（Kotlin `headTagRegex = "(?i)<head>[\\s\\S]*?</head>"`）。
    private static let headTagRegex = try? NSRegularExpression(
        pattern: "<head>[\\s\\S]*?</head>", options: [.caseInsensitive])

    /// meta 标签正则（jsoup `getElementsByTag("meta")` 的等价简化）。
    private static let metaTagRegex = try? NSRegularExpression(
        pattern: "<meta\\b[^>]*>", options: [.caseInsensitive])

    /// 属性名首字符（与 golden 侧 CharsetGen.parseMetaTag 一致）。
    private static func isAttrNameStart(_ c: Character) -> Bool {
        return (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || c == "_" || c == ":"
    }

    /// 属性名其余字符（与 golden 侧 CharsetGen.parseMetaTag 一致）。
    private static func isAttrNameChar(_ c: Character) -> Bool {
        return isAttrNameStart(c) || (c >= "0" && c <= "9") || c == "." || c == "-"
    }

    /// 提取 HTML 首段 `<head>...</head>`（Kotlin `headTagRegex.find(html)?.value`）。
    static func firstHeadMatch(_ html: String) -> String? {
        guard let regex = headTagRegex else { return nil }
        let ns = html as NSString
        let range = regex.rangeOfFirstMatch(in: html, options: [], range: NSRange(location: 0, length: ns.length))
        if range.location == NSNotFound {
            return nil
        }
        return ns.substring(with: range)
    }

    /// 从 HTML 字符串解析 meta 标签链（Kotlin 的 jsoup `getElementsByTag("meta")` 等价物）。
    /// 每个元素为属性字典（属性名小写、首个出现者优先，与 jsoup attr() 行为近似）。
    static func extractMetaTags(_ html: String) -> [[String: String]] {
        guard let regex = metaTagRegex else { return [] }
        let ns = html as NSString
        var tags: [[String: String]] = []
        regex.enumerateMatches(in: html, options: [], range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match = match else { return }
            tags.append(parseMetaTag(ns.substring(with: match.range)))
        }
        return tags
    }

    /// 解析单个 `<meta ...>` 标签（与 golden 侧 CharsetGen.parseMetaTag 算法一致）。
    static func parseMetaTag(_ tag: String) -> [String: String] {
        var attrs: [String: String] = [:]
        var chars = Array(tag)
        var i = 0
        while i < chars.count && chars[i] != ">" {
            let c = chars[i]
            if c.isWhitespace {
                i += 1
            } else if isAttrNameStart(c) {
                let nameStart = i
                while i < chars.count && isAttrNameChar(chars[i]) {
                    i += 1
                }
                let name = String(chars[nameStart..<i]).lowercased()
                while i < chars.count && chars[i].isWhitespace {
                    i += 1
                }
                var value = ""
                if i < chars.count && chars[i] == "=" {
                    i += 1
                    while i < chars.count && chars[i].isWhitespace {
                        i += 1
                    }
                    if i < chars.count && chars[i] == "\"" {
                        i += 1
                        let vStart = i
                        while i < chars.count && chars[i] != "\"" {
                            i += 1
                        }
                        value = String(chars[vStart..<i])
                        if i < chars.count {
                            i += 1
                        }
                    } else if i < chars.count && chars[i] == "'" {
                        i += 1
                        let vStart = i
                        while i < chars.count && chars[i] != "'" {
                            i += 1
                        }
                        value = String(chars[vStart..<i])
                        if i < chars.count {
                            i += 1
                        }
                    } else {
                        let vStart = i
                        while i < chars.count && !chars[i].isWhitespace && chars[i] != ">" {
                            i += 1
                        }
                        value = String(chars[vStart..<i])
                    }
                }
                if attrs[name] == nil {
                    attrs[name] = value
                }
            } else {
                i += 1
            }
        }
        return attrs
    }

    /// 大小写不敏感的 `charset=` 定位（Kotlin `content.indexOf("charset=", ignoreCase = true)`）。
    private static func indexOfIgnoreCase(_ s: String, _ target: String) -> Int? {
        let ns = s as NSString
        let r = ns.range(of: target, options: [.caseInsensitive])
        return r.location == NSNotFound ? nil : r.location
    }

    /// 从 meta 链中取第一个非空字符集名（Kotlin getHtmlEncode 的 meta 扫描段）。
    ///
    /// 对应 Kotlin：`metaTag.attr("charset")` 非空即返回；否则
    /// `http-equiv` 大小写不敏感等于 "content-type" 时，取 `content` 里
    /// `charset=` 之后的部分；无 `charset=` 时取 `;` 之后的部分
    /// （Kotlin `substringAfter(";")` 缺省值 = 整个 content）。
    ///
    /// - Parameter html: 已提取的 head 片段（或全文）。
    /// - Returns: 字符集名字符串；找不到返回 nil。
    public static func getCharsetFromMeta(_ html: String) -> String? {
        guard let head = firstHeadMatch(html) else {
            return nil
        }
        for meta in extractMetaTags(head) {
            if let charsetStr = meta["charset"], !charsetStr.isEmpty {
                return charsetStr
            }
            if let httpEquiv = meta["http-equiv"],
               httpEquiv.compare("content-type", options: [.caseInsensitive]) == .orderedSame {
                if let content = meta["content"] {
                    let cs: String
                    if let idx = indexOfIgnoreCase(content, "charset=") {
                        let start = content.index(content.startIndex, offsetBy: idx + "charset=".count)
                        cs = String(content[start...])
                    } else {
                        // Kotlin substringAfter(";")：找不到分隔符时返回整个字符串
                        if let semi = content.firstIndex(of: ";") {
                            cs = String(content[content.index(after: semi)...])
                        } else {
                            cs = content
                        }
                    }
                    if !cs.isEmpty {
                        return cs
                    }
                }
            }
        }
        return nil
    }

    /// 移除 UTF-8 BOM（对应 Kotlin `Utf8BomUtils.removeUTF8BOM(bytes)`）。
    public static func removeUTF8BOM(_ bytes: [UInt8]) -> [UInt8] {
        if bytes.count > 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF {
            return Array(bytes[3...])
        }
        return bytes
    }

    /// 移除 UTF-8 BOM（对应 Kotlin `Utf8BomUtils.removeUTF8BOM(xmlText)`）。
    public static func removeUTF8BOM(_ string: String) -> String {
        let bytes = Array(string.utf8)
        let stripped = removeUTF8BOM(bytes)
        if stripped.count == bytes.count {
            return string
        }
        if let s = TextDecoder.decode(stripped, charsetName: "UTF-8") {
            return s
        }
        return string
    }

    /// 字节级 indexOf（Kotlin `bytes.indexOf(headOpenBytes)` 语义）。
    private static func indexOf(_ haystack: [UInt8], _ needle: [UInt8], from: Int) -> Int? {
        guard !needle.isEmpty, needle.count <= haystack.count else { return nil }
        for i in max(from, 0)...(haystack.count - needle.count) {
            var matched = true
            for j in 0..<needle.count where haystack[i + j] != needle[j] {
                matched = false
                break
            }
            if matched {
                return i
            }
        }
        return nil
    }

    /// 自动探测字节流的编码（对应 Kotlin `EncodingDetect.getEncode(bytes)`：
    /// `CharsetDetector().setText(bytes).detect()`，无匹配返回 "UTF-8"）。
    public static func getEncode(_ bytes: [UInt8]) -> String {
        return CharsetDetector.detect(bytes)
    }

    /// 响应的 HTML 编码探测（对应 Kotlin `EncodingDetect.getHtmlEncode(bytes)`）。
    ///
    /// 顺序：
    ///   1. 剥 UTF-8 BOM（Kotlin 由调用方 removeUTF8BOM 完成，此处内建——见「差异」）；
    ///   2. 字节级查找 `<head>`/`</head>`，取 head 片段解码为 UTF-8（替换语义）后扫 meta；
    ///   3. 找不到 head 时对全文（UTF-8 替换解码）跑 `(?i)<head>[\s\S]*?</head>` 再扫 meta；
    ///   4. 都失败回退 `getEncode`（检测器，兜底 "UTF-8"）。
    ///
    /// 差异：Kotlin 的 try/catch(Exception) 靠 NPE/越界兜底；Swift 全程安全访问，无需捕获。
    public static func getHtmlEncode(_ bytes: [UInt8]) -> String {
        let stripped = removeUTF8BOM(bytes)
        var head: String?
        let headOpen: [UInt8] = [0x3C, 0x68, 0x65, 0x61, 0x64, 0x3E]   // "<head>"
        let headClose: [UInt8] = [0x3C, 0x2F, 0x68, 0x65, 0x61, 0x64, 0x3E]  // "</head>"
        if let start = indexOf(stripped, headOpen, from: 0),
           let end = indexOf(stripped, headClose, from: start + headOpen.count) {
            let slice = Array(stripped[start..<(end + headClose.count)])
            head = TextDecoder.decode(slice, charsetName: "UTF-8")
        }
        if head == nil {
            let full = TextDecoder.decode(stripped, charsetName: "UTF-8") ?? ""
            head = firstHeadMatch(full)
        }
        if let head = head, let cs = getCharsetFromMeta(head) {
            return cs
        }
        return getEncode(stripped)
    }

    /// 从 Content-Type 头提取 charset 参数（OkHttp `MediaType.charset()` 的等价简化）。
    ///
    /// 对应 Kotlin：`contentType()?.charset()`（OkHttp）。
    /// 差异：OkHttp 用完整 MIME 解析器；这里用正则 `(?i)(?:^|;)\s*charset\s*=\s*"?([^";\s]+)`
    /// 取第一个 charset 参数（参数名大小写不敏感、支持引号）。golden 两侧同一实现。
    static func charsetFromContentTypeHeader(_ header: String?) -> String? {
        guard let header = header, !header.isEmpty else { return nil }
        let ns = header as NSString
        guard let regex = try? NSRegularExpression(
            pattern: "(?:^|;)\\s*charset\\s*=\\s*\"?([^\";\\s]+)", options: [.caseInsensitive]) else {
            return nil
        }
        if let m = regex.firstMatch(in: header, options: [], range: NSRange(location: 0, length: ns.length)) {
            let r = m.range(at: 1)
            if r.location != NSNotFound {
                return ns.substring(with: r)
            }
        }
        return nil
    }
}