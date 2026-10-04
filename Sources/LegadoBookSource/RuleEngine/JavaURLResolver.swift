//
//  JavaURLResolver.swift
//  LegadoBookSource
//
//  实现 java.net.URL 的解析与相对解析（RFC 2396/3986 + java 特例），供 NetworkUtils 使用。
//
//  为什么不用 Foundation URL(string:relativeTo:)：
//   - Swift Foundation 对 `../` 规范化、`//host`、以 `?`/`#` 开头的相对、空相对、
//     含空格/中文/未转义字符的处理与 java.net.URL 不同，会导致与 Kotlin 结果不一致。
//   - 这里按 java.net.URLStreamHandler.parseURL 的核心逻辑移植（http/https handler 继承该逻辑）。
//
//  java.net.URL 相对解析关键点（本实现覆盖）：
//   1. relative 为空串 -> 结果 = base（含 base 的 ref）。
//   2. relative 以 "#" 开头 -> 仅替换 base 的 ref（path/query 保留）。
//   3. relative 含 scheme（如 "http:xxx"）：java 对同协议的 "scheme:相对" 会去掉 scheme 当相对处理
//      （http handler：若 spec 的 scheme == base.scheme，则 start 跳过 scheme，按相对处理）。
//   4. relative 以 "//" 开头 -> 换掉 authority，path=余下。
//   5. relative 以 "/" 开头 -> 绝对路径，保留 base authority。
//   6. 否则 -> 相对路径，基于 base path 的目录拼接，再做 "." / ".." 规范化。
//   7. query：relative 带 "?" 时用 relative 的 query；"?" 开头时保留 base path。
//   8. java **不**对 path 做百分号编码，原样保留空格/中文（与 Foundation 不同）。
//
//  ⚠️ 本实现为「按理解移植」，最终由 C 部分 golden（真实 java.net.URL 至少 60 例）验证；
//     已知可能的边角差异见 README「与 Kotlin 已知差异」表。
//

import Foundation

extension JavaURL {

    /// 解析绝对 URL 字符串。失败返回 nil（对齐 java.net.URL 构造抛 MalformedURLException -> catch）。
    static func parse(_ spec: String) -> JavaURL? {
        let s = spec.trimmingCharacters(in: .whitespaces)
        // 必须有 scheme:  (scheme = ALPHA *( ALPHA / DIGIT / "+" / "-" / "." ))
        guard let colon = firstSchemeColon(s) else { return nil }
        let scheme = String(s[s.startIndex..<colon]).lowercased()
        guard !scheme.isEmpty else { return nil }
        var rest = String(s[s.index(after: colon)...])

        var authority: String? = nil
        if rest.hasPrefix("//") {
            rest.removeFirst(2)
            // authority 到下一个 / ? # 结束
            let authEnd = rest.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" })
            if let e = authEnd {
                authority = String(rest[rest.startIndex..<e])
                rest = String(rest[e...])
            } else {
                authority = rest
                rest = ""
            }
        }
        var ref: String? = nil
        if let h = rest.firstIndex(of: "#") {
            ref = String(rest[rest.index(after: h)...])
            rest = String(rest[rest.startIndex..<h])
        }
        var query: String? = nil
        if let q = rest.firstIndex(of: "?") {
            query = String(rest[rest.index(after: q)...])
            rest = String(rest[rest.startIndex..<q])
        }
        let path = rest
        return JavaURL(scheme: scheme, authority: authority, path: path, query: query, ref: ref)
    }

