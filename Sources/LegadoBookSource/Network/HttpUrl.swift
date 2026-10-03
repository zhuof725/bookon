//
//  HttpUrl.swift
//  LegadoBookSource
//
//  第 6 步 6B：**OkHttp HttpUrl 的 Swift 复刻**（URL 规范化）。
//
//  为什么必须自己实现：Kotlin 侧 AnalyzeUrl 用 `url.toHttpUrl().newBuilder()...build()`，
//  最终 URL 是 OkHttp `HttpUrl.toString()` 的结果——它会做一系列规范化（scheme/host 小写、
//  IDN→punycode、默认端口剥离、路径 `%xx` 规范化与 `.`/`..` 段解析、查询/片段的字符集编码、
//  非法 URL 抛异常）。Swift 的 `URL(string:)`/`URLComponents` 规则不同，**不能**作为最终 URL。
//
//  对照：`scripts/golden` 的 `HttpUrlGen.java`（真实 OkHttp 5.3.2）生成 170 条用例，
//  `Tests/LegadoNetworkTests/HttpUrlGoldenComparisonTests.swift` 逐条比较（含解析失败样例）。
//
//  与 OkHttp 的差异（README 差异表登记，附最小复现）：见文件末 `KNOWN_DIVERGENCES`。
//

import Foundation

public struct HttpUrl: Equatable {

    public var scheme: String          // 小写 "http" / "https"
    public var username: String        // 已规范化（未解码）
    public var password: String        // 已规范化（未解码）
    public var host: String            // 小写；IPv6 不带方括号；IDN 为 punycode
    public var port: Int               // -1 表示使用默认端口
    public var encodedPath: String     // 以 "/" 开头
    public var query: String?          // 已规范化的查询串（nil = 没有 "?"）
    public var fragment: String?       // 已规范化的片段（nil = 没有 "#"）

    public init(scheme: String, username: String = "", password: String = "", host: String,
                port: Int = -1, encodedPath: String = "/", query: String? = nil, fragment: String? = nil) {
        self.scheme = scheme
        self.username = username
        self.password = password
        self.host = host
        self.port = port
        self.encodedPath = encodedPath
        self.query = query
        self.fragment = fragment
    }

    /// 对应 OkHttp `HttpUrl.toString()`（也是 `url(url)` 之后 `toString()` 的结果）。
    public var urlString: String {
        var out = scheme + "://"
        if !username.isEmpty || !password.isEmpty {
            out += username
            if !password.isEmpty { out += ":" + password }
            out += "@"
        }
        out += host.contains(":") ? "[\(host)]" : host
        if port != -1 { out += ":\(port)" }
        out += encodedPath
        if let query = query { out += "?" + query }
        if let fragment = fragment { out += "#" + fragment }
        return out
    }

    public var defaultPort: Int { scheme == "https" ? 443 : 80 }

    // MARK: - 解析（对应 HttpUrl.Builder.parse）

