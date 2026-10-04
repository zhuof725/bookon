//
//  CharsetDetector.swift
//  LegadoBookSource
//
//  第 6 步 6B：ICU4J CharsetDetector 的完整 Swift 移植（检测算法逐行对应）。
//
//  对应 Java/Kotlin：
//   - app/src/main/java/io/legado/app/lib/icu4j/CharsetDetector.java
//   - app/src/main/java/io/legado/app/lib/icu4j/CharsetRecog_*.java（全部识别器）
//   - app/src/main/java/io/legado/app/utils/EncodingDetect.kt（getEncode 调用方）
//
//  语义要点（与 ICU4J 一致，未简化成 if-else 猜测）：
//   - 每个识别器独立打分（confidence 0-100），detectAll 收集所有 >0 的结果；
//   - 按 confidence 降序排列；confidence 相同者，识别器列表靠后者优先
//     （Java 为 Collections.sort 升序 + reverse，稳定排序翻转后即此顺序）；
//   - 无任何匹配时 Java detect() 返回 null，Kotlin 侧以 "UTF-8" 兜底。
//

import Foundation

/// 字符集检测器（legado EncodingDetect 使用的 ICU4J 检测器移植）。
///
/// 与 Kotlin `EncodingDetect.getEncode(bytes)` 行为一致：
/// `detect()` 的结果若为 nil 则返回 "UTF-8"（Kotlin `match?.name ?: "UTF-8"`）。
///
/// 对应 Java：`CharsetDetector().setText(bytes).detect()`
/// 对应 Kotlin：`io.legado.app.utils.EncodingDetect.getEncode`
public struct CharsetDetector {

    /// 一次检测的结果（字符集名 + 置信度），对应 Java `CharsetMatch` 的
    /// `getName()` / `getConfidence()`。用于 golden 逐条比对（字符集名与置信度都要一致）。
    public struct Detection: Equatable {
        /// 检测出的字符集名（Java `CharsetMatch.getName()`，如 "UTF-8"/"GB18030"）。
        public let name: String
        /// 匹配置信度，0-100（Java `CharsetMatch.getConfidence()`）。
        public let confidence: Int
        /// 语言（Java `CharsetMatch.getLanguage()`，无语言时为 ""）。
        public let language: String

        public init(name: String, confidence: Int, language: String) {
            self.name = name
            self.confidence = confidence
            self.language = language
        }
    }

    /// 检测字节数据的字符集，返回字符集名（如 "UTF-8" / "GB18030" / "Big5" / "EUC-KR" / "Shift_JIS" / "ISO-8859-1"）。
    ///
    /// - Parameter bytes: 原始响应字节（未做任何预处理）。
    /// - Returns: 字符集名；无匹配时返回 "UTF-8"（与 Kotlin 兜底一致）。
    public static func detect(_ bytes: [UInt8]) -> String {
        let engine = CharsetDetectorEngine(bytes: bytes)
        return engine.detect()?.name ?? "UTF-8"
    }

    /// 返回所有置信度 > 0 的候选字符集名，按置信度降序（并列时列表靠后者优先）。
    ///
    /// 对应 Java `CharsetDetector.detectAll()`。
    public static func detectAll(_ bytes: [UInt8]) -> [String] {
        let engine = CharsetDetectorEngine(bytes: bytes)
        return engine.detectAll().map { $0.name }
    }

    /// 返回检测到的首选匹配（含置信度）；无匹配时返回 nil（**不做** "UTF-8" 兜底，
    /// 以便调用方区分「真的检测到 UTF-8」与「检测器无结论」，与 Java `detect()` 语义一致）。
    ///
    /// 对应 Java `CharsetDetector().setText(bytes).detect()`。
    public static func detectMatch(_ bytes: [UInt8]) -> Detection? {
        let engine = CharsetDetectorEngine(bytes: bytes)
        guard let m = engine.detect() else { return nil }
        return Detection(name: m.name, confidence: m.confidence, language: m.language)
    }

    /// 返回全部置信度 > 0 的候选（含置信度），顺序与 `detectAll` 一致（置信度降序，
    /// 并列时识别器列表靠后者优先）。对应 Java `CharsetDetector.detectAll()`。
    public static func detectAllMatches(_ bytes: [UInt8]) -> [Detection] {
        let engine = CharsetDetectorEngine(bytes: bytes)
        return engine.detectAll().map {
            Detection(name: $0.name, confidence: $0.confidence, language: $0.language)
        }
    }
}

/// 检测引擎（对应 Java CharsetDetector 实例；Swift 侧为内部引用类型以承载可变状态）。
final class CharsetDetectorEngine {

    /// Java `kBufSize = 8000`：输入与统计缓冲上限。
    static let kBufSize = 8000

    /// Java `fRawInput` / `fRawLength`：原始输入（mbcs / UTF-8 / Unicode 识别器直接使用）。
    let rawInput: [UInt8]

    /// Java `fInputBytes`：标记剥离（MungeInput）后的输入缓冲。
    var inputBytes = [UInt8](repeating: 0, count: CharsetDetectorEngine.kBufSize)

