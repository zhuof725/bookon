//
//  JsExtGoldenComparisonTests.swift
//  LegadoHTMLEngineTests
//
//  Step 5 golden：JsExtensions 纯算法对照真实 Java 库（hutool 5.8.22 / quick-chinese-transfer
//  0.2.17 / jsoup 1.16.2 / Java 标准库）。逐条比较 md5/base64/hex/t2s/s2t/timeFormat/
//  encodeURI/toNumChapter/htmlFormat/strToBytes/bytesToStr；Jsoup.parse 链另测。
//
//  失败信息含 name/输入/Java结果/Swift结果。CI 下 golden 缺失必须 fail（不许 XCTSkip）。
//  全部输入为合成样本。
//

import XCTest
@testable import LegadoBookSource

final class JsExtGoldenComparisonTests: XCTestCase {

    private struct Result: Decodable {
        let name: String
        let method: String
        let args: [JSONArg]?
        let hex: String?
        let result: JSONValueBox?
        let error: String?
    }
    private struct JSONArg: Decodable {
        let value: String?
        let isNumber: Bool?
        let isNull: Bool?
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() { value = nil; isNumber = false; isNull = true; return }
            if let n = try? c.decode(Double.self) { value = "\(n)"; isNumber = true; isNull = false; return }
            if let s = try? c.decode(String.self) { value = s; isNumber = false; isNull = false; return }
            value = nil; isNumber = false; isNull = true
        }
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

    private func report(_ c: Result, java: String?, swift: String) -> String {
        """
        [JS Ext/\(c.name) \(c.method)]
          args: \(c.args?.map { $0.value ?? "<null>" }.joined(separator: ", ") ?? "[]") hex: \(c.hex ?? "-")
          Java: \(java.debugDescription) error: \(c.error ?? "<none>")
          Swift: \(swift.debugDescription)
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
            let swift: String?
            let java: String?
            switch c.method {
            case "md5Encode":
                java = stringResult(c); swift = JsExtensionsCore.md5Encode(stringArg(c, 0) ?? "")
            case "md5Encode16":
                java = stringResult(c); swift = JsExtensionsCore.md5Encode16(stringArg(c, 0) ?? "")
            case "base64Encode":
                java = stringResult(c); swift = JsExtensionsCore.base64Encode(stringArg(c, 0) ?? "")
            case "base64Decode":
                java = stringResult(c); swift = (try? JsExtensionsCore.base64Decode(stringArg(c, 0))) ?? ""
            case "hexEncodeToString":
                java = stringResult(c); swift = JsExtensionsCore.hexEncodeToString(stringArg(c, 0) ?? "")
            case "hexDecodeToString":
                java = stringResult(c); swift = JsExtensionsCore.hexDecodeToString(stringArg(c, 0) ?? "") ?? ""
            case "t2s":
                java = stringResult(c); swift = JsExtensionsCore.t2s(stringArg(c, 0) ?? "")
            case "s2t":
                java = stringResult(c); swift = JsExtensionsCore.s2t(stringArg(c, 0) ?? "")
            case "timeFormat":
                java = stringResult(c); swift = JsExtensionsCore.timeFormat(numberArg(c, 0))
            case "timeFormatUTC":
                java = stringResult(c)
                swift = JsExtensionsCore.timeFormatUTC(numberArg(c, 0), format: stringArg(c, 1) ?? "",
                                                       offsetMilliseconds: Int(numberArg(c, 2)))
            case "encodeURI":
                java = stringResult(c); swift = JsExtensionsCore.encodeURI(stringArg(c, 0) ?? "")
            case "toNumChapter":
                java = stringResult(c); swift = JsExtensionsCore.toNumChapter(stringArg(c, 0)) ?? ""
            case "htmlFormat":
                java = stringResult(c); swift = JsExtensionsCore.htmlFormat(stringArg(c, 0) ?? "")
            case "strToBytes":
                java = stringResult(c)
                let bytes = (try? JsExtensionsCore.strToBytes(stringArg(c, 0) ?? "")) ?? []
                swift = bytes.map { String(format: "%02x", $0) }.joined()
            case "bytesToStr":
                java = stringResult(c)
                let bytes = JsExtensionsCore.hexDecodeToByteArray(c.hex ?? "") ?? []
                swift = (try? JsExtensionsCore.bytesToStr(bytes)) ?? ""
            default:
                continue
            }
            if let swift, let java, swift != java {
                failures.append(report(c, java: java, swift: swift))
            }
        }
        if compared == 0 { try failWhenNoGolden() }
        if !failures.isEmpty { XCTFail("发现 \(failures.count) 处 JsExtensions golden 不一致：\n\n" + failures.joined(separator: "\n\n")) }
    }

    private func stringResult(_ c: Result) -> String? {
        guard let r = c.result else { return nil }
        switch r { case .string(let s): return s; case .null: return "" }
    }

    private func failWhenNoGolden() throws {
        if isRunningInCI() {
            XCTFail("CI 环境下 golden 对照数据缺失或为空（js_ext_cases.json），不允许静默跳过")
            return
        }
        throw XCTSkip("js_ext_cases.json 缺失（本地未跑 golden job）。")
    }
}