    /// 解析失败返回 nil（对齐 `"…".toHttpUrlOrNull()` 的 null 结果）。
    public static func parse(_ rawInput: String) -> HttpUrl? {
        // 对齐 OkHttp：解析前 trim（黄金样例 `https://x.com/ ` -> `https://x.com/`）
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        var pos = 0
        let chars = Array(input.utf16)
        func at(_ i: Int) -> UInt16? { i < chars.count ? chars[i] : nil }

        // 1) scheme：必须以 "http:" / "https:"（大小写不敏感）开头
        let scheme: String
        if matches(input, 0, "http:") {
            scheme = "http"; pos = 5
        } else if matches(input, 0, "https:") {
            scheme = "https"; pos = 6
        } else {
            return nil
        }

        // 2) 前导斜杠：OkHttp 会跳过所有 '/'（至少 2 个），如 "https:///x" -> "https://x/"
        var slashCount = 0
        while let c = at(pos), c == 0x2F { slashCount += 1; pos += 1 }
        if slashCount < 2 { return nil }

        // 3) authority = 到第一个 '/', '?', '#' 之前
        let authorityStart = pos
        while let c = at(pos), c != 0x2F, c != 0x3F, c != 0x23 { pos += 1 }
        let authority = HttpUrl.substring(input, authorityStart, pos)

        // 4) path / query / fragment
        var encodedPath = "/"
        var query: String? = nil
        var fragment: String? = nil

        if let c = at(pos), c == 0x2F { // '/'
            let pathStart = pos
            while let c2 = at(pos), c2 != 0x3F, c2 != 0x23 { pos += 1 }
            encodedPath = HttpUrl.canonicalizePath(HttpUrl.substring(input, pathStart, pos))
        }
        if let c = at(pos), c == 0x3F { // '?'
            pos += 1
            let qStart = pos
            while let c2 = at(pos), c2 != 0x23 { pos += 1 }
            query = HttpUrl.canonicalize(HttpUrl.substring(input, qStart, pos), encodeSet: HttpUrl.queryEncodeSet)
        }
        if let c = at(pos), c == 0x23 { // '#'
            pos += 1
            fragment = HttpUrl.canonicalize(HttpUrl.substring(input, pos, chars.count), encodeSet: HttpUrl.fragmentEncodeSet)
        }
        if pos != chars.count { return nil }

        // 5) authority 拆分：userinfo@host:port
        var userinfo = ""
        var hostPort = authority
        if let atIdx = authority.lastIndex(of: "@") {
            userinfo = String(authority[authority.startIndex..<atIdx])
            hostPort = String(authority[authority.index(after: atIdx)...])
        }
        var username = "", password = ""
        if !userinfo.isEmpty {
            if let colon = userinfo.firstIndex(of: ":") {
                username = HttpUrl.canonicalize(String(userinfo[userinfo.startIndex..<colon]), encodeSet: HttpUrl.userinfoEncodeSet)
                password = HttpUrl.canonicalize(String(userinfo[userinfo.index(after: colon)...]), encodeSet: HttpUrl.userinfoEncodeSet)
            } else {
                username = HttpUrl.canonicalize(userinfo, encodeSet: HttpUrl.userinfoEncodeSet)
            }
        }

        var host = ""
        var port = -1
        if hostPort.hasPrefix("[") {
            guard let close = hostPort.firstIndex(of: "]") else { return nil }
            let inner = String(hostPort[hostPort.index(after: hostPort.startIndex)..<close])
            guard let h = HttpUrl.canonicalizeIPv6(inner) else { return nil }
            host = h
            let rest = String(hostPort[hostPort.index(after: close)...])
            if !rest.isEmpty {
                guard rest.hasPrefix(":") else { return nil }
                guard let p = HttpUrl.parsePort(String(rest.dropFirst())) else { return nil }
                port = p
            }
        } else {
            // 主机:端口 —— 端口是最后一个 ':' 之后全为数字的部分
            if let colon = hostPort.lastIndex(of: ":") {
                let portPart = String(hostPort[hostPort.index(after: colon)...])
                let hostPart = String(hostPort[hostPort.startIndex..<colon])
                if !portPart.isEmpty && portPart.allSatisfy({ $0.isASCII && $0.isNumber }) {
                    guard let p = HttpUrl.parsePort(portPart) else { return nil }
                    port = p
                    hostPort = hostPart
                } else {
                    // 端口部分不是纯数字（含空端口 "host:"、负数、字母）-> OkHttp 判非法
                    return nil
                }
            }
            // 非 bracket 的 host 里不允许出现 ':'（IPv6 必须写方括号）
            if hostPort.contains(":") { return nil }
            guard let h = HttpUrl.canonicalizeHost(hostPort) else { return nil }
            host = h
        }
        if host.isEmpty { return nil }
        if port == (scheme == "https" ? 443 : 80) { port = -1 }

        return HttpUrl(scheme: scheme, username: username, password: password, host: host,
                       port: port, encodedPath: encodedPath, query: query, fragment: fragment)
    }

    // MARK: - 组成部分的规范化

    /// OkHttp `parsePort`：只接受 1..65535 的数字。
    static func parsePort(_ s: String) -> Int? {
        if s.isEmpty { return nil }
        guard s.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        guard let v = Int(s), v > 0, v <= 65535 else { return nil }
        return v
    }

