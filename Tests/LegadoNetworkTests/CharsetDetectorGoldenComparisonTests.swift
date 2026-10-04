//
//  CharsetDetectorGoldenComparisonTests.swift
//  LegadoNetworkTests
//
//  第 6 步 6B：字符集检测与响应解码链的 golden 逐条对照（task 2c/2d）。
//
//  golden 由 `scripts/golden` 用**legado 自带的 icu4j 检测器源码**（逐行复制到 golden 侧
//  `legadoicu` 包）配合 `EncodingDetect.kt` 的 Java 移植（`golden.EncodingDetectGolden`）
// 对 240 份字节样本生成（`cases/charset_cases.json` 触发，输出 `charset_cases.json`）：
//   - `detectName` / `detectConfidence` / `allMatches`：CharserDetector.detect()/detectAll()；
//   - `htmlEncode`：EncodingDetect.getHtmlEncode（HTML meta → 检测器 → "UTF-8"）；
//   - `decoded*`：完整解码链（BOM → explicit charset → Content-Type charset → getHtmlEncode）
//     在各种组合下的结果。
//
//  CI 下 golden 缺失必须 fail（不许 XCTSkip），见 `load`。
//

import XCTest
@testable import LegadoBookSource

final class CharsetDetectorGoldenComparisonTests: XCTestCase {

    // MARK: - golden 读取

    private func goldenFile(_ name: String) -> URL? {
        guard let resourceURL = Bundle.module.resourceURL else { return nil }
        let direct = resourceURL.appendingPathComponent("golden/\(name)")
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        if let en = FileManager.default.enumerator(at: resourceURL, includingPropertiesForKeys: nil) {
            for case let f as URL in en where f.lastPathComponent == name { return f }
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

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "%", with: "%%")
    }

    // MARK: - golden 模型

    private struct GoldenMatch: Decodable {
        let name: String
        let confidence: Int
    }

    private struct CharsetCase: Decodable {
        let name: String
        let group: String
        let note: String
        let synthetic: Bool
        let syntheticNovelChapter: Bool
        let bytesBase64: String
        let byteLength: Int
        let detectName: String
        /// -1 表示 Java `detect()` 返回 null（无候选）。
        let detectConfidence: Int
        let getEncode: String
        let allMatches: [GoldenMatch]
        let htmlEncode: String?
        // 以下 6 个键在 golden 里**部分条目不存在**（只有出错/无候选时才写），
        // Swift 的 Decodable 对 `String?` 缺键会抛 keyNotFound，所以用自定义解码兜底为 nil。
        let htmlDecodeError: String?
        let decodedByHtmlEncode: String?
        let decodedDefault: String?
        let decodedDefaultError: String?
        let decodedContentTypeQuoted: String?
        let decodedContentTypeNoCharset: String?
        let decodedExplicitUtf8: String?
        let decodedExplicitGbk: String?
        let decodedExplicitBig5: String?
        let decodedExplicitIso88591: String?
        let decodedContentTypeUtf8: String?
        let decodedContentTypeGbk: String?
        let decodedExplicitBeatsHeader: String?

