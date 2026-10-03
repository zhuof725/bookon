//
//  CharsetRecogUnicode.swift
//  LegadoBookSource
//
//  第 6 步 6B：ICU4J CharsetRecog_Unicode（UTF-16/UTF-32 各端序）的 Swift 移植。
//
//  对应 Java：app/src/main/java/io/legado/app/lib/icu4j/CharsetRecog_Unicode.java
//

import Foundation

/// 从两个字节合成 16 位码元（Java `codeUnit16FromBytes(hi, lo)`）。
private func codeUnit16FromBytes(_ hi: UInt8, _ lo: UInt8) -> Int {
    return (Int(hi) << 8) | Int(lo)
}

/// UTF-16 置信度调整（Java `adjustConfidence`）：
/// NUL 是反证（扣 10 分），普通可见字符（0x20-0xFF 或换行）加 10 分。
private func adjustConfidence(_ codeUnit: Int, _ confidence: Int) -> Int {
    var c = confidence
    if codeUnit == 0 {
        c -= 10
    } else if (codeUnit >= 0x20 && codeUnit <= 0xFF) || codeUnit == 0x0A {
        c += 10
    }
    if c < 0 {
        c = 0
    } else if c > 100 {
        c = 100
    }
    return c
}

/// UTF-16BE 识别器（ICU4J `CharsetRecog_UTF_16_BE`）。
final class CharsetRecogUTF16BE: CharsetRecognizer {
    var name: String { "UTF-16BE" }

    func match(_ det: CharsetDetectorEngine, index: Int) -> CharsetMatch? {
        let input = det.rawInput
        var confidence = 10
        let bytesToCheck = min(input.count, 30)
        var charIndex = 0
        while charIndex < bytesToCheck - 1 {
            let codeUnit = codeUnit16FromBytes(input[charIndex], input[charIndex + 1])
            if charIndex == 0 && codeUnit == 0xFEFF {
                confidence = 100
                break
            }
            confidence = adjustConfidence(codeUnit, confidence)
            if confidence == 0 || confidence == 100 {
                break
            }
            charIndex += 2
        }
        if bytesToCheck < 4 && confidence < 100 {
            confidence = 0
        }
        return confidence > 0
            ? CharsetMatch(confidence: confidence, name: name, language: language, index: index)
            : nil
    }
}

/// UTF-16LE 识别器（ICU4J `CharsetRecog_UTF_16_LE`）。
final class CharsetRecogUTF16LE: CharsetRecognizer {
    var name: String { "UTF-16LE" }

    func match(_ det: CharsetDetectorEngine, index: Int) -> CharsetMatch? {
        let input = det.rawInput
        var confidence = 10
        let bytesToCheck = min(input.count, 30)
        var charIndex = 0
        while charIndex < bytesToCheck - 1 {
            let codeUnit = codeUnit16FromBytes(input[charIndex + 1], input[charIndex])
            if charIndex == 0 && codeUnit == 0xFEFF {
                confidence = 100
                break
            }
            confidence = adjustConfidence(codeUnit, confidence)
            if confidence == 0 || confidence == 100 {
                break
            }
            charIndex += 2
        }
        if bytesToCheck < 4 && confidence < 100 {
            confidence = 0
        }
        return confidence > 0
            ? CharsetMatch(confidence: confidence, name: name, language: language, index: index)
            : nil
    }
}

/// UTF-32 识别器公共逻辑（ICU4J `CharsetRecog_UTF_32`），端序由子类决定。
private class CharsetRecogUTF32: CharsetRecognizer {
    var name: String { "" }

    /// Java `getChar(input, index)`：取第 index 个 4 字节码点。
    func getChar(_ input: [UInt8], _ index: Int) -> Int {
        return 0
    }

    func match(_ det: CharsetDetectorEngine, index: Int) -> CharsetMatch? {
        let input = det.rawInput
        let limit = (det.rawInput.count / 4) * 4
        var numValid = 0
        var numInvalid = 0
        var hasBOM = false
        var confidence = 0

        if limit == 0 {
            return nil
        }
        if getChar(input, 0) == 0x0000FEFF {
            hasBOM = true
        }

        var i = 0
        while i < limit {
            let ch = getChar(input, i)
            if ch < 0 || ch >= 0x10FFFF || (ch >= 0xD800 && ch <= 0xDFFF) {
                numInvalid += 1
            } else {
                numValid += 1
            }
            i += 4
        }

        // 置信度合计（与 Java 逐分支一致）
        if hasBOM && numInvalid == 0 {
            confidence = 100
        } else if hasBOM && numValid > numInvalid * 10 {
            confidence = 80
        } else if numValid > 3 && numInvalid == 0 {
            confidence = 100
        } else if numValid > 0 && numInvalid == 0 {
            confidence = 80
        } else if numValid > numInvalid * 10 {
            // 可能是损坏的 UTF-32 数据：有效序列不太可能纯靠巧合出现
            confidence = 25
        }

        return confidence == 0
            ? nil
            : CharsetMatch(confidence: confidence, name: name, language: language, index: index)
    }
}

/// UTF-32BE 识别器（ICU4J `CharsetRecog_UTF_32_BE`）。
final class CharsetRecogUTF32BE: CharsetRecogUTF32 {
    override var name: String { "UTF-32BE" }
    override func getChar(_ input: [UInt8], _ index: Int) -> Int {
        return (Int(input[index]) << 24) | (Int(input[index + 1]) << 16) |
            (Int(input[index + 2]) << 8) | Int(input[index + 3])
    }
}

/// UTF-32LE 识别器（ICU4J `CharsetRecog_UTF_32_LE`）。
final class CharsetRecogUTF32LE: CharsetRecogUTF32 {
    override var name: String { "UTF-32LE" }
    override func getChar(_ input: [UInt8], _ index: Int) -> Int {
        return (Int(input[index + 3]) << 24) | (Int(input[index + 2]) << 16) |
            (Int(input[index + 1]) << 8) | Int(input[index])
    }
}