    /// OkHttp `canonicalizeHost`：百分号解码 → 小写 → IDN(punycode)；含 '.' 的 IPv4 形式保持不变。
    static func canonicalizeHost(_ input: String) -> String? {
        var host = input
        if host.contains("%") {
            guard let d = percentDecode(host) else { return nil }
            host = d
        }
        host = host.lowercased()
        if host.isEmpty { return nil }
        // host 里出现空格、控制字符或 URL 保留字符 -> 非法（对齐 OkHttp canonicalizeHost 的行为）
        for scalar in host.unicodeScalars {
            if scalar.value <= 0x20 || scalar.value == 0x7F { return nil }
            switch scalar.value {
            case 0x3C, 0x3E, 0x22, 0x5E, 0x60, 0x7B, 0x7D, 0x7C, 0x5C, 0x2F, 0x3F, 0x23, 0x40:
                return nil
            default: break
            }
        }
        // IPv4 字面量（OkHttp 只做校验形式的保留，不做数值归一化）
        if isIPv4Literal(host) { return host }
        if host.unicodeScalars.contains(where: { $0.value > 0x7F }) {
            guard let ascii = idnToASCII(host) else { return nil }
            return ascii.lowercased()
        }
        // 主机名里不允许出现 OkHttp 的非法字符（空格等）
        for scalar in host.unicodeScalars where scalar.value <= 0x20 || scalar.value == 0x7F {
            return nil
        }
        return host
    }

    /// IPv6 字面量的规范化：小写，压缩写法保持（OkHttp 只做小写与简单校验）。
    static func canonicalizeIPv6(_ input: String) -> String? {
        let lower = input.lowercased()
        if lower.isEmpty { return nil }
        let allowed = CharacterSet(charactersIn: "0123456789abcdef:.")
        guard lower.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        guard lower.contains(":") else { return nil }
        return lower
    }

    /// 路径规范化：先做 `%xx` 的规范化编码，再去掉 `.` / `..` 段。
    static func canonicalizePath(_ raw: String) -> String {
        let encoded = canonicalize(raw, encodeSet: pathEncodeSet, backslashIsSlash: true)
        return removeDotSegments(encoded)
    }

    /// OkHttp `resolvePath` 的等价实现（`.` / `..` 段的解析）。
    static func removeDotSegments(_ path: String) -> String {
        var out: [String] = []
        let segments = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        for (i, rawSeg) in segments.enumerated() {
            let isLast = (i == segments.count - 1)
            // OkHttp 把 %2E 也当作 '.'（大小写不敏感）
            let seg = rawSeg.caseInsensitiveCompare("%2e") == .orderedSame ? "." : rawSeg
            let seg2 = rawSeg.caseInsensitiveCompare("%2e%2e") == .orderedSame ? ".." : seg
            if seg2 == "." {
                if isLast { out.append("") }   // "/a/." -> "/a/"
                continue
            } else if seg2 == ".." {
                if out.count > 0 { out.removeLast() }
                if isLast { out.append("") }   // "/a/b/.." -> "/a/"
                continue
            } else if isLast && seg2.isEmpty {
                out.append("")                 // 尾随空段（路径以 / 结尾）
                continue
            } else {
                out.append(rawSeg)
            }
        }
        var result = out.joined(separator: "/")
        if !result.hasPrefix("/") { result = "/" + result }
        if result.isEmpty { result = "/" }
        return result
    }

    // MARK: - 字符集与编码

    /// 查询串需要编码的字符（OkHttp QUERY_ENCODE_SET）。
    static let queryEncodeSet: Set<UInt16> = setOf(" \"'<>#")
    /// 片段需要编码的字符（OkHttp FRAGMENT_ENCODE_SET）。
    static let fragmentEncodeSet: Set<UInt16> = setOf(" \"<>#")
    /// 路径段需要编码的字符（OkHttp PATH_SEGMENT_ENCODE_SET 的最小可用子集）。
    static let pathEncodeSet: Set<UInt16> = setOf(" \"<>^`{}|\\")
    /// userinfo 需要编码的字符。
    static let userinfoEncodeSet: Set<UInt16> = setOf(" \"'<>#@:[]{}\\^`|/?")

