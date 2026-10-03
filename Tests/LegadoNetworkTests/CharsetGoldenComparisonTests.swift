//
//  CharsetGoldenComparisonTests.swift
//  LegadoNetworkTests
//
//  第 6 步 6B：字符集检测 / 响应解码与**真实 legado icu4j 检测器 + JDK 11 Charset**逐条对照。
//
//  golden 由 `scripts/golden/CharsetGen.java` 生成（96 条合成样本，见
//  scripts/golden/cases/charset_cases.json，全部标注「合成样本（synthetic）」）：
//   - detected：CharsetDetector().setText(removeUTF8BOM(bytes)).detect()?.name ?: "UTF-8"
//   - htmlEncode：EncodingDetect.getHtmlEncode(bytes)（meta → 检测器）
//   - decoded：decodeText(bytes, explicitCharset, contentTypeHeader)
//     （BOM 剥离 → 显式 charset → Content-Type 头 → meta → 检测器）
//
//  不一致时先修 Swift 侧（本仓库 Sources/LegadoBookSource/Network/ 下
//  CharsetDetector/TextDecoder/EncodingDetect/StrResponse）；
//  确实无法对齐的用例把清单写进失败信息并让测试失败（不允许静默跳过）。
//
//  CI 下 golden 缺失必须 fail（不许 XCTSkip）。
//

import XCTest
@testable import LegadoBookSource

final class CharsetGoldenComparisonTests: XCTestCase {

    private struct CharsetCase: Decodable {
        let name: String
        let hex: String?
        let explicitCharset: String?
        let contentTypeHeader: String?
        let detected: String?
        let htmlEncode: String?
        let decoded: String?
        let error: String?
    }

    private func goldenFile() -> URL? {
        guard let resourceURL = Bundle.module.resourceURL else { return nil }
        let direct = resourceURL.appendingPathComponent("golden/charset_cases.json")
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        if let en = FileManager.default.enumerator(at: resourceURL, includingPropertiesForKeys: nil) {
            for case let f as URL in en where f.lastPathComponent == "charset_cases.json" { return f }
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

    private func hexBytes(_ hex: String) -> [UInt8] {
        var result: [UInt8] = []
        var i = hex.startIndex
        while i < hex.endIndex {
            let next = hex.index(i, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            if let v = UInt8(hex[i..<next], radix: 16) {
                result.append(v)
            }
            i = next
        }
        return result
    }

    private func esc(_ s: String) -> String { s.replacingOccurrences(of: "%", with: "%%") }

    func testGoldenCharsetDetectionAndDecoding() throws {
        guard let url = goldenFile(), let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["charsetResults"] as? [Any], !arr.isEmpty else {
            if isRunningInCI() {
                XCTFail("CI 环境下 golden 缺失或为空（charset_cases.json），不允许静默跳过")
                return
            }
            throw XCTSkip("charset_cases.json 缺失（本地未跑 golden job）。")
        }
        var failures: [String] = []
        var compared = 0
        for item in arr {
            guard let d = try? JSONSerialization.data(withJSONObject: item),
                  let c = try? JSONDecoder().decode(CharsetCase.self, from: d) else { continue }
            compared += 1
            let bytes = hexBytes(c.hex ?? "")
            let expectedDetected = c.detected ?? ""
            let expectedHtmlEncode = c.htmlEncode ?? ""
            let expectedDecoded = c.decoded

            let swiftDetected = CharsetDetector.detect(EncodingDetect.removeUTF8BOM(bytes))
            if swiftDetected != expectedDetected {
                failures.append("\(c.name): detected Swift=\(swiftDetected) golden=\(expectedDetected)")
            }

            let swiftHtmlEncode = EncodingDetect.getHtmlEncode(bytes)
            if swiftHtmlEncode != expectedHtmlEncode {
                failures.append("\(c.name): htmlEncode Swift=\(swiftHtmlEncode) golden=\(expectedHtmlEncode)")
            }

            if let expected = expectedDecoded {
                let swiftDecoded = StrResponse.decodeText(
                    bytes: bytes,
                    explicitCharset: c.explicitCharset,
                    contentTypeHeader: c.contentTypeHeader)
                if swiftDecoded != expected {
                    failures.append("\(c.name): decoded Swift=[\(swiftDecoded)] golden=[\(expected)]")
                }
            } else if let err = c.error {
                failures.append("\(c.name): golden 侧 Java 抛错（Swift 无法对齐）: \(err)")
            }
        }
        XCTAssertGreaterThan(compared, 0, "golden 文件里没有可比较的 charset 用例")
        if !failures.isEmpty {
            let detail = failures.prefix(50).joined(separator: "\n")
            let tail = failures.count > 50 ? "\n…（共 \(failures.count) 条不一致）" : ""
            XCTFail("字符集 golden 不一致（\(failures.count) 条）：\n\(detail)\(tail)")
        }
    }
}