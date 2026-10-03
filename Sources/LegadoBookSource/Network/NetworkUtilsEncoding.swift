//
//  NetworkUtilsEncoding.swift
//  LegadoBookSource
//
//  第 6 步 6A：NetworkUtils.kt 里 AnalyzeUrl 依赖的编码判定与域名工具（第 4 步只移植了
//  getAbsoluteURL/getBaseUrl/isAbsUrl/isDataUrl）。
//
//  对应 Kotlin（utils/NetworkUtils.kt）：
//   - encodedQuery(str) / encodedForm(str)：逐 UTF-16 单元判定「是否仍是合法已编码串」
//   - isDigit16Char(c)
//   - getSubDomain(url)（含 isIPAddress / PublicSuffixDatabase.getEffectiveTldPlusOne）
//
//  ⚠️ 已知差异（登记 README）：PublicSuffixDatabase 是 Android 平台库，本移植用
//  「内置常见多段后缀表 + 默认取末两段」的简化实现，未覆盖全部公共后缀
//  （差异只在域名归属判断上，真实书源常见域名一致；最小复现见 README 差异表）。
//

import Foundation

public extension NetworkUtils {

    // MARK: - 是否已是合法编码串（no-op 编码器判定）

    /// Kotlin `notNeedEncodingQuery`：a-z A-Z 0-9 + "!$&()*+,-./:;=?@[\]^_`{|}~"
    private static let querySafe: Set<UInt16> = {
        var s = Set<UInt16>()
        for c in Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".unicodeScalars) {
            s.insert(UInt16(c.value))
        }
        for c in Array("!$&()*+,-./:;=?@[\\]^_`{|}~".unicodeScalars) {
            s.insert(UInt16(c.value))
        }
        return s
    }()

    /// Kotlin `notNeedEncodingForm`：a-z A-Z 0-9 + "*-._"
    private static let formSafe: Set<UInt16> = {
        var s = Set<UInt16>()
        for c in Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".unicodeScalars) {
            s.insert(UInt16(c.value))
        }
        for c in Array("*-._".unicodeScalars) {
            s.insert(UInt16(c.value))
        }
        return s
    }()

    /// 判断 c 是否是 16 进制字符（Kotlin isDigit16Char）。
    static func isDigit16Char(_ c: UInt16) -> Bool {
        return (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x46) || (c >= 0x61 && c <= 0x66)
    }

    /// 对应 Kotlin `NetworkUtils.encodedQuery(str)`：true 表示整串无需再编码。
    static func encodedQuery(_ str: String) -> Bool {
        return isAlreadyEncoded(str, safe: querySafe)
    }

    /// 对应 Kotlin `NetworkUtils.encodedForm(str)`：true 表示整串无需再编码。
    static func encodedForm(_ str: String) -> Bool {
        return isAlreadyEncoded(str, safe: formSafe)
    }

    /// 逐 UTF-16 单元扫描（Kotlin 的 String[i] 就是 UTF-16 单元）：
    /// 安全字符跳过；'%' 且后面还剩 >2 个单元且紧随两个 16 进制字符时跳过 %XX；
    /// 其余情况判定为「需要编码」。
    private static func isAlreadyEncoded(_ str: String, safe: Set<UInt16>) -> Bool {
        let units = Array(str.utf16)
        var i = 0
        while i < units.count {
            let c = units[i]
            if safe.contains(c) {
                i += 1
                continue
            }
            if c == 0x25 && i + 2 < units.count { // '%'
                let c1 = units[i + 1]
                let c2 = units[i + 2]
                if isDigit16Char(c1) && isDigit16Char(c2) {
                    i += 3
                    continue
                }
            }
            return false
        }
        return true
    }

    // MARK: - 域名

    /// 对应 Kotlin `NetworkUtils.getSubDomain(url)`：cookie 归属用的「有效域名」。
    /// 失败时返回传入的 url（Kotlin `getOrDefault(baseUrl)` 的语义是返回 baseUrl，
    /// 但 baseUrl 为 null 时直接返回原 url）。
    static func getSubDomain(_ url: String) -> String {
        guard let baseUrl = getBaseUrl(url) else { return url }
        guard let host = hostOf(baseUrl) else { return baseUrl }
        if isIPAddress(host) { return host }
        return effectiveTldPlusOne(host) ?? host
    }

    /// 对应 Kotlin `NetworkUtils.getDomain(url)`：只取 host。
    static func getDomain(_ url: String) -> String {
        guard let baseUrl = getBaseUrl(url) else { return url }
        return hostOf(baseUrl) ?? baseUrl
    }

    /// java.net.URL(baseUrl).host 的等价物（小写化；Kotlin URL.getHost 不保留大小写）。
    static func hostOf(_ baseUrl: String) -> String? {
        // baseUrl 形如 scheme://authority[...]，getBaseUrl 已去掉 path
        guard let schemeRange = baseUrl.range(of: "://") else { return nil }
        var rest = String(baseUrl[schemeRange.upperBound...])
        // 去 userinfo
        if let at = rest.lastIndex(of: "@") {
            rest = String(rest[rest.index(after: at)...])
        }
        var host = rest
        if let colon = host.lastIndex(of: ":") {
            // IPv6 字面量 [::1]:port 的情况由中括号保护
            if !host.contains("[") {
                host = String(host[host.startIndex..<colon])
            }
        }
        host = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return host.isEmpty ? nil : host.lowercased()
    }

    /// 对应 hutool `Validator.isIpv4` + Kotlin 的前置检查（首字符 1-9、恰好 3 个点）。
    static func isIPv4Address(_ input: String?) -> Bool {
        guard let input = input, !input.isEmpty else { return false }
        let chars = Array(input)
        guard let first = chars.first, first >= "1", first <= "9" else { return false }
        guard chars.filter({ $0 == "." }).count == 3 else { return false }
        let parts = input.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        for p in parts {
            guard p.count >= 1, p.count <= 3 else { return false }
            guard p.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
            guard let v = Int(p), v >= 0, v <= 255 else { return false }
            if p.count > 1 && p.first == "0" { return false } // 不允许前导 0（hutool isIpv4 行为）
        }
        return true
    }

    /// 对应 hutool `Validator.isIpv6` 的简化实现：
    /// 含 ':' 且只由 16 进制字符、':' 和 '.'（IPv4 映射写法）组成。
    /// ⚠️ 差异：不校验分组数量/压缩写法，README 差异表有登记。
    static func isIPv6Address(_ input: String?) -> Bool {
        guard let input = input, input.contains(":") else { return false }
        let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF:.")
        return input.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// 对应 Kotlin `isIPAddress`。
    static func isIPAddress(_ input: String?) -> Bool {
        return isIPv4Address(input) || isIPv6Address(input)
    }

    /// 常见多段公共后缀（简化表；Android PublicSuffixDatabase 的完整列表未移植）。
    private static let multiLabelSuffixes: Set<String> = [
        "co.uk", "org.uk", "ac.uk", "gov.uk", "me.uk", "net.uk", "sch.uk",
        "com.cn", "net.cn", "org.cn", "gov.cn", "edu.cn", "ac.cn",
        "com.tw", "org.tw", "net.tw", "edu.tw", "gov.tw", "idv.tw",
        "co.jp", "or.jp", "ne.jp", "ac.jp", "go.jp",
        "com.hk", "org.hk", "net.hk", "edu.hk", "gov.hk",
        "com.au", "net.au", "org.au", "edu.au", "gov.au",
        "co.kr", "or.kr", "ne.kr", "re.kr", "pe.kr",
        "com.sg", "com.my", "com.br", "com.mx", "com.ar", "com.tr",
        "co.in", "co.nz", "co.za", "co.il", "co.id", "co.th",
        "com.ru", "com.ua", "com.pl", "com.es", "com.it", "com.fr", "com.de",
        "s3.amazonaws.com"
    ]

    /// 对应 Android `PublicSuffixDatabase.getEffectiveTldPlusOne(host)` 的简化版：
    /// 命中内置多段后缀表时取「后缀 + 前一段」，否则取末两段；单段主机名（如 localhost）返回自身。
    static func effectiveTldPlusOne(_ host: String) -> String? {
        let labels = host.split(separator: ".").map(String.init)
        guard !labels.isEmpty else { return nil }
        if labels.count == 1 { return labels[0] }
        for n in stride(from: min(4, labels.count - 1), through: 1, by: -1) {
            let candidate = labels.suffix(n).joined(separator: ".")
            if multiLabelSuffixes.contains(candidate) {
                let need = n + 1
                if labels.count >= need {
                    return labels.suffix(need).joined(separator: ".")
                }
                return labels.joined(separator: ".")
            }
        }
        return labels.suffix(2).joined(separator: ".")
    }
}