    private static func setOf(_ s: String) -> Set<UInt16> {
        var out = Set<UInt16>()
        for u in s.utf16 { out.insert(u) }
        return out
    }

    /// OkHttp `canonicalize`：保留已有的合法 `%xx`（大小写原样），其余按 encodeSet 转义。
    static func canonicalize(_ input: String, encodeSet: Set<UInt16>, backslashIsSlash: Bool = false) -> String {
        var out = ""
        // 控制字符（< 0x20、0x7F）直接丢弃（对齐 OkHttp canonicalize 的 skip 分支）；
        // 非 ASCII 按「标量」处理（emoji 是代理对，按 UTF-16 单元会丢字符）。
        for scalar in input.unicodeScalars {
            if scalar.value < 0x20 || scalar.value == 0x7F { continue }
            if backslashIsSlash && scalar.value == 0x5C {
                out += "/"
                continue
            }
            if scalar.value == 0x25 { // '%'
                out += "%"
                continue
            }
            if scalar.value < 0x80 {
                let c = UInt16(scalar.value)
                if encodeSet.contains(c) {
                    out += String(format: "%%%02X", c)
                } else {
                    out.unicodeScalars.append(scalar)
                }
                continue
            }
            for b in String(scalar).utf8 { out += String(format: "%%%02X", b) }
        }
        return out
    }

    /// 旧的逐 UTF-16 单元实现（保留作对照，未被使用）。
    static func canonicalizeUnits(_ input: String, encodeSet: Set<UInt16>) -> String {
        var out = ""
        let units = Array(input.utf16)
        var i = 0
        while i < units.count {
            let c = units[i]
            if c == 0x25 { // '%'
                // 对齐 OkHttp：非法的 % 转义**原样保留**（不重编码成 %25），只做控制字符与字符集处理
                out += "%"
                i += 1
                continue
            }
            if c < 0x80 {
                if encodeSet.contains(c) {
                    out += String(format: "%%%02X", c)
                } else {
                    out += String(decoding: [c] as [UInt16], as: UTF16.self)
                }
                i += 1
                continue
            }
            // 非 ASCII：按 UTF-8 逐字节 %XX
            if let scalar = UnicodeScalar(UInt32(c)) {
                for b in String(scalar).utf8 { out += String(format: "%%%02X", b) }
            }
            i += 1
        }
        return out
    }

    static func isHex(_ c: UInt16) -> Bool {
        return (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x46) || (c >= 0x61 && c <= 0x66)
    }

    /// 百分号解码（UTF-8）；非法转义返回 nil（对齐 OkHttp 的 strict 行为）。
    static func percentDecode(_ s: String) -> String? {
        let units = Array(s.utf16)
        var bytes: [UInt8] = []
        var i = 0
        while i < units.count {
            let c = units[i]
            if c == 0x25 {
                guard i + 2 < units.count, isHex(units[i + 1]), isHex(units[i + 2]) else { return nil }
                let hi = Int(hexValue(units[i + 1])), lo = Int(hexValue(units[i + 2]))
                bytes.append(UInt8(hi << 4 | lo))
                i += 3
                continue
            }
            if c < 0x80 { bytes.append(UInt8(c)) } else if let sc = UnicodeScalar(UInt32(c)) {
                bytes.append(contentsOf: String(sc).utf8)
            }
            i += 1
        }
        return String(data: Data(bytes), encoding: .utf8) ?? String(decoding: bytes, as: UTF8.self)
    }

    static func hexValue(_ c: UInt16) -> UInt16 {
        if c >= 0x30 && c <= 0x39 { return c - 0x30 }
        if c >= 0x41 && c <= 0x46 { return c - 0x41 + 10 }
        return c - 0x61 + 10
    }

    static func substring(_ s: String, _ start: Int, _ end: Int) -> String {
        let units = Array(s.utf16)
        let a = max(0, min(start, units.count)), b = max(a, min(end, units.count))
        return String(decoding: units[a..<b], as: UTF16.self)
    }

