//
//  CharsetRecogMBCS.swift
//  LegadoBookSource
//
//  第 6 步 6B：ICU4J CharsetRecog_mbcs（多字节字符集：Shift_JIS / Big5 /
//  EUC-JP / EUC-KR / GB18030）的 Swift 移植。
//
//  对应 Java：app/src/main/java/io/legado/app/lib/icu4j/CharsetRecog_mbcs.java
//
//  语义要点（与 ICU4J 一致）：
//   - 检测基于「字节是否合乎编码方案」+「常用字频率统计」；
//   - iteratedChar 按各编码的规则从**原始输入**（fRawInput）逐字符取字节；
//   - 置信度计算逐分支照搬 Java（含 `(float) doubleByteCharCount / 4` 的
//     float 除法语义，见 matchCommon 内注释）。
//

import Foundation

/// 迭代字符缓冲（Java `CharsetRecog_mbcs.iteratedChar`）。
///
/// `charValue` 为 1-4 个原始字节拼成的整数值；用 Int64 承载，取值上界
/// 不超过 0xFFFFFFFF（Java 为 32 位 int，本移植所有 OR 运算结果一致）。
final class IteratedChar {
    /// 1-4 字节原始数据（Java `charValue`）。
    var charValue: Int64 = 0
    /// 下一个待读字节下标（Java `nextIndex`）。
    var nextIndex = 0
    /// 本字符是否非法（Java `error`）。
    var error = false
    /// 是否已读尽输入（Java `done`）。
    var done = false

    func reset() {
        charValue = 0
        nextIndex = 0
        error = false
        done = false
    }

    /// Java `nextByte(CharsetDetector)`：取下一个字节（0-255），到末尾返回 -1 并置 done。
    func nextByte(_ det: CharsetDetectorEngine) -> Int {
        if nextIndex >= det.rawInput.count {
            done = true
            return -1
        }
        let b = Int(det.rawInput[nextIndex])
        nextIndex += 1
        return b & 0xFF
    }
}

/// MBCS 识别器基类（Java `CharsetRecog_mbcs`）。
protocol CharsetRecogMBCS: CharsetRecognizer {
    /// Java `nextChar(iteratedChar, CharsetDetector)`：按本编码规则取下一个字符。
    func nextChar(_ it: IteratedChar, _ det: CharsetDetectorEngine) -> Bool
}

extension CharsetRecogMBCS {
    /// 对 `commonChars` 表做二分查找（Java `Arrays.binarySearch`，表须升序）。
    /// 命中返回 >= 0 的下标，未命中返回负数。
    func binarySearchCommon(_ table: [Int], _ value: Int64) -> Int {
        var low = 0
        var high = table.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let midVal = Int64(table[mid])
            if midVal < value {
                low = mid + 1
            } else if midVal > value {
                high = mid - 1
            } else {
                return mid
            }
        }
        return -(low + 1)
    }

    /// Java `CharsetRecog_mbcs.match(CharsetDetector, int[] commonChars)`。
    ///
    /// 逐分支照搬：
    ///  - badCharCount >= 2 且 badCharCount * 5 >= doubleByteCharCount 时提前退出；
    ///  - 双字节字符很少且无非法字节时给 10（纯 ASCII 小样本给 0）；
    ///  - 非法字节太多给 0；
    ///  - 无统计表：30 + doubleByteCharCount - 20 * badCharCount（上限 100）；
    ///  - 有统计表：`log(commonCharCount + 1) * (90 / log(dbc / 4)) + 10`（上限 100）。
    ///    Java 用 `(float) doubleByteCharCount / 4` 先做 float 除法再转 double，
    ///    Swift 用 `Double(Float(...) / 4.0)` 复刻同一 IEEE 结果。
    func matchCommon(_ det: CharsetDetectorEngine, _ commonChars: [Int]?) -> Int {
        var singleByteCharCount = 0
        var doubleByteCharCount = 0
        var commonCharCount = 0
        var badCharCount = 0
        var totalCharCount = 0
        var confidence = 0
        let iter = IteratedChar()

        detectBlock: do {
            iter.reset()
            while nextChar(iter, det) {
                totalCharCount += 1
                if iter.error {
                    badCharCount += 1
                } else {
                    let cv = iter.charValue & 0xFFFFFFFF
                    if cv <= 0xFF {
                        singleByteCharCount += 1
                    } else {
                        doubleByteCharCount += 1
                        if let commonChars = commonChars {
                            // NOTE: 假定 commonChars 中无 4 字节常用字（与 Java 注释一致）。
                            if binarySearchCommon(commonChars, cv) >= 0 {
                                commonCharCount += 1
                            }
                        }
                    }
                }
                if badCharCount >= 2 && badCharCount * 5 >= doubleByteCharCount {
                    // 数据明显不符合编码方案，提前退出。
                    break detectBlock
                }
            }

            if doubleByteCharCount <= 10 && badCharCount == 0 {
                // 多字节字符不多：若完全没有多字节字符且总字符 < 10，数据不足给 0；
                // 否则可能是 ASCII/ISO 文件，不兼容但也不算错，给 10。
                if doubleByteCharCount == 0 && totalCharCount < 10 {
                    confidence = 0
                } else {
                    confidence = 10
                }
                break detectBlock
            }

            if doubleByteCharCount < 20 * badCharCount {
                confidence = 0
                break detectBlock
            }

            if commonChars == nil {
                // 无频率统计：纯按多字节字符数量评估。
                confidence = 30 + doubleByteCharCount - 20 * badCharCount
                if confidence > 100 {
                    confidence = 100
                }
            } else {
                // 常用字频率统计（与 Java 逐运算一致，float→double 语义已复刻）。
                let maxVal = log(Double(Float(doubleByteCharCount) / 4.0))
                let scaleFactor = 90.0 / maxVal
                confidence = Int(log(Double(commonCharCount + 1)) * scaleFactor + 10)
                confidence = min(confidence, 100)
            }
        }

        return confidence
    }
}