    /// Java `fInputLen`：inputBytes 的有效长度。
    var inputLen = 0

    /// Java `fByteStats`：输入字节统计（0-255 出现次数）。
    var byteStats = [Int](repeating: 0, count: 256)

    /// Java `fC1Bytes`：是否出现 C1 控制区字节（0x80-0x9F）。
    var c1Bytes = false

    /// Java `fStripTags`：是否剥离 HTML 标记（legado 默认不开启，保留实现以忠实移植）。
    var stripTags = false

    /// Java `fDeclaredEncoding`：声明编码（legado 未使用，保留字段）。
    var declaredEncoding: String?

    init(bytes: [UInt8]) {
        rawInput = bytes
    }

    /// 对应 Java `detect()`：返回最佳匹配（置信度最高），无匹配返回 nil。
    func detect() -> CharsetMatch? {
        let matches = detectAll()
        return matches.first
    }

    /// 对应 Java `detectAll()`：收集所有置信度 > 0 的匹配并按序排列。
    func detectAll() -> [CharsetMatch] {
        mungeInput()

        var matches: [CharsetMatch] = []
        let recognizers = CharsetDetectorEngine.allRecognizers
        for (index, info) in recognizers.enumerated() {
            // Java: active = fEnabledRecognizers == null ? isDefaultEnabled : ...
            // legado 不调用 setDetectableCharset，恒为默认值。
            if info.defaultEnabled {
                if let m = info.recognizer.match(self, index: index) {
                    matches.append(m)
                }
            }
        }

        // Java: Collections.sort(升序,稳定) + Collections.reverse → 并列时列表靠后者优先。
        let sorted = matches.sorted { a, b in
            if a.confidence != b.confidence {
                return a.confidence > b.confidence
            }
            return a.index > b.index
        }
        return sorted
    }

    /// 对应 Java `MungeInput()`：标记剥离 + 字节统计。
    private func mungeInput() {
        var srcIndex = 0
        var dstIndex = 0
        var inMarkup = false
        var openTags = 0
        var badTags = 0

        if stripTags {
            while srcIndex < rawInput.count && dstIndex < inputBytes.count {
                let b = rawInput[srcIndex]
                if b == 0x3C { // '<'
                    if inMarkup {
                        badTags += 1
                    }
                    inMarkup = true
                    openTags += 1
                }
                if !inMarkup {
                    inputBytes[dstIndex] = b
                    dstIndex += 1
                }
                if b == 0x3E { // '>'
                    inMarkup = false
                }
                srcIndex += 1
            }
            inputLen = dstIndex
        }

        // Java: openTags < 5 || openTags/5 < badTags || (fInputLen < 100 && fRawLength > 600)
        // 时放弃剥离，直接复制原始输入（此为 Java 的整数除法语义）。
        if openTags < 5 || openTags / 5 < badTags || (inputLen < 100 && rawInput.count > 600) {
            let limit = min(rawInput.count, CharsetDetectorEngine.kBufSize)
            var i = 0
            while i < limit {
                inputBytes[i] = rawInput[i]
                i += 1
            }
            inputLen = i
        }

        byteStats = [Int](repeating: 0, count: 256)
        var i = 0
        while i < inputLen {
            byteStats[Int(inputBytes[i])] += 1
            i += 1
        }

        c1Bytes = false
        for v in 0x80...0x9F {
            if byteStats[v] != 0 {
                c1Bytes = true
                break
            }
        }
    }

    /// 识别器列表（与 Java ALL_CS_RECOGNIZERS 的加入顺序逐一对应，并列决胜依赖此顺序）。
    private static let allRecognizers: [(recognizer: CharsetRecognizer, defaultEnabled: Bool)] = [
        (CharsetRecogUTF8(), true),
        (CharsetRecogUTF16BE(), true),
        (CharsetRecogUTF16LE(), true),
        (CharsetRecogUTF32BE(), true),
        (CharsetRecogUTF32LE(), true),

        (CharsetRecogSJIS(), true),
        (CharsetRecog2022JP(), true),
        (CharsetRecog2022CN(), true),
        (CharsetRecog2022KR(), true),
        (CharsetRecogGB18030(), true),
        (CharsetRecogEUCJP(), true),
        (CharsetRecogEUCKR(), true),
        (CharsetRecogBig5(), true),

        (CharsetRecog8859_1(), true),
        (CharsetRecog8859_2(), true),
        (CharsetRecog8859_5RU(), true),
        (CharsetRecog8859_6AR(), true),
        (CharsetRecog8859_7EL(), true),
        (CharsetRecog8859_8IHE(), true),
        (CharsetRecog8859_8HE(), true),
        (CharsetRecogWindows1251(), true),
        (CharsetRecogWindows1256(), true),
        (CharsetRecogKOI8R(), true),
        (CharsetRecog8859_9TR(), true),

        // IBM 420/424 默认禁用（与 Java isDefaultEnabled=false 一致）
        (CharsetRecogIBM424HE_RTL(), false),
        (CharsetRecogIBM424HE_LTR(), false),
        (CharsetRecogIBM420AR_RTL(), false),
        (CharsetRecogIBM420AR_LTR(), false),
    ]
}