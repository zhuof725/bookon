//
//  CharsetRecogSBCS.swift
//  LegadoBookSource
//
//  第 6 步 6B：ICU4J CharsetRecog_sbcs（单字节字符集 + IBM420/IBM424）的 Swift 移植。
//
//  对应 Java：app/src/main/java/io/legado/app/lib/icu4j/CharsetRecog_sbcs.java
//
//  语义要点（与 ICU4J 一致）：
//   - 单字节编码本身区分度低，靠 N-gram 语言统计（3 字节 gram）打分；
//   - byteMap 把每个输入字节映射到「语言意义上的字符」（0 表示忽略）；
//   - ngramList 每表恰好 64 项（生成脚本已断言），search 用 Java 的固定步长二分；
//   - 置信度：命中率 > 0.33 → 98，否则 (int)(命中率 * 300.0)；
//   - IBM424 用 0x40 作空格符；IBM420 额外做阿拉伯文整形还原（unshapeMap + alef）。
//

import Foundation

/// N-gram 解析器（Java `CharsetRecog_sbcs.NGramParser`）。
///
/// 逐词条对应 Java：
///  - parse(det, spaceChar)：空格符可配（IBM424/420 用 0x40）；
///  - parseCharacters：byteMap[b] == 0 的字节跳过；连续相同空格只计一次；
///  - addByte：3 字节滚动 gram（N_GRAM_MASK = 0xFFFFFF）并查表；
///  - 收尾补一个空格符 gram，避免句末截断偏置；
///  - 命中率 > 0.33 直接给 98（Java 注释：避免出现 135 这类过高的值）。
class NGramParser {
    /// Java `N_GRAM_MASK = 0xFFFFFF`。
    static let nGramMask: Int64 = 0xFFFFFF

    /// Java `byteIndex`：输入字节游标。
    var byteIndex = 0
    /// Java `ngram`：滚动三字节 gram。
    private var ngram: Int64 = 0
    /// Java `ngramList`：64 项升序 gram 表。
    private let ngramList: [Int]
    /// Java `byteMap`：输入字节 → 语言字符映射（0 = 忽略）。
    var byteMap: [UInt8]
    /// Java `ngramCount` / `hitCount`。
    private var ngramCount = 0
    private var hitCount = 0
    /// Java `spaceChar`。
    var spaceChar: UInt8 = 0x20

    init(ngramList: [Int], byteMap: [UInt8]) {
        self.ngramList = ngramList
        self.byteMap = byteMap
        ngram = 0
        ngramCount = 0
        hitCount = 0
    }

    /// Java `search(int[], int)`：对**恰好 64 项**的升序表做固定步长二分查找。
    final func search(_ table: [Int], _ value: Int64) -> Int {
        var index = 0
        if Int64(table[index + 32]) <= value { index += 32 }
        if Int64(table[index + 16]) <= value { index += 16 }
        if Int64(table[index + 8]) <= value { index += 8 }
        if Int64(table[index + 4]) <= value { index += 4 }
        if Int64(table[index + 2]) <= value { index += 2 }
        if Int64(table[index + 1]) <= value { index += 1 }
        if Int64(table[index]) > value { index -= 1 }
        if index < 0 || Int64(table[index]) != value {
            return -1
        }
        return index
    }

    /// Java `lookup(int)`：计数并查表。
    final func lookup(_ thisNgram: Int64) {
        ngramCount += 1
        if search(ngramList, thisNgram) >= 0 {
            hitCount += 1
        }
    }

    /// Java `addByte(int)`：滚动 gram（& 0xFFFFFF）并查表。
    final func addByte(_ b: Int) {
        ngram = ((ngram << 8) + Int64(b & 0xFF)) & NGramParser.nGramMask
        lookup(ngram)
    }

    /// Java `nextByte(CharsetDetector)`：从**标记剥离后的输入**取字节。
    func nextByte(_ det: CharsetDetectorEngine) -> Int {
        if byteIndex >= det.inputLen {
            return -1
        }
        let b = Int(det.inputBytes[byteIndex])
        byteIndex += 1
        return b & 0xFF
    }