    /// java.net.URL(base, spec) 的相对解析。
    /// 精确移植 java.net.URLStreamHandler.parseURL（http/https handler 继承该逻辑）：
    ///  - 规范化（/./ 与 /../ 消解、尾部 /.. /. 处理）**仅对「相对路径」生效**（isRelPath=true），
    ///    对「绝对路径 /...」和「协议相对 //...」路径**不规范化**（保留字面 /../、//）。
    ///  - "?query" only：path = base path 截到最后一个 '/' 之前 + "/"（丢掉文件名段）。
    static func resolve(base: JavaURL, relative spec0: String) -> JavaURL? {
        // java 会先 trim spec 两端空白
        var spec = spec0.trimmingCharacters(in: .whitespaces)

        // 1. 若 spec 以 scheme 开头：若与 base 同协议则按相对处理（去 scheme），否则为新绝对 URL。
        if let colon = firstSchemeColon(spec) {
            let specScheme = String(spec[spec.startIndex..<colon]).lowercased()
            if specScheme == base.scheme {
                // 同协议：java http handler 去掉 "scheme:" 继续按相对解析
                spec = String(spec[spec.index(after: colon)...])
            } else {
                // 不同协议：作为独立绝对 URL 解析
                return parse(spec0.trimmingCharacters(in: .whitespaces))
            }
        }

        let scheme = base.scheme
        var authority = base.authority
        var path: String? = base.path
        var query = base.query
        var ref = base.ref

        // 2. 空 spec -> 结果 = base（含 ref）。
        if spec.isEmpty {
            return JavaURL(scheme: scheme, authority: authority, path: path ?? "", query: query, ref: ref)
        }

        // 分离 ref（# 之后）。spec 带 # -> 用 spec 的 ref；不带 # -> 清除 base ref。
        var work = spec
        if let h = work.firstIndex(of: "#") {
            ref = String(work[work.index(after: h)...])
            work = String(work[work.startIndex..<h])
        } else {
            ref = nil
        }

        // 3. work 为空（纯 # 开头）：只换 ref，其余保留。
        if work.isEmpty {
            return JavaURL(scheme: scheme, authority: authority, path: path ?? "", query: query, ref: ref)
        }

        var isRelPath = false

        // 4. "//" 开头 -> 换 authority（此后 path 为绝对，不作相对规范化）。
        if work.hasPrefix("//") {
            var r = String(work.dropFirst(2))
            let e = r.firstIndex(where: { $0 == "/" || $0 == "?" })
            if let e = e {
                authority = String(r[r.startIndex..<e])
                r = String(r[e...])
            } else {
                authority = r
                r = ""
            }
            let (p, q) = splitPathQuery(r)
            path = p.isEmpty ? nil : p
            query = q
            // 不规范化
            return JavaURL(scheme: scheme, authority: authority, path: path ?? "", query: query, ref: ref)
        }

        // 分离 work 的 query
        let (workPath, workQuery) = splitPathQuery(work)

        if !workPath.isEmpty {
            if workPath.hasPrefix("/") {
                // 5. 绝对路径：直接取，不规范化（java isRelPath=false）
                path = workPath
                query = workQuery
            } else {
                // 6. 相对路径：基于 base path 目录拼接，之后规范化
                isRelPath = true
                let basePath = path ?? ""
                if let ind = basePath.lastIndex(of: "/") {
                    // path.substring(0, ind+1) + spec
                    let dir = String(basePath[basePath.startIndex...ind])
                    path = dir + workPath
                } else {
                    // ind == -1：若有 authority，用 "/" 作分隔
                    let separator = (authority != nil) ? "/" : ""
                    path = separator + workPath
                }
                query = workQuery
            }
        } else {
            // workPath 为空（work 全是 query，如 "?new=2"）
            if workQuery != nil, let bp = path {
                // java: "?query" only -> path = base path 截到最后 '/'（不含文件名）+ "/"
                var ind = bp.range(of: "/", options: .backwards)?.lowerBound
                if ind == nil { ind = bp.startIndex }
                let head = String(bp[bp.startIndex..<ind!])
                path = head + "/"
                query = workQuery
            } else {
                query = workQuery
            }
        }

        // 7. 规范化（仅相对路径）：移植 java.net.URLStreamHandler.parseURL 的消解循环。
        if isRelPath, var p = path {
            p = javaNormalizeRelPath(p)
            path = p
        }

        return JavaURL(scheme: scheme, authority: authority, path: path ?? "", query: query, ref: ref)
    }