        private enum CodingKeys: String, CodingKey {
            case name, group, note, synthetic, syntheticNovelChapter, bytesBase64, byteLength
            case detectName, detectConfidence, getEncode, allMatches, htmlEncode
            case htmlDecodeError, decodedByHtmlEncode, decodedDefault, decodedDefaultError
            case decodedContentTypeQuoted, decodedContentTypeNoCharset
            case decodedExplicitUtf8, decodedExplicitGbk, decodedExplicitBig5, decodedExplicitIso88591
            case decodedContentTypeUtf8, decodedContentTypeGbk, decodedExplicitBeatsHeader
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            group = try c.decode(String.self, forKey: .group)
            note = try c.decode(String.self, forKey: .note)
            synthetic = try c.decode(Bool.self, forKey: .synthetic)
            syntheticNovelChapter = try c.decode(Bool.self, forKey: .syntheticNovelChapter)
            bytesBase64 = try c.decode(String.self, forKey: .bytesBase64)
            byteLength = try c.decode(Int.self, forKey: .byteLength)
            detectName = try c.decode(String.self, forKey: .detectName)
            detectConfidence = try c.decode(Int.self, forKey: .detectConfidence)
            getEncode = try c.decode(String.self, forKey: .getEncode)
            allMatches = try c.decodeIfPresent([GoldenMatch].self, forKey: .allMatches) ?? []
            htmlEncode = try c.decodeIfPresent(String.self, forKey: .htmlEncode)
            htmlDecodeError = try c.decodeIfPresent(String.self, forKey: .htmlDecodeError)
            decodedByHtmlEncode = try c.decodeIfPresent(String.self, forKey: .decodedByHtmlEncode)
            decodedDefault = try c.decodeIfPresent(String.self, forKey: .decodedDefault)
            decodedDefaultError = try c.decodeIfPresent(String.self, forKey: .decodedDefaultError)
            decodedContentTypeQuoted = try c.decodeIfPresent(String.self, forKey: .decodedContentTypeQuoted)
            decodedContentTypeNoCharset = try c.decodeIfPresent(String.self, forKey: .decodedContentTypeNoCharset)
            decodedExplicitUtf8 = try c.decodeIfPresent(String.self, forKey: .decodedExplicitUtf8)
            decodedExplicitGbk = try c.decodeIfPresent(String.self, forKey: .decodedExplicitGbk)
            decodedExplicitBig5 = try c.decodeIfPresent(String.self, forKey: .decodedExplicitBig5)
            decodedExplicitIso88591 = try c.decodeIfPresent(String.self, forKey: .decodedExplicitIso88591)
            decodedContentTypeUtf8 = try c.decodeIfPresent(String.self, forKey: .decodedContentTypeUtf8)
            decodedContentTypeGbk = try c.decodeIfPresent(String.self, forKey: .decodedContentTypeGbk)
            decodedExplicitBeatsHeader = try c.decodeIfPresent(String.self, forKey: .decodedExplicitBeatsHeader)
        }
    }