    /// Java `parseCharacters(CharsetDetector)`：逐字节映射并喂给 addByte。
    func parseCharacters(_ det: CharsetDetectorEngine) {
        var b = nextByte(det)
        var ignoreSpace = false
        while b >= 0 {
            let mb = byteMap[Int(b)]
            if mb != 0 {
                // 连续相同空格只计一次（TODO 注释：0x20 未必是所有字符集的空格）。
                if !(mb == spaceChar && ignoreSpace) {
                    addByte(Int(mb))
                }
                ignoreSpace = (mb == spaceChar)
            }
            b = nextByte(det)
        }
    }

    /// Java `parse(CharsetDetector, byte)`：解析并折算置信度。
    func parse(_ det: CharsetDetectorEngine, spaceChar: UInt8) -> Int {
        self.spaceChar = spaceChar
        parseCharacters(det)

        // 收尾补一个空格 gram（缓冲可能恰在词中间结束）。
        addByte(Int(spaceChar))

        let rawPercent = Double(hitCount) / Double(ngramCount)

        // Java 注释：防置信度出现 135 这类越界值。
        if rawPercent > 0.33 {
            return 98
        }
        return Int(rawPercent * 300.0)
    }
}

/// IBM420 专用 N-gram 解析器（Java `CharsetRecog_sbcs.NGramParser_IBM420`）。
///
/// 阿拉伯文整形还原：字节先经 unshapeMap 还原成「字型无关」的基础字母，
/// 其中 lam-alef 合字（0xB2-0xB5 / 0xB8-0xB9）拆成 alef + 下一字母，
/// 用 0xB1 占位并在主字节处理后补喂 alef 的映射。
final class NGramParserIBM420: NGramParser {

    /// Java `alef`：最近读到的 lam-alef 合字拆出的 alef 字节（0 表示无）。
    private var alef: UInt8 = 0x00

    /// Java `isLamAlef(byte)`：lam-alef 合字字节 → alef 基准字节，否则 0。
    private func isLamAlef(_ b: UInt8) -> UInt8 {
        if b == 0xB2 || b == 0xB3 {
            return 0x47
        } else if b == 0xB4 || b == 0xB5 {
            return 0x49
        } else if b == 0xB8 || b == 0xB9 {
            return 0x56
        }
        return 0x00
    }

    /// Java `nextByte(CharsetDetector)` 覆写：
    ///  - 字节 0 或越界 → -1（结束）；
    ///  - lam-alef 合字 → 0xB1 占位（alef 拆出后由 parseCharacters 补喂）；
    ///  - 其它 → unshapeMap[b]。
    override func nextByte(_ det: CharsetDetectorEngine) -> Int {
        if byteIndex >= det.inputLen || det.inputBytes[byteIndex] == 0 {
            return -1
        }
        let raw = det.inputBytes[byteIndex]
        alef = isLamAlef(raw)
        let next: Int
        if alef != 0x00 {
            next = 0xB1 & 0xFF
        } else {
            next = Int(CharsetTables.unshapeMap[Int(raw)] & 0xFF)
        }
        byteIndex += 1
        return next
    }

    /// Java `parseCharacters` 覆写：主字节处理后若拆出了 alef，再补喂 alef 的映射。
    override func parseCharacters(_ det: CharsetDetectorEngine) {
        var b = nextByte(det)
        var ignoreSpace = false
        while b >= 0 {
            var mb = byteMap[Int(b)]
            if mb != 0 {
                if !(mb == spaceChar && ignoreSpace) {
                    addByte(Int(mb))
                }
                ignoreSpace = (mb == spaceChar)
            }
            if alef != 0x00 {
                mb = byteMap[Int(alef) & 0xFF]
                if mb != 0 {
                    if !(mb == spaceChar && ignoreSpace) {
                        addByte(Int(mb))
                    }
                    ignoreSpace = (mb == spaceChar)
                }
            }
            b = nextByte(det)
        }
    }
}

/// SBCS 识别器基类（Java `CharsetRecog_sbcs`）：提供 match 基础设施。
protocol CharsetRecogSBCS: CharsetRecognizer {}

extension CharsetRecogSBCS {
    /// Java `match(det, ngrams, byteMap)`（空格符 0x20）。
    func matchNGrams(_ det: CharsetDetectorEngine, _ ngrams: [Int], _ byteMap: [UInt8]) -> Int {
        let parser = NGramParser(ngramList: ngrams, byteMap: byteMap)
        return parser.parse(det, spaceChar: 0x20)
    }