/// Shift_JIS 识别器（Java `CharsetRecog_mbcs.CharsetRecog_sjis`）。
final class CharsetRecogSJIS: CharsetRecogMBCS {
    var name: String { "Shift_JIS" }
    var language: String { "ja" }

    func nextChar(_ it: IteratedChar, _ det: CharsetDetectorEngine) -> Bool {
        it.error = false
        let firstByte = it.nextByte(det)
        it.charValue = Int64(firstByte)
        if firstByte < 0 {
            return false
        }

        if firstByte <= 0x7F || (firstByte > 0xA0 && firstByte <= 0xDF) {
            // 单字节字符（ASCII / 半角片假名区）。
            return true
        }

        let secondByte = it.nextByte(det)
        if secondByte < 0 {
            return false
        }
        it.charValue = (it.charValue << 8) | Int64(secondByte)
        if !((secondByte >= 0x40 && secondByte <= 0x7F) || (secondByte >= 0x80 && secondByte <= 0xFF)) {
            // 非法第二字节。
            it.error = true
        }
        return true
    }

    func match(_ det: CharsetDetectorEngine, index: Int) -> CharsetMatch? {
        let confidence = matchCommon(det, CharsetTables.sjisCommonChars)
        return confidence == 0
            ? nil
            : CharsetMatch(confidence: confidence, name: name, language: language, index: index)
    }
}

/// Big5 识别器（Java `CharsetRecog_mbcs.CharsetRecog_big5`）。
final class CharsetRecogBig5: CharsetRecogMBCS {
    var name: String { "Big5" }
    var language: String { "zh" }

    func nextChar(_ it: IteratedChar, _ det: CharsetDetectorEngine) -> Bool {
        it.error = false
        let firstByte = it.nextByte(det)
        it.charValue = Int64(firstByte)
        if firstByte < 0 {
            return false
        }

        if firstByte <= 0x7F || firstByte == 0xFF {
            // 单字节字符（Java 把 0xFF 也当单字节）。
            return true
        }

        let secondByte = it.nextByte(det)
        if secondByte < 0 {
            return false
        }
        it.charValue = (it.charValue << 8) | Int64(secondByte)

        if secondByte < 0x40 || secondByte == 0x7F || secondByte == 0xFF {
            it.error = true
        }
        return true
    }

    func match(_ det: CharsetDetectorEngine, index: Int) -> CharsetMatch? {
        let confidence = matchCommon(det, CharsetTables.big5CommonChars)
        return confidence == 0
            ? nil
            : CharsetMatch(confidence: confidence, name: name, language: language, index: index)
    }
}

/// EUC 家族识别器基类（Java `CharsetRecog_mbcs.CharsetRecog_euc`）。
///
/// nextChar 的取值规则：
///  - firstByte <= 0x8D：单字节；
///  - firstByte 0xA1-0xFE：双字节（第二字节 < 0xA1 判非法）；
///  - firstByte 0x8E：Code Set 2（EUC-JP 半角片假名，第二字节 < 0xA1 判非法）；
///  - firstByte 0x8F：Code Set 3（EUC-JP JIS X 0212 三字节，第三字节 < 0xA1 判非法）；
///  - firstByte 0x90-0xA0 落入以上区间之外时不判非法（与 Java 一致，见 Java 源码）。
/// EUC-JP/EUC-KR 共享的 EUC 识别器（Java `CharsetRecog_mbcs.CharsetRecog_euc`）。
/// 抽象基类：仅被子类继承，不直接参与识别（internal 而非 private——Swift 中子类
/// 访问级别不能高于基类，而 EUC-JP/EUC-KR 子类需被 allRecognizers 内部使用）。
class CharsetRecogEUC: CharsetRecogMBCS {
    var name: String { "" }
    var language: String { "" }

    /// 各 EUC 子类的常用字表（Java 子类各自静态 commonChars；EUC-KR 用韩文表）。
    var commonChars: [Int] { CharsetTables.eucJPCommonChars }

