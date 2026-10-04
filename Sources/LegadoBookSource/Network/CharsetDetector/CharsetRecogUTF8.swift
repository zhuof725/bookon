//
//  CharsetRecogUTF8.swift
//  LegadoBookSource
//
//  第 6 步 6B：ICU4J CharsetRecog_UTF8 的 Swift 移植。
//
//  对应 Java：app/src/main/java/io/legado/app/lib/icu4j/CharsetRecog_UTF8.java
//

import Foundation

/// UTF-8 识别器（ICU4J `CharsetRecog_UTF8`）。
///
/// 扫描原始输入（fRawInput）：统计有效/无效多字节序列数，按 BOM 与
/// 有效/无效比例给出置信度；完全无高字节时给 15（比 UTF-16 的 10 高，见 Java 注释）。
final class CharsetRecogUTF8: CharsetRecognizer {
    var name: String { "UTF-8" }

    func match(_ det: CharsetDetectorEngine, index: Int) -> CharsetMatch? {
        var hasBOM = false
        var numValid = 0
        var numInvalid = 0
        let input = det.rawInput
        var trailBytes = 0
        var confidence = 0

        if det.rawInput.count >= 3 &&
            input[0] == 0xEF && input[1] == 0xBB && input[2] == 0xBF {
            hasBOM = true
        }

        // 扫描多字节序列
        var i = 0
        while i < det.rawInput.count {
            let b = Int(input[i])
            if b & 0x80 == 0 {
                i += 1
                continue // ASCII
            }
            // 高位置位：判定序列长度
            if b & 0x0E0 == 0x0C0 {
                trailBytes = 1
            } else if b & 0x0F0 == 0x0E0 {
                trailBytes = 2
            } else if b & 0x0F8 == 0x0F0 {
                trailBytes = 3
            } else {
                numInvalid += 1
                i += 1
                continue
            }
            // 校验后续字节
            i += 1
            while true {
                if i >= det.rawInput.count {
                    break
                }
                let tb = input[i]
                if tb & 0xC0 != 0x80 {
                    numInvalid += 1
                    i += 1
                    break
                }
                trailBytes -= 1
                i += 1
                if trailBytes == 0 {
                    numValid += 1
                    break
                }
            }
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
        } else if numValid == 0 && numInvalid == 0 {
            // 纯 ASCII：置信度必须 > 10（比 UTF-16 接受 ASCII 的 10 更可信）
            confidence = 15
        } else if numValid > numInvalid * 10 {
            // 可能是损坏的 UTF-8：有效序列不太可能纯靠巧合出现
            confidence = 25
        }
        return confidence == 0
            ? nil
            : CharsetMatch(confidence: confidence, name: name, language: language, index: index)
    }
}