    /// Java `match(det, ngrams, byteMap, spaceChar)`。
    func matchNGrams(_ det: CharsetDetectorEngine, _ ngrams: [Int], _ byteMap: [UInt8], spaceChar: UInt8) -> Int {
        let parser = NGramParser(ngramList: ngrams, byteMap: byteMap)
        return parser.parse(det, spaceChar: spaceChar)
    }

    /// Java `matchIBM420(det, ngrams, byteMap, spaceChar)`。
    func matchIBM420(_ det: CharsetDetectorEngine, _ ngrams: [Int], _ byteMap: [UInt8], spaceChar: UInt8) -> Int {
        let parser = NGramParserIBM420(ngramList: ngrams, byteMap: byteMap)
        return parser.parse(det, spaceChar: spaceChar)
    }
}

/// ISO-8859-1 识别器（Java `CharsetRecog_sbcs.CharsetRecog_8859_1`）。
///
/// 多语言 ngram 表各算一次置信度，取严格大于当前最优者（平局保留先出现语言，
/// 与 Java 逐项 `if (confidence > bestConfidenceSoFar)` 一致）；名字在
/// 出现 C1 控制字节时改为 windows-1252。
final class CharsetRecog8859_1: CharsetRecogSBCS {
    var name: String { "ISO-8859-1" }
    var language: String { "" }

    func match(_ det: CharsetDetectorEngine, index: Int) -> CharsetMatch? {
        let finalName = det.c1Bytes ? "windows-1252" : "ISO-8859-1"
        var bestConfidenceSoFar = -1
        var lang: String?
        for ngl in CharsetTables.ngrams8859_1 {
            let confidence = matchNGrams(det, ngl.ngrams, CharsetTables.byteMap8859_1)
            if confidence > bestConfidenceSoFar {
                bestConfidenceSoFar = confidence
                lang = ngl.lang
            }
        }
        return bestConfidenceSoFar <= 0
            ? nil
            : CharsetMatch(confidence: bestConfidenceSoFar, name: finalName, language: lang ?? "", index: index)
    }
}

/// ISO-8859-2 识别器（Java `CharsetRecog_sbcs.CharsetRecog_8859_2`）。
final class CharsetRecog8859_2: CharsetRecogSBCS {
    var name: String { "ISO-8859-2" }
    var language: String { "" }

    func match(_ det: CharsetDetectorEngine, index: Int) -> CharsetMatch? {
        let finalName = det.c1Bytes ? "windows-1250" : "ISO-8859-2"
        var bestConfidenceSoFar = -1
        var lang: String?
        for ngl in CharsetTables.ngrams8859_2 {
            let confidence = matchNGrams(det, ngl.ngrams, CharsetTables.byteMap8859_2)
            if confidence > bestConfidenceSoFar {
                bestConfidenceSoFar = confidence
                lang = ngl.lang
            }
        }
        return bestConfidenceSoFar <= 0
            ? nil
            : CharsetMatch(confidence: bestConfidenceSoFar, name: finalName, language: lang ?? "", index: index)
    }
}

/// ISO-8859-5（俄语）识别器（Java `CharsetRecog_sbcs.CharsetRecog_8859_5_ru`）。
final class CharsetRecog8859_5RU: CharsetRecogSBCS {
    var name: String { "ISO-8859-5" }
    var language: String { "ru" }

    func match(_ det: CharsetDetectorEngine, index: Int) -> CharsetMatch? {
        let confidence = matchNGrams(det, CharsetTables.ngrams8859_5_ru, CharsetTables.byteMap8859_5)
        return confidence == 0
            ? nil
            : CharsetMatch(confidence: confidence, name: name, language: language, index: index)
    }
}

/// ISO-8859-6（阿拉伯语）识别器（Java `CharsetRecog_sbcs.CharsetRecog_8859_6_ar`）。
final class CharsetRecog8859_6AR: CharsetRecogSBCS {
    var name: String { "ISO-8859-6" }
    var language: String { "ar" }