    func nextChar(_ it: IteratedChar, _ det: CharsetDetectorEngine) -> Bool {
        it.error = false
        let firstByte = it.nextByte(det)
        it.charValue = Int64(firstByte)
        if firstByte < 0 {
            // 输入已读尽。
            it.done = true
            return false
        }

        if firstByte <= 0x8D {
            // 单字节字符。
            return true
        }

        let secondByte = it.nextByte(det)
        it.charValue = (it.charValue << 8) | Int64(secondByte)

        // ⚠️ 下面所有「已确定字符类型」的出口都必须返回 `!it.done`，不能直接 `return true`：
        // 对应 Java 源码里它们都是 `break buildChar`，最终统一走到方法末尾的
        // `return (!it.done)`。若读第二个字节时越界，`nextByte` 会置 `it.done = true`，
        // Java 因此返回 false（该字符不计入 totalCharCount / badCharCount），而早退的
        // `return true` 会让它被计入——曾导致极短输入下 EUC-JP / EUC-KR 少一个
        // confidence=10 的候选（golden 不一致）。
        if firstByte >= 0xA1 && firstByte <= 0xFE {
            // 双字节字符。
            if secondByte < 0xA1 {
                it.error = true
            }
            return !it.done
        }
        if firstByte == 0x8E {
            // Code Set 2。
            if secondByte < 0xA1 {
                it.error = true
            }
            return !it.done
        }
        if firstByte == 0x8F {
            // Code Set 3：三字节字符。
            let thirdByte = it.nextByte(det)
            it.charValue = (it.charValue << 8) | Int64(thirdByte)
            if thirdByte < 0xA1 {
                it.error = true
            }
        }
        return !it.done
    }

    func match(_ det: CharsetDetectorEngine, index: Int) -> CharsetMatch? {
        let confidence = matchCommon(det, commonChars)
        return confidence == 0
            ? nil
            : CharsetMatch(confidence: confidence, name: name, language: language, index: index)
    }
}

/// EUC-JP 识别器（Java `CharsetRecog_mbcs.CharsetRecog_euc.CharsetRecog_euc_jp`）。
final class CharsetRecogEUCJP: CharsetRecogEUC {
    override var name: String { "EUC-JP" }
    override var language: String { "ja" }
}

/// EUC-KR 识别器（Java `CharsetRecog_mbcs.CharsetRecog_euc.CharsetRecog_euc_kr`）。
final class CharsetRecogEUCKR: CharsetRecogEUC {
    override var name: String { "EUC-KR" }
    override var language: String { "ko" }
    override var commonChars: [Int] { CharsetTables.eucKRCommonChars }
}

/// GB18030 识别器（Java `CharsetRecog_mbcs.CharsetRecog_gb_18030`）。
///
/// 注意：Java 源码中双字节第二字节条件写作 `secondByte >= 80`（十进制 80 = 0x50），
/// 与上游 ICU 的 `>= 0x80` 不同；合并 `[0x40,0x7E] ∪ [0x50,0xFE]` 后唯一的行为差异是
/// **0x7F 被判为合法双字节第二字节**（上游判非法）。本移植照搬 legado 行为
/// （golden 以 legado Java 源码为准）。
final class CharsetRecogGB18030: CharsetRecogMBCS {
    var name: String { "GB18030" }
    var language: String { "zh" }

    func nextChar(_ it: IteratedChar, _ det: CharsetDetectorEngine) -> Bool {
        it.error = false
        let firstByte = it.nextByte(det)
        it.charValue = Int64(firstByte)
        if firstByte < 0 {
            it.done = true
            return false
        }

        if firstByte <= 0x80 {
            // 单字节字符。
            return !it.done
        }

        let secondByte = it.nextByte(det)
        it.charValue = (it.charValue << 8) | Int64(secondByte)

        // ⚠️ 同 EUC：Java 这些出口都是 `break buildChar` → 方法末尾统一 `return (!it.done)`。
        // 读次/三/四字节越界时 `nextByte` 会置 `it.done = true`，必须让它们返回 false，
        // 否则该字符会被错误计入 totalCharCount / doubleByteCharCount。
        if firstByte >= 0x81 && firstByte <= 0xFE {
            // 双字节字符（legado 写法 `secondByte >= 80` 为十进制 0x50，照搬）。
            if (secondByte >= 0x40 && secondByte <= 0x7E) || (secondByte >= 0x50 && secondByte <= 0xFE) {
                return !it.done
            }

            // 四字节字符：第二字节 0x30-0x39，第三字节 0x81-0xFE，第四字节 0x30-0x39。
            if secondByte >= 0x30 && secondByte <= 0x39 {
                let thirdByte = it.nextByte(det)
                if thirdByte >= 0x81 && thirdByte <= 0xFE {
                    let fourthByte = it.nextByte(det)
                    if fourthByte >= 0x30 && fourthByte <= 0x39 {
                        it.charValue = (it.charValue << 16) | (Int64(thirdByte) << 8) | Int64(fourthByte)
                        return !it.done
                    }
                }
            }

            it.error = true
        }
        return !it.done
    }

    func match(_ det: CharsetDetectorEngine, index: Int) -> CharsetMatch? {
        let confidence = matchCommon(det, CharsetTables.gb18030CommonChars)
        return confidence == 0
            ? nil
            : CharsetMatch(confidence: confidence, name: name, language: language, index: index)
    }
}
