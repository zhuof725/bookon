//
//  JsExtensionsCore.swift
//  LegadoBookSource
//
//  Step 5 纯算法方法。逐函数对照 legado JsExtensions / JsEncodeUtils 及直接 utils。
//  不涉及网络/UI；这些方法可由 JSJavaBridge 和 public Swift API 共用。
//

import Foundation
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
        default:
            guard let encoding = stringEncoding(charset), let string = String(data: data, encoding: encoding) else {
                throw RuleEngineError.unsupported("字节无法按字符集解码：\(charset)")
            }
            return string
        }
    }

    public static func base64Encode(_ input: String) -> String {
        Data(input.utf8).base64EncodedString()
    }

    public static func base64Decode(_ input: String?, charset: String = "UTF-8") throws -> String {
        let value = input ?? ""
        guard let data = Data(base64Encoded: value, options: [.ignoreUnknownCharacters]) else {
            throw RuleEngineError.unsupported("Base64 解码失败")
        }
        return try bytesToStr(Array(data), charset: charset)
    }

    /// 对齐 Kotlin base64DecodeToByteArray(str, flags=0)：isNullOrBlank() -> null，其余 android Base64.decode。
    public static func base64DecodeToByteArray(_ input: String?) -> [UInt8]? {
        guard let input, !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Data(base64Encoded: input, options: [.ignoreUnknownCharacters]).map { Array($0) }
    }

    public static func hexEncodeToString(_ input: String) -> String {
        input.utf8.map { String(format: "%02x", $0) }.joined()
    }

    public static func hexDecodeToString(_ input: String) -> String? {
        // 对齐 hutool HexUtil.decodeHexStr：非法输入返回 null。
        guard let bytes = try? hexDecodeToBytes(input) else { return nil }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// 对齐 Kotlin HexUtil.decodeHex（返回 byte[]）。
    public static func hexDecodeToByteArray(_ input: String) -> [UInt8]? {
        try? hexDecodeToBytes(input)
    }

    public static func hexDecodeToBytes(_ input: String) throws -> [UInt8] {
        let scalars = Array(input.utf8)
        guard scalars.count % 2 == 0 else { throw RuleEngineError.unsupported("Hex 长度必须为偶数") }
        var result: [UInt8] = []
        result.reserveCapacity(scalars.count / 2)
        var i = 0
        while i < scalars.count {
            guard let high = hexNibble(scalars[i]), let low = hexNibble(scalars[i + 1]) else {
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
    public static func htmlFormat(_ html: String) -> String {
        var output = html
        output = replacing(output, pattern: "(&nbsp;)+", with: " ")
        output = replacing(output, pattern: "(&ensp;|&emsp;)", with: " ")
        output = replacing(output, pattern: "(&thinsp;|&zwnj;|&zwj;|\\u2009|\\u200C|\\u200D)", with: "")
        output = replacing(output, pattern: "</?(?:div|p|br|hr|h\\d|article|dd|dl)[^>]*>", with: "\n")
        output = replacing(output, pattern: "<!--[^>]*-->", with: "")
        output = replacing(output, pattern: "</?(?!img)[a-zA-Z]+(?=[ >])[^<>]*>", with: "")
        output = replacing(output, pattern: "\\s*\\n+\\s*", with: "\n　　")
        output = replacing(output, pattern: "^[\\n\\s]+", with: "　　")
        output = replacing(output, pattern: "[\\n\\s]+$", with: "")
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

    private static func replacing(_ input: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return input }
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
        guard let url = Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Chinese"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: { $0.isNewline }).map(String.init)
    }
}