    func match(_ det: CharsetDetectorEngine, index: Int) -> CharsetMatch? {
        let confidence = matchNGrams(det, CharsetTables.ngrams8859_6_ar, CharsetTables.byteMap8859_6)
        return confidence == 0
            ? nil
            : CharsetMatch(confidence: confidence, name: name, language: language, index: index)
    }
}

/// ISO-8859-7（希腊语）识别器（Java `CharsetRecog_sbcs.CharsetRecog_8859_7_el`）。
final class CharsetRecog8859_7EL: CharsetRecogSBCS {
    var name: String { "ISO-8859-7" }
    var language: String { "el" }

    func match(_ det: CharsetDetectorEngine, index: Int) -> CharsetMatch? {
        let finalName = det.c1Bytes ? "windows-1253" : "ISO-8859-7"
        let confidence = matchNGrams(det, CharsetTables.ngrams8859_7_el, CharsetTables.byteMap8859_7)
        return confidence == 0
            ? nil
            : CharsetMatch(confidence: confidence, name: finalName, language: language, index: index)
    }
}

/// ISO-8859-8-I（希伯来语，逻辑序）识别器（Java `CharsetRecog_sbcs.CharsetRecog_8859_8_I_he`）。
final class CharsetRecog8859_8IHE: CharsetRecogSBCS {
    var name: String { "ISO-8859-8-I" }
    var language: String { "he" }

    func match(_ det: CharsetDetectorEngine, index: Int) -> CharsetMatch? {
        let finalName = det.c1Bytes ? "windows-1255" : "ISO-8859-8-I"
        let confidence = matchNGrams(det, CharsetTables.ngrams8859_8_I_he, CharsetTables.byteMap8859_8)
        return confidence == 0
            ? nil
            : CharsetMatch(confidence: confidence, name: finalName, language: language, index: index)
    }
}

/// ISO-8859-8（希伯来语，视觉序）识别器（Java `CharsetRecog_sbcs.CharsetRecog_8859_8_he`）。
final class CharsetRecog8859_8HE: CharsetRecogSBCS {
    var name: String { "ISO-8859-8" }
    var language: String { "he" }

    func match(_ det: CharsetDetectorEngine, index: Int) -> CharsetMatch? {
        let finalName = det.c1Bytes ? "windows-1255" : "ISO-8859-8"
        let confidence = matchNGrams(det, CharsetTables.ngrams8859_8_he, CharsetTables.byteMap8859_8)
        return confidence == 0
            ? nil
            : CharsetMatch(confidence: confidence, name: finalName, language: language, index: index)
    }
}

/// ISO-8859-9（土耳其语）识别器（Java `CharsetRecog_sbcs.CharsetRecog_8859_9_tr`）。
final class CharsetRecog8859_9TR: CharsetRecogSBCS {
    var name: String { "ISO-8859-9" }
    var language: String { "tr" }

    func match(_ det: CharsetDetectorEngine, index: Int) -> CharsetMatch? {
        let finalName = det.c1Bytes ? "windows-1254" : "ISO-8859-9"
        let confidence = matchNGrams(det, CharsetTables.ngrams8859_9_tr, CharsetTables.byteMap8859_9)
        return confidence == 0
            ? nil
            : CharsetMatch(confidence: confidence, name: finalName, language: language, index: index)
    }
}

/// windows-1251（俄语）识别器（Java `CharsetRecog_sbcs.CharsetRecog_windows_1251`）。
final class CharsetRecogWindows1251: CharsetRecogSBCS {
    var name: String { "windows-1251" }
    var language: String { "ru" }

    func match(_ det: CharsetDetectorEngine, index: Int) -> CharsetMatch? {
        let confidence = matchNGrams(det, CharsetTables.ngrams1251, CharsetTables.byteMap1251)
        return confidence == 0
            ? nil
            : CharsetMatch(confidence: confidence, name: name, language: language, index: index)
    }
}

/// windows-1256（阿拉伯语）识别器（Java `CharsetRecog_sbcs.CharsetRecog_windows_1256`）。
final class CharsetRecogWindows1256: CharsetRecogSBCS {
    var name: String { "windows-1256" }
    var language: String { "ar" }

