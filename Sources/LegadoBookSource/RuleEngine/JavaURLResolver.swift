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

        var scheme = base.scheme
        var authority = base.authority
        var path = base.path
        var query = base.query
        var ref = base.ref

        // 2. 空 spec -> 结果 = base（含 ref）。java 规定空 spec 保留一切（含 ref）。
        if spec.isEmpty {
            return JavaURL(scheme: scheme, authority: authority, path: path, query: query, ref: ref)
        }

        // 分离 ref（# 之后）
        var work = spec
        if let h = work.firstIndex(of: "#") {
            ref = String(work[work.index(after: h)...])
            work = String(work[work.startIndex..<h])
        } else {
            // spec 不带 #：java 清除 base 的 ref（除非是纯 # 开头，上面已处理）
            ref = nil
        }

        // 3. 纯 # 开头（work 为空而 spec 非空且以 # 开头）：只换 ref，其余保留。
        if work.isEmpty {
            if spec.hasPrefix("#") {
                return JavaURL(scheme: scheme, authority: authority, path: path, query: query, ref: ref)
            }
            // work 为空但非 # 开头（极少见）
            return JavaURL(scheme: scheme, authority: authority, path: path, query: query, ref: ref)
        }

        // 4. "//" 开头 -> 换 authority
        if work.hasPrefix("//") {
            var r = String(work.dropFirst(2))
            // authority 到 / ? 结束（# 已剥离）
            let e = r.firstIndex(where: { $0 == "/" || $0 == "?" })
            if let e = e {
                authority = String(r[r.startIndex..<e])
                r = String(r[e...])
            } else {
                authority = r
                r = ""
            }
            // 解析 r 的 path?query
            (path, query) = splitPathQuery(r)
            path = normalizePath(path)
            return JavaURL(scheme: scheme, authority: authority, path: path, query: query, ref: ref)
        }

        // 5. "?" 开头 -> 保留 base path，换 query
        if work.hasPrefix("?") {
            query = String(work.dropFirst())
            return JavaURL(scheme: scheme, authority: authority, path: path, query: query, ref: ref)
        }

        // 6. "/" 开头 -> 绝对路径
        if work.hasPrefix("/") {
            let (p, q) = splitPathQuery(work)
            path = normalizePath(p)
            query = q
            return JavaURL(scheme: scheme, authority: authority, path: path, query: query, ref: ref)
        }

        // 7. 相对路径：基于 base path 的目录。
        let (relPath, relQuery) = splitPathQuery(work)
        // base 目录 = base.path 最后一个 "/" 之前（含 "/"）
        let basePath = path
        var dir: String
        if let lastSlash = basePath.lastIndex(of: "/") {
            dir = String(basePath[basePath.startIndex...lastSlash])
        } else {
            dir = "/"
        }
        if !dir.hasPrefix("/") { dir = "/" + dir }
        let merged = dir + relPath
        path = normalizePath(merged)
        query = relQuery
        scheme = base.scheme
        return JavaURL(scheme: scheme, authority: authority, path: path, query: query, ref: ref)
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