    private func loadCases() throws -> [CharsetCase] {
        guard let url = goldenFile("charset_cases.json"),
              let data = try? Data(contentsOf: url) else {
            if isRunningInCI() {
                XCTFail("CI 环境下 golden 缺失（charset_cases.json），不允许静默跳过")
            }
            throw XCTSkip("charset_cases.json 缺失（本地未跑 golden job）。")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["charsetResults"] as? [Any] else {
            if isRunningInCI() { XCTFail("CI 环境下 golden 结构异常（charset_cases.json/charsetResults）") }
            throw XCTSkip("charset_cases.json 结构异常。")
        }
        // 整段一起解码，避免逐条 JSONSerialization 往返（条目里的 null 会走 NSNull，
        // 往返再喂给 JSONDecoder 容易出岔子）。这里把数组重新序列化一次即可。
        let arrData = try JSONSerialization.data(withJSONObject: arr, options: [.fragmentsAllowed])
        return try JSONDecoder().decode([CharsetCase].self, from: arrData)
    }

    private func bytes(fromBase64 b64: String) -> [UInt8] {
        [UInt8](Data(base64Encoded: b64) ?? Data())
    }

    // MARK: - 1) 检测结果（字符集名 + 置信度 + 全量候选）

    func testGoldenCharsetDetection() throws {
        let cases = try loadCases()
        guard !cases.isEmpty else { XCTFail("charset_cases.json 为空"); return }

        var failures: [String] = []
        var nameChecked = 0
        var confidenceChecked = 0
        var novelChecked = 0

        for c in cases {
            if c.syntheticNovelChapter { novelChecked += 1 }
            let b = bytes(fromBase64: c.bytesBase64)
            XCTAssertEqual(b.count, c.byteLength, "[\(c.name)] Base64 还原后长度与 golden 不一致")

            // 1a. 字符集名（Kotlin getEncode 的兜底语义：无匹配 -> "UTF-8"）
            let swiftName = CharsetDetector.detect(b)
            nameChecked += 1
            if swiftName != c.detectName {
                failures.append(esc("""
                [\(c.name)] getEncode 字符集名不一致（\(c.note)）
                  Java : \(c.detectName)
                  Swift: \(swiftName)
                """))
            }
            let swiftGetEncode = EncodingDetect.getEncode(b)
            if swiftGetEncode != c.getEncode {
                failures.append(esc("[\(c.name)] EncodingDetect.getEncode 不一致 Java=\(c.getEncode) Swift=\(swiftGetEncode)"))
            }

            // 1b. 置信度（-1 表示 Java detect() 返回 null，即无候选）
            let swiftMatch = CharsetDetector.detectMatch(b)
            let swiftConfidence = swiftMatch?.confidence ?? -1
            confidenceChecked += 1
            if swiftConfidence != c.detectConfidence {
                failures.append(esc("""
                [\(c.name)] detect 置信度不一致（\(c.note)）
                  长度: \(c.byteLength) 字节
                  Java : name=\(c.detectName) confidence=\(c.detectConfidence)
                  Swift: name=\(swiftMatch?.name ?? "<nil>") confidence=\(swiftConfidence)
                """))
            }
            // Java detect() 为 null 时，Swift detectMatch 也必须为 nil（不允许凭空造结论）
            if c.detectConfidence == -1 && swiftMatch != nil {
                failures.append("[\(c.name)] Java detect() 返回 null，Swift 却给出 \(swiftMatch!.name)")
            }
            if c.detectConfidence != -1 && swiftMatch == nil {
                failures.append("[\(c.name)] Java detect() 有结论（\(c.detectName)），Swift 返回 nil")
            }

            // 1c. 全量候选（detectAll：名字 + 置信度 + 顺序）
            let swiftAll = CharsetDetector.detectAllMatches(b)
            if swiftAll.count != c.allMatches.count {
                failures.append(esc("[\(c.name)] detectAll 数量不一致 Java=\(c.allMatches.count) Swift=\(swiftAll.count)"))
            } else {
                for (i, gm) in c.allMatches.enumerated() {
                    let sm = swiftAll[i]
                    if sm.name != gm.name || sm.confidence != gm.confidence {
                        failures.append(esc("""
                        [\(c.name)] detectAll[\(i)] 不一致
                          Java : \(gm.name) (\(gm.confidence))
                          Swift: \(sm.name) (\(sm.confidence))
                        """))
                        break
                    }
                }
            }
        }

        // 用户要求：≥200 份样本、≥40 份合成小说章节
        XCTAssertGreaterThanOrEqual(cases.count, 200, "字符集 golden 样本应 ≥200 份")
        XCTAssertGreaterThanOrEqual(novelChecked, 40, "合成小说章节样本应 ≥40 份")
        XCTAssertGreaterThanOrEqual(nameChecked, 200, "字符集名应逐条比较 ≥200 条")
        XCTAssertGreaterThanOrEqual(confidenceChecked, 200, "置信度应逐条比较 ≥200 条")

        if !failures.isEmpty {
            XCTFail("charset 检测 golden 不一致 \(failures.count) 处（共 \(cases.count) 条样本）：\n"
                    + failures.prefix(20).joined(separator: "\n"))
        }
    }

    // MARK: - 2) HTML meta 判定（getHtmlEncode）

    func testGoldenGetHtmlEncode() throws {
        let cases = try loadCases()
        guard !cases.isEmpty else { XCTFail("charset_cases.json 为空"); return }
        var failures: [String] = []
        for c in cases {
            let b = bytes(fromBase64: c.bytesBase64)
            let swift = EncodingDetect.getHtmlEncode(b)
            if let expected = c.htmlEncode, swift != expected {
                failures.append(esc("""
                [\(c.name)] getHtmlEncode 不一致（\(c.note)）
                  Java : \(expected)
                  Swift: \(swift)
                """))
            }
        }
        if !failures.isEmpty {
            XCTFail("getHtmlEncode golden 不一致 \(failures.count)/\(cases.count)：\n"
                    + failures.prefix(20).joined(separator: "\n"))
        }
    }

    // MARK: - 3) 完整解码链（≥40 条，覆盖 BOM/charset/Content-Type 组合）

    /// 每种组合的检查项：golden key / （explicit charset, contentType header）。
    private static let decodeCombos: [(String, String?, String?)] = [
        ("decodedDefault", nil, nil),
        ("decodedExplicitUtf8", "UTF-8", nil),
        ("decodedExplicitGbk", "GBK", nil),
        ("decodedExplicitBig5", "Big5", nil),
        ("decodedExplicitIso88591", "ISO-8859-1", nil),
        ("decodedContentTypeUtf8", nil, "text/html; charset=UTF-8"),
        ("decodedContentTypeGbk", nil, "text/html; charset=gbk"),
        ("decodedContentTypeQuoted", nil, "text/html; charset=\"UTF-8\""),
        ("decodedContentTypeNoCharset", nil, "text/html"),
        ("decodedExplicitBeatsHeader", "GBK", "text/html; charset=UTF-8"),
    ]

    func testGoldenDecodeChain() throws {
        let cases = try loadCases()
        guard !cases.isEmpty else { XCTFail("charset_cases.json 为空"); return }

        // 把 golden 的每条用例的各个组合值取出来（用 KVC 风格的手写查表，避免依赖反射）
        func goldenValue(_ c: CharsetCase, _ key: String) -> String? {
            switch key {
            case "decodedDefault": return c.decodedDefault
            case "decodedExplicitUtf8": return c.decodedExplicitUtf8
            case "decodedExplicitGbk": return c.decodedExplicitGbk
            case "decodedExplicitBig5": return c.decodedExplicitBig5
            case "decodedExplicitIso88591": return c.decodedExplicitIso88591
            case "decodedContentTypeUtf8": return c.decodedContentTypeUtf8
            case "decodedContentTypeGbk": return c.decodedContentTypeGbk
            case "decodedContentTypeQuoted": return c.decodedContentTypeQuoted
            case "decodedContentTypeNoCharset": return c.decodedContentTypeNoCharset
            case "decodedExplicitBeatsHeader": return c.decodedExplicitBeatsHeader
            default: return nil
            }
        }

        var failures: [String] = []
        var comparisons = 0
        for c in cases {
            let b = bytes(fromBase64: c.bytesBase64)
            for (key, explicit, contentType) in CharsetDetectorGoldenComparisonTests.decodeCombos {
                guard let expected = goldenValue(c, key) else { continue }
                comparisons += 1
                let swift = JsNetTextDecoder.decode(bytes: b, explicitCharset: explicit,
                                                    contentTypeHeader: contentType)
                if swift != expected {
                    failures.append(esc("""
                    [\(c.name)] \(key) 解码不一致（\(c.note)）
                      explicit=\(explicit ?? "-") contentType=\(contentType ?? "-")
                      Java : \(expected)
                      Swift: \(swift)
                    """))
                }
            }
        }

        // 用户要求：完整解码用例至少 40 条
        XCTAssertGreaterThanOrEqual(comparisons, 40, "完整解码对照应 ≥40 条")

        if !failures.isEmpty {
            XCTFail("解码链 golden 不一致 \(failures.count)/\(comparisons)：\n"
                    + failures.prefix(15).joined(separator: "\n"))
        }
    }

    // MARK: - 4) 解码链优先级（独立于 golden 的结构性断言，锁定 Kotlin 顺序）

    /// Kotlin `ResponseBody.text(encode)` 的优先级：explicit > Content-Type > getHtmlEncode。
    func testDecodePriorityMatchesKotlin() {
        // 硬编码的 GBK 字节（"中文测试内容" 的 GBK 编码）。
        // 不用 CoreFoundation 转码在测试里现算字节：那条路径依赖平台、且会掩盖「字节是否真的
        // 是 GBK」的问题；固定字节让本用例在 macOS 与 iOS 上完全确定。
        let gbkBytes: [UInt8] = [
            0xD6, 0xD0, 0xCE, 0xC4, 0xB2, 0xE2, 0xCA, 0xD4, 0xC4, 0xDA, 0xC8, 0xDD,
        ]

        // explicit charset 优先于 Content-Type
        let a = JsNetTextDecoder.decode(bytes: gbkBytes, explicitCharset: "GBK",
                                        contentTypeHeader: "text/html; charset=UTF-8")
        XCTAssertEqual(a, "中文测试内容", "explicit charset 应优先于 Content-Type")

        // 无 explicit 时用 Content-Type
        let b = JsNetTextDecoder.decode(bytes: gbkBytes, explicitCharset: nil,
                                        contentTypeHeader: "text/html; charset=GBK")
        XCTAssertEqual(b, "中文测试内容", "Content-Type charset 应被使用")

        // OkHttp 语义：charset 值带引号也要能取到（MediaType.charset() 会剥引号）。
        let b2 = JsNetTextDecoder.decode(bytes: gbkBytes, explicitCharset: nil,
                                         contentTypeHeader: "text/html; charset=\"GBK\"")
        XCTAssertEqual(b2, "中文测试内容", "带引号的 charset 值应被正确解析（对齐 OkHttp MediaType.charset()）")

        // 两者皆无时走 getHtmlEncode（检测器应认出 GBK/GB18030）
        let c = JsNetTextDecoder.decode(bytes: gbkBytes, explicitCharset: nil, contentTypeHeader: nil)
        XCTAssertEqual(c, "中文测试内容", "无 meta 无头时应由 ICU4J 检测器认出 GB 系编码")

        // explicit 指向「不匹配的编码」时必须照用（不回落检测器），与 Java
        // `new String(bytes, charset)` 的替换字符语义一致。
        let d = JsNetTextDecoder.decode(bytes: gbkBytes, explicitCharset: "ISO-8859-1",
                                        contentTypeHeader: nil)
        XCTAssertNotEqual(d, "中文测试内容", "explicit 指定 ISO-8859-1 时不应回落检测器拿到正确中文")
        XCTAssertEqual(d.count, gbkBytes.count, "ISO-8859-1 是单字节编码，字符数应等于字节数")
    }

    /// UTF-8 BOM 必须被剥离（对应 Utf8BomUtils.removeUTF8BOM）。
    func testUTF8BOMStrippedBeforeDecode() {
        let text = "带 BOM 的正文"
        let bytes = [0xEF, 0xBB, 0xBF] + Array(text.utf8)
        let decoded = JsNetTextDecoder.decode(bytes: bytes, explicitCharset: nil, contentTypeHeader: nil)
        XCTAssertEqual(decoded, text)
        XCTAssertFalse(decoded.unicodeScalars.first == "\u{FEFF}", "BOM 不应残留在解码结果里")
    }

    /// HTML meta charset 应被 getHtmlEncode 采用（优先于检测器）。
    func testHTMLMetaCharsetUsedByGetHtmlEncode() {
        let html = "<html><head><meta charset=\"GBK\"></head><body>x</body></html>"
        XCTAssertEqual(EncodingDetect.getHtmlEncode(Array(html.utf8)), "GBK")

        let htmlEquiv = "<html><head><meta http-equiv=\"Content-Type\" "
            + "content=\"text/html; charset=gb2312\"></head><body>x</body></html>"
        XCTAssertEqual(EncodingDetect.getHtmlEncode(Array(htmlEquiv.utf8)), "gb2312")

        let htmlNoMeta = "<html><head><title>t</title></head><body>x</body></html>"
        // 无 meta 时回退检测器；纯 ASCII 内容 ICU4J 会给 ISO-8859-1（与 Java 侧一致，见 golden）
        let fallback = EncodingDetect.getHtmlEncode(Array(htmlNoMeta.utf8))
        XCTAssertEqual(fallback, CharsetDetector.detect(Array(htmlNoMeta.utf8)))
    }
}