    func match(_ det: CharsetDetectorEngine, index: Int) -> CharsetMatch? {
        let confidence = matchNGrams(det, CharsetTables.ngrams1256, CharsetTables.byteMap1256)
        return confidence == 0
            ? nil
            : CharsetMatch(confidence: confidence, name: name, language: language, index: index)
    }
}

/// KOI8-R（俄语）识别器（Java `CharsetRecog_sbcs.CharsetRecog_KOI8_R`）。
final class CharsetRecogKOI8R: CharsetRecogSBCS {
    var name: String { "KOI8-R" }
    var language: String { "ru" }

    func match(_ det: CharsetDetectorEngine, index: Int) -> CharsetMatch? {
        let confidence = matchNGrams(det, CharsetTables.ngramsKOI8R, CharsetTables.byteMapKOI8R)
        return confidence == 0
            ? nil
            : CharsetMatch(confidence: confidence, name: name, language: language, index: index)
    }
}

/// IBM-424（希伯来语）识别器基类（Java `CharsetRecog_sbcs.CharsetRecog_IBM424_he`）。
/// 空格符为 0x40（IBM 码页的空格位）；协议一致性由子类声明。
private class CharsetRecogIBM424 {
    var name: String { "" }
    var language: String { "he" }
}

/// IBM-424 RTL 识别器（Java `CharsetRecog_sbcs.CharsetRecog_IBM424_he_rtl`）。
final class CharsetRecogIBM424HE_RTL: CharsetRecogIBM424, CharsetRecogSBCS {
    override var name: String { "IBM424_rtl" }

    func match(_ det: CharsetDetectorEngine, index: Int) -> CharsetMatch? {
        let confidence = matchNGrams(det, CharsetTables.ngramsIBM424_rtl, CharsetTables.byteMapIBM424, spaceChar: 0x40)
        return confidence == 0
            ? nil
            : CharsetMatch(confidence: confidence, name: name, language: language, index: index)
    }
}

/// IBM-424 LTR 识别器（Java `CharsetRecog_sbcs.CharsetRecog_IBM424_he_ltr`）。
final class CharsetRecogIBM424HE_LTR: CharsetRecogIBM424, CharsetRecogSBCS {
    override var name: String { "IBM424_ltr" }

    func match(_ det: CharsetDetectorEngine, index: Int) -> CharsetMatch? {
        let confidence = matchNGrams(det, CharsetTables.ngramsIBM424_ltr, CharsetTables.byteMapIBM424, spaceChar: 0x40)
        return confidence == 0
            ? nil
            : CharsetMatch(confidence: confidence, name: name, language: language, index: index)
    }
}

/// IBM-420（阿拉伯语）识别器基类（Java `CharsetRecog_sbcs.CharsetRecog_IBM420_ar`）。
/// 协议一致性由子类声明。
private class CharsetRecogIBM420 {
    var name: String { "" }
    var language: String { "ar" }
}

/// IBM-420 RTL 识别器（Java `CharsetRecog_sbcs.CharsetRecog_IBM420_ar_rtl`）。
final class CharsetRecogIBM420AR_RTL: CharsetRecogIBM420, CharsetRecogSBCS {
    override var name: String { "IBM420_rtl" }

    func match(_ det: CharsetDetectorEngine, index: Int) -> CharsetMatch? {
        let confidence = matchIBM420(det, CharsetTables.ngramsIBM420_rtl, CharsetTables.byteMapIBM420, spaceChar: 0x40)
        return confidence == 0
            ? nil
            : CharsetMatch(confidence: confidence, name: name, language: language, index: index)
    }
}

/// IBM-420 LTR 识别器（Java `CharsetRecog_sbcs.CharsetRecog_IBM420_ar_ltr`）。
final class CharsetRecogIBM420AR_LTR: CharsetRecogIBM420, CharsetRecogSBCS {
    override var name: String { "IBM420_ltr" }

    func match(_ det: CharsetDetectorEngine, index: Int) -> CharsetMatch? {
        let confidence = matchIBM420(det, CharsetTables.ngramsIBM420_ltr, CharsetTables.byteMapIBM420, spaceChar: 0x40)
        return confidence == 0
            ? nil
            : CharsetMatch(confidence: confidence, name: name, language: language, index: index)
    }
}