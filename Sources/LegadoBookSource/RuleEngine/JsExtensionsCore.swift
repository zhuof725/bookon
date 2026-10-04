//
//  JsExtensionsCore.swift
//  LegadoBookSource
//
//  Step 5 纯算法方法。逐函数对照 legado JsExtensions / JsEncodeUtils 及直接 utils。
//  不涉及网络/UI；这些方法可由 JSJavaBridge 和 public Swift API 共用。
//

import Foundation
import CoreFoundation
import CryptoKit

public enum JsExtensionsCore {
    // MARK: - MD5 (Kotlin String.toByteArray() 默认 UTF-8)

    public static func md5Encode(_ input: String) -> String {
        Insecure.MD5.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func md5Encode16(_ input: String) -> String {
        let full = md5Encode(input)
        guard full.count >= 24 else { return full }
        return String(full.dropFirst(8).prefix(16))
    }

    // MARK: - Byte / Base64 / Hex

    public static func strToBytes(_ input: String, charset: String = "UTF-8") throws -> [UInt8] {
        guard let encoding = stringEncoding(charset), let data = input.data(using: encoding) else {
            throw RuleEngineError.unsupported("不支持字符集：\(charset)")
        }
        return Array(data)
    }

    public static func bytesToStr(_ bytes: [UInt8], charset: String = "UTF-8") throws -> String {
        let data = Data(bytes)
        switch charset.uppercased().replacingOccurrences(of: "_", with: "-") {
        case "UTF-8", "UTF8":
            // 对齐 Kotlin String(bytes, UTF-8)：非法序列替换为 U+FFFD，不抛错。
            return String(decoding: data, as: UTF8.self)
        case "ISO-8859-1", "LATIN1", "ISO8859-1", "8859-1":
            // ISO-8859-1 是 256 字节到 U+0000..U+00FF 的一一映射，任何字节序列都合法，
            // 与 Java new String(bytes, ISO-8859-1) 逐字符相同。
            if let s = String(data: data, encoding: .isoLatin1) { return s }
            return String(bytes.map { Character(UnicodeScalar($0)) })
        case "GBK", "GB2312", "GB-2312", "CP936", "GB18030":
            // GBK 非法字节的替换语义按 JDK sun.nio.cs.DoubleByte.Decoder 的
            // crMalformedOrUnmappable 逐字节复刻（见 decodeGBKLenient）。
            return decodeGBKLenient(bytes)
        default:
            guard let encoding = stringEncoding(charset), let string = String(data: data, encoding: encoding) else {
                throw RuleEngineError.unsupported("字节无法按字符集解码：\(charset)")
            }
            return string
        }
    }

    /// GB18030-2000 的 Foundation 编码（GBK 是其子集，双字节部分映射一致）。
    private static let gbkEncoding: String.Encoding? = {
        let cf = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        let ns = CFStringConvertEncodingToNSStringEncoding(cf)
        if ns == 0 || ns == UInt(kCFStringEncodingInvalidId) { return nil }
        return String.Encoding(rawValue: ns)
    }()

    /// 对齐 Java `new String(bytes, "GBK")` 的替换语义：
    /// JDK 的 GBK 解码器（sun.nio.cs.DoubleByte.Decoder#decodeArrayLoop + crMalformedOrUnmappable）在遇到
    /// 非法/不可映射的双字节时，按下面的规则决定消费 1 个还是 2 个字节，并输出**一个** U+FFFD：
    ///   - b1 不在 0x81...0xFE（不是前导字节）→ 消费 1
    ///   - b2 在 0x81...0xFE（自身是前导字节）或 b2 &lt; 0x80（是合法单字节）→ 消费 1
    ///   - 其余（b1 是前导字节且 b2 ∈ {0x80, 0xFF}）→ 消费 2
    /// 末尾不足 2 字节时，JDK 走「endOfInput + underflow」→ malformedForLength(剩余) → 同样一个 U+FFFD。
    private static func decodeGBKLenient(_ bytes: [UInt8]) -> String {
        var output = ""
        let count = bytes.count
        var index = 0
        func isLead(_ b: UInt8) -> Bool { b >= 0x81 && b <= 0xFE }
        while index < count {
            let b1 = bytes[index]
            if b1 < 0x80 {
                output.append(Character(UnicodeScalar(b1)))
                index += 1
                continue
            }
            if index + 1 >= count {
                output.append("\u{FFFD}")
                index += 1
                continue
            }
            let pair = Array(bytes[index...index + 1])
            if let encoding = gbkEncoding,
               let decoded = String(data: Data(pair), encoding: encoding),
               decoded.unicodeScalars.count == 1,
               decoded.unicodeScalars.first?.value != 0xFFFD {
                output += decoded
                index += 2
                continue
            }
            let b2 = bytes[index + 1]
            index += (!isLead(b1) || isLead(b2) || b2 < 0x80) ? 1 : 2
            output.append("\u{FFFD}")
        }
        return output
    }

    public static func base64Encode(_ input: String) -> String {
        Data(input.utf8).base64EncodedString()
    }

    public static func base64Decode(_ input: String?, charset: String = "UTF-8") throws -> String {
        // 对齐 hutool Base64.decodeStr：容错解码（跳过非法字符，'=' 作 padding，4 字符一组），
        // 不做严格校验、不抛错（与 Data(base64Encoded:) 的严格行为不同）。
        let value = input ?? ""
        let bytes = hutoolBase64Decode(Array(value.utf8))
        return try bytesToStr(bytes, charset: charset)
    }

    /// hutool Base64Decoder.decode 的逐行移植（5.8.22）。
    /// 说明：hutool 解码表只覆盖到 'z'（长度 123）；Java 对 { | } ~ DEL 会数组越界抛错，
    /// 本移植对越界字节按「非 base64 字符跳过」处理（不崩溃，README 有登记）。
    private static func hutoolBase64Decode(_ input: [UInt8]) -> [UInt8] {
        guard !input.isEmpty else { return input }
        let padding: Int = -2
        var table = [Int](repeating: -1, count: 128)
        // A-Z -> 0-25
        for (i, b) in (0x41...0x5A).enumerated() { table[b] = i }
        // a-z -> 26-51
        for (i, b) in (0x61...0x7A).enumerated() { table[b] = 26 + i }
        // 0-9 -> 52-61
        for (i, b) in (0x30...0x39).enumerated() { table[b] = 52 + i }
        table[0x2B] = 62 // '+'
        table[0x2D] = 62 // '-'
        table[0x2F] = 63 // '/'
        table[0x5F] = 63 // '_'
        table[0x3D] = padding // '='

        var offset = 0
        let maxPos = input.count - 1
        var octet: [UInt8] = []
        octet.reserveCapacity(input.count * 3 / 4)

        func nextValid() -> Int {
            while offset <= maxPos {
                let base64Byte = input[offset]
                offset += 1
                if base64Byte > 0 && base64Byte < 128 {
                    let decodeByte = table[Int(base64Byte)]
                    if decodeByte > -1 { return decodeByte }
                }
            }
            return padding
        }

        while offset <= maxPos {
            let s0 = nextValid()
            let s1 = nextValid()
            let s2 = nextValid()
            let s3 = nextValid()
            if padding != s1 { octet.append(UInt8(truncatingIfNeeded: (s0 << 2) | (s1 >> 4))) }
            if padding != s2 { octet.append(UInt8(truncatingIfNeeded: ((s1 & 0xF) << 4) | (s2 >> 2))) }
            if padding != s3 { octet.append(UInt8(truncatingIfNeeded: ((s2 & 3) << 6) | s3)) }
        }
        return octet
    }

    /// 对齐 Kotlin base64DecodeToByteArray(str, flags=0)：isNullOrBlank() -> null，其余 android Base64.decode。
    public static func base64DecodeToByteArray(_ input: String?) -> [UInt8]? {
        guard let input, !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Data(base64Encoded: input, options: [.ignoreUnknownCharacters]).map { Array($0) }
    }

    public static func hexEncodeToString(_ input: String) -> String {
        input.utf8.map { String(format: "%02x", $0) }.joined()
    }

    public static func hexDecodeToString(_ input: String) throws -> String? {
        // 对齐 hutool HexUtil.decodeHexStr：空串 -> 原样返回 ""；非法字符抛错。
        if input.isEmpty { return "" }
        let bytes = try hexDecodeToBytes(input)
        return String(decoding: bytes, as: UTF8.self)
    }

    /// 对齐 Kotlin HexUtil.decodeHex（byte[]）：空串 -> null；奇数长度前补 0；非法字符抛错。
    public static func hexDecodeToByteArray(_ input: String) -> [UInt8]? {
        if input.isEmpty { return nil }
        return try? hexDecodeToBytes(input)
    }

    public static func hexDecodeToBytes(_ input: String) throws -> [UInt8] {
        // hutool Base16Codec.decode：cleanBlank + 奇数长度前补 0
        let cleaned = input.filter { !$0.isWhitespace }
        var hex = cleaned
        if hex.utf8.count % 2 != 0 { hex = "0" + hex }
        let scalars = Array(hex.utf8)
        var result: [UInt8] = []
        result.reserveCapacity(scalars.count / 2)
        var i = 0
        while i < scalars.count {
            guard let high = hexNibble(scalars[i]), let low = hexNibble(scalars[i + 1]) else {
                // 对齐 hutool toDigit：非法字符抛异常
                throw RuleEngineError.unsupported("Hex 含非法字符")
            }
            result.append(high << 4 | low)
            i += 2
        }
        return result
    }

    // MARK: - Date / URI / HTML

    public static func timeFormat(_ milliseconds: Int64) -> String {
        format(milliseconds: milliseconds, pattern: "yyyy/MM/dd HH:mm", timeZone: .current)
    }

    /// Kotlin `SimpleTimeZone(sh, "UTC")` 的 sh 是原始偏移毫秒数。
    public static func timeFormatUTC(_ milliseconds: Int64, format pattern: String, offsetMilliseconds: Int) -> String {
        let zone = TimeZone(secondsFromGMT: offsetMilliseconds / 1000)
            ?? TimeZone(identifier: "UTC") ?? TimeZone.current
        return format(milliseconds: milliseconds, pattern: pattern, timeZone: zone)
    }

    public static func encodeURI(_ input: String, charset: String = "UTF-8") -> String {
        guard let encoding = stringEncoding(charset), let data = input.data(using: encoding) else { return "" }
        var out = ""
        for byte in data {
            switch byte {
            case 0x41...0x5A, 0x61...0x7A, 0x30...0x39, 0x2E, 0x2D, 0x2A, 0x5F:
                out.append(Character(UnicodeScalar(byte)))
            case 0x20:
                out.append("+")
            default:
                out += String(format: "%%%02X", byte)
            }
        }
        return out
    }

    /// 对齐 HtmlFormatter.formatKeepImg（redirectUrl=null 路径）。
    /// Java 正则 `\s` 只含 ASCII 空白（不含全角空格 U+3000）；ICU 的 `\s` 含全角空格，
    /// 因此这里显式写成 ASCII 空白类，避免差异。
    public static func htmlFormat(_ html: String) -> String {
        var output = html
        output = replacing(output, pattern: "(&nbsp;)+", with: " ")
        output = replacing(output, pattern: "(&ensp;|&emsp;)", with: " ")
        output = replacing(output, pattern: "(&thinsp;|&zwnj;|&zwj;|\\u2009|\\u200C|\\u200D)", with: "")
        output = replacing(output, pattern: "</?(?:div|p|br|hr|h\\d|article|dd|dl)[^>]*>", with: "\n")
        output = replacing(output, pattern: "<!--[^>]*-->", with: "")
        output = replacing(output, pattern: "</?(?!img)[a-zA-Z]+(?=[ >])[^<>]*>", with: "")
        output = replacing(output, pattern: "[ \\t\\r\\n\\f]*\\n+[ \\t\\r\\n\\f]*", with: "\n　　")
        output = replacing(output, pattern: "^[\\n \\t\\r\\f]+", with: "　　")
        output = replacing(output, pattern: "[\\n \\t\\r\\f]+$", with: "")
        // formatKeepImg：把 <img ... src="X" ...> 归一为 <img src="X">（redirectUrl=null，
        // getAbsoluteURL(null, src) 返回 trim 原串）。仅覆盖真实书源用到的双引号无参形式。
        output = replacing(output, pattern: "<img[^>]*\\ssrc\\s*=\\s*\"([^\">]+)\"[^>]*>", with: "<img src=\"$1\">", caseInsensitive: true)
        return output
    }

    // MARK: - Chinese conversion / chapter number

    public static func t2s(_ input: String) -> String { ChineseTransfer.shared.convert(input, direction: .traditionalToSimple) }
    public static func s2t(_ input: String) -> String { ChineseTransfer.shared.convert(input, direction: .simpleToTraditional) }

    public static func toNumChapter(_ input: String?) -> String? {
        guard let input else { return nil }
        guard let regex = try? NSRegularExpression(pattern: "(第)(.+?)(章)") else { return input }
        let ns = input as NSString
        guard let match = regex.firstMatch(in: input, range: NSRange(location: 0, length: ns.length)), match.numberOfRanges >= 4 else {
            return input
        }
        let number = stringToInt(ns.substring(with: match.range(at: 2)))
        return ns.substring(with: match.range(at: 1)) + String(number) + ns.substring(with: match.range(at: 3))
    }

    public static func randomUUID() -> String { UUID().uuidString.lowercased() }

    // MARK: - Helpers

    private static func format(milliseconds: Int64, pattern: String, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000.0))
    }

    private static func stringEncoding(_ name: String) -> String.Encoding? {
        switch name.uppercased().replacingOccurrences(of: "_", with: "-") {
        case "UTF-8", "UTF8": return .utf8
        case "UTF-16", "UTF16": return .utf16
        case "UTF-16LE": return .utf16LittleEndian
        case "UTF-16BE": return .utf16BigEndian
        case "ISO-8859-1", "LATIN1": return .isoLatin1
        case "US-ASCII", "ASCII": return .ascii
        default: return nil
        }
    }

    private static func hexNibble(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: return byte - 48
        case 65...70: return byte - 55
        case 97...102: return byte - 87
        default: return nil
        }
    }

    private static func replacing(_ input: String, pattern: String, with replacement: String, caseInsensitive: Bool = false) -> String {
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return input }
        let range = NSRange(location: 0, length: (input as NSString).length)
        return regex.stringByReplacingMatches(in: input, range: range, withTemplate: replacement)
    }

    private static let chineseNumbers: [Character: Int] = [
        "零":0,"〇":0,"一":1,"壹":1,"二":2,"贰":2,"两":2,"三":3,"叁":3,
        "四":4,"肆":4,"五":5,"伍":5,"六":6,"陆":6,"七":7,"柒":7,"八":8,"捌":8,
        "九":9,"玖":9,"十":10,"拾":10,"百":100,"佰":100,"千":1000,"仟":1000,
        "万":10000,"亿":100000000
    ]

    private static func stringToInt(_ input: String) -> Int {
        let normalized = fullToHalf(input).filter { !$0.isWhitespace }
        if let value = Int(normalized) { return value }
        return chineseNumToInt(normalized)
    }

    private static func fullToHalf(_ input: String) -> String {
        let scalars = input.unicodeScalars.map { scalar -> UnicodeScalar in
            if scalar.value == 12288 { return UnicodeScalar(32) ?? scalar }
            if scalar.value >= 65281 && scalar.value <= 65374 { return UnicodeScalar(scalar.value - 65248) ?? scalar }
            return scalar
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func chineseNumToInt(_ input: String) -> Int {
        let chars = Array(input)
        var result = 0, temp = 0, billion = 0
        for (index, char) in chars.enumerated() {
            guard let n = chineseNumbers[char] else { return -1 }
            if n == 100000000 {
                result += temp; result *= n; billion = billion * 100000000 + result; result = 0; temp = 0
            } else if n == 10000 {
                result += temp; result *= n; temp = 0
            } else if n >= 10 {
                if temp == 0 { temp = 1 }
                result += n * temp; temp = 0
            } else {
                if index >= 2 && index == chars.count - 1, let previous = chineseNumbers[chars[index - 1]], previous > 10 {
                    temp = n * previous / 10
                } else {
                    temp = temp * 10 + n
                }
            }
        }
        return result + temp + billion
    }
}

private final class ChineseTransfer {
    enum Direction { case traditionalToSimple, simpleToTraditional }
    static let shared = ChineseTransfer()

    private struct DictionaryData {
        let map: [String: String]
        let maxLength: Int
    }
    private lazy var t2sDictionary = load("t2s")
    private lazy var s2tDictionary = load("s2t")
    private lazy var t2sExclusions: Set<String> = Set(loadLines("t2s_exclude"))

    func convert(_ input: String, direction: Direction) -> String {
        let dictionary = direction == .traditionalToSimple ? t2sDictionary : s2tDictionary
        var map = dictionary.map
        if direction == .traditionalToSimple {
            for phrase in t2sExclusions { map[phrase] = phrase }
        }
        let chars = Array(input)
        var output = "", index = 0
        while index < chars.count {
            var match: String?, length = min(dictionary.maxLength, chars.count - index)
            while length > 0 {
                let key = String(chars[index..<(index + length)])
                if let value = map[key] { match = value; break }
                length -= 1
            }
            if let match { output += match; index += length }
            else { output.append(chars[index]); index += 1 }
        }
        return output
    }

    private func load(_ name: String) -> DictionaryData {
        var map: [String: String] = [:], maxLength = 1
        for line in loadLines(name) {
            guard let split = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<split]), value = String(line[line.index(after: split)...])
            guard !key.isEmpty else { continue }
            map[key] = value; maxLength = max(maxLength, key.count)
        }
        return DictionaryData(map: map, maxLength: maxLength)
    }

    private func loadLines(_ name: String) -> [String] {
        // 资源加载做健壮化：不同 SwiftPM 资源处理方式（.process/.copy）下目录层级可能不同，
        // 依次尝试 subdirectory、根目录、枚举三种定位方式。
        let bundle = Bundle.module
        var candidates: [URL?] = [
            bundle.url(forResource: name, withExtension: "txt", subdirectory: "Chinese"),
            bundle.url(forResource: name, withExtension: "txt")
        ]
        if let en = FileManager.default.enumerator(at: bundle.bundleURL, includingPropertiesForKeys: nil) {
            for case let f as URL in en where f.lastPathComponent == "\(name).txt" {
                candidates.append(f)
                break
            }
        }
        for case let url? in candidates {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                return text.split(whereSeparator: { $0.isNewline }).map(String.init)
            }
        }
        return []
    }
}
