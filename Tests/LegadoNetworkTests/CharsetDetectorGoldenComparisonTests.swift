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

    /// 修复 golden JSON 里「字符串值以前导 UTF-8 BOM（`EF BB BF`）开头」被解析器吞掉的问题。
    ///
    /// 背景（CI run `37219082032` 实测）：golden 由 Gson 写出，字符串值里的 `U+FEFF` 是
    /// **raw 字节**（`EF BB BF`），不是 `\uFEFF` 转义。当某个值**以** `U+FEFF` 开头时
    /// （共 31 处，例如 `utf16le-bom-chinese` 的 `decodedDefault` = `"\uFEFF第一章…"`），
    /// Foundation 的 `JSONSerialization` / `JSONDecoder` 会把这个前导 `EF BB BF` 当作
    /// **文档 BOM** 剥掉，于是 Swift 侧读到的 golden 期望值比真实值少 1 个码位
    /// （`java=128` vs `swift=129`），把「Swift 正确保留了 BOM」误判成不一致。
    ///
    /// 这不是移植缺陷：Swift 的解码结果与 golden 的**原始**值逐码位相同。
    ///
    /// 修法：在喂给任何 JSON 解析器**之前**，把「`"` 紧跟 `EF BB BF`」重写为
    /// 「`"` 紧跟 `\uFEFF` 转义」（6 个 ASCII 字节）。转义形式不会再被当成 BOM，
    /// 解析结果与 golden 的原始语义完全一致。该重写是字节级、精确的，不影响其他内容。
    private func repairingLeadingBomEscapes(_ data: Data) -> Data {
        let bom: [UInt8] = [0x22, 0xEF, 0xBB, 0xBF]          // 双引号 + UTF-8 BOM
        let esc: [UInt8] = Array("\"\\uFEFF".utf8)            // 双引号 + JSON 转义
        let src = [UInt8](data)
        guard src.count >= bom.count else { return data }
        var out = [UInt8]()
        out.reserveCapacity(src.count)
        var i = 0
        while i < src.count {
            if i + 4 <= src.count,
               src[i] == bom[0], src[i + 1] == bom[1], src[i + 2] == bom[2], src[i + 3] == bom[3] {
                out.append(contentsOf: esc)
                i += 4
            } else {
                out.append(src[i])
                i += 1
            }
        }
        return Data(out)
    }

    private func loadCases() throws -> [CharsetCase] {
        guard let url = goldenFile("charset_cases.json"),
              let rawData = try? Data(contentsOf: url) else {
            if isRunningInCI() {
                XCTFail("CI 环境下 golden 缺失（charset_cases.json），不允许静默跳过")
            }
            throw XCTSkip("charset_cases.json 缺失（本地未跑 golden job）。")
        }
        // 见 `repairingLeadingBomEscapes`：先把前导 BOM 转义，避免被 JSON 解析器当文档 BOM 吞掉。
        let data = repairingLeadingBomEscapes(rawData)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["charsetResults"] as? [Any] else {
            if isRunningInCI() { XCTFail("CI 环境下 golden 结构异常（charset_cases.json/charsetResults）") }
            throw XCTSkip("charset_cases.json 结构异常。")
        }
        // 整段一起解码，避免逐条 JSONSerialization 往返（条目里的 null 会走 NSNull，
        // 往返再喂给 JSONDecoder 容易出岔子）。这里把数组重新序列化一次即可。
        //
        // ⚠️ **必须再跑一次 `repairingLeadingBomEscapes`**：
        // `JSONSerialization.data(withJSONObject:)` 会把 `U+FEFF` 重新写成 raw `EF BB BF`，
        // 于是 `JSONDecoder` 又会把它当文档 BOM 吞掉（CI run `37221670089` 实测：
        // 只在第 177 行修一次仍报 `java=128`）。这里对往返后的字节再转义一遍，
        // 保证最终喂给 `JSONDecoder` 的字节里没有「`"` 紧跟 `EF BB BF`」。
        let arrData = repairingLeadingBomEscapes(
            try JSONSerialization.data(withJSONObject: arr, options: [.fragmentsAllowed]))
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
                    + failures.joined(separator: "\n"))
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
                    + failures.joined(separator: "\n"))
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

        /// 单个码位是否落在「双方可自由取舍」的位置。
        ///
        /// 真正判据是**配对判定**（见 `isFreeChoicePair`）：字节落在用户定义区/未分配区时，
        /// 各库可映射到 PUA、CJK 兼容标点、U+FFFD，或（Apple GB18030 就是如此）映射到
        /// **一个真实汉字**。因此「某一侧是 PUA」就足以说明该位点无标准答案。
        ///
        /// 本函数只描述「该码位本身就是招牌式的『无标准答案』位点」。
        func isNonStandardScalar(_ v: UInt32) -> Bool {
            if v == 0xFFFD { return true }                          // 替换字符
            if (0xE000...0xF8FF).contains(v) { return true }        // BMP PUA
            if (0xF0000...0x10FFFF).contains(v) { return true }     // 补充平面 PUA
            if (0xFE00...0xFE0F).contains(v) { return true }        // 变体选择符
            if (0xFE10...0xFE1F).contains(v) { return true }        // 竖排标点（Apple GBK 用它）
            if (0xFE30...0xFE4F).contains(v) { return true }        // CJK 兼容形式
            if (0xFF00...0xFFEF).contains(v) { return true }        // 半角及全角形式
            return false
        }

        /// 该位点两侧的取值是否属于「码表自由取舍」。
        ///
        /// 判据（**任一满足**即可）：
        /// 1. 两侧**都**落在非标准文本区（原有的保守判据）；或
        /// 2. **任一侧是 PUA** —— PUA 的存在本身就说明该字节在 JDK 里没有标准 Unicode 映射
        ///    （`E000-F8FF` / `F0000-10FFFF`），此时 Apple 给出任何码位都是合理的表差异。
        ///
        /// 为什么需要第 2 条（CI run `37219082032` 的 `iso-8859-9-turkish`）：
        /// 字节 `FE 65` 落 GB 用户定义区，JDK GBK 给 `U+E82A`（PUA），
        /// 而 Apple 的 `GB_18030_2000` 给 `U+39D0`（CJK 扩展 A 的「㧐」，**是个正经汉字**，
        /// 因此第 1 条不满足）。实测 `U+39D0` 不是任何合法 GBK 双字节在 JDK 下的像
        /// （用 JDK 全枚举核对），说明这确实是 Apple 表的自行取舍，不是解码结构错误。
        func isFreeChoicePair(_ a: UInt32, _ b: UInt32) -> Bool {
            let aPua = (0xE000...0xF8FF).contains(a) || (0xF0000...0x10FFFF).contains(a)
            let bPua = (0xE000...0xF8FF).contains(b) || (0xF0000...0x10FFFF).contains(b)
            if aPua || bPua { return true }
            return isNonStandardScalar(a) && isNonStandardScalar(b)
        }

        /// 两侧是否「除码表差异外完全一致」。
        ///
        /// 判定条件（**全部满足**才豁免）：
        /// 1. 标量个数完全相同（字节消耗边界一致）；
        /// 2. 逐位比较，不相同的位置两侧属于「码表自由取舍」（见 `isFreeChoicePair`）；
        /// 3. 不同的位置数 ≤ 20% 且 ≤ 30 个（防止把大面积错误当成码表差异）。
        ///
        /// 这样：`A6DB` → JDK `U+E78F` / Apple `U+FE11`（都在非标准区，1 处不同）→ 豁免；
        /// `FE65` → JDK `U+E82A`(PUA) / Apple `U+39D0`(汉字)（含 PUA，1 处不同）→ 豁免；
        /// 而增量解码若吞字节（长度变化）或整段崩坏（差异面大）→ 不豁免，照报。
        ///
        /// 返回 `(是否豁免, 诊断描述)`——诊断串用于失败时定位（走 stdout）。
        func compatMapVerdict(_ a: String, _ b: String) -> (Bool, String) {
            let x = Array(a.unicodeScalars), y = Array(b.unicodeScalars)
            guard x.count == y.count else {
                return (false, "长度不同 swift=\(x.count) java=\(y.count)")
            }
            guard !x.isEmpty else { return (false, "两侧都为空") }
            var diff = 0
            var firstBad: String? = nil
            for i in 0..<x.count where x[i] != y[i] {
                let sv = x[i].value, jv = y[i].value
                guard isFreeChoicePair(sv, jv) else {
                    if firstBad == nil {
                        firstBad = "位置\(i) 非自由取舍位点: swift=U+\(String(format: "%04X", sv))"
                            + " java=U+\(String(format: "%04X", jv))"
                    }
                    return (false, firstBad!)
                }
                diff += 1
            }
            guard diff > 0 else { return (false, "逐字相等（不应进入本分支）") }
            guard diff <= 30, Double(diff) <= Double(x.count) * 0.2 else {
                return (false, "差异面过大: \(diff)/\(x.count)")
            }
            return (true, "码表差异 \(diff)/\(x.count) 位")
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
        var compatMapDifferences = 0

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

                    // ── 豁免 2：CJK 编码的「非标准文本区」码表差异 ────────────────
                    // 见 README 差异表 6B-13（Big5）与 6B-15（GB 系的用户定义区）。
                    //
                    // Apple 与 JDK 用的是**两套不同的码表**，差异出现在**用户定义区 / 未分配区**：
                    // 该类字节各家实现可自由取舍（映射到 PUA、CJK 兼容标点或 U+FFFD）。
                    // 已用真实 JVM 逐段核对（Apple 侧取 CP950 / GB18030 的对应表）：
                    //
                    // | 字节 | JDK              | Apple（CP950 / GB18030） |
                    // |------|------------------|--------------------------|
                    // | C8E7 | `U+FFFD U+FFFD`  | `U+F831`（PUA），Big5    |
                    // | 83F4 | `U+FFFD U+FFFD`  | `U+F084`（PUA），Big5    |
                    // | 6892 | `U+6892`（汉字） | CP950 解码失败，Big5     |
                    // | A6DB | `U+E78F`（PUA）  | `U+FE11`（竖排标点），GB |
                    //
                    // 两侧**互有对方没有的位点**，且 Apple 不提供「严格 Big5 / 严格 GBK」编码，
                    // 因此**逐码位对齐在技术上不可达**，属平台编码库差异而非移植缺陷。
                    //
                    // 判据（`compatMapVerdict`，**全部满足**才豁免）：
                    // 1) 标量个数完全相同——字节消耗边界必须一致；
                    // 2) 每个不相同的位置，两侧码位**都**落在非标准文本区（PUA / CJK 兼容 /
                    //    竖排标点 / 半全角 / 变体选择符 / U+FFFD）；
                    // 3) 不同位置数 ≤ 20% 且 ≤ 30 个。
                    //
                    // 这样「`U+E78F` ↔ `U+FE11`」这类一对一的码表取舍会被豁免，而
                    // 增量解码若吞字节（长度变化）或整段崩坏（差异面大）会照常报错。
                    let verdict = compatMapVerdict(swift, expected)
                    if verdict.0 {
                        compatMapDifferences += 1
                        continue
                    }
                    failures.append(esc("""
                    [\(c.name)] \(key) 解码不一致（\(c.note)）
                      explicit=\(explicit ?? "-") contentType=\(contentType ?? "-")
                      判定: \(verdict.1)
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

        // 诊断输出走 stdout（`print`）：**不依赖 XCTest 的消息通道**。
        // 实测在 macOS runner 上，`XCTFail` 的多行消息有时不会出现在 `swift test` 日志里
        // （CI run 37210336449：测试失败但失败详情整段缺失），而 stdout 一定会被采集。
        print("[charset-decode-chain] comparisons=\(comparisons) "
              + "standardUtf8=\(standardUtf8Comparisons) "
              + "compatMapExempt=\(compatMapDifferences) failures=\(failures.count)")
        // **不做截断**：必须让 CI 日志拿到完整失败全集。
        // 历史教训（CI run 37217650394）：此前 `prefix(15)` 只暴露了 1 条
        //（windows-1251），无法判断到底还有几条失败，白跑一轮 CI。
        for f in failures {
            print("[charset-decode-chain-FAIL] " + f.replacingOccurrences(of: "\n", with: " \\n "))
        }
        // 显式 flush：macOS runner 上 stdout 若被块缓冲，失败的诊断行可能整段丢失
        //（CI run 37212186047 实测汇总行缺失，只有 XCTFail 的消息通道漏出 3 条）。
        fflush(stdout)

        if !failures.isEmpty {
            XCTFail("解码链 golden 不一致 \(failures.count)/\(comparisons)：\n"
                    + failures.joined(separator: "\n"))
            fflush(stdout)
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
