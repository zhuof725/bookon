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
        /// 标准 UTF-8 解码（Unicode 最大子部分算法）结果。
        ///
        /// Java 的 `new String(bytes, "UTF-8")` 对**连续非法字节**产生的替换字符数量与
        /// Unicode 标准（Swift `String(decoding:as:UTF8.self)`、Python `errors='replace'`）
        /// 不一致（JDK 的 resync 行为），240 份语料里有 18 份受影响。golden 因此额外输出本字段，
        /// 让 Swift 与「标准语义」对照；Java 原生结果 `decodedExplicitUtf8` 的差异在 README
        /// 差异表单列说明。合法 UTF-8 输入下两者完全相同。
        let decodedExplicitUtf8Standard: String?

        private enum CodingKeys: String, CodingKey {
            case name, group, note, synthetic, syntheticNovelChapter, bytesBase64, byteLength
            case detectName, detectConfidence, getEncode, allMatches, htmlEncode
            case htmlDecodeError, decodedByHtmlEncode, decodedDefault, decodedDefaultError
            case decodedContentTypeQuoted, decodedContentTypeNoCharset
            case decodedExplicitUtf8, decodedExplicitGbk, decodedExplicitBig5, decodedExplicitIso88591
            case decodedContentTypeUtf8, decodedContentTypeGbk, decodedExplicitBeatsHeader
            case decodedExplicitUtf8Standard
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
            decodedExplicitUtf8Standard = try c.decodeIfPresent(String.self, forKey: .decodedExplicitUtf8Standard)
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

        /// 该样本在 Apple Big5(CP950) 上是否正确解码的诊断辅助：列出未折叠的 PUA 位点。
        ///
        /// 仅用于失败消息的定位，不参与判定。
        func describePUA(_ s: String) -> String {
            let pua = s.unicodeScalars.filter { (0xE000...0xF8FF).contains($0.value) }
            return pua.isEmpty ? "无" : pua.map { String(format: "U+%04X", $0.value) }.joined(separator: ",")
        }

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

        // Java 生成器把每个 `decoded*` 用 `substring(0, 400)` 截断（**UTF-16 单元**计）。
        // Swift 必须做同样的截断再比较，否则长文本永远「不一致」（曾误报 64 处）。
        // 注意计数单位是 UTF-16 code unit，不是 Unicode 标量：含代理对时 400 单元 = 399 标量。
        func javaTruncate(_ s: String) -> String {
            let u16 = Array(s.utf16)
            if u16.count <= 400 { return s }
            return String(decoding: u16[0..<400], as: UTF16.self)
        }

        var failures: [String] = []
        var comparisons = 0
        var standardUtf8Comparisons = 0
        var big5MapDifferences = 0

        for c in cases {
            let b = bytes(fromBase64: c.bytesBase64)

            // 0) 标准 UTF-8 解码：与 golden 的 `decodedExplicitUtf8Standard` 对照。
            // 这一项锁的是「Swift 的 UTF-8 容错解码 == Unicode 最大子部分算法」，
            // 即与 Python `errors='replace'` 同语义（见 golden 侧 standardUtf8Decode 注释）。
            if let expectedStd = c.decodedExplicitUtf8Standard {
                standardUtf8Comparisons += 1
                let swiftStd = javaTruncate(
                    JsNetTextDecoder.decode(bytes: b, explicitCharset: "UTF-8", contentTypeHeader: nil))
                if swiftStd != expectedStd {
                    failures.append(esc("""
                    [\(c.name)] decodedExplicitUtf8Standard 不一致（\(c.note)）
                      Java(标准算法): \(expectedStd)
                      Swift         : \(swiftStd)
                    """))
                }
            }

            for (key, explicit, contentType) in CharsetDetectorGoldenComparisonTests.decodeCombos {
                guard let expected = goldenValue(c, key) else { continue }
                comparisons += 1
                let swift = javaTruncate(
                    JsNetTextDecoder.decode(bytes: b, explicitCharset: explicit,
                                            contentTypeHeader: contentType))
                if swift != expected {
                    // ── 豁免 1：Java UTF-8 的 resync 语义 ──────────────────────────
                    // 已单独用标准算法校验过的 UTF-8 路径不再重复计入：Java 原生
                    // `new String(bytes,"UTF-8")` 与标准算法的差异只出现在「输入含非法 UTF-8
                    // 字节」时（连续非法字节的 U+FFFD 个数），此时 Java 值必然含 U+FFFD。
                    // 无 U+FFFD 的用例两边必须逐字相同，所以只跳过含 U+FFFD 的那批。
                    //
                    // `decodedContentTypeQuoted`（`charset="UTF-8"`）与 `decodedContentTypeUtf8`
                    // 是**同一条 UTF-8 路径**（差别只在 Content-Type 里 charset 值带不带引号，
                    // 而 OkHttp `MediaType.charset()` 会把引号剥掉，两侧取值完全相同），
                    // 因此必须与它们同列豁免——首轮 CI（run 37207219284）漏了这一项，
                    // `gb2312-chinese` 的 `decodedContentTypeQuoted` 被误报。
                    // 该平台差异已记入 README 差异表 6B-12。
                    let isUtf8Path = (key == "decodedExplicitUtf8"
                                      || key == "decodedContentTypeUtf8"
                                      || key == "decodedContentTypeQuoted")
                    let isJavaUtf8Resync = isUtf8Path
                        && c.decodedExplicitUtf8Standard != nil
                        && expected.unicodeScalars.contains(where: { $0.value == 0xFFFD })
                    if isJavaUtf8Resync { continue }

                    // ── 豁免 2：Apple Big5(CP950) 与 JDK 严格 Big5 的码表差异 ────
                    // 见 README 差异表 6B-13。
                    //
                    // 两侧用的是**两套不同的 Big5 码表**，差异是**双向**的，已用真实 JVM
                    // `x-windows-950`（= Apple `.big5` 对应的 CP950）严格解码逐段核对：
                    //
                    // | 字节   | CP950（Apple）      | JDK `Big5`        |
                    // |--------|---------------------|-------------------|
                    // | C8E7   | `U+F831`（PUA）     | `U+FFFD U+FFFD`   |
                    // | 83F4   | `U+F084`（PUA）     | `U+FFFD U+FFFD`   |
                    // | 819B   | 解码失败            | `U+FFFD U+FFFD`   |
                    // | 972A   | 解码失败            | `U+FFFD U+002A`   |
                    // | 6892   | 解码失败            | `U+6892`（汉字）  |
                    //
                    // 即：CP950 多出 PUA 扩展区，JDK 表多出 `0x6892` 一类位点。**两边都不含彼此**，
                    // Apple 也没有「严格 Big5」编码可选（只有 `.big5` 与 `Big5_HKSCS_1999`，后者
                    // PUA 区更大），因此**逐码位对齐在技术上不可达**，属平台编码库差异而非移植缺陷。
                    //
                    // 本测试对此的立场：**不要求逐码位相等，但要求「退化程度」与 JDK 同量级**。
                    // 用 Big5 去解 UTF-8/日文/垃圾字节时，JDK 侧本来也会产出大面积替换字符，
                    // 所以判据不能是「替换字符少」，而应是「两侧的退化量级相当」：
                    //
                    // 1) Swift 结果非空；
                    // 2) 不含未折叠的 PUA（增量解码已把 PUA 替换成 U+FFFD）；
                    // 3) `swiftFFFD <= javaFFFD * 2 + 5`——Swift 的替换字符数不得超过 JDK 的
                    //    两倍（+5 是给「一个 CP950 PUA ↔ 两个 JDK U+FFFD」这种一对一差异留的余量）。
                    //    若增量解码的字节边界走错（例如吞字节），Swift 会成片多出替换字符，立刻报警；
                    // 4) 长度比在 [1/3, 3] 之间——防止整段被吞或整段被膨胀。
                    let isBig5MapDifference = key == "decodedExplicitBig5" && explicit == "Big5"
                    if isBig5MapDifference {
                        let scalars = Array(swift.unicodeScalars)
                        let swiftFFFD = scalars.filter { $0.value == 0xFFFD }.count
                        let javaFFFD = expected.unicodeScalars.filter { $0.value == 0xFFFD }.count
                        let puaCount = scalars.filter { (0xE000...0xF8FF).contains($0.value) }.count
                        let lenOK: Bool = {
                            if scalars.isEmpty { return b.isEmpty }   // 空输入解出空串是对的
                            let a = Double(scalars.count), b2 = Double(expected.unicodeScalars.count)
                            guard b2 > 0 else { return true }
                            return a / b2 >= 1.0 / 3.0 && a / b2 <= 3.0
                        }()
                        if !lenOK || puaCount > 0 || swiftFFFD > javaFFFD * 2 + 5 {
                            failures.append(esc("""
                            [\(c.name)] decodedExplicitBig5 结构异常（\(c.note)）
                              swiftLen=\(scalars.count) javaLen=\(expected.unicodeScalars.count)
                              swiftFFFD=\(swiftFFFD) javaFFFD=\(javaFFFD) PUA=\(puaCount) [\(describePUA(swift))]
                              Java : \(expected)
                              Swift: \(swift)
                            """))
                        } else {
                            big5MapDifferences += 1
                        }
                        continue
                    }

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
        XCTAssertGreaterThanOrEqual(standardUtf8Comparisons, 200,
                                    "标准 UTF-8 解码对照应覆盖全部样本（≥200 条）")
        // Big5 码表差异是**已登记的已知差异**（README 6B-13），全部 240 条样本都会命中
        // （`decodedExplicitBig5` 对每条用例都做，多数样本用 Big5 解出来的本来就是乱码）。
        // 这里锁「必须全部走结构判定通过」：任一条结构异常（空串 / 残留 PUA / 替换字符占比 >60%）
        // 都会被计入 failures 并在上面 XCTFail，所以这个计数只作留痕。
        XCTAssertGreaterThan(big5MapDifferences, 100,
                             "Big5 结构判定覆盖数异常（\(big5MapDifferences)），"
                             + "说明对照没有真正跑起来")

        if !failures.isEmpty {
            XCTFail("解码链 golden 不一致 \(failures.count)/\(comparisons)：\n"
                    + failures.prefix(15).joined(separator: "\n"))
        }
    }

    // MARK: - 4) 解码链优先级（独立于 golden 的结构性断言，锁定 Kotlin 顺序）

    /// Kotlin `ResponseBody.text(encode)` 的优先级：explicit > Content-Type > getHtmlEncode。
    ///
    /// 关于「无 meta 无头」这一级：**不能想当然认为检测器会把任意 GBK 字节认出 GB 系**。
    /// ICU4J 的启发式打分对「字节很少」的输入会给 Big5/EUC-KR/EUC-JP/GB18030 同分（各 10），
    /// 并按识别器列表的并列规则取 `Big5`。这一点已用真实 ICU4J（golden 侧的
    /// `EncodingDetectGolden.getEncode`）实测确认：12 字节的 `中文测试内容`（GBK）
    /// → `Big5`、conf=10；只有到 ~180 字节的成篇中文才稳定给出 `GB18030`、conf=100。
    /// 本用例因此分别用「短样本」和「长样本」锁定这两段真实行为，而不是假设一个并不存在的
    /// 「短样本也能认出 GBK」。
    func testDecodePriorityMatchesKotlin() {
        // 短样本：12 字节 GBK「中文测试内容」。
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

        // 两者皆无时走 getHtmlEncode。短样本下 ICU4J 的并列规则给 Big5（见方法头注释），
        // 因此这里锁定的是「与 Kotlin 完全一致」，而不是「认出中文」。
        XCTAssertEqual(CharsetDetector.detect(gbkBytes), "Big5",
                       "短 GBK 样本按 ICU4J 并列规则应判 Big5（与 Java golden 一致）")
        // 检测器路径：解码结果必须等于「用检测出的 charset 直接解码」。而且整体必须
        // **非 nil 且非空**——即便字节在 Big5 里非法，也应走 U+FFFD 替换语义产出乱码串，
        // 绝不能因为解码失败而返回空/nil（那会让上层误判编码不可用）。
        let c = JsNetTextDecoder.decode(bytes: gbkBytes, explicitCharset: nil, contentTypeHeader: nil)
        XCTAssertFalse(c.isEmpty, "无 meta 无头时应走检测器路径并产出结果，不能为空")
        XCTAssertEqual(c, JsNetTextDecoder.decode(Data(gbkBytes), charsetName: "Big5") ?? "",
                       "无 meta 无头时应走检测器路径，且其结果与直接用检测出的 Big5 解码一致")

        // 长样本：187 字节成篇 GBK 中文，ICU4J 给出 GB18030/conf=100（与 golden 的
        // gbk-chinese-3 完全相同），此时检测器路径才必须解出正确中文。
        let longGbk = Self.gbkChinesePassage3
        XCTAssertEqual(CharsetDetector.detect(longGbk), "GB18030",
                       "长 GBK 样本应被 ICU4J 判为 GB18030（与 Java golden 一致）")
        let longDecoded = JsNetTextDecoder.decode(bytes: longGbk, explicitCharset: nil,
                                                  contentTypeHeader: nil)
        // 该段落首行是「第七十七章 剑鸣」，用它做可读性判据（此前误用了不在本段里的「他的」）。
        XCTAssertTrue(longDecoded.hasPrefix("第七十七章"),
                      "长 GBK 样本经检测器解码后应还原出可读中文，实际=\(longDecoded.prefix(16))")

        // explicit 指向「不匹配的编码」时必须照用（不回落检测器），与 Java
        // `new String(bytes, charset)` 的替换字符语义一致。
        let d = JsNetTextDecoder.decode(bytes: gbkBytes, explicitCharset: "ISO-8859-1",
                                        contentTypeHeader: nil)
        XCTAssertNotEqual(d, "中文测试内容", "explicit 指定 ISO-8859-1 时不应回落检测器拿到正确中文")
        XCTAssertEqual(d.count, gbkBytes.count, "ISO-8859-1 是单字节编码，字符数应等于字节数")
    }

    /// golden 语料 `gbk-chinese-3` 的原始字节（187 字节 GBK 成篇中文），
    /// ICU4J 判 `GB18030`/conf=100。硬编码以保证跨平台确定。
    static let gbkChinesePassage3: [UInt8] = [
        0xB5, 0xDA, 0xC6, 0xDF, 0xCA, 0xAE, 0xC6, 0xDF, 0xD5, 0xC2, 0x20, 0xBD, 0xA3, 0xC3, 0xF9, 0x0A,
        0xBD, 0xA3, 0xB9, 0xE2, 0xC8, 0xE7, 0xC1, 0xB7, 0xA3, 0xAC, 0xC6, 0xC6, 0xBF, 0xD5, 0xB6, 0xF8,
        0xD6, 0xC1, 0xA1, 0xA3, 0xC2, 0xFA, 0xD7, 0xF9, 0xBD, 0xE4, 0xBE, 0xEA, 0xA3, 0xAC, 0xCE, 0xA8,
        0xD3, 0xD0, 0xCB, 0xFB, 0xD2, 0xC0, 0xBE, 0xC9, 0xB6, 0xCB, 0xD7, 0xF8, 0xB2, 0xBB, 0xB6, 0xAF,
        0xA3, 0xAC, 0xB6, 0xCB, 0xC6, 0xF0, 0xB2, 0xE8, 0xD5, 0xBD, 0xC7, 0xE1, 0xC7, 0xE1, 0xC3, 0xF2,
        0xC1, 0xCB, 0xD2, 0xBB, 0xBF, 0xDA, 0xA1, 0xA3, 0x0A, 0xA1, 0xB0, 0xD5, 0xE2, 0xD2, 0xBB, 0xBD,
        0xA3, 0xA3, 0xAC, 0xCE, 0xD2, 0xD2, 0xD1, 0xBE, 0xAD, 0xB5, 0xC8, 0xC1, 0xCB, 0xBA, 0xDC, 0xB6,
        0xE0, 0xC4, 0xEA, 0xA1, 0xA3, 0xA1, 0xB1, 0x0A, 0xE9, 0xDC, 0xCD, 0xE2, 0xB5, 0xC4, 0xD3, 0xEA,
        0xBA, 0xF6, 0xC8, 0xBB, 0xCD, 0xA3, 0xC1, 0xCB, 0xA3, 0xAC, 0xD4, 0xC2, 0xB9, 0xE2, 0xD2, 0xBB,
        0xB4, 0xE7, 0xD2, 0xBB, 0xB4, 0xE7, 0xB5, 0xD8, 0xC2, 0xFE, 0xBD, 0xF8, 0xCD, 0xA5, 0xD4, 0xBA,
        0xA3, 0xAC, 0xD5, 0xD5, 0xD4, 0xDA, 0xC1, 0xBD, 0xC8, 0xCB, 0xD6, 0xAE, 0xBC, 0xE4, 0xB5, 0xC4,
        0xC7, 0xE0, 0xCA, 0xAF, 0xB0, 0xE5, 0xC9, 0xCF, 0xA1, 0xA3, 0x0A,
    ]

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