    /// 精确移植 java.net.URLStreamHandler.parseURL 中 `if (isRelPath) { ... }` 的路径消解。
    /// 注意：对越过根的 "/../" 保留字面（不裁剪），与 RFC remove_dot_segments 不同。
    static func javaNormalizeRelPath(_ input: String) -> String {
        var path = input
        // 移除内嵌 "/./"
        while let r = path.range(of: "/./") {
            path = String(path[path.startIndex..<r.lowerBound]) + String(path[r.lowerBound...].dropFirst(2))
        }
        // 移除内嵌 "/../"（可消解时）
        var searchStart = path.startIndex
        while let r = path.range(of: "/../", range: searchStart..<path.endIndex) {
            let i = r.lowerBound
            // limit = path.lastIndexOf('/', i-1)
            if i > path.startIndex {
                let beforeI = path.index(before: i)
                if let limitRange = path.range(of: "/", options: .backwards, range: path.startIndex..<path.index(after: beforeI)) {
                    let limit = limitRange.lowerBound
                    // path.indexOf("/../", limit) != 0  —— 即从 limit 起的第一个 "/../" 不在字符串最开头
                    let firstFromLimit = path.range(of: "/../", range: limit..<path.endIndex)?.lowerBound
                    if firstFromLimit != path.startIndex {
                        // path = substring(0, limit) + substring(i+3)
                        let head = String(path[path.startIndex..<limit])
                        let tail = String(path[path.index(i, offsetBy: 3)...])
                        path = head + tail
                        searchStart = path.startIndex
                        continue
                    } else {
                        searchStart = path.index(i, offsetBy: 3)
                        continue
                    }
                } else {
                    searchStart = path.index(i, offsetBy: 3)
                    continue
                }
            } else {
                // i == start：无法消解，向后跳
                searchStart = path.index(i, offsetBy: 3)
                continue
            }
        }
        // 移除尾部 "/.."（可消解时）
        while path.hasSuffix("/..") {
            // i = indexOf("/..")（第一个），limit = lastIndexOf('/', i-1)
            if let iRange = path.range(of: "/..") {
                let i = iRange.lowerBound
                if i > path.startIndex {
                    let beforeI = path.index(before: i)
                    if let limitRange = path.range(of: "/", options: .backwards, range: path.startIndex..<path.index(after: beforeI)) {
                        let limit = limitRange.lowerBound
                        path = String(path[path.startIndex...limit])
                    } else {
                        break
                    }
                } else {
                    break
                }
            } else {
                break
            }
        }
        // 移除尾部 "/."
        if path.hasSuffix("/.") {
            path = String(path.dropLast())
        }
        return path
    }

    // MARK: - helpers

    /// 找到合法 scheme 的冒号位置（scheme = ALPHA *( ALPHA / DIGIT / + - . )）。
    private static func firstSchemeColon(_ s: String) -> String.Index? {
        guard let first = s.first, first.isLetter else { return nil }
        var idx = s.index(after: s.startIndex)
        while idx < s.endIndex {
            let c = s[idx]
            if c == ":" { return idx }
            if c.isLetter || c.isNumber || c == "+" || c == "-" || c == "." {
                idx = s.index(after: idx)
            } else {
                return nil
            }
        }
        return nil
    }

    private static func splitPathQuery(_ s: String) -> (String, String?) {
        if let q = s.firstIndex(of: "?") {
            return (String(s[s.startIndex..<q]), String(s[s.index(after: q)...]))
        }
        return (s, nil)
    }

    /// RFC 3986 remove_dot_segments（java.net.URL 对 path 做 "." / ".." 规范化）。
    static func normalizePath(_ p: String) -> String {
        if p.isEmpty { return p }
        let hasLeadingSlash = p.hasPrefix("/")
        // 以 / 切段但保留尾部是否有 /
        let hasTrailingSlash = p.hasSuffix("/")
        let rawSegs = p.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        var out: [String] = []
        for (i, seg) in rawSegs.enumerated() {
            if seg == "." {
                continue
            } else if seg == ".." {
                if !out.isEmpty && out.last != ".." {
                    out.removeLast()
                } else if !hasLeadingSlash {
                    out.append("..")
                }
                // 绝对路径下越过根的 ".." 被丢弃（java 行为）
            } else if seg.isEmpty {
                // 跳过空段（连续 // 或首尾），稍后按 leading/trailing 重建
                if i == 0 && hasLeadingSlash { continue }
                if i == rawSegs.count - 1 { continue }
                continue
            } else {
                out.append(seg)
            }
        }
        var result = out.joined(separator: "/")
        if hasLeadingSlash { result = "/" + result }
        if hasTrailingSlash && !result.hasSuffix("/") {
            // 若以 . 或 .. 结尾被消解，java 仍保留末尾 /
            result += "/"
        }
        if result.isEmpty { result = hasLeadingSlash ? "/" : "" }
        return result
    }
}