    static func matches(_ s: String, _ offset: Int, _ needle: String) -> Bool {
        let units = Array(s.utf16), n = Array(needle.utf16)
        guard offset >= 0, offset + n.count <= units.count else { return false }
        for (i, v) in n.enumerated() {
            let c = units[offset + i]
            // ASCII 大小写不敏感
            let a = (c >= 0x41 && c <= 0x5A) ? c + 32 : c
            let b = (v >= 0x41 && v <= 0x5A) ? v + 32 : v
            if a != b { return false }
        }
        return true
    }

    static func isIPv4Literal(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { p in !p.isEmpty && p.count <= 3 && p.allSatisfy { $0.isASCII && $0.isNumber } }
    }

    // MARK: - IDN（punycode，RFC 3492 编码部分）

    /// 对应 `java.net.IDN.toASCII`（只做「有非 ASCII 标签」时的 punycode 编码）。
    static func idnToASCII(_ host: String) -> String? {
        var out: [String] = []
        for label in host.split(separator: ".", omittingEmptySubsequences: false).map(String.init) {
            if label.isEmpty { out.append(""); continue }
            if label.unicodeScalars.allSatisfy({ $0.value < 0x80 }) {
                out.append(label.lowercased())
                continue
            }
            var basic = ""
            var allPoints: [UInt32] = []
            for scalar in label.lowercased().unicodeScalars {
                if scalar.value < 0x80 { basic.append(Character(scalar)) }
                allPoints.append(scalar.value)
            }
            // RFC 3492：编码循环遍历**完整**码点序列（基本码点参与 delta 计数），h 从基本码点数 b 开始
            let encoded = punycodeEncode(allPoints)
            // 有基本码点时，基本部分与编码部分之间用 "-" 分隔（如 bücher -> bcher-kva）
            out.append("xn--" + basic + (basic.isEmpty ? "" : "-") + encoded)
        }
        return out.joined(separator: ".")
    }

    /// RFC 3492 §6.3 编码（规范实现；输入是标签的**全部**码点，基本码点由调用方拼在 "xn--" 之后）。
    static func punycodeEncode(_ input: [UInt32]) -> String {
        let base: UInt32 = 36, tmin: UInt32 = 1, tmax: UInt32 = 26, skew: UInt32 = 38
        let damp: UInt32 = 700, initialBias: UInt32 = 72, initialN: UInt32 = 128
        var output = ""
        var n = initialN
        var delta: UInt32 = 0
        var bias = initialBias

        func adapt(_ delta: UInt32, _ numPoints: UInt32, _ firstTime: Bool) -> UInt32 {
            var d = firstTime ? delta / damp : delta >> 1
            d &+= d / numPoints
            var k: UInt32 = 0
            while d > ((base - tmin) &* tmax) / 2 {
                d /= (base - tmin)
                k &+= base
            }
            return k &+ (base - tmin &+ 1) &* d / (d + skew)
        }
        func digit(_ d: UInt32) -> String {
            if d < 26 { return String(UnicodeScalar(97 &+ d) ?? "a") }
            return String(UnicodeScalar(22 &+ d) ?? "0")
        }

        let basicCount = input.filter { $0 < initialN }.count
        var h = basicCount
        while h < input.count {
            guard let m = input.filter({ $0 >= n }).min() else { break }
            delta = delta &+ (m &- n) &* UInt32(h + 1)
            n = m
            for cp in input {
                if cp < n {
                    delta = delta &+ 1
                } else if cp == n {
                    var q = delta
                    var k = base
                    while true {
                        let t: UInt32 = k <= bias ? tmin : (k >= bias &+ tmax ? tmax : k &- bias)
                        if q < t { break }
                        output += digit(t &+ (q &- t) % (base &- t))
                        q = (q &- t) / (base &- t)
                        k = k &+ base
                    }
                    output += digit(q)
                    bias = adapt(delta, UInt32(h + 1), h == basicCount)
                    delta = 0
                    h &+= 1
                }
            }
            delta = delta &+ 1
            n = n &+ 1
        }
        return output
    }
}
