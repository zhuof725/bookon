//
//  JsExtGoldenComparisonTests.swift
//  LegadoHTMLEngineTests
//
//  Step 5 golden：JsExtensions 纯算法对照真实 Java 库（hutool 5.8.22 / quick-chinese-transfer
//  0.2.17 / Java 标准库）。逐条比较 md5/base64/hex/t2s/s2t/timeFormat/encodeURI/toNumChapter/
//  htmlFormat/strToBytes/bytesToStr。
//
//  比较三态：Java 抛错 <-> Swift 抛错；Java null <-> Swift nil；Java 值 == Swift 值。
//  失败信息含 name/输入/Java结果/Swift结果。CI 下 golden 缺失必须 fail（不许 XCTSkip）。
//  全部输入为合成样本。
//

import XCTest
@testable import LegadoBookSource

final class JsExtGoldenComparisonTests: XCTestCase {

    private enum Outcome: Equatable {
        case threw
        case null
        case value(String)
    }

    private struct Result: Decodable {
        let name: String
        let method: String
        let args: [JSONArg]?
        let hex: String?
        let result: JSONValueBox?
        let resultPresent: Bool
        let error: String?

        private enum CodingKeys: String, CodingKey { case name, method, args, hex, result, error }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            method = try c.decode(String.self, forKey: .method)
            args = try c.decodeIfPresent([JSONArg].self, forKey: .args)
            hex = try c.decodeIfPresent(String.self, forKey: .hex)
            error = try c.decodeIfPresent(String.self, forKey: .error)
            resultPresent = c.contains(.result)
            if resultPresent, (try? c.decodeNil(forKey: .result)) != true {
                result = try? c.decode(JSONValueBox.self, forKey: .result)
            } else {
                result = nil
            }
        }
    }

    private struct JSONArg: Decodable {
        let value: String?
        let isNull: Bool
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() { value = nil; isNull = true; return }
            if let n = try? c.decode(Double.self) {
                // JS 数字 → Java String 参数按 JS ToString：整数无 .0
                value = JsExtGoldenComparisonTests.jsNumberToString(n)
                isNull = false
                return
            }
            if let s = try? c.decode(String.self) { value = s; isNull = false; return }
            value = nil; isNull = true
        }
    }

    /// JS Number → 字符串（对齐 Rhino 数字转 String 参数的语义：整数无 .0）。
    private static func jsNumberToString(_ d: Double) -> String {
        if d == d.rounded() && d.isFinite && abs(d) <= 9_007_199_254_740_991 {
            return String(Int64(d))
        }
        return String(d)
    }

    private enum JSONValueBox: Decodable, Equatable {
        case string(String)
        case null
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() { self = .null; return }
            self = .string(try c.decode(String.self))
        }
    }

    private struct Envelope: Decodable { let jsExtResults: [Result]? }

    private func goldenFile() -> URL? {
        guard let resourceURL = Bundle.module.resourceURL else { return nil }
        let golden = resourceURL.appendingPathComponent("golden/js_ext_cases.json")
        if FileManager.default.fileExists(atPath: golden.path) { return golden }
        if let en = FileManager.default.enumerator(at: resourceURL, includingPropertiesForKeys: nil) {
            for case let f as URL in en where f.lastPathComponent == "js_ext_cases.json" { return f }
        }
        return nil
    }

    private func isRunningInCI() -> Bool {
        let env = ProcessInfo.processInfo.environment
        for key in ["CI", "GITHUB_ACTIONS", "GITHUB_WORKFLOW", "GITHUB_RUN_ID", "RUNNER_OS"] {
            if let v = env[key], !v.isEmpty { return true }
        }
        return false
    }

    private func report(_ c: Result, java: Outcome, swift: Outcome) -> String {
        """
        [JS Ext/\(c.name) \(c.method)]
          args: \(c.args?.map { $0.value ?? "<null>" }.joined(separator: ", ") ?? "[]") hex: \(c.hex ?? "-")
          Java: \(java) error: \(c.error ?? "<none>")
          Swift: \(swift)
        """
    }

    private func stringArg(_ c: Result, _ index: Int) -> String? {
        guard let args = c.args, index < args.count else { return nil }
        return args[index].value
    }

    private func numberArg(_ c: Result, _ index: Int) -> Int64 {
        guard let args = c.args, index < args.count, let v = args[index].value,
              let d = Double(v) else { return 0 }
        return Int64(d)
    }

    /// 执行 Swift 调用，把「抛错 / nil / 值」映射为三态。
    private func outcome(_ f: () throws -> String?) -> Outcome {
        do {
            if let v = try f() { return .value(v) }
            return .null
        } catch {
            return .threw
        }
    }

    private func javaOutcome(_ c: Result) -> Outcome {
        // Java 侧抛错时 catch 一定写 error 字段；Gson 默认省略 null 成员，
        // 所以「无 error」= 正常返回；result 缺失或 null 均为「返回 null」。
        if c.error != nil { return .threw }
        switch c.result {
        case .some(.string(let s)): return .value(s)
        default: return .null
        }
    }

    func testGoldenJsExtPureAlgorithms() throws {
        guard let file = goldenFile() else {
            try failWhenNoGolden()
            return
        }
        let data = try Data(contentsOf: file)
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data), let cases = envelope.jsExtResults else {
            try failWhenNoGolden()
            return
        }
        var failures: [String] = []
        var compared = 0
        for c in cases {
            compared += 1
            let swiftOutcome: Outcome
            switch c.method {
            case "md5Encode":
                swiftOutcome = outcome { JsExtensionsCore.md5Encode(stringArg(c, 0) ?? "") }
            case "md5Encode16":
                swiftOutcome = outcome { JsExtensionsCore.md5Encode16(stringArg(c, 0) ?? "") }
            case "base64Encode":
                swiftOutcome = outcome { JsExtensionsCore.base64Encode(stringArg(c, 0) ?? "") }
            case "base64Decode":
                swiftOutcome = outcome { try JsExtensionsCore.base64Decode(stringArg(c, 0)) }
            case "hexEncodeToString":
                swiftOutcome = outcome { JsExtensionsCore.hexEncodeToString(stringArg(c, 0) ?? "") }
            case "hexDecodeToString":
                swiftOutcome = outcome { try JsExtensionsCore.hexDecodeToString(stringArg(c, 0) ?? "") }
            case "t2s":
                swiftOutcome = outcome { JsExtensionsCore.t2s(stringArg(c, 0) ?? "") }
            case "s2t":
                swiftOutcome = outcome { JsExtensionsCore.s2t(stringArg(c, 0) ?? "") }
            case "timeFormat":
                swiftOutcome = outcome { JsExtensionsCore.timeFormat(numberArg(c, 0)) }
            case "timeFormatUTC":
                swiftOutcome = outcome {
                    JsExtensionsCore.timeFormatUTC(numberArg(c, 0), format: stringArg(c, 1) ?? "",
                                                   offsetMilliseconds: Int(numberArg(c, 2)))
                }
            case "encodeURI":
                swiftOutcome = outcome { JsExtensionsCore.encodeURI(stringArg(c, 0) ?? "") }
            case "toNumChapter":
                swiftOutcome = outcome {
                    stringArg(c, 0).flatMap { JsExtensionsCore.toNumChapter($0) }
                }
            case "htmlFormat":
                swiftOutcome = outcome { JsExtensionsCore.htmlFormat(stringArg(c, 0) ?? "") }
            case "strToBytes":
                swiftOutcome = outcome {
                    let bytes = try JsExtensionsCore.strToBytes(stringArg(c, 0) ?? "")
                    return bytes.map { String(format: "%02x", $0) }.joined()
                }
            case "bytesToStr":
                swiftOutcome = outcome {
                    let bytes = JsExtensionsCore.hexDecodeToByteArray(c.hex ?? "") ?? []
                    return try JsExtensionsCore.bytesToStr(bytes)
                }
            default:
                continue
            }
            let java = javaOutcome(c)
            if java != swiftOutcome {
                failures.append(report(c, java: java, swift: swiftOutcome))
            }
        }
        if compared == 0 { try failWhenNoGolden() }
        if !failures.isEmpty { XCTFail("发现 \(failures.count) 处 JsExtensions golden 不一致：\n\n" + failures.joined(separator: "\n\n")) }
    }

    private func failWhenNoGolden() throws {
        if isRunningInCI() {
            XCTFail("CI 环境下 golden 对照数据缺失或为空（js_ext_cases.json），不允许静默跳过")
            return
        }
        throw XCTSkip("js_ext_cases.json 缺失（本地未跑 golden job）。")
    }
}
